# CustomVDD — Windows 虚拟显示器驱动

一个自研的 Windows **虚拟显示器**（Indirect Display Driver，IDD），
基于微软官方 `IddSampleDriver` 示例（MS-PL 许可）改造。

**English** · [README.en.md](README.en.md)

---

## 它解决什么问题

远程串流软件（Sunshine / Moonlight、网易 UU 远程、RDP 等）在**无物理显示器**的
机器上工作时，通常会**临时创建**一个虚拟显示器，断开连接时再销毁它。这会带来三类问题：

| 问题 | 成因 |
|---|---|
| **断连时画面错乱 / 分辨率跳变** | 显示器随连接创建与销毁，显示拓扑反复变化 |
| **宿主机 DWM 卡死**（鼠标能动但点不动、伴随提示音） | 拓扑剧变时桌面窗口管理器卡在 GPU 提交上 |
| **多软件互相争抢** | 每个串流软件各建一个虚拟屏，互相冲突 |

**CustomVDD 的做法**：让虚拟显示器由**驱动常驻提供**，与串流连接**完全解耦**。

```
串流软件（Sunshine / UU远程 / RDP）
        ↓  只做「捕获」
   虚拟显示器（CustomVDD 提供，始终存在）
        ↑  由驱动持有，与连接无关
    图形适配器
```

因而：断开串流**不会**触发拓扑变化 → 不卡死；多个软件**共用**同一块屏 → 不争抢。

---

## 特性

- **驱动常驻**，与串流连接解耦，断开不影响显示拓扑
- **27 种显示模式**：

  | 分辨率 | 刷新率 |
  |---|---|
  | 1920 × 1080 | 60 / 90 / 120 / 144 / 165 / 240 Hz |
  | 2560 × 1440 | 60 / 90 / 120 / 144 / 165 / 240 Hz |
  | 3440 × 1440（带鱼屏） | 60 / 90 / 120 / 144 / 165 / 240 Hz |
  | 3840 × 2160（4K） | 60 / 90 / 120 / 144 / 165 / 240 Hz |

  默认（首选）模式：**2560 × 1440 @ 144 Hz**

- **自定义 EDID**：厂商码 `CVD`、显示器名 `CustomVDD`，可被系统与串流软件稳定识别
  （而非通用 "Generic PnP Monitor"）
- **固定 ContainerId**：避免每次驱动重载都新建显示器实例（详见下文「设计要点」）
- **一键安装包**：自动完成证书信任、驱动部署与设备创建
- **标准卸载**：出现在「控制面板 → 程序和功能」中，可完整移除
- **无需关闭 Secure Boot**，**无需开启测试签名模式**

---

## 安装

### 方式一：使用安装包（推荐）

下载 [最新 Release](../../releases/latest) 中的 `CustomVDD-Setup-x.y.z.exe`，
**以管理员身份运行**，按提示完成。

安装程序会自动：

1. 将驱动自签名证书导入「受信任的根证书颁发机构」与「受信任的发布者」
2. 暂存驱动程序包
3. 创建虚拟显示器设备
4. 验证安装结果

安装完成后，显示器会出现在「设置 → 系统 → 显示」中。

> **关于证书**：本驱动使用自签名证书（开源 / 自用驱动的常见做法）。
> 安装程序会自动完成信任配置，无需手动操作。
> 若在已安装的机器上重复运行安装包，程序会检测到并拒绝安装，提示先卸载。

### 方式二：自行编译

**依赖：**

- Visual Studio 2022（含「使用 C++ 的桌面开发」工作负载）
- Windows SDK（10.0.22621.0 或更高）
- Windows Driver Kit (WDK)，与 SDK 版本匹配
- Inno Setup 6（仅打包安装程序时需要）

**步骤：**

```powershell
# 1. 生成 EDID（可选，仓库已含生成结果）
python tools\gen-edid.py

# 2. 编译驱动
powershell -ExecutionPolicy Bypass -File tools\build.ps1

# 3. 打包（需先准备代码签名证书，见下）
powershell -ExecutionPolicy Bypass -File tools\repack.ps1 -CertThumbprint <证书指纹>

# 4. 编译安装程序（可选）
iscc installer\CustomVDD-Setup.iss
```

