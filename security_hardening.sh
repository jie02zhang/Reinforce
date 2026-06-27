#!/usr/bin/env bash
###############################################################################
# 跨平台系统安全加固脚本 v6.1 (SUSE 15 修复版)
# 支持: Ubuntu 18/20/22/24, Debian 11/12/13, RHEL 7/8/9, CentOS 7/9,
#        AlmaLinux 8/9, Rocky 8/9, Amazon Linux 2/2023, SUSE 15,
#        Oracle Linux, Alibaba Cloud Linux, EuroLinux, CloudLinux
#        WSL 1/2 (Windows Subsystem for Linux)
# 特性：幂等执行 / Dry-Run / 状态跟踪 / 跨发行版兼容 / WSL 兼容
# v6.1: 修复 SUSE 15 支持（sysctl 不可用、zypper 仓库刷新、内核参数 via /proc/sys/）
# v6.0: 修复 PAM 模块路径检测（支持多架构）、修复内核参数空格处理
# v5.9: 修复 WSL 环境兼容性问题（NTP 交互输入、find 性能、服务管理）
# v5.8: 完善内核参数处理（避免不支持参数报错）、权限设置每次都执行（确保600）
###############################################################################

# bash 版本检查（declare -A 等特性需 bash 4.0+）
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "ERROR: bash 4.0+ required. Current: ${BASH_VERSION:-unknown}"
    echo "Please run with: bash $0"
    exit 1
fi
set -euo pipefail

# ================= 新增：WSL 环境检测 =================
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
fi

# ================= root 权限检查 =================
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root. Use: sudo bash $0"
    exit 1
fi

LOG_FILE="/var/log/system_hardening.log"
STATE_FILE="/var/lib/security_hardening/state"
DRY_RUN=false
VERBOSE=false
NTP_SERVER=""
FORCE_RERUN=false
WSL_MODE=false

# ================= 参数解析 =================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=true; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        --force|-f)  FORCE_RERUN=true; shift ;;
        --wsl)       WSL_MODE=true; shift ;;
        --ntp=*) NTP_SERVER="${1#*=}"; shift ;;
        --help|-h) 
            echo "Usage: $0 [--dry-run|-n] [--verbose|-v] [--force|-f] [--wsl] [--ntp=server]"
            echo "Options:"
            echo "  --wsl        WSL 环境模式（跳过不兼容步骤）"
            echo "  --ntp=server 指定 NTP 服务器地址"
            echo "Example: $0 --ntp=10.86.8.51"
            echo "Example: $0 --wsl --dry-run"
            exit 0 
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# 如果在 WSL 环境中且未显式设置 --wsl，自动启用
if $IS_WSL && ! $WSL_MODE; then
    echo "[WARN] 检测到 WSL 环境，自动启用 --wsl 模式"
    WSL_MODE=true
fi

# ================= 状态管理 =================
mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true

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

log() {
    local level="INFO"
    if $DRY_RUN; then level="DRY-RUN"; fi
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
    log "[RUN] 执行: ${desc}"
    "$@"
}

# ================= 系统检测 =================
detect_os() {
    DISTRO="Unknown"
    VERSION="0"
    IS_SYSTEMD=false
    PKG_MGR=""
    
    # 检测发行版
    if [ -f /etc/os-release ]; then
        eval "$(grep -E '^(ID|VERSION_ID)=' /etc/os-release)"
        DISTRO="${ID}"
        VERSION="${VERSION_ID:-unknown}"
        
        # Ubuntu 特殊处理
        if [[ "$ID" == "ubuntu" ]]; then
            DISTRO="Ubuntu"
            VERSION="${VERSION_ID:-unknown}"
        # Debian
        elif [[ "$ID" == "debian" ]]; then
            DISTRO="Debian"
            VERSION="${VERSION_ID:-unknown}"
        # RHEL/CentOS 及其衍生版（含 Oracle Linux、Alibaba Cloud Linux 等）
        elif [[ "$ID" =~ ^(rhel|centos|rocky|almalinux|ol|alinux|eurolinux|cloudlinux)$ ]]; then
            DISTRO="RHEL"
            VERSION="${VERSION_ID:-unknown}"
        # Amazon Linux (映射为 RHEL 兼容处理)
        elif [[ "$ID" == "amzn" ]]; then
            DISTRO="RHEL"
            VERSION="${VERSION_ID:-unknown}"
        # SUSE
        elif [[ "$ID" =~ ^(sles|opensuse-leap|opensuse-tumbleweed|suse)$ ]]; then
            DISTRO="SUSE"
            VERSION="${VERSION_ID:-unknown}"
        fi
    elif [ -f /etc/redhat-release ]; then
        DISTRO="RHEL"
        VERSION=$(sed -n 's/.*release \([0-9.]*\).*/\1/p' /etc/redhat-release | head -1)
    elif [ -f /etc/SuSE-release ]; then
        DISTRO="SUSE"
        VERSION=$(sed -n 's/.*VERSION_ID=\([0-9.]*\).*/\1/p' /etc/os-release 2>/dev/null | head -1)
    fi
    
    # 检测 systemd（WSL 中 systemd 可能不完整）
    if command -v systemctl &>/dev/null; then
        # WSL 中 systemctl --version 可能成功，但实际 systemd 未运行
        if $IS_WSL; then
            # WSL 默认不运行完整的 systemd，除非显式启用
            if [ -f /run/systemd/system ]; then
                IS_SYSTEMD=true
            else
                IS_SYSTEMD=false
                log "[WARN] WSL 环境：systemd 未完整运行，服务管理将跳过"
            fi
        else
            IS_SYSTEMD=true
        fi
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
    
    log "[SYS] 检测到系统: $DISTRO $VERSION (包管理器: $PKG_MGR, systemd: $IS_SYSTEMD, WSL: $IS_WSL)"
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
            # 先刷新仓库（避免元数据过期导致安装失败）
            zypper --non-interactive refresh >/dev/null 2>&1 || true
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

# ================= 服务管理（WSL 兼容） =================
svc_ctrl() {
    local op="$1"
    local name="$2"
    
    # WSL 环境中跳过服务管理（除非显式启用 systemd）
    if $IS_WSL && ! $WSL_MODE; then
        log "[INFO] WSL 环境: 跳过服务操作 $op $name"
        return 0
    fi
    
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

svc_is_disabled() {
    local name="$1"
    
    # WSL 环境中假设服务已禁用
    if $IS_WSL && ! $WSL_MODE; then
        return 0
    fi
    
    if $IS_SYSTEMD; then
        local state
        state=$(systemctl is-enabled "${name}.service" 2>/dev/null || systemctl is-enabled "$name" 2>/dev/null) || true
        [[ "$state" != "enabled" ]] && [[ "$state" != "enabled-runtime" ]] && return 0
        return 1
    else
        if command -v chkconfig &>/dev/null; then
            chkconfig --list "$name" 2>/dev/null | grep -q "off" && return 0
        fi
        return 1
    fi
}

# ================= 工具函数 =================
backup_file() {
    if $DRY_RUN; then
        log "[BKUP] 备份占位: $1"
        return 0
    fi
    [ -f "$1" ] && cp -f "$1" "${1}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
    [ -f "$1" ] && cp -f "$1" "${1}.bak" 2>/dev/null
}

ssh_major_version() {
    local ver
    ver=$(ssh -V 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1) || true
    if [ -z "${ver:-}" ]; then
        case "$PKG_MGR" in
            apt) ver=$(dpkg-query -W -f='${Version}' openssh-server 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1) || true ;;
            yum|dnf|zypper) ver=$(rpm -q --qf '%{VERSION}' openssh-server 2>/dev/null | cut -d. -f1) || true ;;
        esac
    fi
    echo "${ver:-0}"
}

