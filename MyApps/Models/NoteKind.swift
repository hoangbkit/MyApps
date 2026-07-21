import Foundation

// Legacy values are retained so existing P1/P2 SwiftData stores can migrate
// into P3's single Markdown note format without losing content.
enum NoteKind: String, Codable {
    case markdown
    case text
    case checklist
}
