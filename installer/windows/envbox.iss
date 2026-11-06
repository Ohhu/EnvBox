; EnvBox for Windows — Inno Setup 6 安装脚本（仅 x64，每用户安装）
; 由 Scripts/windows/package-windows.ps1 调用：
;   ISCC.exe /DAppVersion=1.1.0 /DAppArch=amd64 /DDistDir=<staging> /DOutDir=<dist> /DIconPath=<ico> envbox.iss
;
; 设计约束：
;   * 唯一的正式分发形态就是安装器：不做便携版，不做 MSIX
;     （MSIX 容器化会拦注册表直写与 WM_SETTINGCHANGE 广播，正好是产品的全部功能）
;   * 每用户安装（PrivilegesRequired=lowest），不需要管理员权限，卸载也不需要
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
; 与 App 内单实例互斥体同名：安装器据此检测"EnvBox 正在运行"，升级时提示关闭而不是覆盖失败
AppMutex=EnvBox-SingleInstance-5C1F7C2E
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
; 静默更新时不要把"安装程序已在运行"弹成模态框
UsePreviousLanguage=no

#if IconPath != ""
SetupIconFile={#IconPath}
#endif

[Languages]
; Inno 官方安装包只带英文 Default.isl；中文界面需把 Languages\ChineseSimplified.isl 放到 installer/windows/lang/ 并改这里。
Name: "english"; MessagesFile: "compiler:Default.isl"

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
