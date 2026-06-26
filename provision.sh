#!/usr/bin/env bash
# provision.sh - Vagrant 自动化配置脚本
# 用法: ./provision.sh <hostname>
# 此脚本由 Vagrantfile 自动调用

set -euxo pipefail

NODE_NAME="${1:-unknown}"
LOG_FILE="/var/log/vagrant_provision.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== 开始配置 $NODE_NAME ($(date)) ==="

# 检测发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="$ID"
    VERSION="$VERSION_ID"
    PRETTY="$PRETTY_NAME"
else
    echo "ERROR: 无法检测发行版"
    exit 1
fi

echo "检测到: $PRETTY"

# ================= 配置网络 =================
configure_network() {
    echo "配置网络..."
    case "$DISTRO" in
        ubuntu|debian)
            # Netplan 配置（启用 eth1）
            if [ -d /etc/netplan ]; then
                cat > /etc/netplan/99-vagrant.yaml <<'EOF'
network:
  version: 2
  ethernets:
    eth1:
      dhcp4: true
EOF
                netplan apply 2>&1 || true
            fi
            ;;
        centos|rhel|almalinux|rocky|ol)
            # NetworkManager 配置
            if command -v nmcli &>/dev/null; then
                nmcli device connect eth1 2>/dev/null || true
                nmcli device up eth1 2>/dev/null || true
            fi
            ;;
        opensuse-leap|sles)
            # wicked 配置
            if command -v wicked &>/dev/null; then
                wicked ifup eth1 2>/dev/null || true
            fi
            ;;
    esac
    echo "网络配置完成"
}

# ================= 安装测试依赖 =================
install_deps() {
    echo "安装测试依赖..."
    case "$DISTRO" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y \
                software-properties-common \
                curl wget git \
                vim nano \
                net-tools iproute2 \
                sudo \
                systemd \
                auditd audispd-plugins \
                libpam-pwquality \
                libpam-cracklib \
                sysstat \
                pciutils \
                lsb-release \
                2>&1 || true
            ;;
        centos|rhel|almalinux|rocky|ol)
            if command -v dnf &>/dev/null; then
                dnf install -y \
                    curl wget git \
                    vim nano \
                    net-tools iproute \
                    sudo \
                    systemd \
                    audit \
                    pam_pwquality \
                    cracklib \
                    sysstat \
                    pciutils \
                    redhat-lsb \
                    2>&1 || true
            else
                yum install -y \
                    curl wget git \
                    vim nano \
                    net-tools iproute \
                    sudo \
                    systemd \
                    audit \
                    pam_pwquality \
                    cracklib \
                    sysstat \
                    pciutils \
                    2>&1 || true
            fi
            ;;
        opensuse-leap|sles)
            zypper --non-interactive install \
                curl wget git \
                vim nano \
                net-tools iproute2 \
                sudo \
                systemd \
                audit \
                pam_cracklib \
                pam_pwquality \
                sysstat \
                pciutils \
                lsb-release \
                2>&1 || true
            ;;
    esac
    echo "依赖安装完成"
}

# ================= 部署安全加固脚本 =================
deploy_script() {
    echo "部署安全加固脚本..."
    mkdir -p /opt/security
    
    # 从 Vagrant 共享目录复制脚本
    if [ -f /vagrant/security_hardening.sh ]; then
        cp /vagrant/security_hardening.sh /opt/security/
        chmod +x /opt/security/security_hardening.sh
        echo "[OK] 脚本已部署到 /opt/security/security_hardening.sh"
    else
        echo "[WARN] 未找到 security_hardening.sh"
        echo "请将脚本放到 Vagrantfile 同级目录"
    fi
    
    # 复制测试脚本
    for test_script in /vagrant/test_*.sh; do
        if [ -f "$test_script" ]; then
            cp "$test_script" /opt/security/
            chmod +x /opt/security/$(basename "$test_script")
            echo "[OK] 已复制 $(basename "$test_script")"
        fi
    done
}

# ================= 配置 sudo 测试用户 =================
setup_test_user() {
    echo "配置测试用户..."
    # 创建 testuser（用于密码策略测试）
    if ! id testuser &>/dev/null; then
        useradd -m -s /bin/bash testuser 2>/dev/null || \
            adduser -D -s /bin/bash testuser 2>/dev/null || true
        echo "testuser:Test@123456" | chpasswd 2>/dev/null || true
        echo "[OK] 测试用户 testuser 已创建"
    fi
    
    # 允许 vagrant 用户无密码 sudo（方便测试）
    if id vagrant &>/dev/null; then
        echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
        chmod 440 /etc/sudoers.d/vagrant
        echo "[OK] vagrant 用户已配置无密码 sudo"
    fi
}

# ================= 主流程 =================
main() {
    echo "=== 开始配置 $NODE_NAME ==="
    echo "发行版: $PRETTY"
    echo "主机名: $(hostname)"
    echo ""
    
    configure_network
    echo ""
    
    install_deps
    echo ""
    
    deploy_script
    echo ""
    
    setup_test_user
    echo ""
    
    echo "=== 配置完成 ($NODE_NAME) ==="
    echo "现在可以运行:"
    echo "  vagrant ssh $NODE_NAME"
    echo "  sudo bash /opt/security/security_hardening.sh --verbose"
    echo ""
    echo "测试脚本位置: /opt/security/"
    ls -l /opt/security/ 2>/dev/null || true
}

main
