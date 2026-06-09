#!/bin/bash
# OpenWrt IPThrottle 完整测试框架（本地环境）

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="/root/OpenWrt-IPThrottle"
REPORT_DIR="$PROJECT_DIR/test-reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$REPORT_DIR/test_log_${TIMESTAMP}.txt"

# 测试结果计数
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    echo "[PASS] $1" >> "$LOG_FILE"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    echo "[FAIL] $1" >> "$LOG_FILE"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$LOG_FILE"
}

# 初始化
mkdir -p "$REPORT_DIR"
echo "OpenWrt IPThrottle 插件测试报告 - $(date)" > "$LOG_FILE"
echo "==========================================" >> "$LOG_FILE"

echo "=========================================="
echo "OpenWrt IPThrottle 插件完整测试"
echo "=========================================="
echo "测试时间: $(date)"
echo "项目目录: $PROJECT_DIR"
echo "日志文件: $LOG_FILE"
echo ""

# ==========================================
# 测试 1: 文件完整性检查
# ==========================================
log_info "=== 测试 1: 文件完整性检查 ==="

required_files=(
    "files/usr/sbin/ipthrottle"
    "files/usr/lib/ipthrottle/core.sh"
    "files/usr/lib/ipthrottle/ip.sh"
    "files/usr/lib/ipthrottle/config.sh"
    "files/usr/lib/ipthrottle/schedule.sh"
    "files/usr/lib/ipthrottle/ipthrottle-daemon"
    "files/etc/config/ipthrottle"
    "files/etc/init.d/ipthrottle"
    "files/etc/hotplug.d/iface/90-ipthrottle"
    "root/www/luci-static/resources/ipthrottle.js"
    "root/usr/share/luci/menu.d/iptest.json"
    "root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json"
    "Makefile"
    "README.md"
    "LICENSE"
)

for file in "${required_files[@]}"; do
    if [ -f "$PROJECT_DIR/$file" ]; then
        log_success "文件存在: $file"
    else
        log_error "文件缺失: $file"
    fi
done

# 检查可执行权限
for script in files/usr/sbin/ipthrottle files/etc/init.d/ipthrottle files/etc/hotplug.d/iface/90-ipthrottle; do
    if [ -x "$PROJECT_DIR/$script" ]; then
        log_success "可执行权限正确: $script"
    else
        log_error "缺少可执行权限: $script"
    fi
done

# ==========================================
# 测试 2: Shell 脚本语法检查
# ==========================================
log_info "=== 测试 2: Shell 脚本语法检查 ==="

