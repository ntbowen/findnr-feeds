include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-simple2fa
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=findnr

# 这一行很重要，表示这是 LuCI 的一个应用
include $(INCLUDE_DIR)/package.mk

define Package/luci-app-simple2fa
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Simple 2FA (TOTP) for Login
  # 依赖关系：oathtool 与 qrencode；并确保有 base32 可用
  DEPENDS:=+oath-toolkit +qrencode +coreutils-base32
  PKGARCH:=all
endef

define Package/luci-app-simple2fa/description
  A minimal Two-Factor Authentication plugin intercepting ucode login.
endef

# 编译环节留空，因为我们是脚本，不需要 gcc 编译
define Build/Compile
endef

# 安装环节：把 root 目录下的东西拷到固件的文件系统里
define Package/luci-app-simple2fa/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/bootstrap/js

	# 复制文件
	$(CP) ./root/* $(1)/

  # 修正可执行权限，安装到标准 cgi-bin 路径
  $(INSTALL_BIN) ./root/www/cgi/luci $(1)/www/cgi-bin/luci
endef

$(eval $(call BuildPackage,luci-app-simple2fa))
