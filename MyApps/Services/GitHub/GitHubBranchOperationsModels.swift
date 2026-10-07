import Foundation

struct GitHubCompareCommitReference: Codable, Hashable, Sendable {
    let sha: String
}

struct GitHubComparisonFile: Codable, Hashable, Sendable {
    let sha: String?
    let filename: String
    let status: String
    let previousFilename: String?

    enum CodingKeys: String, CodingKey {
        case sha
        case filename
        case status
        case previousFilename = "previous_filename"
    }

    var touchedPaths: Set<String> {
        var paths: Set<String> = [filename]
        if let previousFilename {
            paths.insert(previousFilename)
        }
        return paths
    }
}

struct GitHubComparison: Codable, Hashable, Sendable {
    let status: String
    let aheadBy: Int
    let behindBy: Int
    let totalCommits: Int
    let commits: [GitHubCommit]
    let mergeBaseCommit: GitHubCompareCommitReference?
    let files: [GitHubComparisonFile]?

    enum CodingKeys: String, CodingKey {
        case status
        case aheadBy = "ahead_by"
        case behindBy = "behind_by"
        case totalCommits = "total_commits"
        case commits
        case mergeBaseCommit = "merge_base_commit"
        case files
    }
}

enum GitHubMergeResult: Sendable {
    case merged(GitHubCommit)
    case alreadyUpToDate
}

struct GitHubGitCommitObject: Codable, Hashable, Sendable {
    struct ObjectReference: Codable, Hashable, Sendable {
        let sha: String
    }

    let sha: String
    let tree: ObjectReference
}

struct GitHubGitTree: Codable, Hashable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        let path: String
        let mode: String
        let type: String
        let sha: String
    }

    let sha: String
    let truncated: Bool?
    let tree: [Entry]

    func entry(at path: String) -> Entry? {
        tree.first { $0.path == path }
    }
}

struct GitHubTreeMutationEntry: Encodable, Hashable, Sendable {
    let path: String
    let mode: String
    let type: String
    let sha: String?

    enum CodingKeys: String, CodingKey {
        case path
        case mode
        case type
        case sha
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(mode, forKey: .mode)
        try container.encode(type, forKey: .type)
        try container.encode(sha, forKey: .sha)
    }
}

struct GitHubCommitFilesPage: Codable, Sendable {
    let files: [GitHubComparisonFile]?
}

struct GitHubCommitAuthorPayload: Encodable, Sendable {
    let name: String
    let email: String
    let date: Date?
}

enum GitHubRebaseError: LocalizedError {
    case defaultBranch
    case protectedBranch
    case sameBranch
    case tooManyCommits
    case incompleteComparison
    case mergeCommit(String)
    case conflictingPaths([String])
    case branchMoved
    case truncatedTree
    case missingTreeEntry(String)
    case unsupportedFileStatus(String)
    case graphQL(String)

    var errorDescription: String? {
        switch self {
        case .defaultBranch:
            return "Rebasing the repository's default branch is not supported."
        case .protectedBranch:
            return "Protected branches cannot be rebased by MyApps."
        case .sameBranch:
            return "Choose a different destination branch."
        case .tooManyCommits:
            return "This rebase is too large for the safe mobile workflow. Reduce the branch history first."
        case .incompleteComparison:
            return "GitHub did not return the complete commit range, so MyApps will not rewrite the branch."
        case let .mergeCommit(sha):
            return "The replay range contains merge commit \(String(sha.prefix(7))). Rebase with merges is not supported yet."
        case let .conflictingPaths(paths):
            let preview = paths.prefix(5).joined(separator: ", ")
            return "The destination changed files also touched by this branch: \(preview). Resolve or rebase this branch with Git first."
        case .branchMoved:
            return "A selected branch changed while the rebase was being prepared. Refresh and try again."
        case .truncatedTree:
            return "The repository tree is too large for MyApps to verify safely."
        case let .missingTreeEntry(path):
            return "Could not resolve Git tree entry for \(path)."
        case let .unsupportedFileStatus(status):
            return "The rebase contains unsupported file status “\(status)”."
        case let .graphQL(message):
            return message
        }
    }
}
