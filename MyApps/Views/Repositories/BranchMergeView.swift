import SwiftUI

struct BranchMergeView: View {
    let repository: GitHubRepository
    let sourceBranch: GitHubBranch
    let branches: [GitHubBranch]
    let client: GitHubAPIClient?
    let onMerged: () -> Void

    @StateObject private var model: BranchMergeViewModel
    @State private var isConfirmingMerge = false
    @Environment(\.dismiss) private var dismiss

    private var destinations: [GitHubBranch] {
        branches
            .filter { $0.name != sourceBranch.name }
            .sorted { lhs, rhs in
                if lhs.name == repository.defaultBranch { return true }
                if rhs.name == repository.defaultBranch { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    init(
        repository: GitHubRepository,
        sourceBranch: GitHubBranch,
        branches: [GitHubBranch],
        defaultDestination: String,
        client: GitHubAPIClient?,
        onMerged: @escaping () -> Void
    ) {
        self.repository = repository
        self.sourceBranch = sourceBranch
        self.branches = branches
        self.client = client
        self.onMerged = onMerged
        _model = StateObject(
            wrappedValue: BranchMergeViewModel(
                sourceBranch: sourceBranch,
                defaultDestination: defaultDestination
            )
        )
    }

    var body: some View {
        List {
            Section("Direction") {
                LabeledContent("Source", value: sourceBranch.name)

                Picker("Destination", selection: $model.destinationName) {
                    ForEach(destinations) { branch in
                        Text(branch.name)
                            .tag(branch.name)
                    }
                }
            }

            Section("Current Heads") {
                LabeledContent("Source", value: String(model.sourceHeadSHA.prefix(12)))

                if let destinationHeadSHA = model.destinationHeadSHA {
                    LabeledContent("Destination", value: String(destinationHeadSHA.prefix(12)))
                }
            }

            Section("Preview") {
                if model.isLoading {
                    ProgressView("Comparing branches…")
                } else if let comparison = model.comparison {
                    LabeledContent("Ahead", value: comparison.aheadBy.formatted())
                    LabeledContent("Behind", value: comparison.behindBy.formatted())

                    if comparison.aheadBy == 0 {
                        Text("\(model.destinationName) already contains the source branch.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(comparison.commits.prefix(10)) { commit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commit.subject)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text(commit.shortSHA)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if comparison.commits.count > 10 {
                            Text("+ \(comparison.commits.count - 10) more commits")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Choose a destination branch to preview the merge.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    isConfirmingMerge = true
                } label: {
                    if model.isMerging {
                        HStack {
                            ProgressView()
                            Text("Merging…")
                        }
                    } else {
                        Label(
                            "Merge \(sourceBranch.name) into \(model.destinationName)",
                            systemImage: "arrow.triangle.merge"
                        )
                    }
                }
                .disabled(
                    model.isLoading ||
                    model.isMerging ||
                    model.comparison?.aheadBy == 0 ||
                    model.comparison == nil ||
                    !repository.canAttemptWrite
                )
            } footer: {
                Text("Before writing, MyApps refreshes both branch heads and recomputes the comparison.")
            }
        }
        .navigationTitle("Merge")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.destinationName) {
            await model.prepare(repository: repository, client: client)
        }
        .confirmationDialog(
            "Merge Branches?",
            isPresented: $isConfirmingMerge,
            titleVisibility: .visible
        ) {
            Button("Merge \(sourceBranch.name) into \(model.destinationName)") {
                Task {
                    if await model.merge(repository: repository, client: client) {
                        onMerged()
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\(sourceBranch.name) → \(model.destinationName). " +
                "This updates \(model.destinationName)."
            )
        }
        .alert(
            "Merge Failed",
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
            "Merge Complete",
            isPresented: Binding(
                get: { model.successMessage != nil },
                set: { if !$0 { model.successMessage = nil } }
            )
        ) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text(model.successMessage ?? "")
        }
    }
}
