import Foundation

struct GitHubAccount: Codable, Equatable, Sendable {
    let id: Int
    let login: String
    let name: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case name
        case avatarURL = "avatar_url"
    }
}

struct GitHubAPIClient: Sendable {
    private struct MergeBody: Encodable {
        let base: String
        let head: String
    }

    private let token: String
    private let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func currentUser() async throws -> GitHubAccount {
        try await request(path: "/user")
    }

    func branches(repository: GitHubRepository) async throws -> [GitHubBranch] {
        try await paginated(
            path: "/repos/\(repository.owner.login)/\(repository.name)/branches"
        )
    }

    func tags(repository: GitHubRepository) async throws -> [GitHubTag] {
        try await paginated(
            path: "/repos/\(repository.owner.login)/\(repository.name)/tags"
        )
    }

    func commits(
        repository: GitHubRepository,
        branch: String,
        page: Int,
        perPage: Int
    ) async throws -> [GitHubCommit] {
        try await request(
            path: "/repos/\(repository.owner.login)/\(repository.name)/commits",
            queryItems: [
                URLQueryItem(name: "sha", value: branch),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
    }

    func compare(
        repository: GitHubRepository,
        baseSHA: String,
        headSHA: String
    ) async throws -> GitHubComparison {
        try await request(
            path: "/repos/\(repository.owner.login)/\(repository.name)/compare/\(baseSHA)...\(headSHA)"
        )
    }

    func merge(
        repository: GitHubRepository,
        sourceBranch: String,
        destinationBranch: String
    ) async throws -> GitHubMergeResult {
        let body = try JSONEncoder().encode(
            MergeBody(base: destinationBranch, head: sourceBranch)
        )

        let (data, response) = try await perform(
            method: "POST",
            path: "/repos/\(repository.owner.login)/\(repository.name)/merges",
            body: body
        )

        switch response.statusCode {
        case 201:
            return .merged(try decode(GitHubCommit.self, from: data))
        case 204:
            return .alreadyUpToDate
        case 409:
            throw GitHubAPIError.mergeConflict
        default:
            throw GitHubAPIError.httpStatus(response.statusCode)
        }
    }

    func repositories() async throws -> [GitHubRepository] {
        let pageSize = 100
        var page = 1
        var repositories: [GitHubRepository] = []

        while true {
            try Task.checkCancellation()

            let batch: [GitHubRepository] = try await request(
                path: "/user/repos",
                queryItems: [
                    URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
                    URLQueryItem(name: "visibility", value: "all"),
                    URLQueryItem(name: "sort", value: "updated"),
                    URLQueryItem(name: "direction", value: "desc"),
                    URLQueryItem(name: "per_page", value: String(pageSize)),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )

            repositories.append(contentsOf: batch)

            guard batch.count == pageSize else {
                return repositories
            }

            page += 1
        }
    }

    private func paginated<Response: Decodable & Sendable>(
        path: String
    ) async throws -> [Response] {
        let pageSize = 100
        var page = 1
        var values: [Response] = []

        while true {
            try Task.checkCancellation()

            let batch: [Response] = try await request(
                path: path,
                queryItems: [
                    URLQueryItem(name: "per_page", value: String(pageSize)),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )

            values.append(contentsOf: batch)

            guard batch.count == pageSize else {
                return values
            }

            page += 1
        }
    }

    private func request<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let (data, response) = try await perform(
            method: "GET",
            path: path,
            queryItems: queryItems
        )

        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(response.statusCode)
        }

        return try decode(Response.self, from: data)
    }

    private func perform(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw GitHubAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MyApps", forHTTPHeaderField: "User-Agent")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        return (data, response)
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data
    ) throws -> Response {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw GitHubAPIError.decoding(error)
        }
    }
}

enum GitHubAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case mergeConflict
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The GitHub API URL is invalid."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .httpStatus(401):
            return "GitHub rejected the token. Check that it is valid and has not expired."
        case .httpStatus(403):
            return "GitHub denied this request. Check repository permissions or branch protection."
        case .httpStatus(404):
            return "The requested GitHub resource was not found."
        case .httpStatus(422):
            return "GitHub rejected the branch operation as invalid."
        case let .httpStatus(status):
            return "GitHub returned HTTP \(status)."
        case .mergeConflict:
            return "GitHub could not merge these branches automatically because they conflict."
        case let .decoding(error):
            return "Could not read GitHub's response. \(error.localizedDescription)"
        }
    }
}
