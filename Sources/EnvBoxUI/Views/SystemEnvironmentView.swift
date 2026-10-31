import EnvBoxCore
import Foundation
import SwiftUI

struct SystemEnvironmentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var filterNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                header
                stats
                banners
                toolbar
                variablesPanel
                footer
            }
            .padding(.horizontal, EnvBoxTheme.pagePadding)
            .padding(.top, 38)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(text: "Live environment")
                HStack(spacing: 10) {
                    Text("系统环境")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                    sourcePill
                    if model.isRefreshingEnvironment {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 1)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            Spacer(minLength: 12)
            HStack(spacing: 9) {
                if model.isRefreshingEnvironment {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    IconButton(
                        systemName: "arrow.clockwise",
                        help: "刷新系统环境",
                        tint: EnvBoxTheme.textSecondary(for: scheme),
                        size: 36
                    ) {
                        Task { await model.refreshSystemEnvironment() }
                    }
                    .background(Color.primary.opacity(0.035), in: Circle())
                    .overlay {
                        Circle().strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
                    }
                }

                Button {
                    model.presentNewProfile(prefillSystem: true)
                } label: {
                    Label("保存为配置", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(EnvBoxPrimaryButtonStyle())
                .disabled(!model.isVaultUnlocked || model.snapshot == nil)
                .help(model.isVaultUnlocked ? "将当前系统环境保存为可编辑配置" : "配置库未解锁")
            }
        }
    }

    private var sourcePill: some View {
        Pill(
            text: sourceLabel,
            icon: sourceIcon,
            tint: sourceTint
        )
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatCard(
                icon: "number",
                value: "\(model.totalSystemCount)",
                label: "变量总数",
                tint: EnvBoxTheme.aqua
            )
            StatCard(
                icon: "lock.shield.fill",
                value: "\(model.snapshot?.sensitiveCount ?? 0)",
                label: "敏感变量",
                tint: EnvBoxTheme.amber
            )
            StatCard(
                icon: "gearshape.2.fill",
                value: "\(model.snapshot?.internalCount ?? 0)",
                label: "系统内部",
                tint: EnvBoxTheme.violet
            )
        }
    }

    @ViewBuilder
    private var banners: some View {
        if !model.isVaultUnlocked, let vaultError = model.vaultError {
            InfoBanner(
                icon: "lock.trianglebadge.exclamationmark.fill",
                title: "本地配置库未解锁",
                message: vaultError,
                tint: EnvBoxTheme.rose,
                actionTitle: "重试",
                action: { Task { await model.retryVaultUnlock() } }
            )
        }

        if let warning = model.snapshot?.warning {
            InfoBanner(
                icon: "exclamationmark.triangle.fill",
                title: "登录 Shell 读取受限",
                message: warning,
                tint: EnvBoxTheme.amber
            )
        }

        if let status = model.shellStatus, status.isSupported, !status.isInstalled {
            InfoBanner(
                icon: "terminal",
                title: "让新终端自动载入当前配置",
                message: "启用一次 Zsh 集成后，EnvBox 会在 ~/.zshrc 写入受管理的片段，新终端启动时自动读取当前配置。",
                tint: EnvBoxTheme.aqua,
                actionTitle: "启用集成",
                isWorking: model.isTogglingShellIntegration,
                action: { Task { await model.setShellIntegration(true) } }
            )
        } else if let status = model.shellStatus, !status.isSupported {
            InfoBanner(
                icon: "terminal",
                title: "当前 Shell 为 \(status.shellName)",
                message: "EnvBox 的自动 Shell 集成目前仅支持 Zsh。配置仍会应用到系统环境，但新终端需要手动启停配置。",
                tint: EnvBoxTheme.textSecondary(for: scheme)
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            SearchField(text: Binding(
                get: { model.searchText },
                set: { model.searchText = $0 }
            ), placeholder: "搜索变量名或值")
            .frame(maxWidth: 330)

            FilterChipBar(
                selection: Binding(
                    get: { model.filter },
                    set: { model.filter = $0 }
                ),
                options: [.all, .sensitive],
                system: true,
                namespace: filterNamespace
            )

            Spacer(minLength: 4)

            IconButton(
                systemName: model.revealAllSensitive ? "eye.slash.fill" : "eye.fill",
                help: model.revealAllSensitive ? "隐藏所有敏感值" : "显示所有敏感值",
                tint: EnvBoxTheme.textSecondary(for: scheme),
                size: 28
            ) {
                model.revealAllSensitive.toggle()
            }

            ChipToggle(
                title: "系统内部",
                systemName: "gearshape.2",
                isOn: model.payload.settings.showInternalVariables
            ) {
                model.setShowInternalVariables(!model.payload.settings.showInternalVariables)
            }
        }
    }

    private var variablesPanel: some View {
        let visibleVariables = model.visibleSystemVariables
        return VStack(spacing: 0) {
            HStack {
                Text("变量")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(visibleVariables.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.system(size: 9))
                    Text("只读快照")
                        .font(.system(size: 10))
                }
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            PanelDivider()

            if model.isBootstrapping && model.snapshot == nil {
                SkeletonVariableRows(rows: 7)
            } else if visibleVariables.isEmpty {
                EmptyStateView(
                    icon: model.totalSystemCount == 0 ? "terminal" : "line.3.horizontal.decrease.circle",
                    title: model.totalSystemCount == 0 ? "没有读取到环境变量" : "没有匹配的变量",
                    message: model.totalSystemCount == 0
                        ? "登录 Shell 可能启动超时，试试刷新。"
                        : "调整搜索关键词或筛选条件。"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleVariables.enumerated()), id: \.element.id) { index, variable in
                        SystemVariableRow(variable: variable)
                        if index < visibleVariables.count - 1 {
                            PanelDivider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .glassPanel()
        .clipShape(RoundedRectangle(cornerRadius: EnvBoxTheme.panelRadius, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8.5))
            Text("系统快照只读，不会写入配置库。")
                .font(.system(size: 10))
            Spacer()
            if let status = model.shellStatus, status.isInstalled {
                HStack(spacing: 4) {
                    Circle().fill(EnvBoxTheme.mint).frame(width: 4, height: 4)
                    Text("Zsh 集成已启用")
                }
                .font(.system(size: 10))
            }
        }
        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
        .padding(.horizontal, 4)
    }

    private var subtitle: String {
        guard let snapshot = model.snapshot else {
            return "正在读取当前进程与登录 Shell 环境…"
        }
        let time = snapshot.capturedAt.formatted(date: .omitted, time: .standard)
        return "来自\(sourceLabel) · \(time) 更新"
    }

    private var sourceLabel: String {
        switch model.snapshot?.source {
        case .loginShell: return "登录 \(shellDisplayName)"
        case .processOnly: return "应用进程"
        case .fallback: return "应用进程（回退）"
        case .none: return "读取中"
        }
    }

    private var shellDisplayName: String {
        guard let name = model.snapshot?.shellName else { return "Shell" }
        switch name.lowercased() {
        case "zsh": return "Zsh"
        case "bash": return "Bash"
        default: return name.capitalized
        }
    }

    private var sourceIcon: String {
        switch model.snapshot?.source {
        case .loginShell: return "terminal.fill"
        case .processOnly, .fallback: return "app.fill"
        case .none: return "clock"
        }
    }

    private var sourceTint: Color {
        switch model.snapshot?.source {
        case .loginShell: return EnvBoxTheme.mint
        case .processOnly: return EnvBoxTheme.aqua
        case .fallback: return EnvBoxTheme.amber
        case .none: return EnvBoxTheme.textSecondary(for: scheme)
        }
    }
}
