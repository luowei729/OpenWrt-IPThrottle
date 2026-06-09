# IPThrottle 插件开发文档

## 项目结构

```
OpenWrt-IPThrottle/
├── files/                          # 目标系统文件
│   ├── usr/
│   │   ├── lib/
│   │   │   └── ipthrottle/            # 脚本库
│   │   │       ├── core.sh        # 核心逻辑
│   │   │       ├── ip.sh          # IP地址解析
│   │   │       ├── wan.sh         # WAN接口管理
│   │   │       ├── schedule.sh    # 时间计划
│   │   │       └── ipthrottle-daemon  # 守护进程
│   │   └── sbin/
│   │       └── ipthrottle             # 命令行工具
│   └── etc/
│       ├── config/
│       │   └── ipthrottle             # UCI配置
│       └── init.d/
│           └── ipthrottle             # 服务脚本
├── root/                           # 目标根目录
│   ├── usr/share/
│   │   ├── luci/
│   │   │   └── menu.d/            # LuCI菜单
│   │   └── rpcd/
│   │       └── acl.d/             # LuCI权限
│   └── www/
│       └── luci-static/
│           └── resources/view/    # LuCI视图
├── Makefile                        # 包构建文件
├── README.md                       # 项目说明
├── CHANGELOG.md                    # 变更日志
└── test.sh                         # 单元测试
```

## 核心模块

### 1. core.sh - 核心逻辑模块

负责限速规则的管理和应用。

**主要功能：**
- 管理限速规则
- 应用/删除内核规则
- 状态监控
- 规则优先级排序

### 2. ip.sh - IP地址解析模块

处理IP地址验证和范围解析。

**核心函数：**
- `validate_ip`: 验证单个IP地址
- `validate_ip_range`: 验证IP范围（如192.168.1.100-192.168.1.200）
- `ip_to_int`: 将IP地址转换为整数
- `int_to_ip`: 将整数转换为IP地址

**实现原理：**
```bash
# IP转整数算法
ip_to_int() {
    local IFS='.'
    read -r a b c d <<< "$1"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}
```

### 3. wan.sh - WAN接口管理模块

管理多WAN接口支持。

**主要功能：**
- 自动发现WAN接口
- 支持多个WAN接口
- 接口状态监控

### 4. schedule.sh - 时间计划模块

处理基于时间的限速规则。

**时间格式：**
- JSON数组格式：`[{"d":[1,2,3,4,5],"s":"09:00","e":"18:00"}]`
- `d`: 星期几（0=周日，1-6=周一到周六）
- `s`: 开始时间
- `e`: 结束时间

**核心算法：**
```bash
# 检查当前时间是否在计划内
is_time_in_range() {
    local start_hour=$(echo "$1" | cut -d: -f1)
    local start_min=$(echo "$1" | cut -d: -f2)
    local end_hour=$(echo "$2" | cut -d: -f1)
    local end_min=$(echo "$2" | cut -d: -f2)
    local current_hour=$(date +%H)
    local current_min=$(date +%M)
    
    local start=$((start_hour * 60 + start_min))
    local end=$((end_hour * 60 + end_min))
    local current=$((current_hour * 60 + current_min))
    
    [ $current -ge $start ] && [ $current -lt $end ]
}
```

## LuCI前端

### 菜单配置

**luci-menu.json:**
```json
{
    "admin/network/ipthrottle": {
        "title": "IP Throttle",
        "order": 50,
        "action": {
            "type": "view",
            "path": "ipthrottle"
        },
        "depends": {
            "acl": ["luci-app-ipthrottle"]
        }
    }
}
```

### Lua视图

**ipthrottle.lua** 提供：
- 规则列表显示
- 规则添加/编辑/删除
- 状态监控
- 带宽实时统计

## UCI配置格式

```
config global
    option enabled 0
    option default_upload 1024
    option default_download 4096

config rule
    option name 'RuleName'
    option enabled 1
    option priority 10
    option wan_mask 'all'
    option protocol 'all'
    option mode 'shared'
    option upload_mbps 100
    option download_mbps 500
    list ip_addr '192.168.1.100'
    option ip_range '192.168.1.1-192.168.1.254'
    option time_plan '[{"d":[1,2,3,4,5],"s":"09:00","e":"18:00"}]'
```

### 字段说明

- **enabled**: 0=禁用，1=启用
- **priority**: 1-99，数值越小优先级越高
- **wan_mask**: all|wan1|wan2|wan3|wan4
- **protocol**: all|tcp|udp|tcp+udp
- **mode**: shared(共享)|independent(独立)
- **upload_mbps/download_mbps**: 带宽限制（Mbps）
- **time_plan**: 时间计划JSON数组

## 开发规范

### 命名规范

1. **变量命名**: 使用小写字母和下划线
   - 正确: `wan_list`, `rule_count`
   - 错误: `WanList`, `ruleCount`

2. **函数命名**: 使用小写字母和下划线
   - 正确: `validate_ip()`, `get_wan_interfaces()`
   - 错误: `ValidateIP()`, `getWanInterfaces()`

3. **常量命名**: 使用大写字母和下划线
   - 正确: `MAX_PRIORITY`, `DEFAULT_BANDWIDTH`
   - 错误: `maxPriority`, `defaultBandwidth`

### 注释规范

1. **函数注释**: 每个函数必须有注释说明
```bash
# 功能：验证IP地址格式
# 参数：$1 - IP地址
# 返回：0=有效，1=无效
validate_ip() {
    ...
}
```

