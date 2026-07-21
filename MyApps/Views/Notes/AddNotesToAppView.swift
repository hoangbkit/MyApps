import SwiftData
import SwiftUI

struct AddNotesToAppView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \QuickNote.updatedAt, order: .reverse) private var notes: [QuickNote]
    @AppStorage(NoteSortOption.storageKey) private var noteSortRawValue = NoteSortOption.updated.rawValue

    let app: ManagedApp

    @State private var selectedIDs: Set<UUID> = []

    private var noteSortOption: NoteSortOption {
        NoteSortOption(rawValue: noteSortRawValue) ?? .updated
    }

    private var unassignedNotes: [QuickNote] {
        notes
            .filter { $0.app == nil }
            .sorted { lhs, rhs in
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
        NavigationStack {
            Group {
                if unassignedNotes.isEmpty {
                    ContentUnavailableView(
                        "No Unassigned Notes",
                        systemImage: "tray",
                        description: Text("Create a note from the global Notes screen first.")
                    )
                } else {
                    List(unassignedNotes) { note in
                        Button {
                            if selectedIDs.contains(note.id) {
                                selectedIDs.remove(note.id)
                            } else {
                                selectedIDs.insert(note.id)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                RoundedCheckbox(isChecked: selectedIDs.contains(note.id), size: 20)
                                    .padding(.top, 2)

                                Text(note.plainTextPreview.isEmpty ? "Empty note" : note.plainTextPreview)
                                    .font(.system(size: 17, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItemGroup(placement: .confirmationAction) {
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

                    Button("Add") { assignSelectedNotes() }
                        .fontWeight(.semibold)
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func assignSelectedNotes() {
        let now = Date()
        for note in unassignedNotes where selectedIDs.contains(note.id) {
            note.app = app
            note.updatedAt = now
        }
        app.updatedAt = now
        dismiss()
    }
}
