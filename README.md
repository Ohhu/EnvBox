# EnvBox

**EnvBox** 是一个原生 macOS 环境变量管理器。它读取真实的登录 Shell 环境（Zsh / Bash），让你把变量整理成多个可加密保存的配置，并在菜单栏或主窗口中快速切换。

<p align="center">
  <img src="docs/icon.png" width="96" alt="EnvBox icon">
</p>

<p align="center">
  <img src="docs/envbox-light.png" alt="EnvBox 主界面（使用演示数据）" width="100%">
</p>

> 截图使用内置演示数据，不包含真实环境变量。

## 功能

- **实时系统环境**：启动时异步读取 App 进程与登录 Shell 环境，展示变量来源、耗时和敏感变量。
- **可编辑配置**：变量名、值、启用状态、敏感标记和备注均可编辑，支持搜索与筛选。
- **加密配置库**：本地配置库使用 AES-256-GCM 加密，256 位随机密钥存入 macOS Keychain，磁盘上只有密文。
- **配置快速切换**：主窗口一键应用，菜单栏常驻图标可快速切换不同配置。
- **加密导入导出**：使用独立密码保护的可移植 `.envbox` 文件；PBKDF2-HMAC-SHA256 600,000 次迭代 + AES-256-GCM。
- **macOS 原生体验**：SwiftUI、原生材质、跟随系统明暗外观、减少动态效果支持、键盘快捷键。
- **隐私优先**：无网络请求、无遥测、无第三方 SDK；敏感值默认遮盖；敏感剪贴板 45 秒自动清除。
- **正式版本自动发布**：GitHub Actions 仅在 `vMAJOR.MINOR.PATCH` 正式标签上构建、签名、公证并发布通用二进制。

<details>
<summary><strong>更多界面截图：系统环境 / 暗色模式 / 加密导出</strong></summary>

<br>

**系统环境快照**

<img src="docs/envbox-system.png" alt="EnvBox 系统环境页面（演示数据）" width="100%">

**暗色模式**

<img src="docs/envbox-dark.png" alt="EnvBox 暗色模式（演示数据）" width="100%">

**加密导出**

<p align="center">
  <img src="docs/envbox-transfer.png" alt="EnvBox 加密导出（演示数据）" width="620">
</p>

</details>

## 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon 或 Intel Mac
- 从源码构建需要 Xcode 16+ 或 Swift 6 toolchain（测试使用 Swift Testing）

## 安装