apply_sysctl_safe() {
    local param="$1"
    # 提取键和值（去除前后空格，兼容不同格式）
    local key val
    key="$(echo "${param%%=*}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    val="$(echo "${param#*=}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    
    local escaped_key
    escaped_key=$(printf '%s' "$key" | sed 's/\./\\./g')
    
    if $DRY_RUN; then
        safe_op "内核参数设置: ${key} = ${val}" true
        return 0
    fi
    
    # 检查是否已配置
    if grep -q "^${escaped_key}\s*=" /etc/sysctl.conf 2>/dev/null; then
        local current
        current=$(grep "^${escaped_key}\s*=" /etc/sysctl.conf | head -1 | cut -d= -f2 | tr -d ' ')
        if [ "$current" = "${val}" ]; then
            return 0  # 已配置，跳过
        fi
    fi
    
    # ★ 修复：先检查内核参数是否存在（兼容 sysctl 不可用的情况）
    local sysctl_available=false
    command -v sysctl &>/dev/null && sysctl_available=true
    
    local param_exists=false
    if $sysctl_available; then
        # 方法1：使用 sysctl 检查
        if sysctl "${key}" >/dev/null 2>&1; then
            param_exists=true
        fi
    else
        # 方法2：直接检查 /proc/sys/ 文件系统
        # 将 net.ipv4.tcp_syncookies 转换为 /proc/sys/net/ipv4/tcp_syncookies
        local proc_path="/proc/sys/$(echo "${key}" | tr '.' '/')"
        if [ -f "$proc_path" ]; then
            param_exists=true
        fi
    fi
    
    if $param_exists; then
        # 参数存在，尝试设置
        if $sysctl_available; then
            # 使用 sysctl 设置
            if sysctl -w "${key}=${val}" >/dev/null 2>&1; then
                # 设置成功，更新配置文件
                sed -i "\|^${escaped_key}\s*=|d" /etc/sysctl.conf 2>/dev/null
                echo "${key} = ${val}" >> /etc/sysctl.conf
                log_verbose "[OK] 内核参数已设置: ${key}=${val}"
            else
                log "[WARN] 内核参数设置失败: ${key}"
            fi
        else
            # 直接使用 /proc/sys/ 设置（立即生效）
            local proc_path="/proc/sys/$(echo "${key}" | tr '.' '/')"
            if echo "${val}" > "$proc_path" 2>/dev/null; then
                # 设置成功，更新配置文件（重启后生效）
                sed -i "\|^${escaped_key}\s*=|d" /etc/sysctl.conf 2>/dev/null
                echo "${key} = ${val}" >> /etc/sysctl.conf
                log_verbose "[OK] 内核参数已设置: ${key}=${val} (via /proc/sys/)"
            else
                log "[WARN] 内核参数设置失败: ${key}"
            fi
        fi
    else
        log_verbose "[INFO] 内核不支持该参数，跳过: ${key}"
        # 清理配置文件中可能存在的该参数（避免后续 sysctl -p 报错）
        sed -i "\|^${escaped_key}\s*=|d" /etc/sysctl.conf 2>/dev/null
    fi
}

# ================= 主流程 =================
detect_os

log "运行环境: Distro=${DISTRO} Ver=${VERSION} Systemd=${IS_SYSTEMD} PkgMgr=${PKG_MGR} WSL=${IS_WSL}"
if $FORCE_RERUN; then
    log "[WARN] 强制模式: 将重新执行所有步骤"
elif [ -f "$STATE_FILE" ]; then
    log "[STATE] 检测到已有加固状态，将跳过已完成的步骤"
fi

echo ""

# ================= 步骤1: 清理个人认证残留 =================
STEP="1_cleanup_auth"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤1: 清理个人认证残留文件"
    for f in "$HOME/.rhosts" "$HOME/.netrc" "$HOME/.hosts.equiv"; do
        if [ -f "$f" ]; then
            if $DRY_RUN; then
                log "[DEL] 拟删除: $f"
            else
                rm -f "$f"
                log "[OK] 已清理: $f"
            fi
        fi
    done
    mark_completed "$STEP"
else
    log "[SKIP] 步骤1: 已完成，跳过"
fi

# ================= 步骤1.5: 确保 admin_env 用户存在 =================
STEP="1.5_create_admin_env"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤1.5: 确保 admin_env 用户存在"

    if id admin_env &>/dev/null; then
        log "[OK] admin_env 用户已存在 (UID: $(id -u admin_env))"
    else
        if $DRY_RUN; then
            log "[DRY-RUN] 模拟执行: 创建 admin_env 用户"
        else
            # 创建 admin_env 用户（系统级，加入 admin 组）
            if ! getent group admin &>/dev/null; then
                groupadd -r admin 2>/dev/null && log "[OK] 已创建 admin 组"
            fi
            if useradd -r -g admin -s /bin/bash -c "Admin Environment" admin_env 2>/dev/null; then
                mkdir -p /home/admin_env 2>/dev/null
                chown admin_env:admin /home/admin_env 2>/dev/null
                log "[OK] admin_env 用户创建成功"
            elif useradd -r -m -g admin -s /bin/bash -c "Admin Environment" admin_env 2>/dev/null; then
                log "[OK] admin_env 用户创建成功 (带 home 目录)"
            else
                if useradd -m -g admin -s /bin/bash -c "Admin Environment" admin_env 2>/dev/null; then
                    log "[OK] admin_env 用户创建成功 (普通用户模式)"
                else
                    log "[FAIL] admin_env 用户创建失败"
                fi
            fi
        fi
    fi

    mark_completed "$STEP"
else
    log "[SKIP] 步骤1.5: 已完成，跳过"
fi

# ================= 步骤2: 禁用非必要账号 Shell =================
STEP="2_disable_shells"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤2: 禁用非必要系统账号"
    
    SYSTEM_ACCOUNTS=("daemon" "bin" "adm" "nobody" "halt" "shutdown" "sync" "mail" "operator" "lp" "games" "postmaster" "news" "uucp" "proxy" "www-data" "dbus" "messagebus" "ftp" "ftpsecure")
    
    if [[ "$DISTRO" == "RHEL" ]]; then
        SYSTEM_ACCOUNTS+=("nfsnobody" "rpc" "rpcuser")
    fi
    
    if [[ "$DISTRO" == "SUSE" ]]; then
        SYSTEM_ACCOUNTS+=("wwwrun")
    fi
    
    for u in "${SYSTEM_ACCOUNTS[@]}"; do
        if ! id "$u" &>/dev/null; then continue; fi
        current_shell=""
        current_shell=$(getent passwd "$u" | cut -d: -f7)
        if [[ "$current_shell" != "/sbin/nologin" ]] && [[ "$current_shell" != "/usr/sbin/nologin" ]] && [[ "$current_shell" != "/bin/false" ]]; then
            if $DRY_RUN; then
                log "[LOCK] 拟锁定 Shell: $u"
            else
                usermod -s /sbin/nologin "$u" 2>/dev/null || usermod -s /usr/sbin/nologin "$u" 2>/dev/null
                log "[OK] 已锁定 Shell: $u"
            fi
        fi
    done
    mark_completed "$STEP"
else
    log "[SKIP] 步骤2: 已完成，跳过"
fi

# ================= 步骤3: 修复 root 777 权限 =================
STEP="3_fix_777"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤3: 修复 root 777 权限"
    if $DRY_RUN; then
        log "[INFO] 实际运行时将扫描并修正（WSL 环境会排除 /mnt 目录）"
    else
        # WSL 优化：排除 /mnt（Windows 文件系统）和 /proc /sys /dev
        if $IS_WSL; then
            log "[INFO] WSL 环境：排除 /mnt 目录以加速扫描"
            find / \( -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o -path /run -prune -o -path /mnt -prune -o -type f -user root -perm 0777 -exec chmod 744 {} \; \) 2>/dev/null
            find / \( -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o -path /run -prune -o -path /mnt -prune -o -type d -user root -perm 0777 -exec chmod 755 {} \; \) 2>/dev/null
        else
            find / \( -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o -path /run -prune -o -type f -user root -perm 0777 -exec chmod 744 {} \; \) 2>/dev/null
            find / \( -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o -path /run -prune -o -type d -user root -perm 0777 -exec chmod 755 {} \; \) 2>/dev/null
        fi
        log "[OK] root 777 文件/目录已处理"
    fi
    mark_completed "$STEP"
else
    log "[SKIP] 步骤3: 已完成，跳过"
fi

# ================= 步骤4: 会话超时与 umask =================
STEP="4_session_timeout"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤4: 配置会话超时与 umask"
    
    HARDENING_PROFILE="/etc/profile.d/hardening.sh"
    
    if [ -f "$HARDENING_PROFILE" ]; then
        if grep -q "TMOUT=600" "$HARDENING_PROFILE" && grep -q "umask 0022" "$HARDENING_PROFILE" && ! grep -q "export MAIL=" "$HARDENING_PROFILE"; then
            log "[SKIP] $HARDENING_PROFILE 已配置，跳过"
        else
            if $DRY_RUN; then
                log "[EDIT] 拟更新 $HARDENING_PROFILE"
            else
                cat > "$HARDENING_PROFILE" << 'PROF_EOF'
# Security hardening settings
umask 0022
export TMOUT=600
PROF_EOF
                chmod 644 "$HARDENING_PROFILE"
                log "[OK] $HARDENING_PROFILE 已更新"
            fi
        fi
    else
        if $DRY_RUN; then
            log "[EDIT] 拟创建 $HARDENING_PROFILE"
        else
            cat > "$HARDENING_PROFILE" << 'PROF_EOF'
# Security hardening settings
umask 0022
export TMOUT=600
PROF_EOF
            chmod 644 "$HARDENING_PROFILE"
            log "[OK] $HARDENING_PROFILE 已创建"
        fi
    fi
    
    source "$HARDENING_PROFILE" 2>/dev/null || true
    mark_completed "$STEP"
else
    log "[SKIP] 步骤4: 已完成，跳过"
fi

# ================= 步骤5: Sudo 安全基线 =================
STEP="5_sudo_config"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤5: Sudo 安全基线配置"
    
    backup_file /etc/sudoers
    
    if ! $DRY_RUN; then
        # ================= 改进：使用 /etc/sudoers.d/ drop-in 文件 =================
        SUDOERS_D_DIR="/etc/sudoers.d"
        SUDOERS_D_FILE="$SUDOERS_D_DIR/security_hardening"
        
        # ================= 确保 @includedir 已启用 =================
        # 检查是否有未注释的 @includedir
        if ! grep -qE "^@includedir.*sudoers.d" /etc/sudoers 2>/dev/null; then
            # 没有未注释的，检查是否有注释掉的 #includedir
            _COMMENTED_LINE=$(grep -n "^#includedir.*sudoers.d" /etc/sudoers 2>/dev/null | head -1)
            if [ -n "$_COMMENTED_LINE" ]; then
                # 有注释掉的，改为 @includedir（而不是简单地移除 #）
                _LINE_NUM=$(echo "$_COMMENTED_LINE" | cut -d: -f1)
                log "[INFO] 启用 @includedir（第 ${_LINE_NUM} 行：#includedir → @includedir）"
                # 使用 sed 改为 @includedir（先备份，再验证）
                cp /etc/sudoers /etc/sudoers.bak.$(date +%Y%m%d_%H%M%S)
                sed -i "${_LINE_NUM}s/^#includedir/@includedir/" /etc/sudoers
                # 验证语法
                if visudo -c >/dev/null 2>&1; then
                    log "[OK] 已启用 /etc/sudoers.d/ includedir（取消注释）"
                else
                    log "[ERROR] 取消注释失败，已回滚"
                    mv /etc/sudoers.bak.* /etc/sudoers 2>/dev/null
                fi
            else
                # 都没有，追加新行（使用 visudo -f 安全编辑）
                log "[INFO] 添加 @includedir 到主文件"
                echo "@includedir /etc/sudoers.d" >> /etc/sudoers
                if visudo -c >/dev/null 2>&1; then
                    log "[OK] 已启用 /etc/sudoers.d/ includedir（追加）"
                else
                    log "[ERROR] 追加失败，已回滚"
                    mv /etc/sudoers.bak.* /etc/sudoers 2>/dev/null
                fi
            fi
        else
            log "[SKIP] @includedir 已启用，跳过"
        fi
        
        # 写入自定义配置到 drop-in 文件（不修改主文件）
        cat > "$SUDOERS_D_FILE" <<'EOF'
# 安全加固脚本生成的 sudo 配置
# 文件: /etc/sudoers.d/security_hardening
# 请勿手动修改，如需调整请编辑此文件

# 使用 PTY（防止某些漏洞）
Defaults use_pty

# 日志记录
Defaults logfile=/var/log/sudo.log

# 输入输出日志
Defaults log_input, log_output
EOF
        
        # RHEL 7 及以下需要 requiretty
        if [[ "$DISTRO" == "RHEL" ]] && [[ "$(echo "$VERSION" | cut -d. -f1)" -lt 8 ]]; then
            echo "Defaults requiretty" >> "$SUDOERS_D_FILE"
        fi
        
        chmod 440 "$SUDOERS_D_FILE"
        
        # 验证 drop-in 文件语法（单独验证，不影响主文件）
        if visudo -cf "$SUDOERS_D_FILE" >/dev/null 2>&1; then
            log "[OK] sudoers.d/security_hardening 语法验证通过"
        else
            log "[ERROR] sudoers.d/security_hardening 语法错误，已回滚"
            rm -f "$SUDOERS_D_FILE"
            exit 1
        fi
        
        # admin_nopasswd 文件（已正确使用 drop-in）
        if [ ! -f /etc/sudoers.d/admin_nopasswd ]; then
            if ! getent group admin &>/dev/null; then
                groupadd admin 2>/dev/null && log "[OK] 已创建 admin 组"
            fi
            if id admin_env &>/dev/null; then
                usermod -aG admin admin_env 2>/dev/null && log "[OK] admin_env 已加入 admin 组"
            fi
            cat > /etc/sudoers.d/admin_nopasswd <<'EOF'
# admin_env sudo NOPASSWD
%admin ALL=(ALL) NOPASSWD:ALL
admin_env ALL=(ALL) NOPASSWD:ALL
EOF
            chmod 440 /etc/sudoers.d/admin_nopasswd
            log "[OK] sudo 免密规则已添加 (admin 组 + admin_env 用户)"
        else
            if id admin_env &>/dev/null; then
                groups admin_env 2>/dev/null | grep -q '\badmin\b' || usermod -aG admin admin_env 2>/dev/null
            fi
            log "[SKIP] sudo 免密规则已存在，跳过"
        fi
        
        # 最终验证：检查整个 sudoers 配置（主文件 + 所有 drop-in）
        _SUDOERS_CHECK=$(visudo -c 2>&1)
        if [ $? -eq 0 ]; then
            log "[OK] sudoers 整体语法验证通过"
        else
            log "[WARN] sudoers 整体语法验证失败，请检查:"
            log "[WARN]   $_SUDOERS_CHECK"
            # 不退出，因为可能是其他 drop-in 文件的问题
        fi
    fi
    
    mark_completed "$STEP"
else
    log "[SKIP] 步骤5: 已完成，跳过"
fi

# ================= 步骤6: 密码复杂度 =================
_build_pwq_line() {
    echo "password	requisite	pam_pwquality.so	retry=${RETRY} minlen=${MIN_LEN} minclass=${MIN_CLASS} difok=${DIFOK} dcredit=-1 ucredit=-1 lcredit=-1 ocredit=-1 maxrepeat=${MAXREPEAT} maxsequence=${MAXSEQUENCE} enforce_for_root"
}

STEP="6_password_policy"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤6: 密码复杂度配置"
    
    STEP6_OK=true
    
    MIN_LEN=12
    MIN_CLASS=4
    DIFOK=5
    RETRY=3
    MAXREPEAT=3
    MAXSEQUENCE=3
    PWQ_LINE="$(_build_pwq_line)"
    
    log "[SCAN] 检查 PAM 密码质量模块..."
    
    case "$PKG_MGR" in
        apt)
            ensure_pkg "libpam-pwquality" || STEP6_OK=false
            ;;
        yum|dnf)
            ensure_pkg "libpwquality" || STEP6_OK=false
            log_verbose "RHEL 系统: pam_pwquality.so 由 libpwquality 包提供"
            ;;
        zypper)
            # SUSE: 不使用 pam_pwquality，改用已安装的 pam_cracklib.so
            # 尝试安装 libpwquality1（提供 pwquality.conf），失败不阻断
            ensure_pkg "libpwquality1" 2>/dev/null || \
            ensure_pkg "pam" 2>/dev/null || \
            log_verbose "SUSE: 跳过 pam_pwquality 安装（使用 pam_cracklib.so）"
            STEP6_OK=true
            ;;
    esac
    
    log "[EDIT] 配置密码最小长度..."
    backup_file /etc/login.defs
    
    if ! $DRY_RUN; then
        if grep -q "^#\?PASS_MIN_LEN" /etc/login.defs 2>/dev/null; then
            sed -i "s/^#\?\(PASS_MIN_LEN\)[[:space:]]*.*/\1\t$MIN_LEN/" /etc/login.defs
        else
            printf '\n# Password policy\n' >> /etc/login.defs
            echo "PASS_MIN_LEN	$MIN_LEN" >> /etc/login.defs
        fi
        log "[OK] login.defs 已更新（密码最小长度 $MIN_LEN 字符）"
    fi
    
    log "[EDIT] 配置 pwquality.conf..."
    
    if [ -f /etc/security/pwquality.conf ]; then
        backup_file /etc/security/pwquality.conf
        
        if ! $DRY_RUN; then
            _pwq_tmp="$(mktemp)"
            grep -vE '^#?[[:space:]]*(minlen|minclass|difok|dcredit|ucredit|lcredit|ocredit|maxrepeat|maxsequence|enforce_for_root|retry|usercheck|enforcing|dictcheck|gecoscheck|badwords)[[:space:]=]' \
                /etc/security/pwquality.conf 2>/dev/null > "$_pwq_tmp" || true
            
            cat >> "$_pwq_tmp" <<'PWQEOF'
