import CryptoKit
import Foundation

/// The icon is an included \`buildIcons\` resource in the List Apps response.
/// Apple supplies the image as a size-parameterized CDN URL, not as a raw PNG.
struct AppStoreConnectImageAsset: Decodable, Sendable {
    let templateUrl: String
    let width: Int?
    let height: Int?

    func thumbnailURL(size: Int = 120) -> URL? {
        let resolved = templateUrl
            .replacingOccurrences(of: "{w}", with: String(size))
            .replacingOccurrences(of: "{h}", with: String(size))
            .replacingOccurrences(of: "{f}", with: "png")
        guard let url = URL(string: resolved),
              url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "mzstatic.com" || host.hasSuffix(".mzstatic.com"),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else {
            return nil
        }
        return url
    }
}

struct AppStoreConnectBuildIconAttributes: Decodable, Sendable {
    let iconAsset: AppStoreConnectImageAsset?
}

private enum AppStoreConnectIncludedResource: Decodable, Sendable {
    case buildIcon(id: String, attributes: AppStoreConnectBuildIconAttributes?)
    case version(AppStoreConnectVersion)
    case unsupported

    private enum CodingKeys: String, CodingKey {
        case id, type, attributes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "buildIcons":
            self = .buildIcon(
                id: try container.decode(String.self, forKey: .id),
                attributes: try container.decodeIfPresent(
                    AppStoreConnectBuildIconAttributes.self,
                    forKey: .attributes
                )
            )
        case "appStoreVersions":
            self = .version(try AppStoreConnectVersion(from: decoder))
        default:
            self = .unsupported
        }
    }
}

struct AppStoreConnectAppCatalog: Sendable {
    let apps: [AppStoreConnectApp]
    let iconURLsByAppID: [String: URL]
    let versionsByAppID: [String: [AppStoreConnectVersion]]
}

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

struct AppStoreConnectSCMRepositoryAttributes: Decodable, Sendable {
    let ownerName: String?
    let repositoryName: String?
}

struct AppStoreConnectGitReferenceAttributes: Decodable, Sendable {
    let name: String?
    let canonicalName: String?
    let kind: String?
    let isDeleted: Bool?

    var isBuildable: Bool {
        guard isDeleted != true else { return false }
        switch kind?.uppercased() {
        case "BRANCH", "TAG": return true
        default: return false
        }
    }

    var displayName: String {
        name ?? canonicalName ?? "Unknown reference"
    }

    var isBranch: Bool { kind?.uppercased() == "BRANCH" }
}

struct AppStoreConnectIssueCounts: Decodable, Sendable {
    let errors: Int?
    let warnings: Int?
    let testFailures: Int?
    let analyzerWarnings: Int?

    var total: Int {
        (errors ?? 0) + (warnings ?? 0) +
        (testFailures ?? 0) + (analyzerWarnings ?? 0)
    }
}

struct AppStoreConnectCommit: Decodable, Sendable {
    let commitSha: String?
    let message: String?
    let webUrl: String?
    let author: Author?

    struct Author: Decodable, Sendable {
        let displayName: String?
    }
}

struct AppStoreConnectBuildActionAttributes: Decodable, Sendable {
    let name: String?
    let actionType: String?
    let startedDate: String?
    let finishedDate: String?
    let issueCounts: AppStoreConnectIssueCounts?
    let executionProgress: String?
    let completionStatus: String?
    let isRequiredToPass: Bool?
}

struct AppStoreConnectFileSource: Decodable, Sendable {
    let path: String?
    let lineNumber: Int?
    let columnNumber: Int?
}

struct AppStoreConnectIssueAttributes: Decodable, Sendable {
    let issueType: String?
    let message: String?
    let fileSource: AppStoreConnectFileSource?
    let category: String?
}

struct AppStoreConnectTestResultAttributes: Decodable, Sendable {
    let className: String?
    let name: String?
    let status: String?
    let message: String?
    let fileSource: AppStoreConnectFileSource?
}

