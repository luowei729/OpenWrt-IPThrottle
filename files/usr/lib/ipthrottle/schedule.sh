#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle 时间计划校验模块
# 文件: /usr/lib/ipthrottle/schedule.sh
# 功能: 读取 UCI 中的 schedule_type/schedule_days/schedule_start/schedule_end
#       判断当前时间是否在生效范围内
# 创建时间: 2026-06-09
# 修改时间: 2026-06-10 (简化为独立字段，移除 JSON 解析)
# ==========================================

# 日志标签
IPT_SCHEDULE_LOG_TAG="ipthrottle-schedule"

# 记录日志
# 参数: $1=日志级别, $2=日志消息
schedule_log_msg() {
    logger -t "$IPT_SCHEDULE_LOG_TAG" "$1: $2"
}

# 将 HH:MM 格式转换为分钟数（从 00:00 开始）
# 参数: $1=时间字符串 (如 "09:30")
# 返回: 分钟数 (如 570)
# 实现原因: 比较两个时间需要统一为数值，分钟数便于大小比较
time_to_minutes() {
    local time_str="$1"
    local hours="${time_str%:*}"
    local minutes="${time_str#*:}"
    
    # 去除前导零（避免 shell 认为是八进制）
    hours=$((10#$hours))
    minutes=$((10#$minutes))
    
    echo $(( hours * 60 + minutes ))
}

# 判断当前时间是否在时间范围内
# 参数: $1=开始时间 (HH:MM), $2=结束时间 (HH:MM)
# 返回: 0=在范围内, 1=不在
# 实现原因: 需要判断当前时刻是否在用户设定的开始和结束时间之间
# 支持跨午夜场景（如 22:00-06:00）
is_time_in_range() {
    local start_time="$1"
    local end_time="$2"
    
    # 获取当前时间 (HH:MM 格式)
    local now
    now=$(date +%H:%M)
    
    # 转换为分钟数进行比较
    local now_min start_min end_min
    now_min=$(time_to_minutes "$now")
    start_min=$(time_to_minutes "$start_time")
    end_min=$(time_to_minutes "$end_time")
    
    # 判断是否在范围内 (支持跨午夜，如 22:00-06:00)
    if [ "$start_min" -le "$end_min" ]; then
        # 正常情况: start <= now < end
        [ "$now_min" -ge "$start_min" ] && [ "$now_min" -lt "$end_min" ]
    else
        # 跨午夜: start <= now 或 now < end
        [ "$now_min" -ge "$start_min" ] || [ "$now_min" -lt "$end_min" ]
    fi
}

# 判断今天是星期几是否在 schedule_days 列表中
# 参数: $1=rule section 名
# 返回: 0=匹配, 1=不匹配
# 实现原因: LuCI 使用独立的 Flag 字段存储每天（schedule_day_mon/tue/wed/thu/fri/sat/sun）
# 后端将这些 Flag 合并判断今天是否生效
# 注意: date +%u 返回 1=周一...7=周日
is_today_in_schedule_days() {
    local rule="$1"
    
    # 获取今天是星期几 (1=周一...7=周日)
    local today
    today=$(date +%u)
    
    # 映射到 UCI 字段名
    # date +%u: 1=周一 → schedule_day_mon
    #           2=周二 → schedule_day_tue
    #           3=周三 → schedule_day_wed
    #           4=周四 → schedule_day_thu
    #           5=周五 → schedule_day_fri
    #           6=周六 → schedule_day_sat
    #           7=周日 → schedule_day_sun
    local day_field=""
    case "$today" in
        1) day_field="schedule_day_mon" ;;
        2) day_field="schedule_day_tue" ;;
        3) day_field="schedule_day_wed" ;;
        4) day_field="schedule_day_thu" ;;
        5) day_field="schedule_day_fri" ;;
        6) day_field="schedule_day_sat" ;;
        7) day_field="schedule_day_sun" ;;
    esac
    
    # 从 UCI 读取对应的 Flag 值
    local day_enabled
    day_enabled=$(uci -q get ipthrottle."$rule"."$day_field")
    
    # 如果所有星期 Flag 都未设置或为空，表示不限制星期（每天都生效）
    # 检查是否有任何一天被启用
    local any_day_enabled=0
    for f in schedule_day_mon schedule_day_tue schedule_day_wed schedule_day_thu schedule_day_fri schedule_day_sat schedule_day_sun; do
        local val
        val=$(uci -q get ipthrottle."$rule"."$f")
        if [ "$val" = "1" ]; then
            any_day_enabled=1
            break
        fi
    done
    
    # 如果没有任何一天被启用，默认每天生效
    if [ "$any_day_enabled" -eq 0 ]; then
        return 0
    fi
    
    # 检查今天对应的 Flag 是否为 1
    if [ "$day_enabled" = "1" ]; then
        return 0
    else
        return 1
    fi
}

