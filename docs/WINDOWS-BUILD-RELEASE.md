# Windows 编译与发布

配套：[WINDOWS-PORT.md](WINDOWS-PORT.md)（选型）、[WINDOWS-UPDATE.md](WINDOWS-UPDATE.md)（自更新）、[RELEASE.md](RELEASE.md)（macOS 清单）。

## 总览

```text
本地                    打标签                    CI（tag 触发，仅 x64）              产物
────                    ──────                    ────────────────────              ────
go run ./cmd/windows/envbox  →  git tag v1.1.1        →    gate   校验标签 / VERSION     →   EnvBox-1.1.1-Windows-amd64-Setup.exe
go test ./...           git push --tags            build  gofmt/vet/test         SHA256SUMS-windows-amd64.txt
build-windows.ps1                                  ├ wails3 generate syso       BUILD-INFO-amd64.txt
package-windows.ps1                                ├ go build 两个 exe
                                                   ├ 签名 exe
                                                   ├ Inno 编译安装器并签名
                                                   └ publish 上传到同一个 Release
```

只有安装器对外分发；CI 只上传安装器、校验值与构建信息。原始 `EnvBox.exe` / `envbox.exe` 不进 Release。

## 本地循环

| 命令 | 用途 |
| --- | --- |
| `go run ./cmd/windows/envbox` | 启动窗口调试（界面内嵌在 `shared/ui/assets`，仓库没有 `frontend/`） |
| `go test ./...` | 单元测试 |
| `./Scripts/windows/build-windows.ps1 -Configuration dev` | 不 strip 符号，便于看堆栈 |
| `./Scripts/windows/package-windows.ps1 -SkipInstaller` | 只生成校验值，跳过 Inno 编译 |

工具链：Go 1.26+、`wails3`（`go install github.com/wailsapp/wails/v3/cmd/wails3@v3.0.0`）、Inno Setup 6、Windows SDK（`signtool.exe`，仅签名需要）。脚本缺工具时会直接报错并给出安装命令。

三个环境注意点：

- 注册表读写需要正常权限的进程。受限沙箱里 `RegCreateKeyEx`/`RegOpenKeyEx` 返回 LSTATUS=5，UI 会显示错误横幅而不是空表。
- `GOCACHE`/`GOMODCACHE` 默认在用户目录；受限环境要显式指到可写路径，否则 `go build` 报 `Access is denied`。
- **产物会继承构建目录的完整性标签。** 如果构建发生在被标为低完整性的目录里（受限沙箱常这么做），`dist` 下的 exe 也会带上 `Mandatory Label\Low`；双击时 Windows 让新进程取"文件标签与令牌里较低的那个"，安装器就以低完整性运行，在 `%TEMP%`（中等完整性）创建解包目录被拒，报 `Setup was unable to create the directory ... Error 5`。把产物**复制**到普通目录再分发即可：复制不携带 SACL，副本是正常完整性。CI 跑在干净 runner 上，不会出现这个标签。

## 版本号

单一来源是仓库根目录的 `VERSION`，与 macOS 共用。

| 用途 | 取值 | 注入方式 |
| --- | --- | --- |
| 用户可见版本 | `VERSION` | `-X internal/core/buildinfo.Version` |
| 构建号 | `git rev-list --count HEAD` | `-X ...BuildNumber` |
| Windows 资源版本（必须四段） | `1.1.1.10` | 渲染 `build/windows/info.json` → `wails3 generate syso` |
| 提交 / 时间 / 通道 | `git rev-parse --short HEAD`、UTC | `-X ...Commit`、`-X ...BuildDate`、`-X ...Channel` |

`internal/core/buildinfo` 里这些必须是 `var`：`-X` 改不动 `const`，而 `Channel` 决定了开发期开关（`ENVBOX_CONFIG_DIR`、`ENVBOX_ENV_KEY`、`ENVBOX_SKIP_BROADCAST`、`ENVBOX_START_VIEW`）是否生效——它若停在 `dev`，发布版就能被环境变量重定向配置目录。

三处版本必须一致：侧栏版本标签、`envbox version`、资源管理器属性。第四段来自提交数，因为 PE 资源版本不接受三段式。

## 构建开关

| 开关 | 作用 | 原因 |
| --- | --- | --- |
| `-tags production` | Wails 生产构建 | 否则产物指向本地 dev server |
| `-trimpath` | 去掉构建机路径 | 不泄露用户名路径，便于复现 |
| `-buildvcs=false` | 不写入 VCS 状态 | 否则同样的源码两次构建字节不同 |
| `-buildid=` | 清空 Go build id | 可复现构建的前提 |
| `-H windowsgui` | GUI 子系统 | 只给 GUI；CLI 加了会吞掉 stdio |
| `CGO_ENABLED=0` | 纯 Go | 不需要 mingw |
| `wails3 generate syso` | 图标、清单、文件属性 | 没有它 exe 是白板图标，高 DPI 下发虚 |

