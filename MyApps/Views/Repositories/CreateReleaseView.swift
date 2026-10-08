import SwiftUI

struct CreateReleaseView: View {
    let repository: GitHubRepository
    let tags: [GitHubTag]
    let existingReleases: [GitHubRelease]
    let client: GitHubAPIClient?
    let onCreated: () -> Void

    @StateObject private var model: CreateReleaseViewModel
    @State private var isConfirmingCreate = false
    @Environment(\.dismiss) private var dismiss

    private var sortedTags: [GitHubTag] {
        tags.sorted { lhs, rhs in
            let lhsBuild = lhs.name.hasPrefix("mycli-build-")
            let rhsBuild = rhs.name.hasPrefix("mycli-build-")

            if lhsBuild != rhsBuild {
                return !lhsBuild
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
        }
    }

    init(
        repository: GitHubRepository,
        tags: [GitHubTag],
        existingReleases: [GitHubRelease],
        client: GitHubAPIClient?,
        onCreated: @escaping () -> Void
    ) {
        self.repository = repository
        self.tags = tags
        self.existingReleases = existingReleases
        self.client = client
        self.onCreated = onCreated
        _model = StateObject(
            wrappedValue: CreateReleaseViewModel(
                repositoryName: repository.name,
                tags: tags,
                existingReleases: existingReleases
            )
        )
    }

    var body: some View {
        Form {
            Section("Release") {
                Picker("Tag", selection: Binding(
                    get: { model.selectedTagName },
                    set: { model.selectTag($0) }
                )) {
                    ForEach(sortedTags) { tag in
                        Text(tag.name)
                            .tag(tag.name)
                    }
                }

                TextField("Release title", text: $model.title)

                TextField("Release notes", text: $model.notes, axis: .vertical)
                    .lineLimit(5...12)
            }
            .disabled(model.isCreating)

            Section("Options") {
                Toggle("Prerelease", isOn: $model.isPrerelease)
                Toggle("Draft", isOn: $model.isDraft)
            }
            .disabled(model.isCreating)

            if let validationMessage = model.validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
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
                        Label("Create Release", systemImage: "shippingbox")
                    }
                }
                .disabled(
                    model.isCreating ||
                    !model.canCreate ||
                    !repository.canAttemptWrite
                )
            } footer: {
                if tags.isEmpty {
                    Text("Create a Git tag first.")
                } else if !repository.canAttemptWrite {
                    Text(repository.isArchived ? "Archived repositories are read-only." : "This GitHub connection cannot create releases in this repository.")
                } else {
                    Text("Release assets are not uploaded by MyApps in this version.")
                }
            }
        }
        .navigationTitle("Create Release")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Create Release?",
            isPresented: $isConfirmingCreate,
            titleVisibility: .visible
        ) {
            Button("Create \(model.selectedTagName)") {
                Task {
                    await model.create(repository: repository, client: client)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\(model.title) · \(model.selectedTagName)" +
                (model.isDraft ? " · Draft" : "") +
                (model.isPrerelease ? " · Prerelease" : "")
            )
        }
        .alert(
            model.successMessage == nil ? "Release Failed" : "Release Created",
            isPresented: Binding(
                get: { model.errorMessage != nil || model.successMessage != nil },
                set: {
                    if !$0 {
                        model.errorMessage = nil
                        model.successMessage = nil
                    }
                }
            )
        ) {
            if model.successMessage != nil {
                Button("Done") {
                    onCreated()
                    dismiss()
                }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(model.successMessage ?? model.errorMessage ?? "")
        }
    }
}
