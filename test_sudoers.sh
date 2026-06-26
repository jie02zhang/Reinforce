#!/usr/bin/env bash
# test_sudoers.sh - sudoers 配置测试脚本

set -euo pipefail

echo "=========================================="
echo "测试 2: sudoers 配置"
echo "=========================================="
echo ""

# ================= 1. 检查 sudoers 语法 =================
echo "1. 检查 /etc/sudoers 语法..."

if command -v visudo &>/dev/null; then
    if visudo -c 2>&1; then
        echo "  [PASS] sudoers 语法正确"
    else
        echo "  [FAIL] sudoers 语法错误！"
        echo "  → 详细信息:"
        visudo -c 2>&1 | sed 's/^/    /'
        exit 1
    fi
else
    echo "  [WARN] 未找到 visudo 命令"
fi

echo ""

# ================= 2. 检查 drop-in 文件 =================
echo "2. 检查 drop-in 文件..."

if [ -d /etc/sudoers.d ]; then
    echo "  /etc/sudoers.d/ 目录存在"
    echo "  文件列表:"
    ls -l /etc/sudoers.d/ 2>/dev/null | sed 's/^/    /' || echo "    (空目录)"
    
    # 检查是否有我们的配置文件
    if [ -f /etc/sudoers.d/security_hardening ]; then
        echo "  [PASS] security_hardening drop-in 文件存在"
        echo "  内容:"
        cat /etc/sudoers.d/security_hardening | sed 's/^/    /'
        
        # 验证语法
        if visudo -cf /etc/sudoers.d/security_hardening 2>&1; then
            echo "  [PASS] drop-in 文件语法正确"
        else
            echo "  [FAIL] drop-in 文件语法错误！"
        fi
    else
        echo "  [INFO] security_hardening drop-in 文件不存在"
        echo "  → 可能脚本未执行或使用了直接修改方式"
    fi
else
    echo "  [WARN] /etc/sudoers.d/ 目录不存在"
fi

echo ""

# ================= 3. 检查 sudo 日志配置 =================
echo "3. 检查 sudo 日志配置..."

# 检查 sudoers 中是否配置了日志文件
if grep -q "logfile" /etc/sudoers 2>/dev/null || \
   grep -q "logfile" /etc/sudoers.d/* 2>/dev/null; then
    echo "  [PASS] sudo 日志已配置"
    echo "  配置:"
    grep -r "logfile" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | sed 's/^/    /' || true
else
    echo "  [INFO] sudo 日志未配置"
fi

# 检查日志文件
SUDO_LOG=""
if [ -f /var/log/sudo.log ]; then
    SUDO_LOG="/var/log/sudo.log"
elif [ -f /var/log/sudo.log ]; then
    SUDO_LOG="/var/log/sudo.log"
fi

if [ -n "$SUDO_LOG" ] && [ -f "$SUDO_LOG" ]; then
    echo "  [PASS] sudo 日志文件存在: $SUDO_LOG"
    echo "  最近日志:"
    tail -5 "$SUDO_LOG" 2>/dev/null | sed 's/^/    /' || true
else
    echo "  [INFO] sudo 日志文件不存在（可能尚未使用 sudo）"
fi

echo ""

# ================= 4. 测试 sudo 功能 =================
echo "4. 测试 sudo 功能..."

# 测试 sudo -l
echo "  测试 sudo -l ..."
if sudo -l >/dev/null 2>&1; then
    echo "  [PASS] sudo -l 成功"
else
    echo "  [FAIL] sudo -l 失败"
fi

# 测试 sudo 命令
echo "  测试 sudo 执行命令..."
if sudo whoami 2>&1 | grep -q "root"; then
    echo "  [PASS] sudo 命令执行成功"
    
    # 检查是否记录了日志
    if [ -n "$SUDO_LOG" ] && [ -f "$SUDO_LOG" ]; then
        if tail -10 "$SUDO_LOG" 2>/dev/null | grep -q "COMMAND"; then
            echo "  [PASS] sudo 日志已记录"
        else
            echo "  [INFO] sudo 日志尚未记录（可能需要配置 logfile）"
        fi
    fi
else
    echo "  [FAIL] sudo 命令执行失败"
fi

echo ""

# ================= 5. 检查 /etc/sudoers 修改 =================
echo "5. 检查 /etc/sudoers 修改..."

# 检查是否有直接修改（不推荐）
if [ -f /etc/sudoers.bak ]; then
    echo "  [INFO] 发现 /etc/sudoers.bak（脚本可能备份了原文件）"
fi

# 显示关键配置
echo "  当前配置（Defaults 部分）:"
grep "^Defaults" /etc/sudoers 2>/dev/null | head -10 | sed 's/^/    /' || true

echo ""

# ================= 总结 =================
echo "=========================================="
echo "sudoers 配置测试完成"
echo "=========================================="

# 返回结果
if visudo -c 2>/dev/null; then
    echo "[RESULT] sudoers 配置正确"
    exit 0
else
    echo "[RESULT] sudoers 配置有误，请检查"
    exit 1
fi