# ── 安全基线：密码复杂度（由 security_hardening.sh 管理）──
minlen = 12
minclass = 4
difok = 5
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
maxrepeat = 3
maxsequence = 3
enforce_for_root
PWQEOF
            mv -f "$_pwq_tmp" /etc/security/pwquality.conf
            rm -f "$_pwq_tmp"
            log "[OK] pwquality.conf 已完整更新（无空值残留）"
        fi
    else
        log "[WARN] /etc/security/pwquality.conf 不存在，跳过"
    fi
    
    # ================= PAM 密码策略：优先 pam_pwquality，SUSE 用 pam_cracklib =================
    # 通用函数：配置 pam_cracklib.so（SUSE 专用）
    apply_pam_cracklib() {
        local f="$1"
        if [ ! -f "$f" ]; then return; fi
        backup_file "$f"
        if $DRY_RUN; then log "[EDIT] 拟配置 pam_cracklib: $f"; return; fi

        # pam_cracklib 支持的选项（与 pam_pwquality 类似）
        local _opts="retry=3 minlen=${MIN_LEN} dcredit=-1 ucredit=-1 lcredit=-1 ocredit=-1 enforce_for_root"
        local _line="password	requisite	pam_cracklib.so	${_opts}"

        if grep -q "pam_cracklib.so" "$f" 2>/dev/null; then
            # 已存在：检查参数是否完整
            if grep -q "pam_cracklib.so.*minlen=${MIN_LEN}" "$f" 2>/dev/null; then
                log "[SKIP] $f 中 pam_cracklib.so 已配置正确，跳过"
                return
            fi
            sed -i '/pam_cracklib\.so/d' "$f"
        fi

        local _tmp="$(mktemp)"
        local _inserted=false
        while IFS= read -r line; do
            if ! $_inserted && [[ "$line" =~ ^password[[:space:]] ]]; then
                echo "$_line" >> "$_tmp"
                _inserted=true
            fi
            echo "$line" >> "$_tmp"
        done < "$f"

        if $_inserted; then
            mv -f "$_tmp" "$f"
            log "[OK] pam_cracklib.so 已注入 $f（SUSE 密码强策略已生效）"
        else
            rm -f "$_tmp"
            # 没找到 password 行，直接追加
            echo "$_line" >> "$f"
            log "[OK] pam_cracklib.so 已追加到 $f"
        fi
    }

    apply_pam_quality() {
        local f="$1"
        
        # 检查 pam_pwquality.so 是否实际存在
        local _pwq_so=""
        for _d in /usr/lib/security /usr/lib64/security /lib/security /lib64/security \
                 /usr/lib/x86_64-linux-gnu/security /lib/x86_64-linux-gnu/security \
                 /usr/lib/aarch64-linux-gnu/security /lib/aarch64-linux-gnu/security; do
            if [ -f "$_d/pam_pwquality.so" ]; then
                _pwq_so="$_d/pam_pwquality.so"
                break
            fi
        done

        # SUSE 且 pam_pwquality 不存在：改用 pam_cracklib.so
        if [ -z "$_pwq_so" ] && [[ "$DISTRO" == "SUSE" ]]; then
            for _d in /usr/lib/security /usr/lib64/security /lib/security /lib64/security \
                     /usr/lib/x86_64-linux-gnu/security /lib/x86_64-linux-gnu/security \
                     /usr/lib/aarch64-linux-gnu/security /lib/aarch64-linux-gnu/security; do
                if [ -f "$_d/pam_cracklib.so" ]; then
                    log "[INFO] SUSE 环境：使用 pam_cracklib.so 替代 pam_pwquality.so"
                    apply_pam_cracklib "$f"
                    return
                fi
            done
        fi

        if [ -z "$_pwq_so" ]; then
            log "[WARN] pam_pwquality.so 模块文件不存在，跳过 PAM 注入: $f"
            log "[WARN] （密码策略仅通过 /etc/login.defs 生效，强度较弱）"
            return
        fi

        if [ ! -f "$f" ]; then
            log "[WARN] $f 不存在，跳过"
            return
        fi
        
        backup_file "$f"
        
        if $DRY_RUN; then
            log "[EDIT] 拟更新 PAM: $f"
            return
        fi
        
        if grep -q "pam_pwquality.so" "$f" 2>/dev/null; then
            if grep -q "pam_pwquality.so.*minlen=${MIN_LEN}" "$f" 2>/dev/null; then
                log "[SKIP] $f 已配置正确，跳过"
                return
            fi
            sed -i '/pam_pwquality\.so/d' "$f"
        fi
        
        local _tmp="$(mktemp)"
        local _inserted=false
        while IFS= read -r line; do
            if ! $_inserted && [[ "$line" =~ ^password[[:space:]] ]]; then
                echo "${PWQ_LINE}" >> "$_tmp"
                _inserted=true
            fi
            echo "$line" >> "$_tmp"
        done < "$f"
        
        if $_inserted; then
            mv -f "$_tmp" "$f"
            log "[OK] pam_pwquality.so 已注入 $f"
        else
            rm -f "$_tmp"
            log "[WARN] $f 中未找到 password 行，PAM 注入跳过"
        fi
    }
    
    _pam_files=()
    if [[ "$PKG_MGR" == "apt" ]] || [[ "$DISTRO" == "SUSE" ]]; then
        _pam_files=("/etc/pam.d/common-password")
    else
        _pam_files=("/etc/pam.d/password-auth" "/etc/pam.d/system-auth")
    fi
    
    for _pf in "${_pam_files[@]}"; do
        if [ -f "$_pf" ]; then
            apply_pam_quality "$_pf"
        else
            log_verbose "PAM 文件不存在，跳过: $_pf"
        fi
    done
    
    if [ -f /etc/security/pwhistory.conf ]; then
        backup_file /etc/security/pwhistory.conf
        if ! $DRY_RUN; then
            sed -i '/^#\?remember/d' /etc/security/pwhistory.conf 2>/dev/null || true
            echo "remember = 5" >> /etc/security/pwhistory.conf
            log "[OK] 密码历史已配置 (remember=5)"
        fi
    fi
    
    if $STEP6_OK; then
        mark_completed "$STEP"
        log "[OK] 步骤6: 密码复杂度配置完成"
    else
        log "[WARN] 步骤6: 密码质量模块安装失败，下次运行将重试"
    fi
