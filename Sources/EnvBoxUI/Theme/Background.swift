import EnvBoxCore
import SwiftUI

struct EnvBoxBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                EnvBoxTheme.background(for: scheme)
                Circle()
                    .fill(EnvBoxTheme.aqua.opacity(scheme == .dark ? 0.14 : 0.13))
                    .frame(width: proxy.size.width * 0.55)
                    .blur(radius: 150)
                    .offset(x: proxy.size.width * 0.26, y: -proxy.size.height * 0.38)
                Circle()
                    .fill(EnvBoxTheme.violet.opacity(scheme == .dark ? 0.13 : 0.08))
                    .frame(width: proxy.size.width * 0.48)
                    .blur(radius: 160)
                    .offset(x: -proxy.size.width * 0.30, y: proxy.size.height * 0.42)
                LinearGradient(
                    colors: [Color.white.opacity(scheme == .dark ? 0.018 : 0.34), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