struct AppStoreConnectBuildDetail: Sendable {
    let run: AppStoreConnectBuildRun
    let sourceReferenceName: String?
    let workflowName: String?
}

private struct AppStoreConnectBuildDetailResponse: Decodable {
    let data: AppStoreConnectBuildRun
    let included: [IncludedReference]?

    struct IncludedReference: Decodable {
        let id: String
        let type: String
        let attributes: AppStoreConnectGitReferenceAttributes?
    }

    var sourceReferenceName: String? {
        guard let id = data.relationships?.sourceBranchOrTag?.data?.id else { return nil }
        return included?.first(where: { $0.id == id && $0.type == "scmGitReferences" })?
            .attributes?.displayName
    }

    var workflowName: String? {
        guard let id = data.relationships?.workflow?.data?.id else { return nil }
        return included?.first(where: { $0.id == id && $0.type == "ciWorkflows" })?
            .attributes?.name
    }
}

struct AppStoreConnectBuildRunAttributes: Decodable, Sendable {
    let number: Int?
    let createdDate: String?
    let startedDate: String?
    let finishedDate: String?
    let executionProgress: String?
    let completionStatus: String?
    let startReason: String?
    let sourceCommit: AppStoreConnectCommit?
    let issueCounts: AppStoreConnectIssueCounts?
}

struct AppStoreConnectResource<Attributes: Decodable & Sendable>: Decodable, Identifiable, Sendable {
    let id: String
    let attributes: Attributes
    let relationships: AppStoreConnectRelationships?
}

struct AppStoreConnectRelationships: Decodable, Sendable {
    let workflow: AppStoreConnectRelationship?
    let defaultBranch: AppStoreConnectRelationship?
    let appStoreIcon: AppStoreConnectRelationship?
    let appStoreVersions: AppStoreConnectToManyRelationship?
    let sourceBranchOrTag: AppStoreConnectRelationship?
}

struct AppStoreConnectRelationship: Decodable, Sendable {
    let data: AppStoreConnectResourceIdentifier?
}

struct AppStoreConnectToManyRelationship: Decodable, Sendable {
    let data: [AppStoreConnectResourceIdentifier]
}

struct AppStoreConnectResourceIdentifier: Decodable, Sendable {
    let id: String
}

typealias AppStoreConnectApp = AppStoreConnectResource<AppStoreConnectAppAttributes>
typealias AppStoreConnectVersion = AppStoreConnectResource<AppStoreConnectVersionAttributes>
typealias AppStoreConnectProduct = AppStoreConnectResource<AppStoreConnectProductAttributes>
typealias AppStoreConnectWorkflow = AppStoreConnectResource<AppStoreConnectWorkflowAttributes>
typealias AppStoreConnectBuildRun = AppStoreConnectResource<AppStoreConnectBuildRunAttributes>
typealias AppStoreConnectBuildAction = AppStoreConnectResource<AppStoreConnectBuildActionAttributes>
typealias AppStoreConnectIssue = AppStoreConnectResource<AppStoreConnectIssueAttributes>
typealias AppStoreConnectTestResult = AppStoreConnectResource<AppStoreConnectTestResultAttributes>
typealias AppStoreConnectSCMRepository = AppStoreConnectResource<AppStoreConnectSCMRepositoryAttributes>
typealias AppStoreConnectGitReference = AppStoreConnectResource<AppStoreConnectGitReferenceAttributes>

private struct AppStoreConnectPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let data: [Item]
    let included: [AppStoreConnectIncludedResource]?
    let links: PageLinks?

    struct PageLinks: Decodable, Sendable {
        let next: String?
    }
}

private struct AppStoreConnectSingle<Item: Decodable & Sendable>: Decodable, Sendable {
    let data: Item?
}

private struct AppStoreConnectBuildRunCreateRequest: Encodable {
    let data: Resource

    struct Resource: Encodable {
        let type = "ciBuildRuns"
        let attributes = Attributes()
        let relationships: Relationships
    }

    struct Attributes: Encodable {}