else
    log "[SKIP] 步骤6: 已完成，跳过"
fi

# ================= 步骤7: 时区和 NTP =================
STEP="7_ntp"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤7: 时区和 NTP 配置"
    
    # 7.1 配置时区
    CURRENT_TZ=$(timedatectl 2>/dev/null | awk '/[Tt]ime zone:/ {print $3}') || CURRENT_TZ=""
    if [ "$CURRENT_TZ" != "Asia/Shanghai" ]; then
        if $DRY_RUN; then
            log "[NET] 拟切换时区至 Asia/Shanghai"
        else
            timedatectl set-timezone Asia/Shanghai 2>/dev/null || log "[WARN] timedatectl 不可用"
            log "[OK] 时区已切换至 Asia/Shanghai"
            
            if timedatectl 2>/dev/null | grep -q "NTP service: active"; then
                timedatectl set-ntp false 2>/dev/null
                sleep 1
                timedatectl set-ntp true 2>/dev/null
                log "[SYNC] 已重启 NTP 服务以同步时间"
            fi
        fi
    else
        log "[SKIP] 时区已是 Asia/Shanghai，跳过"
    fi
    
    # 7.2 NTP 配置（修复：非交互式环境直接使用默认值）
    # 修复：强制非交互式环境，避免 read 命令卡住
    if [ -z "$NTP_SERVER" ]; then
        # 无论是否在终端，都使用默认值（避免交互式输入卡住）
        NTP_SERVER="10.86.8.51"
        log "[INFO] 使用默认 NTP 服务器: ${NTP_SERVER} (可使用 --ntp= 指定)"
        echo ""
    fi
    
    # 根据发行版选择 NTP 服务
    case "$PKG_MGR" in
        apt)
            CHRONY_PKG="chrony"
            CHRONY_SERVICE="chrony"
            CHRONY_CONF="/etc/chrony/chrony.conf"
            ;;
        yum|dnf)
            CHRONY_PKG="chrony"
            CHRONY_SERVICE="chronyd"
            CHRONY_CONF="/etc/chrony.conf"
            ;;
        zypper)
            CHRONY_PKG="chrony"
            CHRONY_SERVICE="chronyd"
            CHRONY_CONF="/etc/chrony.conf"
            ;;
    esac
    
    # WSL 环境：跳过 chrony 安装和服务管理
    if $IS_WSL; then
        log "[INFO] WSL 环境：跳过 Chrony 安装和服务管理（WSL 使用 Windows 主机时间）"
        log "[INFO] 如需在 WSL 中配置 NTP，请手动安装并配置"
    else
        if check_pkg_installed "$CHRONY_PKG" || ensure_pkg "$CHRONY_PKG" "$CHRONY_SERVICE"; then
            log "[OK] ${CHRONY_PKG} 已就绪，开始配置 NTP..."
            
            for try_conf in "/etc/chrony.conf" "/etc/chrony/chrony.conf"; do
                if [ -f "$try_conf" ]; then
                    CHRONY_CONF="$try_conf"
                    break
                fi
            done
            
            if $DRY_RUN; then
                log "[WAIT] 拟配置 Chrony: ${CHRONY_CONF}"
            else
                if grep -qF "server ${NTP_SERVER}" "$CHRONY_CONF" 2>/dev/null; then
                    log "[SKIP] Chrony 已配置 ${NTP_SERVER}，跳过 NTP 配置"
                else
                    backup_file "$CHRONY_CONF"
                    sed -i 's/^[^#]*server /#&/' "$CHRONY_CONF" 2>/dev/null
                    sed -i 's/^[^#]*pool /#&/' "$CHRONY_CONF" 2>/dev/null
                    sed -i "1i server ${NTP_SERVER} iburst maxpoll 10" "$CHRONY_CONF"
                    log "[OK] Chrony 已配置: ${NTP_SERVER}"
                    
                    svc_ctrl enable "$CHRONY_SERVICE"
                    svc_ctrl restart "$CHRONY_SERVICE"
                    log "[SYNC] 等待时间同步（最多 30 秒）..."
                    sleep 5
                    
                    if command -v chronyc &>/dev/null; then
                        for i in {1..3}; do
                            chronyc makestep 2>/dev/null && log "[OK] Chrony 强制同步时间成功 (尝试 $i)" && break
                            log "[WARN] Chrony 同步失败，重试 ($i/3)..."
                            sleep 2
                        done
                        
                        log "[DATA] Chrony 同步状态:"
                        chronyc tracking 2>/dev/null | grep -E "Reference ID|Last offset|RMS offset|System time" | head -4
                    fi
                    
                    if timedatectl 2>/dev/null | grep -q "System clock synchronized: yes"; then
                        log "[OK] 系统时间已同步"
                    else
                        log "[WARN] 系统时间未同步，可能需要手动干预"
                        log "[INFO] 建议手动执行: sudo chronyc makestep"
                    fi
                    
                    log "[TIME] 当前系统时间: $(date)"
                fi
            fi
        else
            log "[WARN] Chrony 安装失败，尝试使用 systemd-timesyncd 作为回退..."
            
            if $IS_SYSTEMD && [ -f /etc/systemd/timesyncd.conf ]; then
                backup_file /etc/systemd/timesyncd.conf
                if ! grep -q "^NTP=$NTP_SERVER" /etc/systemd/timesyncd.conf 2>/dev/null; then
                    sed -i '/^#\?NTP=/d' /etc/systemd/timesyncd.conf 2>/dev/null
                    sed -i "/^\[Time\]/a NTP=${NTP_SERVER}" /etc/systemd/timesyncd.conf 2>/dev/null
                    if ! grep -q "^NTP=$NTP_SERVER" /etc/systemd/timesyncd.conf 2>/dev/null; then
                        echo "NTP=$NTP_SERVER" >> /etc/systemd/timesyncd.conf
                    fi
                    log "[OK] systemd-timesyncd 已配置: $NTP_SERVER"
                else
                    log "[SKIP] systemd-timesyncd 已配置，跳过"
                fi
                svc_ctrl enable systemd-timesyncd
                svc_ctrl restart systemd-timesyncd
                log "[SYNC] 等待时间同步..."
                sleep 5
                log "[TIME] 当前系统时间: $(date)"
            elif [[ "$PKG_MGR" == "apt" ]]; then
                log "[WARN] systemd-timesyncd 配置文件不存在，跳过"
            else
                if check_pkg_installed ntpdate || (ensure_pkg ntpdate 2>/dev/null); then
                    log "[SYNC] 使用 ntpdate 同步时间..."
                    ntpdate -u "$NTP_SERVER" 2>/dev/null && log "[OK] ntpdate 同步成功" \
                        || log "[WARN] ntpdate 同步失败"
                else
                    log "[WARN] 所有 NTP 方法均不可用，请手动配置"
                fi
            fi
        fi
    fi
    
    mark_completed "$STEP"
