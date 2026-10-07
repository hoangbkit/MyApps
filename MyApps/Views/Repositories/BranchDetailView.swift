import SwiftUI

struct BranchDetailView: View {
    let repository: GitHubRepository
    let branch: GitHubBranch
    let branches: [GitHubBranch]
    let existingTags: [GitHubTag]
    let client: GitHubAPIClient?
    let onMerged: () -> Void

    @State private var comparison: GitHubComparison?
    @State private var isLoadingComparison = false
    @State private var comparisonError: String?

    private var defaultBranch: GitHubBranch? {
        branches.first { $0.name == repository.defaultBranch }
    }

    private var suggestedDestination: String? {
        if branch.name != repository.defaultBranch {
            return repository.defaultBranch
        }

        return branches.first(where: { $0.name != branch.name })?.name
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Branch", value: branch.name)
                LabeledContent("Head", value: String(branch.commit.sha.prefix(12)))

                if branch.name == repository.defaultBranch {
                    Label("Default branch", systemImage: "checkmark.circle")
                }

                if branch.isProtected {
                    Label("Protected", systemImage: "lock.shield")
                }
            }

            if branch.name != repository.defaultBranch {
                Section("Relative to \(repository.defaultBranch)") {
                    if isLoadingComparison {
                        ProgressView()
                    } else if let comparison {
                        LabeledContent("Ahead", value: comparison.aheadBy.formatted())
                        LabeledContent("Behind", value: comparison.behindBy.formatted())
                        LabeledContent("Status", value: comparison.status.capitalized)
                    } else if let comparisonError {
                        Text(comparisonError)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Actions") {
                NavigationLink {
                    CreateTagView(
                        repository: repository,
                        targetSHA: branch.commit.sha,
                        targetDescription: "HEAD of \(branch.name)",
                        existingTags: existingTags,
                        client: client,
                        onCreated: onMerged
                    )
                } label: {
                    Label("Create Tag at HEAD", systemImage: "tag")
                }
                .disabled(!repository.canAttemptWrite)

                if let suggestedDestination {
                    NavigationLink {
                        BranchMergeView(
                            repository: repository,
                            sourceBranch: branch,
                            branches: branches,
                            defaultDestination: suggestedDestination,
                            client: client,
                            onMerged: onMerged
                        )
                    } label: {
                        Label("Merge into…", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(!repository.canAttemptWrite)

                    if branch.name != repository.defaultBranch {
                        NavigationLink {
                            BranchRebaseView(
                                repository: repository,
                                sourceBranch: branch,
                                branches: branches,
                                defaultDestination: repository.defaultBranch,
                                client: client,
                                onRebased: onMerged
                            )
                        } label: {
                            Label("Rebase onto…", systemImage: "arrow.triangle.branch")
                        }
                        .disabled(
                            !repository.canAttemptWrite ||
                            branch.isProtected
                        )
                    }
                }

                if !repository.canAttemptWrite {
                    Text(repository.isArchived ? "Archived repositories are read-only." : "This GitHub connection has read-only access to the repository.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(branch.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDefaultComparison()
        }
    }

    private func loadDefaultComparison() async {
        guard
            branch.name != repository.defaultBranch,
            let defaultBranch,
            let client
        else {
            return
        }

        isLoadingComparison = true
        defer { isLoadingComparison = false }

        do {
            comparison = try await client.compare(
                repository: repository,
                baseSHA: defaultBranch.commit.sha,
                headSHA: branch.commit.sha
            )
            comparisonError = nil
        } catch {
            comparisonError = error.localizedDescription
        }
    }
}
