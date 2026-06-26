# Docker 安装与配置脚本 for Windows (WSL2)
# 用法: 在 PowerShell (管理员) 中运行
#        Set-ExecutionPolicy Bypass -Scope Process -Force
#        .\install_docker_windows.ps1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "    Docker 自动化安装脚本 for Windows" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# 检查管理员权限
Write-Host "[1/6] 检查管理员权限..." -ForegroundColor Yellow
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "X 需要管理员权限！请右键 PowerShell 选择'以管理员身份运行'" -ForegroundColor Red
    exit 1
}
Write-Host "OK 管理员权限确认" -ForegroundColor Green

# 检查系统版本
Write-Host ""
Write-Host "[2/6] 检查系统版本..." -ForegroundColor Yellow
$os = Get-WmiObject -Class Win32_OperatingSystem
$version = [System.Version]$os.Version
$build = $os.BuildNumber

Write-Host "    系统: $($os.Caption)" -ForegroundColor Cyan
Write-Host "    版本: $($os.Version) (Build $build)" -ForegroundColor Cyan

if ($build -lt 19041) {
    Write-Host "X Windows 版本过低！需要 Windows 10 Build 19041+ 或 Windows 11" -ForegroundColor Red
    exit 1
}
Write-Host "OK 系统版本满足要求 (Build $build)" -ForegroundColor Green

# 安装 WSL2
Write-Host ""
Write-Host "[3/6] 安装 WSL2..." -ForegroundColor Yellow
try {
    wsl --install -d Ubuntu --no-launch 2>&1 | Out-Null
    Write-Host "OK WSL2 安装完成" -ForegroundColor Green
}
catch {
    Write-Host "WARN WSL2 可能已安装或安装失败，继续执行..." -ForegroundColor Yellow
}

# 设置 WSL2 为默认版本
$null = wsl --set-default-version 2 2>&1
Write-Host "OK WSL2 已设置为默认版本" -ForegroundColor Green

# 检查 Docker Desktop 是否已安装
Write-Host ""
Write-Host "[4/6] 检查 Docker Desktop..." -ForegroundColor Yellow
$dockerPath = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerPath) {
    Write-Host "OK Docker 已安装: $($dockerPath.Source)" -ForegroundColor Green
    docker --version
}
else {
    Write-Host "WARN Docker Desktop 未安装" -ForegroundColor Yellow
    Write-Host "    请手动下载并安装: https://www.docker.com/products/docker-desktop/" -ForegroundColor Cyan
    Write-Host "    或使用 winget 安装: winget install Docker.DockerDesktop" -ForegroundColor Cyan
    Write-Host ""
    $install = Read-Host "是否使用 winget 自动安装? (Y/n)"
    if ($install -ne "n" -and $install -ne "N") {
        Write-Host "    正在使用 winget 安装 Docker Desktop..." -ForegroundColor Cyan
        winget install Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
        Write-Host "OK Docker Desktop 安装完成，请重启电脑后继续" -ForegroundColor Green
        Write-Host "    重启后请运行此脚本继续配置" -ForegroundColor Yellow
        exit 0
    }
}

# 配置 Docker 镜像加速
Write-Host ""
Write-Host "[5/6] 配置 Docker 镜像加速..." -ForegroundColor Yellow

$daemonConfig = @{
    "registry-mirrors" = @(
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com"
    )
    "log-driver" = "json-file"
    "log-opts" = @{
        "max-size" = "100m"
    }
    "storage-driver" = "overlay2"
}

$configDir = "$env:USERPROFILE\.docker"
$configFile = "$configDir\daemon.json"

if (!(Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

$daemonConfig | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8
Write-Host "OK Docker 镜像加速配置已写入: $configFile" -ForegroundColor Green
Write-Host "    镜像源:" -ForegroundColor Cyan
foreach ($mirror in $daemonConfig["registry-mirrors"]) {
    Write-Host "      - $mirror" -ForegroundColor Cyan
}

# 启动 Docker Desktop (如果已安装)
Write-Host ""
Write-Host "[6/6] 启动 Docker Desktop..." -ForegroundColor Yellow
$dockerDesktop = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
if ($dockerDesktop) {
    Write-Host "OK Docker Desktop 已在运行" -ForegroundColor Green
}
else {
    $dockerExe = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExe) {
        Write-Host "    正在启动 Docker Desktop..." -ForegroundColor Cyan
        Start-Process $dockerExe
        Write-Host "OK Docker Desktop 正在启动，请等待约 1-2 分钟..." -ForegroundColor Green
    }
    else {
        Write-Host "WARN 未找到 Docker Desktop 可执行文件" -ForegroundColor Yellow
    }
}

# 等待 Docker 启动
Write-Host ""
Write-Host "等待 Docker 启动..." -ForegroundColor Yellow
$attempts = 0
$maxAttempts = 30
do {
    Start-Sleep -Seconds 2
    $attempts++
    try {
        $null = docker info 2>&1
        Write-Host "OK Docker 已成功启动！" -ForegroundColor Green
        break
    }
    catch {
        Write-Host "    等待中... ($attempts/$maxAttempts)" -ForegroundColor Gray
    }
} while ($attempts -lt $maxAttempts)

if ($attempts -ge $maxAttempts) {
    Write-Host "WARN Docker 启动超时，请手动检查 Docker Desktop" -ForegroundColor Yellow
}

# 验证安装
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  验证 Docker 安装" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

try {
    docker --version
    Write-Host ""
    docker-compose --version
    Write-Host ""
    Write-Host "镜像加速配置:" -ForegroundColor Cyan
    docker info 2>&1 | Select-String "Registry Mirrors" -Context 0, 5
}
catch {
    Write-Host "WARN 无法获取 Docker 信息，可能还在启动中" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  OK Docker 安装与配置完成！" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "下一步:" -ForegroundColor Yellow
Write-Host "  1. 如果这是首次安装，请重启电脑" -ForegroundColor Cyan
Write-Host "  2. 启动 Docker Desktop" -ForegroundColor Cyan
Write-Host "  3. 在项目目录运行: docker-compose up -d" -ForegroundColor Cyan
Write-Host "  4. 测试: docker run hello-world" -ForegroundColor Cyan
Write-Host ""
