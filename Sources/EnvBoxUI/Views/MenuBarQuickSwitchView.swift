import EnvBoxCore
import AppKit
import SwiftUI

struct MenuBarQuickSwitchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    @State private var hoveredProfileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.isBootstrapping && model.payload.profiles.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取环境…")
                        .font(.system(size: 11))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
            } else if model.payload.profiles.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: model.activeProfile == nil ? "选择配置" : "快速切换")
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.payload.profiles) { profile in
                                quickRow(profile)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 318)
                }
            }

            if let error = model.menuActionError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(error)
                        .font(.system(size: 9.5))
                        .lineLimit(3)
                }
                .foregroundStyle(EnvBoxTheme.rose)
                .padding(.horizontal, 4)
            }

            PanelDivider()

            HStack(spacing: 4) {
                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(MenuBarFooterButtonStyle())
                Spacer()
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("打开", systemImage: "macwindow")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(MenuBarFooterButtonStyle())
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(MenuBarFooterButtonStyle())
                .help("退出 EnvBox")
            }
        }
        .padding(13)
        .frame(width: 318)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 9) {
            BrandMark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("EnvBox")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(model.activeProfile?.name ?? "未启用配置")
                    .font(.system(size: 9.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7.5, weight: .semibold))
                Text("加密")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(EnvBoxTheme.mint)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(EnvBoxTheme.mint.opacity(0.09), in: Capsule())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("还没有配置")
                .font(.system(size: 11.5, weight: .medium))
            Text("打开 EnvBox 从当前系统环境创建一个。")
                .font(.system(size: 9.5))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                .multilineTextAlignment(.center)
            Button("打开 EnvBox") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(EnvBoxSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func quickRow(_ profile: EnvProfile) -> some View {
        let isActive = model.isActive(profileID: profile.id)
        let isPending = isActive && model.activeProfileNeedsApply
        let isHovering = hoveredProfileID == profile.id
        let isApplyingThis = model.applyingProfileID == profile.id

        return Button {
            Task { await model.quickSwitch(profile.id) }
        } label: {
            HStack(spacing: 9) {
                ProfileGlyph(tint: profile.tint, symbol: profile.symbol, size: 27)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(profile.enabledVariables.count) 个变量")
                        .font(.system(size: 9))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                }
                Spacer(minLength: 6)
                if isApplyingThis {
                    ProgressView().controlSize(.mini)
                } else if isPending {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(EnvBoxTheme.amber)
                        .help("有未应用更改")
                } else if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EnvBoxTheme.mint)
                } else if isHovering {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isActive
                            ? EnvBoxTheme.mint.opacity(0.075)
                            : Color.primary.opacity(isHovering ? 0.055 : 0)
                    )
            }
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(EnvBoxTheme.mint.opacity(0.15), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isApplying)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredProfileID = hovering ? profile.id : nil
            }
        }
        .help(isActive ? "当前配置" : "应用 \(profile.name)")
    }
}

private struct MenuBarFooterButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.07 : 0))
            }
    }
}
