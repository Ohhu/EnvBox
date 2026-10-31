import EnvBoxCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var selectionNamespace
    @State private var profileToDelete: EnvProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
                .padding(.horizontal, 18)
                .padding(.top, 36)
                .padding(.bottom, 22)

            systemRow
                .padding(.horizontal, 12)

            sectionHeader
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 8)

            profileList

            footer
        }
        .frame(width: 252)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(EnvBoxTheme.hairline(for: scheme))
                .frame(width: 1)
        }
        .confirmationDialog(
            "删除配置？",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: profileToDelete
        ) { profile in
            Button("删除“\(profile.name)”", role: .destructive) {
                let id = profile.id
                profileToDelete = nil
                Task { await model.deleteProfile(id) }
            }
            Button("取消", role: .cancel) { profileToDelete = nil }
        } message: { _ in
            Text("配置文件与变量将被永久删除。如果它当前已启用，EnvBox 会先停用并清理环境变量。")
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            BrandMark(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("EnvBox")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.activeProfile == nil ? EnvBoxTheme.textSecondary(for: scheme).opacity(0.35) : EnvBoxTheme.mint)
                        .frame(width: 5, height: 5)
                    Text(model.activeProfile?.name ?? "环境配置管理")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var systemRow: some View {
        Button {
            withAnimation(EnvBoxTheme.animation(reduceMotion: reduceMotion)) {
                model.select(.system)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [EnvBoxTheme.aqua.opacity(0.22), EnvBoxTheme.mint.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EnvBoxTheme.aqua)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("系统环境")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("实时快照")
                        .font(.system(size: 10))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                }
                Spacer(minLength: 4)
                Text("\(model.snapshot?.variables.count ?? 0)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    .padding(.horizontal, 6)
                    .frame(height: 19)
                    .background(Color.primary.opacity(0.045), in: Capsule())
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .contentShape(Rectangle())
            .background {
                if model.selection == .system {
                    selectionBackground
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.selection == .system ? [.isSelected] : [])
    }

    private var sectionHeader: some View {
        HStack {
            SectionLabel(text: "Profiles")
            Text("\(model.payload.profiles.count)")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.65))
            Spacer()
            Button {
                model.presentNewProfile()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help("新建配置")
            .accessibilityLabel("新建配置")
        }
    }

    private var profileList: some View {
        ScrollView {
            profileListContent
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var profileListContent: some View {
        if model.payload.profiles.isEmpty {
            emptyProfiles
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        } else {
            LazyVStack(spacing: 3) {
                ForEach(model.payload.profiles) { profile in
                    profileRow(profile)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func profileRow(_ profile: EnvProfile) -> some View {
        ProfileSidebarRow(
            profile: profile,
            isSelected: model.selection == .profile(profile.id),
            isActive: model.activeProfileID == profile.id,
            namespace: selectionNamespace,
            onDelete: {
                profileToDelete = profile
            }
        )
    }

    private var emptyProfiles: some View {
        VStack(spacing: 9) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.7))
            Text("还没有配置")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            Button("从系统环境创建") {
                model.presentNewProfile(prefillSystem: true)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(EnvBoxTheme.mint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            PanelDivider()
            if let vaultError = model.vaultError {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(EnvBoxTheme.rose)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("配置库无法解锁")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(EnvBoxTheme.rose)
                        Text(vaultError)
                            .font(.system(size: 9.5))
                            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                            .lineLimit(2)
                        Button("重试") {
                            Task { await model.retryVaultUnlock() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EnvBoxTheme.mint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(EnvBoxTheme.mint.opacity(0.10))
                    Image(systemName: saveStateIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(saveStateTint)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(saveStateTitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.86))
                    if case .failed = model.saveState {
                        Button("重试保存") {
                            Task { await model.saveNow(force: true) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(EnvBoxTheme.rose)
                    } else {
                        Text("仅此设备")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.8))
                    }
                }
                Spacer(minLength: 0)

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.04), in: Circle())
                }
                .buttonStyle(.plain)
                .help("设置")
                .accessibilityLabel("设置")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .padding(.top, 4)
    }

    private var saveStateTitle: String {
        if !model.isVaultUnlocked { return "配置库未解锁" }
        switch model.saveState {
        case .saving: return "正在保存…"
        case .saved: return "已保存"
        case .failed: return "保存失败"
        case .idle: return "本地配置库"
        }
    }

    private var saveStateIcon: String {
        if !model.isVaultUnlocked { return "lock.fill" }
        switch model.saveState {
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved: return "checkmark"
        case .failed: return "exclamationmark"
        case .idle: return "lock.fill"
        }
    }

    private var saveStateTint: Color {
        if !model.isVaultUnlocked { return EnvBoxTheme.rose }
        switch model.saveState {
        case .saving: return EnvBoxTheme.aqua
        case .saved: return EnvBoxTheme.mint
        case .failed: return EnvBoxTheme.rose
        case .idle: return EnvBoxTheme.mint
        }
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(scheme == .dark ? 0.085 : 0.055),
                        Color.primary.opacity(scheme == .dark ? 0.05 : 0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
            }
            .matchedGeometryEffect(id: "sidebar-selection", in: selectionNamespace)
    }

    private var sidebarBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.black.opacity(scheme == .dark ? 0.10 : 0.02),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct ProfileSidebarRow: View {
    let profile: EnvProfile
    let isSelected: Bool
    let isActive: Bool
    let namespace: Namespace.ID
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(EnvBoxTheme.animation(reduceMotion: reduceMotion)) {
                model.select(.profile(profile.id))
            }
        } label: {
            HStack(spacing: 10) {
                ProfileGlyph(tint: profile.tint, symbol: profile.symbol, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(profile.enabledVariables.count) 启用 · \(profile.variables.count) 变量")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EnvBoxTheme.mint)
                        .help("当前已启用")
                } else if isHovering {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(scheme == .dark ? 0.085 : 0.055),
                                    Color.primary.opacity(scheme == .dark ? 0.05 : 0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "sidebar-selection", in: namespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(scheme == .dark ? 0.035 : 0.022))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
        .contextMenu {
            Button("编辑信息…") { model.presentEditProfile(profile.id) }
            Button("复制配置") { model.duplicateProfile(profile.id) }
            Button("导出…") { model.presentExport(profileIDs: [profile.id], title: profile.name) }
            Divider()
            Button("删除…", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("\(profile.name)，\(profile.variables.count) 个变量\(isActive ? "，当前已启用" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
