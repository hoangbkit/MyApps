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
                phasePlaceholder(
                    title: "Branches",
                    symbol: "arrow.triangle.branch",
                    message: "Branch operations arrive in Phase 4."
                )
            case .tags:
                phasePlaceholder(
                    title: "Tags",
                    symbol: "tag",
                    message: "Tag management arrives in Phase 6."
                )
            case .releases:
                phasePlaceholder(
                    title: "Releases",
                    symbol: "shippingbox",
                    message: "Release management arrives in Phase 7."
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
        if logModel.isLoading && logModel.commits.isEmpty {
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(logModel.commits.enumerated()), id: \.element.sha) { index, commit in
                        NavigationLink {
                            GitCommitDetailView(
                                commit: commit,
                                references: logModel.references(for: commit)
                            )
                        } label: {
                            GitCommitRowView(
                                commit: commit,
                                references: logModel.references(for: commit),
                                isLast: index == logModel.commits.count - 1 && !logModel.hasMoreCommits
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

    private func phasePlaceholder(
        title: String,
        symbol: String,
        message: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(message)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var branchToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
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
                Label(logModel.selectedBranch, systemImage: "arrow.triangle.branch")
            }
            .accessibilityLabel("Branch \(logModel.selectedBranch)")
            .disabled(logModel.isLoading || logModel.isLoadingMore)
        }
    }
}
