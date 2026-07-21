import SwiftData
import SwiftUI

private enum NotesScope: String, CaseIterable, Identifiable {
    case unassigned = "Unassigned"
    case all = "All"

    var id: String { rawValue }
}

struct NotesInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QuickNote.updatedAt, order: .reverse) private var notes: [QuickNote]
    @AppStorage(NoteSortOption.storageKey) private var noteSortRawValue = NoteSortOption.updated.rawValue

    @State private var scope: NotesScope = .unassigned
    @State private var activeNote: QuickNote?
    @State private var activeNoteStartsEditing = false

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    private var displayedNotes: [QuickNote] {
        let scoped = switch scope {
        case .unassigned: notes.filter { $0.app == nil }
        case .all: notes
        }

        return scoped.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            switch noteSortOption {
            case .created:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            case .updated:
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }


    private var noteSortOption: NoteSortOption {
        NoteSortOption(rawValue: noteSortRawValue) ?? .updated
    }

    var body: some View {
        Group {
            if displayedNotes.isEmpty {
                EmptyStateView(
                    symbol: scope == .unassigned ? "tray" : "note.text",
                    title: scope == .unassigned ? "No unassigned notes" : "No notes yet",
                    message: "Use the plus button to capture a Markdown note."
                )
            } else {
                notesGrid
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Scope", selection: $scope) {
                        ForEach(NotesScope.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                } label: {
                    Image(systemName: scope == .unassigned ? "tray" : "note.text")
                }
                .accessibilityLabel("Show \(scope.rawValue) Notes")

                Menu {
                    Picker("Sort Notes", selection: $noteSortRawValue) {
                        ForEach(NoteSortOption.allCases) { option in
                            Label(option.title, systemImage: option.symbolName)
                                .tag(option.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort Notes by \(noteSortOption.title)")

                Button {
                    createNote()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Note")
            }
        }
        .navigationDestination(isPresented: activeNoteBinding) {
            if let activeNote {
                NoteEditorView(note: activeNote, startsInEditMode: activeNoteStartsEditing)
            }
        }
    }

    private var notesGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(displayedNotes) { note in
                    NoteCardView(note: note, showsApp: true) {
                        activeNoteStartsEditing = false
                        activeNote = note
                    } onTogglePin: {
                        note.isPinned.toggle()
                        note.updatedAt = Date()
                        note.app?.updatedAt = Date()
                    } onDelete: {
                        let app = note.app
                        modelContext.delete(note)
                        app?.updatedAt = Date()
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var activeNoteBinding: Binding<Bool> {
        Binding(
            get: { activeNote != nil },
            set: { if !$0 { activeNote = nil } }
        )
    }

    private func createNote() {
        let note = QuickNote()
        modelContext.insert(note)
        activeNoteStartsEditing = true
        activeNote = note
    }
}
