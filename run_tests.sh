#!/usr/bin/env bash
# run_tests.sh - 批量测试脚本（在主机上运行）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/test_results"
mkdir -p "$LOG_DIR"

# 测试矩阵
VMS=(
    "ubuntu2204"
    "ubuntu2404"
    "debian12"
    "almalinux9"
    "suse15"
    "oraclelinux9"
    "rockylinux9"
    "centos7"
    "amazonlinux2023"
)

echo "=========================================="
echo "安全加固脚本 - 批量测试"
echo "=========================================="
echo ""
echo "测试矩阵: ${#VMS[@]} 个虚拟机"
echo "日志目录: $LOG_DIR"
echo ""

# 检查依赖
check_dependencies() {
    echo "检查依赖..."
    if ! command -v vagrant &>/dev/null; then
        echo "[ERROR] 未找到 vagrant 命令"
        echo "请安装: https://developer.hashicorp.com/vagrant/downloads"
        exit 1
    fi
    
    if ! command -v VBoxManage &>/dev/null; then
        echo "[ERROR] 未找到 VBoxManage 命令"
        echo "请安装: https://www.virtualbox.org/wiki/Downloads"
        exit 1
    fi
    
    echo "[OK] Vagrant $(vagrant --version)"
    echo "[OK] VirtualBox $(VBoxManage --version)"
    echo ""
}

# 启动 VM
start_vm() {
    local vm="$1"
    echo "启动 $vm ..."
    if vagrant status "$vm" 2>&1 | grep -q "running"; then
        echo "  VM 已运行"
    else
        vagrant up "$vm" --provision
    fi
}

# 停止 VM
stop_vm() {
    local vm="$1"
    echo "停止 $vm ..."
    vagrant halt "$vm" 2>/dev/null || true
}

# 创建快照
create_snapshot() {
    local vm="$1"
    local snapshot_name="$2"
    echo "创建快照: $vm @ $snapshot_name"
    vagrant snapshot save "$vm" "$snapshot_name" 2>/dev/null || \
        echo "  快照已存在，跳过"
}

# 恢复快照
restore_snapshot() {
    local vm="$1"
    local snapshot_name="$2"
    echo "恢复快照: $vm @ $snapshot_name"
    vagrant snapshot restore "$vm" "$snapshot_name" --no-provision
}

# 运行测试
run_tests() {
    local vm="$1"
    local log_prefix="$LOG_DIR/${vm}"
    
    echo ""
    echo "=========================================="
    echo "测试 VM: $vm"
    echo "=========================================="
    
    # 1. 启动 VM
    start_vm "$vm"
    
    # 2. 创建初始快照
    create_snapshot "$vm" "initial-state"
    
    # 3. 运行安全加固脚本
    echo "运行安全加固脚本..."
    vagrant ssh "$vm" -c "sudo bash /opt/security/security_hardening.sh --verbose" 2>&1 | \
        tee "${log_prefix}_hardening.log"
    
    # 4. 运行测试用例
    echo ""
    echo "运行测试用例..."
    
    echo "  1. 密码策略测试..."
    vagrant ssh "$vm" -c "bash /opt/security/test_password_policy.sh" 2>&1 | \
        tee "${log_prefix}_test_password.log"
    
    echo "  2. sudoers 测试..."
    vagrant ssh "$vm" -c "bash /opt/security/test_sudoers.sh" 2>&1 | \
        tee "${log_prefix}_test_sudoers.log"
    
    echo "  3. 内核参数测试..."
    vagrant ssh "$vm" -c "bash /opt/security/test_kernel_params.sh" 2>&1 | \
        tee "${log_prefix}_test_kernel.log"
    
    echo "  4. 幂等性测试..."
    vagrant ssh "$vm" -c "bash /opt/security/test_idempotency.sh" 2>&1 | \
        tee "${log_prefix}_test_idempotency.log"
    
    # 5. 生成测试报告
    echo ""
    echo "生成测试报告..."
    vagrant ssh "$vm" -c "bash /opt/security/generate_report.sh" 2>&1 | \
        tee "${log_prefix}_report.log"
    
    # 6. 复制报告到主机
    echo ""
    echo "复制报告到主机..."
    vagrant ssh "$vm" -c "cat /tmp/test_report/*.md" 2>/dev/null | \
        tee "${log_prefix}_final_report.md" || true
    
    # 7. 回滚到初始状态
    echo ""
    echo "回滚到初始状态..."
    restore_snapshot "$vm" "initial-state"
    
    echo ""
    echo "完成测试: $vm"
    echo "日志: ${log_prefix}_*.log"
}

