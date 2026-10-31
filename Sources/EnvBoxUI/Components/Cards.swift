import EnvBoxCore
import SwiftUI

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(scheme == .dark ? 0.14 : 0.12))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .glassPanel(cornerRadius: 15, elevated: false)
    }
}

struct InfoBanner: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = EnvBoxTheme.amber
    var actionTitle: String? = nil
    var isWorking = false
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(actionTitle)
                    }
                }
                .buttonStyle(EnvBoxSecondaryButtonStyle())
                .disabled(isWorking)
            }
        }
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.07 : 0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var tint: Color = EnvBoxTheme.mint
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(tint.opacity(scheme == .dark ? 0.14 : 0.11), in: Capsule(style: .continuous))
    }
}

struct SectionLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.8))
    }
}

struct PanelDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(EnvBoxTheme.hairline(for: scheme))
            .frame(height: 1)
    }
}
