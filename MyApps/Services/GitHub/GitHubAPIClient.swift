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

    private func request<Response: Decodable & Sendable>(
        path: String
    ) async throws -> Response {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw GitHubAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MyApps", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(response.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
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
