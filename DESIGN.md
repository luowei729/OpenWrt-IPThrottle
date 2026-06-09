# OpenWrt-IPThrottle 插件完整设计文档

**版本**: v1.0  
**创建时间**: 2026-06-09 23:35:27 (北京时间)  
**最后更新**: 2026-06-09 23:35:27 (北京时间)

---

## 一、项目概述

OpenWrt IP 限速插件，运行于 OpenWrt 23.05+，提供 LuCI Web 控制页面。用户可配置内网 IP 限速规则，支持多 WAN、独立/共享限速、按周时间计划、优先级冲突处理。

---

## 二、核心技术栈

| 层级 | 技术选型 | 说明 |
|------|---------|------|
| **限速引擎** | tc + htb + ifb | Linux 原生流量控制 |
| **流量标记** | nftables (独立表) | 与 fw4 完全解耦 |
| **LuCI 前端** | luci.js (JavaScript) | 新版声明式 UI 框架 |
| **配置存储** | UCI | /etc/config/iptest |
| **包结构** | 单 package 标准布局 | files/ 镜像根目录 |
| **后端语言** | shell 脚本 | 轻量、无额外依赖 |
| **服务管理** | PROCD + hotplug | 标准 OpenWrt 服务生命周期 |
| **目标平台** | OpenWrt 23.05+ | fw4/nftables 时代 |

---

## 三、功能设计决策

### 3.1 限速模式实现

#### 独立限速
- **含义**: 规则内每个 IP 独立拥有带宽上限
- **tc 实现**: 规则父 class `rate=0` (无限), 每个 IP 子 class `rate=规则带宽, ceil=规则带宽`
- **效果**: 每个 IP 独享全速，3 个 IP 可同时满速下载

#### 共享限速
- **含义**: 规则内所有 IP 共享总带宽池
- **tc 实现**: 规则父 class `rate=总带宽, ceil=总带宽`, 每个 IP 子 class `rate=0` (无限)
- **效果**: tc htb 自然实现共享，所有 IP 加起来不超过总带宽

### 3.2 多 WAN 线路支持

#### WAN 发现机制
```shell
# 读取 firewall zone name=wan 的 list network
wan_zone_idx=$(uci -q show firewall | grep -E "zone.*\.name='wan'" | cut -d. -f2)
wan_ifaces=$(uci -q get firewall.@zone[$wan_zone_idx].network)
# 返回: wan wan2 wan6 等
```

#### wan_mask 存储格式
- **UCI 字段**: `option wan_mask 'all'` 或 `option wan_mask 'wan,wan2'`
- **含义**: 该规则作用于哪些 WAN 接口
- **后端处理**: 遍历 wan_mask 中每个接口名，在对应 WAN 接口上挂载 tc qdisc 层级

### 3.3 IP 冲突优先级策略

#### 规则定义
- **UCI 字段**: `option priority '10'` (整数 1-99)
- **默认值**: 按创建顺序自动递增 (10, 20, 30...)
- **行为**: 数值越小越优先，高优先级命中后停止继续匹配

#### 后端实现
- nftables: 按优先级排序后生成规则（priority 小的在前）
- tc filter: 使用 `handle <mark> classid <对应 class>` 映射
- 流量命中高优先级后，nftables 不再匹配后续规则（通过 mark 已设置标志位）

### 3.4 IP 地址存储

#### 取消分组概念
- **原计划**: 独立分组实体 + 规则引用分组
- **简化后**: 规则直接内嵌 IP 列表

#### UCI 存储方式
```uci
config rule
    list ip_entry '192.168.1.10'
    list ip_entry '192.168.1.11'
    list ip_entry '192.168.1.100-192.168.1.200'
```

#### 支持格式
- **单 IP**: `192.168.1.10`
- **IP 段**: `192.168.1.10-192.168.1.200` (用 `-` 分隔起止)
- **不支持 CIDR**: 简化实现，仅支持 `-` 语法

#### LuCI UI 组件
- **组件**: `form.DynamicList`
- **交互**: 自动 "+" 添加 / "-" 删除按钮，每行独立验证 IP 格式

### 3.5 生效时间周期

