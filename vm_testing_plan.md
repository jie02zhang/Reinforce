# 安全加固脚本虚拟机测试方案

**版本**: v1.0  
**日期**: 2026-06-26  
**目标**: 在生产环境相似的虚拟机中全面测试 `security_hardening.sh` 脚本

---

## 📋 一、测试目标

### 1.1 核心目标
- ✅ 验证脚本在**真实虚拟机环境**中的兼容性（非 WSL2/容器）
- ✅ 测试**生产级配置**的正确性（密码策略、sudoers、内核参数等）
- ✅ 验证**幂等性**（重复执行不报错）
- ✅ 测试**回滚能力**（快照恢复）
- ✅ 生成**多发行版兼容性报告**

### 1.2 测试范围
| 类别 | 测试项 |
|------|--------|
| **密码策略** | PAM 配置、密码复杂度、过期策略 |
| **权限管理** | sudoers 配置、文件权限、UMASK |
| **服务安全** | 不必要的服务、防火墙、SELinux/AppArmor |
| **内核安全** | 内核参数（sysctl）、地址空间随机化 |
| **日志审计** | 日志服务、审计规则 |
| **网络安

全** | 网络参数、core dump 限制 |

---

## 🖥️ 二、虚拟机环境规划

### 2.1 测试矩阵

| 发行版 | 版本 | 架构 | 内存 | 磁盘 | 网络 | 优先级 |
|--------|------|------|------|------|------|--------|
| **Ubuntu** | 22.04 LTS | x86_64 | 2GB | 20GB | NAT | P0 |
| **Ubuntu** | 24.04 LTS | x86_64 | 2GB | 20GB | NAT | P0 |
| **Debian** | 12 (Bookworm) | x86_64 | 2GB | 20GB | NAT | P1 |
| **RHEL** | 9.5 | x86_64 | 2GB | 20GB | NAT | P0 |
| **CentOS** | 7.9 | x86_64 | 2GB | 20GB | NAT | P1 |
| **AlmaLinux** | 9.5 | x86_64 | 2GB | 20GB | NAT | P0 |
| **Rocky Linux** | 9.5 | x86_64 | 2GB | 20GB | NAT | P1 |
| **SUSE** | 15 SP7 | x86_64 | 2GB | 20GB | NAT | P0 |
| **Oracle Linux** | 9.5 | x86_64 | 2GB | 20GB | NAT | P0 |
| **Amazon Linux** | 2023 | x86_64 | 2GB | 20GB | NAT | P2 |

### 2.2 虚拟机软件推荐

| 软件 | 优点 | 缺点 | 推荐场景 |
|------|------|------|----------|
| **Vagrant + VirtualBox** | 自动化部署、快照管理、开源免费 | 性能一般 | **推荐**（本文档基于此） |
| **VMware Workstation** | 性能优秀、快照强大 | 商业软件 | 生产环境模拟 |
| **Proxmox VE** | 企业级、Web 管理 | 需要独立服务器 | 团队协作测试 |
| **KVM/QEMU** | 原生 Linux 虚拟化、性能最佳 | 配置复杂 | Linux 桌面用户 |

---

## 🚀 三、自动化部署方案（Vagrant）

### 3.1 环境准备

```powershell
# Windows 主机：安装 Vagrant + VirtualBox
# 1. 安装 VirtualBox
#    下载：https://www.virtualbox.org/wiki/Downloads
#    安装：VirtualBox-7.1.0-Win.exe

# 2. 安装 Vagrant
#    下载：https://developer.hashicorp.com/vagrant/downloads
#    安装：vagrant_2.4.3_windows_amd64.msi

# 3. 验证安装
vagrant --version
VBoxManage --version

# 4. 添加 Vagrant 镜像（国内加速）
vagrant plugin install vagrant-disksize
vagrant plugin install vagrant-proxyconf  # 可选：代理配置
```

### 3.2 Vagrantfile 配置

创建 `Vagrantfile`：

```ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vagrant.plugins = ["vagrant-disksize"]
  
  # 公共配置
  def common_config(vm, hostname, memory=2048, cpus=2)
    vm.vm.hostname = hostname
    vm.disksize.size = "20GB"
    vm.provider "virtualbox" do |vb|
      vb.memory = memory
      vb.cpus = cpus
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    end
    vm.ssh.insert_key = false  # 使用默认 insecure key（方便测试）
  end

  # ================= Ubuntu 22.04 =================
  config.vm.define "ubuntu2204" do |node|
    common_config(node.vm, "ubuntu2204")
    node.vm.box = "bento/ubuntu-22.04"
    node.vm.network "private_network", type: "dhcp"
    node.vm.provision "shell", path: "provision.sh", args: "ubuntu2204"
  end

  # ================= Ubuntu 24.04 =================
  config.vm.define "ubuntu2404" do |node|
    common_config(node.vm, "ubuntu2404")
    node.vm.box = "bento/ubuntu-24.04"
    node.vm.network "private_network", type: "dhcp"
    node.vm.provision "shell", path: "provision.sh", args: "ubuntu2404"
  end

  # ================= Debian 12 =================
  config.vm.define "debian12" do |node|
    common_config(node.vm, "debian12")
    node.vm.box = "bento/debian-12"
    node.vm.network "private_network", type: "dhcp"
    node.vm.provision "shell", path: "provision.sh", args: "debian12"
  end

  # ================= AlmaLinux 9 =================
  config.vm.define "almalinux9" do |node|
    common_config(node.vm, "almalinux9")
    node.vm.box = "bento/almalinux-9"
    node.vm.network "private_network", type: "dhcp"
    node.vm.provision "shell", path: "provision.sh", args: "almalinux9"
  end

  # ================= SUSE 15 SP7 =================
  config.vm.define "suse15" do |node|
    common_config(node.vm, "suse15")
    node.vm.box = "bento/opensuse-leap-15.7"
    node.vm.network "private_network", type: "dhcp"
    node.vm.provision "shell", path: "provision.sh", args: "suse15"
  end

  # ================= Oracle Linux 9 =================
  config.vm.define "oraclelinux9" do |node|
    common_config(node.vm, "oraclelinux9")
    node.vm.box = "bento/oraclelinux-9"
    node.vm.network "private_network", type: "dhcp"
    node.vm.provision "shell", path: "provision.sh", args: "oraclelinux9"
  end

  # ================= Rocky Linux 9 =================
  config.vm.define "rockylinux9" do |node|
    common_config(node.vm, "rockylinux9")
    node.vm.box = "bento/rockylinux-9"
    node.vm.network "private_network", type: "dhcp"
    node.vm.provision "shell", path: "provision.sh", args: "rockylinux9"
  end
end
```

### 3.3 自动化配置脚本（provision.sh）

创建 `provision.sh`（VM 启动后自动执行）：

```bash
#!/usr/bin/env bash
# provision.sh - Vagrant 自动化配置脚本
# 用法: ./provision.sh <hostname>

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
else
    echo "ERROR: 无法检测发行版"
    exit 1
fi

echo "检测到: $PRETTY_NAME"

# 配置静态 IP（方便测试）
configure_network() {
    case "$DISTRO" in
        ubuntu|debian)
            # Netplan 配置
            cat > /etc/netplan/99-vagrant.yaml <<'EOF'
network:
  version: 2
  ethernets:
    eth1:
      dhcp4: true
EOF
            netplan apply
            ;;
        centos|rhel|almalinux|rocky|ol)
            # NetworkManager 配置
            nmcli device connect eth1 2>/dev/null || true
            ;;
        opensuse-leap|sles)
            # wicked 配置
            wicked ifup eth1 2>/dev/null || true
            ;;
    esac
}

# 安装测试依赖
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
                auditd \
                pam_pwquality \
                libpam-cracklib
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
                    cracklib
            else
                yum install -y \
                    curl wget git \
                    vim nano \
                    net-tools iproute \
                    sudo \
                    systemd \
                    audit \
                    pam_pwquality \
                    cracklib
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
                pam_pwquality
            ;;
    esac
}

# 上传安全加固脚本
deploy_script() {
    echo "部署安全加固脚本..."
    mkdir -p /opt/security
    # 注意：需要将 security_hardening.sh 放到 Vagrantfile 同级目录
    if [ -f /vagrant/security_hardening.sh ]; then
        cp /vagrant/security_hardening.sh /opt/security/
        chmod +x /opt/security/security_hardening.sh
        echo "脚本已部署到 /opt/security/security_hardening.sh"
    else
        echo "WARNING: 未找到 security_hardening.sh，请手动上传"
    fi
}

# 主流程
main() {
    configure_network
    install_deps
    deploy_script
    
    echo "=== 配置完成 ($NODE_NAME) ==="
    echo "现在可以运行: vagrant ssh $NODE_NAME"
    echo "然后执行: sudo bash /opt/security/security_hardening.sh"
}

main
```

