import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var apps: [ManagedApp]
    @Query private var notes: [QuickNote]
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    @State private var exportDocument: MyAppsBackupDocument?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingRestore: MyAppsBackupPackage?
    @State private var isConfirmingRestore = false
    @State private var resultMessage = ""
    @State private var isShowingResult = false

    private var unassignedNoteCount: Int {
        notes.filter { $0.app == nil }.count
    }

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceRawValue) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.rawValue, systemImage: appearance.symbolName)
                            .tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Storage") {
                LabeledContent("Mode", value: "Offline")
                Text("MyApps stores its library locally on this device with SwiftData.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Full Backup", systemImage: "square.and.arrow.up")
                }

                Button {
                    isImportingBackup = true
                } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backup & Restore")
            } footer: {
                Text("A .myappsbackup package includes all apps and notes as JSON metadata, with custom icons and attached images stored as separate files. Restoring replaces the current library after confirmation.")
            }

            Section("Library") {
                LabeledContent("Apps", value: apps.count.formatted())
                LabeledContent("All Notes", value: notes.count.formatted())
                LabeledContent("Unassigned Notes", value: unassignedNoteCount.formatted())
            }

            Section("About") {
                LabeledContent("Version", value: "1.0 P3.4.1")
                LabeledContent("Bundle ID", value: "com.hoangbkit.myapps")
            }
        }
        .font(.system(size: 17, weight: .regular, design: .rounded))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .fileExporter(
            isPresented: $isExportingBackup,
            document: exportDocument,
            contentType: .myAppsBackup,
            defaultFilename: "MyApps-P3.4.1-Backup.myappsbackup"
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                showResult("Backup exported successfully.")
            case let .failure(error):
                showResult("Could not export the backup. \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.myAppsBackup, .json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .confirmationDialog(
            "Replace Current Library?",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Restore and Replace Data", role: .destructive) {
                restorePendingBackup()
            }
            Button("Cancel", role: .cancel) {
                pendingRestore = nil
            }
        } message: {
            if let pendingRestore {
                Text(
                    "This backup contains \(pendingRestore.appCount) app\(pendingRestore.appCount == 1 ? "" : "s"), " +
                    "\(pendingRestore.noteCount) note\(pendingRestore.noteCount == 1 ? "" : "s"), and " +
                    "\(pendingRestore.attachmentCount) attachment\(pendingRestore.attachmentCount == 1 ? "" : "s"). " +
                    "Your current local library will be replaced."
                )
            }
        }
        .alert("Backup & Restore", isPresented: $isShowingResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    private func exportBackup() {
        let package = MyAppsBackupService.makePackage(apps: apps, notes: notes)
        exportDocument = MyAppsBackupDocument(package: package)
        isExportingBackup = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                throw MyAppsBackupError.unreadableFile
            }
            pendingRestore = try MyAppsBackupService.load(from: url)
            isConfirmingRestore = true
        } catch {
            pendingRestore = nil
            showResult("Could not read the backup. \(error.localizedDescription)")
        }
    }

    private func restorePendingBackup() {
        guard let pendingRestore else { return }

        do {
            try MyAppsBackupService.restore(pendingRestore, in: modelContext)
            self.pendingRestore = nil
            showResult("Backup restored successfully.")
        } catch {
            showResult("Could not restore the backup. \(error.localizedDescription)")
        }
    }

    private func showResult(_ message: String) {
        resultMessage = message
        isShowingResult = true
    }
}
