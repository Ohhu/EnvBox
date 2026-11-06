# Windows 版技术选型：用 Go 行不行

> 决策记录（2026-11-02）：结论、实测数据、待定项。

## 结论

**行，而且是最省事的一条路。** 但要把"原生"拆成两层看，否则容易选错：

| 层次 | 占工作量 | Go 的能力 | 判断 |
| --- | --- | --- | --- |
| 系统集成：用户环境变量注册表、`WM_SETTINGCHANGE` 广播、DPAPI、开机启动、单实例、剪贴板、托盘 | 约 80% 的复杂度 | 纯 Go、零 cgo；注册表、广播、DPAPI、单实例已实测；托盘已接入，剪贴板尚未实现 | 比 Swift 版更省事 |
| 加密与数据：AES-256-GCM 配置库、PBKDF2 导出、`.envbox` 互通 | 小 | 标准库直出，与 Swift 版字节级兼容 | 已用官方测试向量验证 |
| 界面 | 剩下的大头 | Go **没有**成熟的 Windows 原生控件栈 | 唯一需要选型的地方：用 WebView2，不要用原生控件从零画 |

**Windows 版 = Go 承担全部逻辑 + WebView2 渲染界面**。"原生"体现在系统集成（注册表、DPAPI、广播、DPI、单实例），不在控件像素级。

## 实测记录

本机（Windows，`go version go1.26.5 windows/amd64`，`CGO_ENABLED=0`）：

| 能力 | 结果 | 数据 |
| --- | --- | --- |
| 用户环境变量写入并回读，`REG_EXPAND_SZ` 类型保真 | 通过 | 值 `%USERPROFILE%\envbox-smoke` 原样回读 |
| `WM_SETTINGCHANGE("Environment")` 广播 | 通过 | 新起进程能拿到新值 |
| DPAPI 保护 32 字节主密钥并还原 | 通过 | 2.7 ms，密文 262 字节 |
| PBKDF2-HMAC-SHA256 官方向量（c=1 / c=2） | 通过 | 与 RFC 向量逐字节一致 |
| PBKDF2 600k 轮（现有导出强度） | 通过 | 中位数 78.9 ms（Swift/CommonCrypto 同参数通常 250–600 ms） |
| AES-256-GCM `nonce‖ct‖tag` 封装 | 通过 | 长度与 CryptoKit `.combined` 完全一致 |
| 纯 Go 单文件构建 | 通过 | 1.86 MB（冒烟测试，含注册表/DPAPI/GCM） |

本机工具链：WebView2 Runtime 156.0.4314.58 已装，`gcc` 缺失——依赖 cgo 的 UI 方案（Fyne、GTK）需先装 mingw，Wails 在 Windows 上是纯 Go，不受影响。

复现方式：

```powershell
cd tools\devseed
go run .
```

（受限沙箱下注册表一项会打印 `SKIP`，其余各项照常执行。）

## 界面路线对比

| 方案 | 观感原生度 | 工作量 | 产物 | 外部依赖 | 交叉编译 | 判断 |
| --- | --- | --- | --- | --- | --- | --- |
| **Wails v3**（Go + WebView2） | 约 85%：用 HTML/CSS 对着 `docs/*.png` 复刻 | 中 | 12–15 MB 单 exe | WebView2 Runtime（Win11 内置，Win10 21H2+ 基本都有） | 纯 Go，可交叉编译 | **推荐** |
| Wails v2 | 同 v3 | 中 | 同上 | 同上 | 同上 | 保守备选；v3.0.0 已稳定，v2 只做关键修复 |
| `lxn/walk`（真 Win32 控件） | 控件 100% 原生，但卡片、毛玻璃、Toast、侧栏都得自绘 | 大（+4–6 天） | 约 6 MB | 无 | 纯 Go | 设计稿要重做，不建议 |
| Fyne | 自绘，偏移动端观感 | 中 | 约 20 MB | 需 cgo + mingw | 不可 | 不建议 |
| C# + WinUI 3 | 100% | 中 | 60 MB+ 自包含，或依赖 .NET | .NET 运行时 | 不可 | 仅在"必须原生控件"时选，且那时不要用 Go |

Wails v3 支持系统托盘与多窗口，接入后可省掉 macOS 侧 `NSStatusItem` 那部分的自研成本。