**准备代码签名证书：**

```powershell
# 生成自签名代码签名证书（放在 CurrentUser\My）
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject 'CN=CustomVDD Development, O=CustomVDD Project, C=US' `
    -CertStoreLocation Cert:\CurrentUser\My `
    -HashAlgorithm SHA256 -KeyAlgorithm RSA -KeyLength 2048 `
    -KeyUsage DigitalSignature

$cert.Thumbprint    # 此值传给 repack.ps1
```

---

## 卸载

三种方式任选：

- **控制面板** → 程序和功能 → 选择「CustomVDD 虚拟显示器」→ 卸载
- **开始菜单** → CustomVDD → 卸载 CustomVDD 虚拟显示器
- 运行安装目录下的 `unins000.exe`

卸载会完整移除：虚拟显示器设备、驱动程序包、受信任证书、程序文件与注册项，
**并清理历史遗留的幽灵显示器实例**。

---

## 用法建议

### 与串流软件配合

推荐让串流软件**只做捕获**，不要让它创建自己的虚拟显示器：

**Sunshine / Moonlight**

```ini
# sunshine.conf
output_name = automatic          ; 自动选屏，不依赖 \\.\DISPLAYnn 编号
display_device_prep = ensure_active
vdd_keep_enabled = off           ; 不让 Sunshine 管理虚拟显示器
vdd_headless_create = off
resolution_change = no
refresh_rate_change = no
```

**UU 远程**

在配置中关闭「超级屏 / 虚拟屏」功能。

**为什么用 `automatic` 而不是固定编号**：`\\.\DISPLAYnn` 由 Windows 动态分配，
重装驱动或重启后可能变化。当物理 / 基本会话显示器关闭时，CustomVDD 是唯一
活动显示器，`automatic` 必然选中它。

### 典型工作流

```
1. 保持 CustomVDD 常驻（无需操作，装好后即生效）
2. 关闭宿主机自带的控制台会话（若使用 Hyper-V 等虚拟化环境）
   → CustomVDD 自动成为唯一显示器并接管主屏
3. 用 Sunshine / UU远程 / RDP 连接
   → 自动捕获 CustomVDD
4. 断开连接
   → CustomVDD 依然存在，显示拓扑不变，不会卡死
