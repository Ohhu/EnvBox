# EnvBox macOS ↔ Windows 功能对齐审查

基准：macOS（`Sources/EnvBoxUI`、`Sources/EnvBoxCore`）。对照：Windows（`cmd/windows/envbox`、`internal/windows`、`shared/ui`）。
方法：先由子代理初查，再对每条结论逐行复核；被复核推翻的判断记在文末「复核修正」，正文只保留成立的部分。证据为 `file:line`。

## 一、Windows 缺失的能力

| 能力 | macOS | Windows 现状 | 差距 | 证据 |
| --- | --- | --- | --- | --- |
| 首次应用的确认流程 | 第一次 apply 弹确认 sheet，确认后写 `hasCompletedFirstApply`，之后才直接应用 | 直接写 HKCU，字段 `hasCompletedFirstApply` 在模型里存在但没有任何读取方 | 缺失 | Sources/EnvBoxUI/AppModel.swift:664,711；internal/core/model/profile.go:131 |
| 一键收回全部明文 | 菜单「隐藏所有敏感值」+ 设置项 `concealSensitiveValues`，清空所有已展开状态 | 系统页有整体开关、行内有逐行开关；配置页只有逐行；没有全局动作与设置项 | 部分实现 | Sources/EnvBoxUI/AppModel.swift:390-395,987；shared/ui/assets/app.js:312,335 |
| 敏感值相关的两个设置开关 | `concealSensitiveValues`、`autoClearSensitiveClipboard` 均可关 | 设置文件只有更新频率一段，两项行为都已内置但不可配置 | 部分实现 | Sources/EnvBoxCore/Models/EnvProfile.swift:94-95；internal/windows/settings/settings.go:44-46 |
| 变量编辑器「保存并继续」 | 保存后留在编辑器里继续录入下一个变量 | 只有保存并关闭 | 缺失 | Sources/EnvBoxUI/Sheets/VariableEditorSheet.swift:245；shared/ui/assets/app.js:954-957 |
| 「在资源管理器中显示」配置库目录 | 设置页与菜单可定位库目录 | 无对应命令 | 缺失 | Sources/EnvBoxUI/Views/SettingsView.swift:235；cmd/windows/envbox/service.go:251-289 |
| 快捷键 | Cmd+N / Cmd+O / Cmd+R / Cmd+Return 等 | 只有 Enter 提交、Esc 关闭，没有任何 Ctrl/Alt 快捷键 | 缺失 | Sources/EnvBoxUI/EnvBoxScene.swift:56-97；shared/ui/assets/app.js:1178-1199 |

## 二、同名能力的行为差异

| 能力 | macOS | Windows | 差距 | 证据 |
| --- | --- | --- | --- | --- |
| 配置名重复 | 自动追加序号，忽略大小写与变音符号 | 直接报「配置名重复」 | 行为不同 | Sources/EnvBoxCore/Support/Validation.swift:99-116；internal/core/model/profile.go:329；shared/ui/assets/app.js:803 |
| 备注超长 | 校验时报错 | `Normalized()` 先截断到 500，`ValidateProfile` 的超长分支因此永远不会触发（静默截断） | 行为不同 | Sources/EnvBoxCore/Support/Validation.swift:59；internal/core/model/profile.go:246,253 |
| 系统变量搜索 | 匹配 key + value | 只匹配 key | 行为不同 | Sources/EnvBoxUI/AppModel.swift:317-329；shared/ui/assets/app.js:330 |
| 系统变量的敏感判定 | 只看名字（`EnvironmentSensitivity.isSensitive`），配置里勾了敏感但名字看不出来的变量照样明文 | 名字启发式 **或** 任一配置把该 key 标为敏感；后者更接近用户意图 | Windows 更严，macOS 待跟进 | Sources/EnvBoxCore/Models/EnvironmentVariable.swift:55,110；cmd/windows/envbox/service.go:763-795 |
| MCP `env_reveal` 返回体 | `{available,key,value,generation}`，未启用/不可用时也有明确结构 | `{key,value}` 或 `{key,missing}`，没有 `available`/`generation` | 行为不同 | Sources/EnvBoxCore/MCP/MCPToolHandlers.swift:132-146；internal/windows/mcp/tools.go:182-200 |
| 托盘 / 菜单栏 | 菜单栏常驻项 + 快捷动作 | 托盘有配置列表、应用、停用、退出；没有快捷键，也没有「隐藏所有敏感值」等动作 | 部分实现 | Sources/EnvBoxUI/EnvBoxScene.swift:26,47-97；cmd/windows/envbox/tray.go:70-100 |
| 非法图标标识 | `symbol` 超过 80 字节视为非法归档 | 保存时不校验 | 缺失 | Sources/EnvBoxCore/Support/Validation.swift:61；internal/core/model/profile.go:246-287 |

## 三、已对齐（复核确认）