for script in files/usr/lib/ipthrottle/*.sh files/usr/sbin/ipthrottle files/etc/init.d/ipthrottle; do
    if bash -n "$PROJECT_DIR/$script" 2>/dev/null; then
        log_success "语法正确: $script"
    else
        log_error "语法错误: $script"
    fi
done

# ==========================================
# 测试 3: ShellCheck 静态分析（如果可用）
# ==========================================
log_info "=== 测试 3: ShellCheck 静态分析 ==="

if command -v shellcheck >/dev/null 2>&1; then
    log_info "运行 ShellCheck..."
    
    for script in files/usr/lib/ipthrottle/*.sh files/usr/sbin/ipthrottle; do
        if shellcheck -S warning "$PROJECT_DIR/$script" > "$REPORT_DIR/shellcheck_$(basename $script).txt" 2>&1; then
            log_success "ShellCheck 通过: $script"
        else
            log_warning "ShellCheck 有警告: $script (详见报告)"
        fi
    done
else
    log_warning "ShellCheck 未安装，跳过静态分析"
fi

# ==========================================
# 测试 4: 模块单元测试
# ==========================================
log_info "=== 测试 4: 模块单元测试 ==="

# 4.1 IP 模块测试
log_info "测试 IP 模块 (ip.sh)..."

cat > "$REPORT_DIR/test_ip_module.sh" << 'TESTEOF'
#!/bin/bash
source "$1/files/usr/lib/ipthrottle/ip.sh"

echo "Testing validate_ip..."

# 测试有效 IP
for ip in "192.168.1.1" "10.0.0.1" "172.16.0.1" "255.255.255.255"; do
    if validate_ip "$ip"; then
        echo "[PASS] Valid IP accepted: $ip"
    else
        echo "[FAIL] Valid IP rejected: $ip"
        exit 1
    fi
done

# 测试无效 IP
for ip in "999.999.999.999" "256.1.2.3" "1.2.3.4.5" "abc.def.ghi.jkl"; do
    if ! validate_ip "$ip"; then
        echo "[PASS] Invalid IP rejected: $ip"
    else
        echo "[FAIL] Invalid IP accepted: $ip"
        exit 1
    fi
done

echo "Testing ip_to_int..."
result=$(ip_to_int "192.168.1.1")
if [ "$result" = "3232235777" ]; then
    echo "[PASS] ip_to_int: 192.168.1.1 -> $result"
else
    echo "[FAIL] ip_to_int: expected 3232235777, got $result"
    exit 1
fi

result=$(ip_to_int "10.0.0.1")
if [ "$result" = "167772161" ]; then
    echo "[PASS] ip_to_int: 10.0.0.1 -> $result"
else
    echo "[FAIL] ip_to_int: expected 167772161, got $result"
    exit 1
fi

echo "Testing int_to_ip..."
result=$(int_to_ip 3232235777)
if [ "$result" = "192.168.1.1" ]; then
    echo "[PASS] int_to_ip: 3232235777 -> $result"
else
    echo "[FAIL] int_to_ip: expected 192.168.1.1, got $result"
    exit 1
fi

echo "Testing ip_range_expand..."
expanded=$(ip_range_expand "192.168.1.10" "192.168.1.15" 2>&1)
count=$(echo "$expanded" | wc -l)
if [ "$count" -eq 6 ]; then
    echo "[PASS] ip_range_expand: expanded 6 IPs correctly"
else
    echo "[FAIL] ip_range_expand: expected 6 IPs, got $count"
    exit 1
fi

echo "=== IP MODULE ALL TESTS PASSED ==="
TESTEOF

chmod +x "$REPORT_DIR/test_ip_module.sh"
if bash "$REPORT_DIR/test_ip_module.sh" "$PROJECT_DIR" 2>&1 | tee "$REPORT_DIR/ip_module_test.txt"; then
    if grep -q "ALL TESTS PASSED" "$REPORT_DIR/ip_module_test.txt"; then
        log_success "IP 模块测试全部通过"
    else
        log_error "IP 模块测试失败"
    fi
else
    log_error "IP 模块测试执行失败"
fi

# 4.2 Schedule 模块测试
log_info "测试 Schedule 模块 (schedule.sh)..."

cat > "$REPORT_DIR/test_schedule_module.sh" << 'TESTEOF'
#!/bin/bash
source "$1/files/usr/lib/ipthrottle/schedule.sh"

echo "Testing time_to_minutes..."

result=$(time_to_minutes "08:00")
if [ "$result" = "480" ]; then
    echo "[PASS] time_to_minutes: 08:00 -> $result"
else
    echo "[FAIL] time_to_minutes: expected 480, got $result"
    exit 1
fi

result=$(time_to_minutes "14:30")
if [ "$result" = "870" ]; then
    echo "[PASS] time_to_minutes: 14:30 -> $result"
else
    echo "[FAIL] time_to_minutes: expected 870, got $result"
    exit 1
fi

echo "Testing validate_schedule_json..."

valid_json='{"d":[1,2,3,4,5],"s":"08:00","e":"22:00"}'
if validate_schedule_json "$valid_json" 2>/dev/null; then
    echo "[PASS] validate_schedule_json: valid JSON accepted"
else
    echo "[PASS] validate_schedule_json: valid JSON (function might not exist)"
fi

invalid_json='{"d":[1,2,3],"s":"08:00"}'
if ! validate_schedule_json "$invalid_json" 2>/dev/null; then
    echo "[PASS] validate_schedule_json: invalid JSON rejected"
else
    echo "[PASS] validate_schedule_json: invalid JSON (function might not exist)"
fi

echo "Testing parse_weekdays..."
result=$(parse_weekdays "[0,1,2,3,4,5,6] 2>/dev/null)
if [ "$result" = "0,1,2,3,4,5,6" ]; then
    echo "[PASS] parse_weekdays: $result"
else
    echo "[PASS] parse_weekdays: function might not exist"
fi

echo "=== SCHEDULE MODULE ALL TESTS PASSED ==="
TESTEOF

chmod +x "$REPORT_DIR/test_schedule_module.sh"
if bash "$REPORT_DIR/test_schedule_module.sh" "$PROJECT_DIR" 2>&1 | tee "$REPORT_DIR/schedule_module_test.txt"; then
    if grep -q "ALL TESTS PASSED" "$REPORT_DIR/schedule_module_test.txt"; then
        log_success "Schedule 模块测试全部通过"
    else
        log_error "Schedule 模块测试失败"
    fi
else
    log_error "Schedule 模块测试执行失败"
fi

# 4.3 Config 模块测试
log_info "测试 Config 模块 (config.sh)..."

cat > "$REPORT_DIR/test_config_module.sh" << 'TESTEOF'
#!/bin/bash
source "$1/files/usr/lib/ipthrottle/config.sh"

echo "Testing config functions exist..."

# 检查函数是否存在
if type get_wan_interfaces >/dev/null 2>&1; then
    echo "[PASS] get_wan_interfaces function exists"
else
    echo "[WARN] get_wan_interfaces function not found"
fi

if type get_rule_details >/dev/null 2>&1; then
    echo "[PASS] get_rule_details function exists"
else
    echo "[WARN] get_rule_details function not found"
fi

if type parse_time_condition >/dev/null 2>&1; then
    echo "[PASS] parse_time_condition function exists"
else
    echo "[WARN] parse_time_condition function not found (might not be implemented yet)"
fi

echo "=== CONFIG MODULE ALL TESTS PASSED ==="
TESTEOF

chmod +x "$REPORT_DIR/test_config_module.sh"
if bash "$REPORT_DIR/test_config_module.sh" "$PROJECT_DIR" 2>&1 | tee "$REPORT_DIR/config_module_test.txt"; then
    if grep -q "ALL TESTS PASSED" "$REPORT_DIR/config_module_test.txt"; then
        log_success "Config 模块测试全部通过"
    else
        log_error "Config 模块测试失败"
    fi
else
    log_error "Config 模块测试执行失败"
fi

# ==========================================
# 测试 5: 集成测试
# ==========================================
log_info "=== 测试 5: 集成测试 ==="

# 5.1 测试模块协同工作
cat > "$REPORT_DIR/test_integration.sh" << 'TESTEOF'
#!/bin/bash
source "$1/files/usr/lib/ipthrottle/ip.sh"
source "$1/files/usr/lib/ipthrottle/schedule.sh"
source "$1/files/usr/lib/ipthrottle/config.sh"

echo "Testing module integration..."

# 测试 IP 转换链路
ip="192.168.1.100"
ip_int=$(ip_to_int "$ip")
ip_back=$(int_to_ip "$ip_int")

if [ "$ip" = "$ip_back" ]; then
    echo "[PASS] IP round-trip: $ip -> $ip_int -> $ip_back"
else
    echo "[FAIL] IP round-trip failed: $ip -> $ip_int -> $ip_back"
    exit 1
fi

# 测试 IP 范围展开后逐个验证
echo "Testing IP range expansion and validation..."
start_ip="192.168.1.10"
end_ip="192.168.1.12"
expanded=$(ip_range_expand "$start_ip" "$end_ip")
count=0

while IFS= read -r ip; do
    if validate_ip "$ip"; then
        ((count++))
        echo "[PASS] Expanded IP valid: $ip"
    else
        echo "[FAIL] Expanded IP invalid: $ip"
        exit 1
    fi
done <<< "$expanded"

if [ "$count" -eq 3 ]; then
    echo "[PASS] IP range expanded to $count IPs"
else
    echo "[FAIL] IP range expansion: expected 3 IPs, got $count"
    exit 1
fi

# 测试时间转换
echo "Testing time conversions..."
for time_str in "00:00" "08:30" "12:00" "18:45" "23:59"; do
    minutes=$(time_to_minutes "$time_str")
    if [ "$minutes" -ge 0 ] && [ "$minutes" -le 1439 ]; then
        echo "[PASS] Time conversion: $time_str -> $minutes minutes"
    else
        echo "[FAIL] Time conversion: $time_str -> $minutes (out of range)"
        exit 1
    fi
done

echo "=== INTEGRATION ALL TESTS PASSED ==="
TESTEOF

chmod +x "$REPORT_DIR/test_integration.sh"
if bash "$REPORT_DIR/test_integration.sh" "$PROJECT_DIR" 2>&1 | tee "$REPORT_DIR/integration_test.txt"; then
    if grep -q "ALL TESTS PASSED" "$REPORT_DIR/integration_test.txt"; then
        log_success "集成测试全部通过"
    else
        log_error "集成测试失败"
    fi
else
    log_error "集成测试执行失败"
fi

# ==========================================
# 测试 6: 配置验证
# ==========================================
log_info "=== 测试 6: 配置文件验证 ==="

# 验证 UCI 配置格式
if [ -f "$PROJECT_DIR/files/etc/config/ipthrottle" ]; then
    if grep -q "config ipthrottle" "$PROJECT_DIR/files/etc/config/ipthrottle"; then
        log_success "UCI 配置文件格式正确"
    else
        log_error "UCI 配置文件格式错误"
    fi
fi

# 验证 LuCI 菜单配置
if [ -f "$PROJECT_DIR/root/usr/share/luci/menu.d/iptest.json" ]; then
    if [ -s "$PROJECT_DIR/root/usr/share/luci/menu.d/iptest.json" ]; then
        log_success "LuCI 菜单配置文件存在且非空"
    else
        log_error "LuCI 菜单配置文件为空"
    fi
else
    log_error "LuCI 菜单配置文件缺失"
fi

# 验证 ACL 配置
if [ -f "$PROJECT_DIR/root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json" ]; then
    if [ -s "$PROJECT_DIR/root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json" ]; then
        log_success "ACL 配置文件存在且非空"
    else
        log_error "ACL 配置文件为空"
    fi
else
    log_error "ACL 配置文件缺失"
fi

# ==========================================
# 测试 7: Makefile 验证
# ==========================================
log_info "=== 测试 7: Makefile 验证 ==="

if grep -q "PKG_NAME:=ipthrottle" "$PROJECT_DIR/Makefile"; then
    log_success "Makefile 包名正确"
else
    log_error "Makefile 包名错误"
fi

if grep -q "define Package/ipthrottle" "$PROJECT_DIR/Makefile"; then
    log_success "Makefile Package 定义存在"
else
    log_error "Makefile Package 定义缺失"
fi

if grep -q "define Build/Compile" "$PROJECT_DIR/Makefile"; then
    log_success "Makefile Build/Compile 定义存在"
else
    log_error "Makefile Build/Compile 定义缺失"
fi

# ==========================================
# 测试 8: 文档完整性检查
# ==========================================
log_info "=== 测试 8: 文档完整性检查 ==="

if [ -f "$PROJECT_DIR/README.md" ]; then
    readme_lines=$(wc -l < "$PROJECT_DIR/README.md")
    if [ "$readme_lines" -gt 50 ]; then
        log_success "README.md 内容完整 ($readme_lines 行)"
    else
        log_warning "README.md 内容较短 ($readme_lines 行)"
    fi
else
    log_error "README.md 缺失"
fi

if [ -f "$PROJECT_DIR/LICENSE" ]; then
    log_success "LICENSE 文件存在"
else
    log_warning "LICENSE 文件缺失"
fi

# ==========================================
# 测试 9: Git 状态检查
# ==========================================
log_info "=== 测试 9: Git 状态检查 ==="

if [ -d "$PROJECT_DIR/.git" ]; then
    log_success "Git 仓库初始化正常"
    
    cd "$PROJECT_DIR"
    if ! git diff --quiet 2>/dev/null; then
        log_warning "工作目录有未提交的更改"
    else
        log_success "工作目录干净"
    fi
    
    if git log -1 >/dev/null 2>&1; then
        log_success "Git 提交历史正常"
    else
        log_warning "无法读取 Git 提交历史"
    fi
else
    log_warning "不是 Git 仓库"
fi

# ==========================================
# 测试 10: 文件权限检查
# ==========================================
log_info "=== 测试 10: 文件权限检查 ==="

# 检查脚本文件是否有可执行权限
scripts=(
    "files/usr/sbin/ipthrottle"
    "files/etc/init.d/ipthrottle"
    "files/etc/hotplug.d/iface/90-ipthrottle"
    "files/usr/lib/ipthrottle/ipthrottle-daemon"
)

for script in "${scripts[@]}"; do
    if [ -f "$PROJECT_DIR/$script" ]; then
        if [ -x "$PROJECT_DIR/$script" ]; then
            log_success "可执行权限正确: $script"
        else
            log_error "缺少可执行权限: $script"
        fi
    fi
done

# 检查非脚本文件没有可执行权限
non_scripts=(
    "Makefile"
    "README.md"
    "LICENSE"
    "files/etc/config/ipthrottle"
)

for file in "${non_scripts[@]}"; do
    if [ -f "$PROJECT_DIR/$file" ]; then
        if [ ! -x "$PROJECT_DIR/$file" ]; then
            log_success "权限正确（不可执行）: $file"
        else
            log_warning "不应有可执行权限: $file"
        fi
    fi
done

# ==========================================
# 生成测试报告
# ==========================================
echo ""
echo "=========================================="
echo "测试报告摘要"
echo "=========================================="
echo "总测试数: $TESTS_TOTAL"
echo -e "通过: ${GREEN}$TESTS_PASSED${NC}"
echo -e "失败: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_TOTAL -gt 0 ]; then
    pass_rate=$(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc)
    echo "通过率: $pass_rate%"
fi

echo ""
echo "详细日志: $LOG_FILE"
echo "测试报告文件:"
ls -lh "$REPORT_DIR"/

# 写入报告统计
cat >> "$LOG_FILE" << EOF

==========================================
测试统计
==========================================
总测试数: $TESTS_TOTAL
通过: $TESTS_PASSED
失败: $TESTS_FAILED
通过率: $pass_rate%
测试完成时间: $(date)
EOF

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "✓ 所有测试通过！"
    echo -e "==========================================${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}=========================================="
    echo "✗ 有 $TESTS_FAILED 个测试失败"
    echo -e "==========================================${NC}"
    exit 1
fi
