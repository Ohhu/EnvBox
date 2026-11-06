# 仓库结构

一句话：光看路径就要能回答"这段代码属于 Windows、macOS，还是两者共用"。

## 目录归属

| 路径 | 归属 | 说明 |
| --- | --- | --- |
| `shared/ui/assets/` | 两端共用 | 界面单源。Windows 从可执行文件里读，macOS 从 `Contents/Resources/web` 读 |
| `shared/ui/embed.go` | 共用内容 | 只做一件事：`//go:embed all:assets` |
| `shared/design/tokens.json` | 两端共用 | 唯一设计值来源，改完跑 `Scripts/shared/gen-design-tokens.mjs` |
| `internal/core/` | 引擎 | `model`、`cryptox`、`portable`、`apperr`、`buildinfo` |
| `internal/windows/` | Windows | 注册表、DPAPI、PowerShell、MCP、更新 |
| `cmd/windows/envbox/` | Windows | Wails v3 宿主，只做窗口与 HTTP 桥 |
| `cmd/windows/envbox-cli/` | Windows | CLI 与 MCP stdio server |
| `Sources/`、`Tests/`、`Resources/`、`Package.swift` | macOS | SwiftPM 的默认根，保持原样 |
| `build/windows/`、`installer/windows/` | Windows | 资源模板与 Inno Setup |
| `Scripts/macos/`、`Scripts/windows/`、`Scripts/shared/` | 按名字 | 平台脚本与两端共用脚本 |
| `docs/` | 共用 | 平台相关文档在文件名里带前缀 |

## 三条纪律

1. `internal/core` 不得 import `internal/windows`；反过来可以。
2. `shared/` 不 import 任何 `internal/` 包，它只提供资源。
3. Windows 专属文件要同时满足两点：目录（`internal/windows/`、`cmd/windows/`）与 `//go:build windows`。目录给读者看，build tag 给编译器看。

## 为什么不彻底对称

SwiftPM 和 Go 模块都要求自己的根，因此 `Package.swift` 与 `go.mod` 只能留在仓库根，macOS 源码也就跟着在根上。把 Swift 挪进 `platforms/macos` 要给每个脚本和 CI 传 `--package-path`；把 Go 拆成两个模块则要加 `replace` 才能让宿主引用引擎。两笔代价换来的只是视觉对称，不做。

## 新增平台时

以 Linux 为例：`cmd/linux/envbox/`、`internal/linux/`、`Scripts/linux/`，`shared/` 与 `internal/core` 不动。等到宿主多到三四个、`shared/ui/assets` 开始需要构建步骤时，再把它升级成前端工程。
