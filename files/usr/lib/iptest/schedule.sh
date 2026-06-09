#!/bin/sh
# ==========================================
# OpenWrt-IPThrottle 时间计划校验模块
# 文件: /usr/lib/iptest/schedule.sh
# 功能: 解析 schedule_json、判断当前时间是否在生效范围内
# 创建时间: 2026-06-09
# ==========================================

# 日志标签
IPT_SCHEDULE_LOG_TAG="iptest-schedule"

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
    
    # 去除前导零（避免 bash 认为是八进制）
    hours=$((10#$hours))
    minutes=$((10#$minutes))
    
    echo $(( hours * 60 + minutes ))
}

# 判断当前时间是否在时间范围内
# 参数: $1=开始时间 (HH:MM), $2=结束时间 (HH:MM)
# 返回: 0=在范围内, 1=不在
# 实现原因: schedule_json 中每个时间段包含 s(开始) 和 e(结束)，需要判断当前时刻是否命中
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

# 判断今天是星期几是否在星期列表中
# 参数: $1=星期列表字符串 (如 "1,2,3,4,5" 或 "0,6")
# 返回: 0=匹配, 1=不匹配
# 实现原因: schedule_json 中 d 字段是星期数组，需要判断今天是否生效
# 注意: date +%u 返回 1=周一...7=周日，但 schedule_json 中 0=周日，1-6=周一到周六
is_day_match() {
    local days_str="$1"
    
    # 获取今天是星期几 (1=周一...7=周日)
    local today
    today=$(date +%u)
    
    # 转换为 schedule_json 格式 (0=周日, 1=周一...6=周六)
    # date +%u: 1-6 对应 1-6, 7 对应 0
    if [ "$today" -eq 7 ]; then
        today=0
    fi
    
    # 检查 days_str 中是否包含今天
    # 使用逗号分隔，避免部分匹配 (如 1 匹配 10)
    echo ",$days_str," | grep -q ",$today,"
}

# 解析单个时间段 JSON 对象
# 参数: $1=JSON 字符串 (如 {"d":[1,2,3,4,5],"s":"09:00","e":"18:00"})
# 输出: 三个值 (days start_time end_time)，每行一个
# 返回: 0=成功, 1=解析失败
# 实现原因: OpenWrt 默认不含 jq，需要用 sed/awk 手动提取 JSON 字段
# 注意: 依赖 jshn 或 jsonfilter (OpenWrt 自带)
parse_schedule_period() {
    local period_json="$1"
    
    # 提取 d 字段 (星期数组)
    # 使用 jsonfilter 提取数组，转换为逗号分隔字符串
    local days
    days=$(echo "$period_json" | jsonfilter -e '@.d' 2>/dev/null)
    
    if [ -z "$days" ]; then
        schedule_log_msg "ERROR" "Cannot parse 'd' field from: $period_json"
        return 1
    fi
    
    # 提取 s 字段 (开始时间)
    local start_time
    start_time=$(echo "$period_json" | jsonfilter -e '@.s' 2>/dev/null)
    
    if [ -z "$start_time" ]; then
        schedule_log_msg "ERROR" "Cannot parse 's' field from: $period_json"
        return 1
    fi
    
    # 提取 e 字段 (结束时间)
    local end_time
    end_time=$(echo "$period_json" | jsonfilter -e '@.e' 2>/dev/null)
    
    if [ -z "$end_time" ]; then
        schedule_log_msg "ERROR" "Cannot parse 'e' field from: $period_json"
        return 1
    fi
    
    # 输出解析结果
    echo "$days"
    echo "$start_time"
    echo "$end_time"
}

# 判断当前时间是否在 schedule_json 的生效范围内
# 参数: $1=schedule_json 字符串 (数组格式)
# 返回: 0=生效, 1=不生效
# 实现原因: cron 每分钟调用此函数，判断规则是否应该生效
# 实现思路: 遍历 schedule_json 数组中的每个时间段，只要有一个匹配就返回 0
check_schedule_active() {
    local schedule_json="$1"
    
    # 空 JSON 表示不生效
    if [ -z "$schedule_json" ] || [ "$schedule_json" = "[]" ]; then
        return 1
    fi
    
    # 使用 awk 将 JSON 数组拆分为多个对象（每行一个）
    # 例如: [{"d":[1],"s":"09:00","e":"18:00"},{"d":[0],"s":"10:00","e":"14:00"}]
    # 转换为:
    #   {"d":[1],"s":"09:00","e":"18:00"}
    #   {"d":[0],"s":"10:00","e":"14:00"}
    local periods
    periods=$(echo "$schedule_json" | awk '{
        # 移除首尾的 [ 和 ]
        gsub(/^\[|\]$/, "")
        # 在每个 }, 后换行
        gsub(/\},\{/, "}\n{")
        print
    }')
    
    # 遍历每个时间段
    local period
    echo "$periods" | while IFS= read -r period; do
        # 跳过空行
        [ -z "$period" ] && continue
        
        # 解析时间段
        local parsed
        parsed=$(parse_schedule_period "$period") || continue
        
        # 提取解析结果（三行：days, start, end）
        local days start_time end_time
        days=$(echo "$parsed" | sed -n '1p')
        start_time=$(echo "$parsed" | sed -n '2p')
        end_time=$(echo "$parsed" | sed -n '3p')
        
        # 判断今天是否匹配
        if is_day_match "$days"; then
            # 判断当前时间是否在范围内
            if is_time_in_range "$start_time" "$end_time"; then
                # 匹配成功，返回 0
                exit 0
            fi
        fi
    done
    
    # 循环结束未匹配，返回 1
    return 1
}

# 检查规则是否应该生效（考虑 schedule_type）
# 参数: $1=rule section 名
# 返回: 0=应该生效, 1=不应该生效
# 实现原因: 规则的 schedule_type 可能是 "always" 或 "weekly"，需要分别处理
check_rule_should_active() {
    local rule="$1"
    
    # 读取 schedule_type
    local schedule_type
    schedule_type=$(uci -q get iptest."$rule".schedule_type)
    
    # "always" 或空值表示全天生效
    if [ -z "$schedule_type" ] || [ "$schedule_type" = "always" ]; then
        return 0
    fi
    
    # "weekly" 需要检查 schedule_json
    if [ "$schedule_type" = "weekly" ]; then
        local schedule_json
        schedule_json=$(uci -q get iptest."$rule".schedule_json)
        
        if check_schedule_active "$schedule_json"; then
            return 0
        else
            return 1
        fi
    fi
    
    # 未知类型，默认生效
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
#   3. 与上次状态（保存在 /tmp/iptest_<rule>.status）对比
#   4. 如果状态变化，记录到列表并更新状态文件
check_all_rules_status() {
    local changed=0
    local status_dir="/tmp/iptest_status"
    
    # 创建状态目录
    mkdir -p "$status_dir"
    
    # 遍历所有规则
    local config
    for config in $(uci -q show iptest | grep '=rule$' | cut -d. -f2 | cut -d= -f1); do
        # 跳过 disabled 规则
        local enabled
        enabled=$(uci -q get iptest."$config".enabled)
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