    struct Relationships: Encodable {
        let workflow: Relationship
        let sourceBranchOrTag: Relationship
    }

    struct Relationship: Encodable {
        let data: Identifier
    }

    struct Identifier: Encodable {
        let type: String
        let id: String
    }

    init(workflowID: String, gitReferenceID: String) {
        data = Resource(relationships: Relationships(
            workflow: Relationship(data: Identifier(type: "ciWorkflows", id: workflowID)),
            sourceBranchOrTag: Relationship(data: Identifier(type: "scmGitReferences", id: gitReferenceID))
        ))
    }
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

    func apps(bypassCache: Bool = false) async throws -> [AppStoreConnectApp] {
        try await appsWithIcons(bypassCache: bypassCache).apps
    }

    /// Retrieves app icons and version statuses in the same paginated ASC request as the apps.
    /// Avoids public store lookup (which cannot find unreleased apps) and
    /// avoids N additional network requests for N apps.
    func appsWithIcons(bypassCache: Bool = false) async throws -> AppStoreConnectAppCatalog {
        var url = try apiURL(path: "/v1/apps", query: [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "include", value: "appStoreIcon,appStoreVersions"),
            URLQueryItem(name: "fields[buildIcons]", value: "iconAsset"),
            URLQueryItem(
                name: "fields[appStoreVersions]",
                value: "platform,versionString,appVersionState,appStoreState,createdDate"
            ),
            URLQueryItem(name: "limit[appStoreVersions]", value: "50")
        ])
        let cachePolicy: URLRequest.CachePolicy = bypassCache
            ? .reloadIgnoringLocalCacheData
            : .returnCacheDataElseLoad

        var apps: [AppStoreConnectApp] = []
        var icons: [String: URL] = [:]
        var versionsByAppID: [String: [AppStoreConnectVersion]] = [:]
        var visited = Set<URL>()

        while visited.insert(url).inserted {
            try Task.checkCancellation()
            let page: AppStoreConnectPage<AppStoreConnectApp> = try await get(
                url: url,
                cachePolicy: cachePolicy
            )

            var includedIcons: [String: URL] = [:]
            var includedVersions: [String: AppStoreConnectVersion] = [:]
            for resource in page.included ?? [] {
                switch resource {
                case let .buildIcon(id, attributes):
                    if let url = attributes?.iconAsset?.thumbnailURL() {
                        includedIcons[id] = url
                    }
                case let .version(version):
                    includedVersions[version.id] = version
                case .unsupported:
                    break
                }
            }
            for app in page.data {
                if let iconID = app.relationships?.appStoreIcon?.data?.id,
                   let iconURL = includedIcons[iconID] {
                    icons[app.id] = iconURL
                }
                let versionIDs = app.relationships?.appStoreVersions?.data ?? []
                versionsByAppID[app.id] = versionIDs.compactMap {
                    includedVersions[$0.id]
                }
            }
            apps.append(contentsOf: page.data)

            guard let next = page.links?.next else {
                return AppStoreConnectAppCatalog(
                    apps: apps,
                    iconURLsByAppID: icons,
                    versionsByAppID: versionsByAppID
                )
            }
            guard let nextURL = URL(string: next, relativeTo: url)?.absoluteURL,
                  isTrusted(nextURL) else {
                throw AppStoreConnectAPIError.invalidResponse
            }
            url = nextURL
        }
        throw AppStoreConnectAPIError.invalidResponse
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

    func buildDetail(for runID: String) async throws -> AppStoreConnectBuildDetail {
        let response: AppStoreConnectBuildDetailResponse = try await get(
            path: "/v1/ciBuildRuns/\(runID)",
            query: [URLQueryItem(name: "include", value: "sourceBranchOrTag,workflow")]
        )
        return AppStoreConnectBuildDetail(
            run: response.data,
            sourceReferenceName: response.sourceReferenceName,
            workflowName: response.workflowName
        )
    }

