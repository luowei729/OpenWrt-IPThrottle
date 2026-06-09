#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle 核心逻辑模块
# 文件: /usr/lib/iptest/core.sh
# 功能: 生成 tc/nft 命令、应用规则、服务控制
# 创建时间: 2026-06-09
# 设计说明: 
#   由于 OpenWrt ash shell 的管道会创建子 shell，变量修改不会传递到父 shell，
#   所有跨循环的状态都通过临时文件管理。循环使用 "while read ... done < file"
#   形式而不是 "xxx | while read ..." 形式，避免子 shell 问题。
# ==========================================

# 加载依赖模块
. /usr/lib/iptest/ip.sh
. /usr/lib/iptest/wan.sh
. /usr/lib/iptest/schedule.sh

# 日志标签
IPT_CORE_LOG_TAG="iptest-core"

# 记录日志
core_log_msg() {
    logger -t "$IPT_CORE_LOG_TAG" "$1: $2"
}

# ==========================================
# 临时文件管理
# ==========================================
# 使用临时文件代替全局变量，避免子 shell 作用域问题
# 所有临时文件放在 /tmp/iptest_work/ 目录下
WORK_DIR="/tmp/iptest_work"

# 初始化工作目录
init_work_dir() {
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
}

# 关键临时文件路径
SORTED_RULES_FILE="$WORK_DIR/sorted_rules"     # 排序后的规则列表
MARK_MAP_FILE="$WORK_DIR/mark_map"             # rule -> mark 映射
COUNTER_FILE="$WORK_DIR/counter"               # 全局 ID 计数器

# 初始化全局计数器（写入文件避免子 shell 问题）
init_counter() {
    echo "1" > "$COUNTER_FILE"
}

# 获取并递增计数器（每次调用返回当前值并自增 1）
next_id() {
    local id
    id=$(cat "$COUNTER_FILE")
    echo $((id + 1)) > "$COUNTER_FILE"
    echo "$id"
}

# ==========================================
# 工具函数
# ==========================================

# 速率单位转换：kbps 转换为 tc rate 字符串
# 参数: $1=速率值 (kbps)
# 输出: tc rate 字符串 (如 "1024kbit" 或 "1mbit")
# 实现原因: tc 命令支持 kbit/mbit 单位，用 mbit 更简洁易读
kbps_to_tc_rate() {
    local kbps="$1"
    if [ "$kbps" -ge 1000 ] 2>/dev/null && [ $((kbps % 1000)) -eq 0 ]; then
        echo "$((kbps / 1000))mbit"
    else
        echo "${kbps}kbit"
    fi
}

# 速率单位转换：Mbps 转换为 tc rate 字符串
# 参数: $1=速率值 (Mbps)
# 输出: tc rate 字符串 (如 "100mbit")
mbps_to_tc_rate() {
    echo "${1}mbit"
}

# ==========================================
# 规则排序和准备（Phase 1）
# ==========================================

# 准备：获取所有 active 规则，分配 mark 和 rule_index
# 输出：写入 SORTED_RULES_FILE 和 MARK_MAP_FILE
# 格式：SORTED_RULES_FILE 每行 = "priority rule_section"
#       MARK_MAP_FILE 每行 = "rule_section mark rule_index"
# 实现原因: 全局 mark 分配和 rule 索引需要在单个 shell 上下文中完成，避免子 shell 变量丢失
prepare_rules() {
    core_log_msg "INFO" "Preparing rule list (mark assignment and sorting)"
    
    init_counter
    > "$MARK_MAP_FILE"
    
    local tmp_sorted="$WORK_DIR/tmp_presort"
    > "$tmp_sorted"
    
    # 第一遍：遍历所有 enabled 且 schedule 匹配的规则，记录 priority
    local config
    for config in $(uci -q show iptest | grep '=rule$' | sed 's/^iptables\.//;s/=rule$//'); do
        # 跳过 disabled 规则
        local enabled
        enabled=$(uci -q get iptest."$config".enabled)
        [ "$enabled" = "1" ] || continue
        
        # 检查 schedule 是否生效（当前时间）
        if ! check_rule_should_active "$config"; then
            continue
        fi
        
        # 读取 priority（默认 10，clamp 1-99）
        local priority
        priority=$(uci -q get iptest."$config".priority)
        [ -z "$priority" ] && priority=10
        [ "$priority" -lt 1 ] 2>/dev/null && priority=1
        [ "$priority" -gt 99 ] 2>/dev/null && priority=99
        
        echo "${priority} ${config}" >> "$tmp_sorted"
    done
    
    # 按 priority 升序稳定排序
    sort -n -k1 -s "$tmp_sorted" > "$SORTED_RULES_FILE"
    
    # 第二遍：分配唯一 mark 和 rule_index
    > "$MARK_MAP_FILE"
    init_counter
    
    # 使用临时文件避免管道子 shell 问题
    while read -r _priority _rule; do
        [ -z "$_rule" ] && continue
        local _mark
        _mark=$(next_id)
        echo "$_rule $_mark" >> "$MARK_MAP_FILE"
    done < "$SORTED_RULES_FILE"
    
    # 统计
    local _count
    _count=$(wc -l < "$SORTED_RULES_FILE" 2>/dev/null)
    core_log_msg "INFO" "Prepared $_count active rules"
}

