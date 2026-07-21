import Foundation

enum BusinessModel: String, CaseIterable, Identifiable, Codable {
    case free = "Free"
    case paid = "Paid"
    case freemium = "Freemium"
    case subscription = "Subscription"
    case ads = "Ads"
    case internalUse = "Internal"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .free:
            "gift"
        case .paid:
            "tag"
        case .freemium:
            "sparkles"
        case .subscription:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .ads:
            "megaphone"
        case .internalUse:
            "lock.shield"
        }
    }
}
