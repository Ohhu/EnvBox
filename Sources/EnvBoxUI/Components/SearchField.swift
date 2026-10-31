import EnvBoxCore
import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    @Environment(\.colorScheme) private var scheme
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(isFocused ? 0.055 : 0.035))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    isFocused ? EnvBoxTheme.mint.opacity(0.30) : EnvBoxTheme.hairline(for: scheme),
                    lineWidth: 1
                )
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .accessibilityLabel(placeholder)
    }
}
