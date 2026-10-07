import Combine
import Foundation

@MainActor
final class BranchRebaseViewModel: ObservableObject {
    struct Plan: Sendable {
        let sourceHeadSHA: String
        let destinationHeadSHA: String
        let mergeBaseSHA: String
        let replayCommits: [GitHubCommit]
        let destinationUniqueCount: Int
        let conflictingPaths: [String]
        let isFastForward: Bool
        let isNoOp: Bool
    }

    @Published var destinationName: String
    @Published private(set) var plan: Plan?
    @Published private(set) var proposedHeadSHA: String?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isApplying = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let sourceBranch: GitHubBranch

    private let maxReplayCommits = 100
    private var preparedSourceSHA: String?
    private var preparedDestinationSHA: String?

    init(sourceBranch: GitHubBranch, defaultDestination: String) {
        self.sourceBranch = sourceBranch
        destinationName = defaultDestination
    }

    func analyze(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        proposedHeadSHA = nil
        preparedSourceSHA = nil
        preparedDestinationSHA = nil

        guard sourceBranch.name != repository.defaultBranch else {
            plan = nil
            errorMessage = GitHubRebaseError.defaultBranch.localizedDescription
            return
        }

        guard !sourceBranch.isProtected else {
            plan = nil
            errorMessage = GitHubRebaseError.protectedBranch.localizedDescription
            return
        }

        guard sourceBranch.name != destinationName else {
            plan = nil
            errorMessage = GitHubRebaseError.sameBranch.localizedDescription
            return
        }

        guard let client else {
            plan = nil
            errorMessage = "GitHub is not connected."
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let branches = try await client.branches(repository: repository)
            guard
                let source = branches.first(where: { $0.name == sourceBranch.name }),
                let destination = branches.first(where: { $0.name == destinationName })
            else {
                throw GitHubRebaseError.branchMoved
            }

            let sourceComparison = try await client.compare(
                repository: repository,
                baseSHA: destination.commit.sha,
                headSHA: source.commit.sha
            )

            guard
                sourceComparison.aheadBy <= maxReplayCommits,
                sourceComparison.behindBy <= maxReplayCommits
            else {
                throw GitHubRebaseError.tooManyCommits
            }

            guard sourceComparison.commits.count == sourceComparison.aheadBy else {
                throw GitHubRebaseError.incompleteComparison
            }

            guard let mergeBaseSHA = sourceComparison.mergeBaseCommit?.sha else {
                throw GitHubRebaseError.incompleteComparison
            }

            if sourceComparison.behindBy == 0 {
                plan = Plan(
                    sourceHeadSHA: source.commit.sha,
                    destinationHeadSHA: destination.commit.sha,
                    mergeBaseSHA: mergeBaseSHA,
                    replayCommits: sourceComparison.commits,
                    destinationUniqueCount: 0,
                    conflictingPaths: [],
                    isFastForward: false,
                    isNoOp: true
                )
                errorMessage = nil
                return
            }

            if sourceComparison.aheadBy == 0 {
                plan = Plan(
                    sourceHeadSHA: source.commit.sha,
                    destinationHeadSHA: destination.commit.sha,
                    mergeBaseSHA: mergeBaseSHA,
                    replayCommits: [],
                    destinationUniqueCount: sourceComparison.behindBy,
                    conflictingPaths: [],
                    isFastForward: true,
                    isNoOp: false
                )
                errorMessage = nil
                return
            }

            for commit in sourceComparison.commits {
                guard commit.parents.count == 1 else {
                    throw GitHubRebaseError.mergeCommit(commit.sha)
                }
            }

            let destinationComparison = try await client.compare(
                repository: repository,
                baseSHA: source.commit.sha,
                headSHA: destination.commit.sha
            )

            guard
                destinationComparison.aheadBy == sourceComparison.behindBy,
                destinationComparison.commits.count == destinationComparison.aheadBy
            else {
                throw GitHubRebaseError.incompleteComparison
            }

            var destinationTouched: Set<String> = []
            for commit in destinationComparison.commits {
                let files = try await client.commitFiles(repository: repository, sha: commit.sha)
                for file in files {
                    destinationTouched.formUnion(file.touchedPaths)
                }
            }

            var sourceTouched: Set<String> = []
            for commit in sourceComparison.commits {
                let files = try await client.commitFiles(repository: repository, sha: commit.sha)
                for file in files {
                    sourceTouched.formUnion(file.touchedPaths)
                }
            }

            let conflicts = sourceTouched
                .intersection(destinationTouched)
                .sorted()

            plan = Plan(
                sourceHeadSHA: source.commit.sha,
                destinationHeadSHA: destination.commit.sha,
                mergeBaseSHA: mergeBaseSHA,
                replayCommits: sourceComparison.commits,
                destinationUniqueCount: destinationComparison.commits.count,
                conflictingPaths: conflicts,
                isFastForward: false,
                isNoOp: false
            )

            if !conflicts.isEmpty {
                errorMessage = GitHubRebaseError.conflictingPaths(conflicts).localizedDescription
            } else {
                errorMessage = nil
            }
        } catch is CancellationError {
            return
        } catch {
            plan = nil
            errorMessage = error.localizedDescription
        }
    }

