include $(TOPDIR)/rules.mk

PKG_NAME:=ipthrottle
PKG_VERSION:=1.0.5
PKG_RELEASE:=1
PKG_MAINTAINER:=OpenWrt IPThrottle Development Team
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/ipthrottle
  SECTION:=net
  CATEGORY:=Network
  TITLE:=IP throttling control for OpenWrt
  
  # 依赖说明：
  # - nftables: 用户空间工具（硬性依赖）
  # - luci-base: LuCI 界面框架（硬性依赖）
  # - tc: 流量控制工具（硬性依赖，opkg/apk 自动选择 tc 或 tc-tiny）
  # 注意：内核模块(kmod-*)为架构相关包，不在 SDK 中，
  # 运行时由 init.d 后台自动检测并安装（避免 opkg 锁冲突）
  DEPENDS:=+nftables +luci-base +tc
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

# ==========================================
# 安装后脚本（postinst）
# 功能: 生成版本号，清除 LuCI 缓存
# 原因: LuCI JS 框架缓存机制导致更新后浏览器仍显示旧版，
#       需要生成新时间戳让 JS 检测到版本变化并强制刷新。
# 注意: 此脚本在 opkg/apk install 时自动执行，
#       在路由器上运行时 $IPKG_INSTROOT 为空。
# ==========================================
define Package/ipthrottle/postinst
	#!/bin/sh
	# 仅在路由器上实际安装时执行（非构建环境）
	if [ -z "$${IPKG_INSTROOT}" ]; then
		# 生成版本号并清除缓存
		/usr/lib/ipthrottle/postinstall.sh
	fi
endef

$(eval $(call BuildPackage,ipthrottle))
