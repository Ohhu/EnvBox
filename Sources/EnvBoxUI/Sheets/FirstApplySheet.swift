import EnvBoxCore
import SwiftUI

struct FirstApplySheet: View {
    let profileID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var profile: EnvProfile? {
        model.payload.profile(id: profileID)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(EnvBoxTheme.mint)
                        .frame(width: 44, height: 44)
                        .background(EnvBoxTheme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("应用配置到此 Mac")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Text(profile?.name ?? "配置")
                            .font(.system(size: 11.5))
                            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    }
                    Spacer()
                }
            }
            .padding(24)

            PanelDivider()

            VStack(alignment: .leading, spacing: 16) {
                explanationRow(
                    icon: "terminal.fill",
                    title: "写入当前用户环境",
                    text: "EnvBox 会写入 \(profile?.enabledVariables.count ?? 0) 个变量；如已启用 Shell 集成，同时更新 ~/.envbox/active.zsh。"
                )
                explanationRow(
                    icon: "arrow.uturn.backward.circle",
                    title: "可随时恢复",
                    text: "停用配置后，EnvBox 只清理自己写入的变量。"
                )
                explanationRow(
                    icon: "clock.arrow.circlepath",
                    title: "只影响新进程",
                    text: "已经运行的终端和 App 不会改变。新终端可在设置中启用 Zsh 集成。"
                )
            }
            .padding(24)

            PanelDivider()

            HStack(spacing: 9) {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(EnvBoxSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("应用配置") {
                    model.confirmFirstApply(profileID)
                }
                .buttonStyle(EnvBoxPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
        }
        .frame(width: 500, height: 350)
        .background(.regularMaterial)
    }

    private func explanationRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EnvBoxTheme.mint)
                .frame(width: 28, height: 28)
                .background(EnvBoxTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
