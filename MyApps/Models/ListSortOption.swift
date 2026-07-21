import Foundation

enum AppSortOption: String, CaseIterable, Identifiable, Sendable {
    case name
    case created
    case updated

    static let storageKey = "appSortOption"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name (A–Z)"
        case .created: "Newest Created"
        case .updated: "Recently Updated"
        }
    }

    var symbolName: String {
        switch self {
        case .name: "textformat"
        case .created: "calendar.badge.plus"
        case .updated: "clock.arrow.circlepath"
        }
    }
}

enum NoteSortOption: String, CaseIterable, Identifiable, Sendable {
    case created
    case updated

    static let storageKey = "noteSortOption"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .created: "Newest Created"
        case .updated: "Recently Updated"
        }
    }

    var symbolName: String {
        switch self {
        case .created: "calendar.badge.plus"
        case .updated: "clock.arrow.circlepath"
        }
    }
}
