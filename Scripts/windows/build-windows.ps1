<#
.SYNOPSIS
    构建 EnvBox for Windows（GUI 可执行文件 + CLI/MCP 可执行文件）。

.DESCRIPTION
    与 Scripts/macos/build-app.sh 对齐：校验 VERSION、从 git 取构建号、把版本信息注入二进制。
    与 macOS 侧的差异：
      * 版本通过 -ldflags -X 注入 internal/core/buildinfo（GUI、CLI、文件属性三处一致）
      * Windows 文件属性（资源版本信息、图标、UAC/DPI 清单）由 wails3 generate syso 嵌入，
        版本号来自渲染后的临时副本，仓库里的 build/windows/info.json 模板不被改写
      * GUI 用 -H windowsgui（不弹控制台）；CLI 不加该参数（MCP 走 stdio，必须保留控制台接口）

.PARAMETER Arch
    只发 x64，这里固定 amd64。纯 Go 编译，CGO_ENABLED=0，不需要 mingw。
    要恢复 arm64：放宽本文件的 ValidateSet、在 installer/windows/envbox.iss 加回
    ArchitecturesAllowed 分支、CI 加回矩阵项。

.PARAMETER Configuration
    production 会 strip 符号并注入 Channel=production；dev 保留调试符号。

.PARAMETER SignThumbprint
    证书指纹（当前用户证书存储）。也可用环境变量 ENVBOX_SIGN_THUMBPRINT。

.PARAMETER SignPfx
    PFX 路径（CI 用）。也可用 ENVBOX_SIGN_PFX / ENVBOX_SIGN_PFX_PASSWORD。

.EXAMPLE
    ./Scripts/windows/build-windows.ps1

.EXAMPLE
    ./Scripts/windows/build-windows.ps1 -SignThumbprint 3A1B...C9 -SignerThumbprint 3A1B...C9
#>
[CmdletBinding()]
param(
    [ValidateSet('amd64')] [string] $Arch = 'amd64',
    [ValidateSet('production', 'dev')] [string] $Configuration = 'production',
    [string] $Version,
    [string] $BuildNumber,
    [string] $SignThumbprint = $env:ENVBOX_SIGN_THUMBPRINT,
    [string] $SignPfx = $env:ENVBOX_SIGN_PFX,
    [string] $SignPfxPassword = $env:ENVBOX_SIGN_PFX_PASSWORD,
    # 编译期嵌入的签名证书指纹，自更新时用它校验下载到的安装包（空表示未签名构建，自更新只允许跳转下载）
    [string] $SignerThumbprint = $env:ENVBOX_SIGNER_THUMBPRINT,
    [string] $UpdateRepo = 'Ohhu/EnvBox',
    [string] $TimestampUrl = 'http://timestamp.digicert.com',
    [switch] $SkipSign
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

if (-not $Version) { $Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim() }
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "VERSION 必须是稳定的语义版本（例如 1.0.0），当前为：$Version"
}
if (-not $BuildNumber) {
    $BuildNumber = (git -C $Root rev-list --count HEAD 2>$null)
    if (-not $BuildNumber) { $BuildNumber = '1' }
}
if ($BuildNumber -notmatch '^[0-9]+$') {
    throw "BUILD_NUMBER 必须是数字，当前为：$BuildNumber"
}

$DistDir = Join-Path $Root 'dist'
$BuildDir = Join-Path $Root '.build'
$GuiExe = Join-Path $DistDir "EnvBox-$Version-Windows-$Arch.exe"
$CliExe = Join-Path $DistDir "envbox-$Arch.exe"
$InfoTemplate = Join-Path $Root 'build/windows/info.json'
$Manifest = Join-Path $Root 'build/windows/app.manifest'
$Icon = Join-Path $Root 'build/windows/icon.ico'
$Syso = Join-Path $Root "cmd/windows/envbox/wails_windows_$Arch.syso"
$BuildInfoPackage = 'github.com/Ohhu/EnvBox/internal/core/buildinfo'

. (Join-Path $PSScriptRoot 'sign.ps1')

# Windows 资源版本必须是四段式，第四段来自提交计数。
$FourPartVersion = "$Version.$BuildNumber"
$Commit = (git -C $Root rev-parse --short HEAD 2>$null)
if (-not $Commit) { $Commit = 'unknown' }
$BuildDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

function Write-Step([string] $Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Tool([string] $Name, [string] $Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "缺少 $Name。$Hint" }
}

function Set-FileVersionStrings {
    param($Node, [string] $Replacement)

    if ($null -eq $Node) { return $null }
    if ($Node -is [string]) {
        if ($Node -match '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$') { return $Replacement }
        return $Node
    }
    if ($Node -is [System.Collections.IDictionary]) {
        $map = [ordered]@{}
        foreach ($k in $Node.Keys) { $map[$k] = Set-FileVersionStrings -Node $Node[$k] -Replacement $Replacement }
        return [pscustomobject]$map
    }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        return @($Node | ForEach-Object { Set-FileVersionStrings -Node $_ -Replacement $Replacement })
    }
    if ($Node -is [pscustomobject]) {
        $map = [ordered]@{}
        foreach ($p in $Node.PSObject.Properties) {
            $map[$p.Name] = Set-FileVersionStrings -Node $p.Value -Replacement $Replacement
        }
        return [pscustomobject]$map
    }
    return $Node
}

# --- 工具链 ---------------------------------------------------------------

Write-Step "EnvBox $Version ($BuildNumber) / $Arch / $Configuration"
Write-Step "Commit $Commit，构建时间 $BuildDate"

