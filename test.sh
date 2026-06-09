#!/bin/bash
# Unit test script for IPThrottle

set -e

echo "========================================="
echo "IPThrottle 单元测试"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# 测试1: 检查核心模块是否存在
test_modules_exist() {
    log_info "测试核心模块文件..."
    
    for module in core.sh ip.sh wan.sh schedule.sh; do
        if [ -f "files/usr/lib/iptest/$module" ]; then
            log_pass "模块 $module 存在"
        else
            log_fail "模块 $module 不存在"
        fi
    done
}

# 测试2: 检查脚本语法
test_script_syntax() {
    log_info "测试脚本语法..."
    
    for script in files/usr/lib/iptest/*.sh files/usr/sbin/iptest; do
        if sh -n "$script" 2>/dev/null; then
            log_pass "$(basename $script) 语法正确"
        else
            log_fail "$(basename $script) 语法错误"
        fi
    done
}

# 测试3: 测试IP验证功能
test_ip_validation() {
    log_info "测试IP验证功能..."
    
    # 加载ip模块
    source files/usr/lib/iptest/ip.sh
    
    # 测试有效IP
    if validate_ip "192.168.1.100" 2>/dev/null; then
        log_pass "验证有效IP 192.168.1.100"
    else
        log_fail "验证有效IP 192.168.1.100 失败"
    fi
    
    # 测试无效IP
    if ! validate_ip "999.999.999.999" 2>/dev/null; then
        log_pass "正确拒绝无效IP 999.999.999.999"
    else
        log_fail "应拒绝无效IP 999.999.999.999"
    fi
    
    # 测试有效IP范围
    if validate_ip_range "192.168.1.100-192.168.1.200" 2>/dev/null; then
        log_pass "验证有效IP范围 192.168.1.100-192.168.1.200"
    else
        log_fail "验证有效IP范围失败"
    fi
}

# 测试4: 测试时间计划解析
test_time_plan() {
    log_info "测试时间计划解析..."
    
    source files/usr/lib/iptest/schedule.sh
    
    # 测试解析函数是否存在
    if type parse_time_plan >/dev/null 2>&1; then
        log_pass "parse_time_plan 函数存在"
    else
        log_fail "parse_time_plan 函数不存在"
    fi
}

# 测试5: 检查Luci前端文件
test_luci_files() {
    log_info "测试Luci前端文件..."
    
    for file in \
        "root/usr/share/luci/menu.d/luci-app-iptest.json" \
        "root/usr/share/rpcd/acl.d/luci-app-iptest.json" \
        "root/www/luci-static/resources/view/iptest.js"
    do
        if [ -f "$file" ]; then
            log_pass "$(basename $file) 存在"
        else
            log_fail "$(basename $file) 不存在"
        fi
    done
    
    # 测试JSON格式
    for json in \
        "root/usr/share/luci/menu.d/luci-app-iptest.json" \
        "root/usr/share/rpcd/acl.d/luci-app-iptest.json"
    do
        if [ -f "$json" ]; then
            if python3 -m json.tool "$json" >/dev/null 2>&1; then
                log_pass "$(basename $json) JSON格式正确"
            else
                log_fail "$(basename $json) JSON格式错误"
            fi
        fi
    done
}

# 测试6: 检查配置文件
test_config_files() {
    log_info "测试配置文件..."
    
    if [ -f "files/etc/config/iptest" ]; then
        log_pass "UCI配置文件存在"
    else
        log_fail "UCI配置文件不存在"
    fi
    
    if [ -f "Makefile" ]; then
        log_pass "Makefile存在"
    else
        log_fail "Makefile不存在"
    fi
    
    if [ -f "README.md" ]; then
        log_pass "README.md存在"
    else
        log_fail "README.md不存在"
    fi
}

# 测试7: 测试服务脚本
test_service_scripts() {
    log_info "测试服务脚本..."
    
    if [ -f "files/etc/init.d/iptest" ]; then
        if [ -x "files/etc/init.d/iptest" ]; then
            log_pass "init.d脚本存在且可执行"
        else
            log_fail "init.d脚本不可执行"
        fi
    else
        log_fail "init.d脚本不存在"
    fi
}

# 运行所有测试
run_all_tests() {
    test_modules_exist
    echo
    test_script_syntax
    echo
    test_ip_validation
    echo
    test_time_plan
    echo
    test_luci_files
    echo
    test_config_files
    echo
    test_service_scripts
}

# 主程序
main() {
    run_all_tests
    
    echo
    echo "========================================="
    echo "测试总结"
    echo "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="
    echo -e "通过: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "失败: ${RED}${TESTS_FAILED}${NC}"
    echo "总计: $((TESTS_PASSED + TESTS_FAILED))"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}所有测试通过！${NC}"
        exit 0
    else
        echo -e "${RED}有测试失败，请检查输出${NC}"
        exit 1
    fi
}

main "$@"
