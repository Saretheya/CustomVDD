# ============================================================
#  CustomVDD 驱动打包脚本
#
#  作用：生成 CAT 目录文件并用代码签名证书签名，产出可安装的驱动包。
#
#  前置：
#    1. 已运行 tools\build.ps1 生成 driver\x64\Release\CustomVDD.dll
#    2. 已准备代码签名证书，并记下其指纹（Thumbprint）
#
#  用法：
#      powershell -ExecutionPolicy Bypass -File tools\repack.ps1 -CertThumbprint <指纹>
#
#  产物：package\ 下的 CustomVDD.inf / .dll / .cat / .cer
# ============================================================
[CmdletBinding()]
param(
    # 代码签名证书指纹（放在 CurrentUser\My 中，且含私钥）
    [Parameter(Mandatory = $true)]
    [string] $CertThumbprint,

    # Windows Kits 版本目录名（用于定位 inf2cat / signtool）
    [string] $KitsVersion = '10.0.22621.0'
)

$ErrorActionPreference = 'Continue'

$Root  = Split-Path -Parent $PSScriptRoot
$Log   = Join-Path $PSScriptRoot 'repack.log'
$Pkg   = Join-Path $Root 'package'
$Stage = Join-Path $Root 'stage'
$OutDll = Join-Path $Root 'driver\x64\Release\CustomVDD.dll'
$InfSrc = Join-Path $Root 'driver\CustomVDD.inf'

function L($m) { $m | Tee-Object -FilePath $Log -Append }

"" | Out-File -Encoding Default $Log
"=== repack $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -Encoding Default $Log

# ---- 定位工具 ----
$kitsBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin\$KitsVersion"
$inf2cat  = Join-Path $kitsBin 'x86\Inf2Cat.exe'
$signtool = Join-Path $kitsBin 'x64\signtool.exe'

foreach ($t in @($inf2cat, $signtool)) {
    if (-not (Test-Path $t)) { L "ERROR: 找不到 $t"; exit 1 }
}

if (-not (Test-Path $OutDll)) { L "ERROR: 找不到已构建的 DLL: $OutDll（请先运行 tools\build.ps1）"; exit 1 }
if (-not (Test-Path $InfSrc)) { L "ERROR: 找不到 INF: $InfSrc"; exit 1 }

New-Item -ItemType Directory -Force -Path $Pkg | Out-Null

# ---- 1. 暂存 ----
L '[1/6] 暂存构建产物...'
Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item $OutDll $Stage -Force
Copy-Item $InfSrc (Join-Path $Stage 'CustomVDD.inf') -Force
L "  staged: $((Get-ChildItem $Stage).Name -join ', ')"

# ---- 2. 生成 CAT ----
L '[2/6] 生成 CAT...'
& $inf2cat /driver:"$Stage" /os:10_X64,10_VB_X64,10_NI_X64 2>&1 |
    Out-File -Encoding Default $Log -Append
$cat = Join-Path $Stage 'CustomVDD.cat'
if (-not (Test-Path $cat)) { L '  ERROR: CAT 未生成'; exit 1 }
L "  CAT: $((Get-Item $cat).Length) bytes"

# ---- 3. 签名 CAT ----
L '[3/6] 签名 CAT...'
& $signtool sign /v /fd SHA256 /sha1 $CertThumbprint $cat 2>&1 |
    Out-File -Encoding Default $Log -Append
if ($LASTEXITCODE -ne 0) { L "  ERROR: 签名失败 (exit=$LASTEXITCODE)"; exit 1 }

# ---- 4. 导出证书公钥 ----
L '[4/6] 导出证书公钥...'
$cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Thumbprint -eq $CertThumbprint } |
        Select-Object -First 1
if (-not $cert) { L '  ERROR: 证书未找到'; exit 1 }
$cerOut = Join-Path $Pkg 'CustomVDD.cer'
[System.IO.File]::WriteAllBytes($cerOut,
    $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
L "  $cerOut ($((Get-Item $cerOut).Length) bytes)"

# ---- 5. 输出到 package ----
L '[5/6] 更新 package...'
Copy-Item (Join-Path $Stage 'CustomVDD.inf') $Pkg -Force
Copy-Item $cat $Pkg -Force
Copy-Item $OutDll $Pkg -Force
Get-ChildItem $Pkg | ForEach-Object { L "  $($_.Name)  $($_.Length) bytes" }

# ---- 6. 核验 ----
L '[6/6] 核验...'
L "  证书 Subject: $($cert.Subject)"
L "  证书有效期至: $($cert.NotAfter)"
L '=== repack done ==='
