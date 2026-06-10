#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle 安装后脚本
# 文件: /usr/lib/ipthrottle/postinstall.sh
# 功能: 
#   1. 等待包管理器锁释放（解决 opkg/apk 安装锁冲突）
#   2. 安装缺失的内核模块依赖
#   3. 生成版本号，清除 LuCI 缓存
# 创建时间: 2026-06-10
# 修改时间: 2026-06-10 14:55
# 实现原因: 
#   - opkg/apk 安装多包时，postinst 执行期间主流程仍持锁，需等锁释放
#   - kmod 包在 SDK 中不存在（架构相关），只能运行时安装
#   - 等待锁释放后同步安装依赖，安装完成退出（用户可见进度，不卡界面）
# ==========================================

log_info() {
    logger -t ipthrottle-postinstall "$1"
    echo "[ipthrottle] $1"
}

# ============ 等待包管理器锁释放 ============

wait_pkg_lock() {
    local lock_file=""
    local max_wait=120
    local waited=0
    
    # 检测包管理器类型
    if command -v apk >/dev/null 2>&1; then
        lock_file="/lib/apk/db/lock"
    elif command -v opkg >/dev/null 2>&1; then
        lock_file="/var/lock/opkg.lock"
    else
        return 0
    fi
    
    # 锁不存在直接返回
    [ ! -f "$lock_file" ] && return 0
    
    log_info "Waiting for package manager lock to release..."
    while [ -f "$lock_file" ] && [ $waited -lt $max_wait ]; do
        sleep 2
        waited=$((waited + 2))
    done
    
    if [ $waited -ge $max_wait ]; then
        log_info "WARNING: Lock wait timeout (${max_wait}s), proceeding without deps install"
        return 1
    fi
    
    log_info "Lock released after ${waited}s"
    return 0
}

# ============ 安装依赖 ============

install_package() {
    local pkg="$1"
    
    if command -v apk >/dev/null 2>&1; then
        apk add "$pkg" >/dev/null 2>&1
    elif command -v opkg >/dev/null 2>&1; then
        opkg install "$pkg" >/dev/null 2>&1
    fi
}

load_kmod() {
    local mod="$1"
    modprobe "$mod" 2>/dev/null
}

install_deps() {
    log_info "Installing missing kernel modules..."
    
    # 安装内核模块包（SDK 中不存在，必须运行时安装）
    local kmods="kmod-ifb kmod-sched-htb"
    for pkg in $kmods; do
        install_package "$pkg"
        log_info "Installed: $pkg"
    done
    
    # 加载模块
    for mod in ifb sch_htb sch_ingress act_mirred act_skbedit; do
        load_kmod "$mod"
    done
    
    log_info "Kernel modules installed and loaded"
}

# ============ 主流程 ============

# 1. 等待包管理器锁释放
if wait_pkg_lock; then
    # 2. 锁释放，安装依赖
    install_deps
else
    # 锁超时，跳过依赖安装（用户可稍后手动启动服务）
    log_info "SKIPPED: deps install due to lock timeout"
fi

# 3. 生成版本号，清除 LuCI 缓存
VERSION_FILE="/etc/ipthrottle/version"
WEB_VERSION_FILE="/www/luci-static/resources/view/ipthrottle.version"

mkdir -p /etc/ipthrottle
mkdir -p /www/luci-static/resources/view

NEW_VERSION=$(date +%s)
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "$NEW_VERSION" > "$WEB_VERSION_FILE"

rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null

log_info "Version updated to $NEW_VERSION, LuCI cache cleared"

exit 0
