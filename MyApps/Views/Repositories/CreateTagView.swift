import SwiftUI

struct CreateTagView: View {
    let repository: GitHubRepository
    let targetSHA: String
    let targetDescription: String?
    let existingTags: [GitHubTag]
    let client: GitHubAPIClient?
    let onCreated: () -> Void

    @StateObject private var model: CreateTagViewModel
    @State private var isConfirmingCreate = false
    @Environment(\.dismiss) private var dismiss

    init(
        repository: GitHubRepository,
        targetSHA: String,
        targetDescription: String? = nil,
        existingTags: [GitHubTag],
        client: GitHubAPIClient?,
        onCreated: @escaping () -> Void
    ) {
        self.repository = repository
        self.targetSHA = targetSHA
        self.targetDescription = targetDescription
        self.existingTags = existingTags
        self.client = client
        self.onCreated = onCreated
        _model = StateObject(
            wrappedValue: CreateTagViewModel(existingTags: existingTags)
        )
    }

    var body: some View {
        Form {
            Section("Tag") {
                TextField("1.13", text: $model.name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Type", selection: $model.kind) {
                    ForEach(GitHubTagKind.allCases) { kind in
                        Text(kind.rawValue)
                            .tag(kind)
                    }
                }

                if model.kind == .annotated {
                    TextField("Annotation message", text: $model.message, axis: .vertical)
                        .lineLimit(3...6)
                }
            }

            Section("Target") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commit")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(targetSHA)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let targetDescription {
                    Text(targetDescription)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if let validationError = model.validationError {
                Section {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    isConfirmingCreate = true
                } label: {
                    if model.isCreating {
                        HStack {
                            ProgressView()
                            Text("Creating…")
                        }
                    } else {
                        Label("Create Tag", systemImage: "tag")
                    }
                }
                .disabled(
                    model.isCreating ||
                    !model.canCreate ||
                    !repository.canAttemptWrite
                )
            } footer: {
                if !repository.canAttemptWrite {
                    Text(repository.isArchived ? "Archived repositories are read-only." : "This GitHub connection cannot create tags in this repository.")
                } else {
                    Text("The tag will point exactly to the commit SHA shown above.")
                }
            }
        }
        .navigationTitle("Create Tag")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Create Tag?",
            isPresented: $isConfirmingCreate,
            titleVisibility: .visible
        ) {
            Button("Create \(model.normalizedName)") {
                Task {
                    // Tag creation raises its own success alert. Refresh the
                    // parent only after Done dismisses that alert.
                    await model.create(
                        repository: repository,
                        targetSHA: targetSHA,
                        client: client
                    )
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\(model.normalizedName) → \(String(targetSHA.prefix(12))) " +
                "(\(model.kind.rawValue.lowercased()))."
            )
        }
        .alert(
            "Tag",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(
            "Tag Created",
            isPresented: Binding(
                get: { model.successMessage != nil },
                set: { if !$0 { model.successMessage = nil } }
            )
        ) {
            Button("Done") {
                onCreated()
                dismiss()
            }
        } message: {
            Text(model.successMessage ?? "")
        }
    }
}