else
    log "[SKIP] 步骤7: 已完成，跳过"
fi

# ================= 步骤8: 定时任务安全 =================
STEP="8_cron_security"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤8: 定时任务安全配置"
    
    if $DRY_RUN; then
        log "[LOCK] 拟收紧 cron 目录权限"
    else
        for d in /etc/crontab /etc/cron.{hourly,daily,weekly,monthly,d} /etc/cron.allow /etc/at.allow; do
            if [ -d "$d" ] || [ -f "$d" ]; then
                chown root:root "$d" 2>/dev/null; chmod og-rwx "$d" 2>/dev/null
            fi
        done
        rm -f /etc/cron.deny /etc/at.deny 2>/dev/null
        
        log "[WARN] cron.allow / at.allow 将限制仅 root 和 admin_env 可使用定时任务"
        log "[WARN] 如有其他服务账号需使用 cron，请手动追加到 /etc/cron.allow"
        printf "root\nadmin_env\n" > /etc/cron.allow 2>/dev/null
        printf "root\nadmin_env\n" > /etc/at.allow 2>/dev/null
        chmod 600 /etc/cron.allow /etc/at.allow 2>/dev/null
        
        log "[OK] 定时任务权限已收紧"
    fi
    
    mark_completed "$STEP"
else
    log "[SKIP] 步骤8: 已完成，跳过"
