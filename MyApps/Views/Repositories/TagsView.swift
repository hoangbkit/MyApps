import SwiftUI

struct TagsView: View {
    let repository: GitHubRepository
    let tags: [GitHubTag]
    let branches: [GitHubBranch]
    let selectedBranchName: String
    let client: GitHubAPIClient?
    let onCreated: () -> Void
    let onRefresh: () async -> Void

    private var selectedBranch: GitHubBranch? {
        branches.first { $0.name == selectedBranchName } ??
        branches.first { $0.name == repository.defaultBranch }
    }

    var body: some View {
        List {
            if let selectedBranch {
                Section {
                    NavigationLink {
                        CreateTagView(
                            repository: repository,
                            targetSHA: selectedBranch.commit.sha,
                            targetDescription: "HEAD of \(selectedBranch.name)",
                            existingTags: tags,
                            client: client,
                            onCreated: onCreated
                        )
                    } label: {
                        Label(
                            "Create Tag at \(selectedBranch.name) HEAD",
                            systemImage: "plus.circle"
                        )
                    }
                    .disabled(!repository.canAttemptWrite)
                }
            }

            Section("Tags") {
                if tags.isEmpty {
                    Text("No tags")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags) { tag in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tag.name)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))

                            Text(String(tag.commit.sha.prefix(12)))
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await onRefresh()
        }
        .task {
            // Entering Tags must not wait for the entire All Branches log.
            await onRefresh()
        }
    }
}
