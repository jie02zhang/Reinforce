#!/bin/bash
# 测试脚本：验证内核参数配置
# 用法: bash test_kernel_params.sh [verbose]

set -euo pipefail

VERBOSE="${1:-}"
LOG_PASS="[PASS]"
LOG_FAIL="[FAIL]"
LOG_INFO="[INFO]"
LOG_WARN="[WARN]"

[[ "$VERBOSE" == "verbose" ]] && VERBOSE=1 || VERBOSE=0

pass=0
fail=0
skip=0

log_pass() { echo "$LOG_PASS $1"; pass=$((pass + 1)); }
log_fail() { echo "$LOG_FAIL $1"; fail=$((fail + 1)); }
log_info() { echo "$LOG_INFO $1"; }
log_warn() { echo "$LOG_WARN $1"; skip=$((skip + 1)); }
log_verbose() { [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] $1" || true; }

# 内核参数测试用例
declare -A KERNEL_PARAMS=(
    # 网络参数
    ["net.ipv4.ip_forward"]="0"
    ["net.ipv4.conf.all.send_redirects"]="0"
    ["net.ipv4.conf.default.send_redirects"]="0"
    ["net.ipv4.conf.all.accept_redirects"]="0"
    ["net.ipv4.conf.default.accept_redirects"]="0"
    ["net.ipv4.conf.all.accept_source_route"]="0"
    ["net.ipv4.conf.default.accept_source_route"]="0"
    ["net.ipv4.conf.all.secure_redirects"]="0"
    ["net.ipv4.conf.default.secure_redirects"]="0"
    ["net.ipv4.conf.all.log_martians"]="1"
    ["net.ipv4.conf.default.log_martians"]="1"
    ["net.ipv4.tcp_syncookies"]="1"
    ["net.ipv4.tcp_max_syn_backlog"]="8192"
    ["net.ipv4.tcp_synack_retries"]="2"
    ["net.ipv6.conf.all.accept_ra"]="0"
    ["net.ipv6.conf.default.accept_ra"]="0"
    ["net.ipv6.conf.all.accept_redirects"]="0"
    ["net.ipv6.conf.default.accept_redirects"]="0"
    
    # 内核参数
    ["kernel.randomize_va_space"]="2"
    ["kernel.dmesg_restrict"]="1"
    ["kernel.sysrq"]="0"
    ["kernel.core_uses_pid"]="1"
    ["kernel.kptr_restrict"]="2"
    ["kernel.unprivileged_bpf_disabled"]="1"
    
    # 文件系统参数
    ["fs.suid_dumpable"]="0"
    ["fs.protected_hardlinks"]="1"
    ["fs.protected_symlinks"]="1"
)

# 测试：内核参数
test_kernel_params() {
    log_info "测试: 内核参数配置"
    
    for param in "${!KERNEL_PARAMS[@]}"; do
        local expected="${KERNEL_PARAMS[$param]}"
        local actual
        
        # 读取当前值
        actual=$(sysctl -n "$param" 2>/dev/null) || actual=""
        
        if [ -z "$actual" ]; then
            log_warn "$param 不存在（内核不支持）"
        elif [ "$actual" == "$expected" ]; then
            log_pass "$param = $actual"
        else
            log_fail "$param 未正确设置 (当前: $actual, 期望: $expected)"
        fi
    done
}

# 测试：/etc/sysctl.conf 或 /etc/sysctl.d/ 配置
test_sysctl_config() {
    log_info "测试: sysctl 配置文件"
    
    local config_file=""
    if [ -f /etc/sysctl.d/99-security_hardening.conf ]; then
        config_file="/etc/sysctl.d/99-security_hardening.conf"
    elif [ -f /etc/sysctl.conf ]; then
        config_file="/etc/sysctl.conf"
    fi
    
    if [ -n "$config_file" ]; then
        log_pass "sysctl 配置文件存在: $config_file"
        
        # 检查关键参数是否已写入文件
        local key_params=("net.ipv4.ip_forward" "net.ipv4.tcp_syncookies" "kernel.randomize_va_space")
        for param in "${key_params[@]}"; do
            if grep -q "$param" "$config_file" 2>/dev/null; then
                log_pass "$param 已写入配置文件"
            else
                log_fail "$param 未写入配置文件"
            fi
        done
    else
        log_fail "sysctl 配置文件不存在"
    fi
}

# 测试：系统资源限制 (/etc/security/limits.conf)
test_limits_config() {
    log_info "测试: 系统资源限制配置"
    
    local limits_file=""
    if [ -f /etc/security/limits.d/99-security_hardening.conf ]; then
        limits_file="/etc/security/limits.d/99-security_hardening.conf"
    elif [ -f /etc/security/limits.conf ]; then
        limits_file="/etc/security/limits.conf"
    fi
    
    if [ -n "$limits_file" ]; then
        log_pass "limits 配置文件存在: $limits_file"
        
        # 检查关键限制
        local limits=("* hard core 0" "* soft nofile 65535" "* hard nofile 65535")
        for limit in "${limits[@]}"; do
            if grep -q "$limit" "$limits_file" 2>/dev/null; then
                log_pass "限制已配置: $limit"
            else
                log_fail "限制未配置: $limit"
            fi
        done
    else
        log_fail "limits 配置文件不存在"
    fi
}

# 主函数
main() {
    echo "=========================================="
    echo "内核参数测试脚本"
    echo "系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'" -f2)"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    test_kernel_params
    echo ""
    test_sysctl_config
    echo ""
    test_limits_config
    echo ""
    
    echo "=========================================="
    echo "测试结果: $pass 通过, $fail 失败, $skip 跳过"
    echo "=========================================="
    
    [ $fail -eq 0 ] && exit 0 || exit 1
}

main