## 功能映射（macOS → Windows）

| 能力 | macOS 现状 | Windows 实现 |
| --- | --- | --- |
| 读取真实环境 | 起 `zsh -ilc env`，带超时与回退 | 读 `HKCU\Environment`（HKLM 未实现），`REG_EXPAND_SZ` 用 `ExpandEnvironmentStrings` 展开。Windows 没有"登录 Shell"概念，这块反而更简单：无超时、无副作用 |
| 应用配置 | `launchctl setenv` | `RegSetValueEx` + 广播 `WM_SETTINGCHANGE("Environment")` |
| 清理旧变量 | `launchctl unsetenv` | `RegDeleteValue` |
| 空值 vs 未定义 | `unsetenv` | 必须区分：`REG_SZ ""` = 已定义且为空，删除值 = 未定义 |
| 主密钥 | Keychain（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`） | DPAPI `CryptProtectData`（CurrentUser，`CRYPTPROTECT_UI_FORBIDDEN`），密文存 `%LOCALAPPDATA%\EnvBox\vault.key` |
| 配置库 | AES-256-GCM + Keychain | 同算法同 AAD（`EnvBox.Vault.v1\|keyID=…`），`vault.envbox` 结构直接复用 |
| 导入导出 | PBKDF2-HMAC-SHA256 600k + AES-256-GCM | 同参数；`.envbox` 双向可用：界面导出，`envbox import <file.envbox> --password <密码>` 导入 |
| Shell 集成 | `~/.zshrc` 受管片段 + `active.zsh` | PowerShell `$PROFILE` 受管片段；cmd 的 AutoRun 尚未实现；Windows Terminal 直接读注册表，无需处理 |
| 托盘快速切换 | `NSStatusItem` | 已实现：Wails v3 Systray，菜单列全部配置、勾选当前项、停用、退出 |
| MCP stdio server | Swift `envbox` helper | 同一份 Go 代码编出 `envbox.exe`（约 5 MB 单文件），比 macOS 侧更省事 |
| 敏感剪贴板 | `NSPasteboard` 私有类型 + 45 秒清空 | 未实现（计划用 `ExcludeClipboardContentFromMonitorProcessing` + 45 秒清空） |
| 单实例 | — | `CreateMutexW`，第二个实例静默退出 |

## Windows 语义差异（Go 全都能处理，但必须写对）

1. **变量名大小写不敏感**：内部统一 `ToUpper` 作键，展示用原名。
2. **PATH 特殊**：不要当普通变量覆盖；拼接要保留原有段，注意环境块 32767 字符上限。
3. **类型保真**：`REG_EXPAND_SZ` 必须原样写回，否则 `%USERPROFILE%` 之类会被固化成绝对路径。
4. **广播只影响之后新起的进程**：已开的终端、资源管理器要重启——这正好对应现有 README 的"已知边界"。
5. **注册表重定向**：`HKLM\SOFTWARE` 有 WOW6432Node 分支；`HKCU\Environment` 不被重定向，但仍建议显式 `KEY_WOW64_64KEY`。
6. **应用清单**：必须声明 PerMonitorV2 DPI 感知与 `asInvoker`，否则高 DPI 下 WebView 发虚。
7. **SmartScreen**：未签名 exe 首次运行会被拦；需要 Authenticode 证书（OV 要积累信誉，EV 立即生效）。
8. **机器级变量**（HKLM）需要管理员权限与提权清单，默认只做用户级。
9. **中文用户名 / 非 ASCII 路径**：Go 全 UTF-8 处理，无坑（C 系方案的老问题）。

## 项目结构（与现有 Swift 源码并列，不改 macOS 侧）

UI 路线已定：**Wails v3**。理由不是性能，而是这个产品的界面是"复刻 `docs/*.png` 那套卡片/侧栏/毛玻璃"，
在 HTML/CSS 里是常规工作，在 `lxn/walk` 里是几千行自绘；真·原生控件这条诉求应该换 C#，而不是让 Go 硬画。

```text
go.mod                       根模块；引擎与 Windows 实现同模块，宿主只多一个 Wails 依赖
internal/core/               与宿主无关的引擎：model、cryptox、portable、apperr、buildinfo
internal/windows/            Windows 实现：注册表、配置库、PowerShell、MCP、更新
cmd/windows/envbox/          GUI 宿主（Wails v3 + /api/state、/api/dispatch 两个 JSON 端点）
cmd/windows/envbox-cli/      CLI + MCP stdio server（安装到 <install>\bin\envbox.exe）
shared/ui/assets/            界面单源，Windows 与 macOS 共用同一批文件
```

完整归属见 [ARCHITECTURE.md](ARCHITECTURE.md)。

### 已完成并可验证的部分

| 包 | 状态 | 验证方式 |
| --- | --- | --- |
| `internal/core/cryptox` | 完成 | PBKDF2 官方测试向量（c=1/2/4096）、AES-GCM 篡改检测 |
| `internal/core/model` | 完成 | 时间戳与 Swift 编码逐字符一致、指纹性质测试、键名规则 |
| `internal/core/portable` | 完成 | 导出→导入往返、错密码、密文篡改、迭代次数降级、AAD 钉死 |
| `internal/windows/vault` | 完成 | 磁盘上无明文、密钥丢失/不匹配报错、原子写 |
| `internal/windows/winsys` | 完成 | 注册表往返、`REG_EXPAND_SZ` 类型保真、空值与缺失区分、Apply 清理旧键、Run 键、DPAPI、单实例 |
| `internal/windows/appenv` | 完成 | describe 不含明文、大小写不敏感查找、环境合并去重、exec 退出码与输出截断 |
| `internal/windows/apply` | 完成（单测） | 记录 activeProfile/appliedKeys/指纹、切换时下发旧键、注册表失败不写库、广播失败只警告、deactivate 清空 |
| `internal/windows/shell` | 完成 | active.ps1 引号转义（单引号加倍）、`$PROFILE` 受管片段幂等安装/卸载、标记残缺时拒绝修改 |
| `internal/windows/mcp` | 完成 | initialize / tools/list / tools/call、通知不回复、策略关闭时拒绝、requiredKeys 前置校验、reveal 需显式开启 |
| `internal/windows/settings` | 完成 | 更新开关默认值与归一化、`DueForCheck` 时间窗口、原子写 |
| `internal/windows/update` | 完成 | 发布解析、版本比较、双源摘要、Authenticode 指纹、待安装记录 |
| `cmd/windows/envbox-cli` | 完成 | `version` / `profiles` / `describe` / `apply` / `deactivate` / `exec` / `mcp` / `policy` / `shell` / `update` / `import` / `uninstall-cleanup`（`update` 与界面共用「开发态拒绝」门禁） |
| `cmd/windows/envbox` | 完成 | Wails v3 窗口、单实例、JSON API；三屏界面已截图验证 |

三个只有在本机才会踩到的坑（都已修）：

- **`go build -o out\envbox.exe` 和 `-o out\EnvBox.exe` 是同一个文件**（理由见 [WINDOWS-BUILD-RELEASE.md](WINDOWS-BUILD-RELEASE.md) 分发一节），
  两个二进制会互相覆盖。构建脚本输出到不同目录或不同名前缀，不要在同一个目录里靠大小写区分。
- **读路径不能建目录**：`LocalAppDataDir()` 原本顺手 `MkdirAll`，导致"还没有配置库"的机器上
  `envbox profiles` 直接报 `mkdir ... Access is denied`。现已拆成 `LocalAppDataDir()`（只算路径）
  与 `EnsureConfigDir()`（写之前才建），缺目录等于"空配置库"。
- **`SendMessageTimeoutW(HWND_BROADCAST, …)` 是按窗口逐个等超时的**：桌面上几十个窗口、其中几个不响应时，
  一次广播就能把"应用配置"卡到分钟级（实测把 E2E 拖成超时）。UI 路径改用 `SendNotifyMessageW`
  （异步、立即返回；全仓只用这一个实现），`apply` 外层另加 5 秒硬超时兜底。

开发态开关（仅 `buildinfo.Channel != "production"` 生效，发布版忽略）：
`ENVBOX_CONFIG_DIR`（配置库/mcp.json/active.ps1 位置）、`ENVBOX_ENV_KEY`（环境变量注册表键）、
`ENVBOX_SKIP_BROADCAST`（跳过广播）、`ENVBOX_START_VIEW`（指定首屏，截图用）。`tools/devseed` 用它生成演示配置库。

## 工期（单人）

- 核心（winsys + vault + portable + CLI/MCP + 单元测试）：2–3 个工作日
- 界面（三屏 + 侧栏 + 编辑器 sheet + 托盘菜单 + 明暗主题）：3–4 个工作日
- 打包、签名、CI、文档：1 个工作日

合计：**6–8 个工作日**到功能对齐；如果改成 `lxn/walk` 原生控件路线，界面部分再加 4–6 天，且设计稿要重做。

## 已定事项

| 决定 | 结论 |
| --- | --- |
| 语言 | **Go**（见 [WINDOWS-LANG-GO-VS-RUST.md](WINDOWS-LANG-GO-VS-RUST.md)） |
| 界面 | **Wails v3 + 内嵌 HTML/CSS/JS**（`shared/ui/assets`），不用 `lxn/walk` 自绘原生控件 |
| 架构 | **仅 x64（amd64）**，不发 arm64 |
| 分发形态 | **只有安装器**（Inno Setup，每用户、免管理员），不做便携 zip、不做 MSIX |
| 自动更新 | **做**，渠道 = 本仓库 GitHub Releases，见 [WINDOWS-UPDATE.md](WINDOWS-UPDATE.md) |
| 安装器边界 | 不写环境变量、不写自启动、不装 Shell 集成——这三项由 App 自己管理 |

仍在等的一项：

1. **签名证书**：是否有预算；没有的话首次运行会遇到 SmartScreen 拦截，自更新也只能"跳转下载"（缺可嵌入的签名指纹）。

> 注意自动更新带来了本产品第一批出站流量。macOS 版的"不联网、无遥测"承诺在 Windows 版要改写成
> "仅在你启用更新检查时访问 GitHub Releases API，可完全关闭"，别让文档与实现打架。

## 语言再评估（Go vs Rust）

按性能、安全、UI 三个维度重新比过一轮，结论不变：Go 继续。要点：

- **性能不是决策变量**——PBKDF2 600k 实测 79 ms（Rust 预期 35–55 ms），AES-GCM 已是 3.5 GB/s 硬件地板，启动与内存被 WebView2 支配。
- **安全 Rust 略强**（`zeroize`/`secrecy` 能保证密钥擦除，Go 不能），但 EnvBox 没有网络与富文本解析，真实威胁是同用户进程与泄露面；而"零第三方依赖、可审计"这条 Go 赢得更多。
- **UI 两边同构**——都是 WebView2 + 前端，差在增量编译速度（Go 1–2 s vs Rust 5–30 s）与 Tauri 更成熟的打包。

完整评分、加权结论、Go 侧 8 条密钥加固清单与"什么条件下改选 Rust"见
[WINDOWS-LANG-GO-VS-RUST.md](WINDOWS-LANG-GO-VS-RUST.md)。

## 编译与发布

已落地：[build-windows.ps1](../Scripts/windows/build-windows.ps1)、[package-windows.ps1](../Scripts/windows/package-windows.ps1)、
[envbox.iss](../installer/windows/envbox.iss)、[release-windows.yml](../.github/workflows/release-windows.yml)，
流程说明见 [WINDOWS-BUILD-RELEASE.md](WINDOWS-BUILD-RELEASE.md)。

打包阶段暴露了一个只有到 Windows 才会碰上的坑：NTFS 大小写不敏感，GUI 的 `EnvBox.exe` 与 CLI 的
`envbox.exe` 不能同目录共存（第一版打包脚本因此让产物里的 CLI 凭空消失）。现在 CLI 固定在 `bin\` 子目录，
MCP 客户端指向 `<安装目录>\bin\envbox.exe mcp`。

## 本地开发注意

本机 Go 的模块缓存与构建缓存默认在 workspace 之外（`%USERPROFILE%\go\pkg\mod`、`%LOCALAPPDATA%\go-build`）。在当前受限沙箱里需要显式指定：

```powershell
$env:GOCACHE='<workspace>\.tmp\gocache'
$env:GOMODCACHE='<workspace>\.tmp\gomod'
```

在普通终端里开发不受此限制。
