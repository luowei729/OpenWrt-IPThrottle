#!/bin/sh
# ==========================================
# OpenWrt IPThrottle 安装后脚本
# 文件: /usr/lib/ipthrottle/postinstall.sh
# 功能: 生成版本号，彻底清除 LuCI 缓存
# 创建时间: 2026-06-10
# 修改时间: 2026-06-10 19:25 (增强缓存清理)
# 设计原因:
#   依赖安装由 init.d 在启动服务时完成（等待锁释放后同步安装）。
#   postinstall 只做版本管理和缓存清理，不安装依赖（避免锁冲突）。
# ==========================================

VERSION_FILE="/etc/ipthrottle/version"
WEB_VERSION_FILE="/www/luci-static/resources/view/ipthrottle.version"

mkdir -p /etc/ipthrottle
mkdir -p /www/luci-static/resources/view

# 生成新版本号（Unix 时间戳）
# 原因: 每次安装/升级生成唯一时间戳，用于浏览器缓存破坏
NEW_VERSION=$(date +%s)
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "$NEW_VERSION" > "$WEB_VERSION_FILE"

# 彻底清除所有 LuCI 缓存
# 原因: LuCI 框架会在 /tmp 下缓存模块和索引，旧缓存会导致浏览器加载旧 JS
#   清除后浏览器下次访问会重新加载最新 JS 文件
rm -rf /tmp/luci-indexcache 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
# 清除 ubus/rpcd 缓存（LuCI RPC 调用也可能缓存旧数据）
rm -rf /tmp/luci-* 2>/dev/null

logger -t ipthrottle-postinstall "Version updated to $NEW_VERSION, all LuCI cache cleared"

exit 0
