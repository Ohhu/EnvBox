# Go 还是 Rust：性能 / 安全 / UI 三维度对比

> 配套 [WINDOWS-PORT.md](WINDOWS-PORT.md)（选型结论）与 [WINDOWS-BUILD-RELEASE.md](WINDOWS-BUILD-RELEASE.md)（编译发布）。
> 结论：**继续用 Go**。安全上 Rust 确实更强，但强在"本项目的次要威胁"上；性能上两者都是噪声；UI 上两者同构。

## 一句话结论

| 维度 | 谁更强 | 差多少 | 对 EnvBox 是否是决策变量 |
| --- | --- | --- | --- |
| 性能 | 平手（Rust 略优，仅 KDF 一项） | PBKDF2 600k 约 1.5–2.5×，其余为硬件地板 | **否**——都在用户感知阈值以下 |
| 安全 | Rust | 内存安全 + 密钥擦除确实更硬；但依赖链与可审计性 Go 反而赢 | **部分**——只在"把安全当卖点"时才够决定性 |
| UI | 平手（都是 WebView2 + 前端） | 迭代速度 Go 快一档，打包能力 Tauri 强一档 | **否**——真正影响 UI 的是前端技术栈与设计稿，不是后端语言 |

## 性能

本机实测（Go 1.26.5，windows/amd64，单核，实际跑出来的数）：

| 指标 | 实测值 | 说明 |
| --- | --- | --- |
| PBKDF2-HMAC-SHA256 600k 轮 | min 75.7 / median 78.9 / max 84.0 ms | 与 macOS 版同参数（CommonCrypto 通常 250–600 ms），Go 已经更快 |
| AES-256-GCM 封装 | 3.5 GB/s（1 MiB 用时 0.29 ms） | 已经是 AES-NI + PCLMUL 硬件速度，没有优化空间 |
| DPAPI 往返（32 字节密钥） | 1.2–2.7 ms | 是系统调用开销，与语言无关 |
| Windows 冒烟二进制（注册表 + DPAPI + GCM + PBKDF2，零依赖） | 1.86 MB | 冒烟测试已并入正式测试 |
Rust 会赢在哪、赢多少：

- **PBKDF2**：Rust 的 `sha2`（SHA-NI 路径）加 `pbkdf2` crate 比 Go 的 `hmac` 逐轮封装更紧，公开基准里通常是 1.5–2.5×。换算到本项目：**79 ms → 约 35–55 ms**。
- **AES-GCM**：两边都直接吃 AES-NI，差距在 ±10% 内，且 EnvBox 的配置库是 KB 级文件——1 MiB 0.29 ms 意味着整个配置库读写耗时以微秒计。
- **冷启动**：语言层 Go 约 2–5 ms、Rust 约 1–3 ms；但真实启动被 WebView2 初始化支配（通常 150–400 ms），语言差异被淹没。
- **常驻内存**：Go 运行时基线约 3–6 MB，Rust 约 1–2 MB；但 Wails/Tauri 拉起的一组 `msedgewebview2.exe` 子进程就是 100–200 MB。差距是分母里的 2%。
- **二进制**：含前端的 Go/Wails 约 12–15 MB，Rust/Tauri 约 8–10 MB。

结论：性能差距全部落在"用户不会为此换软件"的区间。**PBKDF2 是用户主动触发的一次性等待（解锁、导出），79 ms 和 45 ms 都是无感。**

## 安全

先明确 EnvBox 的真实威胁模型（与 macOS 版 [SECURITY.md](../SECURITY.md) 一致）：

1. 同一台机器上的**同用户恶意进程**读取内存/剪贴板；
2. 配置库或导出文件**被备份、云同步、误分享**泄露；
3. 明文侧信道：日志、崩溃转储、Shell 激活文件、剪贴板历史；
4. 供应链：构建脚本或第三方依赖被污染。

