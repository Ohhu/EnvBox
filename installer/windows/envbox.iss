; EnvBox for Windows — Inno Setup 6 安装脚本（仅 x64，每用户安装）
; 由 Scripts/windows/package-windows.ps1 调用：
;   ISCC.exe /DAppVersion=1.1.0 /DAppArch=amd64 /DDistDir=<staging> /DOutDir=<dist> /DIconPath=<ico> envbox.iss
;
; 设计约束：
;   * 唯一的正式分发形态就是安装器：不做便携版，不做 MSIX
;     （MSIX 容器化会拦注册表直写与 WM_SETTINGCHANGE 广播，正好是产品的全部功能）
;   * 每用户安装（PrivilegesRequired=lowest），不需要管理员权限，卸载也不需要
;   * 覆盖安装时由安装器通过具名事件通知正在运行的 EnvBox 退出，不让用户手动关托盘程序
;   * 安装界面跟随 Windows 显示语言（中文系统中文，其余英文），不弹语言选择页
;   * 不写任何环境变量、不写自启动项、不装 Shell 集成：这三样都碰 HKCU\Environment 或用户 profile，
;     必须由 App 自己用注册表 API 维护（保住 REG_EXPAND_SZ、可去重、可撤销）
;   * 升级不碰 %LOCALAPPDATA%\EnvBox（配置库与 DPAPI 主密钥必须继续可用）

#define AppName "EnvBox"
#define AppExe "EnvBox.exe"
#define AppPublisher "Ohhu"
#define AppUrl "https://github.com/Ohhu/EnvBox"

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppArch
  #define AppArch "amd64"
#endif
#ifndef DistDir
  #define DistDir "..\dist"
#endif
#ifndef OutDir
  #define OutDir "..\dist"
#endif
#ifndef IconPath
  #define IconPath ""
#endif
; 中文翻译所在目录；默认相对本脚本，打包脚本可传 /DLangDir=<绝对路径>
#ifndef LangDir
  #define LangDir "lang"
#endif

