#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle 核心逻辑模块
# 文件: /usr/lib/ipthrottle/core.sh
# 功能: 生成 tc/nft 命令、应用规则、服务控制
# 创建时间: 2026-06-09
# 最后修改: 2026-06-10
# 设计说明: 
#   由于 OpenWrt ash shell 的管道会创建子 shell，变量修改不会传递到父 shell，
#   所有跨循环的状态都通过临时文件管理。循环使用 "while read ... done < file"
#   形式而不是 "xxx | while read ..." 形式，避免子 shell 问题。
#
# 架构说明 (v3 - 混合方案):
#   上传和下载流量经过不同的网络设备，需要分别挂载 tc htb:
#   - 上传流量路径: 客户端 → br-lan(ingress) → IP栈路由 → WAN(egress) → 互联网
#     → tc htb 挂在 WAN 物理设备上（如 eth1）
#   - 下载流量路径: 互联网 → WAN(ingress) → IP栈路由 → br-lan(egress) → 客户端
#     → tc htb 挂在 LAN 网桥上（如 br-lan）
#   nftables forward chain 同时标记上传(ip saddr)和下载(ip daddr)方向，
#   使用不同的 mark 值区分方向：upload_mark = mark, download_mark = mark + 1000。
#   此方案无需 IFB 设备、skbedit 模块、tc ingress 过滤器，
#   且与 passwall 等透明代理兼容（代理流量仍经过 nftables forward 和对应设备 egress）。
# ==========================================

# 加载依赖模块
. /usr/lib/ipthrottle/ip.sh
. /usr/lib/ipthrottle/wan.sh
. /usr/lib/ipthrottle/schedule.sh

# 日志标签
IPT_LOG_TAG="ipthrottle-core"

# 记录日志
core_log_msg() {
    logger -t "$IPT_CORE_LOG_TAG" "$1: $2"
}

