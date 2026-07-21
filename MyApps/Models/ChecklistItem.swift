import Foundation
import SwiftData

@Model
final class ChecklistItem {
    var id: UUID = UUID()
    var text: String = ""
    var isCompleted: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var note: QuickNote?

    init(text: String = "", isCompleted: Bool = false, sortOrder: Int = 0) {
        self.id = UUID()
        self.text = text
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
