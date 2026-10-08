import SwiftUI

struct BranchDetailView: View {
    let repository: GitHubRepository
    let initialBranch: GitHubBranch
    @ObservedObject var model: GitLogViewModel
    let client: GitHubAPIClient?
    let onTagCreated: () -> Void
    let onRepositoryChanged: () -> Void

    @State private var comparison: GitHubComparison?
    @State private var isLoadingComparison = false
    @State private var comparisonError: String?
    @State private var comparisonGeneration = 0

    private var branches: [GitHubBranch] { model.branches }
    private var existingTags: [GitHubTag] { model.tags }
    private var branch: GitHubBranch {
        branches.first { $0.name == initialBranch.name } ?? initialBranch
    }
    private var branchExists: Bool {
        branches.contains { $0.name == initialBranch.name }
    }
    private var comparisonID: String {
        "\(branchExists)-\(branch.commit.sha)-\(defaultBranch?.commit.sha ?? "")"
    }

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

            if !branchExists {
                Section {
                    Text("This branch no longer exists. Pull to refresh or return to Branches.")
                        .foregroundStyle(.secondary)
                }
            }

            if branchExists && branch.name != repository.defaultBranch {
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
                        onCreated: onTagCreated
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
                            onMerged: onRepositoryChanged
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
                                onRebased: onRepositoryChanged
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
            .disabled(!branchExists)
        }
        .navigationTitle(branch.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.refreshReferences(repository: repository, client: client)
            await loadDefaultComparison()
        }
        .task(id: comparisonID) {
            await loadDefaultComparison()
        }
    }

    private func loadDefaultComparison() async {
        comparisonGeneration += 1
        let generation = comparisonGeneration
        comparison = nil
        comparisonError = nil
        isLoadingComparison = false
        guard
            branchExists,
            branch.name != repository.defaultBranch,
            let defaultBranch,
            let client
        else {
            return
        }

        isLoadingComparison = true
        defer {
            if generation == comparisonGeneration { isLoadingComparison = false }
        }

        do {
            let fetched = try await client.compare(
                repository: repository,
                baseSHA: defaultBranch.commit.sha,
                headSHA: branch.commit.sha
            )
            guard generation == comparisonGeneration, !Task.isCancelled else { return }
            comparison = fetched
            comparisonError = nil
        } catch {
            guard generation == comparisonGeneration,
                  !Task.isCancelled, !GitHubAPIClient.isCancellation(error) else { return }
            comparisonError = error.localizedDescription
        }
    }
}
