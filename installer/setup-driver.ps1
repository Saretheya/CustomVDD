# ============================================================
#  CustomVDD 驱动安装/卸载核心逻辑
#
#  完全自包含：仅依赖 Windows 自带组件（SetupAPI / CfgMgr32 / pnputil / certutil）
#  不依赖任何第三方工具（如 nefconw / devcon）
#
#  用法：
#    powershell -File setup-driver.ps1 -Mode install
#    powershell -File setup-driver.ps1 -Mode uninstall
#    powershell -File setup-driver.ps1 -Mode check     # 已安装返回 2
#    powershell -File setup-driver.ps1 -Mode verify
#
#  退出码：0=成功  2=已安装  1=失败
# ============================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('install', 'uninstall', 'check', 'verify')]
    [string] $Mode,

    [string] $PackageDir,
    [switch] $Force
)

$ErrorActionPreference = 'Continue'

# ---------------- 常量 ----------------
$HWID        = 'Root\CustomVDD'
$CLASS_GUID  = '4d36e968-e325-11ce-bfc1-08002be10318'
$DEVICE_NAME = 'Custom Display Adapter'
$MONITOR_HW  = 'CVD0001'

# ---------------- 路径 ----------------
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $PackageDir) { $PackageDir = Join-Path $ScriptDir 'package' }

$Inf = Join-Path $PackageDir 'CustomVDD.inf'
$Cer = Join-Path $PackageDir 'CustomVDD.cer'

$LogDir = Join-Path $env:ProgramData 'CustomVDD'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$Log = Join-Path $LogDir 'setup.log'

function L($m) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [$Mode]  $m"
    try { $line | Out-File -Append -Encoding UTF8 $Log } catch { }
    Write-Host $m
}
function Fail($m) { L "ERROR: $m"; exit 1 }

function Get-CertThumbprint([string] $cerPath) {
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath)
        return $cert.Thumbprint
    } catch { return $null }
}

