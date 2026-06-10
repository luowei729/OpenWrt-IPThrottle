#!/bin/sh
# ==========================================
# OpenWrt IPThrottle 插件 - 依赖检测与安装
# 文件: /usr/lib/ipthrottle/deps.sh
# 功能: 检测并自动安装运行所需的依赖包
# 创建时间: 2026-06-10
# ==========================================

# 日志函数
deps_log() {
    logger -t "ipthrottle-deps" "$1"
    echo "[ipthrottle-deps] $1"
}

# 检测包管理器类型
detect_pkg_manager() {
    if command -v apk >/dev/null 2>&1; then
        echo "apk"
    elif command -v opkg >/dev/null 2>&1; then
        echo "opkg"
    else
        echo "unknown"
    fi
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# 检查内核模块是否已加载
check_kmod() {
    lsmod 2>/dev/null | grep -q "^$1 "
}

# 安装依赖包
install_package() {
    local pkg="$1"
    local pkg_mgr="$2"
    
    deps_log "Installing package: $pkg"
    
    case "$pkg_mgr" in
        apk)
            apk add "$pkg" 2>&1
            ;;
        opkg)
            opkg update >/dev/null 2>&1
            opkg install "$pkg" 2>&1
            ;;
        *)
            deps_log "ERROR: Unknown package manager"
            return 1
            ;;
    esac
}

# 检查并安装 tc 命令
ensure_tc() {
    if check_command tc; then
        # tc 已存在，检查是否可用
        if tc -V >/dev/null 2>&1; then
            deps_log "tc command OK"
            return 0
        fi
    fi
    
    deps_log "tc command not found, installing..."
    local pkg_mgr
    pkg_mgr=$(detect_pkg_manager)
    
    case "$pkg_mgr" in
        apk)
            # OpenWrt 25+ 使用 apk，包名为 tc-tiny
            install_package "tc-tiny" "$pkg_mgr"
            ;;
        opkg)
            # OpenWrt 24 及更早版本使用 opkg
            # 尝试多个可能的包名
            if opkg list | grep -q "^tc "; then
                install_package "tc" "$pkg_mgr"
            elif opkg list | grep -q "^iproute2-tc "; then
                install_package "iproute2-tc" "$pkg_mgr"
            else
                # 默认尝试 tc
                install_package "tc" "$pkg_mgr"
            fi
            ;;
    esac
    
    # 验证安装
    if check_command tc && tc -V >/dev/null 2>&1; then
        deps_log "tc installed successfully"
        return 0
    else
        deps_log "ERROR: Failed to install tc"
        return 1
    fi
}

# 检查并加载内核模块
ensure_kmod() {
    local kmod_name="$1"
    local pkg_name="$2"
    
    if check_kmod "$kmod_name"; then
        deps_log "Kernel module $kmod_name already loaded"
        return 0
    fi
    
    # 尝试 modprobe 加载
    modprobe "$kmod_name" 2>/dev/null
    if check_kmod "$kmod_name"; then
        deps_log "Kernel module $kmod_name loaded"
        return 0
    fi
    
    # 模块未加载，尝试安装
    deps_log "Installing kernel module: $pkg_name"
    local pkg_mgr
    pkg_mgr=$(detect_pkg_manager)
    install_package "$pkg_name" "$pkg_mgr"
    
    # 再次尝试加载
    modprobe "$kmod_name" 2>/dev/null
    if check_kmod "$kmod_name"; then
        deps_log "Kernel module $kmod_name installed and loaded"
        return 0
    else
        deps_log "WARNING: Failed to load kernel module $kmod_name"
        return 1
    fi
}

# 检查并安装 nftables
ensure_nft() {
    if check_command nft; then
        deps_log "nft command OK"
        return 0
    fi
    
    deps_log "nft command not found, installing..."
    local pkg_mgr
    pkg_mgr=$(detect_pkg_manager)
    
    case "$pkg_mgr" in
        apk)
            install_package "nftables" "$pkg_mgr"
            ;;
        opkg)
            install_package "nftables" "$pkg_mgr"
            ;;
    esac
    
    if check_command nft; then
        deps_log "nft installed successfully"
        return 0
    else
        deps_log "ERROR: Failed to install nft"
        return 1
    fi
}

# 主函数：检查所有依赖
check_all_deps() {
    deps_log "Checking dependencies..."
    local failed=0
    
    # 1. 检查 tc 命令
    ensure_tc || failed=1
    
    # 2. 检查 nft 命令
    ensure_nft || failed=1
    
    # 3. 检查内核模块
    # ifb: 用于入站限速
    ensure_kmod "ifb" "kmod-ifb" || failed=1
    
    # sched: 流量调度（包含 htb）
    ensure_kmod "sch_htb" "kmod-sched" || failed=1
    
    # sch_ingress: ingress qdisc 支持
    ensure_kmod "sch_ingress" "kmod-sched" || true  # 可能已内置
    
    # act_mirred: 流量重定向到 ifb（入站流量镜像到 IFB 虚拟设备）
    ensure_kmod "act_mirred" "kmod-sched" || true  # 可能已内置
    
    # act_skbedit: 在 tc ingress 过滤器中设置 skb mark
    # 实现原因: 下载方向的包需要在 WAN ingress 阶段（重定向到 IFB 之前）设置 mark，
    #           nftables forward chain 对 mirred 重定向的包不生效，
    #           因此必须使用 tc ingress + skbedit 在重定向前标记下载包
    ensure_kmod "act_skbedit" "kmod-sched" || true  # 可能已内置
    
    if [ $failed -eq 0 ]; then
        deps_log "All dependencies OK"
        return 0
    else
        deps_log "ERROR: Some dependencies failed to install"
        return 1
    fi
}

# 如果直接执行此脚本，运行检查
if [ "${0##*/}" = "deps.sh" ] || [ "${0##*/}" = "ipthrottle-deps" ]; then
    check_all_deps
fi
