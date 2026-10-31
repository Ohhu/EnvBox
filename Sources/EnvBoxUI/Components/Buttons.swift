import EnvBoxCore
import SwiftUI

struct EnvBoxPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.035, green: 0.10, blue: 0.12))
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background {
                Capsule(style: .continuous)
                    .fill(EnvBoxTheme.accentGradient)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(configuration.isPressed ? 0.10 : 0.0))
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.44), lineWidth: 1)
            }
            .shadow(color: EnvBoxTheme.aqua.opacity(isEnabled ? 0.24 : 0), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct EnvBoxSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(.primary.opacity(0.86))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                Capsule(style: .continuous)
                    .fill(EnvBoxTheme.subtlyRaised(for: scheme))
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(configuration.isPressed ? 0.05 : 0))
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color = .primary
    var size: CGFloat = 28
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tint.opacity(isHovering ? 1 : 0.90))
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
    }
}

struct EnvBoxSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = EnvBoxTheme.mint
    var accessibilityLabel: String = "切换"

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            withAnimation(EnvBoxTheme.animation(reduceMotion: reduceMotion, .snappy(duration: 0.18))) {
                isOn.toggle()
            }
        } label: {
            Capsule(style: .continuous)
                .fill(
                    isOn
                        ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.17 : 0.13))
                )
                .frame(width: 34, height: 20)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isOn ? tint.opacity(0.50) : Color.primary.opacity(0.06), lineWidth: 0.5)
                }
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "已启用" : "已停用")
        .help(isOn ? "点击停用" : "点击启用")
        .opacity(isEnabled ? 1 : 0.40)
    }
}

struct LabeledSwitch: View {
    let title: String
    let subtitle: String
    var tint: Color = EnvBoxTheme.mint
    @Binding var isOn: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            Spacer(minLength: 0)
            EnvBoxSwitch(isOn: $isOn, tint: tint, accessibilityLabel: title)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(scheme == .dark ? 0.035 : 0.028))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
        }
    }
}

struct ChipToggle: View {
    let title: String
    let systemName: String
    let isOn: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isOn ? EnvBoxTheme.mint : EnvBoxTheme.textSecondary(for: scheme))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                Capsule(style: .continuous)
                    .fill(isOn ? EnvBoxTheme.mint.opacity(0.12) : Color.primary.opacity(isHovering ? 0.05 : 0.025))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isOn ? EnvBoxTheme.mint.opacity(0.24) : EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
    }
}
