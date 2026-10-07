import SwiftUI

struct BranchesView: View {
    let repository: GitHubRepository
    let branches: [GitHubBranch]
    let tags: [GitHubTag]
    let client: GitHubAPIClient?
    let isLoading: Bool
    let onRepositoryChanged: () -> Void

    private var sortedBranches: [GitHubBranch] {
        branches.sorted { lhs, rhs in
            if lhs.name == repository.defaultBranch { return true }
            if rhs.name == repository.defaultBranch { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        if isLoading && branches.isEmpty {
            ProgressView("Loading branches…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if branches.isEmpty {
            ContentUnavailableView(
                "No Branches",
                systemImage: "arrow.triangle.branch",
                description: Text("GitHub returned no branches for this repository.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(sortedBranches) { branch in
                    NavigationLink {
                        BranchDetailView(
                            repository: repository,
                            branch: branch,
                            branches: branches,
                            existingTags: tags,
                            client: client,
                            onRepositoryChanged: onRepositoryChanged
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Text(branch.name)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                                if branch.name == repository.defaultBranch {
                                    Text("Default")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }

                                if branch.isProtected {
                                    Image(systemName: "lock.shield")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text(String(branch.commit.sha.prefix(12)))
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