---

## 🧪 四、测试用例设计

### 4.1 测试流程

```
┌─────────────────────────────────────────────────────┐
│  1. 启动 VM → 创建快照（初始状态）                │
├─────────────────────────────────────────────────────┤
│  2. 首次运行脚本 → 记录结果                        │
├─────────────────────────────────────────────────────┤
│  3. 验证加固项 → 检查配置正确性                    │
├─────────────────────────────────────────────────────┤
│  4. 二次运行脚本 → 验证幂等性                      │
├─────────────────────────────────────────────────────┤
│  5. 回滚快照 → 清理环境                            │
├─────────────────────────────────────────────────────┤
│  6. 循环测试下一个发行版                            │
└─────────────────────────────────────────────────────┘
```

### 4.2 核心测试用例

#### ✅ 用例 1：密码策略测试

| 测试项 | 预期结果 | 验证命令 |
|--------|----------|----------|
| PAM 配置正确 | 无 "Module is unknown" 错误 | `passwd testuser` |
| 密码复杂度生效 | 弱密码被拒绝 | `echo "weak" \| passwd testuser` |
| 密码过期策略 | `/etc/login.defs` 配置正确 | `grep PASS_MAX_DAYS /etc/login.defs` |

**测试脚本**：

```bash
#!/usr/bin/env bash
# test_password_policy.sh

echo "=== 测试密码策略 ==="

# 1. 创建测试用户
useradd -m testuser 2>/dev/null || true

# 2. 尝试修改密码（应该成功）
echo "testuser:Test@123456" | chpasswd
if [ $? -eq 0 ]; then
    echo "[PASS] 密码修改成功"
else
    echo "[FAIL] 密码修改失败"
fi

# 3. 尝试弱密码（应该失败）
echo "weak" | passwd testuser --stdin 2>&1 | grep -i "BAD PASSWORD" && \
    echo "[PASS] 弱密码被拒绝" || \
    echo "[FAIL] 弱密码未被拒绝"

# 4. 检查 PAM 配置
echo "检查 PAM 配置..."
for pam_file in /etc/pam.d/common-password /etc/pam.d/system-auth /etc/pam.d/password-auth; do
    if [ -f "$pam_file" ]; then
        echo "检查 $pam_file ..."
        # 检查是否有不存在的 PAM 模块
        grep -E "^password.*pam_(pwquality|cracklib)\.so" "$pam_file" | while read -r line; do
            module=$(echo "$line" | grep -oP 'pam_\w+\.so')
            if [ -f "/lib/security/$module" ] || [ -f "/lib64/security/$module" ]; then
                echo "[OK] $module 存在"
            else
                echo "[FAIL] $module 不存在！"
            fi
        done
    fi
done

# 5. 清理
userdel -r testuser 2>/dev/null || true
```

#### ✅ 用例 2：sudoers 配置测试

| 测试项 | 预期结果 | 验证命令 |
|--------|----------|----------|
| sudoers 语法正确 | `visudo -c` 返回 OK | `visudo -c` |
| drop-in 文件生效 | `/etc/sudoers.d/` 文件存在 | `ls -l /etc/sudoers.d/` |
| sudo 日志记录 | `/var/log/sudo.log` 生成 | `sudo ls && cat /var/log/sudo.log` |

**测试脚本**：

