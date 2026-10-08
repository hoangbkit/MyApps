import SwiftUI

struct RepositoryWorkspaceView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case log = "Log"
        case branches = "Branches"
        case tags = "Tags"
        case releases = "Releases"

        var id: String { rawValue }
    }

    let repository: GitHubRepository
    let client: GitHubAPIClient?

    @StateObject private var logModel: GitLogViewModel
    @State private var selectedSection: Section = .log

    init(repository: GitHubRepository, client: GitHubAPIClient?) {
        self.repository = repository
        self.client = client
        _logModel = StateObject(
            wrappedValue: GitLogViewModel(defaultBranch: repository.defaultBranch)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Repository Section", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 10)

            switch selectedSection {
            case .log:
                logView
            case .branches:
                BranchesView(
                    repository: repository,
                    branches: logModel.branches,
                    tags: logModel.tags,
                    client: client,
                    isLoading: logModel.isLoading,
                    onTagCreated: {
                        Task {
                            await logModel.refreshTags(repository: repository, client: client)
                        }
                    }
                ) {
                    Task {
                        await logModel.loadInitial(repository: repository, client: client)
                    }
                }
            case .tags:
                TagsView(
                    repository: repository,
                    tags: logModel.tags,
                    branches: logModel.branches,
                    selectedBranchName: logModel.selectedBranch,
                    client: client,
                    onCreated: {
                        Task {
                            await logModel.refreshTags(repository: repository, client: client)
                        }
                    },
                    onRefresh: {
                        await logModel.refreshTags(repository: repository, client: client)
                    }
                )
            case .releases:
                ReleasesView(
                    repository: repository,
                    tags: logModel.tags,
                    client: client
                )
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedSection == .log {
                branchToolbar
            }
        }
        .task {
            if logModel.commits.isEmpty {
                await logModel.loadInitial(repository: repository, client: client)
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
        } else {
            let graph = logModel.graph
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(graph.commits.enumerated()), id: \.element.sha) { index, commit in
                        NavigationLink {
                            GitCommitDetailView(
                                repository: repository,
                                commit: commit,
                                references: logModel.references(for: commit),
                                existingTags: logModel.tags,
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
            .refreshable {
                await logModel.loadInitial(repository: repository, client: client)
            }
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