# 根据 rule section 查询 mark
# 参数: $1=rule section
# 输出: mark 值
get_mark_for_rule() {
    awk -v r="$1" '$1==r {print $2}' "$MARK_MAP_FILE"
}

# 获取规则的 wan_mask 解析后的接口列表（输出到文件）
# 参数: $1=rule section, $2=输出文件
# 实现原因: 避免子 shell 管道问题
get_rule_wans_to_file() {
    local rule="$1"
    local outfile="$2"
    local mask
    mask=$(uci -q get iptest."$rule".wan_mask)
    [ -z "$mask" ] && mask="all"
    parse_wan_mask "$mask" > "$outfile"
    return $?
}

# ==========================================
# IFB 设备管理
# ==========================================

# 加载 ifb 内核模块（服务启动时仅调用一次）
# 实现原因: ifb 模块需要在创建 IFB 设备前加载
load_ifb_module() {
    if ! lsmod 2>/dev/null | grep -q "^ifb "; then
        modprobe ifb numifbs=16 2>/dev/null
    fi
}

# 为 WAN 接口设置 IFB 设备（用于上行限速）
# 参数: $1=WAN 物理设备名, $2=IFB 索引
# 实现流程:
#   1. 启动 ifbX 设备
#   2. 在 WAN 物理设备上添加 ingress qdisc
#   3. 将 ingress 方向流量镜像到 ifb 设备
# 实现原因: Linux tc 只能限速出口方向，入站限速需通过 ifb 设备间接实现
setup_ifb_for_wan() {
    local wan_dev="$1"
    local ifb_idx="$2"
    local ifb_dev="ifb${ifb_idx}"
    
    core_log_msg "INFO" "Setting up IFB $ifb_dev for WAN device $wan_dev"
    
    # 启动 ifb 设备
    ip link set "$ifb_dev" up 2>/dev/null
    
    # 在 WAN 设备添加 ingress qdisc
    tc qdisc del dev "$wan_dev" ingress 2>/dev/null
    tc qdisc add dev "$wan_dev" ingress
    
    # 将 ingress 流量重定向到 IFB
    tc filter add dev "$wan_dev" parent ffff: protocol all \
        u32 match u32 0 0 \
        action mirred egress redirect dev "$ifb_dev"
}

# 清理 WAN 接口的 IFB 设置
cleanup_ifb_for_wan() {
    local wan_dev="$1"
    local ifb_idx="$2"
    local ifb_dev="ifb${ifb_idx}"
    
    tc filter del dev "$wan_dev" parent ffff: 2>/dev/null
    tc qdisc del dev "$wan_dev" ingress 2>/dev/null
    tc qdisc del dev "$ifb_dev" root 2>/dev/null
}

# ==========================================
# tc htb 层级树生成（根节点）
# ==========================================

# 为 WAN 物理设备创建根 htb qdisc
# 参数: $1=物理设备名, $2=总带宽 (mbit/s)
# 实现原因: tc htb 需要一个根 qdisc 和根 class，作为所有限速 class 的父节点
create_root_htb() {
    local dev="$1"
    local total_bw="$2"
    
    # 清理旧规则（幂等）
    tc qdisc del dev "$dev" root 2>/dev/null
    
    # 添加根 htb qdisc，默认 class 0 (不限制)
    tc qdisc add dev "$dev" root handle 1: htb default 100
    tc class add dev "$dev" parent 1: classid 1:100 \
        htb rate "${total_bw}mbit" ceil "${total_bw}mbit"
    
    core_log_msg "INFO" "Root HTB created on $dev (${total_bw}mbit)"
}