#### schedule_type 字段
- **always**: 全天生效
- **weekly**: 按周循环

#### schedule_json 格式
```json
[
  {"d": [1,2,3,4,5], "s": "09:00", "e": "18:00"},
  {"d": [0,6], "s": "10:00", "e": "14:00"}
]
```

**字段说明**:
- `d`: 星期数组，0=周日, 1=周一, ..., 6=周六
- `s`: 开始时间 HH:MM (24小时制)
- `e`: 结束时间 HH:MM (24小时制)
- 数组内多个对象是"或"关系 (并集)

#### LuCI UI 组件 (方案 B)
- schedule_type 用 `form.ListValue` (always/weekly)
- 选 weekly 时动态显示：
  - 7 个星期 checkbox (周一至周日)
  - 每个 checkbox 后跟时间范围输入框 (09:00-18:00)
- 前端自动生成 JSON 字符串

#### 触发机制
- **cron 每分钟评估**: 后台任务每分钟检查所有规则的 schedule_json
- 若当前时间状态变化 (生效↔失效)，触发全量 reload
- 精度为分钟级，完全匹配 schedule 的 HH:MM 粒度

### 3.6 上行限速实现

#### 技术原理
Linux tc 只能限速出口方向。入站限速需借助 IFB (Intermediate Functional Block) 设备。

#### 实现流程
```
1. nftables ingress hook 标记入站流量
   ↓
2. tc ingress qdisc + action mirred 重定向到 ifb 设备
   ↓
3. ifb 设备挂载 htb qdisc 做限速
```

#### WAN 与 IFB 映射
- 每个 WAN 接口对应 1 个 ifb 设备 (ifb0, ifb1, ...)
- 动态创建: `ip link add ifb0 type ifb`
- 挂载 ingress: `tc qdisc add dev $wan iface ingress` + `tc filter add dev $wan parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0`

---

## 四、tc + htb 层级树结构

### 4.1 五层架构

```
Root Qdisc (noqueue/ingress on eth1)
  └─ Root HTB Class (rate=WAN总带宽) [每个 WAN 接口 1 个]
      ├─ Priority Class 5 (rate=WAN总带宽)
      │   └─ Rule R1 Class (rate=0 for independent / rate=10Mbps for shared)
      │       ├─ IP 192.168.1.100 Class (rate=10Mbps, ceil=10Mbps)
      ├─ Priority Class 10 (rate=WAN总带宽)
      │   └─ Rule R2 Class (rate=5Mbps, ceil=5Mbps for shared)
      │       ├─ IP 192.168.1.10 Class (rate=0)
      │       ├─ IP 192.168.1.11 Class (rate=0)
      │       └─ ...
```

### 4.2 Class ID 分配策略

```
Root: 1:0
Priority 5: 1:500
Priority 10: 1:1000
Rule R1 (priority 5): 1:501
Rule R2 (priority 10): 1:1001
IP 192.168.1.10 (in R2): 1:1002
IP 192.168.1.11 (in R2): 1:1003
```

**算法**:
```shell
# priority class ID = base + priority * 100
priority_class_id() {
    local base=1
    local priority=$1
    echo "${base}:$(($priority * 100))"
}

# rule class ID = priority_class_id + rule_index
# IP class ID = priority_class_id + rule_index * 100 + ip_index
```

### 4.3 独立 vs 共享 rate 策略

#### 独立限速 (Independent)
```shell
# 父 class (规则)
tc class add dev ifb0 parent 1:1000 classid 1:1001 htb rate 0

# 子 class (每个 IP)
tc class add dev ifb0 parent 1:1001 classid 1:1002 htb rate 10mbit ceil 10mbit
```

#### 共享限速 (Shared)
```shell
# 父 class (规则)
tc class add dev ifb0 parent 1:1000 classid 1:1001 htb rate 5mbit ceil 5mbit

# 子 class (每个 IP)
tc class add dev ifb0 parent 1:1001 classid 1:1002 htb rate 0
```

---

## 五、nftables 链路设计

### 5.1 独立 iptest 表