# ==========================================
# 临时文件管理
# ==========================================
WORK_DIR="/tmp/ipthrottle_work"

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
# 从 100 开始，避免与 passwall 等工具的 mark=1 冲突
init_counter() {
    echo "100" > "$COUNTER_FILE"
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
# LAN 网桥设备检测
# ==========================================

# 获取 LAN 网桥设备名
# 输出: 网桥设备名 (如 br-lan)
# 实现原因: 下载 tc htb 需要挂在 LAN 网桥上
# 实现思路:
#   1. 优先从 UCI 配置 network.lan.device 获取
#   2. 其次从 UCI 配置 network.lan.ifname 获取（旧版 OpenWrt）
#   3. 都失败则使用默认值 "br-lan"
get_lan_bridge() {
    local bridge=""
    
    # 方法1: 从 network.lan.device 获取（OpenWrt 21+）
    bridge=$(uci -q get network.lan.device)
    if [ -n "$bridge" ] && ip link show "$bridge" >/dev/null 2>&1; then
        echo "$bridge"
        return 0
    fi
    
    # 方法2: 从 network.lan.ifname 获取（旧版 OpenWrt）
    bridge=$(uci -q get network.lan.ifname)
    if [ -n "$bridge" ] && ip link show "$bridge" >/dev/null 2>&1; then
        echo "$bridge"
        return 0
    fi
    
    # 方法3: 默认值 br-lan（OpenWrt 标准命名）
    if ip link show "br-lan" >/dev/null 2>&1; then
        echo "br-lan"
        return 0
    fi
    
    core_log_msg "ERROR" "Cannot detect LAN bridge device"
    return 1
}

# ==========================================
# 规则排序和准备（Phase 1）
# ==========================================

# 准备：获取所有 active 规则，分配 mark 和 rule_index
# 输出：写入 SORTED_RULES_FILE 和 MARK_MAP_FILE
# 格式：SORTED_RULES_FILE 每行 = "priority rule_section"
#       MARK_MAP_FILE 每行 = "rule_section mark"
# mark 分配方案:
#   - 每条规则分配一个基础 mark (从 100 开始递增)
#   - 上传方向使用基础 mark (如 100)
#   - 下载方向使用 mark + 1000 (如 1100)
#   - tc fw filter 通过不同的 handle 值区分上下行
prepare_rules() {
    core_log_msg "INFO" "Preparing rule list (mark assignment and sorting)"
    
    init_counter
    > "$MARK_MAP_FILE"
    
    local tmp_sorted="$WORK_DIR/tmp_presort"
    > "$tmp_sorted"
    
    # 遍历所有 enabled 且 schedule 匹配的规则
    local config
    for config in $(uci -q show ipthrottle | grep '=rule$' | sed 's/^ipthrottle\.//;s/=rule$//'); do
        local enabled
        enabled=$(uci -q get ipthrottle."$config".enabled)
        [ "$enabled" = "1" ] || continue
        
        if ! check_rule_should_active "$config"; then
            continue
        fi
        
        local priority
        priority=$(uci -q get ipthrottle."$config".priority)
        [ -z "$priority" ] && priority=10
        [ "$priority" -lt 1 ] 2>/dev/null && priority=1
        [ "$priority" -gt 99 ] 2>/dev/null && priority=99
        
        echo "${priority} ${config}" >> "$tmp_sorted"
    done
    
    sort -n -k1 -s "$tmp_sorted" > "$SORTED_RULES_FILE"
    
    # 分配唯一 mark
    > "$MARK_MAP_FILE"
    init_counter
    
    while read -r _priority _rule; do
        [ -z "$_rule" ] && continue
        local _mark
        _mark=$(next_id)
        echo "$_rule $_mark" >> "$MARK_MAP_FILE"
    done < "$SORTED_RULES_FILE"
    
    local _count
    _count=$(wc -l < "$SORTED_RULES_FILE" 2>/dev/null)
    core_log_msg "INFO" "Prepared $_count active rules"
}

# 根据 rule section 查询上传方向 mark
# 参数: $1=rule section
# 输出: mark 值
get_mark_for_rule() {
    awk -v r="$1" '$1==r {print $2}' "$MARK_MAP_FILE"
}

# 获取规则的下载方向 mark（= 上传 mark + 1000）
# 参数: $1=rule section
# 输出: 下载方向的 mark 值
# 实现原因: 上传和下载使用不同的 mark 值，tc fw filter 通过 handle 区分方向
get_download_mark_for_rule() {
    local mark
    mark=$(get_mark_for_rule "$1")
    [ -n "$mark" ] && echo $((mark + 1000))
}

# 获取规则的 wan_mask 解析后的接口列表（输出到文件）
# 参数: $1=rule section, $2=输出文件
get_rule_wans_to_file() {
    local rule="$1"
    local outfile="$2"
    local mask
    mask=$(uci -q get ipthrottle."$rule".wan_mask)
    [ -z "$mask" ] && mask="all"
    parse_wan_mask "$mask" > "$outfile"
    return $?
}

# ==========================================
# tc htb 层级树生成
# ==========================================

# 在设备上创建根 htb qdisc
# 参数: $1=设备名, $2=总带宽 (mbit/s)
# 实现原因: tc htb 需要一个根 qdisc 和根 class，作为所有限速 class 的父节点
create_root_htb() {
    local dev="$1"
    local total_bw="$2"
    
    # 清理旧规则（幂等）
    tc qdisc del dev "$dev" root 2>/dev/null
    
    # 添加根 htb qdisc，默认 class 9999 (不限制)
    # class ID 方案:
    # - 1:1 = 根 class
    # - 1:priority (1-99) = 优先级 class
    # - 1:(100 + priority*10 + rule_idx) = 规则 class (110-1089)
    # - 1:(1000 + priority*100 + rule_idx*10 + ip_id) = IP class (1000+)
    tc qdisc add dev "$dev" root handle 1: htb default 9999
    tc class add dev "$dev" parent 1: classid 1:1 \
        htb rate "${total_bw}mbit" ceil "${total_bw}mbit"
    # 默认 class（未匹配的流量，不限速）
    tc class add dev "$dev" parent 1:1 classid 1:9999 \
        htb rate "${total_bw}mbit" ceil "${total_bw}mbit"
    
    core_log_msg "INFO" "Root HTB created on $dev (${total_bw}mbit)"
}

# ==========================================
# nftables 规则生成（Phase 2）
# ==========================================

# 生成 nftables 配置文件
# 输出: $WORK_DIR/ipthrottle.nft
# 规则说明:
#   - 上传方向: ip saddr <client_ip> → set mark <upload_mark>
#   - 下载方向: ip daddr <client_ip> → set mark <download_mark> (= upload_mark + 1000)
#   - 支持协议过滤 (tcp/udp/tcp+udp/any)
#   - forward chain priority -1 确保在 passwall 之前执行
generate_nftables_config() {
    local nft_file="$WORK_DIR/ipthrottle.nft"
    core_log_msg "INFO" "Generating nftables config: $nft_file"
    
    cat > "$nft_file" << 'HEADER'
#!/usr/sbin/nft -f
# OpenWrt-IPThrottle 自动生成的 nftables 规则
# 架构: 混合方案 - 上传 tc 在 WAN，下载 tc 在 br-lan

add table ip ipthrottle
flush table ip ipthrottle
HEADER
    
    # 创建 forward chain，priority -1 在 passwall (priority 0) 之前执行
    {
        echo ""
        echo "add chain ip ipthrottle forward { type filter hook forward priority -1 ; policy accept ; }"
    } >> "$nft_file"
    
    local fwd_rules="$WORK_DIR/nft_fwd"
    > "$fwd_rules"
    
    local ip_list_file="$WORK_DIR/rule_ips"
    
    while read -r _priority _rule; do
        [ -z "$_rule" ] && continue
        
        local _mark_up _mark_down
        _mark_up=$(get_mark_for_rule "$_rule")
        _mark_down=$(get_download_mark_for_rule "$_rule")
        [ -z "$_mark_up" ] && continue
        
        local _proto
        _proto=$(uci -q get ipthrottle."$_rule".proto)
        [ -z "$_proto" ] && _proto="any"
        
        ip_entries_for_rule "$_rule" | ip_dedup_sort > "$ip_list_file"
        
        [ -s "$ip_list_file" ] || {
            core_log_msg "WARN" "Rule $_rule has no valid IPs, skipping"
            continue
        }
        
        local _ip
        while read -r _ip; do
            [ -z "$_ip" ] && continue
            
            case "$_proto" in
                tcp)
                    # 上传: 源 IP 为客户端 TCP
                    echo "add rule ip ipthrottle forward ip saddr $_ip meta l4proto tcp meta mark set $_mark_up" >> "$fwd_rules"
                    # 下载: 目标 IP 为客户端 TCP
                    echo "add rule ip ipthrottle forward ip daddr $_ip meta l4proto tcp meta mark set $_mark_down" >> "$fwd_rules"
                    ;;
                udp)
                    echo "add rule ip ipthrottle forward ip saddr $_ip meta l4proto udp meta mark set $_mark_up" >> "$fwd_rules"
                    echo "add rule ip ipthrottle forward ip daddr $_ip meta l4proto udp meta mark set $_mark_down" >> "$fwd_rules"
                    ;;
                tcp+udp)
                    echo "add rule ip ipthrottle forward ip saddr $_ip meta l4proto tcp meta mark set $_mark_up" >> "$fwd_rules"
                    echo "add rule ip ipthrottle forward ip daddr $_ip meta l4proto tcp meta mark set $_mark_down" >> "$fwd_rules"
                    echo "add rule ip ipthrottle forward ip saddr $_ip meta l4proto udp meta mark set $_mark_up" >> "$fwd_rules"
                    echo "add rule ip ipthrottle forward ip daddr $_ip meta l4proto udp meta mark set $_mark_down" >> "$fwd_rules"
                    ;;
                *)
                    # any: 不限制协议
                    echo "add rule ip ipthrottle forward ip saddr $_ip meta mark set $_mark_up" >> "$fwd_rules"
                    echo "add rule ip ipthrottle forward ip daddr $_ip meta mark set $_mark_down" >> "$fwd_rules"
                    ;;
            esac
        done < "$ip_list_file"
        
    done < "$SORTED_RULES_FILE"
    
    cat "$fwd_rules" >> "$nft_file"
    
    core_log_msg "INFO" "NFT config generated"
}

