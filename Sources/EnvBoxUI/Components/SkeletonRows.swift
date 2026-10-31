import EnvBoxCore
import SwiftUI

struct SkeletonVariableRows: View {
    var rows: Int = 6

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 130 + CGFloat((index * 19) % 55), height: 11)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 52, height: 20)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                if index < rows - 1 { PanelDivider() }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}
