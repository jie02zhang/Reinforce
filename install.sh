#!/bin/bash
# 安全加固脚本 - 一键安装脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/example/security_hardening/main/install.sh | sudo bash
# 或: bash install.sh [选项]

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
SCRIPT_URL="https://raw.githubusercontent.com/example/security_hardening/main/security_hardening.sh"
SCRIPT_NAME="security_hardening.sh"
INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="$INSTALL_DIR/$SCRIPT_NAME"
VERSION="v6.0"

# 打印函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 显示帮助信息
show_help() {
    cat <<EOF
安全加固脚本 - 一键安装脚本

用法:
  $0 [选项]

选项:
  --verbose      详细输出模式
  --dry-run      预览模式（不实际安装）
  --uninstall    卸载脚本
  --version      显示版本信息
  --help         显示此帮助信息

示例:
  # 一键安装并运行
  curl -fsSL https://raw.githubusercontent.com/example/security_hardening/main/install.sh | sudo bash -s -- --verbose

  # 下载安装脚本后运行
  bash install.sh --verbose

  # 卸载
  bash install.sh --uninstall

EOF
}

# 显示版本信息
show_version() {
    echo "安全加固脚本 安装程序"
    echo "版本: $VERSION"
    echo "脚本 URL: $SCRIPT_URL"
}

# 检测系统
detect_system() {
    log_info "检测系统信息..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        log_pass "检测到系统: $OS_NAME $OS_VERSION"
    else
        log_warn "无法检测系统版本，继续安装..."
    fi
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    local deps=("curl" "wget")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "缺少依赖: ${missing_deps[*]}"
        log_info "尝试安装依赖..."
        
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y "${missing_deps[@]}"
        elif command -v yum &>/dev/null; then
            yum install -y "${missing_deps[@]}"
        elif command -v dnf &>/dev/null; then
            dnf install -y "${missing_deps[@]}"
        else
            log_error "无法安装依赖，请手动安装: ${missing_deps[*]}"
            exit 1
        fi
    fi
    
    log_pass "依赖检查通过"
}

# 下载脚本
download_script() {
    local verbose="${1:-}"
    
    log_info "下载安全加固脚本..."
    
    # 创建临时目录
    TMP_DIR=$(mktemp -d)
    TMP_FILE="$TMP_DIR/$SCRIPT_NAME"
    
    # 下载脚本
    if command -v curl &>/dev/null; then
        if [ "$verbose" == "verbose" ]; then
            curl -fsSL "$SCRIPT_URL" -o "$TMP_FILE"
        else
            curl -fsSL "$SCRIPT_URL" -o "$TMP_FILE" 2>/dev/null
        fi
    elif command -v wget &>/dev/null; then
        if [ "$verbose" == "verbose" ]; then
            wget "$SCRIPT_URL" -O "$TMP_FILE"
        else
            wget "$SCRIPT_URL" -O "$TMP_FILE" -q
        fi
    else
        log_error "未找到 curl 或 wget，无法下载脚本"
        exit 1
    fi
    
    # 验证下载
    if [ ! -f "$TMP_FILE" ]; then
        log_error "脚本下载失败"
        exit 1
    fi
    
    # 验证脚本内容（简单检查）
    if ! head -1 "$TMP_FILE" | grep -q "#!/bin/bash"; then
        log_error "下载的文件不是有效的 bash 脚本"
        exit 1
    fi
    
    log_pass "脚本下载成功: $TMP_FILE"
    echo "$TMP_FILE"
}

# 安装脚本
install_script() {
    local verbose="${1:-}"
    local dry_run="${2:-}"
    
    log_info "开始安装..."
    
    # 下载脚本
    local script_file
    script_file=$(download_script "$verbose")
    
    if [ "$dry_run" == "dry-run" ]; then
        log_warn "预览模式：不会实际安装"
        log_info "将安装到: $INSTALL_PATH"
        log_info "脚本大小: $(du -h "$script_file" | cut -f1)"
        return 0
    fi
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 复制脚本
    cp "$script_file" "$INSTALL_PATH"
    
    # 设置权限
    chmod 755 "$INSTALL_PATH"
    
    # 清理临时文件
    rm -rf "$TMP_DIR"
    
    log_pass "安装成功!"
    log_info "安装位置: $INSTALL_PATH"
    log_info ""
    log_info "使用方法:"
    log_info "  sudo security-hardening --verbose"
    log_info ""
    log_info "或直接运行:"
    log_info "  sudo bash $INSTALL_PATH --verbose"
}

# 卸载脚本
uninstall_script() {
    log_info "开始卸载..."
    
    if [ ! -f "$INSTALL_PATH" ]; then
        log_warn "脚本未安装: $INSTALL_PATH"
        return 0
    fi
    
    rm -f "$INSTALL_PATH"
    
    log_pass "卸载成功!"
}

# 运行脚本
run_script() {
    local verbose="${1:-}"
    
    log_info "运行安全加固脚本..."
    
    if [ -f "$INSTALL_PATH" ]; then
        if [ "$verbose" == "verbose" ]; then
            sudo bash "$INSTALL_PATH" --verbose
        else
            sudo bash "$INSTALL_PATH"
        fi
    else
        log_error "脚本未安装，请先运行安装: $0"
        exit 1
    fi
}

# 主函数
main() {
    local action="install"
    local verbose=""
    local dry_run=""
    
    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --verbose)
                verbose="verbose"
                shift
                ;;
            --dry-run)
                dry_run="dry-run"
                shift
                ;;
            --uninstall)
                action="uninstall"
                shift
                ;;
            --version)
                show_version
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 执行动作
    case "$action" in
        install)
            echo "=========================================="
            echo "  安全加固脚本 - 安装程序"
            echo "  版本: $VERSION"
            echo "=========================================="
            echo ""
            
            detect_system
            check_dependencies
            
            if [ -f "$INSTALL_PATH" ]; then
                log_warn "脚本已安装: $INSTALL_PATH"
                read -p "是否覆盖安装? (y/N): " confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    log_info "取消安装"
                    exit 0
                fi
            fi
            
            install_script "$verbose" "$dry_run"
            
            if [ -z "$dry_run" ]; then
                read -p "是否立即运行脚本? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    run_script "$verbose"
                fi
            fi
            ;;
        uninstall)
            uninstall_script
            ;;
    esac
    
    echo ""
    log_pass "操作完成!"
}

main "$@"
