import Combine
import Foundation

@MainActor
final class GitLogViewModel: ObservableObject {
    @Published private(set) var branches: [GitHubBranch] = []
    @Published private(set) var tags: [GitHubTag] = []
    @Published private(set) var commits: [GitHubCommit] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreCommits = true
    @Published var selectedBranch: String
    @Published var errorMessage: String?

    private let pageSize = 40
    private var nextPage = 1
    private var loadedBranch: String?

    init(defaultBranch: String) {
        selectedBranch = defaultBranch
    }

    func loadInitial(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        guard let client else {
            errorMessage = "GitHub is not connected."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let branchesRequest = client.branches(repository: repository)
            async let tagsRequest = client.tags(repository: repository)

            branches = try await branchesRequest
            tags = try await tagsRequest

            if !branches.contains(where: { $0.name == selectedBranch }) {
                selectedBranch = repository.defaultBranch
            }

            try await loadFirstPage(repository: repository, client: client)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectBranch(
        _ branch: String,
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        guard branch != loadedBranch || commits.isEmpty else {
            selectedBranch = branch
            return
        }

        selectedBranch = branch

        guard let client else {
            errorMessage = "GitHub is not connected."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await loadFirstPage(repository: repository, client: client)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        guard
            hasMoreCommits,
            !isLoading,
            !isLoadingMore,
            let client
        else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.commits(
                repository: repository,
                branch: selectedBranch,
                page: nextPage,
                perPage: pageSize
            )

            appendUnique(page)
            hasMoreCommits = page.count == pageSize
            nextPage += 1
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
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

    private func loadFirstPage(
        repository: GitHubRepository,
        client: GitHubAPIClient
    ) async throws {
        commits = []
        nextPage = 1
        hasMoreCommits = true
        loadedBranch = selectedBranch

        let page = try await client.commits(
            repository: repository,
            branch: selectedBranch,
            page: nextPage,
            perPage: pageSize
        )

        commits = page
        hasMoreCommits = page.count == pageSize
        nextPage = 2
    }

    private func appendUnique(_ page: [GitHubCommit]) {
        let existing = Set(commits.map(\.sha))
        commits.append(contentsOf: page.filter { !existing.contains($0.sha) })
    }
}
