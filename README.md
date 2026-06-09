# OpenWrt IP限速插件 (IPThrottle)

一个功能强大的OpenWrt IP限速插件，支持精确的带宽控制、多WAN接口、灵活的时间计划。

## 核心功能

### 精确限速控制
- **独立限速**：为每个IP分配独立的带宽上限
- **共享限速**：多个IP共享同一带宽池
- **精确控制**：支持上传和下载分别限速（KB/s）

### 灵活的规则配置
- **多目标支持**：
  - 单个IP地址
  - IP地址段（如 192.168.1.10-192.168.1.20）
  - 混合目标列表
- **协议过滤**：支持 TCP、UDP、任意协议
- **多WAN支持**：可为不同WAN接口设置不同规则

### 时间计划
- **24小时计划**：设置开始和结束时间
- **周循环**：支持工作日、周末或自定义星期组合
- **灵活组合**：可为不同星期设置不同时间段

### 优先级管理
- **规则优先级**：支持1-100的优先级设置
- **冲突解决**：自动处理IP冲突，优先匹配高优先级规则

## 系统要求

- **OpenWrt版本**：23.05及以上
- **架构支持**：所有OpenWrt支持的架构
- **必需依赖**：
  - tc (Traffic Control)
  - nftables
  - kmod-sched-core
  - kmod-sched-htb

## 安装方法

### 方法一：使用opkg安装（推荐）

```bash
opkg update
opkg install iptest
```

### 方法二：手动安装

```bash
# 下载最新的IPK包
wget https://github.com/your-repo/iptest/releases/latest/download/iptest_1.0.0_all.ipk

# 安装
opkg install iptest_1.0.0_all.ipk
```

### 方法三：源码编译

```bash
# 克隆源码
git clone https://github.com/your-repo/iptest.git

# 进入目录
cd iptest

# 编译（需要OpenWrt SDK环境）
make package/iptest/compile V=s
```

## 快速开始

### 1. 启动服务

```bash
/etc/init.d/iptest start
/etc/init.d/iptest enable
```

### 2. 访问Web界面

打开浏览器，访问：
```
http://192.168.1.1/cgi-bin/luci/admin/network/iptest
```

默认位置：**网络 - IP限速**

### 3. 创建第一条规则

1. 点击"添加新规则"
2. 填写规则信息：
   - **规则名称**：例如 "限制下载"
   - **WAN接口**：选择 wan1（或 all）
   - **IP地址**：输入 192.168.1.100
   - **下载限速**：输入 1024 (KB/s)
   - **上传限速**：输入 512 (KB/s)
   - **时间计划**：设置生效时间
3. 点击"保存并应用"

## 配置示例

### 示例1：限制单个设备

```json
{
  "name": "限制下载",
  "wan_mask": "wan1",
  "ip_entry": ["192.168.1.100"],
  "proto": "any",
  "mode": "independent",
  "upload_kbps": "512",
  "download_kbps": "1024",
  "priority": "10",
  "schedule_type": "weekly",
  "schedule_json": [{"d": [1,2,3,4,5], "s": "09:00", "e": "18:00"}],
  "comment": "工作时间限制下载",
  "enabled": "1"
}
```

### 示例2：限制IP段（共享限速）

```json
{
  "name": "网段限制",
  "wan_mask": "wan1",
  "ip_entry": ["192.168.1.50-192.168.1.100"],
  "proto": "any",
  "mode": "shared",
  "upload_kbps": "2560",
  "download_kbps": "5120",
  "priority": "20",
  "schedule_type": "always",
  "comment": "限制整个网段的总带宽",
  "enabled": "1"
}
```

## 配置参数详解

### 基本参数

| 参数名 | 类型 | 必填 | 说明 | 示例 |
|--------|------|------|------|------|
| name | string | 是 | 规则名称 | "下载限制" |
| wan_mask | string | 是 | WAN接口 | "wan1", "wan2", "all" |
| ip_entry | list | 是 | IP地址列表 | ["192.168.1.100"] |
| proto | string | 是 | 协议 | "any", "tcp", "udp" |
| mode | string | 是 | 限速模式 | "independent", "shared" |
| upload_kbps | integer | 是 | 上传限速(KB/s) | 512 |
| download_kbps | integer | 是 | 下载限速(KB/s) | 2048 |
| priority | integer | 否 | 优先级(1-100) | 10 |
| comment | string | 否 | 备注说明 | "工作时间限制" |
| enabled | string | 是 | 是否启用 | "1"(启用), "0"(禁用) |

### 时间计划参数

| 参数名 | 说明 | 示例 |
|--------|------|------|
| schedule_type | 时间类型 | "always"(全天), "weekly"(按计划) |
| schedule_json | 时间配置JSON | [{"d":[1,2,3,4,5], "s":"09:00", "e":"18:00"}] |

**schedule_json 格式详解**：
```json
[
  {
    "d": [1,2,3,4,5],
    "s": "09:00",
    "e": "18:00"
  }
]
```

- d：生效的星期（0=周日, 1=周一, ..., 6=周六）
- s：开始时间（24小时制）
- e：结束时间（24小时制）

## 命令行工具

### 基本操作

```bash
/etc/init.d/iptest start
/etc/init.d/iptest stop
/etc/init.d/iptest restart
/etc/init.d/iptest status
/etc/init.d/iptest enable
/etc/init.d/iptest disable
```

### 高级操作

```bash
/usr/sbin/iptest apply
/usr/sbin/iptest clear
/usr/sbin/iptest reload
/usr/sbin/iptest status
/usr/sbin/iptest schedule
```

## 故障排除

### 问题1：服务无法启动

```bash
# 检查依赖是否安装
opkg list-installed | grep -E "tc|nftables"

# 安装缺失的依赖
opkg install tc nftables kmod-sched-core kmod-sched-htb

# 查看启动日志
logread | grep iptest
```

### 问题2：LuCI界面找不到

```bash
# 重新安装LuCI组件
opkg install luci-app-iptest

# 重启Web服务器
/etc/init.d/uhttpd restart
```

### 问题3：规则不生效

```bash
# 确认服务正在运行
/etc/init.d/iptest status

# 检查规则是否正确加载
/usr/sbin/iptest status

# 查看nftables规则
nft list ruleset | grep iptest

# 查看tc队列
tc qdisc show

# 检查日志
logread | grep iptest
```

## 性能指标

### 支持的规则数量
- **推荐**：10-20条规则
- **最大**：50条规则（取决于路由器性能）

### 性能影响
- **CPU占用**： 2%（规则应用时）
- **内存占用**： 5MB
- **启动时间**： 3秒（20条规则）

### 限速精度
- **最小限速单位**：1 KB/s
- **时间计划精度**：1分钟
- **实际应用延迟**： 100ms

## 许可证

本项目采用 MIT 许可证
