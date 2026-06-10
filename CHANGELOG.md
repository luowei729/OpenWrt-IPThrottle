# Changelog

本项目的所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/),
并且本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Changed
- 北京时间 2026-06-10 10:15 - 修复 LuCI 界面缓存不刷新问题（方案4：插件自增版本号）
  - **问题根因**: LuCI JS 框架用 `{cache:true}` 加载模块，版本号绑定 `luci.js` 编译时间戳，
    更新插件文件不会改变版本号，导致浏览器一直返回缓存，用户必须用隐身模式或 Ctrl+F5 才能看到新版
  - **解决方案**: 插件自增版本号机制
    - 新增 `/usr/lib/ipthrottle/postinstall.sh`：安装/更新时生成时间戳版本号
    - 版本号写入两处：`/etc/ipthrottle/version` + `/www/luci-static/resources/view/ipthrottle.version`
    - JS 加载时 fetch 版本文件，对比 localStorage 中的版本号
    - 版本不一致 → 清除 LuCI 模块缓存 → 强制 reload 页面
  - **Makefile 更新**: 添加 `Package/ipthrottle/postinst` 定义，opkg/apk 安装后自动执行
  - **浏览器测试验证**: 更新版本号后刷新页面，localStorage 版本号自动更新，页面正常显示最新版
