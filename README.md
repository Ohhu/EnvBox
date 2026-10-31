# EnvBox

**EnvBox** 是一个原生 macOS 环境变量管理器。它读取真实的登录 Shell 环境（Zsh / Bash），让你把变量整理成多个可加密保存的配置，并在菜单栏或主窗口中快速切换。

<p align="center">
  <img src="docs/icon.png" width="96" alt="EnvBox icon">
</p>

<p align="center">
  <img src="docs/envbox-light.png" alt="EnvBox 主界面（演示数据）" width="100%">
</p>

## 功能

- **实时系统环境**：读取 App 进程与登录 Shell 环境，显示变量来源与敏感标记。
- **可编辑配置**：变量名、值、启用状态、敏感标记和备注均可编辑，支持搜索与筛选。
- **加密配置库**：本地配置库使用 AES-256-GCM 加密，256 位随机密钥存入 macOS Keychain，磁盘上只有密文。
- **配置快速切换**：主窗口一键应用，菜单栏常驻图标可快速切换不同配置。
- **加密导入导出**：使用独立密码保护的可移植 `.envbox` 文件。
- **macOS 原生体验**：SwiftUI、原生材质、跟随系统明暗外观、减少动态效果支持、键盘快捷键。
- **隐私优先**：无网络请求、无遥测、无第三方 SDK；敏感值默认遮盖；敏感剪贴板 45 秒自动清除。
- **正式版本自动发布**：GitHub Actions 仅在严格 `vMAJOR.MINOR.PATCH` 标签上构建并发布 arm64 二进制。

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
- Apple Silicon Mac（arm64）
- 从源码构建需要 Xcode 16+ 或 Swift 6 toolchain（测试使用 Swift Testing）

## 安装

从 [Releases](https://github.com/Ohhu/EnvBox/releases) 下载最新 `EnvBox-x.y.z-macOS-arm64.dmg`，拖入 Applications 即可。

如果首次启动被系统拦截，请在 Finder 中右键 App 并选择“打开”。

## 使用

### 读取环境

首次启动会读取当前进程环境，并额外启动一次非交互式登录 Shell（优先使用 `$SHELL` 中的 Zsh/Bash，否则回退到 `/bin/zsh`）读取 `.zprofile`、`.zshrc` 或 `.bash_profile` 中导出的变量。读取失败时会回退到进程环境，并在界面提示。

读取登录 Shell 会执行你自己的 Shell 启动文件。EnvBox 只读取 `env` 输出，不会执行或求值环境变量内容。若你不想运行启动文件，可在设置中关闭“读取登录 Shell 环境”。

### 创建与编辑配置

在系统环境页面点击“保存为配置”，或在侧边栏点击 `+` 创建空配置。变量支持启停、敏感标记、备注和搜索。所有修改自动加密保存。

### 应用配置

点击“应用到此 Mac”后，EnvBox 会：

1. 把启用的变量写入当前用户的系统环境；
2. 清理上一个配置写入、但新配置不再包含的变量；
3. 如果已启用 Shell 集成，生成 `~/.envbox/active.zsh`（权限 `0600`），供登录 Shell 加载。

已经运行的终端和 App 不会改变。新启动的 App 会读取新的系统环境；新开的 Zsh 终端需要在设置中启用一次 Shell 集成，EnvBox 会向 `~/.zshrc` 写入带标记的受管理片段：

```zsh
# >>> EnvBox shell integration >>>
if [ -f "$HOME/.envbox/active.zsh" ]; then
  source "$HOME/.envbox/active.zsh"
fi
# <<< EnvBox shell integration <<<
```

移除集成会删除该 `.zshrc` 片段和明文 `~/.envbox/active.zsh`，但不会清除已应用的系统环境变量；重新启用集成时会根据当前配置重建激活脚本。修改 `.zshrc` 前会备份到 `~/.envbox/backups/`（最多保留 5 份），若受管理标记不完整则拒绝写入。

### MCP

设置 → MCP 打开开关后，客户端可用 `EnvBox.app/Contents/Helpers/envbox` 作为 MCP 服务器（stdio）：

| 工具 | 作用 |
| --- | --- |
| `env_describe` | 变量名、长度、指纹、代际 |
| `env_exec` | 在最新配置环境中执行命令，变量在子进程内展开 |
| `env_reveal` | 返回明文；默认关闭 |

设置页切换客户端后可分别复制 JSON 或提示词。命令行等价物：

```bash
envbox mcp
envbox describe BAIDU_COOKIES
envbox exec -- curl -H "Cookie: $BAIDU_COOKIES" https://example.com
envbox reveal-policy --allow
```

### 导入与导出

- 导出时可选择单个配置或全部配置，必须设置至少 8 个字符的密码。
- 文件只包含密文；密码不会保存，丢失后无法恢复。
- 导入只新增配置，不覆盖现有配置；同名配置自动重命名。
- 导入文件有大小、配置数量和变量数量上限，防止畸形文件耗尽资源。

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

# arm64 + DMG + ZIP
VERSION=1.0.0 ./Scripts/build-app.sh
VERSION=1.0.0 ./Scripts/package-release.sh
```

脚本默认使用 PATH 中的 `swift`。如需指定工具链：

```bash
SWIFT_BIN=/path/to/swift ./Scripts/build-app.sh
```

## 发布

仅严格 `vMAJOR.MINOR.PATCH` 标签会触发构建；其他标签只运行 gate，不编译。

```bash
# VERSION 必须与标签一致
echo 1.0.0 > VERSION
git add VERSION
git commit -m "Release 1.0.0"
git tag v1.0.0
git push origin main --tags
```

详细发布流程、可选签名/公证与 Secrets 配置见 [docs/RELEASE.md](docs/RELEASE.md)。

## 项目结构

```text
Sources/
  EnvBoxCore/     加密、Keychain、配置库、Shell 读取、launchctl 应用、MCP 与激活环境
  EnvBoxUI/       SwiftUI 界面、菜单栏、设置、导入导出交互
  EnvBox/         应用入口
  EnvBoxHelper/   envbox 命令行与 MCP 服务器
Tests/
  EnvBoxCoreTests/
Scripts/          图标、构建、打包、公证、开发运行
Resources/        Info.plist、entitlements、AppIcon.icns
docs/             README 截图、发布说明与图标
.github/workflows/release.yml
```

## 已知边界

- 应用配置无法修改已经运行的进程环境；已打开的终端窗口与 agent 需重新打开，或经 MCP 读取。
- 自动 Shell 集成目前仅支持 Zsh；其他 Shell 可手动 `source ~/.envbox/active.zsh`。
- 系统环境变量在重启后可能丢失；EnvBox 默认在启动时恢复当前配置。
- 配置文件密码无法找回。
- 首次保存时 macOS 可能请求访问 Keychain。拒绝时保存会失败，EnvBox 不会明文保存。
- 应用配置失败时会尝试清理本次写入；必要时重新应用。

## 许可证

[MIT](LICENSE) © 2026 Ohhu
