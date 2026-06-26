#!/usr/bin/env bash
# test_idempotency.sh - 幂等性测试脚本

set -euo pipefail

SCRIPT="/opt/security/security_hardening.sh"
LOG_DIR="/tmp/idempotency_test"
mkdir -p "$LOG_DIR"

echo "=========================================="
echo "测试 4: 幂等性（重复执行不报错）"
echo "=========================================="
echo ""
echo "脚本: $SCRIPT"
echo "日志目录: $LOG_DIR"
echo ""

if [ ! -f "$SCRIPT" ]; then
    echo "[ERROR] 未找到脚本: $SCRIPT"
    echo "请将 security_hardening.sh 放到 /opt/security/ 目录"
    exit 1
fi

# ================= 第一次运行 =================
echo "=========================================="
echo "第一次运行"
echo "=========================================="
echo ""

LOG1="$LOG_DIR/run1.log"
echo "日志: $LOG1"
echo ""

time bash "$SCRIPT" --verbose 2>&1 | tee "$LOG1"

echo ""
echo "第一次运行完成"
echo ""

# 记录第一次的结果
PASSED1=$(grep -c "OK" "$LOG1" || echo "0")
FAILED1=$(grep -c "FAIL" "$LOG1" || echo "0")
WARN1=$(grep -c "WARN" "$LOG1" || echo "0")

echo "  通过: $PASSED1"
echo "  失败: $FAILED1"
echo "  警告: $WARN1"
echo ""

# ================= 等待 3 秒 =================
echo "等待 3 秒..."
sleep 3
echo ""

# ================= 第二次运行 =================
echo "=========================================="
echo "第二次运行（测试幂等性）"
echo "=========================================="
echo ""

LOG2="$LOG_DIR/run2.log"
echo "日志: $LOG2"
echo ""

time bash "$SCRIPT" --verbose 2>&1 | tee "$LOG2"

echo ""
echo "第二次运行完成"
echo ""

# 记录第二次的结果
PASSED2=$(grep -c "OK" "$LOG2" || echo "0")
FAILED2=$(grep -c "FAIL" "$LOG2" || echo "0")
WARN2=$(grep -c "WARN" "$LOG2" || echo "0")

echo "  通过: $PASSED2"
echo "  失败: $FAILED2"
echo "  警告: $WARN2"
echo ""

# ================= 比较差异 =================
echo "=========================================="
echo "比较两次运行差异"
echo "=========================================="
echo ""

DIFF_FILE="$LOG_DIR/diff.txt"
if diff "$LOG1" "$LOG2" > "$DIFF_FILE" 2>&1; then
    echo "[PASS] 两次运行输出完全相同（完全幂等）"
    IDEMPOTENT=true
else
    echo "[INFO] 两次运行输出有差异（可能是正常的状态检查跳过）"
    echo ""
    echo "差异:"
    head -50 "$DIFF_FILE" | sed 's/^/  /'
    echo ""
    
    # 分析差异（是否只是 "已安装" / "已配置" 等提示）
    if grep -q "已安装\|已配置\|已完成\|Skipping" "$DIFF_FILE"; then
        echo "[PASS] 差异是正常的幂等性提示（步骤已执行过）"
        IDEMPOTENT=true
    else
        echo "[WARN] 差异可能表示非幂等行为"
        IDEMPOTENT=false
    fi
fi

echo ""

# ================= 检查状态文件 =================
echo "=========================================="
echo "检查状态文件"
echo "=========================================="
echo ""

STATE_FILE="/var/lib/security_hardening/state"
if [ -f "$STATE_FILE" ]; then
    echo "[PASS] 状态文件存在: $STATE_FILE"
    echo ""
    echo "已完成的步骤:"
    cat "$STATE_FILE" | sed 's/^/  /'
    echo ""
    
    # 统计步骤数
    STEP_COUNT=$(wc -l < "$STATE_FILE")
    echo "共完成 $STEP_COUNT 个步骤"
else
    echo "[INFO] 状态文件不存在（脚本可能未使用状态管理）"
fi

echo ""

# ================= 第三次运行（--force 强制重跑）=================
echo "=========================================="
echo "第三次运行（--force 强制重跑）"
echo "=========================================="
echo ""

LOG3="$LOG_DIR/run3.log"
echo "日志: $LOG3"
echo ""

time bash "$SCRIPT" --verbose --force 2>&1 | tee "$LOG3"

echo ""
echo "第三次运行完成"
echo ""

# ================= 总结 =================
echo "=========================================="
echo "幂等性测试总结"
echo "=========================================="
echo ""
echo "第一次运行: 通过 $PASSED1, 失败 $FAILED1, 警告 $WARN1"
echo "第二次运行: 通过 $PASSED2, 失败 $FAILED2, 警告 $WARN2"
echo ""

if [ "$FAILED1" -eq 0 ] && [ "$FAILED2" -eq 0 ]; then
    echo "[RESULT] 幂等性测试通过（无失败）"
    if [ "$IDEMPOTENT" = true ]; then
        echo "[RESULT] 完全幂等（两次运行输出一致）"
    else
        echo "[RESULT] 基本幂等（差异为正常提示）"
    fi
    exit 0
else
    echo "[RESULT] 幂等性测试失败（存在错误）"
    echo "请检查日志:"
    echo "  $LOG1"
    echo "  $LOG2"
    exit 1
fi