# 验证并加载 nftables 规则
load_nftables_config() {
    local nft_file="$WORK_DIR/ipthrottle.nft"
    
    if ! nft -c -f "$nft_file" 2>/tmp/ipthrottle_nft_err; then
        core_log_msg "ERROR" "NFT syntax check failed: $(cat /tmp/ipthrottle_nft_err)"
        return 1
    fi
    
    if ! nft -f "$nft_file" 2>/tmp/ipthrottle_nft_err; then
        core_log_msg "ERROR" "NFT load failed: $(cat /tmp/ipthrottle_nft_err)"
        return 1
    fi
    
    core_log_msg "INFO" "NFT rules loaded successfully"
}

# ==========================================
# tc 规则生成（Phase 3）
# ==========================================

# 在指定设备上应用 tc 规则（单方向）
# 参数: $1=设备名, $2=方向(up/down), $3=带宽(mbit/s), $4=IP class minor 偏移量
# 实现原因:
#   - 上传 tc 挂在 WAN 设备上，使用上传 IP class (minor 偏移 1000)
#   - 下载 tc 挂在 br-lan 上，使用下载 IP class (minor 偏移 2000)
#   - 两个设备使用相同的 class ID 结构，但 IP class minor 不同避免冲突
# 参数说明:
#   $4: 上传方向传 1000，下载方向传 2000
#       IP class minor = $4 + priority*100 + rule_idx*10 + ip_id
apply_tc_to_device() {
    local dev="$1"
    local direction="$2"    # up 或 down
    local total_bw="$3"
    local ip_minor_offset="$4"  # 1000(上传) 或 2000(下载)
    
    core_log_msg "INFO" "Applying TC rules on $dev direction=$direction bw=${total_bw}mbit offset=$ip_minor_offset"
    
    # 创建根 htb
    create_root_htb "$dev" "$total_bw"
    
    # 临时文件：当前处理的 priority 集合
    local priority_seen="$WORK_DIR/priority_seen_${direction}"
    > "$priority_seen"
    
    local ip_list_file="$WORK_DIR/rule_ips_tc_${direction}"
    
    # IP 全局 index 计数器
    local ip_counter="$WORK_DIR/ip_counter_${direction}"
    echo "1" > "$ip_counter"
    
    next_ip_id() {
        local _id
        _id=$(cat "$ip_counter")
        echo $((_id + 1)) > "$ip_counter"
        echo "$_id"
    }
    
    # ============================================================
    # 第一遍：创建 tc class 层级树
    # ============================================================
    while read -r _priority _rule; do
        [ -z "$_rule" ] && continue
        
        local _mode
        _mode=$(uci -q get ipthrottle."$_rule".mode)
        [ -z "$_mode" ] && _mode="independent"
        
        # 根据方向读取对应的限速参数
        local _rate_kbps
        if [ "$direction" = "up" ]; then
            _rate_kbps=$(uci -q get ipthrottle."$_rule".upload_kbps)
        else
            _rate_kbps=$(uci -q get ipthrottle."$_rule".download_kbps)
        fi
        [ -z "$_rate_kbps" ] && continue
        
        local _rate_str
        _rate_str=$(kbps_to_tc_rate "$_rate_kbps")
        
        # 创建 priority class（每个 priority 仅一次）
        if ! grep -qx "$_priority" "$priority_seen"; then
            tc class add dev "$dev" parent 1:1 classid "1:$_priority" \
                htb rate "${total_bw}mbit" ceil "${total_bw}mbit" 2>/dev/null
            echo "$_priority" >> "$priority_seen"
        fi
        
        # 分配 rule index
        local _rule_idx
        _rule_idx=$(next_ip_id)
        local rule_minor=$(( 100 + _priority * 10 + _rule_idx ))
        
        # 创建 rule class
        if [ "$_mode" = "independent" ]; then
            # 独立限速：rule class 不限速，由 IP class 限制
            tc class add dev "$dev" parent "1:$_priority" classid "1:${rule_minor}" \
                htb rate "${total_bw}mbit" ceil "${total_bw}mbit"
        else
            # 共享限速：rule class 限速，所有 IP class 共享
            tc class add dev "$dev" parent "1:$_priority" classid "1:${rule_minor}" \
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
            # IP class minor = offset + priority*100 + rule_idx*10 + ip_id
            local ip_minor=$(( ip_minor_offset + _priority * 100 + _rule_idx * 10 + _ip_id ))
            
            local ip_rate ip_ceil
            if [ "$_mode" = "independent" ]; then
                # 独立：每个 IP 有独立的 rate 和 ceil
                ip_rate="$_rate_str"
                ip_ceil="$_rate_str"
            else
                # 共享：由父 class 统一限制
                ip_rate="1kbit"
                ip_ceil="${total_bw}mbit"
            fi
            
            tc class add dev "$dev" parent "1:${rule_minor}" classid "1:${ip_minor}" \
                htb rate "$ip_rate" ceil "$ip_ceil"
        done < "$ip_list_file"
        
    done < "$SORTED_RULES_FILE"
    
    # ============================================================
    # 第二遍：创建 tc filter（按 mark 将流量引入对应 IP class）
    # ============================================================
    echo "1" > "$ip_counter"
    
    while read -r _priority _rule; do
        [ -z "$_rule" ] && continue
        
        # 根据方向获取对应的 mark
        local _mark
        if [ "$direction" = "up" ]; then
            _mark=$(get_mark_for_rule "$_rule")
        else
            _mark=$(get_download_mark_for_rule "$_rule")
        fi
        [ -z "$_mark" ] && continue
        
        # 检查方向是否有限速配置
        local _rate_kbps
        if [ "$direction" = "up" ]; then
            _rate_kbps=$(uci -q get ipthrottle."$_rule".upload_kbps)
        else
            _rate_kbps=$(uci -q get ipthrottle."$_rule".download_kbps)
        fi
        [ -z "$_rate_kbps" ] && continue
        
        local _rule_idx
        _rule_idx=$(next_ip_id)
        
        ip_entries_for_rule "$_rule" | ip_dedup_sort > "$ip_list_file"
        [ -s "$ip_list_file" ] || continue
        
        while read -r _ip; do
            [ -z "$_ip" ] && continue
            
            local _ip_id
            _ip_id=$(next_ip_id)
            local ip_minor=$(( ip_minor_offset + _priority * 100 + _rule_idx * 10 + _ip_id ))
            
            # fw filter: handle <mark> → IP class
            tc filter add dev "$dev" parent 1:0 protocol ip \
                handle "$_mark" fw classid "1:${ip_minor}"
        done < "$ip_list_file"
    done < "$SORTED_RULES_FILE"
    
    core_log_msg "INFO" "TC rules applied to $dev direction=$direction"
}

