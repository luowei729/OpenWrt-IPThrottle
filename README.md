# OpenWrt IPThrottle 插件

OpenWrt IP 限速插件，支持按 IP/网段、协议、时间进行精细化带宽控制。

## 功能特性

- **多种限速模式**
  - 独立限速：每个 IP 独享指定带宽
  - 共享限速：多个 IP 共享总带宽

- **灵活的目标地址**
  - 单个 IP 地址
  - IP 网段（192.168.1.10-192.168.1.100）
  - 多目标组合

- **多 WAN 接口支持**
  - 自动发现所有 WAN 接口
  - 支持为不同 WAN 设置不同策略

- **协议过滤**
  - TCP / UDP / TCP+UDP / 全部

- **时间计划**
  - 24小时全天生效
  - 按周计划（支持多个时间段）

- **优先级管理**
  - 规则冲突时按优先级排序
  - 数字越小优先级越高

- **LuCI Web 界面**
  - 图形化规则管理
  - 实时状态监控

## 安装

### 方法一：通过 opkg 安装（推荐）

```bash
opkg update
opkg install luci-app-iptest
```

### 方法二：从源码编译

```bash
# 在 OpenWrt SDK 目录
git clone <this-repo> package/iptest
make package/iptest/compile V=s
```

### 方法三：手动安装

将文件复制到对应目录：
```bash
cp files/usr/lib/iptest/* /usr/lib/iptest/
cp files/usr/sbin/iptest /usr/sbin/
cp files/etc/init.d/iptest /etc/init.d/
cp files/etc/config/iptest /etc/config/
chmod +x /usr/lib/iptest/*.sh
chmod +x /usr/sbin/iptest
chmod +x /etc/init.d/iptest
```

## 配置说明

### UCI 配置文件

编辑 `/etc/config/iptest`：

```bash
config iptest
    option enabled '1'  # 启用插件

config rule 'example'
    option enabled '1'           # 启用此规则
    option name '示例规则'        # 规则名称
    option wan_mask 'all'        # WAN接口: all/wan1/wan2...
    list ip_entry '192.168.1.100'      # 单个IP
    list ip_entry '192.168.1.10-192.168.1.20'  # IP段
    option proto 'any'           # 协议: any/tcp/udp/tcp+udp
    option mode 'independent'    # 模式: independent(独立)/shared(共享)
    option upload_kbps '512'     # 上传限速 (KB/s)
    option download_kbps '2048'  # 下载限速 (KB/s)
    option priority '10'         # 优先级 (1-99, 越小越高)
    option schedule_type 'always' # 时间类型: always/weekly
    option schedule_json '[{"d":[1,2,3,4,5],"s":"09:00","e":"18:00"}]'
    option comment '工作日白天限速'
```

### 通过 LuCI 界面配置

1. 登录 OpenWrt Web 管理界面
2. 导航到 **服务** -> **IP限速**
3. 点击 **添加** 创建新规则
4. 配置规则参数并保存

## 使用示例

### 示例 1：限制单个设备的上传速度

```bash
config rule 'limit_upload'
    option enabled '1'
    option name '限制电脑上传'
    option wan_mask 'all'
    list ip_entry '192.168.1.100'
    option proto 'any'
    option mode 'independent'
    option upload_kbps '512'
    option download_kbps '10240'
    option priority '10'
    option schedule_type 'always'
```

### 示例 2：网段共享带宽

```bash
config rule 'shared_bandwidth'
    option enabled '1'
    option name '访客网络限速'
    option wan_mask 'wan1'
    list ip_entry '192.168.2.100-192.168.2.200'
    option proto 'any'
    option mode 'shared'
    option upload_kbps '1024'
    option download_kbps '4096'
    option priority '20'
    option schedule_type 'always'
```

### 示例 3：工作时间限速

```bash
config rule 'office_hours'
    option enabled '1'
    option name '工作时间限速'
    option wan_mask 'all'
    list ip_entry '192.168.1.0/24'
    option proto 'any'
    option mode 'independent'
    option upload_kbps '256'
    option download_kbps '1024'
    option priority '10'
    option schedule_type 'weekly'
    option schedule_json '[{"d":[1,2,3,4,5],"s":"09:00","e":"18:00"}]'
```

## 命令行操作

```bash
# 启动服务
/etc/init.d/iptest start

# 停止服务
/etc/init.d/iptest stop

# 重启服务
/etc/init.d/iptest restart

# 启用开机自启
/etc/init.d/iptest enable

# 查看状态
/etc/init.d/iptest status

# 手动应用规则
/usr/sbin/iptest apply

# 清除所有规则
/usr/sbin/iptest clear
```

## 工作原理

### 内核模块依赖

- `kmod-sched-core` - 流量控制核心
- `kmod-sched-htb` - HTB 令牌桶队列
- `kmod-sched-connmark` - 连接标记
- `kmod-nft-core` - nftables 防火墙

### 限速实现

插件使用 Linux 内核的 TC (Traffic Control) 和 HTB (Hierarchical Token Bucket) 算法实现精确的带宽控制：

1. **IP 解析**：将配置的 IP/网段展开为单个 IP 地址
2. **规则匹配**：使用 nftables 标记匹配的流量
3. **带宽控制**：通过 HTB 队列对标记流量进行限速
4. **优先级处理**：高优先级规则先匹配，避免冲突

## 故障排除

### 服务无法启动

```bash
# 检查错误日志
logread | grep iptest

# 检查依赖模块是否加载
lsmod | grep sch_htb

# 手动加载内核模块
modprobe sch_htb
```

### 规则不生效

```bash
# 查看当前应用的规则
cat /tmp/iptest_work/sorted_rules

# 检查 TC 队列状态
tc qdisc show

# 检查 nftables 规则
nft list ruleset | grep iptest
```

### LuCI 界面无法访问

```bash
# 重启 LuCI
/etc/init.d/uhttpd restart

# 检查文件权限
chmod 644 /www/luci-static/resources/view/iptest.js
chmod 644 /usr/share/luci/menu.d/iptest.json
```

## 技术细节

### 目录结构

```
/etc/
├── config/iptest          # UCI 配置文件
├── init.d/iptest         # 服务启动脚本
└── hotplug.d/iface/90-iptest  # 网络接口热插拔

/usr/
├── lib/iptest/
│   ├── core.sh           # 核心逻辑
│   ├── ip.sh             # IP 解析模块
│   ├── wan.sh            # WAN 发现模块
│   └── schedule.sh       # 时间计划模块
└── sbin/iptest           # CLI 工具

/www/luci-static/resources/view/
└── iptest.js             # LuCI 前端

/usr/share/luci/menu.d/
└── iptest.json           # LuCI 菜单配置
```

### 性能考虑

- **大量 IP**：建议每个规则不超过 256 个 IP，过多会影响性能
- **规则数量**：建议不超过 50 条规则
- **内存占用**：约 2-4 MB（取决于规则复杂度）
- **CPU 占用**：< 1%（空闲状态）

## 版本历史

- **v1.0.0** (2024)
  - 初始版本
  - 支持独立/共享限速
  - 多 WAN 接口支持
  - 时间计划功能
  - LuCI Web 界面

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 联系方式

如有问题或建议，请通过 GitHub Issues 反馈。
