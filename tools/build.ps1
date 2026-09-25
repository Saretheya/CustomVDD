# ============================================================
#  CustomVDD 驱动构建脚本
#
#  依赖：Visual Studio 2022（含 C++ 桌面开发）+ Windows SDK + WDK
#
#  用法：
#      powershell -ExecutionPolicy Bypass -File tools\build.ps1
#
#  产物：driver\x64\Release\CustomVDD.dll
# ============================================================
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot          # 仓库根目录
$Log  = Join-Path $PSScriptRoot 'build.log'
function L($m) { $m | Tee-Object -FilePath $Log -Append }

"" | Out-File -Encoding Default $Log
"=== build $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -Encoding Default $Log

# ---- 定位 MSBuild ----
$msbuild = $null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
    if ($vsPath) {
        $cand = Join-Path $vsPath 'MSBuild\Current\Bin\MSBuild.exe'
        if (Test-Path $cand) { $msbuild = $cand }
    }
}
if (-not $msbuild) {
    foreach ($p in @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    )) {
        if (Test-Path $p) { $msbuild = $p; break }
    }
}
if (-not $msbuild) { L 'ERROR: 找不到 MSBuild.exe，请先安装 Visual Studio 2022'; exit 1 }
L "MSBuild: $msbuild"

$proj = Join-Path $Root 'driver\CustomVDD.vcxproj'
if (-not (Test-Path $proj)) { L "ERROR: 找不到 $proj"; exit 1 }

L '构建驱动（Release x64）...'
& $msbuild $proj /p:Configuration=Release /p:Platform=x64 `
    /p:Driver_SpectreMitigation=false /v:minimal /nologo 2>&1 |
    Where-Object { $_ -match 'error|\.dll|Successfully signed' } |
    ForEach-Object { L "  $_" }

$dll = Join-Path $Root 'driver\x64\Release\CustomVDD.dll'
if (Test-Path $dll) {
    L "OK: $dll ($((Get-Item $dll).Length) bytes)"
} else {
    L '驱动 DLL 未生成，请检查上方错误。'
}
L '=== done ==='
