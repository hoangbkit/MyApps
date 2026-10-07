import Foundation

struct GitHubBranch: Codable, Identifiable, Hashable, Sendable {
    struct CommitReference: Codable, Hashable, Sendable {
        let sha: String
    }

    let name: String
    let commit: CommitReference
    let isProtected: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case commit
        case isProtected = "protected"
    }
}

struct GitHubTag: Codable, Identifiable, Hashable, Sendable {
    struct CommitReference: Codable, Hashable, Sendable {
        let sha: String
    }

    let name: String
    let commit: CommitReference

    var id: String { name }
}

struct GitHubCommit: Codable, Identifiable, Hashable, Sendable {
    struct GitIdentity: Codable, Hashable, Sendable {
        let name: String
        let email: String?
        let date: Date?
    }

    struct CommitPayload: Codable, Hashable, Sendable {
        let message: String
        let author: GitIdentity?
        let committer: GitIdentity?
    }

    struct GitHubUser: Codable, Hashable, Sendable {
        let login: String
        let avatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }

    struct Parent: Codable, Hashable, Sendable {
        let sha: String
    }

    let sha: String
    let htmlURL: URL
    let commit: CommitPayload
    let author: GitHubUser?
    let committer: GitHubUser?
    let parents: [Parent]

    var id: String { sha }

    enum CodingKeys: String, CodingKey {
        case sha
        case htmlURL = "html_url"
        case commit
        case author
        case committer
        case parents
    }

    var shortSHA: String {
        String(sha.prefix(7))
    }

    var subject: String {
        commit.message
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? commit.message
    }

    var authorName: String {
        author?.login ?? commit.author?.name ?? "Unknown"
    }

    var authoredAt: Date? {
        commit.author?.date ?? commit.committer?.date
    }

    var isMerge: Bool {
        parents.count > 1
    }
}

struct GitHubCommitReferences: Hashable, Sendable {
    let branches: [String]
    let tags: [String]

    var isEmpty: Bool {
        branches.isEmpty && tags.isEmpty
    }
}
