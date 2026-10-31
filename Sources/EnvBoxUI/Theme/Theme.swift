import EnvBoxCore
import SwiftUI

enum EnvBoxTheme {
    static let mint = Color(red: 0.35, green: 0.93, blue: 0.78)
    static let aqua = Color(red: 0.28, green: 0.76, blue: 0.90)
    static let indigo = Color(red: 0.43, green: 0.49, blue: 1.0)
    static let violet = Color(red: 0.66, green: 0.48, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let rose = Color(red: 1.0, green: 0.44, blue: 0.57)

    static let accentGradient = LinearGradient(
        colors: [mint, aqua, indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pagePadding: CGFloat = 30
    static let panelRadius: CGFloat = 20

    static func background(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.055, blue: 0.10),
                    Color(red: 0.055, green: 0.075, blue: 0.13),
                    Color(red: 0.035, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.965, green: 0.975, blue: 0.995),
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color(red: 0.955, green: 0.965, blue: 0.985)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.54)
    }

    static func hairline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    static func subtlyRaised(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.038)
    }

    static func animation(reduceMotion: Bool, _ animation: Animation = .snappy(duration: 0.26)) -> Animation? {
        reduceMotion ? nil : animation
    }
}

extension ProfileTint {
    var displayName: String {
        switch self {
        case .aurora: return "极光"
        case .ocean: return "海洋"
        case .ember: return "余烬"
        case .orchid: return "兰紫"
        case .lime: return "青柠"
        case .slate: return "石墨"
        }
    }

    var primary: Color {
        switch self {
        case .aurora: return EnvBoxTheme.mint
        case .ocean: return Color(red: 0.31, green: 0.61, blue: 1.0)
        case .ember: return Color(red: 1.0, green: 0.56, blue: 0.31)
        case .orchid: return Color(red: 0.76, green: 0.49, blue: 1.0)
        case .lime: return Color(red: 0.60, green: 0.86, blue: 0.33)
        case .slate: return Color(red: 0.58, green: 0.65, blue: 0.76)
        }
    }

    var secondary: Color {
        switch self {
        case .aurora: return EnvBoxTheme.aqua
        case .ocean: return EnvBoxTheme.indigo
        case .ember: return EnvBoxTheme.rose
        case .orchid: return Color(red: 0.98, green: 0.46, blue: 0.74)
        case .lime: return EnvBoxTheme.mint
        case .slate: return Color(red: 0.34, green: 0.43, blue: 0.56)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum ProfileSymbols {
    static let options: [String] = [
        "shippingbox.fill",
        "hammer.fill",
        "terminal.fill",
        "curlybraces",
        "swift",
        "leaf.fill",
        "flame.fill",
        "cloud.fill",
        "cylinder.split.1x2.fill",
        "sparkles"
    ]
}

extension View {
    func glassPanel(cornerRadius: CGFloat = EnvBoxTheme.panelRadius, elevated: Bool = true) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, elevated: elevated))
    }

    func envboxAnimation<V: Equatable>(_ animation: Animation = .snappy(duration: 0.26), value: V, reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let elevated: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(scheme == .dark ? 0.035 : 0.30),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(EnvBoxTheme.hairline(for: scheme), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(elevated ? (scheme == .dark ? 0.22 : 0.07) : 0),
                radius: elevated ? 22 : 0,
                x: 0,
                y: elevated ? 10 : 0
            )
    }
}
