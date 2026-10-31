import EnvBoxCore
import SwiftUI

struct ToastOverlay: View {
    let toast: ToastMessage?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast {
                HStack(spacing: 9) {
                    Image(systemName: icon(for: toast.style))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint(for: toast.style))
                    Text(toast.text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 15)
                .frame(minHeight: 36)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.10), radius: 18, y: 8)
                .padding(.bottom, 22)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
                .id(toast.id)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: toast)
        .allowsHitTesting(false)
    }

    private func icon(for style: ToastStyle) -> String {
        switch style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func tint(for style: ToastStyle) -> Color {
        switch style {
        case .success: return EnvBoxTheme.mint
        case .info: return EnvBoxTheme.aqua
        case .warning: return EnvBoxTheme.amber
        case .error: return EnvBoxTheme.rose
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(EnvBoxTheme.mint.opacity(0.85))
                .frame(width: 50, height: 50)
                .background(EnvBoxTheme.mint.opacity(0.08), in: Circle())
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(EnvBoxSecondaryButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }
}
