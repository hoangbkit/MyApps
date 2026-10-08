import SwiftUI

struct RepositoryWorkspaceView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case log = "Log"
        case branches = "Branches"
        case tags = "Tags"
        case releases = "Releases"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .log: "point.3.connected.trianglepath.dotted"
            case .branches: "arrow.triangle.branch"
            case .tags: "tag"
            case .releases: "shippingbox"
            }
        }
    }

    let repository: GitHubRepository
    let client: GitHubAPIClient?

    @StateObject private var logModel: GitLogViewModel
    @State private var selectedSection: Section = .log
    @State private var lastLoadedSection: Section?

    init(repository: GitHubRepository, client: GitHubAPIClient?) {
        self.repository = repository
        self.client = client
        _logModel = StateObject(
            wrappedValue: GitLogViewModel(defaultBranch: repository.defaultBranch)
        )
    }

    var body: some View {
        Group {
            switch selectedSection {
            case .log:
                logView
            case .branches:
                BranchesView(
                    repository: repository,
                    model: logModel,
                    client: client,
                    onTagCreated: {
                        Task {
                            await logModel.refreshTags(repository: repository, client: client)
                        }
                    },
                    onRepositoryChanged: {
                        Task {
                            await logModel.loadInitial(repository: repository, client: client)
                        }
                    },
                    onRefresh: {
                        await logModel.refreshReferences(repository: repository, client: client)
                    }
                )
            case .tags:
                TagsView(
                    repository: repository,
                    tags: logModel.tags,
                    isLoadingTags: logModel.isLoadingTags,
                    branches: logModel.branches,
                    selectedBranchName: logModel.selectedBranch,
                    client: client,
                    onCreated: {
                        Task {
                            await logModel.refreshTags(repository: repository, client: client)
                        }
                    },
                    onRefresh: {
                        await logModel.refreshReferences(repository: repository, client: client)
                    }
                )
            case .releases:
                ReleasesView(
                    repository: repository,
                    client: client
                )
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            sectionToolbar
            if selectedSection == .log {
                branchToolbar
            }
        }
        .task(id: selectedSection) {
            let changedSection = lastLoadedSection != selectedSection
            lastLoadedSection = selectedSection
            switch selectedSection {
            case .log:
                // Returning from commit details preserves loaded pagination.
                // Switching back from another section refreshes branch heads.
                if changedSection || logModel.commits.isEmpty {
                    await logModel.loadInitial(repository: repository, client: client)
                }
            case .branches, .tags:
                await logModel.refreshReferences(repository: repository, client: client)
            case .releases:
                break // Releases owns its stable list-and-tags refresh task.
            }
        }
        .alert(
            "GitHub",
            isPresented: Binding(
                get: { logModel.errorMessage != nil },
                set: { if !$0 { logModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(logModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var logView: some View {
        if (logModel.isLoading && logModel.commits.isEmpty) || logModel.isSwitchingBranch {
            ProgressView("Loading \(logModel.selectedBranch)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if logModel.commits.isEmpty {
            ScrollView {
                ContentUnavailableView {
                    Label("No Commits", systemImage: "point.3.filled.connected.trianglepath.dotted")
                } description: {
                    Text("No commit history was returned for \(logModel.selectedBranch).")
                } actions: {
                    Button("Try Again") {
                        Task {
                            await logModel.loadInitial(repository: repository, client: client)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.always)
            .refreshable {
                await logModel.loadInitial(repository: repository, client: client)
            }
        } else {
            let graph = logModel.graph
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(graph.commits.enumerated()), id: \.element.sha) { index, commit in
                        NavigationLink {
                            GitCommitDetailView(
                                repository: repository,
                                commit: commit,
                                model: logModel,
                                client: client
                            ) {
                                Task {
                                    await logModel.refreshTags(repository: repository, client: client)
                                }
                            }
                        } label: {
                            GitCommitRowView(
                                commit: commit,
                                references: logModel.references(for: commit),
                                graph: graph.rows[index],
                                graphWidth: graph.width,
                                laneSpacing: graph.laneSpacing
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppTheme.pagePadding)
                    }

                    if logModel.hasMoreCommits {
                        HStack {
                            Spacer()

                            if logModel.isLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 18)
                            } else {
                                Button("Load More") {
                                    Task {
                                        await logModel.loadMore(
                                            repository: repository,
                                            client: client
                                        )
                                    }
                                }
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .padding(.vertical, 18)
                            }

                            Spacer()
                        }
                    }
                }
            }
            .scrollBounceBehavior(.always)
            .refreshable {
                await logModel.loadInitial(repository: repository, client: client)
            }
        }
    }

    // A title menu scales to more repository screens without consuming
    // vertical space or requiring an increasingly cramped segmented control.
    @ToolbarContentBuilder
    private var sectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                ForEach(Section.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        if selectedSection == section {
                            Label(section.rawValue, systemImage: "checkmark")
                        } else {
                            Label(section.rawValue, systemImage: section.symbolName)
                        }
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    Text(repository.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(selectedSection.rawValue)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 190)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Repository sections, currently \(selectedSection.rawValue)")
            .accessibilityHint("Choose Log, Branches, Tags, or Releases")
        }
    }

    @ToolbarContentBuilder
    private var branchToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Task {
                        await logModel.selectBranch(
                            GitLogViewModel.allBranches,
                            repository: repository,
                            client: client
                        )
                    }
                } label: {
                    if logModel.selectedBranch == GitLogViewModel.allBranches {
                        Label("All Branches", systemImage: "checkmark")
                    } else {
                        Label("All Branches", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }

                Divider()

                ForEach(logModel.branches) { branch in
                    Button {
                        Task {
                            await logModel.selectBranch(
                                branch.name,
                                repository: repository,
                                client: client
                            )
                        }
                    } label: {
                        if branch.name == logModel.selectedBranch {
                            Label(branch.name, systemImage: "checkmark")
                        } else {
                            Text(branch.name)
                        }
                    }
                }
            } label: {
                Label(
                    logModel.selectedBranch,
                    systemImage: logModel.selectedBranch == GitLogViewModel.allBranches
                        ? "point.3.connected.trianglepath.dotted"
                        : "arrow.triangle.branch"
                )
            }
            .accessibilityLabel("Branch \(logModel.selectedBranch)")
            .disabled(logModel.isLoading || logModel.isLoadingMore)
        }
    }
}
