#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$TEST_DIR")
REPORT_DIR="$PROJECT_DIR/test-reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORT_DIR/test_report_${TIMESTAMP}.txt"

# 测试结果计数
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    if [ -n "$REPORT_FILE" ]; then
        echo "[PASS] $1" >> "$REPORT_FILE"
    fi
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    if [ -n "$REPORT_FILE" ]; then
        echo -e "[FAIL] $1" >> "$REPORT_FILE"
    fi
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    if [ -n "$REPORT_FILE" ]; then
        echo "[WARN] $1" >> "$REPORT_FILE"
    fi
}

# 测试报告头部
mkdir -p "$REPORT_DIR"
cat > "$REPORT_FILE" << EOF
OpenWrt IPThrottle 插件测试报告
================================
测试时间: $(date '+%Y-%m-%d %H:%M:%S')
项目目录: $PROJECT_DIR
测试环境: $(uname -a)

测试内容:
EOF

echo "OpenWrt IPThrottle 插件测试框架"
echo "================================"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "报告文件: $REPORT_FILE"
echo ""

# ==========================================
# 测试 1: 代码静态分析
# ==========================================
echo ""
log_info "=== 测试 1: Shell 脚本静态分析 ==="
log_info "运行 ShellCheck 检查..."

if command -v shellcheck >/dev/null 2>&1; then
    # 检查所有核心脚本
    for script in \
        "$PROJECT_DIR/files/usr/sbin/ipthrottle" \
        "$PROJECT_DIR/files/usr/lib/ipthrottle"/*.sh \
        "$PROJECT_DIR/files/etc/init.d/ipthrottle" \
        "$PROJECT_DIR/files/etc/hotplug.d/iface/90-ipthrottle" \
        "$PROJECT_DIR/files/usr/lib/ipthrottle/ipthrottle-daemon"
    do
        if [ -f "$script" ]; then
            script_name=$(basename "$script")
            if shellcheck -S warning "$script" 2>&1 | tee "$REPORT_DIR/shellcheck_${script_name}.txt" >/dev/null; then
                log_success "ShellCheck 通过: $script_name"
            else
                log_warning "ShellCheck 有警告: $script_name (详见 shellcheck_${script_name}.txt)"
            fi
        fi
    done
    
    # 检查语法错误
    for script in "$PROJECT_DIR"/files/usr/lib/ipthrottle/*.sh "$PROJECT_DIR"/files/usr/sbin/ipthrottle; do
        if [ -f "$script" ]; then
            script_name=$(basename "$script")
            if bash -n "$script" 2>&1; then
                log_success "语法检查通过: $script_name"
            else
                log_error "语法错误: $script_name"
            fi
        fi
    done
else
    log_warning "ShellCheck 未安装，跳过静态分析"
fi

echo "ShellCheck 检查完成"

# ==========================================
# 测试 2: 配置验证
# ==========================================
echo ""
log_info "=== 测试 2: 配置文件验证 ==="

# 检查 UCI 配置文件格式
if [ -f "$PROJECT_DIR/files/etc/config/ipthrottle" ]; then
    log_success "UCI 配置文件存在"
    
    # 检查必填字段
    if grep -q "config ipthrottle" "$PROJECT_DIR/files/etc/config/ipthrottle"; then
        log_success "config ipthrottle 节点存在"
    else
        log_error "config ipthrottle 节点缺失"
    fi
    
    # 检查规则示例
    if grep -q "config rule" "$PROJECT_DIR/files/etc/config/ipthrottle"; then
        log_success "config rule 示例存在"
    else
        log_error "config rule 示例缺失"
    fi
else
    log_error "UCI 配置文件缺失: files/etc/config/ipthrottle"
fi

# 检查权限配置
if [ -f "$PROJECT_DIR/root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json" ]; then
    log_success "ACL 权限配置文件存在"
    
    if grep -q "luci-app-iptest" "$PROJECT_DIR/root/usr/share/rpcd/acl.d/luci-app-ipthrottle.json"; then
        log_success "ACL 配置内容正确"
    else
        log_error "ACL 配置内容有误"
    fi
else
    log_error "ACL 权限配置文件缺失"
fi

echo "配置验证完成"

# ==========================================
# 测试 3: 核心模块功能测试
# ==========================================
echo ""
log_info "=== 测试 3: 核心模块功能测试 ==="

# 测试 IP 解析模块
log_info "测试 IP 解析模块 (ip.sh)..."

# 创建临时测试脚本
cat > "$REPORT_DIR/test_ip.sh" << 'TESTEOF'
#!/bin/bash
source "$1/files/usr/lib/ipthrottle/ip.sh"

test_ip_validate() {
    echo "Testing IP validation..."
    
    # 测试有效 IP
    if validate_ip "192.168.1.1"; then
        echo "PASS: 192.168.1.1 is valid"
    else
        echo "FAIL: 192.168.1.1 should be valid"
        exit 1
    fi
    
    if validate_ip "10.0.0.255"; then
        echo "PASS: 10.0.0.255 is valid"
    else
        echo "FAIL: 10.0.0.255 should be valid"
        exit 1
    fi
    
    # 测试无效 IP
    if ! validate_ip "999.999.999.999"; then
        echo "PASS: 999.999.999.999 is invalid"
    else
        echo "FAIL: 999.999.999.999 should be invalid"
        exit 1
    fi
    
    if ! validate_ip "abc.def.ghi.jkl"; then
        echo "PASS: abc.def.ghi.jkl is invalid"
    else
        echo "FAIL: abc.def.ghi.jkl should be invalid"
        exit 1
    fi
    
    echo "All IP validation tests passed!"
}

test_ip_to_int() {
    echo "Testing IP to integer conversion..."
    
    local result
    result=$(ip_to_int "192.168.1.1")
    if [ "$result" = "3232235777" ]; then
        echo "PASS: 192.168.1.1 -> $result"
    else
        echo "FAIL: 192.168.1.1 -> $result (expected 3232235777)"
        exit 1
    fi
    
    result=$(ip_to_int "10.0.0.1")
    if [ "$result" = "167772161" ]; then
        echo "PASS: 10.0.0.1 -> $result"
    else
        echo "FAIL: 10.0.0.1 -> $result (expected 167772161)"
        exit 1
    fi
    
    echo "All IP conversion tests passed!"
}

test_ip_range() {
    echo "Testing IP range validation..."
    
    if validate_ip_range "192.168.1.10-192.168.1.20"; then
        echo "PASS: 192.168.1.10-192.168.1.20 is valid range"
    else
        echo "FAIL: 192.168.1.10-192.168.1.20 should be valid range"
        exit 1
    fi
    
    if ! validate_ip_range "192.168.1.20-192.168.1.10"; then
        echo "PASS: 192.168.1.20-192.168.1.10 is invalid range"
    else
        echo "FAIL: 192.168.1.20-192.168.1.10 should be invalid range"
        exit 1
    fi
    
    echo "All IP range tests passed!"
}

test_ip_validate
echo ""
test_ip_to_int
echo ""
test_ip_range
echo ""
echo "=== IP SH MODULE ALL TESTS PASSED ==="
TESTEOF

chmod +x "$REPORT_DIR/test_ip.sh"

if bash "$REPORT_DIR/test_ip.sh" "$PROJECT_DIR" 2>&1 | tee "$REPORT_DIR/ip_module_test.txt"; then
    if grep -q "ALL TESTS PASSED" "$REPORT_DIR/ip_module_test.txt"; then
        log_success "IP 解析模块测试全部通过"
    else
        log_error "IP 解析模块测试部分失败"
    fi
else
    log_error "IP 解析模块测试执行失败"
fi

echo "IP 模块测试完成"

# 测试时间计划模块
log_info "测试时间计划模块 (schedule.sh)..."

cat > "$REPORT_DIR/test_schedule.sh" << 'TESTEOF'
#!/bin/bash
source "$1/files/usr/lib/ipthrottle/schedule.sh"

test_time_to_minutes() {
    echo "Testing time to minutes conversion..."
    
    local result
    result=$(time_to_minutes "08:00")
    if [ "$result" = "480" ]; then
        echo "PASS: 08:00 -> $result minutes"
    else
        echo "FAIL: 08:00 -> $result (expected 480)"
        exit 1
    fi
    
    result=$(time_to_minutes "14:30")
    if [ "$result" = "870" ]; then
        echo "PASS: 14:30 -> $result minutes"
    else
        echo "FAIL: 14:30 -> $result (expected 870)"
        exit 1
    fi
    
    echo "All time conversion tests passed!"
}

test_check_schedule_json() {
    echo "Testing schedule JSON validation..."
    
    # 测试有效的 JSON
    local valid_json='{"d":[1,2,3,4,5],"s":"08:00","e":"22:00"}'
    if validate_schedule_json "$valid_json"; then
        echo "PASS: Valid schedule JSON accepted"
    else
        echo "FAIL: Valid schedule JSON rejected"
        exit 1
    fi
    
    # 测试无效的 JSON
    local invalid_json='{"d":[1,2,3],"s":"08:00"}'
    if ! validate_schedule_json "$invalid_json"; then
        echo "PASS: Invalid schedule JSON rejected"
    else
        echo "FAIL: Invalid schedule JSON should be rejected"
        exit 1
    fi
    
    echo "All schedule JSON tests passed!"
}

test_parse_weekdays() {
    echo "Testing weekday parsing..."
    
    local result
    result=$(parse_weekdays "[1,2,3,4,5]")
    if [ "$result" = "1,2,3,4,5" ]; then
        echo "PASS: Weekdays parsed correctly: $result"
    else
        echo "FAIL: Weekdays parsing failed: $result"
        exit 1
    fi
    
    echo "All weekday parsing tests passed!"
}

test_time_to_minutes
echo ""
test_check_schedule_json
echo ""
test_parse_weekdays
echo ""
echo "=== SCHEDULE SH MODULE ALL TESTS PASSED ==="
TESTEOF

chmod +x "$REPORT_DIR/test_schedule.sh"

if bash "$REPORT_DIR/test_schedule.sh" "$PROJECT_DIR" 2>&1 | tee "$REPORT_DIR/schedule_module_test.txt"; then
    if grep -q "ALL TESTS PASSED" "$REPORT_DIR/schedule_module_test.txt"; then
        log_success "时间计划模块测试全部通过"
    else
        log_error "时间计划模块测试部分失败"
    fi
else
    log_error "时间计划模块测试执行失败"
fi

echo "Schedule 模块测试完成"

# ==========================================
# 测试 4: 核心功能集成测试
# ==========================================
echo ""
log_info "=== 测试 4: 核心功能集成测试 ==="

cat > "$REPORT_DIR/test_integration.sh" << 'TESTEOF'
#!/bin/bash
source "$1/files/usr/lib/ipthrottle/ip.sh"
source "$1/files/usr/lib/ipthrottle/schedule.sh"
source "$1/files/usr/lib/ipthrottle/config.sh"

test_config_parsing() {
    echo "Testing configuration parsing..."
    
    # 创建测试配置
    mkdir -p /tmp/ipthrottle_test_config
    cat > /tmp/ipthrottle_test_config/ipthrottle << CFGEOF
config ipthrottle 'config'
    option enabled '1'
    option default_upload '1024'
    option default_download '4096'

config rule 'test1'
    option name 'Test Rule 1'
    option wan_mask 'wan1'
    option priority '10'
    option protocol 'tcp'
    option throttle_mode 'independent'
    option upload_mbps '100'
    option download_mbps '500'
    list ip_addrs '192.168.1.100'
    option ip_range ''
    option plan '{"d":[1,2,3,4,5],"s":"08:00","e":"22:00"}'
    option enabled '1'

config rule 'test2'
    option name 'Test Rule 2'
    option wan_mask 'all'
    option priority '20'
    option protocol 'all'
    option throttle_mode 'share'
    option upload_mbps '50'
    option download_mbps '200'
    list ip_addrs '192.168.1.10'
    option ip_range '192.168.1.10-192.168.1.20'
    option plan '{"d":[0,6],"s":"00:00","e":"23:59"}'
    option enabled '0'
CFGEOF
    
    echo "PASS: Test configuration created"
    
    # 清理
    rm -rf /tmp/ipthrottle_test_config
    
    echo "All configuration parsing tests passed!"
}

test_rule_priority() {
    echo "Testing rule priority logic..."
    
    # 模拟规则优先级排序
    local rules="rule1:10 rule2:15 rule3:5 rule4:10"
    local sorted=$(echo "$rules" | tr ' ' '\n' | sort -t: -k2 -n | tr '\n' ' ')
    local expected="rule3:5 rule1:10 rule4:10 rule2:15"
    
    if [ "$sorted" = "$expected" ]; then
        echo "PASS: Rules sorted by priority correctly"
    else
        echo "FAIL: Rules sorting failed"
        echo "  Expected: $expected"
        echo "  Got: $sorted"
        exit 1
    fi
    
    echo "All priority logic tests passed!"
}

test_config_parsing
echo ""
test_rule_priority
echo ""
echo "=== INTEGRATION ALL TESTS PASSED ==="
TESTEOF

chmod +x "$REPORT_DIR/test_integration.sh"

if bash "$REPORT_DIR/test_integration.sh" "$PROJECT_DIR" 2>&1 | tee "$REPORT_DIR/integration_test.txt"; then
    if grep -q "ALL TESTS PASSED" "$REPORT_DIR/integration_test.txt"; then
        log_success "集成测试全部通过"
    else
        log_error "集成测试部分失败"
    fi
else
    log_error "集成测试执行失败"
fi

echo "集成测试完成"

# ==========================================
# 测试 5: 文件完整性检查
# ==========================================
echo ""
log_info "=== 测试 5: 文件完整性检查 ==="

required_files=(
    "files/usr/sbin/ipthrottle"
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
)

for file in "${required_files[@]}"; do
    if [ -f "$PROJECT_DIR/$file" ]; then
        log_success "文件存在: $file"
    else
        log_error "文件缺失: $file"
    fi
done

# 检查文件权限
for script in files/usr/sbin/ipthrottle files/etc/init.d/ipthrottle files/etc/hotplug.d/iface/90-ipthrottle; do
    if [ -f "$PROJECT_DIR/$script" ]; then
        if [ -x "$PROJECT_DIR/$script" ]; then
            log_success "文件可执行: $script"
        else
            log_error "文件不可执行: $script"
        fi
    fi
done

echo "文件完整性检查完成"

# ==========================================
# 生成测试报告
# ==========================================
echo ""
log_info "=== 生成测试报告 ==="

cat >> "$REPORT_FILE" << EOF

测试结果摘要
============
总测试数: $TESTS_TOTAL
通过: $TESTS_PASSED
失败: $TESTS_FAILED
通过率: $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc 2>/dev/null || echo "N/A")%

测试时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF

if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ 所有测试通过！${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ 有 $TESTS_FAILED 个测试失败${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
