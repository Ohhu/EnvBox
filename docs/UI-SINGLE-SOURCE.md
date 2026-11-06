# UI 单源：一份界面，两个宿主

> 决策记录（2026-11-05）。目标：让 macOS 与 Windows 共用同一份界面代码，同时保留各自的系统集成。

## 结论

界面收敛到 **`shared/ui/assets`** 一份源码，两端只是"宿主 + 传输层"不同：

```
                    ┌───────────────────────────────┐
                    │  shared/ui/assets (单源 UI)      │
                    │  index.html / app.css / app.js │
                    │  tokens.css (生成)             │
                    └──────────────┬────────────────┘
                                   │
                 ┌─────────────────┴──────────────────┐
                 │            bridge.js               │
                 │  native  │   http   │    demo      │
                 └────┬─────┴────┬─────┴──────┬──────┘
                      │          │            │
              WKWebView    WebView2 (Wails)   浏览器预览
              (macOS)      (Windows)
                      │          │
   WebUIBridge (Swift)     /api/state, /api/dispatch
   → EnvBoxCore            → internal/* (Go)
```

业务逻辑仍是两端各自的原生实现（Swift Core / Go），**没有合并**；合并的只有界面像素。
两端共享的是同一个 JSON 契约：`state()` 与 `dispatch(action, payload)`。

## 已落地（本次改动）

| 文件 | 作用 |
| --- | --- |
| `shared/design/tokens.json` | 唯一设计真源：色板、圆角、间距、字号、动效 |
| `Scripts/shared/gen-design-tokens.mjs` | 生成 `shared/ui/assets/tokens.css` 与 `Sources/EnvBoxUI/Theme/DesignTokens.swift` |
| `shared/ui/assets/tokens.css` | 生成产物，勿手改 |
| `shared/ui/assets/app.css` | 共享样式（浅色/深色，全部走 CSS 变量） |
| `shared/ui/assets/app.js` | 三个视图：系统环境 / 配置详情 / 设置，含变量编辑抽屉 |
| `shared/ui/assets/icons.js` | 内嵌 SVG 图标集（SF Symbols 不可再分发，这里用同光学重量的等价图标） |
| `shared/ui/assets/bridge.js` | 三种传输：原生桥 / Wails HTTP / 浏览器 Demo，自动探测 |
| `shared/ui/assets/mock.js` | 演示数据，供预览与截图，不参与发布逻辑 |
| `Scripts/shared/preview-server.mjs` | 无宿主预览用的静态服务器 |
| `Sources/EnvBoxUI/WebUI/*.swift` | macOS 宿主：自定义 scheme 资源服务、WKWebView、JS↔Swift 桥 |
| `docs/ui-web/*.png` | 本次实拍的四个界面状态（1180×760） |

后端小改动：`ProfileView` 增加 `updatedAt`（`internal/core/model.Timestamp.ISO8601()`），
让两端都能渲染"最后修改"这个统计卡；Go 单测已通过。

## 窗口外壳（Windows）

原生标题栏和页面背景是两套材质，接缝无法消除，所以 Windows 侧改成 **frameless + 自绘标题条**，
和 macOS 的 `.hiddenTitleBar` + 顶部拖拽区对齐：

- 38px 高的透明标题条，背景就是页面的极光渐变，不再有独立标题栏
- 拖拽用 Wails 的 `--wails-draggable: drag`（页面需显式 import `/wails/runtime.js`，Wails 不会自动注入）
- 右侧三个 46×30 的窗口按钮：最小化 / 最大化 / 关闭，关闭态悬停变红；点击走 `window-minimise`、
  `window-toggle-maximise`、`window-close` 三个 dispatch action，由 `main.go` 调 Wails 窗口 API
- 双击标题条切换最大化（Wails 只在 macOS 内置这个行为）
- macOS 宿主不走 Wails，标题条只预留 78px 给红绿灯
- 保留系统阴影与 Win11 圆角（`DisableFramelessWindowDecorations` 默认 false）

