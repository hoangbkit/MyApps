import Foundation

/// A shared direction vocabulary across the four sortable root tabs.
enum SortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending, descending

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        }
    }

    func title(isText: Bool) -> String {
        switch (self, isText) {
        case (.ascending, true): "Ascending (A–Z)"
        case (.descending, true): "Descending (Z–A)"
        case (.ascending, false): "Ascending (Oldest First)"
        case (.descending, false): "Descending (Newest First)"
        }
    }

    static func defaultForText(_ isText: Bool) -> Self {
        isText ? .ascending : .descending
    }
}

enum AppSortOption: String, CaseIterable, Identifiable, Sendable {
    case name, created, updated

    // Keep the existing key to preserve users' current selected field.
    static let storageKey = "appSortOption"
    static let directionStorageKey = "myapps.projects.sortDirection"

    var id: Self { self }

    var title: String {
        switch self {
        case .name: "Name"
        case .created: "Created"
        case .updated: "Updated"
        }
    }

    var symbolName: String {
        switch self {
        case .name: "textformat.abc"
        case .created: "calendar.badge.plus"
        case .updated: "clock.arrow.circlepath"
        }
    }

    var isText: Bool { self == .name }
}

enum NoteSortOption: String, CaseIterable, Identifiable, Sendable {
    case created, updated

    static let storageKey = "noteSortOption"
    static let directionStorageKey = "myapps.notes.sortDirection"

    var id: Self { self }

    var title: String {
        switch self {
        case .created: "Created"
        case .updated: "Updated"
        }
    }

    var symbolName: String {
        switch self {
        case .created: "calendar.badge.plus"
        case .updated: "clock.arrow.circlepath"
        }
    }

    /// Shared by Notes, Project Notes and Add Notes: pinned first, then
    /// selected chronological order, with a stable tie-breaker.
    @MainActor
    func sorted(_ notes: [QuickNote], direction: SortDirection) -> [QuickNote] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            let left = self == .created ? lhs.createdAt : lhs.updatedAt
            let right = self == .created ? rhs.createdAt : rhs.updatedAt
            if left != right {
                return direction == .ascending ? left < right : left > right
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
