#!/usr/bin/env bash
# 修复 CentOS 7 测试环境

set -e

echo "=== 开始修复 CentOS 7 环境 ==="

# 1. 修复仓库配置（切换到 vault.centos.org）
echo "1. 修复仓库配置..."
sed -i 's/mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/CentOS-*.repo
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo
echo "✅ 仓库已修复"

# 2. 安装 dos2unix
echo "2. 安装 dos2unix..."
yum install -y dos2unix 2>&1 | tail -5
echo "✅ dos2unix 已安装"

# 3. 转换脚本换行符
echo "3. 转换脚本换行符..."
dos2unix /opt/security/security_hardening.sh
echo "✅ 换行符已转换"

# 4. 修复 sudoers（允许无 TTY）
echo "4. 修复 sudoers..."
echo "Defaults !requiretty" >> /etc/sudoers.d/vagrant
chmod 440 /etc/sudoers.d/vagrant
echo "✅ sudoers 已修复"

# 5. 安装依赖
echo "5. 安装依赖..."
yum install -y audit pam_pwquality cracklib chrony postfix 2>&1 | tail -10
echo "✅ 依赖已安装"

echo "=== 修复完成 ==="
echo "现在可以运行: sudo bash /opt/security/security_hardening.sh --verbose"
