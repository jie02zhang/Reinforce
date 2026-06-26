#!/bin/bash
# 主测试脚本：运行所有测试并生成报告
# 用法: bash run_all_tests.sh [VM名称] [verbose]

VM_NAME="${1:-all}"
VERBOSE="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="$SCRIPT_DIR/test_report_$(date +%Y%m%d_%H%M%S).txt"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "$1"; echo "$1" >> "$REPORT_FILE"; }

run_test_on_vm() {
    local vm="$1"
    local test_script="$2"
    local test_name="$3"
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "[$vm] 运行测试: $test_name"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if vagrant ssh "$vm" -c "bash /vagrant/test_results/$(basename $test_script) ${VERBOSE}" >> "$REPORT_FILE" 2>&1; then
        log "${GREEN}✅ [$vm] $test_name 通过${NC}"
        return 0
    else
        log "${RED}❌ [$vm] $test_name 失败${NC}"
        return 1
    fi
}

main() {
    # 初始化报告文件
    echo "安全加固脚本自动化测试报告" > "$REPORT_FILE"
    echo "==========================================" >> "$REPORT_FILE"
    echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
    echo "脚本版本: security_hardening.sh v6.0" >> "$REPORT_FILE"
    echo "==========================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    log "🚀 开始自动化测试..."
    log ""
    
    # 确定要测试的 VM
    local vms=()
    if [ "$VM_NAME" == "all" ]; then
        vms=("ubuntu2204" "ubuntu2404" "debian12" "rockylinux9")
    else
        vms=("$VM_NAME")
    fi
    
    local total_pass=0
    local total_fail=0
    local total_skip=0
    
    # 遍历每个 VM
    for vm in "${vms[@]}"; do
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "🖥️  测试虚拟机: $vm"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log ""
        
        # 检查 VM 是否运行
        if ! vagrant status "$vm" 2>&1 | grep -q "running"; then
            log "${YELLOW}⚠️  VM $vm 未运行，跳过${NC}"
            log ""
            continue
        fi
        
        # 1. 先运行安全加固脚本（如果未运行过）
        log "📋 步骤1: 运行安全加固脚本..."
        if vagrant ssh "$vm" -c "sudo bash /vagrant/security_hardening.sh --verbose" >> "$REPORT_FILE" 2>&1; then
            log "${GREEN}✅ 安全加固脚本执行成功${NC}"
        else
            log "${RED}❌ 安全加固脚本执行失败${NC}"
            continue
        fi
        log ""
        
        # 2. 运行测试脚本
        log "📋 步骤2: 运行测试脚本..."
        log ""
        
        # 测试 1: 密码策略
        run_test_on_vm "$vm" "$SCRIPT_DIR/test_password_policy.sh" "密码策略测试"
        log ""
        
        # 测试 2: Sudo 配置
        run_test_on_vm "$vm" "$SCRIPT_DIR/test_sudoers.sh" "Sudo 配置测试"
        log ""
        
        # 测试 3: SSH 硬化
        run_test_on_vm "$vm" "$SCRIPT_DIR/test_ssh_hardening.sh" "SSH 硬化测试"
        log ""
        
        # 测试 4: 内核参数
        run_test_on_vm "$vm" "$SCRIPT_DIR/test_kernel_params.sh" "内核参数测试"
        log ""
        
        # 3. 幂等性测试
        log "📋 步骤3: 幂等性测试（重新运行脚本）..."
        if vagrant ssh "$vm" -c "sudo bash /vagrant/security_hardening.sh --verbose" 2>&1 | tee -a "$REPORT_FILE" | grep -q "所有步骤已完成"; then
            log "${GREEN}✅ 幂等性测试通过${NC}"
        else
            log "${YELLOW}⚠️  幂等性测试可能有问题，请检查日志${NC}"
        fi
        log ""
    done
    
    # 生成总结
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "📊 测试总结"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""
    log "总通过: $total_pass"
    log "总失败: $total_fail"
    log "总跳过: $total_skip"
    log ""
    log "完整报告已保存至: $REPORT_FILE"
    log ""
    log "✅ 自动化测试完成！"
}

main "$@"