```nft
table ip iptest {
    chain forward {
        type filter hook forward priority -1; policy accept;
        # 标记出站流量 (WAN -> 内网)
        # 按优先级排序生成规则
        ip saddr 192.168.1.100 meta mark set 0x1
        ip saddr 192.168.1.10-192.168.1.20 meta mark set 0x2
        # ...
    }
    
    chain ingress {
        type filter hook ingress priority -1; policy accept;
        # 标记入站流量 (内网 -> WAN)
        # 用于 IFB 设备限速
        ip daddr 192.168.1.100 meta mark set 0x1
        ip daddr 192.168.1.10-192.168.1.20 meta mark set 0x2
        # ...
    }
}
```

### 5.2 mark 分配策略

- **全局递增**: 按优先级排序后顺序编号 (1, 2, 3, ...)
- **不依赖 priority 数值**: 避免相同 priority 冲突
- **mark 空间**: 1-65535 (完全够用)

**分配算法**:
```shell
# 1. 读取所有 enabled=1 的规则
# 2. 按 priority 升序排序 (相同 priority 按 UCI 顺序稳定排序)
# 3. 依次分配 mark = 1, 2, 3, ...

parse_rules() {
    local mark=1
    for rule in $(uci -q show iptest | grep "=rule" | sort -t= -k2 -n); do
        local enabled=$(uci -q get iptest.$rule.enabled)
        [ "$enabled" = "1" ] || continue
        echo "mark=$mark rule=$rule"
        mark=$((mark + 1))
    done
}
```

### 5.3 tc filter 映射

```shell
# tc filter 按 mark 分流到对应 class
tc filter add dev ifb0 parent 1:0 protocol ip handle 0x1 fw classid 1:1002
tc filter add dev ifb0 parent 1:0 protocol ip handle 0x2 fw classid 1:1003
# handle 对应 mark，classid 对应 IP class
```

---

## 六、UCI 配置完整示例

```uci
# /etc/config/iptest

config rule
    option name '办公室普通'
    option wan_mask 'all'
    option proto 'tcp'
    option mode 'shared'
    option upload_kbps '512'
    option download_kbps '2048'
    option priority '10'
    option schedule_type 'weekly'
    option schedule_json '[{"d":[1,2,3,4,5],"s":"09:00","e":"18:00"}]'
    option comment '办公室工作日限速'
    option enabled '1'
    list ip_entry '192.168.1.10'
    list ip_entry '192.168.1.11'
    list ip_entry '192.168.1.100-192.168.1.200'

config rule
    option name '服务器'
    option wan_mask 'wan1'
    option proto 'any'
    option mode 'independent'
    option upload_kbps '5120'
    option download_kbps '10240'
    option priority '5'
    option schedule_type 'always'
    option comment '服务器独立高速'
    option enabled '1'
    list ip_entry '192.168.1.100'
```

---

## 七、项目文件结构

```
iptest/
├── Makefile                          # OpenWrt package build
├── files/
│   ├── etc/
│   │   ├── config/
│   │   │   └── iptest               # UCI 默认配置 (空模板)
│   │   ├── init.d/
│   │   │   └── iptest               # PROCD 服务脚本 (start/stop/restart/reload)
│   │   ├── hotplug.d/
│   │   │   └── iface/
│   │   │       └── 90-iptest        # 网络接口 up/down 事件处理
│   │   └── cron.d/
│   │       └── iptest               # 每分钟 schedule 评估任务
│   └── usr/
│       ├── lib/
│       │   └── iptest/
│       │       ├── core.sh          # 核心逻辑: 规则解析、tc/nft 命令生成
│       │       ├── wan.sh           # WAN 发现逻辑 (读取 firewall zone)
│       │       ├── schedule.sh      # 时间计划校验 (判断当前是否在生效时段)
│       │       └── ip.sh            # IP 地址解析 (单IP/IP段展开)
│       └── sbin/
│           └── iptest               # CLI 入口脚本 (调用 core.sh)
├── htdoc/
│   └── luci-static/
│       └── resources/
│           └── view/
│               └── iptest/
│                   ├── rules.js     # LuCI 规则列表页
│                   └── rule-edit.js # LuCI 规则编辑页
└── root/
    └── usr/
        ├── share/
        │   ├── luci/
        │   │   └── menu.d/
        │   │       └── luci-app-iptest.json  # LuCI 菜单注册
        │   └── rpcd/
        │       └── acl.d/
        │           └── luci-app-iptest.json  # LuCI ACL 权限
        └── libexec/
            └── rpcd/
                └── iptest           # UBUS RPC 后端 (可选, 用于动态数据查询)
```