从 [Releases](https://github.com/Ohhu/EnvBox/releases) 下载最新 `EnvBox-x.y.z-macOS-universal.dmg`，拖入 Applications 即可。

发布是否完成 Developer ID 签名/公证取决于仓库 Secrets 配置。未公证的构建首次启动时需要在 Finder 中右键 App 并选择“打开”。

## 使用

### 读取环境

首次启动会读取当前进程环境，并额外启动一次非交互式登录 Shell（优先使用 `$SHELL` 中的 Zsh/Bash，否则回退到 `/bin/zsh`）读取 `.zprofile`、`.zshrc` 或 `.bash_profile` 中导出的变量。登录 Shell 启动有 5 秒超时，失败时会回退到进程环境并在界面提示。

读取登录 Shell 会执行你自己的 Shell 启动文件，这是获得真实终端环境的必要代价。EnvBox 只读取 `env` 输出，不会执行或求值环境变量内容。若你不想运行启动文件，可在设置中关闭“读取登录 Shell 环境”。

### 创建与编辑配置

在系统环境页面点击“保存为配置”，或在侧边栏点击 `+` 创建空配置。变量支持启停、敏感标记、备注和搜索。所有修改自动加密保存。

### 应用配置

点击“应用到此 Mac”后，EnvBox 会：

1. 通过 `launchctl setenv` 把启用的变量写入当前用户 launchd 环境；
2. 清理上一个配置写入、但新配置不再包含的变量；
3. 如果已启用 Shell 集成，生成 `~/.envbox/active.zsh`（权限 `0600`），供登录 Shell 加载。

已经运行的终端和 App 不会改变。新启动的 App 会读取 launchd 环境；新开的 Zsh 终端需要在设置中启用一次 Shell 集成，EnvBox 会向 `~/.zshrc` 写入带标记的受管理片段：

```zsh
# >>> EnvBox shell integration >>>
if [ -f "$HOME/.envbox/active.zsh" ]; then
  source "$HOME/.envbox/active.zsh"
fi
# <<< EnvBox shell integration <<<
```

移除集成会删除该 `.zshrc` 片段和明文 `~/.envbox/active.zsh`，但不会删除已应用的 launchd 变量；重新启用集成时会根据当前配置重建激活脚本。修改 `.zshrc` 前会备份到 `~/.envbox/backups/`（最多保留 5 份），若受管理标记不完整则拒绝写入。

### 导入与导出

- 导出时可选择单个配置或全部配置，必须设置至少 8 个字符的密码。
- 文件只包含密文；密码不会保存，丢失后无法恢复。
- 导入只新增配置，不覆盖现有配置；同名配置自动重命名。
- 文件读取最大 20 MB，解密后的变量值总量最大 8 MB，并限制配置数与变量数，防止畸形文件导致资源耗尽。

## 安全模型

| 数据 | 保护方式 |
| --- | --- |
| 本地配置库 | AES-256-GCM；随机 256 位密钥存于登录 Keychain；文件权限 `0600` |
| 导出文件 | PBKDF2-HMAC-SHA256（600,000 次）+ AES-256-GCM；独立密码 |
| 敏感值展示 | 默认遮盖，可逐项显示；复制后标记 `org.nspasteboard.ConcealedType`，并可选 45 秒自动清空剪贴板 |
| Shell 激活文件 | 权限 `0600`，内容为明文（Shell 必须能读取） |
| 网络 | 不包含任何网络代码或第三方 SDK |

完整威胁模型与已知边界见 [SECURITY.md](SECURITY.md)。

## 从源码构建

```bash
git clone https://github.com/Ohhu/EnvBox.git
cd EnvBox

# 单元测试
swift test

# 构建当前架构的 .app（开发用）
./Scripts/build-app.sh
open dist/EnvBox.app

# 通用二进制 + DMG + ZIP
UNIVERSAL=1 VERSION=1.0.0 ./Scripts/build-app.sh
VERSION=1.0.0 ./Scripts/package-release.sh
```

脚本默认使用 PATH 中的 `swift`。如需指定工具链：

```bash
SWIFT_BIN=/path/to/swift ./Scripts/build-app.sh
```

应用图标由 `Scripts/make-icon.swift` 生成，生成的 `Resources/AppIcon.icns` 会随仓库提交。

## 发布流程

只有正式语义化版本标签会触发完整构建：

```bash
# VERSION 必须与标签一致
echo 1.0.0 > VERSION
git add VERSION
git commit -m "Release 1.0.0"
git tag v1.0.0
git push origin main --tags
```

`.github/workflows/release.yml` 的行为：

- 仅监听 `v*` 标签；普通分支推送和 Pull Request 不会触发构建。
- 先运行轻量 gate：非 `vMAJOR.MINOR.PATCH` 标签（例如 `v1.0.0-beta`）直接跳过，不编译。
- 正式标签还会校验 `VERSION` 与标签一致。
- 构建 arm64 + x86_64 通用 App、运行单元测试、生成 DMG/ZIP 和 SHA256。
- 个人仓库默认允许 unsigned 发布：未配置签名 Secrets 时生成 ad-hoc 包，Release 说明会明确标注；不要求付费 Apple Developer 账号。
- 如需严格发布，设置仓库变量 `REQUIRE_SIGNED_RELEASE=true`，此时缺少 Developer ID / 公证凭据会直接失败。配置签名 Secrets 后会自动导入证书、签名并公证 App 和 DMG。
- 通过 GitHub CLI 创建 Release 并上传产物。
- `release` Environment 可配置 required reviewers / 受保护 tag，进一步限制谁可以发布。

### 发布 Secrets（可选；需要无 Gatekeeper 警告的分发时配置）

| Secret | 用途 |
| --- | --- |
| `MACOS_CERTIFICATE` | Developer ID Application 证书的 base64 编码 `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串密码（可随机） |
| `APPLE_ID` | Apple 公证账号 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App 专用密码 |

个人使用无需配置以上 Secrets：默认会发布 ad-hoc 构建，用户首次打开需右键 → 打开。若你希望强制签名/公证，设置仓库变量 `REQUIRE_SIGNED_RELEASE=true` 并配置全部 Secrets；此时缺项会让 workflow 失败，而不是悄悄发布未签名包。建议在 GitHub 仓库设置中为 `release` Environment 添加 required reviewers，并保护 `v*` 标签。

## 项目结构

```text
Sources/
  EnvBoxCore/     加密、Keychain、配置库、Shell 读取、launchctl 应用
  EnvBoxUI/       SwiftUI 界面、菜单栏、设置、导入导出交互
  EnvBox/         应用入口
Tests/
  EnvBoxCoreTests/
Scripts/          图标、构建、打包、公证、开发运行
Resources/        Info.plist、entitlements、AppIcon.icns
docs/             README 截图、发布说明与图标
.github/workflows/release.yml
```

## 已知边界

- 应用配置无法修改已经运行的进程环境，这是 POSIX/macOS 的限制。
- 自动 Shell 集成目前仅支持 Zsh；其他 Shell 可手动 `source ~/.envbox/active.zsh`。
- launchd 变量在重启后可能丢失；EnvBox 默认在启动时恢复当前配置。
- 配置文件密码无法找回，这是有意的安全设计。
- 首次保存（或签名身份变化后）macOS 可能请求访问 Keychain。拒绝时保存会失败，EnvBox 不会降级为明文保存；正式发布应使用稳定的 Developer ID 签名。
- 若应用配置失败，EnvBox 会尝试回收本次可能写入的变量；极少数情况下仍建议重新应用或手动检查 launchd 环境。
- 应用未启用 App Sandbox（需要写 `~/.zshrc`、启动 `launchctl` 与访问 Keychain），通过 Hardened Runtime 和最小权限签名。

## 许可证

[MIT](LICENSE) © 2026 Ohhu
