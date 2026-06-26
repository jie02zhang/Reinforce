#!/usr/bin/env bash
###############################################################################
# 系统健康度检查清单 - 安全加固后验证脚本
# 用途: 在安全加固脚本运行前后执行，对比系统状态
# 用法: ./health_check.sh [pre|post|compare]
###############################################################################

set -euo pipefail

LOG_DIR="/test_results"
LOG_FILE="${LOG_DIR}/health_check_$(date +%Y%m%d_%H%M%S).log"
BASELINE_FILE="${LOG_DIR}/baseline.txt"
CURRENT_FILE="${LOG_DIR}/current_state.txt"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

separator() {
    echo "═══════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
}

# ================= 1. SSH 连接性检查 =================
check_ssh() {
    log "[CHECK] SSH 服务状态检查"
    separator
    
    # 检查 SSH 服务是否运行
    if pgrep -x "sshd" >/dev/null 2>&1; then
        log "[PASS] SSH 守护进程运行中"
    else
        log "[FAIL] ⚠️  SSH 守护进程未运行！"
    fi
    
    # 检查 SSH 端口监听
    if command -v ss &>/dev/null; then
        SSH_PORT=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | grep -oE '[0-9]+$' | head -1)
    elif command -v netstat &>/dev/null; then
        SSH_PORT=$(netstat -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | grep -oE '[0-9]+$' | head -1)
    else
        SSH_PORT="22"
    fi
    
    if [ -n "${SSH_PORT:-}" ]; then
        log "[PASS] SSH 监听端口: ${SSH_PORT}"
    else
        log "[WARN] 未检测到 SSH 端口监听"
    fi
    
    # 检查 SSH 配置文件语法
    if command -v sshd &>/dev/null; then
        if sshd -t 2>&1; then
            log "[PASS] SSH 配置文件语法正确"
        else
            log "[FAIL] ⚠️  SSH 配置文件语法错误！"
            sshd -t 2>&1 | while IFS= read -r line; do
                log "        $line"
            done
        fi
    fi
    
    # 检查关键 SSH 配置
    if [ -f /etc/ssh/sshd_config ]; then
        local port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
        local permit_root=$(grep -E "^PermitRootLogin " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
        local password_auth=$(grep -E "^PasswordAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
        
        log "[INFO] SSH 配置: Port=${port:-22}, PermitRoot=${permit_root:-yes}, PasswordAuth=${password_auth:-yes}"
        
        if [[ "${permit_root:-yes}" == "no" ]]; then
            log "[WARN] Root 登录已禁用，确保有普通用户可登录"
        fi
    fi
    
    echo ""
}

# ================= 2. 包管理器检查 =================
    check_package_manager() {
        log "[CHECK] 包管理器状态检查"
        separator
        
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
            log "[FAIL] 未找到支持的包管理器！"
            return 1
        fi
        
        log "[INFO] 包管理器: $PKG_MGR"
        
        # 测试包管理器基本功能
        case "$PKG_MGR" in
            apt)
                log "[TEST] 测试 apt-get update..."
                if apt-get update -qq >/dev/null 2>&1; then
                    log "[PASS] apt-get update 成功"
                else
                    log "[FAIL] ⚠️  apt-get update 失败！检查仓库配置"
                fi
                
                log "[TEST] 测试 GPG 校验..."
                if apt-key list >/dev/null 2>&1; then
                    log "[PASS] GPG 校验功能正常"
                else
                    log "[WARN] GPG 校验可能存在问题"
                fi
                ;;
            yum|dnf)
                log "[TEST] 测试 $PKG_MGR repolist..."
                if $PKG_MGR repolist >/dev/null 2>&1; then
                    log "[PASS] $PKG_MGR 仓库列表正常"
                else
                    log "[FAIL] ⚠️  $PKG_MGR 仓库访问失败！"
                fi
                
                log "[TEST] 检查 GPG 校验设置..."
                if grep -r "gpgcheck=0" /etc/yum.repos.d/*.repo 2>/dev/null; then
                    log "[WARN] 检测到 GPG 校验被禁用的仓库"
                else
                    log "[PASS] GPG 校验配置正常"
                fi
                ;;
            zypper)
                log "[TEST] 测试 zypper refresh..."
                if zypper --non-interactive refresh >/dev/null 2>&1; then
                    log "[PASS] zypper refresh 成功"
                else
                    log "[FAIL] ⚠️  zypper refresh 失败！"
                fi
                ;;
        esac
        
        echo ""
    }
    
    # ================= 3. 核心服务检查 =================
    check_core_services() {
        log "[CHECK] 核心服务状态检查"
        separator
        
        local critical_services=("sshd" "cron" "rsyslog" "network")
        
        # 根据系统调整服务名
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian)
                    critical_services=("ssh" "cron" "rsyslog" "networking")
                    ;;
                centos|rhel|rocky|almalinux)
                    critical_services=("sshd" "crond" "rsyslog" "NetworkManager")
                    ;;
                opensuse*|sles)
                    critical_services=("sshd" "cron" "rsyslog" "wicked")
                    ;;
            esac
        fi
        
        for svc in "${critical_services[@]}"; do
            if command -v systemctl &>/dev/null; then
                status=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
                enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "not-found")
                
                if [[ "$status" == "active" ]]; then
                    log "[PASS] 服务 $svc: 运行中 (enabled: $enabled)"
                elif [[ "$status" == "inactive" ]]; then
                    log "[WARN] 服务 $svc: 未运行 (enabled: $enabled)"
                else
                    log "[INFO] 服务 $svc: $status"
                fi
            elif command -v service &>/dev/null; then
                if service "$svc" status >/dev/null 2>&1; then
                    log "[PASS] 服务 $svc: 运行中"
                else
                    log "[WARN] 服务 $svc: 未运行或不存在"
                fi
            else
                log "[INFO] 无法检测服务状态（无 systemctl/service）"
            fi
        done
        
        # 检查 systemd 本身
        if command -v systemctl &>/dev/null; then
            if systemctl --version >/dev/null 2>&1; then
                log "[PASS] systemd 功能正常"
            else
                log "[FAIL] ⚠️  systemd 可能存在问题！"
            fi
        fi
        
        echo ""
    }
    
    # ================= 4. 权限与用户检查 =================
    check_permissions_users() {
        log "[CHECK] 权限与用户安全检查"
        separator
        
        # 检查关键系统文件权限
        local critical_files=(
            "/etc/passwd:644"
            "/etc/group:644"
            "/etc/shadow:640"
            "/etc/gshadow:640"
            "/etc/sudoers:440"
        )
        
        for item in "${critical_files[@]}"; do
            local file="${item%%:*}"
            local expected_perm="${item##*:}"
            
            if [ -f "$file" ]; then
                local actual_perm=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file" 2>/dev/null)
                local owner=$(stat -c "%U:%G" "$file" 2>/dev/null)
                
                if [[ "${actual_perm:-0}" -le "${expected_perm}" ]]; then
                    log "[PASS] $file: 权限=${actual_perm}, 所有者=${owner}"
                else
                    log "[FAIL] ⚠️  $file: 权限过宽 (${actual_perm} > ${expected_perm})"
                fi
            fi
        done
        
        # 检查 sudo 功能
        log "[TEST] 测试 sudo 功能..."
        if command -v sudo &>/dev/null; then
            if echo "" | sudo -n true 2>/dev/null; then
                log "[PASS] sudo 免密配置正常"
            else
                log "[INFO] sudo 需要密码（正常）"
            fi
            
            # 检查 sudoers 语法
            if visudo -cf /etc/sudoers 2>/dev/null; then
                log "[PASS] sudoers 语法正确"
            else
                log "[FAIL] ⚠️  sudoers 语法错误！"
            fi
        fi
        
        # 检查关键用户
        log "[INFO] 检查关键用户..."
        for user in "root" "admin_env"; do
            if id "$user" &>/dev/null; then
                local shell=$(getent passwd "$user" | cut -d: -f7)
                log "[PASS] 用户 $user 存在 (Shell: $shell)"
            else
                log "[WARN] 用户 $user 不存在"
            fi
        done
        
        # 检查 admin 组
        if getent group admin &>/dev/null; then
            log "[PASS] admin 组存在"
            local members=$(getent group admin | cut -d: -f4)
            log "[INFO] admin 组成员: ${members:-无}"
        else
            log "[WARN] admin 组不存在"
        fi
        
        echo ""
    }
    
    # ================= 5. 网络与防火墙检查 =================
    check_network_firewall() {
        log "[CHECK] 网络与防火墙检查"
        separator
        
        # 检查网络连通性
        log "[TEST] 测试网络连通性..."
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            log "[PASS] 外网连通性正常 (8.8.8.8)"
        else
            log "[WARN] 无法连接外网（可能是容器环境或防火墙拦截）"
        fi
        
        # 检查 DNS
        if getent hosts google.com >/dev/null 2>&1; then
            log "[PASS] DNS 解析正常"
        else
            log "[WARN] DNS 解析失败"
        fi
        
        # 检查防火墙状态
        if command -v ufw &>/dev/null; then
            local ufw_status=$(ufw status 2>/dev/null | head -1)
            log "[INFO] UFW 状态: $ufw_status"
        elif command -v firewall-cmd &>/dev/null; then
            if firewall-cmd --state >/dev/null 2>&1; then
                log "[INFO] Firewalld 运行中"
            else
                log "[INFO] Firewalld 未运行"
            fi
        elif command -v SuSEfirewall2 &>/dev/null; then
            log "[INFO] SuSEfirewall2 已安装"
        else
            log "[INFO] 未检测到防火墙服务"
        fi
        
        # 检查监听端口
        log "[INFO] 当前监听端口:"
        if command -v ss &>/dev/null; then
            ss -tlnp 2>/dev/null | grep LISTEN | while read -r line; do
                log "        $line"
            done
        elif command -v netstat &>/dev/null; then
            netstat -tlnp 2>/dev/null | grep LISTEN | while read -r line; do
                log "        $line"
            done
        fi
        
        echo ""
    }
    
    # ================= 6. 系统资源检查 =================
    check_system_resources() {
        log "[CHECK] 系统资源检查"
        separator
        
        # 磁盘空间
        log "[INFO] 磁盘使用情况:"
        df -h 2>/dev/null | while read -r line; do
            log "        $line"
        done
        
        # 内存使用
        log "[INFO] 内存使用情况:"
        free -h 2>/dev/null | while read -r line; do
            log "        $line"
        done
        
        # inode 使用
        log "[INFO] Inode 使用情况:"
        df -i 2>/dev/null | grep -v "Filesystem" | while read -r line; do
            log "        $line"
        done
        
        echo ""
    }
    
    # ================= 7. 生成快照 =================
    generate_snapshot() {
        local output_file="$1"
        
        log "[SNAPSHOT] 生成系统快照: $output_file"
        
        {
            echo "=== 系统快照: $(date) ==="
            echo ""
            
            echo "--- 系统信息 ---"
            uname -a
            [ -f /etc/os-release ] && cat /etc/os-release
            echo ""
            
            echo "--- 网络监听端口 ---"
            ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
            echo ""
            
            echo "--- 运行中的服务 ---"
            if command -v systemctl &>/dev/null; then
                systemctl list-units --type=service --state=running --no-pager
            else
                service --status-all 2>/dev/null | grep running
            fi
            echo ""
            
            echo "--- SSH 配置 ---"
            [ -f /etc/ssh/sshd_config ] && grep -E "^[^#]" /etc/ssh/sshd_config | head -20
            echo ""
            
            echo "--- 用户列表 ---"
            getent passwd | grep -E ":/bin/(bash|sh|zsh)$"
            echo ""
            
            echo "--- Sudo 配置 ---"
            [ -f /etc/sudoers ] && grep -v "^#" /etc/sudoers | grep -v "^$"
            [ -d /etc/sudoers.d ] && ls -la /etc/sudoers.d/
            echo ""
            
            echo "--- 核心文件权限 ---"
            ls -la /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/sudoers 2>/dev/null
            echo ""
            
            echo "--- 防火墙规则 ---"
            if command -v iptables &>/dev/null; then
                iptables -L -n 2>/dev/null | head -30
            fi
            echo ""
            
            echo "--- 定时任务 ---"
            crontab -l 2>/dev/null
            ls -la /etc/cron.* 2>/dev/null | head -20
            echo ""
            
        } > "$output_file" 2>&1
        
        log "[PASS] 快照已保存: $output_file"
    }
    
    # ================= 主流程 =================
    main() {
        local mode="${1:-post}"
        
        log "═══════════════════════════════════════════════════════════"
        log "  系统健康度检查工具"
        log "  模式: $mode"
        log "═══════════════════════════════════════════════════════════"
        
        case "$mode" in
            pre)
                log "[INFO] 执行加固前基线检查..."
                generate_snapshot "$BASELINE_FILE"
                check_ssh
                check_package_manager
                check_core_services
                check_permissions_users
                check_network_firewall
                check_system_resources
                log "[DONE] 基线检查完成，结果保存至: $BASELINE_FILE"
                ;;
            post)
                log "[INFO] 执行加固后验证检查..."
                generate_snapshot "$CURRENT_FILE"
                check_ssh
                check_package_manager
                check_core_services
                check_permissions_users
                check_network_firewall
                check_system_resources
                log "[DONE] 验证检查完成，结果保存至: $CURRENT_FILE"
                ;;
            compare)
                log "[INFO] 对比基线快照与当前状态..."
                if [ -f "$BASELINE_FILE" ] && [ -f "$CURRENT_FILE" ]; then
                    log "[COMPARE] 生成对比报告..."
                    diff -u "$BASELINE_FILE" "$CURRENT_FILE" > "${LOG_DIR}/comparison.diff" 2>&1 || true
                    log "[PASS] 对比报告已生成: ${LOG_DIR}/comparison.diff"
                    log "[INFO] 关键变化摘要:"
                    grep -E "^[+-]" "${LOG_DIR}/comparison.diff" | grep -v "^+++" | grep -v "^---" | head -50
                else
                    log "[FAIL] 基线文件或当前状态文件不存在，请先运行 pre 和 post 模式"
                fi
                ;;
            *)
                echo "用法: $0 [pre|post|compare]"
                echo "  pre     - 加固前基线检查"
                echo "  post    - 加固后验证检查"
                echo "  compare - 对比前后状态"
                exit 1
                ;;
        esac
        
        log "═══════════════════════════════════════════════════════════"
        log "  检查完成，详细日志: $LOG_FILE"
        log "═══════════════════════════════════════════════════════════"
    }
    
    main "$@"
