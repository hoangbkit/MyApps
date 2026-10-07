import Foundation

struct GitHubComparison: Codable, Hashable, Sendable {
    let status: String
    let aheadBy: Int
    let behindBy: Int
    let totalCommits: Int
    let commits: [GitHubCommit]

    enum CodingKeys: String, CodingKey {
        case status
        case aheadBy = "ahead_by"
        case behindBy = "behind_by"
        case totalCommits = "total_commits"
        case commits
    }
}

enum GitHubMergeResult: Sendable {
    case merged(GitHubCommit)
    case alreadyUpToDate
}
