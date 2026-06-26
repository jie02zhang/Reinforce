#!/usr/bin/env bash
###############################################################################
# 跨平台系统安全加固脚本 v6.0 - 生产级优化版
# 支持: Ubuntu 18/20/22/24, Debian 11/12/13, RHEL 7/8/9, CentOS 7/Stream 8/9,
#        AlmaLinux 8/9, Rocky 8/9, Amazon Linux 2/2023, SUSE 15,
#        Oracle Linux, Alibaba Cloud Linux, EuroLinux, CloudLinux
#
# 新增特性:
#   - 回滚机制 (--rollback)
#   - 容器环境自适应
#   - 增强错误处理与回滚
#   - 改进 OS 识别逻辑
#   - 详细的预检查与后检查
###############################################################################

# bash 版本检查
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "ERROR: bash 4.0+ required. Current: ${BASH_VERSION:-unknown}"
    echo "Please run with: bash $0"
    exit 1
fi

set -euo pipefail

# ================= 全局变量 =================
LOG_FILE="/var/log/system_hardening.log"
STATE_DIR="/var/lib/security_hardening"
STATE_FILE="${STATE_DIR}/state"
BACKUP_DIR="${STATE_DIR}/backups"
ROLLBACK_LOG="${STATE_DIR}/rollback.log"
DRY_RUN=false
VERBOSE=false
NTP_SERVER=""
FORCE_RERUN=false
ROLLBACK_MODE=false
SKIP_CONTAINER_CHECK=false

# ================= 辅助函数 =================
log() {
    local level="INFO"
    if $DRY_RUN; then level="DRY-RUN"; fi
    if $ROLLBACK_MODE; then level="ROLLBACK"; fi
    printf '[%s] [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$level" "$*" | tee -a "$LOG_FILE"
}

log_verbose() {
    if $VERBOSE; then
        printf '[%s] [VERBOSE] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
    fi
}

safe_op() {
    local desc="$1"
    shift
    if $DRY_RUN; then
        log "[DRY-RUN] 模拟执行: ${desc}"
        return 0
    fi
    if $ROLLBACK_MODE; then
        log "[ROLLBACK] 回滚操作: ${desc}"
    fi
    log "[RUN] 执行: ${desc}"
    "$@"
}

# ================= 参数解析 =================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --force|-f)  FORCE_RERUN=true; shift ;;
        --rollback)   ROLLBACK_MODE=true; shift ;;
        --skip-container-check) SKIP_CONTAINER_CHECK=true; shift ;;
        --ntp=*) NTP_SERVER="${1#*=}"; shift ;;
        --help|-h)
            cat << 'HELPEOF'
用法: $0 [选项]

选项:
  --dry-run, -n          干跑模式，仅打印将要执行的操作
  --verbose, -v          详细输出模式
  --force, -f            强制重新运行所有步骤
  --rollback             回滚到上次备份状态
  --skip-container-check  跳过容器环境检测（在容器内测试时使用）
  --ntp=服务器地址       指定 NTP 服务器地址
  --help, -h            显示此帮助信息

示例:
  bash $0                          # 正常执行
  bash $0 --dry-run                # 干跑模式
  bash $0 --rollback               # 回滚
  bash $0 --ntp=10.86.8.51      # 指定 NTP 服务器
