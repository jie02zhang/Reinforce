#!/usr/bin/env bash
# generate_report.sh - 生成测试报告

set -euo pipefail

REPORT_DIR="/tmp/test_report"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/test_report_$(hostname)_$(date +%Y%m%d_%H%M%S).md"

# 获取系统信息
HOSTNAME=$(hostname)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_NAME="$PRETTY_NAME"
    DISTRO_ID="$ID"
    DISTRO_VERSION="$VERSION_ID"
else
    DISTRO_NAME="Unknown"
    DISTRO_ID="unknown"
    DISTRO_VERSION="0"
fi

KERNEL_VERSION=$(uname -r)
MEMORY_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "N/A")
DISK_TOTAL=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "N/A")

echo "=========================================="
echo "生成测试报告..."
echo "报告文件: $REPORT_FILE"
echo "=========================================="
echo ""

# ================= 生成报告 =================
cat > "$REPORT_FILE" <<EOF
# 安全加固脚本测试报告

**测试日期**: $(date +'%Y-%m-%d %H:%M:%S')  
**主机名**: $HOSTNAME  
**发行版**: $DISTRO_NAME  
**内核版本**: $KERNEL_VERSION  

---

## 1. 系统信息

| 项目 | 值 |
|------|-----|
| 发行版 | $DISTRO_NAME |
| 发行版 ID | $DISTRO_ID |
| 版本 | $DISTRO_VERSION |
| 内核版本 | $KERNEL_VERSION |
| 内存 | $MEMORY_TOTAL |
| 磁盘 (/) | $DISK_TOTAL |
| 架构 | $(uname -m) |
| CPU | $(nproc) 核 |

## 2. 脚本执行结果

### 2.1 脚本版本

\`\`\`bash
$(bash /opt/security/security_hardening.sh --help 2>&1 | head -5 || echo "无法获取版本")
\`\`\`

### 2.2 执行日志

\`\`\`log
$(tail -50 /var/log/system_hardening.log 2>/dev/null || echo "日志文件不存在")
\`\`\`

### 2.3 执行的步骤

\`\`\`text
$(cat /var/lib/security_hardening/state 2>/dev/null || echo "状态文件不存在")
\`\`\`

## 3. 测试用例结果

### 3.1 密码策略测试

\`\`\`text
$(bash /opt/security/test_password_policy.sh 2>&1 | tail -30 || echo "测试脚本不存在")
\`\`\`

**检查项**:
- [ ] PAM 配置正确（无 "Module is unknown" 错误）
- [ ] 密码复杂度生效（弱密码被拒绝）
- [ ] 密码过期策略正确（/etc/login.defs）

### 3.2 sudoers 测试

\`\`\`text
$(bash /opt/security/test_sudoers.sh 2>&1 | tail -30 || echo "测试脚本不存在")
\`\`\`

**检查项**:
- [ ] sudoers 语法正确（visudo -c 通过）
- [ ] drop-in 文件生效（/etc/sudoers.d/security_hardening）
- [ ] sudo 日志记录正常（/var/log/sudo.log）

### 3.3 内核参数测试

\`\`\`text
$(bash /opt/security/test_kernel_params.sh 2>&1 | tail -30 || echo "测试脚本不存在")
\`\`\`

**检查项**:
- [ ] ASLR 启用（kernel.randomize_va_space = 2）
- [ ] IP 转发禁用（net.ipv4.ip_forward = 0）
- [ ] ICMP 重定向禁用（accept_redirects = 0）
- [ ] SYN Cookies 启用（tcp_syncookies = 1）

### 3.4 幂等性测试

\`\`\`text
$(bash /opt/security/test_idempotency.sh 2>&1 | tail -30 || echo "测试脚本不存在")
\`\`\`

**检查项**:
- [ ] 第二次运行无错误
- [ ] 状态文件正确（/var/lib/security_hardening/state）
- [ ] --force 参数可强制重跑

## 4. 发现的问题

| Bug ID | 描述 | 严重级别 | 状态 |
|--------|------|----------|------|
| ... | ... | P0/P1/P2 | Open/Fixed |

## 5. 配置文件检查

### 5.1 PAM 配置

\`\`\`text
$(cat /etc/pam.d/common-password 2>/dev/null | grep -E "^password|^#password" | head -10 || \
  cat /etc/pam.d/system-auth 2>/dev/null | grep -E "^password|^#password" | head -10 || \
  echo "未找到 PAM 配置")
\`\`\`

### 5.2 sudoers 配置

\`\`\`text
$(cat /etc/sudoers.d/security_hardening 2>/dev/null || echo "drop-in 文件不存在")
\`\`\`

### 5.3 内核参数配置

\`\`\`text
$(cat /etc/sysctl.d/99-security_hardening.conf 2>/dev/null || \
  grep -E "^(kernel|net|fs)\." /etc/sysctl.conf 2>/dev/null | head -20 || \
  echo "未找到内核参数配置文件")
\`\`\`

## 6. 结论

- [ ] ✅ 通过（所有测试通过）
- [ ] ⚠️ 通过（有警告，但不影响安全）
- [ ] ❌ 失败（存在致命错误）

**通过率**: .../... (...%)

**建议**:
1. ...
2. ...
3. ...

---

*报告生成时间: $(date)*  
*脚本版本: (检查脚本头部)*
EOF

echo ""
echo "=========================================="
echo "报告已生成"
echo "=========================================="
echo ""
cat "$REPORT_FILE"

echo ""
echo "报告文件: $REPORT_FILE"
echo ""
echo "可以复制到主机（在主机上执行）:"
echo "  vagrant scp $HOSTNAME:$REPORT_FILE ."
