import EnvBoxCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            EnvBoxBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    generalSection
                        .disabled(!model.isVaultUnlocked)
                    shellSection
                    securitySection
                    aboutSection
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 30)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 620, height: 720)
        .task { await model.refreshShellStatus() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("EnvBox \(model.appVersion) · 本机环境配置管理器")
                    .font(.system(size: 11))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            Spacer()
        }
    }

    private var generalSection: some View {
        SettingsCard(title: "通用", icon: "slider.horizontal.3") {
            SettingsToggleRow(
                icon: "bolt.fill",
                tint: EnvBoxTheme.mint,
                title: "启动时恢复当前配置",
                description: "打开 EnvBox 时将当前配置重新写入 launchd。macOS 重启后环境会丢失，建议保留。",
                isOn: Binding(
                    get: { model.payload.settings.autoRestoreActiveProfile },
                    set: { model.setAutoRestore($0) }
                )
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon: "terminal",
                tint: EnvBoxTheme.aqua,
                title: "读取登录 Shell 环境",
                description: "通过一次性的登录 Shell（Zsh / Bash）读取 .zprofile、.zshrc 或 .bash_profile 中的变量。关闭后只显示 App 进程自身环境。",
                isOn: Binding(
                    get: { model.payload.settings.includeLoginShellEnvironment },
                    set: { model.setIncludeLoginShell($0) }
                )
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon: "gearshape.2",
                tint: EnvBoxTheme.violet,
                title: "显示系统内部变量",
                description: "在系统环境页面显示 PWD、XPC_*、DYLD_* 等由系统或启动器注入的变量。",
                isOn: Binding(
                    get: { model.payload.settings.showInternalVariables },
                    set: { model.setShowInternalVariables($0) }
                )
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon: "eye.slash.fill",
                tint: EnvBoxTheme.amber,
                title: "敏感值默认隐藏",
                description: "对 TOKEN、PASSWORD、SECRET、ACCESS_KEY 等变量默认显示圆点，仍可逐项查看。",
                isOn: Binding(
                    get: { model.payload.settings.concealSensitiveValues },
                    set: { model.setConcealSensitiveValues($0) }
                )
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon: "clock.badge.checkmark",
                tint: EnvBoxTheme.aqua,
                title: "自动清除敏感剪贴板",
                description: "复制敏感值后，如果剪贴板内容未被替换，EnvBox 会在 45 秒后清空。",
                isOn: Binding(
                    get: { model.payload.settings.autoClearSensitiveClipboard },
                    set: { model.setAutoClearSensitiveClipboard($0) }
                )
            )
        }
    }

    private var shellSection: some View {
        SettingsCard(title: "Shell 集成", icon: "terminal.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 11) {
                    ZStack {
                        Circle().fill(shellTint.opacity(0.12))
                        Image(systemName: shellIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(shellTint)
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(shellTitle)
                                .font(.system(size: 12.5, weight: .semibold))
                            if model.isTogglingShellIntegration {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        Text(shellDescription)
                            .font(.system(size: 10.5))
                            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)

                    Button(model.shellStatus?.isInstalled == true ? "移除集成" : "启用集成") {
                        Task {
                            await model.setShellIntegration(!(model.shellStatus?.isInstalled ?? false))
                        }
                    }
                    .buttonStyle(EnvBoxSecondaryButtonStyle())
                    .disabled(
                        model.isTogglingShellIntegration
                            || !(model.shellStatus?.isSupported ?? false)
                            || !model.isVaultUnlocked
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    pathRow(label: "Shell 配置", path: model.shellStatus?.rcURL.path ?? "~/.zshrc")
                    pathRow(label: "激活脚本", path: model.shellStatus?.activationURL.path ?? "~/.envbox/active.zsh")
                }
                .padding(11)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(EnvBoxTheme.amber)
                    Text("仅在启用 Shell 集成时写入 active.zsh；它必须以明文保存（权限 0600），只有当前用户可读。移除集成会删除该文件。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("在 Finder 中显示") {
                        let url = model.shellStatus?.rcURL ?? model.vaultFileURL.deletingLastPathComponent()
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(EnvBoxSecondaryButtonStyle())
                    if model.shellStatus?.isInstalled == true {
                        Button("刷新状态") {
                            Task { await model.refreshShellStatus() }
                        }
                        .buttonStyle(EnvBoxSecondaryButtonStyle())
                    }
                }
            }
            .padding(14)
        }
    }

    private var securitySection: some View {
        SettingsCard(title: "安全与隐私", icon: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    securityBadge(icon: "lock.fill", title: "AES-256-GCM", subtitle: "本地配置库")
                    securityBadge(icon: "key.fill", title: "macOS Keychain", subtitle: "随机 256 位主密钥")
                    securityBadge(icon: "function", title: "PBKDF2", subtitle: "600,000 次迭代")
                }

                VStack(alignment: .leading, spacing: 5) {
                    SettingsPathLabel(label: "配置库位置", path: model.vaultFileURL.path)
                    Text("本地配置库只保存密文；主密钥存放在当前用户的登录钥匙串中，不写入应用数据。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("在 Finder 中显示") { model.openVaultFolder() }
                        .buttonStyle(EnvBoxSecondaryButtonStyle())
                    Button("立即隐藏敏感值") { model.hideAllSensitiveValues() }
                        .buttonStyle(EnvBoxSecondaryButtonStyle())
                    Button("导出全部配置…") { model.presentExportAll() }
                        .buttonStyle(EnvBoxSecondaryButtonStyle())
                        .disabled(!model.isVaultUnlocked || model.payload.profiles.isEmpty)
                }

                if !model.isVaultUnlocked {
                    Label("配置库未解锁，安全相关操作暂不可用。", systemImage: "lock.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(EnvBoxTheme.rose)
                }
            }
            .padding(14)
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "关于", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BrandMark(size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EnvBox")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("版本 \(model.appVersion) (build \(model.buildNumber)) · MIT License")
                            .font(.system(size: 10))
                            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    }
                    Spacer()
                    Button("GitHub") { model.openGitHub() }
                        .buttonStyle(EnvBoxSecondaryButtonStyle())
                }
                Text("原生 SwiftUI 环境变量管理器。配置默认只保存在本机，不联网、不包含遥测。Shell 集成与 launchd 写入都需要你明确操作。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }

    private var shellTitle: String {
        guard let status = model.shellStatus else { return "正在检查…" }
        if !status.isSupported { return "当前 Shell：\(status.shellName)（不支持）" }
        return status.isInstalled ? "\(status.shellName) 集成已启用" : "\(status.shellName) 集成未启用"
    }

    private var shellDescription: String {
        guard let status = model.shellStatus else { return "读取 ~/.zshrc 状态" }
        if !status.isSupported {
            return "EnvBox 支持 Zsh / Bash 的自动加载片段。你仍可应用配置到 launchd，但请自行在 \(status.shellName) 中加载 ~/.envbox/active.zsh。"
        }
        return status.isInstalled
            ? "新开的 \(status.shellName) 终端会自动载入配置。移除集成会删除激活脚本，但不会删除已经应用的 launchd 变量。"
            : "写入一段带标记的 \(status.rcURL.lastPathComponent) 片段，只影响新开的 \(status.shellName) 终端；可随时移除。"
    }

    private var shellIcon: String {
        model.shellStatus?.isInstalled == true ? "checkmark.circle.fill" : "terminal"
    }

    private var shellTint: Color {
        if model.shellStatus?.isSupported == false { return EnvBoxTheme.amber }
        return model.shellStatus?.isInstalled == true ? EnvBoxTheme.mint : EnvBoxTheme.aqua
    }

    private func pathRow(label: String, path: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                .frame(width: 58, alignment: .leading)
            Text(path)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func securityBadge(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EnvBoxTheme.mint)
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 8.5))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(EnvBoxTheme.mint)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            PanelDivider()
            content
        }
        .glassPanel(cornerRadius: 17, elevated: false)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    let description: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 9.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            EnvBoxSwitch(
                isOn: $isOn,
                tint: EnvBoxTheme.mint,
                accessibilityLabel: title
            )
            .padding(.top, 2)
        }
        .padding(14)
    }
}

private struct SettingsRowDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(EnvBoxTheme.hairline(for: scheme))
            .frame(height: 1)
            .padding(.leading, 51)
            .padding(.trailing, 14)
    }
}

private struct SettingsPathLabel: View {
    let label: String
    let path: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            Text(path)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
