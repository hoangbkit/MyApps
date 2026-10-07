import Foundation

struct GitHubRepository: Codable, Identifiable, Hashable, Sendable {
    struct Owner: Codable, Hashable, Sendable {
        let login: String
    }

    struct Permissions: Codable, Hashable, Sendable {
        let admin: Bool?
        let maintain: Bool?
        let push: Bool?
        let triage: Bool?
        let pull: Bool?
    }

    let id: Int
    let name: String
    let fullName: String
    let owner: Owner
    let isPrivate: Bool
    let isFork: Bool
    let isArchived: Bool
    let language: String?
    let defaultBranch: String
    let htmlURL: URL
    let pushedAt: Date?
    let permissions: Permissions?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case owner
        case isPrivate = "private"
        case isFork = "fork"
        case isArchived = "archived"
        case language
        case defaultBranch = "default_branch"
        case htmlURL = "html_url"
        case pushedAt = "pushed_at"
        case permissions
    }

    var hasWriteAccess: Bool {
        guard let permissions else { return true }
        return permissions.push == true || permissions.maintain == true || permissions.admin == true
    }

    var canAttemptWrite: Bool {
        !isArchived && hasWriteAccess
    }
}
