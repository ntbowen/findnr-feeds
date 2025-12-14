module("luci.controller.vpnrss", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/vpnrss") then
		return
	end

	entry({"admin", "services", "vpnrss"}, cbi("vpnrss/client"), _("VPN RSS"), 99).dependent = true
	
	-- Public subscription endpoint (no sysauth)
	local page = entry({"vpnrss", "subscribe"}, call("action_subscribe"), nil)
	page.sysauth = false
	page.leaf = true
end

function action_subscribe()
	local uci = require "luci.model.uci".cursor()
	local http = require "luci.http"
	local dispatcher = require "luci.dispatcher"
	local transformer = require "vpnrss.transformer"

	-- 1. Security Check: Token
	local config_token = uci:get("vpnrss", "global", "token")
	local param_token = http.formvalue("token")

	if config_token and config_token ~= "" and config_token ~= param_token then
		http.status(403, "Forbidden")
		http.write("Invalid Token")
		return
	end

	-- 2. Get Nodes
	local nodes = {}
	uci:foreach("vpnrss", "node", function(s)
		if s.enable == '1' and s.link then
			table.insert(nodes, {
				alias = s.alias or "Node",
				link = s.link
			})
		end
	end)

	if #nodes == 0 then
		http.status(200, "OK")
		http.write("No keys found.")
		return
	end

	-- 3. Transform
	local client = http.formvalue("client") or "base64"
	local result = ""
	local content_type = "text/plain"

	if client == "clash" or client == "clash_meta" then
		result = transformer.to_clash(nodes)
		content_type = "text/yaml"
	elseif client == "singbox" then
		result = transformer.to_singbox(nodes)
		content_type = "application/json"
	elseif client == "surge" then
		result = transformer.to_surge(nodes)
		content_type = "text/plain"
	else
		-- Default to base64
		result = transformer.to_base64(nodes)
		content_type = "text/plain"
	end

	http.header("Content-Type", content_type .. "; charset=utf-8")
	http.write(result)
end