# ==========================================
# 服务主函数
# ==========================================

# 启动服务
# 实现流程:
#   1. 准备规则列表（mark + 优先级排序）
#   2. 检测 WAN 设备和 LAN 网桥
#   3. 在 WAN 设备上创建上传 tc htb（标记 upload_mark）
#   4. 在 LAN 网桥上创建下载 tc htb（标记 download_mark）
#   5. 生成并加载 nftables 规则（同时标记上传和下载方向）
start_service() {
    core_log_msg "INFO" "====== ipthrottle service starting (hybrid mode) ======"
    
    init_work_dir
    prepare_rules
    
    local rule_count
    rule_count=$(wc -l < "$SORTED_RULES_FILE" 2>/dev/null || echo 0)
    if [ "$rule_count" -eq 0 ]; then
        core_log_msg "INFO" "No active rules, nothing to apply"
        return 0
    fi
    
    # ============================================================
    # 检测网络设备
    # ============================================================
    
    # 检测 LAN 网桥（下载 tc 挂在此设备上）
    local lan_bridge
    lan_bridge=$(get_lan_bridge) || {
        core_log_msg "ERROR" "Cannot detect LAN bridge device"
        return 1
    }
    core_log_msg "INFO" "LAN bridge: $lan_bridge"
    
    # 获取 WAN 接口（上传 tc 挂在 WAN 物理设备上）
    local all_wans_file="$WORK_DIR/all_wans"
    get_wan_interfaces > "$all_wans_file" || {
        core_log_msg "ERROR" "No WAN interfaces found"
        return 1
    }
    
    # ============================================================
    # 按物理设备去重 WAN 接口
    # 实现原因: wan/wan6 可能共享同一物理设备（如 eth1）
    # ============================================================
    local pairs_file="$WORK_DIR/dev_iface_pairs"
    > "$pairs_file"
    
    local wan_iface
    while read -r wan_iface; do
        [ -z "$wan_iface" ] && continue
        local wan_dev
        wan_dev=$(get_wan_device "$wan_iface") || {
            core_log_msg "WARN" "WAN $wan_iface has no device, skipping"
            continue
        }
        echo "$wan_dev $wan_iface" >> "$pairs_file"
    done < "$all_wans_file"
    
    local unique_devs_file="$WORK_DIR/unique_devs"
    awk '!seen[$1]++ {print $1}' "$pairs_file" > "$unique_devs_file"
    
    # 保存设备信息供 stop_service 使用
    echo "$lan_bridge" > "$WORK_DIR/lan_bridge_saved"
    cp "$unique_devs_file" "$WORK_DIR/unique_devs_saved"
    cp "$pairs_file" "$WORK_DIR/pairs_saved"
    
    # ============================================================
    # Phase 1: 为每个 WAN 物理设备创建上传 tc htb
    # ============================================================
    # 上传流量路径: 客户端 → br-lan → IP栈 → WAN(egress) → 互联网
    # tc htb 挂在 WAN egress，按 upload_mark 分类限速
    
    local wan_dev
    while read -r wan_dev; do
        [ -z "$wan_dev" ] && continue
        
        # 获取此物理设备对应的逻辑接口列表
        local lif_file="$WORK_DIR/lif_${wan_dev}"
        grep "^${wan_dev} " "$pairs_file" | awk '{print $2}' > "$lif_file"
        
        local first_lif
        first_lif=$(head -1 "$lif_file")
        local up_bw
        up_bw=$(get_wan_bandwidth "$first_lif" "up")
        
        core_log_msg "INFO" "Upload TC on WAN device: $wan_dev (${up_bw}mbit)"
        
        # 上传 tc: IP class minor 偏移 1000
        apply_tc_to_device "$wan_dev" "up" "$up_bw" 1000
        
    done < "$unique_devs_file"
    
    # ============================================================
    # Phase 2: 在 LAN 网桥上创建下载 tc htb
    # ============================================================
    # 下载流量路径: 互联网 → WAN → IP栈 → br-lan(egress) → 客户端
    # tc htb 挂在 br-lan egress，按 download_mark 分类限速
    
    # 获取第一个 WAN 接口的下载带宽
    local first_wan
    first_wan=$(head -1 "$all_wans_file")
    local down_bw
    down_bw=$(get_wan_bandwidth "$first_wan" "down")
    
    core_log_msg "INFO" "Download TC on LAN bridge: $lan_bridge (${down_bw}mbit)"
    
    # 下载 tc: IP class minor 偏移 2000
    apply_tc_to_device "$lan_bridge" "down" "$down_bw" 2000
    
    # ============================================================
    # Phase 3: 生成并加载 nftables 规则
    # ============================================================
    # nftables forward chain 同时标记:
    #   - 上传: ip saddr <client_ip> → mark <upload_mark> (100+)
    #   - 下载: ip daddr <client_ip> → mark <download_mark> (1100+)
    generate_nftables_config
    load_nftables_config || {
        core_log_msg "ERROR" "Failed to load nftables rules, service start aborted"
        return 1
    }
    
    core_log_msg "INFO" "====== ipthrottle service started successfully (hybrid mode) ======"
}

