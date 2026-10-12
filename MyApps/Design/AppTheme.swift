import AppFoundation
import SwiftUI
import UIKit

enum AppTheme {
    static let pagePadding: CGFloat = 16
    static let appCardRadius: CGFloat = 22
    static let noteCardRadius: CGFloat = 18
}

/// MiLove's translucent surfaces and soft highlights, using the active
/// AppFoundation palette rather than assuming a dark background and white text.
struct MyAppsGlassBackground: View {
    @Environment(\.appFoundationTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            theme.backgroundColor
            if !reduceTransparency {
                theme.gradient.opacity(0.12)
                RadialGradient(
                    colors: [theme.accentColor.opacity(0.24), .clear],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 520
                )
                RadialGradient(
                    colors: [theme.appearance.gradientEnd.color.opacity(0.12), .clear],
                    center: .bottomLeading,
                    startRadius: 18,
                    endRadius: 480
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct MyAppsGlassSurface: View {
    @Environment(\.appFoundationTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = 0
    var showsBorder = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(theme.backgroundColor)
                shape.fill(theme.elevatedSurfaceColor)
            } else {
                shape.fill(theme.surfaceColor)
                shape.fill(LinearGradient(
                    colors: [
                        theme.appearance.gradientStart.color.opacity(colorScheme == .dark ? 0.075 : 0.18),
                        theme.appearance.gradientEnd.color.opacity(0.018),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            }
        }
        .overlay {
            if showsBorder {
                shape.strokeBorder(theme.borderColor, lineWidth: 0.8)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MyAppsPageModifier: ViewModifier {
    @Environment(\.appFoundationTheme) private var theme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                theme.primaryForegroundColor,
                theme.secondaryForegroundColor,
                theme.secondaryForegroundColor.opacity(0.75)
            )
            .tint(theme.accentColor)
            .background(MyAppsGlassBackground())
    }
}

private struct SurfaceCardModifier: ViewModifier {
    @Environment(\.appFoundationTheme) private var theme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(MyAppsGlassSurface(cornerRadius: cornerRadius, showsBorder: true))
            .shadow(color: theme.appearance.shadow.color.opacity(0.45), radius: 16, y: 9)
    }
}

extension View {
    func myAppsPage() -> some View {
        modifier(MyAppsPageModifier())
    }

    func surfaceCard(cornerRadius: CGFloat) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius))
    }
}

extension ThemeColor {
    var myAppsUIColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