# 检查规则是否应该生效（根据 schedule_type 判断）
# 参数: $1=rule section 名
# 返回: 0=应该生效, 1=不应该生效
# 实现原因: 根据用户设置的 schedule_type 类型决定规则是否在当前时间生效
# UCI 字段说明:
#   schedule_type: "always"(全天生效，默认) 或 "weekly"(自定义时间)
#   schedule_days: list 类型，0=周日，1-6=周一到周六（仅 weekly 时有效）
#   schedule_start: 开始时间 HH:MM（仅 weekly 时有效，默认 00:00）
#   schedule_end: 结束时间 HH:MM（仅 weekly 时有效，默认 23:59）
check_rule_should_active() {
    local rule="$1"
    
    # 读取 schedule_type（默认 "always"）
    local schedule_type
    schedule_type=$(uci -q get ipthrottle."$rule".schedule_type)
    
    # "always" 或空值表示全天生效，无需检查时间
    # 实现原因: 大多数用户不需要时间限制，默认全天生效是最简单的配置
    if [ -z "$schedule_type" ] || [ "$schedule_type" = "always" ]; then
        return 0
    fi
    
    # "weekly" 需要检查星期和时间范围
    if [ "$schedule_type" = "weekly" ]; then
        # 第一步：检查今天是否在生效星期列表中
        if ! is_today_in_schedule_days "$rule"; then
            return 1
        fi
        
        # 第二步：检查当前时间是否在生效时间段内
        local start_time end_time
        start_time=$(uci -q get ipthrottle."$rule".schedule_start)
        end_time=$(uci -q get ipthrottle."$rule".schedule_end)
        
        # 如果开始/结束时间为空，使用默认值（全天）
        # 实现原因: 用户可能只设置了星期但没设置时间，默认全天生效
        [ -z "$start_time" ] && start_time="00:00"
        [ -z "$end_time" ] && end_time="23:59"
        
        if is_time_in_range "$start_time" "$end_time"; then
            return 0
        else
            return 1
        fi
    fi
    
    # 未知类型，默认生效（保守策略：宁可误生效也不要误停）
    schedule_log_msg "WARN" "Unknown schedule_type for rule $rule: $schedule_type"
    return 0
}

# 检查所有规则，返回需要 reload 的列表
# 输出: 每行一个 rule section 名
# 返回: 0=有变更, 1=无变更
# 实现原因: cron 脚本调用此函数，判断是否有规则状态变化（生效↔失效），有则触发 reload
# 实现思路: 
#   1. 遍历所有 enabled=1 的规则
#   2. 对每个规则，检查当前应该生效还是失效
#   3. 与上次状态（保存在 /tmp/ipthrottle_<rule>.status）对比
#   4. 如果状态变化，记录到列表并更新状态文件
check_all_rules_status() {
    local changed=0
    local status_dir="/tmp/ipthrottle_status"
    
    # 创建状态目录
    mkdir -p "$status_dir"
    
    # 遍历所有规则
    local config
    for config in $(uci -q show ipthrottle | grep '=rule$' | cut -d. -f2 | cut -d= -f1); do
        # 跳过 disabled 规则
        local enabled
        enabled=$(uci -q get ipthrottle."$config".enabled)
        [ "$enabled" = "1" ] || continue
        
        # 检查当前应该生效还是失效
        local should_active=0
        check_rule_should_active "$config" || should_active=1
        
        # 读取上次状态（0=生效, 1=失效, 空=首次）
        local status_file="$status_dir/$config"
        local last_status=""
        [ -f "$status_file" ] && last_status=$(cat "$status_file")
        
        # 首次检查，记录状态
        if [ -z "$last_status" ]; then
            echo "$should_active" > "$status_file"
            continue
        fi
        
        # 状态变化，需要 reload
        if [ "$last_status" != "$should_active" ]; then
            echo "$config"
            echo "$should_active" > "$status_file"
            changed=1
        fi
    done
    
    return $changed
}