---

## 八、实现阶段规划

### 阶段 1: 基础框架 (预计 2h)
- [ ] 创建 package 目录结构
- [ ] 编写 Makefile (PKG_NAME, PKG_VERSION, PKG_RELEASE, Build/Compile, Package/iptest)
- [ ] UCI 默认配置 (/etc/config/iptest 空模板)
- [ ] PROCD init 脚本骨架 (start_service, stop_service, reload_service)
- [ ] 验证: `/etc/init.d/iptest start` 能启动，`ps | grep iptest` 能看到 PROCD 进程

### 阶段 2: tc 核心逻辑 (预计 4h)
- [ ] WAN 发现脚本 (读取 firewall zone name=wan 的 list network)
- [ ] IFB 设备创建与挂载脚本 (ip link add ifbX type ifb)
- [ ] tc htb 层级树生成 (root → WAN → priority → rule → IP)
- [ ] 独立限速 vs 共享限速 rate 策略实现
- [ ] 验证: 手动执行 tc 命令，用 iperf3 测试限速生效

### 阶段 3: nftables 流量标记 (预计 3h)
- [ ] 自定义 nftables 表/链 (iptest forward/ingress)
- [ ] 按规则生成 nft match (src/dst IP, proto)
- [ ] mark 分配策略 (全局递增编号)
- [ ] tc filter 按 mark 分流到对应 class
- [ ] 验证: tcpdump 抓包显示 mark 值，流量正确命中 tc class

### 阶段 4: UCI 集成 (预计 2h)
- [ ] 读取 /etc/config/iptest (uci -q show iptest)
- [ ] 解析 list ip_entry (单IP/IP段展开函数 ip_range_expand)
- [ ] 解析 schedule_json (JSON 解析，提取 d/s/e)
- [ ] 优先级排序 (按 priority 字段排序，相同 priority 按 UCI 顺序稳定排序)
- [ ] 验证: UCI 配置正确映射到 tc/nft 命令

### 阶段 5: hotplug 响应 (预计 2h)
- [ ] 监听 iface up/down 事件 (hotplug.d/iface/90-iptest)
- [ ] 动态添加/移除 WAN 接口的 tc qdisc
- [ ] 验证: WAN 重新拨号后限速依然生效

### 阶段 6: LuCI 前端 (预计 6h)
- [ ] 规则列表页 (GridSection, 9 列表格，启用状态 toggle)
- [ ] 规则编辑页 (表单字段: name, wan_mask, ip_entry, proto, mode, rate, priority, schedule)
- [ ] IP 段动态添加 (form.DynamicList，自定义 IP 格式验证)
- [ ] 时间计划编辑器 (方案 B: 星期 checkbox + 时间范围输入)
- [ ] 实时验证 (IP格式, 范围合法性, priority 范围 1-99)
- [ ] 验证: 页面能创建/编辑/删除规则，数据正确写入 UCI

### 阶段 7: 测试与优化 (预计 3h)
- [ ] 边界情况测试 (超大 IP 段 192.168.0.1-192.168.255.254, 大量规则 100+)
- [ ] 性能测试 (1000+ IP 限速，CPU/内存占用)
- [ ] 错误处理 (非法配置, WAN 不存在, schedule_json 解析失败)
- [ ] 文档 (README, CHANGELOG, AGENTS.md 更新)

**总预计工时**: 22 小时

---

## 九、关键技术点实现

### 9.1 IP 段展开算法

