# CustomVDD — Virtual Display Driver for Windows

A self-contained **virtual display driver** (Indirect Display Driver, IDD) for Windows,
derived from Microsoft's official `IddSampleDriver` sample (MS-PL licensed).

**English** · [中文说明](README.md)

---

## The Problem It Solves

When streaming software (Sunshine/Moonlight, NetEase UU Remote, RDP, etc.) runs on a
machine with **no physical monitor**, it typically **creates a temporary virtual display**
and destroys it on disconnect. This causes three classes of problems:

| Problem | Cause |
|---|---|
| **Garbled output / resolution jumps on disconnect** | Display topology changes every connect/disconnect cycle |
| **Host DWM freeze** (cursor moves but clicks do nothing, with a beep) | Desktop Window Manager stalls on GPU submission during topology changes |
| **Software fighting over displays** | Each streaming tool creates its own virtual display, conflicting with the others |

**CustomVDD's approach**: the virtual display is provided **persistently by a driver**,
**fully decoupled** from any streaming connection.

```
Streaming client (Sunshine / UU Remote / RDP)
        ↓  capture only
   Virtual display (provided by CustomVDD, always present)
        ↑  owned by the driver, independent of connections
    Graphics adapter
```

Result: disconnecting **does not** alter display topology → no freeze;
multiple tools **share** one display → no conflict.

---

## Features

- **Persistent driver-provided display**, decoupled from streaming connections
- **27 display modes**:

  | Resolution | Refresh rates |
  |---|---|
  | 1920 × 1080 | 60 / 90 / 120 / 144 / 165 / 240 Hz |
  | 2560 × 1440 | 60 / 90 / 120 / 144 / 165 / 240 Hz |
  | 3440 × 1440 (ultrawide) | 60 / 90 / 120 / 144 / 165 / 240 Hz |
  | 3840 × 2160 (4K) | 60 / 90 / 120 / 144 / 165 / 240 Hz |

  Preferred (default) mode: **2560 × 1440 @ 144 Hz**

- **Custom EDID**: vendor code `CVD`, monitor name `CustomVDD` — reliably identified by
  the OS and streaming software instead of showing as a generic "Generic PnP Monitor"
- **Stable ContainerId**: prevents a new monitor instance from being created on every
  driver reload (see "Design Notes" below)
- **One-click installer**: handles certificate trust, driver staging and device creation
- **Standard uninstaller**: appears in "Control Panel → Programs and Features"
- **No need to disable Secure Boot**, **no need to enable test signing**

---

## Installation

### Option 1: Installer (recommended)

Download `CustomVDD-Setup-x.y.z.exe` from the [latest release](../../releases/latest)
and run it **as Administrator**.

The installer will automatically:

1. Import the driver's self-signed certificate into *Trusted Root Certification
   Authorities* and *Trusted Publishers*
2. Stage the driver package
3. Create the virtual display device
4. Verify the installation

The display then appears under **Settings → System → Display**.

> **About the certificate**: this driver uses a self-signed certificate, which is common
> practice for open-source / personal drivers. The installer configures trust
> automatically. If you run the installer again on a machine where it is already
> installed, it detects the existing installation and refuses to proceed, prompting you
> to uninstall first.

### Option 2: Build from source

**Requirements:**

- Visual Studio 2022 with the *Desktop development with C++* workload
- Windows SDK (10.0.22621.0 or later)
- Windows Driver Kit (WDK) matching the SDK version
- Inno Setup 6 (only needed to build the installer)

**Steps:**

```powershell
# 1. Generate the EDID (optional; the generated result is already in the repo)
python tools\gen-edid.py

# 2. Build the driver
powershell -ExecutionPolicy Bypass -File tools\build.ps1

# 3. Package it (requires a code-signing certificate, see below)
powershell -ExecutionPolicy Bypass -File tools\repack.ps1 -CertThumbprint <thumbprint>

# 4. Build the installer (optional)
iscc installer\CustomVDD-Setup.iss
```

**Creating a code-signing certificate:**

```powershell
# Generate a self-signed code-signing certificate in CurrentUser\My
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject 'CN=CustomVDD Development, O=CustomVDD Project, C=US' `
    -CertStoreLocation Cert:\CurrentUser\My `
    -HashAlgorithm SHA256 -KeyAlgorithm RSA -KeyLength 2048 `
    -KeyUsage DigitalSignature

$cert.Thumbprint    # pass this value to repack.ps1
```

---

## Uninstalling

Any of the following:

- **Control Panel** → Programs and Features → *CustomVDD Virtual Display* → Uninstall
- **Start Menu** → CustomVDD → Uninstall CustomVDD
- Run `unins000.exe` from the installation directory

Uninstalling removes the virtual display device, driver package, trusted certificate,
program files and registry entries — **and cleans up any orphaned "phantom" monitor
instances left behind by earlier versions**.

---

## Recommended Usage

### With streaming software

Let the streaming tool **capture only** — do not let it create its own virtual display:

**Sunshine / Moonlight**

```ini
# sunshine.conf
output_name = automatic          ; auto-select; does not depend on \\.\DISPLAYnn
display_device_prep = ensure_active
vdd_keep_enabled = off           ; do not let Sunshine manage a virtual display
vdd_headless_create = off
resolution_change = no
refresh_rate_change = no
```

**NetEase UU Remote**

Turn off its "super screen" / virtual-display feature in the settings.

**Why `automatic` rather than a fixed display number**: Windows assigns `\\.\DISPLAYnn`
dynamically, so the number can change after a driver reinstall or reboot. When the
physical/console display is off, CustomVDD is the only active display, so `automatic`
always selects it.

### Typical workflow

```
1. Keep CustomVDD installed (nothing to do — it works once installed)
2. Close the host's own console session (on Hyper-V and similar virtualized setups)
   → CustomVDD automatically becomes the only display and takes over as primary