可复现性只对未签名的 exe 成立：签名会改写 PE 证书表并带时间戳，同一二进制签两次结果不同。

## 签名

| 方案 | 成本 | SmartScreen | CI 需要 |
| --- | --- | --- | --- |
| 不签名 | 0 | 首次运行需「更多信息 → 仍要运行」 | 无 |
| Authenticode OV/EV | 年费 | OV 需积累信誉，EV 立即生效 | PFX 或证书指纹 |
| Azure Artifact Signing | 按次 | 微软签发 | Azure 凭据 + 专用客户端工具 |

脚本支持两种凭据：

```powershell
./Scripts/windows/build-windows.ps1 -SignPfx $env:ENVBOX_SIGN_PFX        # CI：PFX 落盘
./Scripts/windows/build-windows.ps1 -SignThumbprint 3A1B...C9            # 本地：证书在用户存储
```

参数固定 `/fd SHA256 /td SHA256 /tr <RFC3161>`，签完立即 `verify /pa /all`。顺序是**先签两个 exe，再装进安装器，最后签安装器**；反过来安装器里躺的是未签名 exe。

`ENVBOX_SIGNER_THUMBPRINT`（仓库变量）会被嵌入二进制，供自更新比对签名者；没有它自更新只能跳转下载。

仓库变量 `REQUIRE_SIGNED_RELEASE_WINDOWS=true` 时，缺凭据或缺指纹直接失败。

## 分发与安装

| 产物 | 说明 |
| --- | --- |
| `EnvBox-<v>-Windows-amd64-Setup.exe` | 唯一正式分发物；每用户安装到 `%LOCALAPPDATA%\Programs\EnvBox`，免管理员 |
| `SHA256SUMS-windows-amd64.txt` | 自更新会与 GitHub 资产 digest 交叉核对 |
| `BUILD-INFO-amd64.txt` | 版本、构建号、提交、Go 版本、构建时间 |

安装器只做四件事：复制文件、建快捷方式（开始菜单与可选桌面）、提供卸载器、检测系统版本（`MinVersion=10.0.17763`）。静默安装结束后会启动 EnvBox；WebView2 不做检测，缺运行时由应用启动失败后提示。

三条原则：

