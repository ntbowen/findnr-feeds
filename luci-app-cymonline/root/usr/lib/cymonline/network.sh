#!/bin/sh
# CymOnline Network Control Script
# Provides traffic monitoring and speed limiting via iptables + tc

. /lib/functions.sh

# Configuration
CHAIN_NAME="CYMONLINE"
MANGLE_CHAIN="CYMONLINE_MARK"

# Get interface from UCI or use defaults
get_interfaces() {
	config_load cymonline
	config_get WAN_IFACE main wan_iface "eth0"
	config_get LAN_IFACE main lan_iface "br-lan"
}

# ============================================================
# Traffic Monitoring
# ============================================================

init_traffic() {
	get_interfaces

	# Create custom chains for traffic accounting
	iptables -t mangle -N "$CHAIN_NAME" 2>/dev/null
	iptables -t mangle -F "$CHAIN_NAME"

	# Hook into FORWARD chain
	iptables -t mangle -C FORWARD -j "$CHAIN_NAME" 2>/dev/null || \
		iptables -t mangle -I FORWARD -j "$CHAIN_NAME"

	# Create marking chain for speed limits
	iptables -t mangle -N "$MANGLE_CHAIN" 2>/dev/null
	iptables -t mangle -F "$MANGLE_CHAIN"

	# Hook POSTROUTING for download (traffic going to devices)
	iptables -t mangle -C POSTROUTING -o "$LAN_IFACE" -j "$MANGLE_CHAIN" 2>/dev/null || \
		iptables -t mangle -I POSTROUTING -o "$LAN_IFACE" -j "$MANGLE_CHAIN"

	echo "Traffic monitoring initialized"
}

cleanup_traffic() {
	get_interfaces

	# Remove hooks
	iptables -t mangle -D FORWARD -j "$CHAIN_NAME" 2>/dev/null
	iptables -t mangle -D POSTROUTING -o "$LAN_IFACE" -j "$MANGLE_CHAIN" 2>/dev/null

	# Flush and delete chains
	iptables -t mangle -F "$CHAIN_NAME" 2>/dev/null
	iptables -t mangle -X "$CHAIN_NAME" 2>/dev/null
	iptables -t mangle -F "$MANGLE_CHAIN" 2>/dev/null
	iptables -t mangle -X "$MANGLE_CHAIN" 2>/dev/null

	echo "Traffic monitoring cleaned up"
}

# Add traffic counter for an IP
add_traffic_counter() {
	local ip="$1"
	# Download (to this IP)
	iptables -t mangle -C "$CHAIN_NAME" -d "$ip" -j RETURN 2>/dev/null || \
		iptables -t mangle -A "$CHAIN_NAME" -d "$ip" -j RETURN
	# Upload (from this IP)
	iptables -t mangle -C "$CHAIN_NAME" -s "$ip" -j RETURN 2>/dev/null || \
		iptables -t mangle -A "$CHAIN_NAME" -s "$ip" -j RETURN
}

# Get traffic stats for an IP (returns: rx_bytes tx_bytes rx_packets tx_packets)
get_traffic_stats() {
	local ip="$1"
	local rx_bytes=0 tx_bytes=0 rx_pkts=0 tx_pkts=0

	# Download (destination = IP)
	local dl=$(iptables -t mangle -L "$CHAIN_NAME" -v -n -x 2>/dev/null | grep -E "^\s*[0-9]+" | awk -v ip="$ip" '$9 == ip {print $2, $1}')
	if [ -n "$dl" ]; then
		rx_bytes=$(echo "$dl" | awk '{print $1}')
		rx_pkts=$(echo "$dl" | awk '{print $2}')
	fi

	# Upload (source = IP)
	local ul=$(iptables -t mangle -L "$CHAIN_NAME" -v -n -x 2>/dev/null | grep -E "^\s*[0-9]+" | awk -v ip="$ip" '$8 == ip {print $2, $1}')
	if [ -n "$ul" ]; then
		tx_bytes=$(echo "$ul" | awk '{print $1}')
		tx_pkts=$(echo "$ul" | awk '{print $2}')
	fi

	echo "$rx_bytes $tx_bytes $rx_pkts $tx_pkts"
}