# ==========================================
# nftables 规则生成（Phase 2）
# ==========================================

# 生成 nftables 配置文件（/tmp/iptest.nft）
# 实现原因: nftables 支持通过 -f 加载配置文件，比逐条调用 nft 命令效率高
# 输出: /tmp/iptest.nft
generate_nftables_config() {
    local nft_file="$WORK_DIR/iptest.nft"
    core_log_msg "INFO" "Generating nftables config: $nft_file"
    
    # 写入文件头：flush 现有 iptest 表，创建新表
    cat > "$nft_file" << 'HEADER'
#!/usr/sbin/nft -f
# OpenWrt-IPThrottle 自动生成的 nftables 规则
# 注意: 本文件由 iptest 服务自动生成，请勿手动修改

flush table ip iptest
HEADER
    
    # 如果 iptest 表不存在，需要创建
    # 使用 "add table" 而不是 "table"，如果不存在则创建，否则不报错
    {
        echo ""
        echo "add table ip iptest"
        echo ""
        echo "add chain ip iptest forward { type filter hook forward priority -1 ; policy accept ; }"
        echo "add chain ip iptest ingress { type filter hook ingress priority 0 ; policy accept ; }"
    } >> "$nft_file"
    
    # 临时文件，保存 forward 和 ingress 规则
    local fwd_rules="$WORK_DIR/nft_fwd"
    local igs_rules="$WORK_DIR/nft_igs"
    > "$fwd_rules"
    > "$igs_rules"
    
    # 临时文件：存放每条规则展开后的 IP 列表
    local ip_list_file="$WORK_DIR/rule_ips"
    
    # 遍历排序后的规则
    while read -r _priority _rule; do
        [ -z "$_rule" ] && continue
        
        local _mark
        _mark=$(get_mark_for_rule "$_rule")
        [ -z "$_mark" ] && continue
        
        # 读取协议
        local _proto
        _proto=$(uci -q get iptest."$_rule".proto)
        [ -z "$_proto" ] && _proto="any"
        
        # 展开所有 IP 到临时文件
        ip_entries_for_rule "$_rule" | ip_dedup_sort > "$ip_list_file"
        
        [ -s "$ip_list_file" ] || {
            core_log_msg "WARN" "Rule $_rule has no valid IPs, skipping"
            continue
        }
        
        # 为每个 IP 生成匹配规则
        local _ip
        while read -r _ip; do
            [ -z "$_ip" ] && continue
            
            case "$_proto" in
                tcp)
                    # forward: 匹配出站方向（源 IP 为 LAN IP）
                    echo "add rule ip iptest forward ip saddr $_ip meta l4proto tcp meta mark set $_mark" >> "$fwd_rules"
                    # ingress: 匹配入站方向（目的 IP 为 LAN IP）
                    echo "add rule ip iptest ingress ip daddr $_ip meta l4proto tcp meta mark set $_mark" >> "$igs_rules"
                    ;;
                udp)
                    echo "add rule ip iptest forward ip saddr $_ip meta l4proto udp meta mark set $_mark" >> "$fwd_rules"
                    echo "add rule ip iptest ingress ip daddr $_ip meta l4proto udp meta mark set $_mark" >> "$igs_rules"
                    ;;
                tcp+udp)
                    echo "add rule ip iptest forward ip saddr $_ip meta l4proto tcp meta mark set $_mark" >> "$fwd_rules"
                    echo "add rule ip iptest forward ip saddr $_ip meta l4proto udp meta mark set $_mark" >> "$fwd_rules"
                    echo "add rule ip iptest ingress ip daddr $_ip meta l4proto tcp meta mark set $_mark" >> "$igs_rules"
                    echo "add rule ip iptest ingress ip daddr $_ip meta l4proto udp meta mark set $_mark" >> "$igs_rules"
                    ;;
                *)
                    # any：不限制协议
                    echo "add rule ip iptest forward ip saddr $_ip meta mark set $_mark" >> "$fwd_rules"
                    echo "add rule ip iptest ingress ip daddr $_ip meta mark set $_mark" >> "$igs_rules"
                    ;;
            esac
        done < "$ip_list_file"
        
    done < "$SORTED_RULES_FILE"
    
    # 合并规则到配置文件
    cat "$fwd_rules" "$igs_rules" >> "$nft_file"
    
    core_log_msg "INFO" "NFT config generated"
}