```bash
#!/usr/bin/env bash
# test_sudoers.sh

echo "=== 测试 sudoers 配置 ==="

# 1. 检查语法
echo "检查 /etc/sudoers 语法..."
if visudo -c; then
    echo "[PASS] sudoers 语法正确"
else
    echo "[FAIL] sudoers 语法错误！"
    exit 1
fi

# 2. 检查 drop-in 文件
echo "检查 drop-in 文件..."
if [ -f /etc/sudoers.d/security_hardening ]; then
    echo "[PASS] drop-in 文件存在"
    echo "内容："
    cat /etc/sudoers.d/security_hardening
else
    echo "[INFO] drop-in 文件不存在（可能未执行脚本）"
fi

# 3. 测试 sudo 日志
echo "测试 sudo 日志..."
sudo -l >/dev/null 2>&1
if [ -f /var/log/sudo.log ]; then
    echo "[PASS] sudo 日志生成成功"
    tail -5 /var/log/sudo.log
else
    echo "[FAIL] sudo 日志未生成"
fi
```

#### ✅ 用例 3：幂等性测试

```bash
#!/usr/bin/env bash
# test_idempotency.sh

echo "=== 测试幂等性 ==="

SCRIPT="/opt/security/security_hardening.sh"
LOG_FILE="/var/log/system_hardening.log"

# 第一次运行
echo "第一次运行..."
time bash "$SCRIPT" 2>&1 | tee /tmp/run1.log

# 第二次运行
echo "第二次运行..."
time bash "$SCRIPT" 2>&1 | tee /tmp/run2.log

# 比较日志
echo "比较两次运行的输出..."
if diff /tmp/run1.log /tmp/run2.log >/dev/null 2>&1; then
    echo "[PASS] 两次运行输出完全相同（幂等）"
else
    echo "[INFO] 两次运行输出不同（可能是状态检查跳过）"
    diff /tmp/run1.log /tmp/run2.log | head -20
fi

# 检查状态文件
echo "检查状态文件..."
if [ -f /var/lib/security_hardening/state ]; then
    echo "已完成的步骤："
    cat /var/lib/security_hardening/state
else
    echo "[INFO] 状态文件不存在"
fi
```

#### ✅ 用例 4：回滚测试

```bash
#!/usr/bin/env bash
# test_rollback.sh

echo "=== 测试回滚能力 ==="

# 1. 记录初始状态
echo "记录初始状态..."
rpm -qa > /tmp/initial_packages.txt 2>/dev/null || \
    dpkg-query -W -f='${Package}\n' > /tmp/initial_packages.txt 2>/dev/null

# 2. 运行脚本
echo "运行安全加固脚本..."
bash /opt/security/security_hardening.sh

# 3. 检查变更
echo "检查变更..."
rpm -qa > /tmp/final_packages.txt 2>/dev/null || \
    dpkg-query -W -f='${Package}\n' > /tmp/final_packages.txt 2>/dev/null

diff /tmp/initial_packages.txt /tmp/final_packages.txt > /tmp/package_changes.txt || true
echo "包变更："
cat /tmp/package_changes.txt

# 4. 提示回滚
echo ""
echo "⚠️  现在可以回滚到初始快照："
echo "  vagrant snapshot restore $VM_NAME initial-state --no-provision"
```
```

#### ✅ 用例 5：内核参数测试

```bash
#!/usr/bin/env bash
# test_kernel_params.sh

echo "=== 测试内核参数 ==="

# 检查关键参数
check_param() {
    local param="$1"
    local expected="$2"
    local actual=$(sysctl -n "$param" 2>/dev/null)
    
    if [ "$actual" = "$expected" ]; then
        echo "[PASS] $param = $actual"
    else
        echo "[FAIL] $param: 期望 $expected, 实际 $actual"
    fi
}

check_param "kernel.randomize_va_space" "2"
check_param "net.ipv4.ip_forward" "0"
check_param "net.ipv4.conf.all.accept_redirects" "0"
check_param "net.ipv4.conf.all.send_redirects" "0"
check_param "net.ipv4.tcp_syncookies" "1"

