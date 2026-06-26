#!/usr/bin/env bash
# snapshot_manager.sh - 快照管理工具

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助
show_help() {
    cat <<EOF
快照管理工具

用法: $SCRIPT_NAME <action> [vm-name] [snapshot-name]

动作 (action):
  list             列出所有 VM 的快照
  list <vm>       列出指定 VM 的快照
  create <vm> <name>  创建快照
  restore <vm> <name> 恢复快照
  delete <vm> <name>  删除快照
  clean <vm>          删除所有快照（保留当前状态）
  clean-all           删除所有 VM 的所有快照

示例:
  $SCRIPT_NAME list
  $SCRIPT_NAME list ubuntu2204
  $SCRIPT_NAME create ubuntu2204 initial-state
  $SCRIPT_NAME restore ubuntu2204 initial-state
  $SCRIPT_NAME delete ubuntu2204 initial-state
  $SCRIPT_NAME clean ubuntu2204
  $SCRIPT_NAME clean-all

EOF
}

# 检查依赖
check_dependencies() {
    if ! command -v vagrant &>/dev/null; then
        log_error "未找到 vagrant 命令"
        echo "请安装: https://developer.hashicorp.com/vagrant/downloads"
        exit 1
    fi
}

# 列出所有 VM
get_vm_list() {
    vagrant status 2>/dev/null | grep -E "^\w+" | awk '{print $1}' | grep -v "^$"
}

# 列出快照
list_snapshots() {
    local vm="${1:-}"
    
    if [ -z "$vm" ]; then
        # 列出所有 VM 的快照
        log_info "列出所有 VM 的快照..."
        echo ""
        
        for vm in $(get_vm_list); do
            echo "=========================================="
            echo "VM: $vm"
            echo "=========================================="
            vagrant snapshot list "$vm" 2>/dev/null || log_warn "无法列出 $vm 的快照"
            echo ""
        done
    else
        # 列出指定 VM 的快照
        log_info "列出 $vm 的快照..."
        echo ""
        vagrant snapshot list "$vm" 2>/dev/null || log_error "无法列出 $vm 的快照"
    fi
}

# 创建快照
create_snapshot() {
    local vm="$1"
    local snapshot_name="$2"
    
    if [ -z "$vm" ] || [ -z "$snapshot_name" ]; then
        log_error "请指定 VM 名称和快照名称"
        echo "用法: $SCRIPT_NAME create <vm-name> <snapshot-name>"
        exit 1
    fi
    
    log_info "创建快照: $vm @ $snapshot_name"
    
    if vagrant snapshot save "$vm" "$snapshot_name"; then
        log_info "快照创建成功: $vm @ $snapshot_name"
    else
        log_error "快照创建失败"
        exit 1
    fi
}

# 恢复快照
restore_snapshot() {
    local vm="$1"
    local snapshot_name="$2"
    
    if [ -z "$vm" ] || [ -z "$snapshot_name" ]; then
        log_error "请指定 VM 名称和快照名称"
        echo "用法: $SCRIPT_NAME restore <vm-name> <snapshot-name>"
        exit 1
    fi
    
    log_info "恢复快照: $vm @ $snapshot_name"
    log_warn "这将丢弃当前状态，确定吗？"
    read -p "输入 'yes' 继续: " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "取消恢复"
        exit 0
    fi
    
    if vagrant snapshot restore "$vm" "$snapshot_name" --no-provision; then
        log_info "快照恢复成功: $vm @ $snapshot_name"
    else
        log_error "快照恢复失败"
        exit 1
    fi
}

# 删除快照
delete_snapshot() {
    local vm="$1"
    local snapshot_name="$2"
    
    if [ -z "$vm" ] || [ -z "$snapshot_name" ]; then
        log_error "请指定 VM 名称和快照名称"
        echo "用法: $SCRIPT_NAME delete <vm-name> <snapshot-name>"
        exit 1
    fi
    
    log_warn "删除快照: $vm @ $snapshot_name"
    log_warn "确定吗？"
    read -p "输入 'yes' 继续: " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "取消删除"
        exit 0
    fi
    
    if vagrant snapshot delete "$vm" "$snapshot_name"; then
        log_info "快照删除成功: $vm @ $snapshot_name"
    else
        log_error "快照删除失败"
        exit 1
    fi
}

# 清理 VM 的所有快照
clean_vm() {
    local vm="$1"
    
    if [ -z "$vm" ]; then
        log_error "请指定 VM 名称"
        echo "用法: $SCRIPT_NAME clean <vm-name>"
        exit 1
    fi
    
    log_warn "清理 $vm 的所有快照..."
    log_warn "这将删除所有快照，但保留当前状态"
    read -p "输入 'yes' 继续: " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "取消清理"
        exit 0
    fi
    
    # 列出所有快照
    local snapshots
    snapshots=$(vagrant snapshot list "$vm" 2>/dev/null | awk '{print $1}' || true)
    
    if [ -z "$snapshots" ]; then
        log_info "没有快照需要清理"
        return 0
    fi
    
    # 删除每个快照
    for snapshot in $snapshots; do
        log_info "删除快照: $vm @ $snapshot"
        vagrant snapshot delete "$vm" "$snapshot" 2>/dev/null || true
    done
    
    log_info "清理完成: $vm"
}

# 清理所有 VM 的所有快照
clean_all() {
    log_warn "清理所有 VM 的所有快照..."
    log_warn "这将删除所有快照，但保留当前状态"
    read -p "输入 'yes' 继续: " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "取消清理"
        exit 0
    fi
    
    for vm in $(get_vm_list); do
        clean_vm "$vm"
    done
    
    log_info "全部清理完成"
}

# 主流程
main() {
    check_dependencies
    
    local action="${1:-}"
    local vm="${2:-}"
    local snapshot_name="${3:-}"
    
    case "$action" in
        list)
            list_snapshots "$vm"
            ;;
        create)
            create_snapshot "$vm" "$snapshot_name"
            ;;
        restore)
            restore_snapshot "$vm" "$snapshot_name"
            ;;
        delete)
            delete_snapshot "$vm" "$snapshot_name"
            ;;
        clean)
            clean_vm "$vm"
            ;;
        clean-all)
            clean_all
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知动作: $action"
            show_help
            exit 1
            ;;
    esac
}

# 如果没有参数，显示帮助
if [ "$#" -eq 0 ]; then
    show_help
    exit 1
fi

main "$@"