注意第 1 条的前提：DPAPI 的信任边界本来就是"同一登录用户"。同用户进程能解密的，语言再安全也挡不住——**语言层内存安全主要防的是"被恶意输入触发的内存破坏"，而 EnvBox 没有网络、没有文件格式解析、没有富文本渲染**，唯一的外部输入是你自己导入的 `.envbox`（有大小/条目上限、AES-GCM 认证、JSON 结构校验）。

七项细评：

| 项目 | Go | Rust | 说明 |
| --- | --- | --- | --- |
| 语言层内存安全 | 8 | 10 | Go 有数据竞争与切片别名；Rust 编译期消除 |
| 密钥生命周期（清零/锁页） | 5（加固后 7） | 9 | Rust 有 `zeroize`/`secrecy`；Go 的 GC 会搬移对象、string 不可清零、编译器可消除清零 |
| 依赖链 / 可审计性 | 9 | 5 | 业务包（注册表 + DPAPI + AES-GCM + PBKDF2）零第三方依赖，GUI 只引入 Wails v3；Tauri 侧通常是数百个 crate |
| Win32 绑定正确性 | 6 | 8 | Go 用 `uintptr` 裸调，错误码语义要自己判断（这次就踩了 LSTATUS=5 与 LastError 不一致）；`windows-sys` 是类型化绑定 |
| 发布可复现 | 8 | 8 | 都能 trimpath、锁依赖、清 buildid |
| 默认加固（CFG/ASLR/DEP） | 6 | 8 | Go 不支持 `/guard:cf`；Rust 可加 link-arg 打开 |
| 供应链维护负担 | 8 | 6 | Rust 生态更新快，`cargo-audit` 要常态跑 |

对隐私类产品来说，**"依赖链为零"是可以对外承诺的性质，而"内存安全"是所有人都该有的底线**。EnvBox 的卖点是"默认不联网、无遥测、无第三方 SDK、代码可审计"——这一条 Go 明显更容易兑现：`internal/*` 与 CLI 只用标准库，GUI 仅依赖 Wails v3，依赖面远小于 Tauri。

Go 侧把密钥短板补回来的具体清单（不写在文档里就等于没做）：

1. 主密钥只以 `[]byte` 存在，用完立刻清零；**绝不转 `string`**（Go 的 string 不可改、不可清）。
2. 用 `（尚未使用）CryptProtectMemory(SECMEMORY)` 包裹密钥缓冲区——这是 Windows 对应 `mlock` + 加密的方案，进程被换页、休眠、转储时都是密文。
3. `VirtualLock` 锁页，降低 swap 暴露面（注意工作集配额，失败要降级而不是崩）。
4. `SetProcessMitigationPolicy`：强制 DEP、禁动态代码、禁子进程继承敏感句柄。
5. 抑制崩溃转储里的内存（`SetErrorMode` + WER 策略），EnvBox 崩溃不该把变量写到磁盘。
6. 变量值永不进日志/错误串——只记长度与前缀指纹（沿用 macOS 版的 `env_describe` 设计）。
7. 剪贴板走 `ExcludeClipboardContentFromMonitorProcessing` + `CanIncludeInClipboardHistory=0`，45 秒清空。
8. 明文的 Shell 激活文件必须明确标注边界（macOS 版的 `active.zsh` 就是明文，这点要在新 SECURITY.md 里继承并改写为 PowerShell 等价物）。

做完这 8 条，Go 的密钥生命周期评分从 5 提到 7，与 Rust 的实际差距缩小到"理论可证 vs 工程可控"的差别。

## UI

