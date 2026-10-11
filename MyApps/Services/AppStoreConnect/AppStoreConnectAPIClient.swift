import CryptoKit
import Foundation

struct AppStoreConnectAppAttributes: Decodable, Sendable {
    let name: String
    let bundleId: String?
    let sku: String?
    let primaryLocale: String?
    let isOrEverWasMadeForKids: Bool?
}

struct AppStoreConnectVersionAttributes: Decodable, Sendable {
    let platform: String?
    let versionString: String?
    let appVersionState: String?
    let appStoreState: String?
    let createdDate: String?

    var state: String? { appVersionState ?? appStoreState }
}

struct AppStoreConnectProductAttributes: Decodable, Sendable {
    let name: String?
    let productType: String?
    let createdDate: String?
}

struct AppStoreConnectWorkflowAttributes: Decodable, Sendable {
    let name: String
    let description: String?
    let isEnabled: Bool?
    let lastModifiedDate: String?
}

struct AppStoreConnectBuildRunAttributes: Decodable, Sendable {
    let number: Int?
    let createdDate: String?
    let startedDate: String?
    let finishedDate: String?
    let executionProgress: String?
    let completionStatus: String?
    let startReason: String?
}

struct AppStoreConnectResource<Attributes: Decodable & Sendable>: Decodable, Identifiable, Sendable {
    let id: String
    let attributes: Attributes
    let relationships: AppStoreConnectRelationships?
}

struct AppStoreConnectRelationships: Decodable, Sendable {
    let workflow: AppStoreConnectRelationship?
}

struct AppStoreConnectRelationship: Decodable, Sendable {
    let data: AppStoreConnectResourceIdentifier?
}

struct AppStoreConnectResourceIdentifier: Decodable, Sendable {
    let id: String
}

typealias AppStoreConnectApp = AppStoreConnectResource<AppStoreConnectAppAttributes>
typealias AppStoreConnectVersion = AppStoreConnectResource<AppStoreConnectVersionAttributes>
typealias AppStoreConnectProduct = AppStoreConnectResource<AppStoreConnectProductAttributes>
typealias AppStoreConnectWorkflow = AppStoreConnectResource<AppStoreConnectWorkflowAttributes>
typealias AppStoreConnectBuildRun = AppStoreConnectResource<AppStoreConnectBuildRunAttributes>

private struct AppStoreConnectPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let data: [Item]
    let links: PageLinks?

    struct PageLinks: Decodable, Sendable {
        let next: String?
    }
}

private struct AppStoreConnectSingle<Item: Decodable & Sendable>: Decodable, Sendable {
    let data: Item?
}

struct AppStoreConnectAPIClient: Sendable {
    private let credentials: AppStoreConnectCredentials
    private static let apiHost = "api.appstoreconnect.apple.com"

    init(credentials: AppStoreConnectCredentials) throws {
        guard UUID(uuidString: credentials.issuerID) != nil,
              !credentials.keyID.isEmpty,
              !credentials.privateKeyPEM.isEmpty else {
            throw AppStoreConnectAPIError.invalidCredentials
        }
        do {
            _ = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        } catch {
            throw AppStoreConnectAPIError.invalidPrivateKey
        }
        self.credentials = credentials
    }

    func validate() async throws {
        let _: AppStoreConnectPage<AppStoreConnectApp> = try await get(
            path: "/v1/apps", query: [URLQueryItem(name: "limit", value: "1")]
        )
    }

    func apps() async throws -> [AppStoreConnectApp] {
        try await allPages(path: "/v1/apps", query: [
            URLQueryItem(name: "limit", value: "200")
        ])
    }

