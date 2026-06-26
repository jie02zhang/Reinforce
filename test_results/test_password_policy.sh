#!/bin/bash
# 测试脚本：验证密码策略配置
# 用法: bash test_password_policy.sh [verbose]

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

# 测试 1: PAM 配置
test_pam_config() {
    log_info "测试 1: PAM 配置"
    
    if [ -f /etc/pam.d/common-password ]; then
        # Debian/Ubuntu 系列
        if sudo grep -q "pam_pwquality.so" /etc/pam.d/common-password 2>/dev/null; then
            log_pass "PAM pwquality 模块已配置 (Debian/Ubuntu)"
            log_verbose "$(sudo grep 'pam_pwquality.so' /etc/pam.d/common-password | head -1)"
        else
            log_fail "PAM pwquality 模块未配置 (Debian/Ubuntu)"
        fi
    elif [ -f /etc/pam.d/system-auth ]; then
        # RHEL 系列
        if sudo grep -q "pam_pwquality.so" /etc/pam.d/system-auth 2>/dev/null; then
            log_pass "PAM pwquality 模块已配置 (RHEL)"
            log_verbose "$(sudo grep 'pam_pwquality.so' /etc/pam.d/system-auth | head -1)"
        else
            log_fail "PAM pwquality 模块未配置 (RHEL)"
        fi
    else
        log_fail "未找到 PAM 配置文件"
    fi
}

# 测试 2: pwquality.conf 配置
test_pwquality_conf() {
    log_info "测试 2: pwquality.conf 配置"
    
    if [ -f /etc/security/pwquality.conf ]; then
        local minlen retry dcredit ucredit lcredit ocredit
        minlen=$(grep -E "^minlen" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}')
        retry=$(grep -E "^retry" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}')
        dcredit=$(grep -E "^dcredit" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}')
        ucredit=$(grep -E "^ucredit" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}')
        lcredit=$(grep -E "^lcredit" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}')
        ocredit=$(grep -E "^ocredit" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}')
        
        if [ -n "$minlen" ] && [ "$minlen" -ge 12 ]; then
            log_pass "minlen 已设置: $minlen"
        else
            log_fail "minlen 未正确设置 (当前: $minlen, 期望: >=12)"
        fi
        
        if [ -n "$retry" ] && [ "$retry" -ge 3 ]; then
            log_pass "retry 已设置: $retry"
        else
            log_fail "retry 未正确设置 (当前: $retry, 期望: >=3)"
        fi
        
        for param in dcredit ucredit lcredit ocredit; do
            local val
            val=$(eval echo "\$$param")
            if [ -n "$val" ] && [ "$val" -lt 0 ]; then
                log_pass "$param 已设置: $val"
            else
                log_fail "$param 未正确设置 (当前: $val, 期望: <0)"
            fi
        done
    else
        log_fail "pwquality.conf 文件不存在"
    fi
}

# 测试 3: 密码过期策略
test_password_expiry() {
    log_info "测试 3: 密码过期策略"
    
    if [ -f /etc/login.defs ]; then
        local pass_max_days pass_min_days pass_warn_age
        pass_max_days=$(grep -E "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
        pass_min_days=$(grep -E "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')
        pass_warn_age=$(grep -E "^PASS_WARN_AGE" /etc/login.defs | awk '{print $2}')
        
        if [ -n "$pass_max_days" ] && [ "$pass_max_days" -le 90 ]; then
            log_pass "PASS_MAX_DAYS 已设置: $pass_max_days"
        else
            log_fail "PASS_MAX_DAYS 未正确设置 (当前: $pass_max_days, 期望: <=90)"
        fi
        
        if [ -n "$pass_min_days" ] && [ "$pass_min_days" -ge 1 ]; then
            log_pass "PASS_MIN_DAYS 已设置: $pass_min_days"
        else
            log_fail "PASS_MIN_DAYS 未正确设置 (当前: $pass_min_days, 期望: >=1)"
        fi
        
        if [ -n "$pass_warn_age" ] && [ "$pass_warn_age" -ge 7 ]; then
            log_pass "PASS_WARN_AGE 已设置: $pass_warn_age"
        else
            log_fail "PASS_WARN_AGE 未正确设置 (当前: $pass_warn_age, 期望: >=7)"
        fi
    else
        log_fail "login.defs 文件不存在"
    fi
}

# 测试 4: 账户锁定策略 (faillock)
test_account_lockout() {
    log_info "测试 4: 账户锁定策略"
    
    if command -v faillock &>/dev/null; then
        local deny unlock_time
        deny=$(grep -E "deny\s*=" /etc/security/faillock.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
        unlock_time=$(grep -E "unlock_time\s*=" /etc/security/faillock.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
        
        if [ -n "$deny" ] && [ "$deny" -le 5 ]; then
            log_pass "faillock deny 已设置: $deny"
        else
            log_fail "faillock deny 未正确设置 (当前: $deny, 期望: <=5)"
        fi
        
        if [ -n "$unlock_time" ] && [ "$unlock_time" -ge 600 ]; then
            log_pass "faillock unlock_time 已设置: $unlock_time"
        else
            log_fail "faillock unlock_time 未正确设置 (当前: $unlock_time, 期望: >=600)"
        fi
    else
        log_info "faillock 未安装，跳过测试"
    fi
}

# 主函数
main() {
    echo "=========================================="
    echo "密码策略测试脚本"
    echo "系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    test_pam_config
    echo ""
    test_pwquality_conf
    echo ""
    test_password_expiry
    echo ""
    test_account_lockout
    echo ""
    
    echo "=========================================="
    echo "测试结果: $pass 通过, $fail 失败"
    echo "=========================================="
    
    [ $fail -eq 0 ] && exit 0 || exit 1
}

main
