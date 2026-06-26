#!/usr/bin/env bash
# test_password_policy.sh - 密码策略测试脚本

set -euo pipefail

echo "=========================================="
echo "测试 1: 密码策略"
echo "=========================================="
echo ""

# ================= 1. 检查 PAM 配置 =================
echo "1. 检查 PAM 配置..."

PAM_FILES=(
    "/etc/pam.d/common-password"
    "/etc/pam.d/system-auth"
    "/etc/pam.d/password-auth"
)

PAM_MODULE=""
for pam_file in "${PAM_FILES[@]}"; do
    if [ -f "$pam_file" ]; then
        echo "  检查 $pam_file ..."
        
        # 查找使用的 PAM 模块
        if grep -q "pam_pwquality.so" "$pam_file" 2>/dev/null; then
            PAM_MODULE="pam_pwquality.so"
        elif grep -q "pam_cracklib.so" "$pam_file" 2>/dev/null; then
            PAM_MODULE="pam_cracklib.so"
        fi
        
        # 检查模块文件是否存在
        if [ -n "$PAM_MODULE" ]; then
            if [ -f "/lib/security/$PAM_MODULE" ] || [ -f "/lib64/security/$PAM_MODULE" ]; then
                echo "  [PASS] $PAM_MODULE 存在"
            else
                echo "  [FAIL] $PAM_MODULE 不存在！"
                echo "  → 这会导致密码修改失败"
            fi
        fi
        
        # 显示 PAM 配置
        echo "  PAM 配置:"
        grep -E "^password.*pam_(pwquality|cracklib)\.so" "$pam_file" | sed 's/^/    /'
    fi
done

if [ -z "$PAM_MODULE" ]; then
    echo "  [WARN] 未找到 PAM 密码强度模块配置"
fi

echo ""

# ================= 2. 检查密码复杂度参数 =================
echo "2. 检查密码复杂度参数..."

if [ -f /etc/security/pwquality.conf ]; then
    echo "  /etc/security/pwquality.conf:"
    grep -E "^minlen|^dcredit|^ucredit|^lcredit|^ocredit" /etc/security/pwquality.conf 2>/dev/null | sed 's/^/    /' || \
        echo "    (使用默认值)"
elif [ -f /etc/security/cracklib.conf ]; then
    echo "  /etc/security/cracklib.conf:"
    cat /etc/security/cracklib.conf | sed 's/^/    /'
else
    echo "  [INFO] 未找到密码配置文件"
fi

echo ""

# ================= 3. 检查 /etc/login.defs =================
echo "3. 检查 /etc/login.defs ..."

echo "  密码过期策略:"
grep -E "^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_MIN_LEN|^PASS_WARN_AGE" /etc/login.defs 2>/dev/null | sed 's/^/    /' || \
    echo "    (未配置)"

echo ""

# ================= 4. 测试密码修改 =================
echo "4. 测试密码修改..."

# 创建测试用户
TEST_USER="testuser_pwd_$$"
useradd -m "$TEST_USER" 2>/dev/null || \
    adduser -D "$TEST_USER" 2>/dev/null || true

if id "$TEST_USER" &>/dev/null; then
    echo "  测试用户: $TEST_USER"
    
    # 尝试修改密码
    echo "  尝试修改密码为强密码 (Test@123456)..."
    if echo "$TEST_USER:Test@123456" | chpasswd 2>&1; then
        echo "  [PASS] 强密码修改成功"
    else
        echo "  [FAIL] 强密码修改失败"
        echo "  → 可能 PAM 配置错误"
    fi
    
    # 尝试弱密码（应该失败）
    echo "  尝试修改密码为弱密码 (123)..."
    if echo "$TEST_USER:123" | chpasswd 2>&1; then
        echo "  [FAIL] 弱密码被接受（密码策略未生效）"
    else
        echo "  [PASS] 弱密码被拒绝"
    fi
    
    # 清理
    userdel -r "$TEST_USER" 2>/dev/null || true
else
    echo "  [WARN] 无法创建测试用户，跳过密码修改测试"
fi

echo ""

# ================= 5. 检查密码过期信息 =================
echo "5. 检查密码过期信息..."

if command -v chage &>/dev/null; then
    echo "  当前用户 ($(whoami)) 的密码策略:"
    chage -l "$(whoami)" 2>&1 | head -6 | sed 's/^/    /' || true
fi

echo ""

# ================= 总结 =================
echo "=========================================="
echo "密码策略测试完成"
echo "=========================================="

# 返回结果
if [ -n "$PAM_MODULE" ] && \
   { [ -f "/lib/security/$PAM_MODULE" ] || [ -f "/lib64/security/$PAM_MODULE" ]; }; then
    echo "[RESULT] 密码策略配置正确"
    exit 0
else
    echo "[RESULT] 密码策略配置有误，请检查"
    exit 1
fi