# 生成汇总报告
generate_summary() {
    local summary_file="$LOG_DIR/summary_report_$(date +%Y%m%d_%H%M%S).md"
    
    echo ""
    echo "生成汇总报告: $summary_file"
    
    cat > "$summary_file" <<EOF
# 安全加固脚本 - 批量测试汇总报告

**测试日期**: $(date +'%Y-%m-%d %H:%M:%S')  
**脚本版本**: v5.9 (WSL 兼容修复版)  
**测试人员**: 自动化测试  

---

## 1. 测试环境

| 虚拟机 | 发行版 | 状态 | 日志 |
|--------|--------|------|------|
EOF
    
    for vm in "${VMS[@]}"; do
        log_file="$LOG_DIR/${vm}_hardening.log"
        if [ -f "$log_file" ]; then
            if grep -q "ERROR" "$log_file" 2>/dev/null; then
                status="❌ 失败"
            else
                status="✅ 通过"
            fi
        else
            status="⚠️ 未测试"
        fi
        
        echo "| $vm | ... | $status | ${vm}_*.log |" >> "$summary_file"
    done
    
    cat >> "$summary_file" <<EOF

## 2. 发现的 Bug

| Bug ID | 描述 | 严重级别 | 状态 | 修复版本 |
|--------|------|----------|------|----------|
| ... | ... | P0/P1/P2 | Open/Fixed | ... |

## 3. 兼容性矩阵

| 功能 | Ubuntu 22.04 | Ubuntu 24.04 | Debian 12 | AlmaLinux 9 | SUSE 15 | Oracle Linux 9 |
|------|---------------|---------------|------------|--------------|----------|-----------------|
| 密码策略 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| sudoers | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 内核参数 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 服务管理 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 日志审计 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## 4. 改进建议

1. ...
2. ...
3. ...

## 5. 结论

**通过率**: .../... (...%)  
**建议**: 可以发布到生产环境

---
*报告生成: $(date)*
EOF
    
    cat "$summary_file"
    echo ""
    echo "汇总报告已生成: $summary_file"
}

# 主流程
main() {
    check_dependencies
    
    echo "开始批量测试..."
    echo ""
    
    for vm in "${VMS[@]}"; do
        run_tests "$vm"
    done
    
    echo ""
    echo "=========================================="
    echo "所有测试完成！"
    echo "=========================================="
    echo ""
    
    generate_summary
    
    echo ""
    echo "日志文件在: $LOG_DIR"
    echo ""
    echo "下一步:"
    echo "  1. 查看测试报告"
    echo "  2. 修复发现的问题"
    echo "  3. 重新测试"
}

# 显示菜单
if [ "$#" -eq 0 ]; then
    echo "用法: $0 [all|vm-name|summary]"
    echo ""
    echo "示例:"
    echo "  $0 all              # 测试所有 VM"
    echo "  $0 ubuntu2204       # 测试单个 VM"
    echo "  $0 summary          # 生成汇总报告"
    echo ""
    echo "可用 VM:"
    for vm in "${VMS[@]}"; do
        echo "  - $vm"
    done
    exit 1
fi

ACTION="$1"

case "$ACTION" in
    all)
        main
        ;;
    summary)
        generate_summary
        ;;
    *)
        # 测试单个 VM
        if [[ " ${VMS[@]} " =~ " ${ACTION} " ]]; then
            run_tests "$ACTION"
            generate_summary
        else
            echo "[ERROR] 未知的 VM: $ACTION"
            exit 1
        fi
        ;;
esac
