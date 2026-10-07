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
    private let token: String
    private let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func currentUser() async throws -> GitHubAccount {
        try await request(path: "/user")
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

    private func request<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw GitHubAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MyApps", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(response.statusCode)
        }

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
            return "GitHub denied this request. Check the token permissions."
        case .httpStatus(404):
            return "The requested GitHub resource was not found."
        case let .httpStatus(status):
            return "GitHub returned HTTP \(status)."
        case let .decoding(error):
            return "Could not read GitHub's response. \(error.localizedDescription)"
        }
    }
}