3. Connect with Sunshine / UU Remote / RDP
   → it captures CustomVDD automatically
4. Disconnect
   → CustomVDD remains; topology is unchanged; no freeze
```

---

## Design Notes

### Why the ContainerId is fixed

Windows uses `ContainerId` to decide whether it is looking at *the same* monitor.
Microsoft's sample driver does this:

```cpp
CoCreateGuid(&MonitorInfo.MonitorContainerId);   // random GUID on every start
```

**A random value makes every driver load (boot / reinstall / upgrade) look like a
brand-new monitor**, so new instances accumulate under `DISPLAY\<hardware ID>`:

```
DISPLAY\CVD0001\1&xxxxxxxx&0&UID256   ← phantom
DISPLAY\CVD0001\1&xxxxxxxx&1&UID256   ← phantom
DISPLAY\CVD0001\1&xxxxxxxx&2&UID256   ← currently active
```

When the parent device goes away, the old instances remain as `Disconnected` phantom
devices, and the `\\.\DISPLAYnn` numbering keeps inflating (multiple phantoms observed;
numbering grew from DISPLAY25 to DISPLAY73 in testing).

CustomVDD instead uses a **fixed GUID derived from the EDID identity**. Every load
yields the same monitor, so Windows reuses the existing instance and no phantoms appear:

```cpp
MonitorInfo.MonitorContainerId.Data1 = 0x43564430;   // "CVD0"
MonitorInfo.MonitorContainerId.Data2 = 0x0001;       // product code
MonitorInfo.MonitorContainerId.Data3 = 0x0001;       // serial number
// Data4 = 'C','V','D',0,0,0,0,<connector index>
```

> The Microsoft sample's own comment above that line says *"it's best practice to choose
> a stable container ID"* — the sample code itself does not do so.

### Two sources of the mode list

In IddCx, the modes the OS reports are the **intersection of two sets**:

| Source | Location | Role |
|---|---|---|
| Monitor modes | `s_SampleMonitors[].pModeList` | Described by the EDID; count limited by `szModeList` |
| Target modes | `TargetModes` in `CustomVDDMonitorQueryModes()` | Device processing capability |

**Both must be updated when adding a resolution or refresh rate**, or it will not show
up in display settings.

### Range limits in the EDID

The horizontal-frequency and pixel-clock fields of an EDID range descriptor are 8 bits
each, capping at 255 kHz and 2550 MHz respectively. This driver uses those maximums,
which covers the pixel clock required for 4K@240Hz.

---

## FAQ

**Q: No new display appears in display settings after installation**

1. Check **Device Manager → Display adapters** for `Custom Display Adapter`
2. If it shows a yellow warning, see the log: `%ProgramData%\CustomVDD\setup.log`
3. Some systems need a reboot to enumerate a newly created root device

**Q: It says a reboot is required**

After creating a root-enumerated device, some systems need a reboot to finish
enumeration. Reboot as prompted.

**Q: The host froze (cursor moves but clicks do nothing, with a beep)**

This is a known symptom of abrupt display-topology changes. Press
**`Win + Ctrl + Shift + B`** (graphics driver stack hot reset); it may need to be
pressed twice. This does not lose your open applications.

The real prevention is **avoiding unnecessary display topology changes** — which is
exactly what this project is designed for.

**Q: The driver is not WHQL certified**

This project uses a self-signed certificate and is not WHQL certified, which is typical
for personal / open-source drivers. The installer imports the certificate into the
trusted stores, so the driver loads normally.

**Q: Do I need to disable Secure Boot?**

No. Importing the certificate into *Trusted Root Certification Authorities* and
*Trusted Publishers* is sufficient; test signing (`bcdedit /set testsigning on`) is not
required.

---

## Project Layout

```
CustomVDD/
├── driver/                     Driver sources
│   ├── Driver.cpp              Main implementation (EDID, mode tables, ContainerId)
│   ├── Driver.h                Header definitions
│   ├── CustomVDD.inf           Driver installation info
│   ├── CustomVDD.vcxproj       VS project file
│   └── Trace.h                 WPP tracing
├── installer/                  Installer
│   ├── CustomVDD-Setup.iss     Inno Setup script
│   └── setup-driver.ps1        Install / uninstall core logic
└── tools/                      Build tooling
    ├── build.ps1               Build the driver
    ├── repack.ps1              Generate the CAT and sign
    └── gen-edid.py             EDID generator
```

---

## Technical Details

| Item | Value |
|---|---|
| Driver model | UMDF2 + IddCx 1.4 (user-mode driver) |
| Hardware ID | `Root\CustomVDD` |
| Device name | Custom Display Adapter |
| Monitor hardware ID | `MONITOR\CVD0001` |
| EDID vendor code | `CVD` |
| Product code | `0x0001` |
| Monitor name | `CustomVDD` |
| Install log | `%ProgramData%\CustomVDD\setup.log` |

---

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE).

The driver framework is derived from Microsoft's official
[`IddSampleDriver`](https://github.com/microsoft/Windows-driver-samples/tree/main/video/IndirectDisplay)
sample, which is released under the **MS-PL (Microsoft Public License)**.
Source files under `driver/` retain Microsoft's original copyright notice.

> MS-PL is a permissive license that allows modification and redistribution (including
> commercial use) provided the original copyright notice is retained. This project is an
> independent derivative work and is not affiliated with Microsoft.

---

Copyright (c) 2026 CustomVDD Project · MIT License
