import AppFoundation
import SwiftUI
import UniformTypeIdentifiers

struct AppStoreConnectSettingsSection: View {
    @Environment(\.appFoundationTheme) private var foundationTheme

    @EnvironmentObject private var session: AppStoreConnectSession
    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var privateKeyPEM = ""
    @State private var isReplacingKey = false
    @State private var isImportingKey = false
    @State private var isConfirmingDisconnect = false

    private var isFormValid: Bool {
        !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section("App Store Connect") {
            switch session.connectionState {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking App Store Connect…")
                        .foregroundStyle(foundationTheme.secondaryForegroundColor)
                }
            case .disconnected:
                keyForm
            case let .connected(connectedKeyID):
                LabeledContent("Status", value: "Connected")
                LabeledContent("Key ID", value: connectedKeyID)

                if isReplacingKey {
                    keyForm
                    Button("Cancel Replacement") {
                        clearForm()
                        isReplacingKey = false
                        session.errorMessage = nil
                    }
                    .disabled(session.isWorking)
                } else {
                    Button("Replace API Key") {
                        clearForm()
                        isReplacingKey = true
                    }
                    .disabled(session.isWorking)
                }

                Button("Disconnect App Store Connect", role: .destructive) {
                    isConfirmingDisconnect = true
                }
                .disabled(session.isWorking)
            }
        }
        .fileImporter(
            isPresented: $isImportingKey,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                privateKeyPEM = try String(contentsOf: url, encoding: .utf8)
            } catch {
                session.errorMessage = "Could not read the .p8 file. Choose a valid private key."
            }
        }
        .confirmationDialog(
            "Disconnect App Store Connect?",
            isPresented: $isConfirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                clearForm()
                isReplacingKey = false
                session.disconnect()
            }
        } message: {
            Text("The API key will be deleted from this device. Your App Store Connect apps and builds will not be changed.")
        }
        .alert(
            "App Store Connect",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
        .onDisappear {
            // Never leave the imported private key in an inactive settings form.
            clearForm()
        }
    }

    private var keyForm: some View {
        Group {
            TextField("Issuer ID", text: $issuerID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(session.isWorking)

            TextField("Key ID", text: $keyID)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .disabled(session.isWorking)

            SecureField("Paste the .p8 private key", text: $privateKeyPEM)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .disabled(session.isWorking)

            Button {
                isImportingKey = true
            } label: {
                Label("Import .p8 Key File", systemImage: "doc.badge.plus")
            }
            .disabled(session.isWorking)

            Button {
                Task {
                    if await session.connect(
                        issuerID: issuerID,
                        keyID: keyID,
                        privateKeyPEM: privateKeyPEM
                    ) {
                        clearForm()
                        isReplacingKey = false
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if session.isWorking { ProgressView().controlSize(.small) }
                    Text(session.isWorking ? "Validating API Key…" : "Connect App Store Connect")
                }
            }
            .disabled(!isFormValid || session.isWorking)
        }
    }

    private func clearForm() {
        issuerID = ""
        keyID = ""
        privateKeyPEM = ""
    }
}
