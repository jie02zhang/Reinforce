# 自动化测试脚本 - 在多个 WSL 发行版中测试 security_hardening.sh
# 用法: .\test_security_wsl.ps1

$distros = @(
    "Ubuntu-24.04",
    "OracleLinux_9_5",
    "AlmaLinux-9",
    "SUSE-Linux-Enterprise-15-SP7"
)

$script = "/mnt/d/Code/安全加固/security_hardening.sh"
$logDir = "D:\Code\安全加固\test_results"
$summaryLog = "$logDir\test_summary.log"

# 创建日志目录
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# 初始化摘要日志
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"══════════════════════════════════════════════════════" | Out-File -FilePath $summaryLog
"  跨平台安全加固脚本测试摘要" | Out-File -FilePath $summaryLog -Append
"  测试时间: $timestamp" | Out-File -FilePath $summaryLog -Append
"══════════════════════════════════════════════════════" | Out-File -FilePath $summaryLog -Append
"" | Out-File -FilePath $summaryLog -Append

Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  跨平台安全加固脚本测试" -ForegroundColor Cyan
Write-Host "  测试发行版数量: $($distros.Count)" -ForegroundColor Cyan
Write-Host "  日志目录: $logDir" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$results = @()

foreach ($distro in $distros) {
    Write-Host "─────────────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  [$(($distros.IndexOf($distro))+1)/$($distros.Count)] 测试: $distro" -ForegroundColor Yellow
    Write-Host "─────────────────────────────────────────────────────" -ForegroundColor Yellow
    
    # 检查发行版是否已安装
    $installed = wsl --list --verbose 2>&1 | Select-String $distro
    if (-not $installed) {
        Write-Host "  ⚠️  $distro 未安装，跳过..." -ForegroundColor Yellow
        $results += [PSCustomObject]@{
            Distro = $distro
            Status = "未安装"
            DryRun = "跳过"
            Syntax = "跳过"
        }
        continue
    }
    
    # 1. Dry-run 测试
    Write-Host "  [1/3] Dry-run 测试..." -ForegroundColor Cyan
    $dryRunLog = "$logDir\$($distro.Replace('-','_'))_dryrun.log"
    $dryRunOutput = ""
    $dryRunSuccess = $true
    
    try {
        $dryRunOutput = wsl -d $distro -u root -- bash $script --dry-run 2>&1 | Out-String
        $dryRunOutput | Out-File -FilePath $dryRunLog
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✅ Dry-run 测试通过" -ForegroundColor Green
        } else {
            Write-Host "    ⚠️  Dry-run 测试失败 (退出码: $LASTEXITCODE)" -ForegroundColor Yellow
            $dryRunSuccess = $false
        }
    }
    catch {
        Write-Host "    ❌ Dry-run 测试异常: $_" -ForegroundColor Red
        $dryRunSuccess = $false
        $_ | Out-File -FilePath $dryRunLog
    }
    
    # 2. 语法检查
    Write-Host "  [2/3] 语法检查..." -ForegroundColor Cyan
    $syntaxLog = "$logDir\$($distro.Replace('-','_'))_syntax.log"
    $syntaxOutput = ""
    $syntaxSuccess = $true
    
    try {
        $syntaxOutput = wsl -d $distro -u root -- bash -n $script 2>&1 | Out-String
        $syntaxOutput | Out-File -FilePath $syntaxLog
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✅ 语法检查通过" -ForegroundColor Green
        } else {
            Write-Host "    ❌ 语法检查失败" -ForegroundColor Red
            $syntaxSuccess = $false
        }
    }
    catch {
        Write-Host "    ❌ 语法检查异常: $_" -ForegroundColor Red
        $syntaxSuccess = $false
        $_ | Out-File -FilePath $syntaxLog
    }
    
    # 3. 检测 OS（可选）
    Write-Host "  [3/3] 检测系统信息..." -ForegroundColor Cyan
    $osInfo = ""
    try {
        $osInfo = wsl -d $distro -u root -- cat /etc/os-release 2>&1 | Out-String
        $osInfo | Out-File -FilePath "$logDir\$($distro.Replace('-','_'))_osinfo.log"
        Write-Host "    ✅ 系统信息已保存" -ForegroundColor Green
    }
    catch {
        Write-Host "    ⚠️  无法获取系统信息" -ForegroundColor Yellow
    }
    
    # 记录结果
    $status = if ($dryRunSuccess -and $syntaxSuccess) { "通过" } elseif ($dryRunSuccess -or $syntaxSuccess) { "部分通过" } else { "失败" }
    $results += [PSCustomObject]@{
        Distro = $distro
        Status = $status
        DryRun = if ($dryRunSuccess) { "✅" } else { "❌" }
        Syntax = if ($syntaxSuccess) { "✅" } else { "❌" }
    }
    
    Write-Host "  ✅ $distro 测试完成 (状态: $status)" -ForegroundColor Green
    Write-Host ""
}

# 生成摘要报告
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ 所有测试完成！" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

# 显示表格
$results | Format-Table -AutoSize | Out-String | Write-Host

# 保存摘要
"" | Out-File -FilePath $summaryLog -Append
"测试结果摘要:" | Out-File -FilePath $summaryLog -Append
"─────────────────────────────────────────────────────" | Out-File -FilePath $summaryLog -Append
$results | Format-Table -AutoSize | Out-String | Out-File -FilePath $summaryLog -Append
"" | Out-File -FilePath $summaryLog -Append
"详细日志: $logDir" | Out-File -FilePath $summaryLog -Append

Write-Host "摘要日志: $summaryLog" -ForegroundColor Cyan
Write-Host "详细日志目录: $logDir" -ForegroundColor Cyan
Write-Host ""

# 统计
$passed = ($results | Where-Object { $_.Status -eq "通过" }).Count
$partial = ($results | Where-Object { $_.Status -eq "部分通过" }).Count
$failed = ($results | Where-Object { $_.Status -eq "失败" }).Count
$notInstalled = ($results | Where-Object { $_.Status -eq "未安装" }).Count

Write-Host "统计:" -ForegroundColor Yellow
Write-Host "  通过: $passed | 部分通过: $partial | 失败: $failed | 未安装: $notInstalled" -ForegroundColor Cyan
Write-Host ""

if ($failed -gt 0) {
    Write-Host "⚠️  有 $failed 个发行版测试失败，请查看详细日志" -ForegroundColor Yellow
}

if ($notInstalled -gt 0) {
    Write-Host "⚠️  有 $notInstalled 个发行版未安装，请先安装" -ForegroundColor Yellow
}

Write-Host "下一步:" -ForegroundColor Green
Write-Host "  1. 查看详细日志: Get-Content '$summaryLog'" -ForegroundColor Cyan
Write-Host "  2. 实际运行测试（会修改系统）: 去掉脚本中的 --dry-run 参数" -ForegroundColor Cyan
Write-Host "  3. 生成修复补丁: 根据日志中的错误，修改 security_hardening.sh" -ForegroundColor Cyan