# 验证并加载 nftables 规则
load_nftables_config() {
    local nft_file="$WORK_DIR/iptest.nft"
    
    # 语法检查
    if ! nft -c -f "$nft_file" 2>/tmp/iptest_nft_err; then
        core_log_msg "ERROR" "NFT syntax check failed: $(cat /tmp/iptest_nft_err)"
        return 1
    fi
    
    # 原子加载：先 flush 后添加，使用单条 nft -f 调用
    if ! nft -f "$nft_file" 2>/tmp/iptest_nft_err; then
        core_log_msg "ERROR" "NFT load failed: $(cat /tmp/iptest_nft_err)"
        return 1
    fi
    
    core_log_msg "INFO" "NFT rules loaded successfully"
}

# ==========================================
# tc 规则生成（Phase 3）
# ==========================================

# 为单个 WAN 物理设备应用所有相关规则
# 参数: $1=物理设备名, $2=方向（up/down）, $3=WAN 带宽 (mbit/s), $4=WAN 逻辑接口名
# 实现原因: 每个 WAN 设备+方向 独立挂载一套 tc 层级树
apply_tc_to_device() {
    local dev="$1"
    local direction="$2"
    local total_bw="$3"
    local wan_iface="$4"
    
    core_log_msg "INFO" "Applying TC rules for device=$dev direction=$direction bw=${total_bw}mbit"
    
    # 创建根 htb
    create_root_htb "$dev" "$total_bw"
    
    # 临时文件：当前处理的 priority 集合（用于创建 priority class）
    local priority_seen="$WORK_DIR/priority_seen_${dev}_${direction}"
    > "$priority_seen"
    
    # 临时文件：每条规则的 IP 列表
    local ip_list_file="$WORK_DIR/rule_ips_tc"
    
    # 用于分配 IP 全局 index（避免冲突）
    local ip_counter="$WORK_DIR/ip_counter_${dev}_${direction}"
    echo "1" > "$ip_counter"
    
    next_ip_id() {
        local _id
        _id=$(cat "$ip_counter")
        echo $((_id + 1)) > "$ip_counter"
        echo "$_id"
    }
    
    # 遍历排序后的规则
    while read -r _priority _rule; do
        [ -z "$_rule" ] && continue
        
        # 检查规则的 wan_mask 是否包含当前 WAN 接口
        local rule_wans_file="$WORK_DIR/rule_wans"
        get_rule_wans_to_file "$_rule" "$rule_wans_file" || continue
        
        if ! grep -q "^${wan_iface}$" "$rule_wans_file"; then
            continue
        fi
        
        # 读取限速参数
        local _mode _rate_kbps
        _mode=$(uci -q get iptest."$_rule".mode)
        [ -z "$_mode" ] && _mode="independent"
        
        if [ "$direction" = "up" ]; then
            _rate_kbps=$(uci -q get iptest."$_rule".upload_kbps)
        else
            _rate_kbps=$(uci -q get iptest."$_rule".download_kbps)
        fi
        [ -z "$_rate_kbps" ] && continue
        
        local _rate_str
        _rate_str=$(kbps_to_tc_rate "$_rate_kbps")
        
        # 创建 priority class（每个 priority 仅一次）
        if ! grep -qx "$_priority" "$priority_seen"; then
            local prio_minor_p100=$(( _priority * 100 ))
            tc class add dev "$dev" parent 1:100 classid "1:${prio_minor_p100}" \
                htb rate "${total_bw}mbit" ceil "${total_bw}mbit" 2>/dev/null
            echo "$_priority" >> "$priority_seen"
        fi
        
        # 分配 rule index 和 rule class ID
        local _rule_idx
        _rule_idx=$(next_ip_id)
        local rule_minor=$(( _priority * 1000 + _rule_idx ))
        
        # 创建 rule class（独立 vs 共享模式不同）
        if [ "$_mode" = "independent" ]; then
            # 独立限速：rule class rate=0（用 WAN 总带宽作为父速率限制）
            tc class add dev "$dev" parent "1:$((_priority * 100))" classid "1:${rule_minor}" \
                htb rate "${total_bw}mbit" ceil "${total_bw}mbit"
        else
            # 共享限速：rule class rate=限速值（所有 IP class 共享此带宽）
            tc class add dev "$dev" parent "1:$((_priority * 100))" classid "1:${rule_minor}" \
                htb rate "$_rate_str" ceil "$_rate_str"
        fi
        
        # 展开 IP 列表
        ip_entries_for_rule "$_rule" | ip_dedup_sort > "$ip_list_file"
        [ -s "$ip_list_file" ] || continue
        
        # 为每个 IP 创建 class
        while read -r _ip; do
            [ -z "$_ip" ] && continue
            
            local _ip_id
            _ip_id=$(next_ip_id)
            # IP class minor: priority*1000 + rule_idx*100 + ip_id（避免冲突）
            local ip_minor=$(( _priority * 1000 + _rule_idx * 100 + _ip_id ))
            
            local ip_rate
            if [ "$_mode" = "independent" ]; then
                # 独立：每个 IP 有独立的 rate 限制
                ip_rate="$_rate_str"
            else
                # 共享：IP class rate 不设限制，由父 class 统一限制
                # tc 不支持 rate=0，但可以用极小速率（1bit）作为最小保证
                ip_rate="1kbit"
            fi
            
            tc class add dev "$dev" parent "1:${rule_minor}" classid "1:${ip_minor}" \
                htb rate "$ip_rate" ceil "${total_bw}mbit"
        done < "$ip_list_file"
        
    done < "$SORTED_RULES_FILE"
    
    # 生成 tc filter（按 mark 将流量引入对应 IP class）
    # 需要重新遍历规则和 IP 列表（因为 filter 需要知道 IP class ID）
    echo "1" > "$ip_counter"
    
    while read -r _priority _rule; do
        [ -z "$_rule" ] && continue
        
        # 再次检查 wan_mask
        local rule_wans_file="$WORK_DIR/rule_wans2"
        get_rule_wans_to_file "$_rule" "$rule_wans_file" || continue
        grep -q "^${wan_iface}$" "$rule_wans_file" || continue
        
        local _mark
        _mark=$(get_mark_for_rule "$_rule")
        [ -z "$_mark" ] && continue
        
        local _rule_idx
        _rule_idx=$(next_ip_id)  # 与上一轮保持一致
        
        # 展开 IP 列表
        ip_entries_for_rule "$_rule" | ip_dedup_sort > "$ip_list_file"
        [ -s "$ip_list_file" ] || continue
        
        # 为每个 IP 创建 filter
        while read -r _ip; do
            [ -z "$_ip" ] && continue
            
            local _ip_id
            _ip_id=$(next_ip_id)
            local ip_minor=$(( _priority * 1000 + _rule_idx * 100 + _ip_id ))
            
            # 使用 fw filter，按 mark 匹配，路由到相应 class
            tc filter add dev "$dev" parent 1:0 protocol ip \
                handle "$_mark" fw classid "1:${ip_minor}"
        done < "$ip_list_file"
    done < "$SORTED_RULES_FILE"
    
    core_log_msg "INFO" "TC rules applied to $dev"
}

