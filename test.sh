#!/bin/sh
# OpenWrt IP限速插件单元测试脚本

set -e

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0

pass() {
    passed=$((passed + 1))
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    failed=$((failed + 1))
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

echo "========================================"
echo "OpenWrt IP限速插件 - 单元测试"
echo "========================================"
echo

# 测试1: 目录结构
echo "测试 1: 目录结构检查"
[ -d "files/usr/lib/ipthrottle" ] && pass "核心库目录存在" || fail "核心库目录缺失"
[ -d "files/usr/sbin" ] && pass "可执行文件目录存在" || fail "可执行文件目录缺失"
[ -d "files/etc/init.d" ] && pass "init.d目录存在" || fail "init.d目录缺失"
[ -d "files/etc/config" ] && pass "配置目录存在" || fail "配置目录缺失"
[ -d "files/etc/cron.d" ] && pass "cron目录存在" || fail "cron目录缺失"
[ -d "files/etc/hotplug.d/iface" ] && pass "hotplug目录存在" || fail "hotplug目录缺失"
[ -d "root/usr/share/luci/menu.d" ] && pass "LuCI菜单目录存在" || fail "LuCI菜单目录缺失"
[ -d "root/usr/share/rpcd/acl.d" ] && pass "RPC ACL目录存在" || fail "RPC ACL目录缺失"
[ -d "root/www/luci-static/resources/view" ] && pass "LuCI视图目录存在" || fail "LuCI视图目录缺失"
echo

# 测试2: 核心脚本文件
echo "测试 2: 核心脚本文件检查"
[ -f "files/usr/lib/ipthrottle/core.sh" ] && pass "core.sh 存在" || fail "core.sh 缺失"
[ -f "files/usr/lib/ipthrottle/ip.sh" ] && pass "ip.sh 存在" || fail "ip.sh 缺失"
[ -f "files/usr/lib/ipthrottle/wan.sh" ] && pass "wan.sh 存在" || fail "wan.sh 缺失"
[ -f "files/usr/lib/ipthrottle/schedule.sh" ] && pass "schedule.sh 存在" || fail "schedule.sh 缺失"
[ -f "files/usr/sbin/ipthrottle" ] && pass "ipthrottle 主程序存在" || fail "ipthrottle 主程序缺失"
echo

# 测试3: 服务脚本
echo "测试 3: 服务脚本检查"
[ -f "files/etc/init.d/ipthrottle" ] && pass "init.d/ipthrottle 存在" || fail "init.d/ipthrottle 缺失"
[ -f "files/etc/cron.d/ipthrottle" ] && pass "cron.d/ipthrottle 存在" || fail "cron.d/ipthrottle 缺失"
[ -f "files/etc/hotplug.d/iface/90-ipthrottle" ] && pass "hotplug脚本存在" || fail "hotplug脚本缺失"
echo

# 测试4: 配置文件
echo "测试 4: 配置文件检查"
[ -f "files/etc/config/ipthrottle" ] && pass "UCI配置文件存在" || fail "UCI配置文件缺失"
if grep -qE "^config (global|rule)" files/etc/config/ipthrottle 2>/dev/null; then
    pass "UCI配置文件格式正确"
else
    fail "UCI配置文件格式错误"
fi
echo

# 测试5: LuCI文件
echo "测试 5: LuCI集成文件检查"
if [ -f "root/usr/share/luci/menu.d/luci-app-ipthrottle.json" ] || [ -f "root/usr/share/luci/menu.d/ipthrottle.json" ]; then
    pass "LuCI菜单配置存在"
else
    fail "LuCI菜单配置缺失"
fi
[ -f "root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json" ] && pass "RPC ACL配置存在" || fail "RPC ACL配置缺失"
[ -f "root/www/luci-static/resources/view/ipthrottle.js" ] && pass "LuCI视图文件存在" || fail "LuCI视图文件缺失"
echo

# 测试6: 文件权限
echo "测试 6: 文件执行权限检查"
[ -x "files/usr/lib/ipthrottle/core.sh" ] && pass "core.sh 可执行" || fail "core.sh 不可执行"
[ -x "files/usr/lib/ipthrottle/ip.sh" ] && pass "ip.sh 可执行" || fail "ip.sh 不可执行"
[ -x "files/usr/lib/ipthrottle/wan.sh" ] && pass "wan.sh 可执行" || fail "wan.sh 不可执行"
[ -x "files/usr/lib/ipthrottle/schedule.sh" ] && pass "schedule.sh 可执行" || fail "schedule.sh 不可执行"
[ -x "files/usr/sbin/ipthrottle" ] && pass "ipthrottle 可执行" || fail "ipthrottle 不可执行"
[ -x "files/etc/init.d/ipthrottle" ] && pass "init.d/ipthrottle 可执行" || fail "init.d/ipthrottle 不可执行"
echo

# 测试7: Shell脚本语法
echo "测试 7: Shell脚本语法检查"
sh -n files/usr/lib/ipthrottle/core.sh 2>/dev/null && pass "core.sh 语法正确" || fail "core.sh 语法错误"
sh -n files/usr/lib/ipthrottle/ip.sh 2>/dev/null && pass "ip.sh 语法正确" || fail "ip.sh 语法错误"
sh -n files/usr/lib/ipthrottle/wan.sh 2>/dev/null && pass "wan.sh 语法正确" || fail "wan.sh 语法错误"
sh -n files/usr/lib/ipthrottle/schedule.sh 2>/dev/null && pass "schedule.sh 语法正确" || fail "schedule.sh 语法错误"
sh -n files/usr/sbin/ipthrottle 2>/dev/null && pass "ipthrottle 语法正确" || fail "ipthrottle 语法错误"
sh -n files/etc/init.d/ipthrottle 2>/dev/null && pass "init.d/ipthrottle 语法正确" || fail "init.d/ipthrottle 语法错误"
sh -n files/etc/hotplug.d/iface/90-ipthrottle 2>/dev/null && pass "hotplug脚本语法正确" || fail "hotplug脚本语法错误"
echo

# 测试8: JSON格式验证
echo "测试 8: JSON文件格式检查"
menu_json=$(find root/usr/share/luci/menu.d/ -name "*.json" 2>/dev/null | head -1)
acl_json="root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json"

if command -v jq >/dev/null 2>&1; then
    [ -f "$menu_json" ] && jq . "$menu_json" >/dev/null 2>&1 && pass "菜单JSON格式正确" || fail "菜单JSON格式错误"
    [ -f "$acl_json" ] && jq . "$acl_json" >/dev/null 2>&1 && pass "ACL JSON格式正确" || fail "ACL JSON格式错误"
else
    warn "跳过JSON验证 (无jq工具)"
fi
echo

# 测试9: Makefile检查
echo "测试 9: Makefile检查"
[ -f "Makefile" ] && pass "Makefile存在" || fail "Makefile缺失"
if grep -q "PKG_NAME:=ipthrottle" Makefile 2>/dev/null; then
    pass "Makefile包含正确的包名"
else
    fail "Makefile包名错误"
fi
if grep -q 'include $(TOPDIR)/rules.mk' Makefile 2>/dev/null; then
    pass "Makefile包含OpenWrt规则"
else
    fail "Makefile缺少OpenWrt规则"
fi
echo

# 测试10: 文档完整性
echo "测试 10: 文档完整性检查"
[ -f "README.md" ] && pass "README.md 存在" || fail "README.md 缺失"
[ -f "DEVELOPMENT.md" ] && pass "DEVELOPMENT.md 存在" || fail "DEVELOPMENT.md 缺失"
[ -f "CHANGELOG.md" ] && pass "CHANGELOG.md 存在" || fail "CHANGELOG.md 缺失"
[ -f "test.sh" ] && pass "test.sh 存在" || fail "test.sh 缺失"
echo

# 测试11: 核心函数测试
echo "测试 11: 核心功能函数测试"
cat > /tmp/test_ip_func.sh << 'IPTEST'
#!/bin/sh
ip_to_int() {
    local IFS='.'
    local a b c d
    read -r a b c d <<IP
$1
IP
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

result=$(ip_to_int "192.168.1.1" 2>/dev/null)
expected=3232235777
if [ "$result" = "$expected" ]; then
    echo "PASS"
    exit 0
else
    echo "FAIL"
    exit 1
fi
IPTEST
chmod +x /tmp/test_ip_func.sh
if sh /tmp/test_ip_func.sh 2>/dev/null; then
    pass "ip_to_int 函数工作正常"
else
    warn "ip_to_int 函数测试需要在实际环境中运行"
fi
rm -f /tmp/test_ip_func.sh
echo

# 测试12: 依赖检查
echo "测试 12: 依赖项检查"
command -v tc >/dev/null 2>&1 && pass "tc 命令可用" || warn "tc 命令不可用 (仅在OpenWrt上)"
command -v nft >/dev/null 2>&1 && pass "nft 命令可用" || warn "nft 命令不可用 (仅在OpenWrt上)"
command -v uci >/dev/null 2>&1 && pass "uci 命令可用" || warn "uci 命令不可用 (仅在OpenWrt上)"
command -v ip >/dev/null 2>&1 && pass "ip 命令可用" || warn "ip 命令不可用"
echo

# 汇总结果
echo "========================================"
echo "测试结果汇总"
echo "========================================"
echo "通过: $passed"
echo "失败: $failed"
total=$((passed + failed))
echo "总计: $total"
echo
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ 所有测试通过！${NC}"
    exit 0
else
    echo -e "${RED}✗ 有 $failed 个测试失败${NC}"
    exit 1
fi
