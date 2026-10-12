import AppFoundation
import SwiftUI

struct TagsView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme

    let repository: GitHubRepository
    let tags: [GitHubTag]
    let isLoadingTags: Bool
    let branches: [GitHubBranch]
    let selectedBranchName: String
    let client: GitHubAPIClient?
    let onCreated: () -> Void
    let onRefresh: () async -> Void

    private var sortedTags: [GitHubTag] {
        tags.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame
                ? lhs.commit.sha < rhs.commit.sha
                : order == .orderedAscending
        }
    }

    private var selectedBranch: GitHubBranch? {
        branches.first { $0.name == selectedBranchName } ??
        branches.first { $0.name == repository.defaultBranch }
    }

    var body: some View {
        List {
            Group {
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
                    if isLoadingTags && tags.isEmpty {
                        ProgressView("Loading tags…")
                    } else if tags.isEmpty {
                        Text("No tags")
                            .foregroundStyle(foundationTheme.secondaryForegroundColor)
                    } else {
                        ForEach(sortedTags) { tag in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(tag.name)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                                Text(String(tag.commit.sha.prefix(12)))
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundStyle(foundationTheme.secondaryForegroundColor)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .listRowBackground(MyAppsGlassSurface())
            .listRowSeparatorTint(foundationTheme.borderColor)
        }
        .scrollContentBackground(.hidden)
        .myAppsPage()
        .listStyle(.insetGrouped)
        .refreshable {
            await onRefresh()
        }
    }
}
