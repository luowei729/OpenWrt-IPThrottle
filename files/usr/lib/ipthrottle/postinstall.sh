#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle 安装后脚本
# 文件: /usr/lib/ipthrottle/postinstall.sh
# 功能: 生成版本号，清除 LuCI 缓存
# 创建时间: 2026-06-10
# 修改时间: 2026-06-10 15:15
# 设计原因:
#   依赖安装由 init.d 在启动服务时完成（等待锁释放后同步安装）。
#   postinstall 只做版本管理和缓存清理，不安装依赖（避免锁冲突）。
# ==========================================

VERSION_FILE="/etc/ipthrottle/version"
WEB_VERSION_FILE="/www/luci-static/resources/view/ipthrottle.version"

mkdir -p /etc/ipthrottle
mkdir -p /www/luci-static/resources/view

NEW_VERSION=$(date +%s)
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "$NEW_VERSION" > "$WEB_VERSION_FILE"

rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null

logger -t ipthrottle-postinstall "Version updated to $NEW_VERSION, LuCI cache cleared"

exit 0