2. **复杂逻辑**: 必须说明实现原理
```bash
# 使用位运算将IP地址转换为整数
# 例如：192.168.1.100 -> 3232235876
ip_to_int() {
    ...
}
```

3. **模块头部**: 包含模块说明、作者、版本
```bash
#!/bin/sh
# IPThrottle IP地址解析模块
# 版本：1.0.0
# 作者：开发团队
# 功能：提供IP地址验证和范围解析功能
```

### 错误处理

1. **参数验证**: 所有函数必须验证参数
```bash
validate_ip() {
    local ip="$1"
    [ -z "$ip" ] && return 1
    ...
}
```

2. **错误返回**: 统一使用返回码
   - 0: 成功
   - 1: 失败
   - 2: 参数错误

3. **日志输出**: 使用logger记录错误
```bash
logger -t ipthrottle "ERROR: Invalid IP address: $ip"
```

### 性能优化

1. **避免重复执行**: 缓存计算结果
```bash
# 缓存WAN接口列表
wan_cache="/tmp/ipthrottle_wan_cache"
if [ ! -f "$wan_cache" ]; then
    get_wan_interfaces > "$wan_cache"
fi
wan_list=$(cat "$wan_cache")
```

2. **减少进程创建**: 使用shell内建命令
```bash
# 好：使用内建命令
count=${#array[@]}

# 差：创建子进程
count=$(echo "${#array[@]}")
```

3. **批量操作**: 减少循环次数
```bash
# 一次性处理多个IP
for ip in $ip_list; do
    process_ip "$ip"
done
```

## 测试指南

### 运行单元测试

```bash
./test.sh
```

### 测试内容

1. **模块文件测试**: 检查所有必需模块是否存在
2. **语法测试**: 检查所有脚本的语法是否正确
3. **功能测试**: 测试核心功能（IP验证、时间计划等）
4. **前端测试**: 检查LuCI文件是否存在
5. **配置测试**: 验证配置文件格式
6. **服务测试**: 检查服务脚本

### 添加新测试

在test.sh中添加测试函数：

```bash
test_my_feature() {
    log_info "测试新功能..."
    
    # 测试代码
    if [ condition ]; then
        log_pass "测试通过"
    else
        log_fail "测试失败"
    fi
}

# 在run_all_tests中调用
run_all_tests() {
    test_my_feature
    ...
}
```

## 构建和安装

### 构建步骤

1. **准备OpenWrt开发环境**:
```bash
# 克隆OpenWrt源码
git clone https://github.com/openwrt/openwrt.git
cd openwrt

# 更新feeds
./scripts/feeds update -a
./scripts/feeds install -a
```

2. **添加插件到package目录**:
```bash
# 将OpenWrt-IPThrottle目录复制到package/
cp -r OpenWrt-IPThrottle package/
```

3. **构建包**:
```bash
make package/ipthrottle/compile V=s
```

4. **找到生成的安装包**:
```bash
ls bin/packages/*/base/ipthrottle_*.ipk
```

### 安装到路由器

```bash
# 传输安装包到路由器
scp bin/packages/*/base/ipthrottle_*.ipk root@192.168.1.1:/tmp/

# SSH登录路由器
ssh root@192.168.1.1

# 安装
opkg update
opkg install /tmp/ipthrottle_*.ipk

# 启动服务
/etc/init.d/ipthrottle start
/etc/init.d/ipthrottle enable
```

## 常见问题

### 1. 脚本执行错误

**问题**: `syntax error: unexpected "("`

**原因**: 使用了bash特性但shebang是sh

**解决**: 确保所有脚本使用 `#!/bin/sh` 而不是 `#!/bin/bash`

### 2. LuCI界面不显示

**问题**: LuCI界面上看不到插件菜单

**原因**: 菜单配置文件格式错误或权限问题

**解决**:
```bash
# 检查JSON格式
python3 -m json.tool root/usr/share/luci/menu.d/luci-app-ipthrottle.json

# 重启LuCI
/etc/init.d/uhttpd restart
```

### 3. 服务无法启动

**问题**: `/etc/init.d/ipthrottle start` 无响应

**原因**: 守护进程依赖缺失或路径错误

**解决**:
```bash
# 检查依赖
opkg list-installed | grep -E "tc|nftables"

# 检查路径
ls -l /usr/lib/ipthrottle/
```

## 开发路线图

### 版本 1.1.0 计划

- [ ] 添加IPv6支持
- [ ] 支持端口范围限制
- [ ] 实时带宽监控图表
- [ ] 规则导入/导出功能
- [ ] 多用户支持

### 版本 2.0.0 计划

- [ ] 使用Python重写核心模块
- [ ] Web API接口
- [ ] 移动端App支持
- [ ] 云配置同步
- [ ] 智能推荐算法

## 贡献指南

### 代码提交流程

1. Fork项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建Pull Request

### 代码审查清单

- [ ] 代码符合命名规范
- [ ] 所有函数有详细注释
- [ ] 通过shellcheck检查
- [ ] 通过单元测试
- [ ] 更新CHANGELOG.md
- [ ] 更新相关文档

## 技术支持

- 项目地址: https://github.com/yourusername/openwrt-ipthrottle
- 问题反馈: 提交Issue
- 开发讨论: 加入开发群组

## 许可证

MIT License - 详见 LICENSE 文件

---

**最后更新**: 2024-06-09 23:35:27
**版本**: 1.0.0
