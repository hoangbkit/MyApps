import SwiftData
import SwiftUI

struct AppDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let app: ManagedApp

    @AppStorage(NoteSortOption.storageKey) private var noteSortRawValue = NoteSortOption.updated.rawValue
    @State private var activeNote: QuickNote?
    @State private var activeNoteStartsEditing = false
    @State private var isPresentingEditor = false
    @State private var isPresentingAddNotes = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingPermanentDelete = false

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

    private var noteSortOption: NoteSortOption {
        NoteSortOption(rawValue: noteSortRawValue) ?? .updated
    }

    private var sortedNotes: [QuickNote] {
        app.notes.sorted { lhs, rhs in
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

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if sortedNotes.isEmpty {
                    emptyNotesView
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(sortedNotes) { note in
                            NoteCardView(note: note) {
                                activeNoteStartsEditing = false
                                activeNote = note
                            } onTogglePin: {
                                note.isPinned.toggle()
                                note.updatedAt = Date()
                                app.updatedAt = Date()
                            } onDelete: {
                                modelContext.delete(note)
                                app.updatedAt = Date()
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                navigationTitle
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
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

                Menu {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Label("Edit App", systemImage: "pencil")
                    }

                    Button {
                        isPresentingAddNotes = true
                    } label: {
                        Label("Add Existing Notes", systemImage: "text.badge.plus")
                    }

                    Button {
                        app.setPinned(!app.isPinned)
                    } label: {
                        Label(app.isPinned ? "Unpin App" : "Pin App", systemImage: app.isPinned ? "pin.slash" : "pin")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete App", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("App Actions")
            }
        }
        .navigationDestination(isPresented: activeNoteBinding) {
            if let activeNote {
                NoteEditorView(note: activeNote, startsInEditMode: activeNoteStartsEditing)
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            AppEditorView(app: app)
        }
        .sheet(isPresented: $isPresentingAddNotes) {
            AddNotesToAppView(app: app)
        }
        .confirmationDialog(
            "Delete “\(app.name)”?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            if app.notes.isEmpty {
                Button("Delete App", role: .destructive) {
                    ProjectDeletionService.deleteProjectKeepingNotes(app, in: modelContext)
                    dismiss()
                }
            } else {
                Button("Delete App, Keep Notes") {
                    ProjectDeletionService.deleteProjectKeepingNotes(app, in: modelContext)
                    dismiss()
                }

                Button("Delete App and Notes", role: .destructive) {
                    isConfirmingPermanentDelete = true
                }
            }
        } message: {
            if app.notes.isEmpty {
                Text("This removes the app from MyApps.")
            } else {
                Text("This app contains \(noteCountLabel). Keep its notes as unassigned notes, or delete them with the app.")
            }
        }
        .confirmationDialog(
            "Permanently delete “\(app.name)”?",
            isPresented: $isConfirmingPermanentDelete,
            titleVisibility: .visible
        ) {
            Button("Delete App and \(noteCountLabel)", role: .destructive) {
                ProjectDeletionService.deleteProjectAndNotes(app, in: modelContext)
                dismiss()
            }
        } message: {
            Text("This permanently deletes every attached note and image. This cannot be undone.")
        }
    }

    private var navigationTitle: some View {
        HStack(spacing: 7) {
            AppIconView(app: app, size: 26)

            Text(app.name)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyNotesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text("No notes yet")
                .font(.system(size: 19, weight: .semibold, design: .rounded))

            Text("Use the plus button to create a Markdown note.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 56)
    }

    private var activeNoteBinding: Binding<Bool> {
        Binding(
            get: { activeNote != nil },
            set: { if !$0 { activeNote = nil } }
        )
    }

    private var noteCountLabel: String {
        "\(app.notes.count) note\(app.notes.count == 1 ? "" : "s")"
    }

    private func createNote() {
        let note = QuickNote()
        modelContext.insert(note)
        note.app = app
        app.updatedAt = Date()
        activeNoteStartsEditing = true
        activeNote = note
    }
}
