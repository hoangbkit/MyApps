import AppFoundation
import SwiftData
import SwiftUI

struct AddNotesToAppView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \QuickNote.updatedAt, order: .reverse) private var notes: [QuickNote]
    @AppStorage(NoteSortOption.storageKey) private var noteSortRawValue = NoteSortOption.updated.rawValue
    @AppStorage(NoteSortOption.directionStorageKey) private var directionRawValue = SortDirection.descending.rawValue

    let app: ManagedApp

    @State private var selectedIDs: Set<UUID> = []

    private var noteSortOption: NoteSortOption {
        NoteSortOption(rawValue: noteSortRawValue) ?? .updated
    }

    private var sortDirection: SortDirection {
        SortDirection(rawValue: directionRawValue) ?? .descending
    }

    private var unassignedNotes: [QuickNote] {
        noteSortOption.sorted(notes.filter { $0.app == nil }, direction: sortDirection)
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
                        Group {
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
                                        .foregroundStyle(foundationTheme.primaryForegroundColor)
                                        .lineLimit(4)
                                        .multilineTextAlignment(.leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(foundationTheme.borderColor)
                    }
                    .scrollContentBackground(.hidden)
                    .myAppsPage()
                    .listStyle(.plain)
                }
            }
            .myAppsPage()
            .onChange(of: noteSortRawValue) { _, _ in
                directionRawValue = SortDirection.descending.rawValue
            }
            .navigationTitle("Add Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItemGroup(placement: .confirmationAction) {
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
