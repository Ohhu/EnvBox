# Windows 自动更新（渠道：GitHub Releases）

行为规格。实现分布在 `internal/windows/update`（协议、校验、安装）、`internal/windows/settings`（开关与状态）。

## 边界

更新检查是 EnvBox 唯一的出站流量：

- 请求 `api.github.com` 的 latest release，校验通过后下载安装包。
- 不带标识符、Cookie，不发送配置、变量名、变量值。GitHub 侧可见 IP、时间与 `User-Agent: EnvBox`。
- 可完全关闭：设置页选「关闭自动检查」，或把 `update.check` 置为 `off`。关闭后进程内不再发起请求。

## 渠道规则

| 项 | 规则 |
| --- | --- |
| 端点 | `GET https://api.github.com/repos/{UpdateRepo}/releases/latest`，`UpdateRepo` 由 `-X internal/core/buildinfo.UpdateRepo` 注入 |
| 请求头 | `Accept: application/vnd.github+json`、`X-GitHub-Api-Version: 2022-11-28`、`User-Agent: EnvBox`，有缓存时带 `If-None-Match` |
| 接受条件 | `tag_name` 匹配 `^v?(\d+)\.(\d+)\.(\d+)$`（`v` 前缀可省），`draft`/`prerelease` 均为 false |
| 版本比较 | 三段 semver 数值比较；只有远端更新才提示，低于当前一律拒绝 |
| 资产选择 | 必须存在 `EnvBox-<version>-Windows-amd64-Setup.exe`；`SHA256SUMS-windows-amd64.txt` 可选 |
| 自动检查 | 默认每天一次，可选 `off`/`daily`/`weekly`；手动检查不做节流 |
| 条件请求 | 保存 `ETag`，304 视为无更新 |
| 限流 | 403/429 提示「GitHub 限制了请求频率，请稍后再试」；自动检查顺延到下一次 |
| 代理 | 优先 `HTTPS_PROXY`/`HTTP_PROXY`，否则读 WinINET `Internet Settings`；loopback 直连 |
| 重定向 | 只允许 `github.com`、`api.github.com`、`codeload.github.com`、`*.githubusercontent.com` |

## 校验链

四道，任何一道失败即终止，不提供「仍然安装」：

1. **传输**：仅 http(s)，TLS 1.2+，重定向域名白名单。
2. **哈希**：GitHub 资产 `digest` 与 `SHA256SUMS-windows-amd64.txt` 交叉核对；两者都缺视为失败。
3. **Authenticode**：`WinVerifyTrust`（`WTD_REVOKE_NONE` + `WTD_CACHE_ONLY_URL_RETRIEVAL`）验签，取签名证书 SHA-1 指纹与编译期嵌入的 `internal/core/buildinfo.SignerThumbprint` 比对。
   - 未签名构建（指纹为空）不自动安装；界面给出 `https://github.com/<UpdateRepo>/releases/latest` 链接。
   - 只接受内嵌签名，catalog 签名的系统文件会被拒。
4. **一致性**：资产名里的版本号必须等于 `tag_name`。

检查结果写进 `settings.json` 的 `update.lastResult`：成功为 `not-modified`、`up-to-date`、`update-available:<版本>`，失败为 `check-failed`、`invalid-tag`、`asset-missing`、`digest-mismatch`、`signature-invalid`、`signer-mismatch`、`unsigned-build`。更新已关闭、命中跳过版本、tag 无法解析这三种情况直接返回、不写入结果码。摘要不符时还没落盘，签名不符时删掉已落盘的安装包。界面把这些码翻译成中文说明。

## 安装流程

```text
1. 下载 → <config>/updates/<version>/<Setup.exe>
2. 四道校验
3. 写 update-pending.json {from, to, sha256, path, at}
   摘要缺失也视为失败：记录被手工改写不能成为跳过校验的开关
4. 启动安装包前再核对一次：重算暂存文件的 SHA-256 与记录比对，
   再用 WinVerifyTrust 验签并与编译期嵌入的指纹比对
   （记录与安装包同目录，摘要本身不是独立信任锚）
5. 确认后关闭窗口并退出进程（释放 exe 文件锁）
6. 启动安装包 /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /SP-
7. 安装器以 --updated 重启 EnvBox；启动时发现 pending.To 不高于当前版本即清理记录（手工装了更高版本也会回收）
```

- 免 UAC：安装器 `PrivilegesRequired=lowest`。
- 退出码 0 成功、3010 需重启（不重启）、1602 中止、1603 致命错误；目前应用只依据「版本是否变化」判断结果，安装器退出码未读取。
- 不做自动回滚，不做差分更新。
- 开发态（`winsys.IsInstalled()` 为假）不参与更新：GUI 与 `envbox update check|download|install` 都会被拒绝，界面三个按钮置灰。

## 状态

`settings.json` 里的更新节（非敏感配置，与 vault 分开）：

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `update.check` | `daily` | `off`/`daily`/`weekly` |
| `update.skippedVersion` | 空 | 仅 CLI 可设置（`envbox update settings --skip-version <版本>`、`--clear-skip`）；命中该版本时更新被跳过 |
| `update.etag` | 空 | 条件请求缓存 |
| `update.lastCheckAt`/`lastResult` | - | UI 展示「上次检查」与结果码 |

检查自动、安装手动确认；不提供静默自动安装。原因：四道校验能挡传输层与存储层篡改，挡不住发布者自己发布问题版本，自动执行等于把发布流水线的安全性等同于本地代码执行权限。

## UI

位置：设置 → 更新。

| 状态 | 展示 |
| --- | --- |
| 已是最新 | 当前版本、上次检查时间、上次结果码 |
| 有新版本 | 版本号、发布说明前 600 字、按钮「下载安装包」「安装并重启」 |
| 待安装 | 「待安装 <版本>，点击「安装并重启」完成升级」 |
| 未签名构建 | 提示「此版本需手动下载安装包」+ Release 链接 |
| 校验失败 | 提示「安装包完整性校验失败：<原因>」，卡片结果码显示「安装包摘要不一致」等中文说明，并给出 Release 链接 |

## 不做

- beta/nightly 渠道切换、差分更新、自动回滚、后台常驻更新服务、远程配置或远程脚本。

## 待完成

1. 安装器退出码映射（当前只看版本号是否变化）。
2. 安装后 `--updated` 的首次报告（现在只写一行 startup.log）。
3. 签名安装包的 `digest` 与 `SHA256SUMS` 双源一致性核对（首次发布时验证）。