# ==========================================
# 服务主函数
# ==========================================

# 启动服务：完整初始化
# 实现流程:
#   1. 加载 ifb 内核模块
#   2. 准备规则列表（mark + 优先级排序）
#   3. 为每个 WAN 接口设置 IFB
#   4. 为每个 WAN 接口 + 每个方向 应用 tc 规则
#   5. 生成并加载 nftables 规则
start_service() {
    core_log_msg "INFO" "====== iptest service starting ======"
    
    # 准备数据：规则排序和 mark 分配
    init_work_dir
    prepare_rules
    
    local rule_count
    rule_count=$(wc -l < "$SORTED_RULES_FILE" 2>/dev/null || echo 0)
    if [ "$rule_count" -eq 0 ]; then
        core_log_msg "INFO" "No active rules, nothing to apply"
        return 0
    fi
    
    # 加载 ifb 模块（用于上行限速）
    load_ifb_module
    
    # 获取所有 WAN 接口
    local wans_file="$WORK_DIR/all_wans"
    get_wan_interfaces > "$wans_file" || {
        core_log_msg "ERROR" "No WAN interfaces found"
        return 1
    }
    
    local ifb_idx=0
    local wan_iface
    
    while read -r wan_iface; do
        [ -z "$wan_iface" ] && continue
        
        core_log_msg "INFO" "Processing WAN interface: $wan_iface"
        
        # 获取 WAN 逻辑接口对应的物理设备名
        local wan_dev
        wan_dev=$(get_wan_device "$wan_iface") || {
            core_log_msg "WARN" "WAN $wan_iface has no device, skipping"
            continue
        }
        
        # 获取上下行带宽
        local up_bw down_bw
        up_bw=$(get_wan_bandwidth "$wan_iface" "up")
        down_bw=$(get_wan_bandwidth "$wan_iface" "down")
        
        core_log_msg "INFO" "WAN $wan_iface: device=$wan_dev, up=${up_bw}Mbps, down=${down_bw}Mbps"
        
        # 设置 IFB 设备（用于上行限速）
        setup_ifb_for_wan "$wan_dev" "$ifb_idx"
        
        # 下行：直接在 WAN 物理设备上创建
        apply_tc_to_device "$wan_dev" "down" "$down_bw" "$wan_iface"
        
        # 上行：在 IFB 设备上创建
        local ifb_dev="ifb${ifb_idx}"
        apply_tc_to_device "$ifb_dev" "up" "$up_bw" "$wan_iface"
        
        ifb_idx=$((ifb_idx + 1))
    done < "$wans_file"
    
    # 生成并加载 nftables 规则
    generate_nftables_config
    load_nftables_config || {
        core_log_msg "ERROR" "Failed to load nftables rules, service start aborted"
        return 1
    }
    
    core_log_msg "INFO" "====== iptest service started successfully ======"
}

