#!/bin/bash
# 生成 OpenWrt 包签名密钥对
# 使用方法: ./generate-keys.sh

set -e

echo "=== 生成 OpenWrt 包签名密钥 ==="

# 检查是否有 usign 工具
if command -v usign &> /dev/null; then
    USIGN=usign
elif [ -x "$HOME/openwrt-sdk/staging_dir/host/bin/usign" ]; then
    USIGN="$HOME/openwrt-sdk/staging_dir/host/bin/usign"
else
    echo "错误: 未找到 usign 工具"
    echo "请先编译一次 OpenWrt SDK 安装依赖，或手动安装 usign"
    exit 1
fi

# 生成私钥和公钥
echo "生成签名密钥对..."
$USIGN -G -s key-build -p key-build.pub

# 创建证书
echo "生成证书..."
$USIGN -C -s key-build -p key-build.pub > key-build.ucert

echo ""
echo "✅ 密钥生成完成！"
echo ""
echo "文件说明："
echo "  key-build      - 私钥（用于 Actions 编译签名）"
echo "  key-build.pub  - 公钥"  
echo "  key-build.ucert - 证书（需要安装到 OpenWrt 设备）"
echo ""
echo "下一步操作："
echo "1. 将 key-build 内容添加到 GitHub Secrets:"
echo "   仓库 Settings → Secrets → Actions → New repository secret"
echo "   Name: OPENWRT_SIGN_KEY"
echo "   Value: (粘贴 key-build 文件内容)"
echo ""
echo "2. 将证书安装到 OpenWrt 设备:"
echo "   复制 key-build.ucert 到设备的 /etc/opkg/keys/ 目录"
echo "   文件名必须是公钥指纹（前8个字符）"
echo "   例如: /etc/opkg/keys/\$(usign -F -p key-build.pub | head -c8).ucert"
echo ""
echo "3. 推送代码触发 Actions 编译"
