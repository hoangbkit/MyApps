import Combine
import Foundation

@MainActor
final class GitLogViewModel: ObservableObject {
    static let allBranches = "All Branches"

    @Published private(set) var branches: [GitHubBranch] = []
    @Published private(set) var tags: [GitHubTag] = []
    @Published private(set) var commits: [GitHubCommit] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreCommits = true
    @Published var selectedBranch: String
    @Published var errorMessage: String?

    private let singleBranchPageSize = 40
    private let allBranchesPageSize = 20

    private var nextPage = 1
    private var loadedBranch: String?
    private var loadGeneration = 0

    // The next page to request for every branch that has more history.
    // All Branches does not use a single pagination cursor.
    private var pendingBranchPages: [String: Int] = [:]

    var isSwitchingBranch: Bool {
        isLoading && loadedBranch != nil && loadedBranch != selectedBranch
    }

    init(defaultBranch: String) {
        // The selected branch is still available in the menu, but a log graph
        // is most useful when it includes unmerged feature branch heads.
        selectedBranch = Self.allBranches
    }

    func loadInitial(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        guard let client else {
            errorMessage = "GitHub is not connected."
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            async let branchesRequest = client.branches(repository: repository)
            async let tagsRequest = client.tags(repository: repository)
            let freshBranches = try await branchesRequest
            let freshTags = try await tagsRequest
            guard generation == loadGeneration, !Task.isCancelled else { return }

            let scope = selectedBranch == Self.allBranches ||
                freshBranches.contains(where: { $0.name == selectedBranch })
                ? selectedBranch
                : repository.defaultBranch

            let firstPage = try await fetchFirstPage(
                scope: scope,
                branches: freshBranches,
                repository: repository,
                client: client
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }

            branches = freshBranches
            tags = freshTags
            applyFirstPage(firstPage, scope: scope)
        } catch {
            guard generation == loadGeneration,
                  !Task.isCancelled,
                  !GitHubAPIClient.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func selectBranch(
        _ branch: String,
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        if branch == loadedBranch && !commits.isEmpty {
            // A selection can supersede a pending request for another branch.
            loadGeneration += 1
            selectedBranch = branch
            isLoading = false
            isLoadingMore = false
            errorMessage = nil
            return
        }

        guard let client else {
            errorMessage = "GitHub is not connected."
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        selectedBranch = branch
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            let firstPage = try await fetchFirstPage(
                scope: branch,
                branches: branches,
                repository: repository,
                client: client
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }
            applyFirstPage(firstPage, scope: branch)
        } catch {
            guard generation == loadGeneration else { return }
            selectedBranch = loadedBranch ?? Self.allBranches
            guard !Task.isCancelled,
                  !GitHubAPIClient.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadMore(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        guard hasMoreCommits, !isLoading, !isLoadingMore,
              let client, let scope = loadedBranch else { return }

        let generation = loadGeneration
        let pageNumber = nextPage
        let cursors = pendingBranchPages
            .map { GitHubBranchHistoryCursor(branch: $0.key, page: $0.value) }
            .sorted { $0.branch < $1.branch }

        isLoadingMore = true
        defer {
            if generation == loadGeneration { isLoadingMore = false }
        }

        do {
            if scope == Self.allBranches {
                let pages = try await client.commitPages(
                    repository: repository,
                    cursors: cursors,
                    perPage: allBranchesPageSize
                )
                guard generation == loadGeneration,
                      loadedBranch == scope, !Task.isCancelled else { return }

                // Combine all fetched pages before touching visible state.
                // A duplicate shared ancestor must appear only once.
                commits = Self.uniqueRecentCommits(
                    commits + pages.flatMap(\.commits)
                )
                pendingBranchPages = nextBranchPages(
                    from: pages,
                    pageSize: allBranchesPageSize
                )
                hasMoreCommits = !pendingBranchPages.isEmpty
            } else {
                let page = try await client.commits(
                    repository: repository,
                    branch: scope,
                    page: pageNumber,
                    perPage: singleBranchPageSize
                )
                guard generation == loadGeneration,
                      loadedBranch == scope,
                      nextPage == pageNumber,
                      !Task.isCancelled else { return }
                appendUnique(page)
                hasMoreCommits = page.count == singleBranchPageSize
                nextPage += 1
            }
            errorMessage = nil
        } catch {
            guard generation == loadGeneration,
                  !Task.isCancelled,
                  !GitHubAPIClient.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func references(for commit: GitHubCommit) -> GitHubCommitReferences {
        GitHubCommitReferences(
            branches: branches
                .filter { $0.commit.sha == commit.sha }
                .map(\.name)
                .sorted(),
            tags: tags
                .filter { $0.commit.sha == commit.sha }
                .map(\.name)
                .sorted()
        )
    }

    private struct FirstPage {
        let commits: [GitHubCommit]
        let nextBranchPages: [String: Int]
        let hasMore: Bool
    }

    private func fetchFirstPage(
        scope: String,
        branches availableBranches: [GitHubBranch],
        repository: GitHubRepository,
        client: GitHubAPIClient
    ) async throws -> FirstPage {
        if scope == Self.allBranches {
            let cursors = availableBranches.map {
                GitHubBranchHistoryCursor(branch: $0.name, page: 1)
            }
            let pages = try await client.commitPages(
                repository: repository,
                cursors: cursors,
                perPage: allBranchesPageSize
            )
            let pending = nextBranchPages(from: pages, pageSize: allBranchesPageSize)
            return FirstPage(
                commits: Self.uniqueRecentCommits(pages.flatMap(\.commits)),
                nextBranchPages: pending,
                hasMore: !pending.isEmpty
            )
        }

        let page = try await client.commits(
            repository: repository,
            branch: scope,
            page: 1,
            perPage: singleBranchPageSize
        )
        return FirstPage(
            commits: page,
            nextBranchPages: [:],
            hasMore: page.count == singleBranchPageSize
        )
    }

    private func nextBranchPages(
        from pages: [GitHubBranchHistoryPage],
        pageSize: Int
    ) -> [String: Int] {
        var next: [String: Int] = [:]
        for page in pages where page.commits.count == pageSize {
            next[page.branch] = page.page + 1
        }
        return next
    }

    private func applyFirstPage(_ page: FirstPage, scope: String) {
        selectedBranch = scope
        loadedBranch = scope
        commits = page.commits
        pendingBranchPages = page.nextBranchPages
        hasMoreCommits = page.hasMore
        nextPage = 2
        errorMessage = nil
    }

    private func appendUnique(_ page: [GitHubCommit]) {
        let existing = Set(commits.map(\.sha))
        commits.append(contentsOf: page.filter { !existing.contains($0.sha) })
    }

    private static func uniqueRecentCommits(_ items: [GitHubCommit]) -> [GitHubCommit] {
        var visited = Set<String>()
        return items
            .filter { visited.insert($0.sha).inserted }
            .sorted {
                let firstDate = $0.commit.committer?.date ?? $0.authoredAt ?? .distantPast
                let secondDate = $1.commit.committer?.date ?? $1.authoredAt ?? .distantPast
                if firstDate != secondDate { return firstDate > secondDate }
                return $0.sha < $1.sha
            }
    }
}
