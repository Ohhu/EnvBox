import EnvBoxCore
import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 36
    var showsShadow = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.20, blue: 0.46),
                            Color(red: 0.16, green: 0.55, blue: 0.58),
                            EnvBoxTheme.mint
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: size * 0.075)
                .offset(x: size * 0.28, y: -size * 0.28)
                .blendMode(.softLight)
        }
        .frame(width: size, height: size)
        .shadow(color: EnvBoxTheme.aqua.opacity(showsShadow ? 0.28 : 0), radius: size * 0.32, y: size * 0.13)
    }
}

struct ProfileGlyph: View {
    let tint: ProfileTint
    let symbol: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(tint.gradient)
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
            Image(systemName: symbol.isEmpty ? "shippingbox.fill" : symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.primary.opacity(0.22), radius: size * 0.25, y: size * 0.09)
    }
}