代价：Windows 11 的悬停"布局"菜单（Snap Layouts）依赖原生标题栏，frameless 后没有；如需保留，
把 `Frameless` 关掉即可回到原生标题栏，页面里的按钮会自动隐藏。

## 侧栏与窗口的关系

侧栏是窗口结构的一部分，不是标题栏下面的一个区块：

```css
.shell { display: grid; grid-template-columns: 252px 1fr; grid-template-rows: 38px 1fr; }
.sidebar { grid-column: 1; grid-row: 1 / span 2; }  /* 从窗口顶边到窗口底边 */
.titlebar { grid-column: 2; grid-row: 1; }           /* 只覆盖内容区 */
.content { grid-column: 2; grid-row: 2; }
```

因此侧栏的背景和右侧分隔线一直延伸到窗口顶边，和 macOS 的全尺寸内容视图一致（红绿灯浮在侧栏上方）。
标题栏不再横跨侧栏，所以侧栏顶部 38px 单独放了一个 `--wails-draggable: drag` 的透明拖拽层，
否则那块区域拖不动窗口。

侧栏选中态是**一个**绝对定位的胶囊（`#selection-pill`），由 `positionSelection()` 移到当前行，
高度随系统行（52px）与配置行（50px）动画过渡。系统环境和配置共用同一个高亮元素，所以切换时
不会出现"两个样式不同的选中块"。

## 预览 / 截图

```bash
node Scripts/shared/preview-server.mjs        # http://127.0.0.1:4173
```

URL 参数：

- `?demo=1` 使用演示数据（不连任何后端）
- `?view=system|profiles|settings`
- `?theme=light|dark` 强制外观（默认跟随系统）

截图基线为 **1180×760**，与 macOS 窗口 `defaultSize` 一致。

## 一致性边界

| 维度 | 状态 |
| --- | --- |
| 布局、信息架构、文案、组件状态 | 100% 同源 |
| 视觉（配色/圆角/间距/字号/阴影） | 100% 同源（令牌驱动） |
| 像素 | 约 85–90%：字体度量、滚动条、`<select>`、1px 缩放、P3 色域仍由引擎决定 |
| 交互手感 | 约 80%：滚动惯性、右键菜单、键盘导航仍是浏览器语义 |
| 系统集成 | 不在共享层：红绿灯、托盘、快捷键、剪贴板、无障碍留在各自原生侧 |

字体策略：不打包字体。macOS 命中 SF，Windows 命中 Segoe UI Variable，字号/字重/行高/字距
全部走令牌，保证排版节奏一致而不是字形一致。

## 尚未完成（接入 macOS 之前的清单）

1. **AppModel 适配器**：在 `Sources/EnvBoxUI/WebUI` 里实现 `WebUIBridge`，把 14 个 action 映射到现有 `AppModel` 方法；
   目前宿主只有协议与路由，没有业务映射。
2. **入口切换**：`EnvBoxScene` 里用环境变量开关（`ENVBOX_WEB_UI=1`）在 `RootView`（SwiftUI）
   与 `WebUIView` 之间切换，保证可回退、可并行对比。
3. ~~打包资源~~：已由 `Scripts/macos/build-app.sh` 的 `cp -R shared/ui/assets "$APP/Contents/Resources/web"` 完成。
4. **平台能力补齐**：托盘弹层（`NSStatusItem` + 无边框窗口）、快捷键菜单、敏感值 45 秒清屏、
   剪贴板私有类型——这些不能由 Web 层提供，需要在宿主里保留。
5. **截图回归**：把 `docs/ui-web` 的四张图作为基线，补一个脚本在改动后重拍并比对。

## 已知风险

- macOS 上 `ultraThinMaterial` 的系统材质无法像素级复刻，共享 UI 用 `backdrop-filter` 近似；
  系统级"减少透明度"设置不会影响这层自绘材质。
- WKWebView 与 WebView2 的字体渲染差异会让同一字号看起来略有粗细差别，属于预期。
- 托盘弹层的交互（点击图标弹出、失焦收起）需要原生窗口，Web 层无法参与，届时两端行为会有差异。
