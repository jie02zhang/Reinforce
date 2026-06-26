#!/bin/bash
# 测试脚本：验证 Sudo 配置
# 用法: bash test_sudoers.sh [verbose]

set -euo pipefail

VERBOSE="${1:-}"
LOG_PASS="[PASS]"
LOG_FAIL="[FAIL]"
LOG_INFO="[INFO]"

[[ "$VERBOSE" == "verbose" ]] && VERBOSE=1 || VERBOSE=0

pass=0
fail=0

log_pass() { echo "$LOG_PASS $1"; pass=$((pass + 1)); }
log_fail() { echo "$LOG_FAIL $1"; fail=$((fail + 1)); }
log_info() { echo "$LOG_INFO $1"; }
log_verbose() { [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] $1" || true; }

# 测试 1: sudoers 语法验证
test_sudoers_syntax() {
    log_info "测试 1: sudoers 语法验证"
    
    if visudo -c 2>&1; then
        log_pass "sudoers 语法验证通过"
        log_verbose "$(visudo -c 2>&1)"
    else
        log_fail "sudoers 语法验证失败"
        log_verbose "$(visudo -c 2>&1)"
    fi
}

# 测试 2: admin 用户 sudo 权限
test_admin_sudo() {
    log_info "测试 2: admin 用户 sudo 权限"
    
    if id admin &>/dev/null; then
        if sudo -l -U admin 2>&1 | grep -q "NOPASSWD"; then
            log_pass "admin 用户已配置 NOPASSWD"
            log_verbose "$(sudo -l -U admin 2>&1 | grep -A5 NOPASSWD)"
        else
            log_fail "admin 用户未配置 NOPASSWD"
        fi
    else
        log_info "admin 用户不存在，跳过测试"
    fi
}

# 测试 3: sudo 日志配置
test_sudo_logging() {
    log_info "测试 3: sudo 日志配置"
    
    if [ -f /etc/sudoers.d/security_hardening ]; then
        if grep -q "Defaults logfile" /etc/sudoers.d/security_hardening 2>/dev/null; then
            log_pass "sudo 日志已配置"
            log_verbose "$(grep 'Defaults logfile' /etc/sudoers.d/security_hardening)"
        else
            log_fail "sudo 日志未配置"
        fi
        
        if grep -q "Defaults log_input" /etc/sudoers.d/security_hardening 2>/dev/null; then
            log_pass "sudo log_input 已启用"
        else
            log_fail "sudo log_input 未启用"
        fi
        
        if grep -q "Defaults log_output" /etc/sudoers.d/security_hardening 2>/dev/null; then
            log_pass "sudo log_output 已启用"
        else
            log_fail "sudo log_output 未启用"
        fi
    else
        log_fail "sudoers.d/security_hardening 文件不存在"
    fi
}

# 测试 4: sudo 超时配置
test_sudo_timeout() {
    log_info "测试 4: sudo 超时配置"
    
    if [ -f /etc/sudoers.d/security_hardening ]; then
        if grep -q "Defaults timestamp_timeout" /etc/sudoers.d/security_hardening 2>/dev/null; then
            local timeout
            timeout=$(grep "Defaults timestamp_timeout" /etc/sudoers.d/security_hardening | awk -F= '{print $2}' | tr -d ' ')
            if [ -n "$timeout" ] && [ "$timeout" -le 15 ]; then
                log_pass "sudo timestamp_timeout 已设置: $timeout 分钟"
            else
                log_fail "sudo timestamp_timeout 未正确设置 (当前: $timeout, 期望: <=15)"
            fi
        else
            log_fail "sudo timestamp_timeout 未配置"
        fi
    else
        log_fail "sudoers.d/security_hardening 文件不存在"
    fi
}

# 测试 5: sudo 权限（400 或 440）
test_sudo_permissions() {
    log_info "测试 5: sudo 文件权限"
    
    local files=("/etc/sudoers" "/etc/sudoers.d/security_hardening")
    [ -f /etc/sudoers.d/admin_nopasswd ] && files+=("/etc/sudoers.d/admin_nopasswd")
    
    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            local perm
            perm=$(stat -c "%a" "$f" 2>/dev/null || stat -f "%Lp" "$f" 2>/dev/null)
            if [[ "$perm" == "400" || "$perm" == "440" ]]; then
                log_pass "$f 权限正确: $perm"
            else
                log_fail "$f 权限不正确 (当前: $perm, 期望: 400 或 440)"
            fi
        else
            log_info "$f 不存在，跳过"
        fi
    done
}

# 主函数
main() {
    echo "=========================================="
    echo "Sudo 配置测试脚本"
    echo "系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    test_sudoers_syntax
    echo ""
    test_admin_sudo
    echo ""
    test_sudo_logging
    echo ""
    test_sudo_timeout
    echo ""
    test_sudo_permissions
    echo ""
    
    echo "=========================================="
    echo "测试结果: $pass 通过, $fail 失败"
    echo "=========================================="
    
    [ $fail -eq 0 ] && exit 0 || exit 1
}

main
