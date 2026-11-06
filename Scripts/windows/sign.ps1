# Shared Authenticode helper. Dot-source from build/package scripts:
#   . (Join-Path $PSScriptRoot 'sign.ps1')

function Find-SignTool {
    $onPath = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    if (-not $programFilesX86) { return $null }
    $kits = Join-Path $programFilesX86 'Windows Kits\10\bin'
    if (-not (Test-Path $kits)) { return $null }
    $found = Get-ChildItem -Path $kits -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Invoke-CodeSign {
    param(
        [Parameter(Mandatory)][string] $Path,
        [string] $Pfx,
        [string] $PfxPassword,
        [string] $Thumbprint,
        [string] $TimestampUrl = 'http://timestamp.digicert.com'
    )
    $signTool = Find-SignTool
    if (-not $signTool) { throw '找不到 signtool.exe；请安装 Windows SDK，或用 -SkipSign' }
    if ($Pfx) {
        & $signTool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /f $Pfx /p $PfxPassword $Path
    } else {
        & $signTool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /sha1 $Thumbprint $Path
    }
    if ($LASTEXITCODE -ne 0) { throw "签名失败：$Path（exit $LASTEXITCODE）" }
    & $signTool verify /pa /all $Path
    if ($LASTEXITCODE -ne 0) { throw "签名校验失败：$Path（exit $LASTEXITCODE）" }
    Write-Host "==> 已签名 $(Split-Path -Leaf $Path)"
}
