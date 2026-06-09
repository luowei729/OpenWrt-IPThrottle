include $(TOPDIR)/rules.mk

PKG_NAME:=ipthrottle
PKG_VERSION:=1.0.0
PKG_RELEASE:=2
PKG_MAINTAINER:=OpenWrt IPThrottle Development Team
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/ipthrottle
  SECTION:=net
  CATEGORY:=Network
  TITLE:=IP throttling control for OpenWrt
  # 依赖说明：
  # - nftables: 用户空间工具，硬性依赖
  # - luci-base: LuCI 界面框架，硬性依赖
  # - tc: 流量控制工具，部分固件已内置或包名为 iproute2-tc，运行时检测
  # - kmod-sched/htb/nft-core: 内核模块，部分固件已内置，运行时检测
  DEPENDS:=+nftables +luci-base
  PKGARCH:=all
endef

define Package/ipthrottle/description
  IPThrottle is a powerful IP address throttling plugin for OpenWrt.
  Supports independent and shared throttling modes, IP range configuration,
  multi-WAN interfaces, protocol filtering and weekly scheduling.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/ipthrottle/install
	$(INSTALL_DIR) $(1)/usr/lib/ipthrottle
	$(INSTALL_BIN) ./files/usr/lib/ipthrottle/*.sh $(1)/usr/lib/ipthrottle/
	$(INSTALL_BIN) ./files/usr/lib/ipthrottle/ipthrottle-daemon $(1)/usr/lib/ipthrottle/
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/etc/config/ipthrottle $(1)/etc/config/
	
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/ipthrottle $(1)/etc/init.d/
	
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/ipthrottle $(1)/usr/sbin/
	
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-ipthrottle.json $(1)/usr/share/luci/menu.d/
	
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json $(1)/usr/share/rpcd/acl.d/
	
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/ipthrottle.js $(1)/www/luci-static/resources/view/
endef

$(eval $(call BuildPackage,ipthrottle))
