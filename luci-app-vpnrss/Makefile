include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vpnrss
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=findnr

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-vpnrss
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=VPN RSS Subscription Generator
  DEPENDS:=+luci-base +luci-lib-jsonc +luci-lib-nixio
  PKGARCH:=all
endef

define Package/luci-app-vpnrss/description
  Aggregate VPN nodes and generate subscriptions for Clash, Sing-box, etc.
endef

define Build/Compile
endef

define Package/luci-app-vpnrss/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/vpnrss
	$(INSTALL_DIR) $(1)/usr/share/vpnrss

	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-vpnrss))
