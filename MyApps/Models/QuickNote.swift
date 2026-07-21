import Foundation
import SwiftData

@Model
final class QuickNote {
    var id: UUID = UUID()

    // P3 always writes `markdown`. Older values are retained for automatic migration.
    var kindRawValue: String = NoteKind.markdown.rawValue
    var title: String = ""
    var body: String = ""
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var app: ManagedApp?

    // Legacy P1/P2 checklist records. P3 migrates them into Markdown task lines.
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.note)
    var checklistItems: [ChecklistItem] = []

    @Relationship(deleteRule: .cascade, inverse: \NoteAttachment.note)
    var attachments: [NoteAttachment] = []

    init(markdown: String = "") {
        self.id = UUID()
        self.kindRawValue = NoteKind.markdown.rawValue
        self.title = ""
        self.body = markdown
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var legacyKind: NoteKind {
        get { NoteKind(rawValue: kindRawValue) ?? .markdown }
        set { kindRawValue = newValue.rawValue }
    }

    var isEffectivelyEmpty: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }

    var openTaskCount: Int {
        MarkdownTaskParser.openTaskCount(in: body)
    }

    var plainTextPreview: String {
        MarkdownTextExtractor.plainText(from: body)
    }
}
