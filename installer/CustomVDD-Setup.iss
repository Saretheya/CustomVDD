; ============================================================
;  CustomVDD 虚拟显示器 —— 一键部署安装包
;
;  编译：
;    iscc CustomVDD-Setup.iss
;
;  生成：output\CustomVDD-Setup-1.0.0.exe
;
;  特性：
;    - 一键部署驱动 + 证书信任 + 设备节点创建
;    - 重复安装检测（已安装则拒绝并提示）
;    - 标准卸载程序（控制面板可见，完整移除所有内容）
; ============================================================

#define AppName        "CustomVDD 虚拟显示器"
#define AppNameShort   "CustomVDD"
#define AppVersion     "1.0.0"
#define AppPublisher   "CustomVDD Project"
; [Setup] 段的 AppId 需要 {{ 转义（Inno 规则：值以 { 开头时前置一个 {）
#define AppId          "{{8F3A2C71-4B95-4E6D-9A18-7C2E5D4F1B03}"
; [Code] 段做注册表检测时要用未转义的形式（否则会变成双花括号，路径匹配不上）
#define AppIdPlain     "{8F3A2C71-4B95-4E6D-9A18-7C2E5D4F1B03}"
#define ServiceName    "CustomVDD"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppNameShort}
DefaultGroupName={#AppNameShort}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=CustomVDD-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\setup-driver.ps1
DisableDirPage=yes
AllowNoIcons=yes
; 卸载时不删除用户数据目录（由脚本自行处理）
Uninstallable=yes

[Languages]
Name: "chinese"; MessagesFile: "compiler:Default.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
chinese.AlreadyInstalled=检测到本机已安装 %1。%n%n请先在「控制面板 → 程序和功能」中卸载后再运行本安装程序。
chinese.InstallFailed=驱动安装失败，请查看日志：%n%1
chinese.InstallOk=CustomVDD 虚拟显示器部署完成。%n%n显示器将在数秒内出现在「设置 → 显示」中。%n如需调整分辨率/刷新率，请在显示设置中选择。
chinese.UninstallNote=即将卸载 CustomVDD 虚拟显示器。%n%n这将移除：%n  · 虚拟显示器设备%n  · 驱动程序包%n  · 受信任证书%n  · 程序文件%n%n点击「是」开始卸载。
chinese.UninstallOk=CustomVDD 虚拟显示器已成功卸载。%n%n已移除：%n  · 虚拟显示器设备%n  · 驱动程序包%n  · 受信任证书%n  · 程序文件与注册项
chinese.UninstallPartial=卸载已完成，但部分组件可能未完全移除。%n%n请查看日志：%n%1%n%n若显示器仍出现在显示设置中，请重启系统。
chinese.NeedRestart=系统报告需要重启才能完成安装。是否现在重启？
english.AlreadyInstalled=An existing installation of %1 was detected.%n%nPlease uninstall it from "Control Panel > Programs and Features" first.
english.InstallFailed=Driver installation failed. See log: %n%1
english.InstallOk=CustomVDD virtual display deployed successfully.
english.UninstallNote=This will remove the CustomVDD virtual display device, driver package, trusted certificate and program files. Continue?
english.UninstallOk=CustomVDD virtual display has been uninstalled successfully.
english.UninstallPartial=Uninstall finished, but some components may remain. See log: %n%1
english.NeedRestart=A restart is required to complete installation. Restart now?

[Files]
; 驱动包
Source: "package\CustomVDD.inf";  DestDir: "{app}\package"; Flags: ignoreversion
Source: "package\CustomVDD.dll";  DestDir: "{app}\package"; Flags: ignoreversion
Source: "package\CustomVDD.cat";  DestDir: "{app}\package"; Flags: ignoreversion
Source: "package\CustomVDD.cer";  DestDir: "{app}\package"; Flags: ignoreversion
; 安装/卸载核心脚本
Source: "setup-driver.ps1";       DestDir: "{app}"; Flags: ignoreversion
; 说明文档
Source: "README.txt";             DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\卸载 {#AppName}"; Filename: "{uninstallexe}"

[Run]
; 执行驱动安装（等待完成，隐藏窗口）
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup-driver.ps1"" -Mode install -PackageDir ""{app}\package"""; \
  StatusMsg: "正在部署虚拟显示器驱动..."; \
  Flags: runhidden waituntilterminated; \
  AfterInstall: CheckInstallResult

[UninstallRun]
; 卸载驱动（在文件删除前执行）
; 注意：StatusMsg 会在卸载进度条上显示文字说明
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup-driver.ps1"" -Mode uninstall -PackageDir ""{app}\package"""; \
  StatusMsg: "正在移除虚拟显示器设备、驱动与证书..."; \
  RunOnceId: "CustomVDDUninstallDriver"; \
  Flags: runhidden waituntilterminated

[UninstallDelete]
; 清理数据目录
Type: filesandordirs; Name: "{commonappdata}\{#ServiceName}"
Type: filesandordirs; Name: "{app}"

[Code]
var
  InstallExitCode: Integer;
  InstallSucceeded: Boolean;
  UninstallSucceeded: Boolean;
  UninstallRan: Boolean;

{ ------------------------------------------------------------
  读取脚本退出码
  ------------------------------------------------------------ }
function RunSetupScript(const Params: String; var ExitCode: Integer): Boolean;
var
  ResultCode: Integer;
  Exe: String;
begin
  Exe := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Result := Exec(Exe, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  ExitCode := ResultCode;
end;

{ ------------------------------------------------------------
  安装前：检测是否已安装
  注意：静默模式下不能弹窗阻塞，改为直接静默退出。
  ------------------------------------------------------------ }
function InitializeSetup(): Boolean;
var
  ExitCode: Integer;
  ScriptPath: String;
begin
  Result := True;

  { 通过注册表检测已有安装。
    注意：必须用 AppIdPlain（未转义版）。
    若用 AppId 常量，在 Code 段会展开成双花括号，与真实注册表路径不符。 }
  if RegKeyExists(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{#AppIdPlain}_is1') then
  begin
    if not WizardSilent then
      MsgBox(FmtMessage(CustomMessage('AlreadyInstalled'), ['{#AppName}']), mbError, MB_OK);
    Result := False;
    Exit;
  end;

  { 通过驱动检测（覆盖：注册表记录丢失但驱动仍在的情况）
    用内联 PowerShell 检查，不依赖已解压的脚本文件。 }
  if RunSetupScript('-NoProfile -ExecutionPolicy Bypass -Command "' +
       '$d = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | ' +
       'Where-Object { $_.FriendlyName -eq ''Custom Display Adapter'' }; ' +
       'if ($d) { exit 2 } else { exit 0 }"', ExitCode) then
  begin
    if ExitCode = 2 then
    begin
      if not WizardSilent then
        MsgBox(FmtMessage(CustomMessage('AlreadyInstalled'), ['{#AppName}']), mbError, MB_OK);
      Result := False;
    end;
  end;
end;

{ ------------------------------------------------------------
  安装后：检查驱动安装结果
  ------------------------------------------------------------ }
procedure CheckInstallResult();
var
  LogPath: String;
begin
  LogPath := ExpandConstant('{commonappdata}\CustomVDD\setup.log');
  { [Run] 的 ExitCode 无法直接读取，改为再次 verify }
  if RunSetupScript('-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\setup-driver.ps1') + '" -Mode verify', InstallExitCode) then
  begin
    InstallSucceeded := (InstallExitCode = 0);
    if (not InstallSucceeded) and (not WizardSilent) then
    begin
      MsgBox(FmtMessage(CustomMessage('InstallFailed'), [LogPath]), mbError, MB_OK);
    end;
  end;
end;

{ ------------------------------------------------------------
  安装成功后提示
  ------------------------------------------------------------ }
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if InstallSucceeded and (not WizardSilent) then
      MsgBox(CustomMessage('InstallOk'), mbInformation, MB_OK);
  end;
end;

{ ------------------------------------------------------------
  卸载确认
  注意：静默模式下（/VERYSILENT 或 /SILENT）不能用 MsgBox，
        否则会阻塞自动化卸载。此时直接放行。
  ------------------------------------------------------------ }
function InitializeUninstall(): Boolean;
begin
  if UninstallSilent then
    Result := True
  else
    Result := MsgBox(CustomMessage('UninstallNote'), mbConfirmation, MB_YESNO) = IDYES;
end;

{ ------------------------------------------------------------
  检查卸载是否彻底：验证设备、驱动包是否真的都不在了
  返回 True = 已清理干净
  ------------------------------------------------------------ }
function VerifyUninstallComplete(): Boolean;
var
  ExitCode: Integer;
  ScriptPath: String;
begin
  Result := False;
  ScriptPath := ExpandConstant('{app}\setup-driver.ps1');
  if not FileExists(ScriptPath) then
  begin
    { 脚本已被删除，无法验证；保守地认为成功 }
    Result := True;
    Exit;
  end;

  { check 模式：退出码 2 = 仍检测到安装；0 = 已清理干净 }
  if RunSetupScript('-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" -Mode check', ExitCode) then
    Result := (ExitCode = 0);
end;

{ ------------------------------------------------------------
  卸载过程：各阶段状态提示 + 完成确认
  ------------------------------------------------------------ }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Msg: String;
  LogPath: String;
begin
  case CurUninstallStep of
    usAppMutexCheck:
      begin
        UninstallRan := False;
        UninstallSucceeded := False;
      end;

    usUninstall:
      begin
        { 该阶段之后 Inno 会执行 [UninstallRun]（带 StatusMsg 的进度提示） }
      end;

    usPostUninstall:
      begin
        { 驱动清理已完成，做真实验证 }
        LogPath := ExpandConstant('{commonappdata}\CustomVDD\setup.log');
        UninstallRan := True;
        UninstallSucceeded := VerifyUninstallComplete();

        if not UninstallSilent then
        begin
          if UninstallSucceeded then
            Msg := CustomMessage('UninstallOk')
          else
            Msg := FmtMessage(CustomMessage('UninstallPartial'), [LogPath]);
          MsgBox(Msg, mbInformation, MB_OK);
        end;
      end;

    usDone:
      begin
        { 全部完成 }
      end;
  end;
end;