# Get all traffic stats at once (returns lines of: IP RX_BYTES TX_BYTES)
get_all_stats() {
	# Get all rules from the chain
	# Column 2: bytes, Column 8: source, Column 9: destination
	iptables -t mangle -L "$CHAIN_NAME" -v -n -x 2>/dev/null | grep -E "^\s*[0-9]+" | awk '
	$9 != "0.0.0.0/0" { rx[$9] = $2 }
	$8 != "0.0.0.0/0" { tx[$8] = $2 }
	END {
		for (ip in rx) {
			print ip, rx[ip], (tx[ip] ? tx[ip] : 0)
		}
		for (ip in tx) {
			if (!(ip in rx)) {
				print ip, 0, tx[ip]
			}
		}
	}'
}

# ============================================================
# Speed Limiting (tc HTB on LAN interface)
# ============================================================

# Initialize tc qdisc on LAN interface
init_tc() {
	get_interfaces

	# Check if tc is available
	which tc >/dev/null 2>&1 || {
		echo "ERROR: tc command not found"
		return 1
	}

	# Setup tc on LAN interface (for download limiting to devices)
	tc qdisc del dev "$LAN_IFACE" root 2>/dev/null
	tc qdisc add dev "$LAN_IFACE" root handle 1: htb default 9999
	tc class add dev "$LAN_IFACE" parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit
	# Default class - unlimited
	tc class add dev "$LAN_IFACE" parent 1:1 classid 1:9999 htb rate 1000mbit ceil 1000mbit

	echo "TC qdisc initialized on $LAN_IFACE"
}

cleanup_tc() {
	get_interfaces
	tc qdisc del dev "$LAN_IFACE" root 2>/dev/null
	echo "TC qdisc cleaned up"
}

# Convert MAC to a unique mark number (range 100-65100)
mac_to_mark() {
	local mac="$1"
	# Use last 2 octets as mark (simple hash)
	local last2=$(echo "$mac" | awk -F: '{print $5$6}' | tr 'a-f' 'A-F')
	local mark=$(printf "%d" "0x$last2" 2>/dev/null)
	mark=$((mark % 65000 + 100))
	echo "$mark"
}

# Ensure tc is initialized
ensure_tc_ready() {
	get_interfaces
	# Check if our qdisc exists
	tc qdisc show dev "$LAN_IFACE" 2>/dev/null | grep -q "htb 1:" || {
		echo "Initializing tc..."
		init_tc
	}
}

# Set speed limit for a MAC address
# Usage: set_limit <MAC> <UP_KBPS> <DOWN_KBPS>
set_limit() {
	local mac="$1"
	local up_kbps="$2"
	local down_kbps="$3"

	get_interfaces
	
	# Validate MAC
	[ -z "$mac" ] && {
		echo "ERROR: MAC address required"
		return 1
	}

	# Convert MAC to uppercase
	mac=$(echo "$mac" | tr 'a-f' 'A-F')

	# If both are 0, remove limit
	[ "$up_kbps" = "0" ] && [ "$down_kbps" = "0" ] && {
		remove_limit "$mac"
		return 0
	}

	# Ensure tc is ready
	ensure_tc_ready

	local mark=$(mac_to_mark "$mac")
	local classid=$((mark % 9000 + 10))

	echo "Setting limit for MAC=$mac mark=$mark classid=1:$classid down=${down_kbps}kbps"

	# Remove existing rules first
	remove_limit "$mac"

	# We need to find the IP for this MAC to create iptables rules
	local ip=$(cat /proc/net/arp | grep -i "$mac" | awk '{print $1}' | head -1)
	
	if [ -z "$ip" ]; then
		echo "WARNING: Cannot find IP for MAC $mac (device may be offline)"
		# Still save it - it will apply when the device comes online
	fi

	# Add tc class for download limiting
	if [ "$down_kbps" != "0" ] && [ -n "$down_kbps" ]; then
		# Create the limited class
		tc class add dev "$LAN_IFACE" parent 1:1 classid "1:$classid" htb rate "${down_kbps}kbit" ceil "${down_kbps}kbit" 2>/dev/null
		
		# Add filter by mark
		tc filter add dev "$LAN_IFACE" parent 1: protocol ip prio 1 handle "$mark" fw flowid "1:$classid" 2>/dev/null
		
		# Add iptables rule to mark packets going TO this IP
		if [ -n "$ip" ]; then
			iptables -t mangle -A "$MANGLE_CHAIN" -d "$ip" -j MARK --set-mark "$mark" 2>/dev/null
			echo "Added iptables mark rule for IP $ip -> mark $mark"
		fi
	fi

	echo "Speed limit set for $mac: down=${down_kbps}kbps (up limiting not yet implemented)"
	return 0
}