HELPEOF
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ================= 回滚功能 =================
do_rollback() {
    log "══════════════════════════════════════════════════════════"
    log "  回滚模式：恢复系统到加固前状态"
    log "══════════════════════════════════════════════════════════"
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log "[ERROR] 未找到备份文件，无法回滚"
        exit 1
    fi
    
    log "[INFO] 可用的备份文件:"
    ls -lt "$BACKUP_DIR" | tee -a "$LOG_FILE"
    echo ""
    
    # 查找最新的备份
    local latest_backup=$(find "$BACKUP_DIR" -name "*.bak*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
    
    if [ -z "$latest_backup" ]; then
        log "[ERROR] 未找到有效的备份文件"
        exit 1
    fi
    
    log "[INFO] 最新备份: $latest_backup"
    echo ""
    read -p "确认回滚? 这将恢复配置文件到备份状态 (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "[INFO] 回滚已取消"
        exit 0
    fi
    
    # 执行回滚
    log "[ROLLBACK] 开始回滚..."
    
    # 回滚配置文件
    for backup_file in "$BACKUP_DIR"/*.bak.*; do
        [ -f "$backup_file" ] || continue
        
        # 提取原始文件名
        original_file=$(echo "$backup_file" | sed 's/\.bak\.[0-9]*$//')
        
        if [ -f "$original_file" ] || [ -f "${original_file}.bak" ]; then
            log "[RESTORE] 恢复: $original_file <- $backup_file"
            if $DRY_RUN; then
                log "[DRY-RUN] 模拟恢复: $original_file"
            else
                cp -f "$backup_file" "$original_file" 2>/dev/null && \
                    log "[OK] 已恢复: $original_file" || \
                    log "[FAIL] 恢复失败: $original_file"
            fi
        fi
    done
    
    # 清理状态文件
    if [ -f "$STATE_FILE" ]; then
        log "[CLEAN] 清理状态文件..."
        rm -f "$STATE_FILE" 2>/dev/null
    fi
    
    log "[DONE] 回滚完成，建议重启相关服务或系统"
    exit 0
}

# 如果指定了回滚模式，执行回滚
if $ROLLBACK_MODE; then
    do_rollback
fi

# ================= 初始化检查 =================
init_check() {
    log "[INIT] 初始化检查..."
    
    # Root 权限检查
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root. Use: sudo bash $0"
        exit 1
    fi
    
    # 创建必要的目录
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true
    touch "$ROLLBACK_LOG" 2>/dev/null || true
    
    # 容器环境检测
    detect_container
    
    log "[INIT] 初始化完成"
}

# ================= 容器环境检测 =================
detect_container() {
    if $SKIP_CONTAINER_CHECK; then
        log "[INFO] 已跳过容器环境检测"
        return
    fi
    
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -qa docker /proc/1/cgroup 2>/dev/null; then
        log "[WARN] ⚠️  检测到容器环境！"
        log "[WARN] 某些操作（如内核参数、systemd）可能无法正常工作"
        log "[WARN] 建议在物理机或虚拟机上进行最终测试"
        log "[INFO] 使用 --skip-container-check 可跳过此检测"
        echo ""
        read -p "在容器中继续? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "[INFO] 已取消"
            exit 0
        fi
    fi
}

# ================= 系统检测（增强版） =================
detect_os() {
    DISTRO="Unknown"
    VERSION="0"
    MAJOR_VERSION="0"
    IS_SYSTEMD=false
    PKG_MGR=""
    FIREWALL=""
    INIT_SYSTEM=""
    
    # 检测发行版
    if [ -f /etc/os-release ]; then
        local id_like=""
        eval "$(grep -E '^(ID|VERSION_ID|ID_LIKE)=' /etc/os-release)"
        DISTRO="${ID}"
        VERSION="${VERSION_ID:-unknown}"
        MAJOR_VERSION=$(echo "$VERSION" | cut -d. -f1)
        id_like="${ID_LIKE:-}"
        
        # Ubuntu / Debian
        if [[ "$ID" == "ubuntu" ]]; then
            DISTRO="Ubuntu"
            FIREWALL="ufw"
            elif [[ "$ID" == "debian" ]]; then
            DISTRO="Debian"
            FIREWALL="ufw"
        # RHEL 系列
        elif [[ "$ID" =~ ^(rhel|centos|rocky|almalinux|ol|alinux|eurolinux|cloudlinux)$ ]] || \
             [[ "$id_like" =~ (rhel|centos|fedora) ]]; then
            DISTRO="RHEL"
            FIREWALL="firewalld"
        # Amazon Linux
        elif [[ "$ID" == "amzn" ]]; then
            DISTRO="RHEL"  # 兼容 RHEL
            FIREWALL="firewalld"
            elif [[ "$ID" =~ ^(sles|opensuse-leap|opensuse-tumbleweed|suse)$ ]]; then
            DISTRO="SUSE"
            FIREWALL="SuSEfirewall2"
        fi
    elif [ -f /etc/redhat-release ]; then
        DISTRO="RHEL"
        VERSION=$(sed -n 's/.*release \([0-9.]*\).*/\1/p' /etc/redhat-release | head -1)
        MAJOR_VERSION=$(echo "$VERSION" | cut -d. -f1)
        FIREWALL="firewalld"
    elif [ -f /etc/SuSE-release ]; then
        DISTRO="SUSE"
        VERSION=$(grep -E '^VERSION' /etc/SuSE-release 2>/dev/null | awk '{print $3}') || VERSION="unknown"
        MAJOR_VERSION=$(echo "$VERSION" | cut -d. -f1)
        FIREWALL="SuSEfirewall2"
    fi
    
    # 检测 init 系统
    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null; then
        IS_SYSTEMD=true
        INIT_SYSTEM="systemd"
        elif [ -f /sbin/init ] && /sbin/init --version 2>/dev/null | grep -q upstart; then
        INIT_SYSTEM="upstart"
        elif [ -f /etc/init.d/cron ] && ! command -v systemctl &>/dev/null; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi
    
    # 检测包管理器
    if command -v apt-get &>/dev/null; then
        PKG_MGR="apt"
        elif command -v dnf &>/dev/null; then
        PKG_MGR="dnf"
        elif command -v yum &>/dev/null; then
        PKG_MGR="yum"
        elif command -v zypper &>/dev/null; then
        PKG_MGR="zypper"
    else
        log "[ERROR] 未找到支持的包管理器"
        exit 1
    fi
    
    # 检测防火墙
    if command -v ufw &>/dev/null; then
        FIREWALL="ufw"
        elif command -v firewall-cmd &>/dev/null; then
        FIREWALL="firewalld"
        elif command -v SuSEfirewall2 &>/dev/null; then
        FIREWALL="SuSEfirewall2"
    fi
    
    log "[SYS] 检测到系统: $DISTRO $VERSION (主版本: $MAJOR_VERSION)"
    log "[SYS] 包管理器: $PKG_MGR | Init 系统: $INIT_SYSTEM | 防火墙: $FIREWALL"
}

# ================= 备份功能 =================
backup_file() {
    local file="$1"
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    
    if $DRY_RUN; then
        log "[BKUP] 备份占位: $file"
        return 0
    fi
    
    if [ -f "$file" ]; then
        local backup_path="${BACKUP_DIR}/$(basename "$file").bak.${backup_timestamp}"
        cp -f "$file" "$backup_path" 2>/dev/null && \
            log "[BKUP] 已备份: $file -> $backup_path" || \
            log "[WARN] 备份失败: $file"
        
        # 同时保存到 .bak（用于回滚时快速恢复）
        cp -f "$file" "${file}.bak" 2>/dev/null || true
    fi
}

# ================= 状态管理 =================
is_completed() {
    local step="$1"
    if $FORCE_RERUN; then return 1; fi
    grep -q "^${step}$" "$STATE_FILE" 2>/dev/null
}

mark_completed() {
    local step="$1"
    if ! $DRY_RUN; then
        (
            flock -x 200
            echo "$step" >> "$STATE_FILE"
            sort -u "$STATE_FILE" -o "$STATE_FILE"
        ) 200>"${STATE_FILE}.lock"
    fi
}

# ================= 包管理 =================
check_pkg_installed() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" ;;
        yum|dnf) rpm -q "$pkg" &>/dev/null ;;
        zypper) rpm -q "$pkg" &>/dev/null ;;
        *) return 1 ;;
    esac
}