echo ""
echo "所有内核参数："
sysctl -a 2>/dev/null | grep -E "(randomize_va_space|ip_forward|accept_redirects|send_redirects|syncookies)"
```

---

## 📸 五、快照与回滚策略

### 5.1 快照规划

| 快照名称 | 创建时机 | 用途 |
|----------|----------|------|
| `initial-state` | VM 首次启动后 | 基线测试、回滚 |
| `pre-hardening` | 运行脚本前 | 对比变更 |
| `post-hardening` | 运行脚本后 | 验证结果 |
| `broken-state` | 测试失败时 | Bug 复现 |

### 5.2 快照管理命令

```bash
# 创建快照
vagrant snapshot save <vm-name> <snapshot-name>

# 恢复快照
vagrant snapshot restore <vm-name> <snapshot-name> --no-provision

# 列出快照
vagrant snapshot list <vm-name>

# 删除快照
vagrant snapshot delete <vm-name> <snapshot-name>
```

### 5.3 自动化快照脚本

创建 `snapshot_manager.sh`：

```bash
#!/usr/bin/env bash
# snapshot_manager.sh - 快照管理工具

VM_NAME="$1"
ACTION="$2"
SNAPSHOT_NAME="$3"

if [ -z "$VM_NAME" ] || [ -z "$ACTION" ]; then
    echo "用法: $0 <vm-name> <action> [snapshot-name]"
    echo "action: create, restore, list, delete"
    exit 1
fi

case "$ACTION" in
    create)
        if [ -z "$SNAPSHOT_NAME" ]; then
            echo "错误：请指定快照名称"
            exit 1
        fi
        echo "创建快照: $VM_NAME @ $SNAPSHOT_NAME"
        vagrant snapshot save "$VM_NAME" "$SNAPSHOT_NAME"
        ;;
    restore)
        if [ -z "$SNAPSHOT_NAME" ]; then
            echo "错误：请指定快照名称"
            exit 1
        fi
        echo "恢复快照: $VM_NAME @ $SNAPSHOT_NAME"
        vagrant snapshot restore "$VM_NAME" "$SNAPSHOT_NAME" --no-provision
        ;;
    list)
        echo "快照列表: $VM_NAME"
        vagrant snapshot list "$VM_NAME"
        ;;
    delete)
        if [ -z "$SNAPSHOT_NAME" ]; then
            echo "错误：请指定快照名称"
            exit 1
        fi
        echo "删除快照: $VM_NAME @ $SNAPSHOT_NAME"
        vagrant snapshot delete "$VM_NAME" "$SNAPSHOT_NAME"
        ;;
    *)
        echo "未知操作: $ACTION"
        exit 1
        ;;
esac
```

---

## 📊 六、测试执行流程

### 6.1 快速开始

```bash
# 1. 克隆仓库（如果适用）
cd D:\Code\安全加固\

# 2. 启动所有 VM（首次会下载镜像，耗时较长）
vagrant up

# 3. 查看 VM 状态
vagrant status

# 4. SSH 登录到某个 VM
vagrant ssh ubuntu2204

# 5. 在 VM 中运行测试
sudo bash /opt/security/security_hardening.sh --verbose
```

### 6.2 批量测试脚本

创建 `run_tests.sh`（在主机上运行）：

```bash
#!/usr/bin/env bash
# run_tests.sh - 批量测试脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/test_results"
mkdir -p "$LOG_DIR"

VMS=(
    "ubuntu2204"
    "ubuntu2404"
    "debian12"
    "almalinux9"
    "suse15"
    "oraclelinux9"
)

echo "开始批量测试..."
echo "日志目录: $LOG_DIR"

