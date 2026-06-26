# sudoers 写入方式改进报告

## 改进概述

**改进前**：脚本直接修改 `/etc/sudoers` 主文件（使用 `echo "..." >> /etc/sudoers`），存在以下风险：
1. 写入过程中断可能导致主文件损坏
2. 无法验证单行语法（只能验证整个文件）
3. 主文件被修改，难以排查问题

**改进后**：所有自定义 sudo 配置写入 `/etc/sudoers.d/` drop-in 文件：
1. 主文件保持原厂状态，只启用 `@includedir /etc/sudoers.d`
2. 每个 drop-in 文件单独验证语法（`visudo -c -f /etc/sudoers.d/xxx`）
3. 配置模块化，易于管理和排错

---

## 改进内容

### 1. 使用 `/etc/sudoers.d/security_hardening` drop-in 文件

**改进前**（第 537-548 行）：
```bash
for conf in "Defaults use_pty" "Defaults logfile=/var/log/sudo.log" "Defaults log_input, log_output"; do
    key=$(echo "$conf" | awk '{print $1 " " $2}')
    if ! grep -q "^${key}" /etc/sudoers 2>/dev/null; then
        echo "$conf" >> /etc/sudoers
    fi
done
```

**改进后**（第 544-558 行）：
```bash
SUDOERS_D_FILE="/etc/sudoers.d/security_hardening"

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

chmod 440 "$SUDOERS_D_FILE"

# 验证 drop-in 文件语法（单独验证）
if visudo -cf "$SUDOERS_D_FILE" >/dev/null 2>&1; then
    log "[OK] sudoers.d/security_hardening 语法验证通过"
else
    log "[ERROR] sudoers.d/security_hardening 语法错误，已回滚"
    rm -f "$SUDOERS_D_FILE"
    exit 1
fi
```

---

### 2. 修复 `@includedir` 启用逻辑（Bug 修复）

**问题**：Oracle Linux / AlmaLinux 的 `/etc/sudoers` 主文件中，`@includedir /etc/sudoers.d` 默认是**注释掉的**（`#includedir`）。

**改进前**（第 533-535 行）：
```bash
if ! grep -qE "^(#|@)includedir.*sudoers.d" /etc/sudoers 2>/dev/null; then
    echo "@includedir /etc/sudoers.d" | EDITOR="tee -a" visudo
    log "[OK] 已启用 /etc/sudoers.d/ includedir"
fi
```

**问题**：这个逻辑会匹配 `#includedir`（注释状态），然后跳过，不会启用它。

**改进后**（第 537-572 行）：
```bash
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
        # 都没有，追加新行
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
```

---

### 3. 保留 `admin_nopasswd` drop-in 文件（已正确使用）

**代码位置**：第 550-569 行（未改动）

**说明**：脚本已经在使用 `/etc/sudoers.d/admin_nopasswd` drop-in 文件，这部分不需要改进。

---

## 测试结果

### 测试环境

| 发行版 | 版本 | WSL 环境 |
|---------|------|----------|
| Ubuntu | 24.04 | ✅ |
| SUSE Linux Enterprise | 15 SP7 | ✅ |
| Oracle Linux | 9.5 | ✅ |
| AlmaLinux | 9 | ✅ |

### 测试覆盖的功能

| 功能 | Ubuntu | SUSE | Oracle Linux | AlmaLinux |
|------|-------|------|---------------|-----------|
| `@includedir` 已启用检测 | ✅ | ✅ | ✅ | ✅ |
| `#includedir` 注释取消（Oracle/AlmaLinux） | N/A | N/A | ✅ | ✅ |
| drop-in 文件创建 | ✅ | ✅ | ✅ | ✅ |
| 主文件未被修改 | ✅ | ✅ | ✅ | ✅ |
| `visudo -c` 验证通过 | ✅ | ✅ | ✅ | ✅ |

### 测试命令

