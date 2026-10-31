import EnvBoxCore
import SwiftUI

struct FilterChipBar: View {
    @Binding var selection: VariableFilter
    let options: [VariableFilter]
    var system: Bool = false
    var namespace: Namespace.ID

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(options) { option in
                Button {
                    withAnimation(EnvBoxTheme.animation(reduceMotion: reduceMotion, .snappy(duration: 0.2))) {
                        selection = option
                    }
                } label: {
                    Text(system ? option.systemTitle : option.title)
                        .font(.system(size: 11.5, weight: selection == option ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(selection == option ? Color.primary : EnvBoxTheme.textSecondary(for: scheme))
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background {
                            if selection == option {
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(scheme == .dark ? 0.11 : 0.075))
                                    .matchedGeometryEffect(id: "filter-selection", in: namespace)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
                                    }
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(scheme == .dark ? 0.035 : 0.025))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
        }
    }
}