# 停止服务：清理所有 ipthrottle 创建的 tc/nft 规则
stop_service() {
    core_log_msg "INFO" "====== ipthrottle service stopping ======"
    
    # 删除 nftables ipthrottle 表
    nft delete table ip ipthrottle 2>/dev/null
    
    # 清理 LAN 网桥上的 tc（下载方向）
    local lan_bridge=""
    if [ -f "$WORK_DIR/lan_bridge_saved" ]; then
        lan_bridge=$(cat "$WORK_DIR/lan_bridge_saved")
    else
        lan_bridge=$(get_lan_bridge 2>/dev/null)
    fi
    if [ -n "$lan_bridge" ]; then
        core_log_msg "INFO" "Cleaning up download TC on $lan_bridge"
        tc qdisc del dev "$lan_bridge" root 2>/dev/null
    fi
    
    # 清理 WAN 物理设备上的 tc（上传方向）
    if [ -f "$WORK_DIR/unique_devs_saved" ]; then
        local wan_dev
        while read -r wan_dev; do
            [ -z "$wan_dev" ] && continue
            core_log_msg "INFO" "Cleaning up upload TC on $wan_dev"
            tc qdisc del dev "$wan_dev" root 2>/dev/null
        done < "$WORK_DIR/unique_devs_saved"
    fi
    
    # 清理工作目录
    rm -rf "$WORK_DIR"
    
    core_log_msg "INFO" "====== ipthrottle service stopped ======"
}