# ---------------- P/Invoke 定义 ----------------
if (-not ('CustomVDDNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class CustomVDDNative
{
    // 常量
    public const uint DIGCF_PRESENT              = 0x00000002;
    public const uint DIGCF_ALLCLASSES           = 0x00000004;
    public const uint DICD_GENERATE_ID           = 0x00000001;
    public const uint SPDRP_HARDWAREID           = 0x00000001;
    public const uint SPDRP_DEVICEDESC           = 0x00000000;
    public const uint DIF_REGISTERDEVICE         = 0x00000019;
    public const uint DIF_REMOVE                 = 0x00000005;
    public const uint INSTALLFLAG_FORCE          = 0x00000001;
    public const uint INSTALLFLAG_NONINTERACTIVE = 0x00000004;

    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DEVINFO_DATA
    {
        public uint cbSize;
        public Guid ClassGuid;
        public uint DevInst;
        public IntPtr Reserved;
    }

    // ---------- SetupAPI ----------
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SetupDiCreateDeviceInfoList(ref Guid ClassGuid, IntPtr hwndParent);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiCreateDeviceInfo(
        IntPtr DeviceInfoSet, string DeviceName, ref Guid ClassGuid,
        string DeviceDescription, IntPtr hwndParent, uint CreationFlags,
        ref SP_DEVINFO_DATA DeviceInfoData);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiSetDeviceRegistryProperty(
        IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData,
        uint Property, byte[] PropertyBuffer, uint PropertyBufferSize);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiCallClassInstaller(
        uint InstallFunction, IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SetupDiGetClassDevs(
        ref Guid ClassGuid, IntPtr Enumerator, IntPtr hwndParent, uint Flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiEnumDeviceInfo(
        IntPtr DeviceInfoSet, uint MemberIndex, ref SP_DEVINFO_DATA DeviceInfoData);

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetupDiGetDeviceInstanceId(
        IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData,
        StringBuilder DeviceInstanceId, uint DeviceInstanceIdSize, out uint RequiredSize);

    // ---------- NewDev ----------
    [DllImport("newdev.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool UpdateDriverForPlugAndPlayDevicesW(
        IntPtr hwndParent, string HardwareId, string FullInfPath,
        uint InstallFlags, out bool bRebootRequired);
}
'@ -ErrorAction Stop
}

# ---------------- 设备查询 ----------------

function Get-CustomVddDevices {
    <# 枚举当前存在的 Custom Display Adapter 设备 #>
    $list = @()
    $guid = [Guid] $CLASS_GUID
    $h = [CustomVDDNative]::SetupDiGetClassDevs([ref]$guid, [IntPtr]::Zero, [IntPtr]::Zero,
                                                [CustomVDDNative]::DIGCF_PRESENT)
    if ($h -eq [IntPtr]::new(-1)) { return @() }
    try {
        $i = 0
        while ($true) {
            $data = New-Object 'CustomVDDNative+SP_DEVINFO_DATA'
            $data.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($data)
            if (-not [CustomVDDNative]::SetupDiEnumDeviceInfo($h, [uint32]$i, [ref]$data)) { break }

            $sb = New-Object System.Text.StringBuilder 512
            $need = [uint32]0
            $ok = [CustomVDDNative]::SetupDiGetDeviceInstanceId($h, [ref]$data, $sb, [uint32]512, [ref]$need)
            if ($ok) {
                $instanceId = $sb.ToString()
                $dev = Get-PnpDevice -InstanceId $instanceId -ErrorAction SilentlyContinue
                if ($dev -and $dev.FriendlyName -eq $DEVICE_NAME) {
                    $list += [pscustomobject]@{
                        InstanceId = $instanceId
                        Status     = $dev.Status
                        Present    = $dev.Present
                    }
                }
            }
            $i++
        }
    } finally {
        $null = [CustomVDDNative]::SetupDiDestroyDeviceInfoList($h)
    }
    return $list
}

function Get-StagedPackageNames {
    <# 返回 customvdd.inf 已暂存对应的 oemXX.inf 名称

       重要：pnputil /enum-drivers 的输出是**本地化**的（中文系统显示
       "发布名称/原始名称"），所以不能依赖 "Published Name:" 这类英文标签。
       这里改为按空行分块，只要块内含 customvdd.inf 就提取其中的 oemNN.inf。 #>
    $names = @()
    $out = & pnputil /enum-drivers 2>&1 | Out-String

    # 按连续空行分块，每块对应一个驱动包
    $blocks = $out -split "(?:\r?\n\s*){2,}"
    foreach ($b in $blocks) {
        if ($b -match '(?i)customvdd\.inf') {
            $m = [regex]::Match($b, '(?i)\b(oem\d+\.inf)\b')
            if ($m.Success) { $names += $m.Groups[1].Value }
        }
    }

    # 兜底：若分块失败但确实存在 customvdd.inf，则取所有 oemNN.inf
    if ($names.Count -eq 0 -and $out -match '(?i)customvdd\.inf') {
        foreach ($m in [regex]::Matches($out, '(?i)\b(oem\d+\.inf)\b')) {
            $names += $m.Groups[1].Value
        }
    }

    return ($names | Sort-Object -Unique)
}

function Test-CustomVddInstalled {
    if (@(Get-CustomVddDevices).Count -gt 0) { return $true }
    if (@(Get-StagedPackageNames).Count -gt 0) { return $true }
    return $false
}

# ---------------- 操作 ----------------

function Install-Certificates {
    L '导入证书'
    & certutil -addstore -f Root $Cer             2>&1 | Out-Null
    & certutil -addstore -f TrustedPublisher $Cer 2>&1 | Out-Null
    L '  证书已导入 Root + TrustedPublisher'
}

function New-CustomVddDevice {
    <# 创建 root 枚举设备节点（不依赖第三方工具）

       要点（实测验证）：
         · SetupDiCreateDeviceInfo 的 DeviceName 参数**不能为 NULL**，
           必须传设备名（这里用 'CustomVDD'），否则返回 0xE0000205。
         · 硬件 ID 用 REG_MULTI_SZ 格式（双 NUL 结尾）。
         · 注册用 DIF_REGISTERDEVICE，随后由 UpdateDriver 绑定驱动。 #>
    L '创建设备节点'
    $guid = [Guid] $CLASS_GUID
    $h = [CustomVDDNative]::SetupDiCreateDeviceInfoList([ref]$guid, [IntPtr]::Zero)
    if ($h -eq [IntPtr]::new(-1) -or $h -eq [IntPtr]::Zero) {
        L "  SetupDiCreateDeviceInfoList 失败: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        return $false
    }
    try {
        $data = New-Object 'CustomVDDNative+SP_DEVINFO_DATA'
        $data.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($data)

        # DeviceName 必须非空（传 NULL 会得到 0xE0000205）
        $ok = [CustomVDDNative]::SetupDiCreateDeviceInfo(
            $h, 'CustomVDD', [ref]$guid, $DEVICE_NAME, [IntPtr]::Zero,
            [CustomVDDNative]::DICD_GENERATE_ID, [ref]$data)
        if (-not $ok) {
            L "  SetupDiCreateDeviceInfo 失败: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            return $false
        }

        # 设置硬件 ID：REG_MULTI_SZ，双 NUL 结尾
        $hwidBytes = [System.Text.Encoding]::Unicode.GetBytes("$HWID`0`0")
        $ok = [CustomVDDNative]::SetupDiSetDeviceRegistryProperty(
            $h, [ref]$data, [CustomVDDNative]::SPDRP_HARDWAREID,
            $hwidBytes, [uint32]$hwidBytes.Length)
        if (-not $ok) {
            L "  SetupDiSetDeviceRegistryProperty 失败: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            return $false
        }

        # 注册设备
        $ok = [CustomVDDNative]::SetupDiCallClassInstaller(
            [CustomVDDNative]::DIF_REGISTERDEVICE, $h, [ref]$data)
        if (-not $ok) {
            L "  DIF_REGISTERDEVICE 失败: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
            return $false
        }

        L '  设备节点已创建'
        return $true
    } finally {
        $null = [CustomVDDNative]::SetupDiDestroyDeviceInfoList($h)
    }
}

function Install-CustomVddDriver {
    <# 用 UpdateDriverForPlugAndPlayDevices 绑定驱动 #>
    L '绑定驱动'
    $reboot = $false
    $flags = [CustomVDDNative]::INSTALLFLAG_FORCE -bor [CustomVDDNative]::INSTALLFLAG_NONINTERACTIVE
    $ok = [CustomVDDNative]::UpdateDriverForPlugAndPlayDevicesW(
        [IntPtr]::Zero, $HWID, (Resolve-Path $Inf).Path, $flags, [ref]$reboot)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    L "  UpdateDriverForPlugAndPlayDevices => $ok (reboot=$reboot, err=$err)"
    return $ok
}

function Remove-CustomVddDevices {
    $devs = @(Get-CustomVddDevices)
    if ($devs.Count -eq 0) { L '  无设备实例'; return }
    foreach ($d in $devs) {
        L "  移除设备: $($d.InstanceId)"
        & pnputil /remove-device $d.InstanceId 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 2
}

function Remove-CustomVddPhantomMonitors {
    <# 清理 CustomVDD 遗留的幽灵监视器实例

       背景：监视器实例记录在 Enum\DISPLAY\<HWID> 下。适配器设备被移除后，
             这些记录不会自动消失，而会变成父设备为 HTREE\ROOT\0 的
             Disconnected 幽灵设备。长期累积会使 \\.\DISPLAYnn 编号膨胀。

       做法：枚举该硬件 ID 下的全部实例，删除其中非 Present 的。
             活跃实例一律保留。 #>
    $enumRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY'
    $removed = 0

    foreach ($hwid in @($MONITOR_HW)) {
        $key = Join-Path $enumRoot $hwid
        if (-not (Test-Path $key)) { continue }

        $instances = @(Get-ChildItem $key -ErrorAction SilentlyContinue |
                       ForEach-Object { "DISPLAY\$hwid\$($_.PSChildName)" })

        foreach ($inst in $instances) {
            $dev = Get-PnpDevice -InstanceId $inst -ErrorAction SilentlyContinue
            if ($dev -and $dev.Present) { continue }   # 活跃实例保留

            & pnputil /remove-device "$inst" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                L "  移除幽灵监视器: $inst"
                $removed++
            }
        }
    }

    if ($removed -eq 0) { L '  无幽灵监视器需要清理' }
    else { L "  共清理幽灵监视器 $removed 个" }
}

function Remove-CustomVddPackages {
    $names = @(Get-StagedPackageNames)
    if ($names.Count -eq 0) { L '  无驱动包'; return }
    foreach ($n in $names) {
        L "  删除驱动包: $n"
        & pnputil /delete-driver $n /uninstall /force 2>&1 | Out-Null
    }
}

function Remove-CustomVddCertificates {
    $tp = Get-CertThumbprint $Cer
    if (-not $tp) { L '  无法读取证书指纹，跳过'; return }
    L "  移除证书 $tp"
    & certutil -delstore Root $tp             2>&1 | Out-Null
    & certutil -delstore TrustedPublisher $tp 2>&1 | Out-Null
}

# ---------------- 主流程 ----------------

"" | Out-File -Append -Encoding UTF8 $Log
L "=== CustomVDD $Mode ==="

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

switch ($Mode) {

    'check' {
        if (Test-CustomVddInstalled) {
            L '已安装'
            exit 2
        }
        L '未安装'
        exit 0
    }

    'verify' {
        $devs = @(Get-CustomVddDevices)
        L "设备数: $($devs.Count)"
        foreach ($d in $devs) { L "  $($d.InstanceId) [$($d.Status)]" }
        $mon = Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue |
               Where-Object { $_.InstanceId -match $MONITOR_HW -and $_.Present }
        if ($mon) { L "显示器: $($mon.InstanceId) [$($mon.Status)]" }
        if ($devs.Count -gt 0 -and $mon) { exit 0 } else { exit 1 }
    }

    'install' {
        if (-not $isAdmin) { Fail '需要管理员权限' }
        foreach ($p in @($Inf, $Cer)) {
            if (-not (Test-Path $p)) { Fail "缺少文件: $p" }
        }

        if ((Test-CustomVddInstalled) -and -not $Force) {
            L '检测到已安装'
            exit 2
        }

        Install-Certificates

        if (Test-CustomVddInstalled) {
            L '清理既有安装'
            Remove-CustomVddDevices
            Remove-CustomVddPackages
            Start-Sleep -Seconds 2
        }

        # 暂存驱动包（复制到 DriverStore）
        L '暂存驱动包'
        & pnputil /add-driver $Inf 2>&1 | ForEach-Object { L "  $_" }
        if ($LASTEXITCODE -notin @(0, 3010)) { Fail "pnputil 暂存失败 (exit=$LASTEXITCODE)" }

        # 创建设备节点
        if (-not (New-CustomVddDevice)) {
            Fail '创建设备节点失败'
        }
        Start-Sleep -Seconds 1

        # 绑定驱动
        if (-not (Install-CustomVddDriver)) {
            Fail '驱动绑定失败'
        }
        Start-Sleep -Seconds 3

        # 验证
        $devs = @(Get-CustomVddDevices)
        if ($devs.Count -eq 0) { Fail '安装后未检测到设备' }
        foreach ($d in $devs) { L "  设备: $($d.InstanceId) [$($d.Status)]" }

        $mon = Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue |
               Where-Object { $_.InstanceId -match $MONITOR_HW -and $_.Present }
        if ($mon) { L "  显示器: $($mon.InstanceId)" }

        L '=== 安装完成 ==='
        exit 0
    }

    'uninstall' {
        if (-not $isAdmin) { Fail '需要管理员权限' }
        L '开始卸载'

        # 1. 移除适配器设备（此后其监视器变为 Disconnected）
        Remove-CustomVddDevices

        # 2. 清理随之产生的幽灵监视器实例
        #    顺序关键：必须在移除适配器之后执行，否则监视器仍是 Present。
        L '清理幽灵监视器实例'
        Remove-CustomVddPhantomMonitors

        # 3. 删除驱动包
        Remove-CustomVddPackages

        # 4. 移除证书
        Remove-CustomVddCertificates

        L '=== 卸载完成 ==='
        exit 0
    }
}
