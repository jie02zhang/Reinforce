# 安全加固脚本生产部署 SOP (Standard Operating Procedure)

**文档版本**: v1.0  
**生效日期**: 2026-06-27  
**适用范围**: 生产环境 Linux 服务器安全加固  
**脚本版本**: security_hardening.sh v6.0  

---

## 📋 目录

1. [文档目的](#文档目的)
2. [适用范围](#适用范围)
3. [前置条件](#前置条件)
4. [部署前准备](#部署前准备)
5. [部署步骤](#部署步骤)
6. [验证测试](#验证测试)
7. [回滚方案](#回滚方案)
8. [应急响应](#应急响应)
9. [附录](#附录)

---

## 📝 文档目的

本文档定义生产环境 Linux 服务器安全加固的标准操作流程，确保：
- ✅ 部署过程标准化、可重复
- ✅ 降低人为错误风险
- ✅ 提供完整的回滚方案
- ✅ 符合变更管理流程

---

## 🖥️ 适用范围

### 适用系统

| 发行版系列 | 版本 | 优先级 |
|------------|------|--------|
| Ubuntu LTS | 20.04, 22.04, 24.04 | 🔴 高 |
| Debian | 11, 12 | 🔴 高 |
| RHEL / CentOS | 7, 8, 9 | 🔴 高 |
| AlmaLinux / Rocky Linux | 8, 9 | 🟡 中 |
| Amazon Linux | 2, 2023 | 🟡 中 |
| SUSE Linux Enterprise | 15 SP1+ | 🟢 低 |

### 不适用环境

❌ **禁止在生产环境直接运行的情况**：
- 核心数据库服务器（需 DBA 确认）
- 负载均衡器（需备份配置文件）
- 容器宿主机（需测试容器兼容性）
- 网络设备故障转移节点（需按顺序操作）

---

## ✅ 前置条件

### 1. 权限要求

```bash
# 必须有 root 或 sudo 权限
sudo -l  # 验证 sudo 权限

# 建议：使用具有 NOPASSWD 的专用运维账号
ssh admin@server
sudo bash security_hardening.sh --verbose
```

### 2. 系统要求

| 项目 | 最低要求 | 推荐配置 |
|------|------------|------------|
| CPU | 1 核 | 2 核+ |
| 内存 | 512 MB | 2 GB+ |
| 磁盘空间 | 100 MB | 1 GB+ |
| 网络 | 可访问软件源 | 稳定连接 |

### 3. 备份要求（强制）

⚠️ **部署前必须完成备份**

```bash
# 创建备份目录
sudo mkdir -p /root/backup_$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/backup_$(date +%Y%m%d_%H%M%S)"

# 备份关键配置文件
sudo cp -p /etc/passwd $BACKUP_DIR/
sudo cp -p /etc/shadow $BACKUP_DIR/
sudo cp -p /etc/group $BACKUP_DIR/
sudo cp -p /etc/sudoers $BACKUP_DIR/
sudo cp -pr /etc/sudoers.d $BACKUP_DIR/
sudo cp -p /etc/ssh/sshd_config $BACKUP_DIR/
sudo cp -p /etc/login.defs $BACKUP_DIR/
sudo cp -p /etc/pam.d/common-password $BACKUP_DIR/ 2>/dev/null || true
sudo cp -p /etc/pam.d/system-auth $BACKUP_DIR/ 2>/dev/null || true
sudo cp -p /etc/security/pwquality.conf $BACKUP_DIR/

# 备份 sysctl 配置
sudo cp -pr /etc/sysctl.d $BACKUP_DIR/
sudo cp -p /etc/sysctl.conf $BACKUP_DIR/

# 记录备份位置
echo "备份已完成: $BACKUP_DIR"
```

### 4. 变更管理

| 变更级别 | 审批要求 | 通知范围 | 回滚窗口 |
|----------|------------|------------|------------|
| 🟢 低（单机测试） | 无需审批 | 运维团队 | 立即 |
| 🟡 中（<10 台） | 组长审批 | 相关团队 | 2 小时 |
| 🔴 高（≥10 台） | 部门审批 | 全公司 | 4 小时 |
| 🔵 关键（核心系统） | CTO 审批 | 全公司 + 客户 | 8 小时 |

---

## 🚀 部署前准备

### 步骤 1：下载脚本

```bash
# 方法 1: 从内部仓库下载（推荐）
curl -o /tmp/security_hardening.sh \
  http://internal-repo.company.com/scripts/security_hardening.sh

# 方法 2: 从 GitHub 下载
curl -o /tmp/security_hardening.sh \
  https://raw.githubusercontent.com/example/security_hardening/main/security_hardening.sh

# 验证文件完整性
md5sum /tmp/security_hardening.sh
# 对比官方 MD5: xxxxxxx

# 赋予执行权限
chmod +x /tmp/security_hardening.sh
```

### 步骤 2：审查脚本

⚠️ **重要：生产环境部署前必须审查脚本内容**

```bash
# 审查脚本（重点关注以下部分）
less /tmp/security_hardening.sh

# 关键检查点：
# 1. 是否有 rm -rf / 等危险命令？
# 2. 是否会删除业务账号？
# 3. 是否会修改关键服务配置？
# 4. 是否有外部下载或上传行为？
```

**审查清单**：

- [ ] 无危险命令（`rm -rf /`, `dd if=/dev/zero` 等）
- [ ] 不会删除业务账号（只锁定系统账号）
- [ ] 不会修改应用配置文件
- [ ] 无外部网络通信（除非明确说明）
- [ ] 版本号正确（v6.0）
- [ ] 支持幂等执行（可重复运行）

### 步骤 3：测试环境验证

⚠️ **强制要求：必须先在测试环境运行**

```bash
# 1. 启动测试 VM
vagrant up ubuntu2204

# 2. 复制脚本到 VM
vagrant ssh ubuntu2204 -c "cat > /tmp/security_hardening.sh" < /tmp/security_hardening.sh

# 3. 运行脚本
vagrant ssh ubuntu2204 -c "sudo bash /tmp/security_hardening.sh --verbose"

# 4. 验证功能
vagrant ssh ubuntu2204 -c "sudo visudo -c"
vagrant ssh ubuntu2204 -c "sudo bash /vagrant/test_results/test_password_policy.sh"

# 5. 测试 SSH 连接（开新终端）
ssh vagrant@127.0.0.1 -p 2222

# 6. 幂等性测试
vagrant ssh ubuntu2204 -c "sudo bash /tmp/security_hardening.sh --verbose"
# 应该显示 "所有步骤已完成，跳过"
```

### 步骤 4：制定回滚计划

**必须明确以下问题**：

1. 如何快速恢复原始配置？
2. 回滚需要多长时间？
3. 回滚是否会影响业务？
4. 是否需要通知用户？

**回滚方案**（见 [回滚方案](#回滚方案) 章节）

---

## 🔧 部署步骤

### 标准部署流程

#### 阶段 1：单机试点（1 台）

```bash
# 1. 登录目标服务器
ssh admin@prod-server-01

# 2. 创建备份（见前置条件）
sudo mkdir -p /root/backup_$(date +%Y%m%d_%H%M%S)
# ... (执行备份命令)

# 3. 上传脚本
scp /tmp/security_hardening.sh admin@prod-server-01:/tmp/

# 4. 运行脚本（详细模式）
sudo bash /tmp/security_hardening.sh --verbose

# 5. 实时监控日志（开第二个终端）
ssh admin@prod-server-01
sudo tail -f /var/log/system_hardening.log

# 6. 验证部署
sudo visudo -c  # 验证 sudoers 语法
sshd -t          # 验证 SSH 配置
sudo bash /tmp/test_password_policy.sh  # 运行测试脚本
```

#### 阶段 2：小批量部署（≤10 台）

```bash
# 使用批量部署工具（示例：并行 SSH）
# 1. 创建服务器列表
cat > /tmp/servers.txt <<EOF
prod-web-01
prod-web-02
prod-web-03
prod-api-01
prod-api-02
EOF

# 2. 批量部署（使用 parallel-ssh 或 Ansible）
for server in $(cat /tmp/servers.txt); do
    echo "=== 部署到 $server ==="
    
    # 上传脚本
    scp /tmp/security_hardening.sh admin@$server:/tmp/
    
    # 远程执行
    ssh admin@$server "sudo bash /tmp/security_hardening.sh --verbose" &
    
    # 限制并发数（避免压力过大）
    if [ $(jobs -r | wc -l) -ge 5 ]; then
        wait -n  # 等待任意一个任务完成
    fi
done

wait  # 等待所有任务完成
```

#### 阶段 3：全量部署（>10 台）

⚠️ **必须使用配置管理工具（Ansible / Puppet / SaltStack）**

```yaml
# Ansible Playbook 示例（deploy_hardening.yml）
---
- name: Deploy Security Hardening Script
  hosts: production
  become: yes
  serial: 5%  # 每次只部署 5% 的服务器
  max_fail_percentage: 10  # 允许最多 10% 失败
  
  tasks:
    - name: Backup critical files
      include_tasks: backup.yml
    
    - name: Copy hardening script
      copy:
        src: security_hardening.sh
        dest: /tmp/security_hardening.sh
        mode: '0755'
    
    - name: Run hardening script
      command: bash /tmp/security_hardening.sh --verbose
      register: result
      failed_when: result.rc != 0
    
    - name: Verify deployment
      include_tasks: verify.yml
    
    - name: Rollback on failure
      include_tasks: rollback.yml
      when: result.rc != 0
```

---

## ✅ 验证测试

### 验证清单

部署完成后，必须执行以下验证：

#### 1. 基础功能验证

```bash
# 验证 sudoers 语法
sudo visudo -c
# 期望输出: "files have no syntax errors"

# 验证 SSH 配置
sudo sshd -t
# 无输出表示配置正确

# 验证 PAM 配置
sudo pamtester login $USER authenticate
# 期望输出: "Authentication succeeded"
```

#### 2. 安全配置验证

```bash
# 运行自动化测试脚本
sudo bash test_password_policy.sh verbose
sudo bash test_sudoers.sh verbose
sudo bash test_ssh_hardening.sh verbose
sudo bash test_kernel_params.sh verbose

# 期望输出: "测试结果: X 通过, 0 失败"
```

#### 3. 业务功能验证

⚠️ **关键：确保业务服务正常运行**

```bash
# 验证 SSH 连接（开新终端）
ssh admin@prod-server-01
# 应该能正常登录

# 验证 sudo 权限
ssh admin@prod-server-01
sudo whoami
# 应该输出: "root"

# 验证业务服务
systemctl status nginx    # Web 服务
systemctl status mysql    # 数据库服务
systemctl status docker  # 容器服务
# 应该显示 "active (running)"
```

#### 4. 幂等性验证

```bash
# 重新运行脚本
sudo bash /tmp/security_hardening.sh --verbose

# 期望输出:
# [INFO] [SKIP] 步骤1: 已完成，跳过
# [INFO] [SKIP] 步骤2: 已完成，跳过
# ...
# [DONE] 安全加固流程完成！
```

---

## ⏪ 回滚方案

### 回滚触发条件

立即触发回滚的情况：
- ❌ SSH 无法连接
- ❌ sudo 命令失败
- ❌ 业务服务无法启动
- ❌ 系统出现不可逆错误

### 回滚步骤

#### 方法 1：使用备份文件恢复（推荐）

```bash
# 1. 登录服务器（通过控制台或带外管理）
# 如果 SSH 无法连接，使用 IPMI/iDRAC/云控制台

# 2. 恢复备份文件
BACKUP_DIR="/root/backup_20260627_102030"  # 替换为实际备份目录

sudo cp -p $BACKUP_DIR/passwd /etc/
sudo cp -p $BACKUP_DIR/shadow /etc/
sudo cp -p $BACKUP_DIR/group /etc/
sudo cp -p $BACKUP_DIR/sudoers /etc/
sudo cp -pr $BACKUP_DIR/sudoers.d /etc/
sudo cp -p $BACKUP_DIR/sshd_config /etc/ssh/
sudo cp -p $BACKUP_DIR/login.defs /etc/
sudo cp -p $BACKUP_DIR/pwquality.conf /etc/security/

# 3. 重启 SSH 服务
sudo systemctl restart sshd

# 4. 验证恢复
sudo visudo -c
sshd -t

# 5. 测试 SSH 连接（开新终端）
ssh admin@prod-server-01
```

#### 方法 2：使用脚本卸载功能（如果支持）

```bash
# 注意：当前版本 (v6.0) 尚未实现 --uninstall 功能
# 未来版本将支持：
sudo bash /tmp/security_hardening.sh --uninstall
```

#### 方法 3：重建服务器（最后手段）

⚠️ **仅在无法恢复时使用**

```bash
# 1. 记录服务器配置
# 2. 销毁服务器
# 3. 从备份镜像重建
# 4. 恢复业务数据
# 5. 验证服务正常
```

### 回滚时间估算

| 回滚方法 | 预计时间 | 适用场景 |
|----------|------------|------------|
| 备份恢复 | 5-10 分钟 | 配置文件错误 |
| 卸载脚本 | 2-5 分钟 | 脚本支持卸载 |
| 重建服务器 | 30-60 分钟 | 严重故障 |

---

## 🚨 应急响应

### 紧急联系人

| 角色 | 姓名 | 电话 | 邮箱 | 备注 |
|------|------|------|------|------|
| 运维负责人 | 张三 | +86 138-xxxx-xxxx | zhangsan@company.com | 24x7 待命 |
| 安全负责人 | 李四 | +86 139-xxxx-xxxx | lisi@company.com | 工作时间 |
| DBA | 王五 | +86 137-xxxx-xxxx | wangwu@company.com | 数据库问题 |
| 网络工程师 | 赵六 | +86 136-xxxx-xxxx | zhaoliu@company.com | SSH 连接问题 |

### 故障等级定义

| 等级 | 定义 | 响应时间 | 处理时间 |
|------|------|------------|------------|
| P1 | 业务完全中断 | 5 分钟 | 30 分钟 |
| P2 | 部分功能异常 | 15 分钟 | 2 小时 |
| P3 | 配置错误但不影响业务 | 1 小时 | 8 小时 |
| P4 | 文档问题 | 4 小时 | 24 小时 |

### 常见故障处理

#### 故障 1：SSH 无法连接

**症状**：`ssh: connect to host x.x.x.x port 22: Connection refused`

**排查步骤**：
1. 通过控制台登录服务器
2. 检查 SSH 服务状态：`systemctl status sshd`
3. 检查 SSH 配置：`cat /etc/ssh/sshd_config`
4. 检查防火墙：`iptables -L` 或 `ufw status`
5. 检查端口监听：`netstat -tlnp | grep 22`

**解决方案**：
```bash
# 恢复 SSH 配置
sudo cp /root/backup_*/sshd_config /etc/ssh/
sudo systemctl restart sshd
```

---

#### 故障 2：sudo 命令失败

**症状**：`sudo: parse error in /etc/sudoers near line X`

**排查步骤**：
1. 使用 `su -` 切换到 root 用户
2. 检查 sudoers 语法：`visudo -c`
3. 查看错误行：`sed -n 'Xp' /etc/sudoers`

**解决方案**：
```bash
# 恢复 sudoers 配置
su -
cp /root/backup_*/sudoers /etc/
cp -r /root/backup_*/sudoers.d /etc/
visudo -c  # 验证
```

---

#### 故障 3：业务服务无法启动

**症状**：`systemctl start nginx` 失败

**排查步骤**：
1. 查看服务日志：`journalctl -u nginx -n 50`
2. 检查配置文件：`nginx -t`
3. 检查文件权限：`ls -la /etc/nginx/`

**解决方案**：
- 如果是权限问题：调整文件权限
- 如果是配置问题：恢复备份配置

---

## 📊 部署后检查

### 定期检查清单

部署完成后 24 小时内，必须完成以下检查：

- [ ] 所有服务器 SSH 连接正常
- [ ] 所有服务器 sudo 命令正常
- [ ] 所有业务服务正常运行
- [ ] 监控系统无异常告警
- [ ] 日志记录正常
- [ ] 备份文件已归档

### 监控指标

| 指标 | 正常范围 | 告警阈值 |
|------|----------|------------|
| SSH 连接成功率 | 100% | < 99% |
| sudo 命令成功率 | 100% | < 99% |
| 服务可用性 | UP | DOWN > 1 分钟 |
| 系统负载 | < 80% | > 90% |

---

## 📝 附录

### 附录 A：快速参考卡片

```
┌─────────────────────────────────────────────────┐
│  安全加固脚本快速参考卡片                        │
├─────────────────────────────────────────────────┤
│ 下载脚本:                                       │
│   curl -O https://.../security_hardening.sh   │
│                                                 │
│ 运行脚本:                                       │
│   sudo bash security_hardening.sh --verbose     │
│                                                 │
│ 验证部署:                                       │
│   sudo visudo -c                               │
│   sshd -t                                      │
│   sudo bash test_*.sh                          │
│                                                 │
│ 回滚命令:                                       │
│   sudo cp -pr /root/backup_*/sudoers /etc/    │
│   sudo systemctl restart sshd                   │
│                                                 │
│ 日志位置:                                       │
│   /var/log/system_hardening.log                │
│   /var/lib/security_hardening/state            │
└─────────────────────────────────────────────────┘
```

### 附录 B：变更记录表

| 日期 | 服务器 | 操作人 | 版本 | 结果 | 备注 |
|------|--------|--------|------|------|------|
| 2026-06-27 | prod-web-01 | admin | v6.0 | 成功 | 首次部署 |
| 2026-06-27 | prod-web-02 | admin | v6.0 | 成功 | - |
| 2026-06-27 | prod-api-01 | admin | v6.0 | 失败 | SSH 配置错误，已回滚 |

### 附录 C：相关文档

- [安全加固脚本 README](README.md)
- [版本历史](CHANGELOG.md)
- [测试报告](test_results/cross_platform_test_report.md)
- [Linux 安全基线标准](https://example.com/security-baseline)
- [公司变更管理流程](https://example.com/change-management)

---

## 📞 文档维护

**文档负责人**: 运维团队  
**更新频率**: 每次脚本版本更新时  
**反馈渠道**: ops-team@company.com  

---

**文档审批记录**:

| 审批人 | 角色 | 日期 | 签名 |
|--------|------|------|------|
| 张三 | 运维负责人 | 2026-06-27 | /s/ Zhang San |
| 李四 | 安全负责人 | 2026-06-27 | /s/ Li Si |

---

**文档版本历史**:

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| v1.0 | 2026-06-27 | 初始版本 | AI Assistant |

---

** END OF DOCUMENT **
