#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle 安装后脚本
# 文件: /usr/lib/ipthrottle/postinstall.sh
# 功能: 生成版本号，清除 LuCI 缓存
# 创建时间: 2026-06-10
# 实现原因: 
#   LuCI JS 框架用 {cache:true} 加载模块，版本号绑定 luci.js 编译时间戳，
#   更新插件文件不会改变版本号，导致浏览器一直返回缓存。
#   此脚本在安装/更新时生成新时间戳，JS 加载时对比版本号决定是否强制刷新。
# ==========================================

# 版本号存储路径（两处：配置目录 + Web 可访问目录）
VERSION_FILE="/etc/ipthrottle/version"
WEB_VERSION_FILE="/www/luci-static/resources/view/ipthrottle.version"

# 确保目录存在
mkdir -p /etc/ipthrottle
mkdir -p /www/luci-static/resources/view

# 生成时间戳版本号（精确到秒）
NEW_VERSION=$(date +%s)

# 写入版本号文件（两处）
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "$NEW_VERSION" > "$WEB_VERSION_FILE"

# 清除 LuCI 缓存（确保下次加载使用新配置）
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null

# 记录日志
logger -t ipthrottle-postinstall "Version updated to $NEW_VERSION, LuCI cache cleared"

exit 0