    func buildActions(for runID: String) async throws -> [AppStoreConnectBuildAction] {
        try await allPages(
            path: "/v1/ciBuildRuns/\(runID)/actions",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
    }

    func issues(for actionID: String) async throws -> [AppStoreConnectIssue] {
        try await allPages(
            path: "/v1/ciBuildActions/\(actionID)/issues",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
    }

    func testResults(for actionID: String) async throws -> [AppStoreConnectTestResult] {
        try await allPages(
            path: "/v1/ciBuildActions/\(actionID)/testResults",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
    }

    /// Git references come from the repository associated with this exact
    /// workflow; GitHub branch IDs are not interchangeable with Apple's SCM IDs.
    func repository(for workflow: AppStoreConnectWorkflow) async throws -> AppStoreConnectSCMRepository {
        let response: AppStoreConnectSingle<AppStoreConnectSCMRepository> = try await get(
            path: "/v1/ciWorkflows/\(workflow.id)/repository",
            query: [URLQueryItem(name: "include", value: "defaultBranch")]
        )
        guard let repository = response.data else {
            throw AppStoreConnectAPIError.missingWorkflowRepository
        }
        return repository
    }

    func gitReferences(for repository: AppStoreConnectSCMRepository) async throws -> [AppStoreConnectGitReference] {
        let references: [AppStoreConnectGitReference] = try await allPages(
            path: "/v1/scmRepositories/\(repository.id)/gitReferences",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        return references.filter { $0.attributes.isBuildable }.sorted { lhs, rhs in
            if lhs.attributes.isBranch != rhs.attributes.isBranch {
                return lhs.attributes.isBranch
            }
            let order = lhs.attributes.displayName.localizedStandardCompare(rhs.attributes.displayName)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    /// The only mutating App Store Connect endpoint in MyApps: manual build
    /// creation. Report success only after Apple's 201 response and valid run.
    func startBuild(
        workflow: AppStoreConnectWorkflow,
        source: AppStoreConnectGitReference
    ) async throws -> AppStoreConnectBuildRun {
        guard workflow.attributes.isEnabled == true else {
            throw AppStoreConnectAPIError.disabledWorkflow
        }
        guard source.attributes.isBuildable else {
            throw AppStoreConnectAPIError.invalidSourceReference
        }

        let body = try JSONEncoder().encode(
            AppStoreConnectBuildRunCreateRequest(
                workflowID: workflow.id,
                gitReferenceID: source.id
            )
        )
        let url = try apiURL(path: "/v1/ciBuildRuns", query: [])
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(try authorizationToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreConnectAPIError.invalidResponse
        }
        guard http.statusCode == 201 else {
            throw AppStoreConnectAPIError.httpStatus(http.statusCode)
        }
        guard let buildRun = try JSONDecoder()
            .decode(AppStoreConnectSingle<AppStoreConnectBuildRun>.self, from: data).data else {
            throw AppStoreConnectAPIError.invalidResponse
        }
        return buildRun
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

    private func get<Response: Decodable & Sendable>(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    ) async throws -> Response {
        guard isTrusted(url) else { throw AppStoreConnectAPIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try authorizationToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if cachePolicy == .reloadIgnoringLocalCacheData {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
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
    case missingWorkflowRepository
    case disabledWorkflow
    case invalidSourceReference
    case invalidCredentials
    case invalidPrivateKey
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingWorkflowRepository:
            "This Xcode Cloud workflow has no connected Git repository."
        case .disabledWorkflow:
            "Choose an enabled Xcode Cloud workflow."
        case .invalidSourceReference:
            "Choose an existing Git branch or tag from this workflow's repository."
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
        case .httpStatus(409):
            "Xcode Cloud could not start this build because of a conflict. Refresh the workflow and reference."
        case .httpStatus(422):
            "Xcode Cloud rejected the workflow or source reference. Refresh and try again."
        case .httpStatus(429):
            "App Store Connect rate limit reached. Try again later."
        case let .httpStatus(status):
            "App Store Connect returned HTTP \(status)."
        }
    }
}