1. 不做 MSIX：容器化会挡注册表直写与 `WM_SETTINGCHANGE` 广播，正好是产品的全部功能。
2. 安装器不写任何环境变量；PATH 集成尚未实现，理由见下。
3. CLI 放在 `bin\` 子目录：NTFS 大小写不敏感，两条同名 exe 会互相覆盖。

### 为什么安装器不碰 PATH

Inno 与 PowerShell 读 `HKCU\Environment\Path` 时会自动展开 `REG_EXPAND_SZ`，回写就变成 `REG_SZ`，把 `%SystemRoot%` 之类固化成绝对路径。将来实现 PATH 集成时必须走应用自己的注册表实现（保类型、去重、可撤销）。

## 运行模式

只有安装态：exe 位于 `%LOCALAPPDATA%\Programs\EnvBox\`，配置与 vault 在 `%LOCALAPPDATA%\EnvBox\`。

从源码目录运行（`go run`、直接跑 `dist\*.exe`）视为开发态：自更新被禁用（界面按钮置灰、自动检查跳过、CLI 直接拒绝），避免把开发机覆盖成发布版。

不做便携版：MCP 客户端与开机启动都引用固定绝对路径，便携目录一旦移动就断；而不写安装信息又无法在卸载时清干净 Run 键与 PATH 片段。

### 升级与卸载

- 升级：Inno 同一 `AppId` 原地覆盖，`UsePreviousAppDir=yes`；任何情况下都不删 `%LOCALAPPDATA%\EnvBox`。
- 目标位置页强制显示（`DisableDirPage=no`）：默认值 `auto` 在检测到已安装时会把整页藏掉，用户既看不到装到哪、也没法改。
- 卸载：`[UninstallRun]` 调 `bin\envbox.exe uninstall-cleanup` 清 Run 键、Shell 集成与激活快照，再删文件。
- 覆盖安装会自动关掉正在运行的 EnvBox，而且**在向导出现之前**就先关：`InitializeSetup` → 跑一次 `EnvBox.exe --quit`，那个进程只是把具名事件 `EnvBox-Quit-5C1F7C2E` 置位然后退出，真正运行的实例收到事件后自己 `Quit()`；安装器轮询单实例互斥体最多 5 秒。`PrepareToInstall` 在复制文件前再查一次，防止向导期间用户又把程序打开。
- `EnvBox.exe` 路径先取 `{app}`，取不到再读上一版卸载项里的 `Inno Setup: App Path`：向导出现前 `{app}` 未必已经指向旧目录。
- 故意**不设** `AppMutex`：那条指令会让安装器在启动时就弹"请手动关闭程序"，而它拦在 `[Code]` 之前，自动关闭代码根本没机会跑。只有`--quit` 之前的旧版本会走到"重试/取消"对话框。
- 卸载走同一套心跳：`InitializeUninstall` 里同样先等它退出，避免删到一半发现文件被占用。

### 安装界面语言

`[Languages]` 两条：`compiler:Default.isl`（英文）与 `lang\ChineseSimplified.isl`（仓库自带）。`LanguageDetectionMethod=uilanguage` + `.isl` 里的 `LanguageID=$0804` 让中文 Windows 自动用中文，其余用英文；`ShowLanguageDialog=no` 不弹语言选择页，需要强制时用 `/LANG=zh` 或 `/LANG=en`。

翻译文件是**部分翻译**：没列到的消息回落到英文，所以新增 Inno 版本时不用整份重译。文件必须存成 **UTF-8 带 BOM**（6.3 之前不认没有 BOM 的 UTF-8），`LanguageCodePage=936` 保留是因为部分消息仍会交给 ANSI API。`NameAndVersion`、`CreateDesktopIcon` 这类在 Inno 里属于 `[CustomMessages]` 而不是 `[Messages]`，放错段会静默回落成英文。

## CI

`.github/workflows/release-windows.yml` 三个 job：

| job | runner | 内容 |
| --- | --- | --- |
| `gate` | ubuntu-latest | 标签必须匹配 `^v\d+\.\d+\.\d+$` 且等于 `VERSION` |
| `build` | windows-latest | gofmt → vet → test → wails3 → Inno → 构建 → 签名 → 打安装器 |
| `publish` | ubuntu-latest | 创建或复用同一个 Release，追加 Windows 说明段，`gh release upload --clobber` |

- `wails3` 固定 `@v3.0.0`：CLI 属于构建系统，滚动升级等于同一 tag 构建结果不稳定。
- 与 macOS 共用一个 Release：谁先跑完谁创建，另一个复用；说明用 `<!-- envbox-windows-assets -->` 去重。
- 资产名保留 `amd64`：自更新按文件名精确匹配，改名等于让旧版本收不到更新。

## 发布清单

1. 更新 `VERSION` 与 `CHANGELOG.md`。
2. `go test ./...` 与 `swift test` 通过。
3. 本地 `build-windows.ps1` + `package-windows.ps1`，安装后应用配置、新开终端能读到变量。
4. 提交并打标签：`git tag v1.1.1 && git push origin main --tags`（1.1.0 已作为 macOS-only 发布，Windows 首发放到下一个版本）。
5. CI 通过后检查 Release 资产齐全、Windows 说明段存在。
6. 干净机器装 `Setup.exe`：`bin\envbox.exe describe <KEY>` 可用。
7. 装上一个版本，从「设置 → 更新」跑通整条链路。

## 首次发布前要核对

1. `wails3 generate syso` 的参数名（v3 早期改过）。
2. `ISCC.exe` 能编译 `installer/windows/envbox.iss`（本机未安装，尚未首跑）。
3. 未签名产物在干净机器上的 SmartScreen 表现。
4. `digest` 与 `SHA256SUMS` 双源是否一致。

## 失败模式

| 现象 | 原因 | 对策 |
| --- | --- | --- |
| 产物里 CLI 消失 | NTFS 大小写不敏感 | CLI 在 `bin\` 子目录 |
| CLI 无输出 / MCP 死掉 | 给 CLI 加了 `-H windowsgui` | 只有 GUI 加 |
| 高 DPI 发虚 | 缺 PerMonitorV2 清单 | `build/windows/app.manifest` + syso |
| `generate syso` 报版本不可读 | 资源版本不是四段 | `VERSION.BUILD_NUMBER` |
| `generate syso` 报 `invalid character` | PowerShell 5.1 写了 BOM | 用无 BOM 编码器写 JSON |
| 脚本中文乱码 / 解析失败 | 无 BOM 的 UTF-8 被当成 ANSI | `.ps1` 存 UTF-8 BOM |
| 应用配置后旧终端没变 | 广播只影响新进程 | `apply` 提示成功后应重开终端；广播超时时会额外说明 |
| 用户 PATH 被固化 | 有人直接改 `Path` | 只用应用内的注册表实现 |
| 签名后校验失败 | 时间戳服务不可达 | 换 `/tr` 地址 |

## 成本

- CI：gate 约 20 秒，build 约 7–10 分钟，publish 约 30 秒。
- 本地：首次全量约 3 分钟，之后改 Go 约 20 秒。
- 证书：不签名 0；Azure Artifact Signing 按次；OV/EV 按年。
