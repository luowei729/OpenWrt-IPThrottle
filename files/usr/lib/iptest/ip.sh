#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle IP 地址解析模块
# 文件: /usr/lib/iptest/ip.sh
# 功能: IP 地址格式验证、IP段展开、IP段转CIDR
# 创建时间: 2026-06-09
# ==========================================

# 日志标签
IPT_IP_LOG_TAG="iptest-ip"

# 记录日志
# 参数: $1=日志级别, $2=日志消息
ip_log_msg() {
    logger -t "$IPT_IP_LOG_TAG" "$1: $2"
}

# IP 地址转换为 32位整数
# 参数: $1=IP (如 192.168.1.10)
# 返回: 整数 (通过 echo)
# 实现原因: tc htb 的 filter 按 mark 分流时，需要将 IP 段范围用于 nftables 规则
#          通过整数运算快速判断 IP 是否在段区间内
ip_to_int() {
    local ip="$1"
    local a b c d
    # 按 . 分割 IP 地址为四个字节
    IFS='.' read -r a b c d <<EOF
$ip
EOF
    # 位运算: a<<24 | b<<16 | c<<8 | d
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# 32位整数转 IP 地址
# 参数: $1=整数
# 返回: IP 字符串 (通过 echo)
# 实现原因: 展开 IP 段时需要将整数转回 IP 形式
int_to_ip() {
    local int="$1"
    # 位运算提取每个字节
    echo "$(( (int >> 24) & 0xFF )).$(( (int >> 16) & 0xFF )).$(( (int >> 8) & 0xFF )).$(( int & 0xFF ))"
}

# 验证单个 IP 格式是否合法
# 参数: $1=IP 字符串
# 返回: 0=合法, 1=非法
# 实现原因: 前端输入可能包含错误 IP，后端需二次校验，防止非法配置进入 tc/nft
ip_validate() {
    local ip="$1"
    # 正则匹配: 四字节点分十进制
    if ! echo "$ip" | grep -qE '^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'; then
        return 1
    fi
    # 拆分为四个部分验证范围
    local IFS='.'
    set -- $ip
    [ "$1" -ge 0 ] && [ "$1" -le 255 ] && \
    [ "$2" -ge 0 ] && [ "$2" -le 255 ] && \
    [ "$3" -ge 0 ] && [ "$3" -le 255 ] && \
    [ "$4" -ge 0 ] && [ "$4" -le 255 ]
}

# 验证 IP 条目（支持单个 IP 或 IP 段）
# 参数: $1=条目 (单IP或 start-end 格式)
# 返回: 0=合法, 1=非法
# 实现原因: UCI 的 list ip_entry 可能存储单 IP 或 IP 段，需统一验证
ip_entry_validate() {
    local entry="$1"
    # 检查是否是 IP 段 (含 - 分隔符)
    case "$entry" in
        *-*)
            # IP 段格式: start-end
            local start="${entry%-*}"
            local end="${entry#*-}"
            ip_validate "$start" && ip_validate "$end"
            ;;
        *)
            # 单 IP 格式
            ip_validate "$entry"
            ;;
    esac
}

# 展开 IP 段为单个 IP 列表
# 参数: $1=IP 段 (start-end 格式，如 192.168.1.10-192.168.1.20)
# 输出: 每行一个 IP 地址 (通过 echo)
# 返回: 0=成功, 1=非法输入
# 实现原因: nftables 不支持直接匹配 IP 范围，需要展开为独立 IP 或转换为 CIDR
# 注意: 大 IP 段会展开为大量 IP，可能影响性能，后续优化可用 CIDR 合并
ip_range_expand() {
    local range="$1"
    local start_ip="${range%-*}"
    local end_ip="${range#*-}"
    
    # 验证起止 IP 合法性
    if ! ip_validate "$start_ip" || ! ip_validate "$end_ip"; then
        ip_log_msg "ERROR" "Invalid IP in range: $range"
        return 1
    fi
    
    # 转换为整数进行范围判断
    local start_int
    start_int=$(ip_to_int "$start_ip")
    local end_int
    end_int=$(ip_to_int "$end_ip")
    
    # 检查 start <= end
    if [ "$start_int" -gt "$end_int" ]; then
        ip_log_msg "ERROR" "IP range start > end: $range"
        return 1
    fi
    
    # 逐个生成 IP
    local current="$start_int"
    while [ "$current" -le "$end_int" ]; do
        int_to_ip "$current"
        current=$((current + 1))
    done
}

# 解析单条 ip_entry (可能是单 IP 或 IP 段)
# 参数: $1=ip_entry 字符串
# 输出: 每行一个 IP 地址
# 返回: 0=成功, 1=非法
# 实现原因: 统一处理单 IP 和 IP 段两种格式
ip_entry_parse() {
    local entry="$1"
    case "$entry" in
        *-*)
            # IP 段: 展开
            ip_range_expand "$entry"
            ;;
        *)
            # 单 IP: 先验证再输出
            if ip_validate "$entry"; then
                echo "$entry"
            else
                ip_log_msg "ERROR" "Invalid single IP: $entry"
                return 1
            fi
            ;;
    esac
}

# 解析规则的所有 ip_entry
# 参数: $1=rule section 名 (如 cfg0a1b2c)
# 输出: 每行一个 IP 地址 (所有 ip_entry 展开后的结果)
# 实现原因: core.sh 需要获取某条规则涉及的所有 IP 来生成 nftables 规则
ip_entries_for_rule() {
    local rule="$1"
    # 读取 UCI list
    local entries
    entries=$(uci -q get iptest."$rule".ip_entry)
    [ -z "$entries" ] && return
    
    local entry
    for entry in $entries; do
        ip_entry_parse "$entry"
    done
}

# 去重排序 IP 列表
# 输入: stdin (每行一个 IP)
# 输出: stdout (去重排序后，每行一个 IP)
# 实现原因: nftables 规则中同一 IP 重复匹配会浪费性能，需要去重
ip_dedup_sort() {
    sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | uniq
}
