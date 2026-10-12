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
    @AppStorage(NoteSortOption.directionStorageKey) private var directionRawValue = SortDirection.descending.rawValue

    @State private var scope: NotesScope = .unassigned
    @State private var activeNote: QuickNote?
    @State private var activeNoteStartsEditing = false

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    private var displayedNotes: [QuickNote] {
        let scoped: [QuickNote]
        switch scope {
        case .unassigned: scoped = notes.filter { $0.app == nil }
        case .all: scoped = notes
        }
        return noteSortOption.sorted(scoped, direction: sortDirection)
    }

    private var noteSortOption: NoteSortOption {
        NoteSortOption(rawValue: noteSortRawValue) ?? .updated
    }

    private var sortDirection: SortDirection {
        SortDirection(rawValue: directionRawValue) ?? .descending
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
                    Section("Sort By") {
                        Picker("Sort Field", selection: $noteSortRawValue) {
                            ForEach(NoteSortOption.allCases) { option in
                                Label(option.title, systemImage: option.symbolName)
                                    .tag(option.rawValue)
                            }
                        }
                    }
                    Section("Order") {
                        Picker("Sort Order", selection: $directionRawValue) {
                            ForEach(SortDirection.allCases) { direction in
                                Label(direction.title(isText: false), systemImage: direction.symbolName)
                                    .tag(direction.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort Notes by \(noteSortOption.title), \(sortDirection.title(isText: false))")

                Button {
                    createNote()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Note")
            }
        }
        .onChange(of: noteSortRawValue) { _, _ in
            directionRawValue = SortDirection.descending.rawValue
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