Assert-Tool 'go' '安装 Go 1.26+：winget install GoLang.Go'
if (-not (Get-Command 'wails3' -ErrorAction SilentlyContinue)) {
    throw '缺少 wails3。安装：go install github.com/wailsapp/wails/v3/cmd/wails3@v3.0.0（并把 Go 的 bin 目录加入 PATH）'
}
foreach ($required in @($InfoTemplate, $Manifest, $Icon)) {
    if (-not (Test-Path $required)) { throw "缺少 Wails 项目资源：$required（先执行 wails3 init）" }
}

Write-Step ('go ' + ((go version) -replace '^go version ', ''))

New-Item -ItemType Directory -Force -Path $DistDir, $BuildDir | Out-Null

# 前端是 shared/ui/assets 下的手写静态资源，随仓库提交，没有构建步骤。


# --- 渲染 Windows 资源信息并生成 .syso -----------------------------------

Write-Step "渲染 Windows 资源版本 $FourPartVersion"
$infoJson = Get-Content -Raw -Path $InfoTemplate | ConvertFrom-Json
$renderedInfo = Set-FileVersionStrings -Node $infoJson -Replacement $FourPartVersion
$InfoPath = Join-Path $BuildDir "windows-info-$Arch.json"
# WriteAllText with a BOM-less encoder: PowerShell 5.1's -Encoding utf8 writes a BOM,
# and the JSON parser in the syso generator rejects it.
[System.IO.File]::WriteAllText($InfoPath, ($renderedInfo | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))

Write-Step '生成 Windows 资源（图标 / 清单 / 版本信息）'
Remove-Item -Force $Syso -ErrorAction SilentlyContinue
& wails3 generate syso -arch $Arch -icon $Icon -manifest $Manifest -info $InfoPath -out $Syso
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Syso)) {
    throw "wails3 generate syso 失败（exit $LASTEXITCODE）"
}

# --- 编译 ----------------------------------------------------------------

$SignerForEmbed = ($SignerThumbprint -replace '\s', '').ToUpperInvariant()
if ($SignerForEmbed) {
    Write-Step "嵌入签名指纹用于自更新校验：$SignerForEmbed"
} else {
    Write-Warning '未提供签名证书指纹（ENVBOX_SIGNER_THUMBPRINT），自更新将只能跳转下载，不能自动安装。'
}

$VersionLdflags = @(
    "-X $BuildInfoPackage.Version=$Version",
    "-X $BuildInfoPackage.Commit=$Commit",
    "-X $BuildInfoPackage.BuildDate=$BuildDate",
    "-X $BuildInfoPackage.BuildNumber=$BuildNumber",
    "-X $BuildInfoPackage.Channel=$Configuration",
    "-X $BuildInfoPackage.UpdateRepo=$UpdateRepo",
    "-X $BuildInfoPackage.SignerThumbprint=$SignerForEmbed"
)
$CommonFlags = @('-trimpath', '-buildvcs=false')
if ($Configuration -eq 'production') {
    # Wails 自己的源码用 //go:build production 选择内嵌资源与运行时
    # （pkg/application/application_production.go）；缺这个 tag 会退化成连 dev server 的构建。
    $CommonFlags += @('-tags', 'production')
}
$env:GOOS = 'windows'
$env:GOARCH = $Arch
$env:GOFLAGS = ''

Write-Step "编译 GUI → dist/$(Split-Path -Leaf $GuiExe)"
# Production strips symbols; dev keeps them so stack traces stay readable.
$stripFlags = @('-s', '-w')
if ($Configuration -eq 'dev') { $stripFlags = @() }
$guiLdflags = ((@('-H windowsgui') + $stripFlags + @('-buildid=') + $VersionLdflags) -join ' ')
& go build @CommonFlags -ldflags $guiLdflags -o $GuiExe ./cmd/windows/envbox
if ($LASTEXITCODE -ne 0) { throw "GUI 编译失败（exit $LASTEXITCODE）" }

Write-Step "编译 CLI / MCP → dist/$(Split-Path -Leaf $CliExe)"
$cliLdflags = (($stripFlags + @('-buildid=') + $VersionLdflags) -join ' ')
& go build @CommonFlags -ldflags $cliLdflags -o $CliExe ./cmd/windows/envbox-cli
if ($LASTEXITCODE -ne 0) { throw "CLI 编译失败（exit $LASTEXITCODE）" }

Remove-Item -Force $Syso -ErrorAction SilentlyContinue

# --- 签名 ----------------------------------------------------------------

$wantsSign = (-not $SkipSign) -and ($SignPfx -or $SignThumbprint)
if ($wantsSign) {
    Invoke-CodeSign -Path $GuiExe -Pfx $SignPfx -PfxPassword $SignPfxPassword -Thumbprint $SignThumbprint -TimestampUrl $TimestampUrl
    Invoke-CodeSign -Path $CliExe -Pfx $SignPfx -PfxPassword $SignPfxPassword -Thumbprint $SignThumbprint -TimestampUrl $TimestampUrl
} else {
    Write-Warning '未提供签名凭据，产物未签名（首次运行会有 SmartScreen 提示）。'
}

# --- 构建信息 ------------------------------------------------------------

$buildInfo = @(
    "product=EnvBox"
    "version=$Version"
    "build_number=$BuildNumber"
    "resource_version=$FourPartVersion"
    "arch=$Arch"
    "configuration=$Configuration"
    "commit=$Commit"
    "built_at=$BuildDate"
    "go=$((go version) -replace '^go version ', '')"
) -join [Environment]::NewLine
Set-Content -Path (Join-Path $DistDir "BUILD-INFO-$Arch.txt") -Value $buildInfo -Encoding utf8

Write-Step '完成'
Get-ChildItem $DistDir | Where-Object { $_.Name -like "*$Arch*" } | ForEach-Object {
    Write-Host ('{0,-46} {1,7:N2} MB' -f $_.Name, ($_.Length / 1MB))
}
