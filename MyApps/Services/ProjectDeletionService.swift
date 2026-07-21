import Foundation
import SwiftData

@MainActor
enum ProjectDeletionService {
    static func deleteProjectKeepingNotes(_ project: ManagedApp, in context: ModelContext) {
        let now = Date()
        for note in Array(project.notes) {
            note.app = nil
            note.updatedAt = now
        }
        context.delete(project)
    }

    static func deleteProjectAndNotes(_ project: ManagedApp, in context: ModelContext) {
        for note in Array(project.notes) {
            context.delete(note)
        }
        context.delete(project)
    }
}
