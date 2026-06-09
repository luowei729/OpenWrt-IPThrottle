# OpenWrt 包签名

## 整体流程

```
GitHub Actions 编译
        │
        ├─ 私钥（GitHub Secrets: OPENWRT_SIGN_KEY）
        │
        ▼
自动生成已签名的 ipk 包
        │
        │  .ipk + Packages.sig + index.json.sig
        │
        ▼
下载到 OpenWrt 设备
        │
        ▼
设备的 opkg 用公钥自动验证
        │
        ▼
安装成功 ✅
```

**设备端永远不需要做签名操作**，opkg 会自动用 `key-build.ucert` 验证签名的合法性。

## 文件说明

| 文件 | 作用 | 存放位置 |
|------|------|----------|
| `key-build` | 私钥，用于 Actions 编译时签名 | GitHub Secret `OPENWRT_SIGN_KEY` |
| `key-build.ucert` | 公钥，用于设备端验证签名 | 部署到 OpenWrt 设备 `/etc/opkg/keys/` |

## 配置 GitHub Secrets（已完成）

私钥已配置，Actions 每次 push 时会自动：
1. 编译 usign 工具
2. 用私钥对 ipk 进行签名
3. 上传产物（`ipthrottle_*.ipk` + `Packages.sig` + `index.json.sig`）

## 在设备上部署公钥（第一次安装需要做一次）

**公钥文件名必须是其指纹前 8 位字符**，opkg 靠这个定位公钥。

在 OpenWrt 设备上执行以下步骤：

```bash
# 第一步：确保设备上有 usign 工具
opkg update
opkg install usign

# 第二步：创建公钥目录（通常已存在）
mkdir -p /etc/opkg/keys

# 第三步：获取本仓库公钥的指纹（本机执行，非设备）
# cd /root/OpenWrt-IPThrottle
# usign -F -p .github/signing/key-build.ucert
# 输出类似：RWQ1M+ExKylSoh

# 第四步：将公钥证书复制到设备，重命名为指纹前8位
# 例如指纹是 RWQ1M+ExKylSoh...，则文件名为 RWQ1M+Ex
cp key-build.ucert /etc/opkg/keys/RWQ1M+Ex

# 完成！之后安装本项目的 ipk 包就可以直接通过签名验证
```

## 安装 ipk 包

从 Actions 下载 `ipthrottle_*.ipk` 后，直接安装即可：

```bash
opkg install ipthrottle_1.0.0-1_all.ipk
```

签名验证会自动在后台完成，无需任何手动签名操作。

## 常见错误

| 错误提示 | 原因 | 解决 |
|----------|------|------|
| `UNTRUSTED signature` | 公钥未部署到设备 | 按上面步骤部署 `key-build.ucert` |
| `Signature check failed` | 公钥指纹文件名不对 | 用 `usign -F` 重新获取正确的指纹 |
| `ipk: not found` | ipk 包未下载到设备 | 从 Actions 下载后手动复制到设备 |

## 安全说明

- ❌ `key-build`（私钥）**绝不能**进入 Git，已在 `.gitignore` 中排除
- ✅ `key-build.ucert`（公钥）可以公开分发，放在仓库里没有问题
- 🔑 如需更换密钥：删除旧公钥，重新生成密钥对，更新 GitHub Secret 并重新构建