# 停止服务：清理所有 iptest 创建的 tc/nft 规则
stop_service() {
    core_log_msg "INFO" "====== iptest service stopping ======"
    
    # 删除 nftables iptest 表
    nft delete table ip iptest 2>/dev/null
    
    # 清理每个 WAN 接口的 IFB 和 tc
    local wans_file="$WORK_DIR/all_wans"
    if [ -f "$WORK_DIR/all_wans" ]; then
        local ifb_idx=0
        local wan_iface
        
        while read -r wan_iface; do
            [ -z "$wan_iface" ] && continue
            local wan_dev
            wan_dev=$(get_wan_device "$wan_iface") || continue
            
            # 清理 IFB（包括 ingress 重定向）
            cleanup_ifb_for_wan "$wan_dev" "$ifb_idx"
            
            # 清理 WAN 物理设备上的根 qdisc
            tc qdisc del dev "$wan_dev" root 2>/dev/null
            
            ifb_idx=$((ifb_idx + 1))
        done < "$wans_file"
    fi
    
    # 清理工作目录
    rm -rf "$WORK_DIR"
    
    core_log_msg "INFO" "====== iptest service stopped ======"
}

# 重新加载：先 stop 再 start
# 实现原因: reload 需要全量重建，确保规则一致性
reload_service() {
    core_log_msg "INFO" "Reloading iptest configuration"
    stop_service
    start_service
}

# ==========================================
# CLI 命令入口（用于调试和手动操作）
# ==========================================

# iptest 命令: apply (应用当前配置)
cmd_apply() {
    start_service
}

# iptest 命令: clear (清除所有规则)
cmd_clear() {
    stop_service
}

# iptest 命令: reload (重新加载)
cmd_reload() {
    reload_service
}

# iptest 命令: status (查看当前状态)
cmd_status() {
    echo "=== iptest 服务状态 ==="
    
    # 检查 nftables iptest 表
    echo "nftables 表:"
    if nft list table ip iptest 2>/dev/null | head -3; then
        echo "  ✓ iptest 表已加载"
    else
        echo "  ✗ iptest 表未加载"
    fi
    
    # 检查 tc 配置
    echo ""
    echo "tc qdisc:"
    tc qdisc show 2>/dev/null | grep -v "noqueue\|fq_codel" | head -20
    
    echo ""
    echo "活跃规则:"
    prepare_rules 2>/dev/null
    if [ -s "$SORTED_RULES_FILE" ]; then
        while read -r _p _r; do
            local _mark
            _mark=$(get_mark_for_rule "$_r")
            local _name
            _name=$(uci -q get iptest."$_r".name)
            echo "  priority=$_p mark=$_mark rule=$_r name=$_name"
        done < "$SORTED_RULES_FILE"
    else
        echo "  无活跃规则"
    fi
}