[Setup]
; AppId 必须长期固定，否则升级会被当成另一个产品
AppId={{5C1F7C2E-8A4B-4E6D-9F31-2B7D6A0C4E11}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; 故意不设 AppMutex：那条指令只会在启动时弹"请手动关闭程序"。运行中的实例改由
; [Code] 里的退出事件关闭（见文件末尾），AppMutex 会让安装器在事件生效前就拦住。
CloseApplications=yes
RestartApplications=no
PrivilegesRequired=lowest
OutputDir={#OutDir}
OutputBaseFilename=EnvBox-{#AppVersion}-Windows-{#AppArch}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
MinVersion=10.0.17763
; 覆盖安装时保留用户上次选择的目录
UsePreviousAppDir=yes
; DisableDirPage 的默认值是 auto：检测到已安装过就整页隐藏，用户看不到装到哪、
; 也没法改。这里强制显示，页里预填上次的目录（UsePreviousAppDir），多一次"下一步"。
DisableDirPage=no
; 静默更新时不要把"安装程序已在运行"弹成模态框
UsePreviousLanguage=no
; 按系统显示语言选界面语言；不弹选择页，用户仍可用 /LANG=zh 或 /LANG=en 覆盖
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=no

#if IconPath != ""
SetupIconFile={#IconPath}
#endif

[Languages]
; 中文翻译随仓库放在 installer/windows/lang/：Inno 官方安装包只带英文和部分欧洲语言。
; LanguageID 在 .isl 内声明（$0804），安装器按系统显示语言自动匹配。
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "zh"; MessagesFile: "{#LangDir}\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#DistDir}\EnvBox.exe"; DestDir: "{app}"; Flags: ignoreversion
; CLI 放在 bin\ 子目录：NTFS 大小写不敏感，{app}\EnvBox.exe 与 {app}\envbox.exe 会互相覆盖
Source: "{#DistDir}\bin\envbox.exe"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#DistDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#DistDir}\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{#AppName} 命令行"; Filename: "{cmd}"; Parameters: "/k ""{app}\bin\envbox.exe"" version"; WorkingDir: "{app}"; Flags: runminimized
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; 交互式安装：结束页勾选启动
Filename: "{app}\{#AppExe}"; Description: "启动 {#AppName}"; Flags: nowait postinstall skipifsilent
; 静默安装（App 自更新调用 /VERYSILENT 时）：装完把新版本拉起来，带上 /updated 让 App 汇报结果
Filename: "{app}\{#AppExe}"; Parameters: "--updated"; Flags: nowait; Check: WizardSilent

[UninstallRun]
; 清理自启动项、Shell 集成与激活快照（PATH 集成尚未实现）
Filename: "{app}\bin\envbox.exe"; Parameters: "uninstall-cleanup"; Flags: runhidden; RunOnceId: "EnvBoxCleanup"

[CustomMessages]
en.EnvBoxStillRunning=The installer needs to replace EnvBox's files, but EnvBox is still running.%n%nClose EnvBox from its notification-area icon, then choose Retry.
zh.EnvBoxStillRunning=安装程序需要覆盖 EnvBox 的程序文件，但 EnvBox 仍在运行。%n%n请从通知区域图标退出 EnvBox，然后选择“重试”。

[Code]
{ EnvBox lives in the notification area, so it keeps running after the window is
  closed, and Setup cannot replace a running executable. Instead of telling the
  user to quit it, Setup runs "EnvBox.exe --quit": that build signals its own
  quit event and exits within a second. AppMutex is deliberately not set, because
  that directive blocks before this code gets a chance to run.

  Builds older than --quit only re-focus their window, so the first upgrade after
  this change still falls back to the retry dialog. }

const
  EnvBoxMutexName = 'EnvBox-SingleInstance-5C1F7C2E';
  QuitWaitMilliseconds = 5000;

function EnvBoxIsRunning(): Boolean;
begin
  Result := CheckForMutexes(EnvBoxMutexName);
end;

{ The installed EnvBox.exe. Expanding the app-dir constant before the wizard
  exists aborts Setup with a runtime error, so it is only touched once the caller
  says it is safe; until then the previous uninstall entry is the only source. }
function EnvBoxExePath(AppDirReady: Boolean): String;
var
  Candidate: String;
  InstallPath: String;
begin
  Result := '';
  if AppDirReady then
  begin
    Candidate := ExpandConstant('{app}\{#AppExe}');
    if FileExists(Candidate) then
    begin
      Result := Candidate;
      Exit;
    end;
  end;
  { No default-folder guess here: the previous uninstall entry is the only source
    that is both reliable and cheap this early. }
  { The uninstall key is AppId plus the _is1 suffix, with the literal braces that
    the setup section escapes by doubling the opening one. Spelled out on
    purpose: SetupSetting("AppId") hands back the escaped form. }
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{5C1F7C2E-8A4B-4E6D-9F31-2B7D6A0C4E11}_is1', 'Inno Setup: App Path', InstallPath) then
  begin
    Candidate := InstallPath + '\{#AppExe}';
    if FileExists(Candidate) then
      Result := Candidate;
  end;
end;

{ Asks the installed app to exit. The app answers --quit before it touches the
  single-instance mutex, so this never looks like a second instance. Used instead
  of a Win32 event call because Inno's script engine does not expose one. }
function AskEnvBoxToQuit(AppDirReady: Boolean): Boolean;
var
  ResultCode: Integer;
  ExePath: String;
begin
  Result := False;
  ExePath := EnvBoxExePath(AppDirReady);
  if ExePath = '' then
    Exit;
  { ewNoWait: the app is polled through its mutex below, and the caller must not
    freeze the wizard while a --quit process exits. }
  Result := Exec(ExePath, '--quit', '', SW_HIDE, ewNoWait, ResultCode);
end;

function WaitForEnvBoxExit(AppDirReady: Boolean): Boolean;
var
  Elapsed: Integer;
begin
  Result := not EnvBoxIsRunning();
  if Result then
    Exit;
  { No exe means an older build without the listener: stop waiting and let the
    caller fall back to asking the user. }
  if not AskEnvBoxToQuit(AppDirReady) then
    Exit;
  Elapsed := 0;
  while EnvBoxIsRunning() and (Elapsed < QuitWaitMilliseconds) do
  begin
    Sleep(100);
    Elapsed := Elapsed + 100;
  end;
  Result := not EnvBoxIsRunning();
end;

{ Closes a running EnvBox, asking the user only when the automatic close failed.
  Used right before files are copied, and by the uninstaller. }
function CloseRunningEnvBox(AppDirReady: Boolean): Boolean;
begin
  Result := True;
  while not WaitForEnvBoxExit(AppDirReady) do
  begin
    if WizardSilent then
    begin
      Result := False;
      Exit;
    end;
    if MsgBox(CustomMessage('EnvBoxStillRunning'), mbError, MB_RETRYCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

{ Ask the app to leave as soon as the wizard exists, but do not block the first
  page waiting for it: PrepareToInstall does the waiting. No prompts here either.
  The app-dir constant is still off limits (only the registry path is used), which
  is what the earlier InitializeSetup attempt got wrong: expanding it there
  aborts the whole setup with a runtime error. }
procedure InitializeWizard();
begin
  if EnvBoxIsRunning() then
    AskEnvBoxToQuit(False);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not CloseRunningEnvBox(True) then
    Result := CustomMessage('EnvBoxStillRunning');
end;

{ Uninstaller: resolve through the registry, the uninstall log owns the folder. }
function InitializeUninstall(): Boolean;
begin
  Result := CloseRunningEnvBox(False);
end;
