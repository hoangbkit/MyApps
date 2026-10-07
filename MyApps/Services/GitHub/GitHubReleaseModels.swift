import Foundation

struct GitHubRelease: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let tagName: String
    let targetCommitish: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let htmlURL: URL
    let createdAt: Date
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case targetCommitish = "target_commitish"
        case name
        case body
        case draft
        case prerelease
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case publishedAt = "published_at"
    }

    var isMyCLIBuild: Bool {
        tagName.hasPrefix("mycli-build-")
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? tagName : trimmed
    }

    var displayDate: Date {
        publishedAt ?? createdAt
    }
}

struct GitHubCreateReleaseRequest: Encodable, Sendable {
    let tagName: String
    let targetCommitish: String
    let name: String
    let body: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case targetCommitish = "target_commitish"
        case name
        case body
        case draft
        case prerelease
    }
}
