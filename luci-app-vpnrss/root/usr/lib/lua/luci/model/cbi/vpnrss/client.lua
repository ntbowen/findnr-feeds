m = Map("vpnrss", translate("VPN 订阅聚合"), translate("管理您的 VPN 节点并生成订阅链接。"))

-- =========================================================================
-- Global Settings
-- =========================================================================
s = m:section(NamedSection, "global", "global", translate("全局设置"))

o = s:option(Flag, "enabled", translate("启用插件"))
o.rmempty = false

o = s:option(Value, "token", translate("安全密钥 (Token)"), translate("设置密钥以保护您的订阅链接不被扫描（推荐）。"))
o.password = true
o.rmempty = false

-- Embed the status/links view
s:append(Template("vpnrss/status"))

-- =========================================================================
-- Node Management
-- =========================================================================
s = m:section(TypedSection, "node", translate("节点管理"), translate("在此添加您的 VPN 节点链接 (vmess://, vless://, trojan://, ss://)。"))
s.template = "cbi/tblsection"
s.anonymous = true
s.addremove = true
s.sortable = true

o = s:option(Flag, "enable", translate("启用"))
o.default = '1'
o.rmempty = false
o.width = "5%"

o = s:option(Value, "alias", translate("备注"), translate("给节点起个名字。"))
o.width = "20%"

o = s:option(TextValue, "link", translate("链接"), translate("粘贴完整的分享链接。"))
o.rows = 2
o.wrap = "off"
o.width = "75%"
-- Validate that it looks like a link
function o.validate(self, value)
	if value then
		value = value:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
		if (value:match("^vmess://") or value:match("^vless://") or value:match("^trojan://") or value:match("^ss://") or value:match("^hysteria2://")) then
			return value
		end
	end
	return nil, translate("链接格式无效。必须以 vmess://, vless://, trojan://, ss:// 或 hysteria2:// 开头")
end

return m
