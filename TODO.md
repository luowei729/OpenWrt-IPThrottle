# OpenWrt IP限速插件开发进度

## 核心模块
- [x] 核心逻辑模块 (core.sh) - tc/nft 命令生成、服务控制
- [x] IP 地址解析模块 (ip.sh) - IP 格式验证、范围展开
- [x] WAN 接口管理模块 (wan.sh) - WAN 发现、带宽获取
- [x] 时间计划模块 (schedule.sh) - 时间条件判断

## 服务脚本
- [x] CLI 入口脚本 (/usr/sbin/ipthrottle)
- [x] PROCD 服务脚本 (/etc/init.d/ipthrottle)
- [x] Hotplug 脚本 (/etc/hotplug.d/iface/90-ipthrottle)
- [x] Cron 定时任务 (/etc/cron.d/ipthrottle)

## 配置文件
- [x] UCI 配置模板 (/etc/config/ipthrottle)
- [x] uci-defaults 初始化脚本 (/etc/uci-defaults/50-ipthrottle)

## LuCI 前端
- [x] 菜单配置 (luci-app-ipthrottle.json)
- [x] ACL 权限配置 (luci-app-ipthrottle.json)
- [x] 网页视图 (ipthrottle.js)

## 打包
- [x] Makefile 构建脚本

## 测试与文档
- [x] 语法验证脚本 (test.sh)
- [x] README.md 使用文档
- [x] CHANGELOG.md 变更记录
