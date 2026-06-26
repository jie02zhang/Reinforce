#!/bin/bash
# 测试脚本：验证 SSH 硬化配置
# 用法: bash test_ssh_hardening.sh [verbose]

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

# 测试 1: SSH 服务状态
test_ssh_service() {
    log_info "测试 1: SSH 服务状态"
    
    if systemctl is-active sshd &>/dev/null || systemctl is-active ssh &>/dev/null; then
        log_pass "SSH 服务正在运行"
    else
        log_fail "SSH 服务未运行"
    fi
}

# 测试 2: SSH 关键安全配置
test_ssh_config() {
    log_info "测试 2: SSH 关键安全配置"
    
    if [ ! -f /etc/ssh/sshd_config ]; then
        log_fail "sshd_config 文件不存在"
        return
    fi
    
    # 创建临时合并文件（包含 include）
    local config_file="/tmp/sshd_config_test"
    if command -v sshd &>/dev/null; then
        # 使用 sshd -T 获取有效配置
        sshd -T 2>/dev/null > "$config_file" || cat /etc/ssh/sshd_config > "$config_file"
    else
        cat /etc/ssh/sshd_config > "$config_file"
    fi
    
    # 测试各项配置
    local params=(
        "PermitRootLogin:no"
        "PasswordAuthentication:no"
        "PermitEmptyPasswords:no"
        "X11Forwarding:no"
        "MaxAuthTries:3"
        "Protocol:2"
        "UseDNS:no"
        "GSSAPIAuthentication:no"
    )
    
    for param in "${params[@]}"; do
        local key="${param%%:*}"
        local expected="${param##*:}"
        
        # 从 sshd -T 输出中读取（更可靠）
        local actual
        if command -v sshd &>/dev/null; then
            actual=$(sshd -T 2>/dev/null | grep -i "^${key,,}" | awk '{print $2}' | head -1)
        else
            actual=$(grep -E "^${key}" /etc/ssh/sshd_config | awk '{print $2}' | tail -1)
        fi
        
        if [ -z "$actual" ]; then
            log_fail "$key 未配置"
        elif [[ "${actual,,}" == "${expected,,}" ]]; then
            log_pass "$key 已正确设置: $actual"
        else
            log_fail "$key 未正确设置 (当前: $actual, 期望: $expected)"
        fi
    done
    
    rm -f "$config_file"
}

# 测试 3: SSH Banner
test_ssh_banner() {
    log_info "测试 3: SSH Banner"
    
    if [ -f /etc/ssh/banner ]; then
        log_pass "SSH banner 文件已创建"
        
        if grep -q "Authorized access only" /etc/ssh/banner 2>/dev/null; then
            log_pass "SSH banner 内容正确"
        else
            log_fail "SSH banner 内容不正确"
        fi
    else
        log_fail "SSH banner 文件不存在"
    fi
    
    # 检查 sshd_config 是否引用 banner
    if grep -q "^Banner" /etc/ssh/sshd_config 2>/dev/null; then
        log_pass "sshd_config 已配置 Banner"
    else
        log_fail "sshd_config 未配置 Banner"
    fi
}

# 测试 4: SSH 密钥认证
test_ssh_key_auth() {
    log_info "测试 4: SSH 密钥认证"
    
    if grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config 2>/dev/null || \
       sshd -T 2>/dev/null | grep -q "^pubkeyauthentication yes"; then
        log_pass "SSH 密钥认证已启用"
    else
        log_info "SSH 密钥认证未明确启用（可能使用默认值）"
    fi
}

# 测试 5: SSH 登录警告 (MOTD)
test_motd() {
    log_info "测试 5: MOTD 警告横幅"
    
    if [ -f /etc/motd ]; then
        if grep -q "Authorized access only" /etc/motd 2>/dev/null; then
            log_pass "MOTD 已配置警告横幅"
        else
            log_fail "MOTD 未配置警告横幅"
        fi
    else
        log_fail "MOTD 文件不存在"
    fi
}

# 主函数
main() {
    echo "=========================================="
    echo "SSH 硬化测试脚本"
    echo "系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    test_ssh_service
    echo ""
    test_ssh_config
    echo ""
    test_ssh_banner
    echo ""
    test_ssh_key_auth
    echo ""
    test_motd
    echo ""
    
    echo "=========================================="
    echo "测试结果: $pass 通过, $fail 失败"
    echo "=========================================="
    
    [ $fail -eq 0 ] && exit 0 || exit 1
}

main
