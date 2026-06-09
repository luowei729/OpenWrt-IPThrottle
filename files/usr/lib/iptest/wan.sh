#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle WAN 接口管理模块
# 文件: /usr/lib/iptest/wan.sh
# 功能: WAN 接口发现、带宽获取、接口验证
# 创建时间: 2026-06-09
# ==========================================

# 日志标签
IPT_WAN_LOG_TAG="iptest-wan"

# 记录日志
# 参数: $1=日志级别, $2=日志消息
wan_log_msg() {
    logger -t "$IPT_WAN_LOG_TAG" "$1: $2"
}

# 发现所有 WAN 接口
# 输出: 每行一个 WAN 接口名 (如 wan, wan2)
# 返回: 0=成功, 1=未发现 WAN
# 实现原因: 多 WAN 环境下，需要动态获取所有 WAN 接口，而非硬编码
# 实现思路: 通过 firewall zone name=wan 的 list network 字段获取
get_wan_interfaces() {
    # 查找 firewall 中 name=wan 的 zone 索引
    local wan_zone_idx=""
    local idx=0
    
    # 遍历所有 zone，查找 name=wan
    while uci -q get firewall.@zone[$idx].name >/dev/null 2>&1; do
        local zone_name
        zone_name=$(uci -q get firewall.@zone[$idx].name)
        if [ "$zone_name" = "wan" ]; then
            wan_zone_idx=$idx
            break
        fi
        idx=$((idx + 1))
    done
    
    # 未找到 wan zone
    if [ -z "$wan_zone_idx" ]; then
        wan_log_msg "ERROR" "Cannot find firewall zone with name=wan"
        return 1
    fi
    
    # 获取 wan zone 的 network 列表
    local networks
    networks=$(uci -q get firewall.@zone[$wan_zone_idx].network)
    
    if [ -z "$networks" ]; then
        wan_log_msg "ERROR" "Firewall zone wan has no network interfaces"
        return 1
    fi
    
    # 输出所有网络接口（每行一个）
    echo "$networks"
}

# 验证 WAN 接口是否存在
# 参数: $1=接口名 (如 wan, wan2)
# 返回: 0=存在, 1=不存在
# 实现原因: 用户配置的 wan_mask 可能包含不存在的接口，需要校验
wan_interface_exists() {
    local iface="$1"
    
    # 检查接口是否在 get_wan_interfaces 输出中
    local all_wans
    all_wans=$(get_wan_interfaces) || return 1
    
    echo "$all_wans" | grep -q "^${iface}$"
}

# 获取 WAN 接口的物理设备名
# 参数: $1=接口名 (如 wan)
# 输出: 物理设备名 (如 eth0.2, pppoe-wan)
# 返回: 0=成功, 1=失败
# 实现原因: tc 限速需要作用在物理设备上，而非逻辑接口名
# 实现思路: 通过 ubus 查询 network.interface.$iface.status 获取 device 字段
get_wan_device() {
    local iface="$1"
    
    # 通过 ubus 查询接口状态
    local status
    status=$(ubus -S call network.interface."$iface" status 2>/dev/null)
    
    if [ -z "$status" ]; then
        wan_log_msg "ERROR" "Cannot get status for interface: $iface"
        return 1
    fi
    
    # 提取 device 字段
    local device
    device=$(echo "$status" | jsonfilter -e '@.device' 2>/dev/null)
    
    if [ -z "$device" ]; then
        wan_log_msg "ERROR" "Interface $iface has no device"
        return 1
    fi
    
    echo "$device"
}

