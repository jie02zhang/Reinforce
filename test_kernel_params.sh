#!/usr/bin/env bash
# test_kernel_params.sh - 内核参数测试脚本

set -euo pipefail

echo "=========================================="
echo "测试 3: 内核参数"
echo "=========================================="
echo ""

# ================= 定义检查项 =================
declare -A EXPECTED_PARAMS=(
    ["kernel.randomize_va_space"]="2"
    ["net.ipv4.ip_forward"]="0"
    ["net.ipv4.conf.all.accept_redirects"]="0"
    ["net.ipv4.conf.default.accept_redirects"]="0"
    ["net.ipv4.conf.all.send_redirects"]="0"
    ["net.ipv4.tcp_syncookies"]="1"
    ["net.ipv4.conf.all.accept_source_route"]="0"
    ["net.ipv4.conf.default.accept_source_route"]="0"
    ["net.ipv4.icmp_echo_ignore_broadcasts"]="1"
    ["net.ipv6.conf.all.accept_redirects"]="0"
    ["net.ipv6.conf.default.accept_redirects"]="0"
    ["fs.suid_dumpable"]="0"
    ["kernel.sysrq"]="0"
)

PASSED=0
FAILED=0
TOTAL=${#EXPECTED_PARAMS[@]}

# ================= 1. 检查关键参数 =================
echo "1. 检查关键内核参数..."
echo ""

for param in "${!EXPECTED_PARAMS[@]}"; do
    expected="${EXPECTED_PARAMS[$param]}"
    actual=$(sysctl -n "$param" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$actual" = "NOT_FOUND" ]; then
        echo "  [WARN] $param: 参数不存在"
        ((FAILED++))
    elif [ "$actual" = "$expected" ]; then
        echo "  [PASS] $param = $actual"
        ((PASSED++))
    else
        echo "  [FAIL] $param: 期望 $expected, 实际 $actual"
        ((FAILED++))
    fi
done

echo ""

# ================= 2. 检查 /etc/sysctl.conf =================
echo "2. 检查 /etc/sysctl.conf ..."

if [ -f /etc/sysctl.conf ]; then
    echo "  文件存在: /etc/sysctl.conf"
    
    # 检查是否有我们的配置
    if grep -q "kernel.randomize_va_space" /etc/sysctl.conf 2>/dev/null; then
        echo "  [PASS] 参数已写入 /etc/sysctl.conf"
        echo "  相关配置:"
        grep -E "^(kernel|net|fs)\." /etc/sysctl.conf 2>/dev/null | grep -v "^#" | head -10 | sed 's/^/    /' || true
    else
        echo "  [INFO] 未找到安全加固配置"
        echo "  → 可能脚本未执行或使用了其他配置文件"
    fi
else
    echo "  [WARN] /etc/sysctl.conf 不存在"
fi

# 检查 /etc/sysctl.d/ 目录
if [ -d /etc/sysctl.d ]; then
    echo ""
    echo "  检查 /etc/sysctl.d/ ..."
    security_file=$(find /etc/sysctl.d/ -name "*security*" -o -name "*hardening*" 2>/dev/null | head -1)
    if [ -n "$security_file" ]; then
        echo "  [PASS] 找到安全配置文件: $security_file"
        echo "  内容:"
        cat "$security_file" | sed 's/^/    /' | head -20
    else
        echo "  [INFO] 未找到 security/hardening 配置文件"
        echo "  /etc/sysctl.d/ 文件列表:"
        ls -l /etc/sysctl.d/ 2>/dev/null | sed 's/^/    /' || true
    fi
fi

echo ""

# ================= 3. 测试生效性 =================
echo "3. 测试参数生效性..."

# 临时修改一个参数并恢复（测试 sysctl -w 是否生效）
TEST_PARAM="kernel.randomize_va_space"
TEST_VALUE_ORIG=$(sysctl -n "$TEST_PARAM" 2>/dev/null || echo "2")

echo "  测试: 临时修改 $TEST_PARAM ..."
if sysctl -w "${TEST_PARAM}=${TEST_VALUE_ORIG}" >/dev/null 2>&1; then
    echo "  [PASS] sysctl -w 可用（参数可动态修改）"
else
    echo "  [WARN] sysctl -w 失败（可能需要重启或参数只读）"
fi

echo ""

# ================= 4. 显示所有安全相关参数 =================
echo "4. 所有安全相关内核参数..."
echo ""

echo "  ASLR (地址空间随机化):"
sysctl "kernel.randomize_va_space" 2>/dev/null | sed 's/^/    /' || true

echo ""
echo "  IP 转发:"
sysctl "net.ipv4.ip_forward" 2>/dev/null | sed 's/^/    /' || true

echo ""
echo "  ICMP 重定向:"
sysctl "net.ipv4.conf.all.accept_redirects" 2>/dev/null | sed 's/^/    /' || true

echo ""
echo "  SYN Cookies:"
sysctl "net.ipv4.tcp_syncookies" 2>/dev/null | sed 's/^/    /' || true

echo ""

# ================= 总结 =================
echo "=========================================="
echo "内核参数测试完成"
echo "=========================================="
echo ""
echo "结果: $PASSED/$TOTAL 通过, $FAILED/$TOTAL 失败"

if [ $FAILED -eq 0 ]; then
    echo "[RESULT] 所有内核参数配置正确"
    exit 0
else
    echo "[RESULT] 部分内核参数配置有误，请检查"
    exit 1
fi
