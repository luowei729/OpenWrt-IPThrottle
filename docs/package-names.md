# OpenWrt 包名对照表

## tc (流量控制工具)

| 版本 | 包名 | 说明 |
|------|------|------|
| 23.05 | tc-tiny | 无 `tc` 包 |
| 24.10 | tc-tiny | 无 `tc` 包 |
| 25.12 | tc-tiny | 无 `tc` 包 |

**结论**: 所有版本统一使用 `tc-tiny`

## kmod (内核模块)

| 模块 | 包名 | 说明 |
|------|------|------|
| IFB 虚拟网卡 | kmod-ifb | 入站限速必需 |
| 流量调度 (htb等) | kmod-sched | 包含 htb/ingress/mirred 等 |
| 调度核心 | kmod-sched-core | tc 基础依赖 |

**结论**: 使用 `kmod-ifb` + `kmod-sched`

## nftables

| 版本 | 包名 |
|------|------|
| 23.05 | nftables |
| 24.10 | nftables |
| 25.12 | nftables |

## 更新日期

- 2026-06-10: 初始记录
