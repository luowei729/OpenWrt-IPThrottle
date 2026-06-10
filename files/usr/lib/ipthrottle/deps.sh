#!/bin/sh
# ==========================================
# OpenWrt IPThrottle 插件 - 依赖检测（只检测，不安装）
# 文件: /usr/lib/ipthrottle/deps.sh
# 功能: 检测运行所需依赖是否就绪，缺失时输出警告+安装指令
# 创建时间: 2026-06-10
# 修改时间: 2026-06-10 14:40
# 设计原因:
#   依赖安装由包管理器(opkg/apk)在安装时原子完成（Makefile DEPENDS:= 声明）。
#   服务运行时只做检测+警告，绝不调用 opkg/apk 安装（会触发死锁）。
#   若用户手动删除依赖，此脚本提示如何补装。
# ==========================================

# 日志函数
deps_log() {
    logger -t "ipthrottle-deps" "$1"
    echo "[ipthrottle-deps] $1"
}

deps_warn() {
    logger -t "ipthrottle-deps" "WARNING: $1"
    echo "[ipthrottle-deps] WARNING: $1"
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# 检查内核模块是否已加载（支持已编入内核的情况）
check_kmod() {
    # lsmod 显示已加载模块
    lsmod 2>/dev/null | grep -q "^$1 " && return 0
    # 检查是否编入内核（/lib/modules/.../modules.builtin）
    find /lib/modules -name "modules.builtin" -exec grep -q "$1" {} \; 2>/dev/null && return 0
    return 1
}

# ============ 只检测函数 ============

# 检测 tc 命令
check_tc() {
    if check_command tc; then
        if tc -V >/dev/null 2>&1; then
            deps_log "tc command OK"
            return 0
        fi
    fi
    deps_warn "tc command not found! Install: opkg install tc  OR  apk add tc-tiny"
    return 1
}

# 检测 nft 命令
check_nft() {
    if check_command nft; then
        deps_log "nft command OK"
        return 0
    fi
    deps_warn "nft command not found! Install: opkg install nftables  OR  apk add nftables"
    return 1
}

# 检测内核模块（仅警告，不安装）
check_kmod_only() {
    local kmod_name="$1"
    local pkg_name="$2"
    local optional="$3"  # "optional" = 缺少不报错
    
    if check_kmod "$kmod_name"; then
        deps_log "kmod $kmod_name OK"
        return 0
    fi
    
    # 尝试 modprobe 加载（模块可能已安装但未加载）
    modprobe "$kmod_name" 2>/dev/null
    if check_kmod "$kmod_name"; then
        deps_log "kmod $kmod_name loaded via modprobe"
        return 0
    fi
    
    if [ "$optional" = "optional" ]; then
        deps_warn "kmod $kmod_name not loaded (optional, may be built-in or not needed)"
    else
        deps_warn "kmod $kmod_name not found! Install: opkg/apk install $pkg_name, then modprobe $kmod_name"
        return 1
    fi
    return 0
}

# ============ 主函数 ============

check_all_deps() {
    deps_log "Checking dependencies..."
    local failed=0
    
    # 1. 检测 tc 命令
    check_tc || failed=1
    
    # 2. 检测 nft 命令
    check_nft || failed=1
    
    # 3. 检测内核模块
    # ifb: IFB 虚拟网卡（入站流量镜像目标）
    check_kmod_only "ifb" "kmod-ifb" "" || failed=1
    
    # sch_htb: HTB 流量调度（核心模块，必须）
    check_kmod_only "sch_htb" "kmod-sched-htb" "" || failed=1
    
    # sch_ingress: ingress qdisc（可选，某些固件已内置）
    check_kmod_only "sch_ingress" "kmod-sched" "optional"
    
    # act_mirred: 流量重定向到 IFB（可选，某些固件已内置）
    check_kmod_only "act_mirred" "kmod-sched" "optional"
    
    # act_skbedit: 在 tc ingress 设置 skb mark
    # 实现原因: 下载方向包需在 WAN ingress 标记（重定向到 IFB 之前），
    #           nftables forward chain 对 mirred 重定向包不生效
    check_kmod_only "act_skbedit" "kmod-sched" "optional"
    
    if [ $failed -eq 0 ]; then
        deps_log "All dependencies OK"
        return 0
    else
        deps_warn "Some dependencies missing! Install them manually, then run: /etc/init.d/ipthrottle restart"
        return 1
    fi
}

# 独立执行此脚本时运行检测
if [ "${0##*/}" = "deps.sh" ] || [ "${0##*/}" = "ipthrottle-deps" ]; then
    check_all_deps
fi