fi

# ================= 步骤9: 核心文件权限 =================
STEP="9_file_permissions"
log "[STEP] 步骤9: 核心文件权限配置"

if $DRY_RUN; then
    log "[LOCK] 拟设置核心文件权限"
else
    if [ -f /etc/ssh/sshd_config ]; then
        chown root:root /etc/ssh/sshd_config 2>/dev/null
        chmod 600 /etc/ssh/sshd_config 2>/dev/null
        log_verbose "[OK] SSH 配置权限已设置为 600"
    fi
    
    for key_file in /etc/ssh/ssh_host_*_key; do
        if [ -f "$key_file" ]; then
            chown root:root "$key_file" 2>/dev/null
            chmod 600 "$key_file" 2>/dev/null
            log_verbose "[OK] SSH 私钥权限已设置为 600: $key_file"
        fi
    done
    
    for pub_file in /etc/ssh/ssh_host_*_key.pub; do
        if [ -f "$pub_file" ]; then
            chown root:root "$pub_file" 2>/dev/null
            chmod 644 "$pub_file" 2>/dev/null
            log_verbose "[OK] SSH 公钥权限已设置为 644: $pub_file"
        fi
    done
    
    for f in /var/log/wtmp /var/log/btmp; do
        if [ -f "$f" ]; then
            chmod 664 "$f" 2>/dev/null
            log_verbose "[OK] 日志文件权限已设置: $f"
        fi
    done
    
    for f in /etc/passwd /etc/group /etc/motd /etc/issue /etc/issue.net; do
        if [ -f "$f" ]; then
            chown root:root "$f" 2>/dev/null
            chmod 644 "$f" 2>/dev/null
            log_verbose "[OK] 系统文件权限已设置: $f"
        fi
    done
    
    SHADOW_GROUP="shadow"
    if ! getent group shadow &>/dev/null; then
        SHADOW_GROUP="root"
        log_verbose "shadow 组不存在，使用 root:root 作为影子文件所有者"
    fi
    for f in /etc/shadow /etc/gshadow; do
        if [ -f "$f" ]; then
            chown "root:${SHADOW_GROUP}" "$f" 2>/dev/null
            chmod 640 "$f" 2>/dev/null
            log_verbose "[OK] 影子文件权限已设置为 640: $f"
        fi
    done
    
    for sensitive_file in /etc/crontab /etc/sudoers /etc/sudoers.d/*; do
        if [ -f "$sensitive_file" ]; then
            if [[ "$sensitive_file" == "/etc/sudoers" ]] || [[ "$sensitive_file" == "/etc/sudoers.d"* ]]; then
                chown root:root "$sensitive_file" 2>/dev/null
                chmod 440 "$sensitive_file" 2>/dev/null
                log_verbose "[OK] Sudo 文件权限已设置为 440: $sensitive_file"
            else
                chown root:root "$sensitive_file" 2>/dev/null
                chmod 600 "$sensitive_file" 2>/dev/null
                log_verbose "[OK] 敏感文件权限已设置为 600: $sensitive_file"
            fi
        fi
    done
    
    log "[OK] 核心文件权限已配置"
fi

# ================= 步骤10: 关闭高风险服务 =================
STEP="10_stop_services"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤10: 关闭高风险服务"
    
    # WSL 环境：跳过服务管理
    if $IS_WSL; then
        log "[INFO] WSL 环境：跳过高风险服务检查（WSL 中不运行这些服务）"
        mark_completed "$STEP"
    else
        declare -A SERVICES_MAP=(
            ["nis"]="nis|rpc.nisd|ypserv"
            ["slapd"]="slapd|openldap"
            ["snmpd"]="snmpd|net-snmp"
            ["rpcbind"]="rpcbind|rpcbind.service|portmap"
            ["nfs"]="nfs|nfs-server|nfs-kernel-server|nfsd"
            ["autofs"]="autofs|autofs.service"
            ["sendmail"]="sendmail|sendmail.service|sendmail.mta"
            ["finger"]="finger|fingerd"
            ["vsftpd"]="vsftpd|vsftpd.service"
            ["tftpd"]="tftpd|tftpd-hpa|tftp"
            ["telnet"]="telnet|telnetd|telnet.service"
            ["avahi"]="avahi-daemon|avahi-daemon.service|avahi"
            ["rsh"]="rsh|rshd|rsh.service"
            ["rexec"]="rexec|rexecd|rexec.service"
            ["rlogin"]="rlogin|rlogind|rlogin.service"
            ["squid"]="squid|squid.service|squid3"
            ["samba"]="smb|smb.service|samba|nmbd"
            ["bind"]="named|bind|bind9|named.service"
            ["dhcp"]="dhcpd|dhcp|dhcpd.service|dhcp3-server"
            ["cups"]="cups|cups.service|cupsd"
            ["xinetd"]="xinetd|xinetd.service"
        )
        
        declare -a HIGH_RISK_SERVICES=(
            "telnet" "rsh" "rexec" "rlogin" "finger" "tftpd"
            "vsftpd" "squid" "samba" "rpcbind"
            "nis" "slapd" "cups" "snmpd"
            "dhcp" "bind" "sendmail"
            "xinetd" "autofs" "avahi"
        )
        
        STOPPED=0
        SKIPPED=0
        
        for svc in "${HIGH_RISK_SERVICES[@]}"; do
            alt_names="${SERVICES_MAP[$svc]:-$svc}"
            found=""
            
            for try_name in $(echo "$alt_names" | tr '|' ' '); do
                if $IS_SYSTEMD; then
                    if systemctl list-unit-files 2>/dev/null | grep -qE "^${try_name}"'\.(service|socket|timer|mount|target)' ||
                       systemctl list-unit-files 2>/dev/null | grep -qE "^${try_name}$"; then
                        found="$try_name"
                        break
                    fi
                else
                    [ -f "/etc/init.d/$try_name" ] && found="$try_name" && break
                fi
            done
            
            if [ -n "$found" ]; then
                if svc_is_disabled "$found"; then
                    if $IS_SYSTEMD; then
                        if systemctl is-active --quiet "${found}.service" 2>/dev/null || systemctl is-active --quiet "$found" 2>/dev/null; then
                            log "[WARN] $found 已禁用但仍在运行，正在停止..."
                            svc_ctrl stop "$found" 2>/dev/null
                            log "[STOP] 已停止运行中的服务: $found"
                            ((STOPPED++)) || true
                        fi
                    fi
                    ((SKIPPED++)) || true
                    continue
                fi
                if $DRY_RUN; then
                    log "[STOP] 拟停止: $found"
                else
                    svc_ctrl disable "$found" 2>/dev/null
                    svc_ctrl stop "$found" 2>/dev/null
                    log "[STOP] 已停止: $found"
                fi
                ((STOPPED++)) || true
            fi
        done
        
        if $DRY_RUN; then
            log "[SCAN] 拟停止 $STOPPED 个服务，跳过 $SKIPPED 个"
        else
            log "[OK] 已停止 $STOPPED 个服务，$SKIPPED 个已禁用"
        fi
        
        mark_completed "$STEP"
    fi
else
    log "[SKIP] 步骤10: 已完成，跳过"
fi

# ================= 步骤11: SSH 硬化 =================
STEP="11_ssh_hardening"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤11: SSH 硬化配置"
    
    # WSL 环境：跳过 SSH 硬化（WSL 通常不需要 SSH Server）
    if $IS_WSL; then
        log "[INFO] WSL 环境：跳过 SSH 硬化（WSL 通常不需要 SSH Server）"
        log "[INFO] 如需在 WSL 中启用 SSH，请手动安装并配置"
        mark_completed "$STEP"
    else
        if ! command -v sshd &>/dev/null; then
            log "[WARN] SSH Server 未安装，跳过"
        else
            SSHD_V=$(ssh_major_version)
            log "[SCAN] OpenSSH v${SSHD_V}"
            
            if $DRY_RUN; then
                log "[LOCK] 拟硬化 SSH 配置"
            else
                for kf in /etc/ssh/ssh_host_*_key; do
                    [ -f "$kf" ] && chown root:root "$kf" 2>/dev/null; [ -f "$kf" ] && chmod 600 "$kf" 2>/dev/null
                done
                for pf in /etc/ssh/ssh_host_*_key.pub; do
                    [ -f "$pf" ] && chown root:root "$pf" 2>/dev/null; [ -f "$pf" ] && chmod 644 "$pf" 2>/dev/null
                done
                
                SAFE_DIR="/etc/ssh/sshd_config.d"
                USE_CONFIG_D=false
                
                # 检查是否支持 Include 指令（OpenSSH >= 8.2）
                # 先检查是否已配置 Include
                if [ -f /etc/ssh/sshd_config ] && grep -q "^Include.*sshd_config.d" /etc/ssh/sshd_config 2>/dev/null; then
                    USE_CONFIG_D=true
                elif [ "$SSHD_V" -ge 9 ] 2>/dev/null; then
                    # OpenSSH 9.x+ 肯定支持 Include
                    USE_CONFIG_D=true
                    if ! grep -q "^Include.*sshd_config.d" /etc/ssh/sshd_config 2>/dev/null; then
                        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config 2>/dev/null
                        log "[EDIT] 已添加 Include 指令到 sshd_config（末尾，确保硬化优先）"
                    fi
                elif [ "$SSHD_V" -eq 8 ] 2>/dev/null; then
                    # OpenSSH 8.x - 尝试使用 Include，如果失败则回退
                    if ! grep -q "^Include.*sshd_config.d" /etc/ssh/sshd_config 2>/dev/null; then
                        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config 2>/dev/null
                        # 验证配置是否有效
                        if sshd -t 2>/dev/null; then
                            USE_CONFIG_D=true
                            log "[EDIT] 已添加 Include 指令到 sshd_config（OpenSSH 8.x）"
                        else
                            # Include 不支持，回退到直接编辑 sshd_config
                            sed -i '/^Include.*sshd_config.d/d' /etc/ssh/sshd_config 2>/dev/null
                            USE_CONFIG_D=false
                            log "[WARN] OpenSSH 8.x 不支持 Include，将直接编辑 sshd_config"
                        fi
                    else
                        USE_CONFIG_D=true
                    fi
                fi
                
                if $USE_CONFIG_D; then
                    mkdir -p "$SAFE_DIR"
                    
                    if [ -f "$SAFE_DIR/99-hardening.conf" ]; then
                        log "[SKIP] SSH 硬化配置已存在，跳过"
                    else
                        cat > "$SAFE_DIR/99-hardening.conf" << 'SSH_EOF'
# SSH Security Hardening
LogLevel INFO
GatewayPorts no
UsePAM yes
X11Forwarding no
LoginGraceTime 2m
MaxAuthTries 5
HostbasedAuthentication no
IgnoreRhosts yes
PermitEmptyPasswords no
PasswordAuthentication yes
PubkeyAuthentication yes
StrictModes yes
ClientAliveInterval 300
ClientAliveCountMax 3
MaxSessions 10
MaxStartups 10:30:100
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
HostKeyAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256
PubkeyAcceptedKeyTypes ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256
SSH_EOF
                        log "[OK] SSH 硬化配置已应用: $SAFE_DIR/99-hardening.conf"
                    fi
                else
                    log "[WARN] OpenSSH < 7.3，直接修改 sshd_config"
                    
                    HARDENING_APPLIED=false
                    declare -A SSH_SETTINGS=(
                        ["LogLevel"]="INFO"
                        ["GatewayPorts"]="no"
                        ["X11Forwarding"]="no"
                        ["LoginGraceTime"]="2m"
                        ["MaxAuthTries"]="5"
                        ["PermitEmptyPasswords"]="no"
                        ["ClientAliveInterval"]="300"
                        ["ClientAliveCountMax"]="3"
                        ["MaxSessions"]="10"
                    )
                    
                    for key in "${!SSH_SETTINGS[@]}"; do
                        val="${SSH_SETTINGS[$key]}"
                        if grep -q "^${key} ${val}$" /etc/ssh/sshd_config 2>/dev/null; then
                            continue
                        fi
                        if grep -q "^#\?${key}" /etc/ssh/sshd_config 2>/dev/null; then
                            sed -i "s/^#\?${key}.*/${key} ${val}/" /etc/ssh/sshd_config 2>/dev/null
                        else
                            echo "${key} ${val}" >> /etc/ssh/sshd_config 2>/dev/null
                        fi
                        HARDENING_APPLIED=true
                    done
                    
                    if $HARDENING_APPLIED; then
                        log "[OK] SSH 硬化配置已直接写入 sshd_config"
                    fi
                fi
                
                if sshd -t 2>/dev/null; then
                    log "[OK] SSH 配置语法验证通过，重启服务..."
                    svc_ctrl restart sshd 2>/dev/null || svc_ctrl restart ssh 2>/dev/null
                    log "[OK] SSH 服务已重启"
                else
                    log "[WARN] SSH 配置语法验证失败！跳过重启，请手动检查配置"
                    sshd_err=$(sshd -t 2>&1) || true
                    printf '%s\n' "$sshd_err" | while IFS= read -r err; do
                        [ -n "$err" ] && log "[WARN] sshd -t: $err"
                    done || true
                fi
            fi
        fi
        
        mark_completed "$STEP"
    fi