```shell
# /usr/lib/iptest/ip.sh

# IP 转整数
ip_to_int() {
    local ip=$1
    local a b c d
    IFS='.' read -r a b c d <<< "$ip"
    echo $(( ($a << 24) + ($b << 16) + ($c << 8) + $d ))
}

# 整数转 IP
int_to_ip() {
    local int=$1
    echo "$(( ($int >> 24) & 0xFF )).$(( ($int >> 16) & 0xFF )).$(( ($int >> 8) & 0xFF )).$(($int & 0xFF))"
}

# 展开 IP 段
# 输入: "192.168.1.10-192.168.1.20"
# 输出: 每行一个 IP
ip_range_expand() {
    local range=$1
    local start_ip="${range%-*}"
    local end_ip="${range#*-}"
    
    local start_int=$(ip_to_int "$start_ip")
    local end_int=$(ip_to_int "$end_ip")
    
    if [ $start_int -gt $end_int ]; then
        logger -t iptest "ERROR: IP range start > end: $range"
        return 1
    fi
    
    local current=$start_int
    while [ $current -le $end_int ]; do
        int_to_ip $current
        current=$((current + 1))
    done
}
```

### 9.2 nftables mark 分配策略

```shell
# /usr/lib/iptest/core.sh

# 生成 nftables 规则
generate_nft_rules() {
    local mark=1
    
    # 1. 读取所有 enabled=1 的规则
    # 2. 按 priority 升序排序
    local rules=$(get_rules_sorted)
    
    for rule in $rules; do
        local enabled=$(uci -q get iptest.$rule.enabled)
        [ "$enabled" = "1" ] || continue
        
        local name=$(uci -q get iptest.$rule.name)
        local ip_entries=$(uci -q get iptest.$rule.ip_entry)
        
        # 展开每个 IP 条目
        for ip_entry in $ip_entries; do
            if echo "$ip_entry" | grep -q '-'; then
                # IP 段
                local ips=$(ip_range_expand "$ip_entry")
                for ip in $ips; do
                    echo "ip saddr $ip meta mark set $mark"
                done
            else
                # 单 IP
                echo "ip saddr $ip_entry meta mark set $mark"
            fi
        done
        
        mark=$((mark + 1))
    done
}
```

### 9.3 时间计划校验

```shell
# /usr/lib/iptest/schedule.sh

# 判断当前时间是否在 schedule_json 的生效范围内
schedule_active() {
    local json=$1
    local now_dow=$(date +%u)  # 1=Monday...7=Sunday
    local now_hhmm=$(date +%H:%M)
    
    # 解析 JSON (用 uci lua 或 jshn)
    # 遍历每个时间段
    # 检查 dow 和 hhmm 是否匹配
    
    # 伪代码
    for period in $json; do
        local days=$(echo $period | jq -r '.d[]')
        local start=$(echo $period | jq -r '.s')
        local end=$(echo $period | jq -r '.e')
        
        # 转换 0=周日 为 7 (适配 date +%u)
        days=$(echo "$days" | sed 's/0/7/g')
        
        # 检查今天是否匹配
        if echo "$days" | grep -qw "$now_dow"; then
            # 检查当前时间是否在范围内
            if [ "$now_hhmm" \> "$start" ] && [ "$now_hhmm" \< "$end" ]; then
                return 0  # 生效
            fi
        fi
    done
    
    return 1  # 不生效
}

# cron 调用的主函数
check_and_reload() {
    local need_reload=0
    
    local rules=$(uci -q show iptest | grep "=rule")
    for rule in $rules; do
        local schedule_type=$(uci -q get iptest.$rule.schedule_type)
        local schedule_json=$(uci -q get iptest.$rule.schedule_json)
        
        if [ "$schedule_type" = "weekly" ]; then
            if schedule_active "$schedule_json"; then
                # 检查上次状态
                local last_status=$(cat /tmp/iptest_$rule.status 2>/dev/null)
                if [ "$last_status" != "active" ]; then
                    need_reload=1
                    echo "active" > /tmp/iptest_$rule.status
                fi
            else
                local last_status=$(cat /tmp/iptest_$rule.status 2>/dev/null)
                if [ "$last_status" = "active" ]; then
                    need_reload=1
                    echo "inactive" > /tmp/iptest_$rule.status
                fi
            fi
        fi
    done
    
    if [ $need_reload -eq 1 ]; then
        /etc/init.d/iptest reload
    fi
}
```

---

## 十、错误处理策略