# Remove speed limit for a MAC address
remove_limit() {
	local mac="$1"
	get_interfaces

	# Convert MAC to uppercase
	mac=$(echo "$mac" | tr 'a-f' 'A-F')

	local mark=$(mac_to_mark "$mac")
	local classid=$((mark % 9000 + 10))

	echo "Removing limit for MAC=$mac mark=$mark classid=1:$classid"

	# Find the IP for this MAC
	local ip=$(cat /proc/net/arp | grep -i "$mac" | awk '{print $1}' | head -1)

	# Remove iptables rules (try with IP if found)
	if [ -n "$ip" ]; then
		while iptables -t mangle -D "$MANGLE_CHAIN" -d "$ip" -j MARK --set-mark "$mark" 2>/dev/null; do :; done
	fi

	# Also try to remove any rules with this mark
	# This handles cases where IP changed
	iptables-save -t mangle 2>/dev/null | grep "MARK --set-xmark 0x$(printf '%x' $mark)" | while read line; do
		rule=$(echo "$line" | sed 's/-A /-D /')
		eval "iptables -t mangle $rule" 2>/dev/null
	done

	# Remove tc filter and class
	tc filter del dev "$LAN_IFACE" parent 1: handle "$mark" fw 2>/dev/null
	tc class del dev "$LAN_IFACE" classid "1:$classid" 2>/dev/null

	echo "Speed limit removed for $mac"
}

# Restore all limits from UCI config
restore_limits() {
	echo "Restoring speed limits from config..."
	
	init_tc

	config_load cymonline

	restore_device_limit() {
		local cfg="$1"
		local mac limit_up limit_down

		config_get mac "$cfg" mac
		config_get limit_up "$cfg" limit_up "0"
		config_get limit_down "$cfg" limit_down "0"

		if [ -n "$mac" ]; then
			if [ "$limit_up" != "0" ] || [ "$limit_down" != "0" ]; then
				echo "Restoring limit for $mac: up=$limit_up down=$limit_down"
				set_limit "$mac" "$limit_up" "$limit_down"
			fi
		fi
	}

	config_foreach restore_device_limit device
	echo "Speed limits restored"
}

cleanup_limits() {
	cleanup_tc

	# Remove all mark rules
	get_interfaces
	iptables -t mangle -F "$MANGLE_CHAIN" 2>/dev/null
}

# Debug: show current status
show_status() {
	echo "=== Interfaces ==="
	get_interfaces
	echo "WAN: $WAN_IFACE"
	echo "LAN: $LAN_IFACE"
	
	echo ""
	echo "=== TC Qdisc ==="
	tc qdisc show dev "$LAN_IFACE" 2>/dev/null
	
	echo ""
	echo "=== TC Classes ==="
	tc class show dev "$LAN_IFACE" 2>/dev/null
	
	echo ""
	echo "=== TC Filters ==="
	tc filter show dev "$LAN_IFACE" 2>/dev/null
	
	echo ""
	echo "=== iptables MANGLE Chain ==="
	iptables -t mangle -L "$MANGLE_CHAIN" -v -n 2>/dev/null
}

# ============================================================
# Main Entry
# ============================================================

case "$1" in
	init_traffic)
		init_traffic
		;;
	cleanup_traffic)
		cleanup_traffic
		;;
	add_counter)
		add_traffic_counter "$2"
		;;
	get_stats)
		get_traffic_stats "$2"
		;;
	get_all_stats)
		get_all_stats
		;;
	init_tc)
		init_tc
		;;
	set_limit)
		set_limit "$2" "$3" "$4"
		;;
	remove_limit)
		remove_limit "$2"
		;;
	restore_limits)
		restore_limits
		;;
	cleanup_limits)
		cleanup_limits
		;;
	status)
		show_status
		;;
	*)
		echo "Usage: $0 {init_traffic|cleanup_traffic|add_counter|get_stats|init_tc|set_limit|remove_limit|restore_limits|cleanup_limits|status}"
		exit 1
		;;
esac