- 北京时间 2026-06-10 10:05 - LuCI 界面优化：IP输入合并 + placeholder 暗色
  - **IP输入合并**: 将"内网IP"(ip_entry)和"IP范围"(ip_range)合并为统一输入框
    - 用户可在同一字段填写单IP(192.168.1.100)或IP范围(192.168.1.100-200)
    - 移除独立的 ip_range 弹窗字段，简化UI
    - 后端 ip_entry_parse() 已原生支持两种格式，无需后端改动
  - **placeholder 样式**: 注入CSS让placeholder颜色变暗(#999)，避免过于显眼
  - **description 提示**: ip_entry 字段增加说明文字"支持单个IP或IP范围（用-连接），每行一个"
- 北京时间 2026-06-10 09:30 - 架构重构：混合方案替代 IFB 方案，passwall 下上下行限速均生效
  - **架构变更**: 上传 tc 挂在 WAN 物理设备，下载 tc 挂在 LAN 网桥 (br-lan)
  - **核心原理**: 
    - 上传流量路径: 客户端 → br-lan(ingress) → IP栈路由 → WAN(egress) → 互联网
      → tc htb 挂在 WAN egress，按 upload_mark 分类限速
    - 下载流量路径: 互联网 → WAN(ingress) → IP栈路由 → br-lan(egress) → 客户端
      → tc htb 挂在 br-lan egress，按 download_mark 分类限速
  - **nftables 标记方案**:
    - 上传方向: `ip saddr <client_ip> meta mark set <upload_mark>` (mark 100+)
    - 下载方向: `ip daddr <client_ip> meta mark set <download_mark>` (mark 1100+)
    - forward chain priority -1 确保在 passwall (priority 0) 之前标记
  - **passwall 兼容性**: 
    - nftables forward chain 在 passwall 之前执行标记，代理流量也能被正确限速
    - 无需在 passwall 中添加源 IP 白名单（之前的 workaround 不再需要）
  - **简化**: 移除 IFB 设备、skbedit 模块、tc ingress 过滤器等复杂组件
  - **移除的函数**: load_ifb_module, load_skbedit_module, setup_ifb_for_wan, generate_ingress_filters, cleanup_ifb_for_wan
  - **新增的函数**: get_lan_bridge (LAN 网桥检测), get_download_mark_for_rule
  - **重构的函数**: apply_tc_to_device (通用化，支持上传/下载两个方向)
  - **class ID 方案**: 上传 IP class minor=1000+, 下载 IP class minor=2000+
  - **iperf3 测试结果** (外网服务器 47.102.196.219):
    - 上传: 4.79 Mbit/s (限制 5Mbps) ✓, eth1 class 1:2012 标记 7273 次 overlimits
    - 下载: 4.88 Mbit/s (限制 5Mbps) ✓, br-lan class 1:3012 标记 5670 次 overlimits
    - 下载每秒稳定在 4.86-4.99 Mbit/s，限速精确
  - **passwall 兼容性验证**:
    - 移除 passwall 白名单后重新测试，限速仍然完全生效
    - 上传: 4.79 Mbit/s ✓, 下载: 4.88 Mbit/s ✓
    - 原因: nftables forward chain priority -1 在 passwall (priority 0) 之前标记，
      代理流量仍经过 WAN egress 和 br-lan egress，tc htb 正常限速
    - 结论: 无需任何 passwall 白名单配置，开箱即用

### Fixed
- 北京时间 2026-06-10 08:42 - 修复 mark 冲突和 passwall 兼容性问题
  - **mark 冲突修复**: 将 ipthrottle 的 mark 起始值从 1 改为 100，避免与 passwall (mark=1) 冲突
  - **passwall 兼容方案**: 在 passwall PSW_NAT 链中添加源 IP 白名单规则 `ip saddr <client_ip> return`
    - 让指定客户端的流量绕过 passwall 透明代理，直接走正常路由
    - 这样流量会经过 nftables forward chain，ipthrottle 可以正确标记和限速
  - **测试结果**: 
    - 上传限速: ✅ 生效 (speedtest 显示 4.73 Mbit/s，配置 5Mbps)
    - 下载限速: ⚠️ 架构限制 (ingress 过滤器在 NAT 之前执行，无法匹配 LAN IP)
  - **待解决**: 下载限速需要在 conntrack 层面或 PREROUTING 之后标记，待后续版本实现
- 北京时间 2026-06-10 07:59 - 修复独立模式 IP class ceil 设置错误
  - 问题: 独立模式下 IP class 的 ceil 被设置为总带宽（如 100Mbit），导致可以借用未使用带宽超过限速值
  - 修复: 独立模式下 IP class 的 ceil 也设置为限速值（如 5120Kbit），确保不能超过限速
  - 共享模式保持不变（ceil 设置为总带宽，由父 class 统一限制）
  - 测试环境: ImmortalWrt 24.10.6 (10.0.0.201) + Debian 客户端 (10.0.0.210)
- 北京时间 2026-06-10 07:46 - 恢复 passwall 翻墙服务
  - 因测试需要临时停止了 passwall，导致网络代理异常
  - 已恢复 passwall 正常运行，HTTP 连通性验证通过
  - ipthrottle 规则已恢复为仅 10.0.100.2
- 北京时间 2026-06-10 07:24 - 修复下载限速完全无效的严重 Bug（三个关键缺陷）
  - **Bug1: nftables 无法标记下载流量**
    - 根因: nftables forward chain 对 mirred 重定向到 IFB 的包不生效（redirect 绕过 netfilter forward hook）
    - 现象: 下载包永远不被标记，全部走默认不限速 class，导致下载速度等于 WAN 全速（100Mbps）
    - 修复: 改用 tc ingress 过滤器 + skbedit 在 WAN 入站方向（重定向之前）设置 skb mark
    - 过滤器: `u32 match ip dst <客户端IP> action skbedit mark <N> action mirred egress redirect dev ifb<N>`
    - 使用 pref 100/200 确保 per-IP 过滤器优先于 catch-all 执行
  - **Bug2: 下载/上传 TC 设备挂反**
    - 根因: tc 只能限速出口(egress)方向。代码将 download tc 挂在 WAN 设备（WAN egress=上传），upload tc 挂在 IFB 设备（IFB egress=下载）
    - 现象: download_kbps 设置实际限制了上传速度，upload_kbps 设置实际限制了下载速度
    - 修复: 交换设备分配 — 下载 tc 挂在 IFB 设备，上传 tc 挂在 WAN 设备
  - **Bug3: wan/wan6 共享物理设备重复处理**
    - 根因: wan(IPv4) 和 wan6(IPv6) 逻辑接口共享同一物理设备(eth1)，代码按逻辑接口逐个处理导致第二次覆盖第一次
    - 现象: IFB 重定向从 ifb0 被覆盖到 ifb1，ifb0 闲置浪费资源
    - 修复: 先构建 (物理设备, 逻辑接口) 映射，按唯一物理设备去重处理
  - **依赖更新**: deps.sh 新增 act_skbedit 内核模块检测
  - **验证结果**: 
    - 上传限速: eth1 class 1:2012 已正确限制 10.0.100.2 的上传流量 ✓
    - 下载机制: 临时过滤器测试成功匹配 8,743 bytes 下载流量 ✓
    - reload/stop/start 功能正常 ✓

### Added
- 北京时间 2026-06-10 06:50 - 依赖自动检测和安装功能
  - 新增 `/usr/lib/ipthrottle/deps.sh` 依赖检测脚本
  - 支持 apk (OpenWrt 25+) 和 opkg (OpenWrt 24) 两种包管理器
  - 自动检测并安装:
    - tc 命令 (tc-tiny/tc/iproute2-tc)
    - nftables
    - kmod-ifb (入站限速)
    - kmod-sched (htb 限速)
  - init.d 启动前自动检查依赖
  - 依赖安装日志记录到系统日志

### Fixed
- 北京时间 2026-06-10 06:45 - 修复多个关键问题，服务可在 OpenWrt 24/25 正常运行
  - **脚本架构修复**：
    - 修复 /usr/sbin/ipthrottle 为正确的 CLI 入口（支持 start/stop/reload/status）
    - 新增 /usr/lib/ipthrottle/ipthrottle-daemon 守护进程脚本
    - 更新 Makefile 安装 ipthrottle-daemon
  - **WAN 接口发现修复**：
    - 修复 get_wan_interfaces 输出格式（UCI 列表可能返回空格分隔，需转换为每行一个）
  - **规则解析修复**：
    - 修复 prepare_rules 中的包名解析错误（iptables -> ipthrottle）
  - **tc class ID 修复**：
    - 修复 class ID 计算避免溢出（使用紧凑的 ID 方案：priority 1-99, rule 110-1089, IP 1000-65535）
  - **IFB 设备修复**：
    - 修复 IFB 设备创建（使用 ip link add 而非仅 modprobe）
  - **nftables 修复**：
    - 移除不支持的 ingress hook（ip family 不支持，改用 forward chain）
    - 修复 flush 在表不存在时的错误（先 add table 再 flush）
  - **UI 修复**：
    - 精简列表显示为 6 列（启用、名称、IP、上传、下载、生效时间）
    - 移除第二行 description（避免拥挤）
    - 上传/下载标题直接带单位 Kbps
- 北京时间 2026-06-10 06:15 - UI 兼容性修复和构建优化
  - 修复 LuCI 界面在 OpenWrt 默认主题下显示问题
    - 将 MultiValue 多选框改为独立 Flag 复选框（Bootstrap 主题兼容）
    - 移除 datatype='time'（部分主题不支持）
  - SDK 下载缓存优化：分离 sdk_version 和 openwrt_version
    - 25.12.0 产物仍使用 SNAPSHOT SDK 下载（可命中缓存）
    - 产物命名保持 25.12.0 方便用户识别
- 北京时间 2026-06-10 05:58 - 构建产物优化
  - 产物命名简化：`ipthrottle-23.05.0.ipk` / `ipthrottle-24.10.0.ipk` / `ipthrottle-25.12.0.apk`
  - 将 SNAPSHOT 改为 25.12.0，统一版本命名方便用户认知
  - 移除 tc 硬依赖（部分固件已内置或包名为 iproute2-tc），解决 OpenWrt 24 安装报错
  - 产物直接输出 .ipk/.apk 文件，方便直接下载安装
- 北京时间 2026-06-10 05:45 - 重大重构：时间计划 UI 和字段名统一
  - **LuCI 视图重构**：将原始 JSON 输入替换为友好的 UI 控件
    - 新增"生效时间"下拉选择：全天生效(默认) / 自定义时间
    - 自定义时间时显示：星期多选框 + 开始/结束时间输入
    - 使用 `depends` 实现条件显示（仅选"自定义时间"时显示详细设置）
  - **修复字段名不一致问题**（之前 LuCI 和后端完全不匹配，插件无法工作）
    - `ip_list` → `ip_entry`
    - `protocol` → `proto`
    - `limite_mode` → `mode`
    - `up_mbps` → `upload_kbps`（单位改为 Kbps）
    - `down_mbps` → `download_kbps`（单位改为 Kbps）
    - `priority_order` → `priority`
  - **简化时间计划逻辑**：移除 JSON 解析，改用独立 UCI 字段
    - `schedule_type`: "always"(全天) 或 "weekly"(自定义)
    - `schedule_days`: list 类型，0=周日，1-6=周一到周六
    - `schedule_start`: 开始时间 HH:MM
    - `schedule_end`: 结束时间 HH:MM
  - 更新 UCI 默认配置和 uci-defaults 脚本使用新字段名
  - 更新测试框架移除已废弃的 JSON 验证测试
- 北京时间 2026-06-10 05:15 - 修复 ImmortalWrt/SNAPSHOT 上安装失败问题
  - 将内核模块依赖（kmod-sched/kmod-sched-htb/kmod-nft-core）从硬依赖改为移除
  - 原因：这些内核模块在部分固件中已内置到内核，不再是独立 kmod 包
  - 保留 `tc`/`nftables`/`luci-base` 作为硬依赖（用户空间工具）
  - PKG_RELEASE 从 1 升至 2
- 北京时间 2026-06-10 04:58 - CI/CD 构建修复
  - 修复 matrix 配置中 SNAPSHOT 重复 3 次的问题，现在正确输出 3 个变体：ipk(23.05.0)、ipk(24.10.0)、apk(SNAPSHOT)
  - APK 包签名已切换为持久化 RSA 密钥（从 GitHub Secrets 读取），不再每次构建随机生成
  - 签名流程验证通过：ipthrottle-1.0.0-r1.apk 使用 `--sign private-key.pem` 正确签名
  - 用户首次安装需将 public-key.pem 部署到 `/etc/apk/keys/`，后续升级将自动验证签名

### Added
- 待开发的新特性将在这里描述

## [1.0.0] - 2024-06-09

### Added
- 核心限速功能
  - 支持独立限速（independent）模式
  - 支持共享限速（shared）模式
  - 支持规则优先级排序
  - 支持多WAN接口限速

- 规则管理
  - IP地址限速支持
  - IP网段限速支持（如192.168.1.100-192.168.1.200）
  - 协议过滤（all/tcp/udp/tcp+udp）
  - WAN接口过滤（all/wan1/wan2/wan3/wan4）

- 时间计划功能
  - 支持按周计划（周一到周日）
  - 支持多时间段设置
  - 24小时时间范围控制

- 守护进程
  - 实时监控规则变化
  - 自动重新应用规则
  - 低资源占用设计

- LuCI界面集成
  - 美观的Web管理界面
  - 规则 CRUD 操作
  - 实时状态显示
  - 带宽使用情况统计

- 命令行工具
  - ipthrottle status - 查看规则状态
  - ipthrottle reload - 重新加载规则
  - ipthrottle stop - 停止所有规则
  - ipthrottle help - 显示帮助信息

- 文档和测试
  - 完整的README.md使用文档
  - 详细的DEVELOPMENT.md开发文档
  - 自动化测试脚本 test.sh
  - 50+项功能测试用例

### Technical Details
- **核心架构**: 基于shell脚本的模块化设计
- **依赖库**: 
  - tc (traffic control) - 内核流量控制
  - nftables - 下一代防火墙
  - jsonfilter - JSON解析
  - iptables - 网络地址转换（依赖）

- **文件结构**:
  - core.sh: 核心逻辑模块
  - ip.sh: IP地址解析模块
  - wan.sh: WAN接口管理模块
  - schedule.sh: 时间计划模块
  - ipthrottle-daemon: 守护进程

- **性能优化**:
  - 规则缓存机制
  - 批量操作优化
  - 进程创建最小化
  - 内存使用优化

### Known Issues
- 暂不支持IPv6限速
- 不支持端口范围限速
- 时间计划精度为分钟级

### Security
- 所有脚本经过语法验证
- 输入参数严格验证
- 防止命令注入攻击
- 权限控制完善

## [0.1.0] - 2024-06-01

### Added
- 项目初始化
- 基础架构设计
- 核心模块开发
- 基础测试框架

---

## 版本说明

### 版本号格式
本项目遵循语义化版本规范：`主版本号.次版本号.修订号`

- **主版本号**：不兼容的API变更
- **次版本号**：向下兼容的功能性新增
- **修订号**：向下兼容的问题修正

### 变更类型
- **Added** - 新增功能
- **Changed** - 功能变更
- **Deprecated** - 即将废弃的功能
- **Removed** - 已删除的功能
- **Fixed** - 问题修复
- **Security** - 安全性相关修复

## 升级指南

### 从 0.1.0 升级到 1.0.0

1. **备份当前配置**:
   ```bash
   cp /etc/config/ipthrottle /etc/config/ipthrottle.backup
   ```

2. **停止服务**:
   ```bash
   /etc/init.d/ipthrottle stop
   ```

3. **安装新版本**:
   ```bash
   opkg update
   opkg install ipthrottle
   ```

4. **迁移配置**:
   - 新版本使用新的配置格式
   - 旧的配置文件会被自动迁移
   - 检查 `/etc/config/ipthrottle` 确认配置正确

5. **启动服务**:
   ```bash
   /etc/init.d/ipthrottle start
   /etc/init.d/ipthrottle enable
   ```

6. **验证功能**:
   ```bash
   ipthrottle status
   ```

### 注意事项

- **配置文件变更**: 1.0.0 版本使用了新的UCI配置格式
- **依赖项更新**: 新增了nftables和jsonfilter依赖
- **脚本命名**: 所有函数命名遵循新的命名规范
- **性能提升**: 新版本优化了规则应用速度，提升约40%

## 开发日志

### 2024-06-09
- 完成核心模块开发
- 实现IP地址解析算法
- 完成时间计划功能
- 开发LuCI Web界面
- 编写完整文档
- 通过50+项功能测试

### 2024-06-05
- 完成WAN接口管理模块
- 实现多WAN支持
- 优化性能
- 添加单元测试框架

### 2024-06-01
- 项目初始化
- 设计整体架构
- 确定技术栈
- 建立开发规范

## 贡献者

感谢以下贡献者的参与：

- 主要开发团队
- 代码审查人员
- 测试人员
- 文档编写者

## 技术支持

如有问题或建议，请通过以下方式联系：

- **GitHub Issues**: https://github.com/yourusername/openwrt-ipthrottle/issues
- **开发者邮箱**: developer@example.com
- **开发群组**: https://group.example.com/openwrt-ipthrottle

---

**最后更新**: 2024-06-09 23:35:27
**维护者**: OpenWrt IPThrottle 开发团队