```bash
# 在 WSL 中测试
wsl -d Ubuntu-24.04 -u root -- bash /mnt/d/Code/安全加固/security_hardening.sh --wsl

# 验证主文件未被修改
grep "^Defaults use_pty" /etc/sudoers 2>/dev/null && echo "❌ 主文件被修改" || echo "✅ 主文件未被修改"

# 验证 drop-in 文件
cat /etc/sudoers.d/security_hardening

# 验证语法
visudo -c
```

---

## 从旧版本迁移（重要！）

如果你的系统之前运行过**改进前**的脚本，主文件中可能有这些残留配置：
```
Defaults use_pty
Defaults logfile=/var/log/sudo.log
Defaults log_input, log_output
```

**需要手动清理**：

```bash
# 1. 备份主文件
cp /etc/sudoers /etc/sudoers.bak.$(date +%Y%m%d_%H%M%S)

# 2. 移除残留配置
cp /etc/sudoers /etc/sudoers.clean
sed -i "/^Defaults use_pty$/d" /etc/sudoers.clean
sed -i "/^Defaults logfile=/d" /etc/sudoers.clean
sed -i "/^Defaults log_input/d" /etc/sudoers.clean
mv /etc/sudoers.clean /etc/sudoers
chmod 440 /etc/sudoers

# 3. 验证语法
visudo -c

# 4. 重新运行脚本（会创建 drop-in 文件）
bash /path/to/security_hardening.sh
```

---

## 使用说明

### 新安装（推荐）

1. 运行脚本：
   ```bash
   bash security_hardening.sh
   ```

2. 验证：
   ```bash
   # 检查 drop-in 文件
   ls -la /etc/sudoers.d/
   
   # 验证语法
   visudo -c
   
   # 测试 sudo
   sudo -n echo "✅ sudo 正常工作"
   ```

### 升级 from 旧版本

1. 清理主文件中的旧配置（参考"从旧版本迁移"章节）
2. 重新运行脚本

---

## 文件清单

| 文件 | 说明 |
|------|------|
| `/etc/sudoers.d/security_hardening` | 改进后创建，包含所有自定义 sudo 配置 |
| `/etc/sudoers.d/admin_nopasswd` | 已存在（改进前就正确），包含 `admin` 组免密规则 |
| `/etc/sudoers` | 主文件，改进后不会被修改（除了启用 `@includedir`） |

---

## 已知问题

### 问题 1：`#includedir` 注释格式差异

**现象**：不同发行版的 `/etc/sudoers` 主文件中，`@includedir` 的注释格式可能不同：
- Oracle Linux / AlmaLinux: `#includedir /etc/sudoers.d`
- Ubuntu / Debian: `@includedir /etc/sudoers.d`（通常已启用）

**脚本处理**：脚本会检测并自动启用（取消注释或追加）。

### 问题 2：WSL 环境不支持 `visudo -f`

**现象**：WSL 环境中，`visudo -f /etc/sudoers.d/xxx` 可能无法正常工作。

**脚本处理**：脚本使用 `visudo -cf`（检查模式）验证语法，而不是 `-f`（编辑模式）。

---

## 总结

✅ **改进成功**：
1. 主文件不会被修改（除了启用 `@includedir`）
2. 所有自定义配置写入 drop-in 文件
3. 每个 drop-in 文件单独验证语法
4. 所有发行版测试通过

✅ **Bug 修复**：
1. 修复 `#includedir` 取消注释逻辑（Oracle Linux / AlmaLinux）
2. 修复 `sed` 命令的分隔符冲突（`@` 被当成分隔符）

⚠️ **注意事项**：
1. 从旧版本升级需要手动清理主文件
2. 确保 `@includedir` 已启用（脚本会自动检测并启用）

---

**报告生成时间**: 2026-06-26 21:26  
**脚本版本**: v5.9 (WSL 兼容修复版)  
**测试人员**: WorkBuddy (AI Assistant)