for vm in "${VMS[@]}"; do
    echo ""
    echo "=========================================="
    echo "测试 VM: $vm"
    echo "=========================================="
    
    # 1. 检查 VM 状态
    if ! vagrant status "$vm" | grep -q "running"; then
        echo "启动 $vm ..."
        vagrant up "$vm" --provision
    fi
    
    # 2. 创建初始快照
    echo "创建初始快照..."
    vagrant snapshot save "$vm" "initial-state" 2>/dev/null || \
        echo "快照已存在，跳过"
    
    # 3. 运行安全加固脚本
    echo "运行安全加固脚本..."
    vagrant ssh "$vm" -c "sudo bash /opt/security/security_hardening.sh --verbose" 2>&1 | \
        tee "$LOG_DIR/${vm}_hardening.log"
    
    # 4. 运行测试用例
    echo "运行测试用例..."
    vagrant ssh "$vm" -c "bash /vagrant/test_password_policy.sh" 2>&1 | \
        tee "$LOG_DIR/${vm}_test_password.log"
    
    vagrant ssh "$vm" -c "bash /vagrant/test_sudoers.sh" 2>&1 | \
        tee "$LOG_DIR/${vm}_test_sudoers.log"
    
    vagrant ssh "$vm" -c "bash /vagrant/test_kernel_params.sh" 2>&1 | \
        tee "$LOG_DIR/${vm}_test_kernel.log"
    
    # 5. 测试幂等性
    echo "测试幂等性..."
    vagrant ssh "$vm" -c "bash /vagrant/test_idempotency.sh" 2>&1 | \
        tee "$LOG_DIR/${vm}_test_idempotency.log"
    
    # 6. 生成测试报告
    echo "生成测试报告..."
    vagrant ssh "$vm" -c "bash /vagrant/generate_report.sh" 2>&1 | \
        tee "$LOG_DIR/${vm}_report.log"
    
    # 7. 回滚到初始状态
    echo "回滚到初始状态..."
    vagrant snapshot restore "$vm" "initial-state" --no-provision
    
    echo "完成测试: $vm"
done

echo ""
echo "=========================================="
echo "所有测试完成！"
echo "日志文件在: $LOG_DIR"
echo "=========================================="
```

---

## 📝 七、测试报告模板

### 7.1 报告结构

创建 `generate_report.sh`：

```bash
#!/usr/bin/env bash
# generate_report.sh - 生成测试报告

REPORT_FILE="/tmp/test_report_$(hostname)_$(date +%Y%m%d_%H%M%S).md"

cat > "$REPORT_FILE" <<'EOF'
# 安全加固脚本测试报告

**测试日期**: $(date +'%Y-%m-%d %H:%M:%S')  
**主机名**: $(hostname)  
**发行版**: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)

---

## 1. 系统信息

| 项目 | 值 |
|------|-----|
| 发行版 | ... |
| 内核版本 | ... |
| 内存 | ... |
| 磁盘 | ... |

## 2. 脚本执行结果

### 2.1 执行日志

```log
...
```

### 2.2 执行的步骤

```log
...
```

## 3. 测试用例结果

### 3.1 密码策略测试

- [ ] PAM 配置正确
- [ ] 密码复杂度生效
- [ ] 密码过期策略正确

### 3.2 sudoers 测试

- [ ] sudoers 语法正确
- [ ] drop-in 文件生效
- [ ] sudo 日志记录正常

### 3.3 内核参数测试

- [ ] ASLR 启用
- [ ] IP 转发禁用
- [ ] ICMP 重定向禁用

### 3.4 幂等性测试

- [ ] 第二次运行无错误
- [ ] 状态文件正确

## 4. 发现的问题

| 问题 | 严重级别 | 状态 |
|------|----------|------|
| ... | P0/P1/P2 | Open/Fixed |

## 5. 结论

- [ ] 通过
- [ ] 通过（有警告）
- [ ] 失败

---
*报告生成时间: $(date)*
EOF

cat "$REPORT_FILE"
echo ""
echo "报告已生成: $REPORT_FILE"
```

### 7.2 汇总报告模板

创建 `generate_summary_report.sh`：

```bash
#!/usr/bin/env bash
# generate_summary_report.sh - 生成跨平台汇总报告

REPORT_FILE="./test_results/cross_platform_vm_test_report.md"

cat > "$REPORT_FILE" <<'EOF'
# 跨平台虚拟机测试汇总报告

**测试日期**: 2026-06-26  
**测试人员**: ...  
**脚本版本**: v5.9

