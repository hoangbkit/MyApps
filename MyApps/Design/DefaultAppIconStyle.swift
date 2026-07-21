import SwiftUI

enum DefaultAppIconStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case ocean
    case sunset
    case grape
    case mint
    case rose
    case midnight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean: "Ocean"
        case .sunset: "Sunset"
        case .grape: "Grape"
        case .mint: "Mint"
        case .rose: "Rose"
        case .midnight: "Midnight"
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var colors: [Color] {
        switch self {
        case .ocean:
            [
                Color(red: 0.02, green: 0.32, blue: 0.85),
                Color(red: 0.08, green: 0.66, blue: 1.00)
            ]
        case .sunset:
            [
                Color(red: 1.00, green: 0.35, blue: 0.28),
                Color(red: 1.00, green: 0.68, blue: 0.20)
            ]
        case .grape:
            [
                Color(red: 0.39, green: 0.15, blue: 0.88),
                Color(red: 0.76, green: 0.28, blue: 0.92)
            ]
        case .mint:
            [
                Color(red: 0.02, green: 0.56, blue: 0.48),
                Color(red: 0.19, green: 0.82, blue: 0.61)
            ]
        case .rose:
            [
                Color(red: 0.83, green: 0.12, blue: 0.42),
                Color(red: 1.00, green: 0.38, blue: 0.58)
            ]
        case .midnight:
            [
                Color(red: 0.08, green: 0.10, blue: 0.19),
                Color(red: 0.25, green: 0.31, blue: 0.48)
            ]
        }
    }
}
