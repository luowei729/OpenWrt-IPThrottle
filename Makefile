include $(TOPDIR)/rules.mk

PKG_NAME:=ipthrottle
PKG_VERSION:=1.0.8
PKG_RELEASE:=1
PKG_MAINTAINER:=OpenWrt IPThrottle Development Team
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/ipthrottle
  SECTION:=net
  CATEGORY:=Network
  TITLE:=IP throttling control for OpenWrt
  
  # 依赖说明：
  # - nftables: nftables 用户空间工具
  # - luci-base: LuCI 界面框架
  # - tc-tiny: 流量控制工具（所有版本统一包名，无 tc 包）
  # - kmod-ifb: IFB 虚拟网卡（入站限速必需）
  # 注意: kmod-sched-core 由 tc-tiny 自动依赖
  # 包名参考: docs/package-names.md
  DEPENDS:=+nftables +luci-base +tc-tiny +kmod-ifb
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
