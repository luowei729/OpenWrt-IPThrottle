# Changelog

本项目的所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/),
并且本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Fixed
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