| 场景 | 处理方式 |
|------|---------|
| UCI 配置字段缺失/非法 | 跳过该规则，log 警告 (`logger -t iptest "WARN: ..."`), 继续加载其他规则 |
| IP 段 start > end | 跳过该 IP 条目，log 警告 |
| WAN 接口名不存在 | 跳过该规则，log 警告 |
| priority 重复 | 允许，按 UCI 顺序排序 (稳定排序) |
| schedule_json 解析失败 | 回退到 "always"，log 警告 |
| 规则 enabled=0 | 跳过，不加载 |
| tc 命令执行失败 | log 错误，不退出 (尽力加载其余规则) |
| reload 中途失败 | 保留旧规则，log 错误 (全量原子替换: 先构建新规则在临时表，成功后 swap，失败保持旧表) |

**原子 reload 实现**:
```shell
reload_service() {
    # 1. 生成新规则到临时表
    nft -f /tmp/iptest_new.nft || return 1
    
    # 2. 原子替换
    nft replace table ip iptest /tmp/iptest_new.nft
    
    # 3. 清理临时文件
    rm -f /tmp/iptest_new.nft
}
```

---

## 十一、依赖项

| 依赖 | 说明 |
|------|------|
| tc (iproute2) | OpenWrt 默认包含 |
| nftables | OpenWrt 23.05+ 默认包含 |
| procd | OpenWrt 默认包含 |
| firewall4 (fw4) | OpenWrt 23.05+ 默认包含 |
| luci-base | LuCI 基础库 |
| luci-mod-admin-full | 管理界面 |
| jq (可选) | JSON 解析 (若无则用 uci lua 或 jshn 替代) |

---

## 十二、测试计划

### 12.1 功能测试
- [ ] 单 IP 单规则限速 (独立/共享)
- [ ] IP 段限速 (192.168.1.10-192.168.1.20)
- [ ] 多 WAN 限速 (wan1 + wan2)
- [ ] 优先级冲突处理 (两条规则重叠 IP)
- [ ] 时间计划 (工作日 9-18 生效)
- [ ] LuCI 页面创建/编辑/删除规则

### 12.2 边界测试
- [ ] 超大 IP 段 (192.168.0.1-192.168.255.254, 65534 个 IP)
- [ ] 大量规则 (100+ 条)
- [ ] 非法配置 (IP 格式错误, priority 超出范围)
- [ ] WAN 接口名不存在

### 12.3 性能测试
- [ ] 1000+ IP 限速，CPU/内存占用
- [ ] tc 命令执行延迟
- [ ] LuCI 页面加载速度

### 12.4 稳定性测试
- [ ] WAN 重新拨号后限速依然生效
- [ ] 服务重启后规则自动恢复
- [ ] 长时间运行 (7 天) 无内存泄漏

---

## 十三、已知限制与未来扩展

### 已知限制
1. **不支持 CIDR**: 仅支持 `-` 语法 IP 段，不支持 192.168.1.0/24
2. **不支持端口匹配**: proto 字段仅区分 tcp/udp，不支持端口范围
3. **单规则单 WAN**: wan_mask 可多选，但 tc 层级在每个 WAN 独立，无法跨 WAN 共享带宽
4. **无实时统计**: 无法在 LuCI 查看每个 IP 实时流量 (需后续扩展 ucollect 或自定义 RPC)

### 未来扩展
1. 支持 CIDR 子网 (需修改 ip_range_expand 支持 / 语法)
2. 支持端口匹配 (nftables 规则增加 dport/sport 条件)
3. 实时流量统计 (tc -s class show, 定期采集存入 RRD)
4. 规则导入/导出 (JSON/CSV 格式)
5. 规则模板 (预设常用策略: 办公室/服务器/访客)

---

## 十四、参考资料

- OpenWrt 官方文档: https://openwrt.org/docs
- LuCI 开发文档: https://github.com/openwrt/luci/wiki
- tc (Traffic Control) HOWTO: http://tldp.org/HOWTO/Traffic-Control-HOWTO/
- htb (Hierarchical Token Bucket): http://luxik.cds.cz/~devik/qos/htb/manual/userg.htm
- nftables Wiki: https://wiki.nftables.org/
- IFB 设备: https://linuxfoundation.org/blog/using-ifb-device/

---

**文档结束**
