import SwiftUI
import UIKit

enum AppTheme {
    static let pagePadding: CGFloat = 16
    static let appCardRadius: CGFloat = 22
    static let noteCardRadius: CGFloat = 18

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.42, blue: 0.96),
            Color(red: 0.12, green: 0.58, blue: 1.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let appIconGradient = LinearGradient(
        colors: [
            Color(red: 0.02, green: 0.32, blue: 0.85),
            Color(red: 0.08, green: 0.58, blue: 1.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct SurfaceCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.055),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.065),
                radius: colorScheme == .dark ? 10 : 8,
                y: 3
            )
    }
}

extension View {
    func surfaceCard(cornerRadius: CGFloat) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius))
    }
}