# 获取 WAN 接口带宽（Mbps）
# 参数: $1=接口名, $2=方向 (up/down)
# 输出: 带宽值 (Mbps)
# 返回: 0=成功, 1=失败
# 实现原因: tc htb 根 class 需要设置总带宽上限，优先自动检测，失败则使用 UCI 配置值
# 实现思路: 
#   1. 优先通过 ubus 自动检测（适用于 DHCP/PPPoE 等可获取协商速率的场景）
#   2. 自动检测失败时，回退到 UCI 配置 iptest.@global[0].${iface}_${direction}_mbps
#   3. UCI 配置也不存在时，使用默认值 100 Mbps
get_wan_bandwidth() {
    local iface="$1"
    local direction="$2"  # up 或 down
    
    # 尝试自动检测
    local auto_bw=""
    auto_bw=$(detect_wan_bandwidth "$iface" "$direction")
    
    if [ -n "$auto_bw" ] && [ "$auto_bw" -gt 0 ] 2>/dev/null; then
        echo "$auto_bw"
        return 0
    fi
    
    # 自动检测失败，使用 UCI 配置
    local uci_bw
    uci_bw=$(uci -q get iptest.@global[0]."${iface}_${direction}_mbps")
    
    if [ -n "$uci_bw" ] && [ "$uci_bw" -gt 0 ] 2>/dev/null; then
        wan_log_msg "WARN" "Auto-detect failed for $iface $direction, using UCI config: ${uci_bw}Mbps"
        echo "$uci_bw"
        return 0
    fi
    
    # 都没有，使用默认值
    wan_log_msg "WARN" "No bandwidth config for $iface $direction, using default: 100Mbps"
    echo "100"
}

# 自动检测 WAN 接口带宽
# 参数: $1=接口名, $2=方向 (up/down)
# 输出: 带宽值 (Mbps)
# 返回: 0=成功, 1=失败
# 实现原因: 部分接口（如 PPPoE、DHCP）可通过 ubus 获取协商速率
detect_wan_bandwidth() {
    local iface="$1"
    local direction="$2"
    
    # 通过 ubus 查询接口状态
    local status
    status=$(ubus -S call network.interface."$iface" status 2>/dev/null) || return 1
    
    # 尝试从 status 中提取带宽（不同协议字段名可能不同）
    # 例如: DHCP 可能返回 up/download，PPPoE 可能返回 bandwidth
    local bw=""
    
    # 尝试获取 up (上传)
    if [ "$direction" = "up" ]; then
        bw=$(echo "$status" | jsonfilter -e '@.up' 2>/dev/null)
        [ -z "$bw" ] && bw=$(echo "$status" | jsonfilter -e '@.upload' 2>/dev/null)
    fi
    
    # 尝试获取 down (下载)
    if [ "$direction" = "down" ]; then
        bw=$(echo "$status" | jsonfilter -e '@.down' 2>/dev/null)
        [ -z "$bw" ] && bw=$(echo "$status" | jsonfilter -e '@.download' 2>/dev/null)
    fi
    
    # 尝试通用 bandwidth 字段
    [ -z "$bw" ] && bw=$(echo "$status" | jsonfilter -e '@.bandwidth' 2>/dev/null)
    
    # 如果获取到值，返回
    if [ -n "$bw" ] && [ "$bw" -gt 0 ] 2>/dev/null; then
        echo "$bw"
        return 0
    fi
    
    return 1
}

# 解析 wan_mask 为接口列表
# 参数: $1=wan_mask (如 "all" 或 "wan,wan2")
# 输出: 每行一个接口名
# 返回: 0=成功, 1=包含无效接口
# 实现原因: 规则的 wan_mask 字段可能是 "all" 或逗号分隔的接口列表，需要统一处理
parse_wan_mask() {
    local mask="$1"
    
    # "all" 表示所有 WAN
    if [ "$mask" = "all" ]; then
        get_wan_interfaces
        return $?
    fi
    
    # 逗号分隔的接口列表
    local IFS=','
    for iface in $mask; do
        # 验证接口是否存在
        if ! wan_interface_exists "$iface"; then
            wan_log_msg "ERROR" "WAN interface not found: $iface"
            return 1
        fi
        echo "$iface"
    done
}
