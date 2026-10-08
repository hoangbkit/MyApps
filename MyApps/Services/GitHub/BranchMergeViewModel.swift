import Combine
import Foundation

@MainActor
final class BranchMergeViewModel: ObservableObject {
    @Published var destinationName: String
    @Published private(set) var comparison: GitHubComparison?
    @Published private(set) var sourceHeadSHA: String
    @Published private(set) var destinationHeadSHA: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isMerging = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let sourceBranch: GitHubBranch

    init(sourceBranch: GitHubBranch, defaultDestination: String) {
        self.sourceBranch = sourceBranch
        destinationName = defaultDestination
        sourceHeadSHA = sourceBranch.commit.sha
    }

    func prepare(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        guard sourceBranch.name != destinationName else {
            comparison = nil
            destinationHeadSHA = nil
            errorMessage = "Choose a destination branch different from the source branch."
            return
        }

        guard let client else {
            errorMessage = "GitHub is not connected."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let branches = try await client.branches(repository: repository)
            guard
                let source = branches.first(where: { $0.name == sourceBranch.name }),
                let destination = branches.first(where: { $0.name == destinationName })
            else {
                throw BranchOperationError.branchMovedOrMissing
            }

            sourceHeadSHA = source.commit.sha
            destinationHeadSHA = destination.commit.sha
            comparison = try await client.compare(
                repository: repository,
                baseSHA: destination.commit.sha,
                headSHA: source.commit.sha
            )
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, !GitHubAPIClient.isCancellation(error) else { return }
            comparison = nil
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func merge(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async -> Bool {
        guard let client else {
            errorMessage = "GitHub is not connected."
            return false
        }

        isMerging = true
        defer { isMerging = false }

        do {
            let branches = try await client.branches(repository: repository)
            guard
                let latestSource = branches.first(where: { $0.name == sourceBranch.name }),
                let latestDestination = branches.first(where: { $0.name == destinationName })
            else {
                throw BranchOperationError.branchMovedOrMissing
            }

            let latestComparison = try await client.compare(
                repository: repository,
                baseSHA: latestDestination.commit.sha,
                headSHA: latestSource.commit.sha
            )

            sourceHeadSHA = latestSource.commit.sha
            destinationHeadSHA = latestDestination.commit.sha
            comparison = latestComparison

            guard latestComparison.aheadBy > 0 else {
                successMessage = "\(destinationName) already contains \(sourceBranch.name)."
                errorMessage = nil
                return true
            }

            let result = try await client.merge(
                repository: repository,
                sourceBranch: sourceBranch.name,
                destinationBranch: destinationName
            )

            switch result {
            case let .merged(commit):
                successMessage = "Merged \(sourceBranch.name) into \(destinationName) at \(commit.shortSHA)."
            case .alreadyUpToDate:
                successMessage = "\(destinationName) is already up to date with \(sourceBranch.name)."
            }

            errorMessage = nil
            return true
        } catch {
            guard !Task.isCancelled, !GitHubAPIClient.isCancellation(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }
}

enum BranchOperationError: LocalizedError {
    case branchMovedOrMissing

    var errorDescription: String? {
        switch self {
        case .branchMovedOrMissing:
            return "One of the selected branches no longer exists. Refresh the repository and try again."
        }
    }
}