```

---

## 设计要点

### 为什么固定 ContainerId

Windows 用 `ContainerId` 判断「这是不是同一台显示器」。微软示例驱动中写的是：

```cpp
CoCreateGuid(&MonitorInfo.MonitorContainerId);   // 每次启动生成随机 GUID
```

**随机值会导致每次驱动加载（开机 / 重装 / 升级）都被视为一台全新显示器**，
于是在 `DISPLAY\<硬件ID>` 下不断新建实例：

```
DISPLAY\CVD0001\1&xxxxxxxx&0&UID256   ← 幽灵
DISPLAY\CVD0001\1&xxxxxxxx&1&UID256   ← 幽灵
DISPLAY\CVD0001\1&xxxxxxxx&2&UID256   ← 当前活跃
```

旧实例在父设备消失后残留为 `Disconnected` 幽灵设备，并使 `\\.\DISPLAYnn`
编号持续膨胀（实测可累积多个幽灵、编号从 DISPLAY25 涨到 DISPLAY73）。

CustomVDD 改用**由 EDID 身份派生的固定 GUID**，每次加载都得到同一台显示器，
Windows 复用既有实例，不再产生幽灵：

```cpp
MonitorInfo.MonitorContainerId.Data1 = 0x43564430;   // "CVD0"
MonitorInfo.MonitorContainerId.Data2 = 0x0001;       // 产品码
MonitorInfo.MonitorContainerId.Data3 = 0x0001;       // 序列号
// Data4 = 'C','V','D',0,0,0,0,<连接器索引>
```

> 微软示例在该行上方的注释中本就写明 *"it's best practice to choose a stable
> container ID"* —— 示例代码自身未落实这一点。

### 模式列表的两个来源

IddCx 中，系统报告的可用模式是**两个集合的交集**：

| 来源 | 位置 | 作用 |
|---|---|---|
| 监视器模式 | `s_SampleMonitors[].pModeList` | 由 EDID 描述，`szModeList` 限定数量 |
| 目标模式 | `CustomVDDMonitorQueryModes()` 中的 `TargetModes` | 设备处理能力 |

**新增分辨率或刷新率时两处都要改**，否则不会出现在显示设置中。

### EDID 中的范围限制

EDID 范围描述符的水平频率与像素时钟字段各为 8 位，可表示上限分别为
255 kHz 与 2550 MHz。本驱动已取到该上限，覆盖 4K@240Hz 所需的像素时钟。

---

## 常见问题

**Q：安装后显示设置里没有出现新显示器**

1. 检查「设备管理器 → 显示适配器」是否有 `Custom Display Adapter`
2. 若有黄色感叹号，查看日志：`%ProgramData%\CustomVDD\setup.log`
3. 部分系统在新建 root 设备后需要重启才能枚举显示器

**Q：提示需要重启**

新建 root 枚举设备后，部分系统需要重启才能完成枚举。按提示重启即可。

**Q：宿主机卡死（鼠标能动但点击无响应，伴随提示音）**

这是显示拓扑剧变时的已知现象。按 **`Win + Ctrl + Shift + B`**
（显卡驱动栈热重置），可能需要按两次。此操作不会丢失已打开的应用程序。

其根本预防方式是**避免不必要的显示拓扑变更**——这正是本项目的设计目标。

**Q：驱动没有通过 Windows 硬件认证**

本项目使用自签名证书，未做 WHQL 认证（个人 / 开源项目通常如此）。
安装程序会将证书导入受信任存储，因此驱动可以正常加载。

**Q：Secure Boot 需要关闭吗**

不需要。将证书导入「受信任的根证书颁发机构」+「受信任的发布者」即可，
无需开启测试签名模式（`bcdedit /set testsigning on`）。

---

## 项目结构

```
CustomVDD/
├── driver/                     驱动源码
│   ├── Driver.cpp              主实现（含 EDID、模式表、ContainerId）
│   ├── Driver.h                头部定义
│   ├── CustomVDD.inf           驱动安装信息
│   ├── CustomVDD.vcxproj       VS 项目文件
│   └── Trace.h                 WPP 跟踪
├── installer/                  安装程序
│   ├── CustomVDD-Setup.iss     Inno Setup 脚本
│   └── setup-driver.ps1        安装 / 卸载核心逻辑
└── tools/                      构建工具
    ├── build.ps1               编译驱动
    ├── repack.ps1              生成 CAT 并签名
    └── gen-edid.py             EDID 生成器
```

---

## 技术信息

| 项 | 值 |
|---|---|
| 驱动类型 | UMDF2 + IddCx 1.4（用户模式驱动） |
| 硬件 ID | `Root\CustomVDD` |
| 设备名 | Custom Display Adapter |
| 监视器硬件 ID | `MONITOR\CVD0001` |
| EDID 厂商码 | `CVD` |
| 产品码 | `0x0001` |
| 显示器名 | `CustomVDD` |
| 安装日志 | `%ProgramData%\CustomVDD\setup.log` |

---

## 许可证

本项目采用 **MIT 许可证**，详见 [LICENSE](LICENSE)。

本项目的驱动框架源自微软官方示例
[`IddSampleDriver`](https://github.com/microsoft/Windows-driver-samples/tree/main/video/IndirectDisplay)，
该示例以 **MS-PL（Microsoft Public License）** 发布。
`driver/` 目录下的源文件保留了微软的原始版权声明。

> MS-PL 是宽松许可证，允许修改与再分发（含商业用途），
> 要求保留原始版权声明。本项目为独立的衍生作品，与微软无隶属关系。

---

Copyright (c) 2026 Saretheya · MIT License