else
    log "[SKIP] 步骤11: 已完成，跳过"
fi

# ================= 步骤12: 内核网络参数 =================
STEP="12_sysctl"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤12: 内核网络参数配置"
    
    if [ ! -f /etc/sysctl.conf ]; then touch /etc/sysctl.conf; fi
    
    if $DRY_RUN; then
        log "[EDIT] 拟配置内核参数"
    else
        backup_file /etc/sysctl.conf
        
        # 禁用不必要的内核模块
        [ -d /etc/modprobe.d ] || mkdir -p /etc/modprobe.d
        echo "install sctp /bin/true" > /etc/modprobe.d/sctp.conf 2>/dev/null || true
        echo "install dccp /bin/true" > /etc/modprobe.d/dccp.conf 2>/dev/null || true
        echo "install rds /bin/true" > /etc/modprobe.d/rds.conf 2>/dev/null || true
        echo "install tipc /bin/true" > /etc/modprobe.d/tipc.conf 2>/dev/null || true
    fi

    SYSCTL_PARAMS=(
        "net.ipv4.conf.all.send_redirects = 0"
        "net.ipv4.conf.default.send_redirects = 0"
        "net.ipv4.conf.all.accept_source_route = 0"
        "net.ipv4.conf.default.accept_source_route = 0"
        "net.ipv4.icmp_echo_ignore_broadcasts = 1"
        "kernel.randomize_va_space = 2"
        "net.ipv6.conf.all.forwarding = 0"
        "net.ipv6.conf.all.accept_source_route = 0"
        "net.ipv6.conf.default.accept_source_route = 0"
        "net.ipv4.conf.all.secure_redirects = 0"
        "net.ipv4.conf.default.secure_redirects = 0"
        "net.ipv4.conf.all.log_martians = 1"
        "net.ipv4.conf.default.log_martians = 1"
        "net.ipv4.icmp_ignore_bogus_error_responses = 1"
        "net.ipv4.conf.all.rp_filter = 1"
        "net.ipv4.conf.default.rp_filter = 1"
        "net.ipv4.tcp_syncookies = 1"
        "net.ipv6.conf.all.accept_ra = 0"
        "net.ipv6.conf.default.accept_ra = 0"
        "net.ipv4.conf.all.accept_redirects = 0"
        "net.ipv4.conf.default.accept_redirects = 0"
        "net.ipv6.conf.all.accept_redirects = 0"
        "net.ipv6.conf.default.accept_redirects = 0"
    )
    
    for p in "${SYSCTL_PARAMS[@]}"; do 
        apply_sysctl_safe "$p"
    done

    # WSL 环境：跳过 ip_forward 检查（WSL 不使用 Docker）
    if ! $IS_WSL; then
        if ! command -v docker &>/dev/null && ! [ -f /run/containerd/containerd.pid ]; then
            apply_sysctl_safe "net.ipv4.ip_forward = 0"
        else
            log "[INFO] 检测到容器环境(Docker/containerd)，跳过禁用 ip_forward"
        fi
    fi

    if ! $DRY_RUN; then
        sysctl -p >/dev/null 2>&1 && log "[OK] 内核参数已生效" || log "[WARN] 部分参数需重启生效"
    fi
    
    mark_completed "$STEP"