    func versions(for app: AppStoreConnectApp) async throws -> [AppStoreConnectVersion] {
        try await allPages(
            path: "/v1/apps/\(app.id)/appStoreVersions",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
    }

    /// A 404 means Xcode Cloud has not been configured for the app.
    func product(for app: AppStoreConnectApp) async throws -> AppStoreConnectProduct? {
        do {
            let response: AppStoreConnectSingle<AppStoreConnectProduct> = try await get(
                path: "/v1/apps/\(app.id)/ciProduct"
            )
            return response.data
        } catch AppStoreConnectAPIError.httpStatus(404) {
            return nil
        }
    }

    func workflows(for product: AppStoreConnectProduct) async throws -> [AppStoreConnectWorkflow] {
        try await allPages(
            path: "/v1/ciProducts/\(product.id)/workflows",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
    }

    func recentBuildRuns(for product: AppStoreConnectProduct) async throws -> [AppStoreConnectBuildRun] {
        // Apple's API supports descending build number ordering, so the
        // first page contains the most recent runs without fetching full history.
        let page: AppStoreConnectPage<AppStoreConnectBuildRun> = try await get(
            path: "/v1/ciProducts/\(product.id)/buildRuns",
            query: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "sort", value: "-number")
            ]
        )
        return page.data.sorted {
            ($0.attributes.createdDate ?? "") > ($1.attributes.createdDate ?? "")
        }
    }

    private func allPages<Item: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> [Item] {
        var url = try apiURL(path: path, query: query)
        var results: [Item] = []
        var visited = Set<URL>()
        while visited.insert(url).inserted {
            try Task.checkCancellation()
            let response: AppStoreConnectPage<Item> = try await get(url: url)
            results.append(contentsOf: response.data)
            guard let next = response.links?.next else { return results }
            guard let nextURL = URL(string: next, relativeTo: url)?.absoluteURL,
                  isTrusted(nextURL) else { throw AppStoreConnectAPIError.invalidResponse }
            url = nextURL
        }
        throw AppStoreConnectAPIError.invalidResponse
    }

    private func get<Response: Decodable & Sendable>(
        path: String, query: [URLQueryItem] = []
    ) async throws -> Response {
        try await get(url: apiURL(path: path, query: query))
    }

    private func get<Response: Decodable & Sendable>(url: URL) async throws -> Response {
        guard isTrusted(url) else { throw AppStoreConnectAPIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try authorizationToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreConnectAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppStoreConnectAPIError.httpStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AppStoreConnectAPIError.invalidResponse
        }
    }

    private func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == Self.apiHost &&
        (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    private func apiURL(path: String, query: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.apiHost
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw AppStoreConnectAPIError.invalidResponse }
        return url
    }

    private func authorizationToken() throws -> String {
        let issued = Int(Date().timeIntervalSince1970)
        let header: [String: Any] = [
            "alg": "ES256", "kid": credentials.keyID, "typ": "JWT"
        ]
        let payload: [String: Any] = [
            "iss": credentials.issuerID,
            "iat": issued,
            "exp": issued + 600,
            "aud": "appstoreconnect-v1"
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let signingInput = [
            Self.base64URL(headerData),
            Self.base64URL(payloadData)
        ].joined(separator: ".")
        let key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        // CryptoKit rawRepresentation is the JOSE ES256 r || s signature.
        let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation
        return signingInput + "." + Self.base64URL(signature)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AppStoreConnectAPIError: LocalizedError, Equatable {
    case invalidCredentials
    case invalidPrivateKey
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Enter a valid issuer ID and API key ID."
        case .invalidPrivateKey:
            "The private key is not a valid App Store Connect .p8 signing key."
        case .invalidResponse:
            "App Store Connect returned an unexpected response."
        case .httpStatus(401):
            "App Store Connect rejected the credentials. Check the issuer ID, key ID, and private key."
        case .httpStatus(403):
            "Access denied. Check the API key role and app/Xcode Cloud permissions in App Store Connect."
        case .httpStatus(404):
            "The requested App Store Connect resource was not found."
        case .httpStatus(429):
            "App Store Connect rate limit reached. Try again later."
        case let .httpStatus(status):
            "App Store Connect returned HTTP \(status)."
        }
    }
}
