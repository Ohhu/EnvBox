<#
.SYNOPSIS
    打包 EnvBox for Windows 的发布产物：安装器 + 校验文件。

.DESCRIPTION
    输入是 Scripts/build-windows.ps1 生成的 dist/：
        EnvBox-<version>-Windows-amd64.exe   GUI
        envbox-amd64.exe                     CLI / MCP
    输出：
        EnvBox-<version>-Windows-amd64-Setup.exe   唯一的正式分发形态（每用户安装）
        SHA256SUMS-windows-amd64.txt               校验值（自更新会交叉核对）

    不做便携 zip：EnvBox 需要有固定路径供 MCP 客户端与开机启动引用，
    也需要卸载时清干净注册表残留，便携形态会在这两件事上制造孤儿项。

.PARAMETER SkipInstaller
    只给本地调试用：跳过 Inno 编译，直接对 dist 里已有的 Setup.exe 生成校验值。

.EXAMPLE
    ./Scripts/package-windows.ps1

.EXAMPLE
    ./Scripts/package-windows.ps1 -SignThumbprint 3A1B...C9
#>
[CmdletBinding()]
param(
    [ValidateSet('amd64')] [string] $Arch = 'amd64',
    [string] $Version,
    [string] $DistDir,
    [string] $SignThumbprint = $env:ENVBOX_SIGN_THUMBPRINT,
    [string] $SignPfx = $env:ENVBOX_SIGN_PFX,
    [string] $SignPfxPassword = $env:ENVBOX_SIGN_PFX_PASSWORD,
    [string] $TimestampUrl = 'http://timestamp.digicert.com',
    [switch] $SkipInstaller,
    [switch] $SkipSign
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'sign.ps1')
Set-Location $Root

if (-not $Version) { $Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim() }
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "VERSION 必须是稳定的语义版本（例如 1.0.0），当前为：$Version"
}
if (-not $DistDir) { $DistDir = Join-Path $Root 'dist' }
if (-not (Test-Path $DistDir)) { throw "找不到 dist 目录：$DistDir（先运行 Scripts/build-windows.ps1）" }

$GuiExe = Join-Path $DistDir "EnvBox-$Version-Windows-$Arch.exe"
$CliExe = Join-Path $DistDir "envbox-$Arch.exe"
foreach ($required in @($GuiExe, $CliExe)) {
    if (-not (Test-Path $required)) { throw "缺少产物：$required" }
}

$StagingDir = Join-Path $Root ".build/installer-$Arch"
$SetupPath = Join-Path $DistDir "EnvBox-$Version-Windows-$Arch-Setup.exe"
$SumPath = Join-Path $DistDir "SHA256SUMS-windows-$Arch.txt"

function Write-Step([string] $Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Find-InnoCompiler {
    $onPath = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $candidates = @(
        (Join-Path $localAppData 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path $programFilesX86 'Inno Setup 6\ISCC.exe'),
        (Join-Path $programFiles 'Inno Setup 6\ISCC.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

# --- 安装器输入目录 -------------------------------------------------------

Write-Step "准备安装器输入目录（$Arch）"
Remove-Item -Recurse -Force $StagingDir -ErrorAction SilentlyContinue
$BinDir = Join-Path $StagingDir 'bin'
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

# Windows 文件系统大小写不敏感：GUI 的 EnvBox.exe 与 CLI 的 envbox.exe 不能同目录共存，
# 因此 CLI 放进 bin\ 子目录，MCP 客户端配置指向 bin\envbox.exe。
Copy-Item $GuiExe (Join-Path $StagingDir 'EnvBox.exe')
Copy-Item $CliExe (Join-Path $BinDir 'envbox.exe')
foreach ($extra in @('LICENSE', 'CHANGELOG.md')) {
    $source = Join-Path $Root $extra
    if (Test-Path $source) { Copy-Item $source $StagingDir }
}

# --- 安装器 ---------------------------------------------------------------

if ($SkipInstaller) {
    Write-Warning '已跳过安装器编译（-SkipInstaller），仅对现有 Setup.exe 生成校验值。'
    if (-not (Test-Path $SetupPath)) { throw "dist 里没有可用的安装器：$SetupPath" }
} else {
    $iscc = Find-InnoCompiler
    if (-not $iscc) {
        throw '找不到 ISCC.exe。安装 Inno Setup 6：winget install JRSoftware.InnoSetup（CI 用 choco install innosetup）'
    }
    Write-Step "编译安装器（$(Split-Path -Leaf $SetupPath)）"
    Remove-Item -Force $SetupPath -ErrorAction SilentlyContinue
    $issPath = Join-Path $Root 'installer/windows/envbox.iss'
    if (-not (Test-Path $issPath)) { throw "缺少安装器脚本：$issPath" }
    $iconPath = Join-Path $Root 'build/windows/icon.ico'
    & $iscc "/DAppVersion=$Version" "/DAppArch=$Arch" "/DDistDir=$StagingDir" "/DOutDir=$DistDir" "/DIconPath=$iconPath" $issPath
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup 编译失败（exit $LASTEXITCODE）" }
    if (-not (Test-Path $SetupPath)) { throw "安装器未生成：$SetupPath" }
    # 顺序要求：先签 exe（build 阶段），再打进安装器，最后签安装器
    if ((-not $SkipSign) -and ($SignPfx -or $SignThumbprint)) { Invoke-CodeSign -Path $SetupPath -Pfx $SignPfx -PfxPassword $SignPfxPassword -Thumbprint $SignThumbprint -TimestampUrl $TimestampUrl }
}

# --- 校验值 ---------------------------------------------------------------

Write-Step "生成 $(Split-Path -Leaf $SumPath)"
$hash = (Get-FileHash -Algorithm SHA256 -Path $SetupPath).Hash.ToLowerInvariant()
$sumLine = $hash + '  ' + (Split-Path -Leaf $SetupPath) + [char]10
[System.IO.File]::WriteAllText($SumPath, $sumLine, (New-Object System.Text.UTF8Encoding($false)))

Write-Step '发布产物'
Get-ChildItem $DistDir | Sort-Object Name | ForEach-Object {
    Write-Host ('{0,-52} {1,7:N2} MB' -f $_.Name, ($_.Length / 1MB))
}