else
    log "[SKIP] 步骤12: 已完成，跳过"
fi

# ================= 步骤13: Postfix 限制 =================
STEP="13_postfix"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤13: Postfix 安全配置"
    
    if ! check_pkg_installed postfix; then
        log "[NOTE] Postfix 未安装，跳过"
    else
        POSTFIX_CF="/etc/postfix/main.cf"
        if [ ! -f "$POSTFIX_CF" ]; then
            log "[WARN] 未找到 Postfix 配置，跳过"
        else
            if $DRY_RUN; then
                log "[LOCK] 拟限制 Postfix 至 loopback"
            else
                backup_file "$POSTFIX_CF"
                
                if grep -q "^inet_interfaces = loopback-only" "$POSTFIX_CF"; then
                    log "[SKIP] Postfix 已限制至 loopback，跳过"
                else
                    sed -i 's/^inet_interfaces /#&/' "$POSTFIX_CF"
                    echo "inet_interfaces = loopback-only" >> "$POSTFIX_CF"
                    svc_ctrl restart postfix
                    log "[OK] Postfix 已限制至本地回环"
                fi
            fi
        fi
    fi
    
    mark_completed "$STEP"
else
    log "[SKIP] 步骤13: 已完成，跳过"
fi

# ================= 步骤14: MOTD 横幅 =================
STEP="14_motd"
if ! is_completed "$STEP"; then
    log "[STEP] 步骤14: 设置 MOTD 警告横幅"
    
    if $DRY_RUN; then
        log "[EDIT] 拟设置 MOTD"
    else
        cat > /etc/motd << 'EOL'
*******************************************************************************
*   The standard Company warning banner must be displayed at all logins.      *
*                                                                             *
*******************************************************************************
EOL
        log "[OK] MOTD 横幅已设置"
        
        cp /etc/motd /etc/issue 2>/dev/null
        cp /etc/motd /etc/issue.net 2>/dev/null
    fi
    
    mark_completed "$STEP"
else
    log "[SKIP] 步骤14: 已完成，跳过"
fi

# ================= 总结 =================
echo ""
log "═══════════════════════════════════════════════════════════"
log "  [DONE] 安全加固流程完成！"
log "═══════════════════════════════════════════════════════════"
log "  系统: $DISTRO $VERSION"
log "  状态文件: ${STATE_FILE}"
log "  详细日志: ${LOG_FILE}"
log ""
if $FORCE_RERUN; then
    log "  使用 --force 或 -f 可重新执行所有步骤"
fi
log "═══════════════════════════════════════════════════════════"

exit 0