# 重新加载：先 stop 再 start
reload_service() {
    core_log_msg "INFO" "Reloading ipthrottle configuration"
    stop_service
    start_service
}

# ==========================================
# CLI 命令入口
# ==========================================

cmd_apply() {
    start_service
}

cmd_clear() {
    stop_service
}

cmd_reload() {
    reload_service
}

cmd_status() {
    echo "=== ipthrottle 服务状态 (hybrid mode) ==="
    
    echo "nftables 表:"
    if nft list table ip ipthrottle 2>/dev/null | head -3; then
        echo "  ✓ ipthrottle 表已加载"
    else
        echo "  ✗ ipthrottle 表未加载"
    fi
    
    # LAN 网桥（下载 tc）
    local lan_bridge
    lan_bridge=$(get_lan_bridge 2>/dev/null)
    echo ""
    echo "LAN 网桥 (下载TC): ${lan_bridge:-未检测到}"
    if [ -n "$lan_bridge" ]; then
        echo "  tc qdisc:"
        tc qdisc show dev "$lan_bridge" 2>/dev/null | grep -v "noqueue\|fq_codel" | head -5
    fi
    
    # WAN 设备（上传 tc）
    echo ""
    echo "WAN 设备 (上传TC):"
    local all_wans_file="$WORK_DIR/all_wans"
    if [ -f "$all_wans_file" ]; then
        while read -r wan_iface; do
            [ -z "$wan_iface" ] && continue
            local wan_dev
            wan_dev=$(get_wan_device "$wan_iface" 2>/dev/null) || continue
            echo "  $wan_iface → $wan_dev:"
            tc qdisc show dev "$wan_dev" 2>/dev/null | grep -v "noqueue\|fq_codel" | head -5
        done < "$all_wans_file"
    else
        echo "  服务未运行"
    fi
    
    echo ""
    echo "活跃规则:"
    prepare_rules 2>/dev/null
    if [ -s "$SORTED_RULES_FILE" ]; then
        while read -r _p _r; do
            local _mark_up _mark_down
            _mark_up=$(get_mark_for_rule "$_r")
            _mark_down=$(get_download_mark_for_rule "$_r")
            local _name
            _name=$(uci -q get ipthrottle."$_r".name)
            echo "  priority=$_p mark_up=$_mark_up mark_down=$_mark_down rule=$_r name=$_name"
        done < "$SORTED_RULES_FILE"
    else
        echo "  无活跃规则"
    fi
}