| 能力 | Go | Rust | 判断 |
| --- | --- | --- | --- |
| 复刻现有设计稿（`docs/*.png` 那套卡片/侧栏/毛玻璃） | Wails v3 + HTML/CSS | Tauri v2 + HTML/CSS | 等价。**UI 质量取决于前端和设计还原，不取决于后端语言** |
| 真·原生控件 | `lxn/walk`（Win32 控件，自绘成本高） | `windows-sys` 手写 Win32；无成熟 WinUI 3 绑定 | 都不行；要原生控件应该换 C# |
| 自绘渲染方案 | Fyne（观感偏移动端，且需 cgo） | egui / iced / Slint / Freya（自绘，非原生观感） | 都不符合"原生 macOS 观感移植到 Windows"的诉求 |
| 增量构建速度 | **1–2 s** | 5–30 s（首次全量 2–6 min） | Go 明显快；UI 为主的项目里每天要点几百次 |
| 打包能力 | 自带 Inno 脚本（已写） | `tauri build` 内置 MSI/NSIS/updater/sidecar | Tauri 更强，能省掉我上一轮写的那部分脚本 |
| 生态成熟度 | Wails v3 较新（2026 才 3.0.0 稳定） | Tauri v2 更成熟、文档更多 | Tauri 略优 |

选 Rust 的唯一实质理由是 Tauri 的打包与 sidecar；这部分已用 Inno + PowerShell 补上，签名与 Inno 编译尚未首跑。

## 加权

权重按 EnvBox 的实际情况给：安全 40%、工程成本/迭代速度 30%、UI 能力 20%、性能 10%。

| 维度 | 权重 | Go | Rust | 加权 Go | 加权 Rust |
| --- | --- | --- | --- | --- | --- |
| 安全 | 40% | 7.5 | 8.5 | 3.00 | 3.40 |
| 工程成本 / 迭代速度 | 30% | 9.0 | 6.0 | 2.70 | 1.80 |
| UI 能力 | 20% | 8.0 | 8.5 | 1.60 | 1.70 |
| 性能 | 10% | 8.0 | 9.0 | 0.80 | 0.90 |
| **合计** | | | | **8.10** | **7.80** |

Go 的领先全部来自工程成本（迭代速度、零依赖、交叉编译、与现有 Swift 工程的结构对齐）；Rust 的领先全部来自安全理论强度。

## 什么条件下改选 Rust

出现下面任意一条，就值得推翻上面的结论：

1. **要把"密钥内存零化 + 内存安全"写进产品承诺**——比如面向安全团队售卖、要过第三方代码审计、客户安全基线明确要求 `zeroize`/`mlock` 语义。
2. **二进制体积或常驻内存变成硬指标**——目标机型内存紧张、或要求"安装包 < 10 MB、常驻 < 80 MB"这类可量化的验收条件。
3. **团队已经是 Rust 熟手**——人的成本永远大于技术差异。本项目单人 6–8 天的工作量，用不熟的语言写会变成 15 天。

## 如果真要走 Rust

架构会长这样，工期比 Go 方案多 2–4 天：

```text
src-tauri/            Tauri v2 主进程（Rust）
  registry.rs         windows-sys 读写 HKCU\Environment + SendMessageTimeoutW
  dpapi.rs            CryptProtectData / （尚未使用）CryptProtectMemory
  vault.rs            aes-gcm + pbkdf2（zeroize 包裹密钥）
  mcp.rs              MCP stdio server（同一 crate 编出 envbox.exe 作 sidecar）
frontend/             Svelte / React（与 Go 方案完全共享）
tauri.conf.json       bundle: msi + nsis，sidecar 声明 envbox.exe
```

依赖面：`tauri`、`windows-sys`、`aes-gcm`、`pbkdf2`、`sha2`、`zeroize`、`secrecy`、`subtle`、`serde`、`serde_json`——**加上 Tauri 自己的传递依赖，总计数百个 crate**。要维持"可审计"，得做 `cargo vendor` + `cargo-deny` + `cargo-audit`，并把 `Cargo.lock` 当发布物的一部分。

**不建议混合方案**（Go 主体 + Rust 加密内核）：FFI 边界本身就是 `unsafe` 面，交叉编译能力（Go 现在 `CGO_ENABLED=0` 一行命令出两个架构）直接失效，构建复杂度翻倍，而收益只有"密钥擦除"一项——那 8 条 Go 加固清单能覆盖其中大部分。
