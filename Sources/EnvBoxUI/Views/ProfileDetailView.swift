import EnvBoxCore
import Foundation
import SwiftUI

struct ProfileDetailView: View {
    let profileID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var filterNamespace
    @State private var variableToDelete: EnvVariable?
    @State private var showDeleteProfile = false

    var body: some View {
        Group {
            if let profile = model.payload.profile(id: profileID) {
                content(for: profile)
            } else {
                EmptyStateView(
                    icon: "questionmark.folder",
                    title: "配置不存在",
                    message: "它可能已经被删除。",
                    actionTitle: "返回系统环境",
                    action: { model.select(.system) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func content(for profile: EnvProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                header(for: profile)
                stats(for: profile)
                banners(for: profile)
                toolbar(for: profile)
                variablesPanel(for: profile)
                footer(for: profile)
            }
            .padding(.horizontal, EnvBoxTheme.pagePadding)
            .padding(.top, 38)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog(
            "删除变量？",
            isPresented: Binding(
                get: { variableToDelete != nil },
                set: { if !$0 { variableToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: variableToDelete
        ) { variable in
            Button("删除 \(variable.key)", role: .destructive) {
                variableToDelete = nil
                model.deleteVariable(variable.id, profileID: profile.id)
            }
            Button("取消", role: .cancel) { variableToDelete = nil }
        } message: { variable in
            Text("“\(variable.key)”及其值将从此配置中移除。")
        }
        .confirmationDialog(
            "删除配置？",
            isPresented: $showDeleteProfile,
            titleVisibility: .visible
        ) {
            Button("删除“\(profile.name)”", role: .destructive) {
                Task { await model.deleteProfile(profile.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                model.isActive(profileID: profile.id)
                    ? "该配置当前已启用。EnvBox 会先清理它写入的环境变量，再永久删除配置。"
                    : "该配置将被永久删除，此操作无法撤销。"
            )
        }
    }

    private func header(for profile: EnvProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Profile · \(profile.tint.displayName)")
            HStack(alignment: .top, spacing: 14) {
                ProfileGlyph(tint: profile.tint, symbol: profile.symbol, size: 46)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .tracking(-0.5)
                            .lineLimit(1)
                        if model.isActive(profileID: profile.id) {
                            Pill(text: "当前已启用", icon: "checkmark.circle.fill", tint: EnvBoxTheme.mint)
                        }
                        if model.isActive(profileID: profile.id), model.activeProfileNeedsApply {
                            Pill(text: "待应用", icon: "arrow.up.circle.fill", tint: EnvBoxTheme.amber)
                        }
                    }

                    Button {
                        model.presentEditProfile(profile.id)
                    } label: {
                        Text(profile.note.isEmpty ? "添加说明…" : profile.note)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                profile.note.isEmpty
                                    ? EnvBoxTheme.textSecondary(for: scheme).opacity(0.75)
                                    : EnvBoxTheme.textSecondary(for: scheme)
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 14)

                HStack(spacing: 9) {
                    Menu {
                        Button("编辑配置信息…") { model.presentEditProfile(profile.id) }
                        Button("复制配置") { model.duplicateProfile(profile.id) }
                        Button("从系统环境补充变量") {
                            model.importSystemVariables(into: profile.id)
                        }
                        Button("导出加密配置…") {
                            model.presentExport(profileIDs: [profile.id], title: profile.name)
                        }
                        if model.isActive(profileID: profile.id) {
                            Divider()
                            Button("停用当前配置") { model.requestDeactivate() }
                        }
                        Divider()
                        Button("删除配置…", role: .destructive) { showDeleteProfile = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.045), in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 36, height: 36)
                    .help("更多操作")

                    applyButton(for: profile)
                }
            }
        }
    }

    @ViewBuilder
    private func applyButton(for profile: EnvProfile) -> some View {
        if model.isApplying {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("正在应用…")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(EnvBoxTheme.subtlyRaised(for: scheme), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
            }
        } else if model.isActive(profileID: profile.id), !model.activeProfileNeedsApply {
            Button {
                model.reapplyActiveProfile()
            } label: {
                Label("重新应用", systemImage: "arrow.clockwise")
            }
            .buttonStyle(EnvBoxSecondaryButtonStyle())
            .disabled(model.isApplying || !model.isVaultUnlocked)
            .help("重新写入系统环境")
        } else {
            Button {
                model.requestApply(profile.id)
            } label: {
                if model.isActive(profileID: profile.id) {
                    Label("应用更改", systemImage: "arrow.up.circle.fill")
                } else {
                    Label("应用到此 Mac", systemImage: "bolt.fill")
                }
            }
            .buttonStyle(EnvBoxPrimaryButtonStyle())
            .disabled(model.isApplying || !model.isVaultUnlocked)
            .help("写入系统环境")
        }
    }

    private func stats(for profile: EnvProfile) -> some View {
        HStack(spacing: 10) {
            StatCard(
                icon: "checkmark.circle",
                value: "\(profile.enabledVariables.count)/\(profile.variables.count)",
                label: "已启用变量",
                tint: EnvBoxTheme.mint
            )
            StatCard(
                icon: "lock.shield.fill",
                value: "\(profile.secretCount)",
                label: "敏感变量",
                tint: EnvBoxTheme.amber
            )
            StatCard(
                icon: "clock",
                value: relativeUpdate(profile.updatedAt),
                label: "最后修改",
                tint: EnvBoxTheme.aqua
            )
        }
    }

    @ViewBuilder
    private func banners(for profile: EnvProfile) -> some View {
        if model.isActive(profileID: profile.id), model.activeProfileNeedsApply {
            InfoBanner(
                icon: "arrow.triangle.2.circlepath",
                title: "当前系统仍在使用上一次应用的值",
                message: "编辑只会更新加密配置库。点击“应用更改”后，新打开的终端和 App 才会使用最新值。",
                tint: EnvBoxTheme.amber,
                actionTitle: "应用更改",
                action: { model.requestApply(profile.id) }
            )
        }

        if let status = model.shellStatus, status.isSupported, !status.isInstalled {
            InfoBanner(
                icon: "terminal",
                title: "新终端还不会自动读取配置",
                message: "应用配置会写入系统环境。要让新的 Zsh 终端自动读取，请启用 Shell 集成。",
                tint: EnvBoxTheme.aqua,
                actionTitle: "启用集成",
                isWorking: model.isTogglingShellIntegration,
                action: { Task { await model.setShellIntegration(true) } }
            )
        }
    }

    private func toolbar(for profile: EnvProfile) -> some View {
        HStack(spacing: 10) {
            SearchField(
                text: Binding(
                    get: { model.searchText },
                    set: { model.searchText = $0 }
                ),
                placeholder: "搜索变量名、值或备注"
            )
            .frame(maxWidth: 310)

            FilterChipBar(
                selection: Binding(
                    get: { model.filter },
                    set: { model.filter = $0 }
                ),
                options: [.all, .enabled, .disabled, .sensitive],
                namespace: filterNamespace
            )

            Spacer(minLength: 4)

            Button {
                model.presentVariableEditor(profileID: profile.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("添加变量")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }
            .buttonStyle(EnvBoxSecondaryButtonStyle())
            .disabled(!model.isVaultUnlocked || profile.variables.count >= EnvProfile.maxVariables)
            .help("添加变量")
        }
    }

    private func variablesPanel(for profile: EnvProfile) -> some View {
        let visibleVariables = model.visibleProfileVariables
        return VStack(spacing: 0) {
            HStack {
                Text("变量")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(profile.variables.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                Spacer()
                Text("\(profile.enabledVariables.count) 已启用")
                    .font(.system(size: 10))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            PanelDivider()

            if visibleVariables.isEmpty {
                EmptyStateView(
                    icon: profile.variables.isEmpty ? "text.badge.plus" : "line.3.horizontal.decrease.circle",
                    title: profile.variables.isEmpty ? "还没有变量" : "没有匹配的变量",
                    message: profile.variables.isEmpty
                        ? "手动添加变量，或从当前系统环境补充。"
                        : "调整搜索关键词或筛选条件。",
                    actionTitle: profile.variables.isEmpty ? "添加变量" : nil,
                    action: profile.variables.isEmpty
                        ? { model.presentVariableEditor(profileID: profile.id) }
                        : nil
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleVariables.enumerated()), id: \.element.id) { index, variable in
                        ProfileVariableRow(
                            variable: variable,
                            profileID: profile.id,
                            onEdit: { model.presentVariableEditor(profileID: profile.id, variable: variable) },
                            onDeleteRequest: { variableToDelete = variable }
                        )
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

    private func footer(for profile: EnvProfile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8.5))
            Text("修改会自动保存。")
                .font(.system(size: 10))
            Spacer()
            if profile.enabledVariables.isEmpty {
                Text("没有启用的变量")
                    .font(.system(size: 10))
                    .foregroundStyle(EnvBoxTheme.amber.opacity(0.9))
            }
        }
        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
        .padding(.horizontal, 4)
    }

    private func relativeUpdate(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}