| 能力 | 两侧一致之处 | 证据 |
| --- | --- | --- |
| 校验上限 | 100 配置 / 500 变量 / 512KB 单配置 / 8MB 聚合 / 20MB 库 / 5000 变量 / key ≤128 / 值 ≤32KB / 名 ≤60 / 备注 ≤500 | internal/core/model/profile.go:23-32；Sources/EnvBoxCore/Support/Validation.swift:4-10 |
| key 规则、重复 key、变量 ID 唯一、值含 NUL | 规则与报错一致 | internal/core/model/profile.go:267-280；Sources/EnvBoxCore/Support/Validation.swift:14-53 |
| 排序 | 变量按 key、配置按名称 | cmd/windows/envbox/service.go:197；internal/core/model/profile.go:109 |
| 配置内变量搜索 | key + value + note | shared/ui/assets/app.js:258 |
| 变量筛选维度 | 全部 / 已启用 / 已停用 / 敏感 | shared/ui/assets/app.js:246；Sources/EnvBoxUI/AppModel.swift:25-37 |
| 删除配置的破坏性确认 | 带配置名的二次确认 | shared/ui/assets/app.js:1079-1092 |
| 敏感值掩码与逐行 reveal | 掩码 + 行内眼睛 + 系统变量可单独展开 | shared/ui/assets/app.js:279,335；Sources/EnvBoxUI/AppModel.swift:368-387 |
| 敏感值剪贴板 | 45 秒后自动清除（内容未被替换时），并打隐藏标记 | cmd/windows/envbox/service.go:582-608；internal/windows/winsys/clipboard.go；Sources/EnvBoxUI/AppModel.swift:405-407 |
| MCP 片段与提示词 | 三个客户端、片段与提示词文案、两个复制按钮 | shared/ui/assets/app.js:438-439；internal/windows/mcp/wiring.go；Sources/EnvBoxCore/MCP/MCPPolicy.swift:96-137 |
| 复制变量名 / 复制值 | 行内两个动作分开，各有图标与提示 | shared/ui/assets/app.js:283-285；Sources/EnvBoxUI/Views/VariableRows.swift:62-77 |
| 导入 `.envbox` | 选文件 → 密码 → 解密合并；重名自动改名、配置与变量 ID 重键、绝不覆盖本地 | cmd/windows/envbox/transfer.go:78,112,202；cmd/windows/envbox/main.go:146；shared/ui/assets/app.js:417,1138 |
| 复制配置 | 名称取「X 副本」并自动加序号，变量全部重键 | cmd/windows/envbox/transfer.go:31；shared/ui/assets/app.js:240,1118；Sources/EnvBoxUI/AppModel.swift:508 |
| 导出子集 | 单配置导出与全部导出两个入口，同一密码规则 | shared/ui/assets/app.js:241,1124；cmd/windows/envbox/service.go:721-748；Sources/EnvBoxUI/AppModel.swift:1048 |
| MCP `env_exec` | `command`/`requiredKeys`/`timeoutSeconds`/`login`，返回体都带 `generation` | internal/windows/mcp/tools.go:45-48,156-172；internal/windows/appenv/appenv.go:164-200；Sources/EnvBoxCore/MCP/MCPToolHandlers.swift:106,115-122 |

## 四、优先修复清单

**已完成（本轮，1.2.0 build 21）**

- 导入 `.envbox`：host 选文件 + 密码，合并时重名改名、ID 重键；命令行 `envbox import` 保留。
- 复制配置：详情页按钮，命名与 macOS 一致。
- 导出子集：详情页「导出此配置」，host 的 `ids` 参数第一次被界面用上。
- `env_exec` 的 `login`：Windows 没有登录 Shell，映射为「先从注册表重读用户环境变量」，命令行 `envbox exec --login` 同步支持。

**P1**

1. 全局「隐藏所有敏感值」+ 两项敏感值设置开关（行为已有，缺开关）。
2. 首次应用确认流程（字段已在模型里，缺消费）。
3. 系统变量搜索补上按值匹配。
4. 快捷键（至少 新建配置 / 刷新 / 应用当前）。
5. `env_reveal` 返回体补齐 `available` / `generation`，让 Agent 侧解析一致。
6. macOS 侧系统变量的敏感判定跟上 Windows：配置里 `isSecret` 的 key 在系统页也要掩码（见第二节）。

**P2**

7. 名称重复改为自动加序号（与 macOS 一致，避免打断录入）。
8. 备注超长改为报错而不是静默截断。
9. 「保存并继续」、「在资源管理器中显示」、`symbol` 长度校验。

## 五、复核修正

子代理初查中有 5 条经复核不成立、1 条需降级，正文已按复核结果改写：

| 初查结论 | 复核结果 | 证据 |
| --- | --- | --- |
| 变量筛选维度缺失 | 不成立：配置页有 全部/已启用/已停用/敏感，系统页有 全部/敏感/EnvBox | shared/ui/assets/app.js:246,318 |
| 删除配置无二次确认 | 不成立：删除前弹破坏性确认 | shared/ui/assets/app.js:1079-1092 |
| 敏感值剪贴板 45 秒自动清除缺失 | 不成立：已实现（含剪贴板历史/云同步标记） | cmd/windows/envbox/service.go:582-608；internal/windows/winsys/clipboard.go |
| 值含 NUL 未校验 | 不成立：校验存在 | internal/core/model/profile.go:274 |
| 托盘菜单只有退出与窗口按钮 | 不成立：托盘有配置列表/应用/停用/退出 | cmd/windows/envbox/tray.go:70-100 |
| 导出只能全量（按主机能力记） | 降级：host 支持子集，缺的是界面 | cmd/windows/envbox/service.go:735-748 |

未确认：macOS 侧是否具备自更新能力（本次未读更新相关实现），Windows 侧已有 检查/下载/安装 三段。