    func prepare(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async {
        guard
            let plan,
            plan.conflictingPaths.isEmpty,
            !plan.isNoOp,
            let client
        else {
            return
        }

        isPreparing = true
        defer { isPreparing = false }

        do {
            let branches = try await client.branches(repository: repository)
            guard
                let source = branches.first(where: { $0.name == sourceBranch.name }),
                let destination = branches.first(where: { $0.name == destinationName }),
                source.commit.sha == plan.sourceHeadSHA,
                destination.commit.sha == plan.destinationHeadSHA
            else {
                throw GitHubRebaseError.branchMoved
            }

            if plan.isFastForward {
                proposedHeadSHA = plan.destinationHeadSHA
                preparedSourceSHA = plan.sourceHeadSHA
                preparedDestinationSHA = plan.destinationHeadSHA
                errorMessage = nil
                return
            }

            let destinationCommit = try await client.gitCommit(
                repository: repository,
                sha: plan.destinationHeadSHA
            )

            var currentParentSHA = plan.destinationHeadSHA
            var currentTreeSHA = destinationCommit.tree.sha

            for commit in plan.replayCommits {
                guard let originalParentSHA = commit.parents.first?.sha else {
                    throw GitHubRebaseError.incompleteComparison
                }

                let originalCommit = try await client.gitCommit(
                    repository: repository,
                    sha: commit.sha
                )
                let originalParent = try await client.gitCommit(
                    repository: repository,
                    sha: originalParentSHA
                )

                let originalTree = try await client.gitTree(
                    repository: repository,
                    sha: originalCommit.tree.sha
                )
                let parentTree = try await client.gitTree(
                    repository: repository,
                    sha: originalParent.tree.sha
                )

                guard originalTree.truncated != true, parentTree.truncated != true else {
                    throw GitHubRebaseError.truncatedTree
                }

                let files = try await client.commitFiles(
                    repository: repository,
                    sha: commit.sha
                )
                let entries = try treeMutations(
                    files: files,
                    originalTree: originalTree,
                    parentTree: parentTree
                )

                let newTree = try await client.createTree(
                    repository: repository,
                    baseTreeSHA: currentTreeSHA,
                    entries: entries
                )

                let author: GitHubCommitAuthorPayload?
                if let identity = commit.commit.author, let email = identity.email {
                    author = GitHubCommitAuthorPayload(
                        name: identity.name,
                        email: email,
                        date: identity.date
                    )
                } else {
                    author = nil
                }

                let newCommit = try await client.createCommit(
                    repository: repository,
                    message: commit.commit.message,
                    treeSHA: newTree.sha,
                    parentSHA: currentParentSHA,
                    author: author
                )

                currentParentSHA = newCommit.sha
                currentTreeSHA = newCommit.tree.sha
            }

            proposedHeadSHA = currentParentSHA
            preparedSourceSHA = plan.sourceHeadSHA
            preparedDestinationSHA = plan.destinationHeadSHA
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            proposedHeadSHA = nil
            preparedSourceSHA = nil
            preparedDestinationSHA = nil
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func apply(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async -> Bool {
        guard
            let client,
            let proposedHeadSHA,
            let preparedSourceSHA,
            let preparedDestinationSHA
        else {
            errorMessage = "Prepare the rebase before applying it."
            return false
        }

        isApplying = true
        defer { isApplying = false }

        do {
            try await client.updateRebasedBranchWithLease(
                repository: repository,
                sourceBranch: sourceBranch.name,
                expectedSourceSHA: preparedSourceSHA,
                newSourceSHA: proposedHeadSHA,
                destinationBranch: destinationName,
                expectedDestinationSHA: preparedDestinationSHA
            )

            successMessage = "Rebased \(sourceBranch.name) onto \(destinationName)."
            errorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func treeMutations(
        files: [GitHubComparisonFile],
        originalTree: GitHubGitTree,
        parentTree: GitHubGitTree
    ) throws -> [GitHubTreeMutationEntry] {
        var entries: [GitHubTreeMutationEntry] = []

        for file in files {
            switch file.status {
            case "removed":
                guard let old = parentTree.entry(at: file.filename) else {
                    throw GitHubRebaseError.missingTreeEntry(file.filename)
                }
                entries.append(
                    GitHubTreeMutationEntry(
                        path: file.filename,
                        mode: old.mode,
                        type: old.type,
                        sha: nil
                    )
                )

            case "renamed":
                guard
                    let previousFilename = file.previousFilename,
                    let old = parentTree.entry(at: previousFilename),
                    let new = originalTree.entry(at: file.filename)
                else {
                    throw GitHubRebaseError.missingTreeEntry(
                        file.previousFilename ?? file.filename
                    )
                }

                entries.append(
                    GitHubTreeMutationEntry(
                        path: previousFilename,
                        mode: old.mode,
                        type: old.type,
                        sha: nil
                    )
                )
                entries.append(
                    GitHubTreeMutationEntry(
                        path: file.filename,
                        mode: new.mode,
                        type: new.type,
                        sha: new.sha
                    )
                )

            case "added", "modified", "changed", "copied":
                guard let new = originalTree.entry(at: file.filename) else {
                    throw GitHubRebaseError.missingTreeEntry(file.filename)
                }

                entries.append(
                    GitHubTreeMutationEntry(
                        path: file.filename,
                        mode: new.mode,
                        type: new.type,
                        sha: new.sha
                    )
                )

            default:
                throw GitHubRebaseError.unsupportedFileStatus(file.status)
            }
        }

        return entries
    }
}
