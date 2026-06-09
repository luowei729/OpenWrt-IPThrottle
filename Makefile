include $(TOPDIR)/rules.mk

PKG_NAME:=iptest
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=OpenWrt IPThrottle Development Team
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/iptest
  SECTION:=net
  CATEGORY:=Network
  TITLE:=IP address throttling control for OpenWrt
  DEPENDS:=+tc +kmod-sched +kmod-sched-htb +kmod-nft-core +nftables +luci-base
  PKGARCH:=all
endef

define Package/iptest/description
  OpenWrt IPThrottle is a powerful IP address throttling plugin that provides
  fine-grained bandwidth control for network devices.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/iptest/install
	$(INSTALL_DIR) $(1)/usr/lib/iptest
	$(INSTALL_BIN) ./files/usr/lib/iptest/*.sh $(1)/usr/lib/iptest/
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/etc/config/iptest $(1)/etc/config/
	
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/iptest $(1)/etc/init.d/
	
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/iptest $(1)/usr/sbin/
	
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-iptest.json $(1)/usr/share/luci/menu.d/
	
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-iptest.json $(1)/usr/share/rpcd/acl.d/
	
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/iptest.js $(1)/www/luci-static/resources/view/
endef

$(eval $(call BuildPackage,iptest))
