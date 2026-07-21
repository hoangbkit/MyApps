import Foundation
import SwiftUI

enum ProjectStatus: String, CaseIterable, Identifiable, Codable {
    case idea = "Idea"
    case building = "Building"
    case testing = "Testing"
    case ready = "Ready"
    case live = "Live"
    case paused = "Paused"
    case needsAttention = "Needs Attention"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .idea:
            "lightbulb.fill"
        case .building:
            "hammer"
        case .testing:
            "iphone.gen3.radiowaves.left.and.right"
        case .ready:
            "checkmark.seal"
        case .live:
            "checkmark.circle.fill"
        case .paused:
            "pause.circle"
        case .needsAttention:
            "exclamationmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .idea:
            Color(red: 0.92, green: 0.61, blue: 0.08)
        case .building:
            .blue
        case .testing:
            .orange
        case .ready:
            .purple
        case .live:
            .green
        case .paused:
            .gray
        case .needsAttention:
            .red
        }
    }
}
