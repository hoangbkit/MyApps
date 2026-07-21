import Foundation
import SwiftData

@MainActor
enum P3MigrationService {
    static func run(in context: ModelContext) {
        do {
            let apps = try context.fetch(FetchDescriptor<ManagedApp>())
            let notes = try context.fetch(FetchDescriptor<QuickNote>())
            var changed = false

            for app in apps {
                if app.stageRawValue != ProjectStage.app.rawValue {
                    app.stage = .app
                    changed = true
                }

                if ProjectStatus(rawValue: app.projectStatusRawValue) == nil {
                    app.projectStatus = .building
                    changed = true
                }
            }

            for note in notes where note.legacyKind != .markdown || !note.title.isEmpty {
                let legacyTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let existingBody = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                var sections: [String] = []

                if !legacyTitle.isEmpty {
                    sections.append(legacyTitle)
                }

                if !existingBody.isEmpty {
                    sections.append(existingBody)
                }

                if note.legacyKind == .checklist || !note.checklistItems.isEmpty {
                    let tasks = note.checklistItems
                        .sorted {
                            if $0.sortOrder == $1.sortOrder { return $0.createdAt < $1.createdAt }
                            return $0.sortOrder < $1.sortOrder
                        }
                        .compactMap { item -> String? in
                            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return nil }
                            return "- [\(item.isCompleted ? "x" : " ")] \(text)"
                        }

                    if !tasks.isEmpty {
                        sections.append(tasks.joined(separator: "\n"))
                    }
                }

                note.body = sections.joined(separator: "\n\n")
                note.title = ""
                note.legacyKind = .markdown
                note.updatedAt = Date()

                for item in Array(note.checklistItems) {
                    context.delete(item)
                }
                changed = true
            }

            if changed {
                try context.save()
            }
        } catch {
            assertionFailure("P3 migration failed: \(error)")
        }
    }
}