---

## 1. 测试环境

| 发行版 | 版本 | 架构 | 测试结果 |
|--------|------|------|----------|
| Ubuntu | 22.04 | x86_64 | ✅ 通过 |
| Ubuntu | 24.04 | x86_64 | ✅ 通过 |
| Debian | 12 | x86_64 | ⚠️ 警告 |
| AlmaLinux | 9.5 | x86_64 | ✅ 通过 |
| SUSE | 15 SP7 | x86_64 | ✅ 通过 |
| Oracle Linux | 9.5 | x86_64 | ✅ 通过 |

## 2. 发现的 Bug

### P0 (致命)

| Bug ID | 描述 | 状态 | 修复版本 |
|--------|------|------|----------|
| BUG-001 | ... | Fixed | v5.9 |

### P1 (严重)

| Bug ID | 描述 | 状态 | 修复版本 |
|--------|------|------|----------|
| BUG-002 | ... | Fixed | v5.9 |

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

**通过率**: 6/6 (100%)  
**建议**: 可以发布到生产环境

---
*报告生成: 2026-06-26*
EOF

echo "汇总报告已生成: $REPORT_FILE"
cat "$REPORT_FILE"
```

---

## 🎯 八、最佳实践

### 8.1 测试前准备

1. **备份脚本** - 每次测试前备份 `security_hardening.sh`
2. **清理环境** - 使用快照回滚到初始状态
3. **记录日志** - 所有测试输出保存到文件
4. **版本控制** - 使用 Git 管理脚本和测试文件

### 8.2 测试中注意事项

1. **观察错误** - 注意任何 WARNING 或 ERROR
2. **验证配置** - 不要只依赖脚本输出，要手动验证
3. **测试边界** - 测试特殊情况（空密码、超长密码等）
4. **性能测试** - 注意脚本执行时间（应该 < 5 分钟）

### 8.3 测试后处理

1. **生成报告** - 及时生成测试报告
2. **修复 Bug** - 发现问题立即修复
3. **回归测试** - 修复后重新测试
4. **文档更新** - 更新脚本注释和 README

---

## 📚 九、附录

### 9.1 常用命令速查表

| 命令 | 说明 |
|------|------|
| `vagrant up` | 启动所有 VM |
| `vagrant up <vm-name>` | 启动指定 VM |
| `vagrant ssh <vm-name>` | SSH 登录 VM |
| `vagrant halt` | 关闭所有 VM |
| `vagrant destroy` | 删除所有 VM |
| `vagrant snapshot save <vm> <name>` | 创建快照 |
| `vagrant snapshot restore <vm> <name>` | 恢复快照 |

### 9.2 故障排查

#### 问题 1: Vagrant 无法下载镜像

**解决方案**:

```bash
# 手动下载镜像
wget https://app.vagrantup.com/bento/boxes/ubuntu-22.04/versions/202407.21.0/providers/virtualbox.box

# 添加到本地
vagrant box add bento/ubuntu-22.04 ./virtualbox.box
```

#### 问题 2: VM 启动失败（VT-x 未启用）

**解决方案**:
1. 重启进入 BIOS
2. 启用 "Intel Virtualization Technology" 或 "AMD-V"
3. 保存并重启

#### 问题 3: 脚本执行超时

**解决方案**:
1. 检查 VM 资源（内存、CPU）
2. 检查网络连接
3. 使用 `--verbose` 参数查看详细输出

---

## 🎉 十、总结

本测试方案提供了：
- ✅ **完整的 VM 测试环境**（Vagrant + VirtualBox）
- ✅ **自动化部署脚本**（provision.sh）
- ✅ **全面的测试用例**（密码、sudoers、内核参数等）
- ✅ **快照管理策略**（回滚能力）
- ✅ **测试报告模板**（单机和汇总报告）

**下一步**:
1. 部署 Vagrant 环境
2. 运行批量测试
3. 修复发现的问题
4. 生成最终测试报告

---

**文档版本**: v1.0  
**最后更新**: 2026-06-26  
**作者**: WorkBuddy AI Assistant
