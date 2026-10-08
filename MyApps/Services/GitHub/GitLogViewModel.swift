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
    private var loadGeneration = 0

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
            let fetchedBranches = try await branchesRequest
            let fetchedTags = try await tagsRequest
            guard generation == loadGeneration, !Task.isCancelled else { return }

            let branch = fetchedBranches.contains(where: { $0.name == selectedBranch })
                ? selectedBranch
                : repository.defaultBranch
            let page = try await client.commits(
                repository: repository, branch: branch, page: 1, perPage: pageSize
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }
            branches = fetchedBranches
            tags = fetchedTags
            applyFirstPage(page, branch: branch)
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
        // Re-selecting the loaded branch invalidates an older request too.
        if branch == loadedBranch && !commits.isEmpty {
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
            let page = try await client.commits(
                repository: repository, branch: branch, page: 1, perPage: pageSize
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }
            applyFirstPage(page, branch: branch)
        } catch {
            guard generation == loadGeneration else { return }
            // Preserve the old commits and their matching branch label.
            selectedBranch = loadedBranch ?? repository.defaultBranch
            guard !Task.isCancelled, !GitHubAPIClient.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadMore(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        guard hasMoreCommits, !isLoading, !isLoadingMore,
              let client, let branch = loadedBranch else { return }

        let generation = loadGeneration
        let pageNumber = nextPage
        isLoadingMore = true
        defer {
            if generation == loadGeneration { isLoadingMore = false }
        }

        do {
            let page = try await client.commits(
                repository: repository, branch: branch, page: pageNumber, perPage: pageSize
            )
            guard generation == loadGeneration, loadedBranch == branch,
                  nextPage == pageNumber, !Task.isCancelled else { return }
            appendUnique(page)
            hasMoreCommits = page.count == pageSize
            nextPage += 1
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

    private func applyFirstPage(_ page: [GitHubCommit], branch: String) {
        selectedBranch = branch
        loadedBranch = branch
        commits = page
        hasMoreCommits = page.count == pageSize
        nextPage = 2
        errorMessage = nil
    }

    private func appendUnique(_ page: [GitHubCommit]) {
        let existing = Set(commits.map(\.sha))
        commits.append(contentsOf: page.filter { !existing.contains($0.sha) })
    }
}