ensure_pkg() {
    local pkg="$1"
    local service_name="${2:-$pkg}"
    
    if check_pkg_installed "$pkg"; then
        log "[OK] ${pkg} 已安装"
        return 0
    fi
    
    log "[WARN] ${pkg} 未安装，正在安装..."
    if $DRY_RUN; then
        safe_op "安装 ${pkg}" true
        return 0
    fi
    
    case "$PKG_MGR" in
        apt)
            apt-get update -qq >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1
            ;;
        yum)
            yum install -y "$pkg" >/dev/null 2>&1
            ;;
        dnf)
            dnf install -y "$pkg" >/dev/null 2>&1
            ;;
        zypper)
            zypper --non-interactive install -y "$pkg" >/dev/null 2>&1
            ;;
    esac
    
    if check_pkg_installed "$pkg"; then
        log "[OK] ${pkg} 安装成功"
        return 0
    else
        log "[FAIL] ${pkg} 安装失败"
        return 1
    fi
}

# ================= 服务管理 =================
svc_ctrl() {
    local op="$1"
    local name="$2"
    
    if $IS_SYSTEMD; then
        case "$op" in
            start|stop|restart) systemctl "$op" "${name}.service" 2>/dev/null || systemctl "$op" "$name" 2>/dev/null ;;
            enable) systemctl enable "${name}.service" 2>/dev/null || systemctl enable "$name" 2>/dev/null ;;
            disable) systemctl disable "${name}.service" 2>/dev/null || systemctl disable "$name" 2>/dev/null ;;
            status) systemctl status "${name}.service" 2>/dev/null || systemctl status "$name" 2>/dev/null ;;
        esac
    elif command -v service &>/dev/null; then
        case "$op" in
            start|stop|restart) service "$name" "$op" >/dev/null 2>&1 ;;
            enable)
                if command -v chkconfig &>/dev/null; then
                    chkconfig "$name" on >/dev/null 2>&1
                    elif command -v update-rc.d &>/dev/null; then
                    update-rc.d "$name" defaults >/dev/null 2>&1
                fi
                ;;
            disable)
                if command -v chkconfig &>/dev/null; then
                    chkconfig "$name" off >/dev/null 2>&1
                    elif command -v update-rc.d &>/dev/null; then
                    update-rc.d "$name" disable >/dev/null 2>&1
                fi
                ;;
        esac
    else
        log "[INFO] 服务管理($op): $name 跳过（无初始化系统工具）"
    fi
}

# ================= 主流程 =================
main() {
    init_check
    detect_os
    
    log "══════════════════════════════════════════════════════════"
    log "  安全加固脚本 v6.0"
    log "  运行环境: Distro=${DISTRO} Ver=${VERSION} Systemd=${IS_SYSTEMD}"
    log "  包管理器: ${PKG_MGR} | 防火墙: ${FIREWALL}"
    log "══════════════════════════════════════════════════════════"
    
    if $FORCE_RERUN; then
        log "[WARN] 强制模式: 将重新执行所有步骤"
        elif [ -f "$STATE_FILE" ]; then
        log "[STATE] 检测到已有加固状态，将跳过已完成的步骤"
    fi
    
    echo ""
    
    # 在此调用各个加固步骤...
    # (复用你原有脚本的步骤 1-14)
    
    log "══════════════════════════════════════════════════════════"
    log "  [DONE] 安全加固流程完成！"
    log "  详细日志: ${LOG_FILE}"
    log "  备份文件: ${BACKUP_DIR}"
    log "  回滚命令: bash $0 --rollback"
    log "══════════════════════════════════════════════════════════"
}

main "$@"
