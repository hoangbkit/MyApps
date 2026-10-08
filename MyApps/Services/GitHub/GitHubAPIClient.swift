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

/// A per-branch pagination request for an All Branches log.
struct GitHubBranchHistoryCursor: Sendable {
    let branch: String
    let headSHA: String
    let page: Int
}

struct GitHubBranchHistoryPage: Sendable {
    let branch: String
    let headSHA: String
    let page: Int
    let commits: [GitHubCommit]
}

struct GitHubAPIClient: Sendable {
    private struct MergeBody: Encodable {
        let base: String
        let head: String
    }

    private struct CreateTagObjectBody: Encodable {
        let tag: String
        let message: String
        let object: String
        let type: String
    }

    private struct CreateTagObjectResponse: Decodable {
        let sha: String
    }

    private struct CreateRefBody: Encodable {
        let ref: String
        let sha: String
    }

    private struct CreateRefResponse: Decodable {
        let ref: String
    }

    private struct GitHubErrorMessage: Decodable {
        let message: String?
    }

    private struct CreateTreeBody: Encodable {
        let baseTree: String
        let tree: [GitHubTreeMutationEntry]

        enum CodingKeys: String, CodingKey {
            case baseTree = "base_tree"
            case tree
        }
    }

    private struct CreateCommitBody: Encodable {
        let message: String
        let tree: String
        let parents: [String]
        let author: GitHubCommitAuthorPayload?
    }

    private struct GraphQLUpdateRefsVariables: Encodable {
        let repositoryID: String
        let sourceName: String
        let sourceBefore: String
        let sourceAfter: String
        let destinationName: String
        let destinationOID: String
    }

    private struct GraphQLUpdateRefsBody: Encodable {
        let query: String
        let variables: GraphQLUpdateRefsVariables
    }

    private struct GraphQLErrorItem: Decodable {
        let message: String
    }

    private struct GraphQLUpdateRefsResponse: Decodable {
        let errors: [GraphQLErrorItem]?
    }

    // URLSession cancellation errors (-999) are not always CancellationError.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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

    func createLightweightTag(
        repository: GitHubRepository,
        name: String,
        targetSHA: String
    ) async throws {
        try await createTagRef(
            repository: repository,
            name: name,
            objectSHA: targetSHA
        )
    }

    func createAnnotatedTag(
        repository: GitHubRepository,
        name: String,
        message: String,
        targetSHA: String
    ) async throws {
        let body = try jsonEncoder().encode(
            CreateTagObjectBody(
                tag: name,
                message: message,
                object: targetSHA,
                type: "commit"
            )
        )

        let (data, response) = try await perform(
            method: "POST",
            path: "/repos/\(repository.owner.login)/\(repository.name)/git/tags",
            body: body
        )

        guard response.statusCode == 201 else {
            throw tagWriteError(status: response.statusCode, data: data)
        }

        let tagObject = try decode(CreateTagObjectResponse.self, from: data)
        try await createTagRef(
            repository: repository,
            name: name,
            objectSHA: tagObject.sha
        )
    }

    func releases(repository: GitHubRepository) async throws -> [GitHubRelease] {
        try await paginated(
            path: "/repos/\(repository.owner.login)/\(repository.name)/releases"
        )
    }

    func createRelease(
        repository: GitHubRepository,
        request release: GitHubCreateReleaseRequest
    ) async throws -> GitHubRelease {
        let body = try jsonEncoder().encode(release)

        let (data, response) = try await perform(
            method: "POST",
            path: "/repos/\(repository.owner.login)/\(repository.name)/releases",
            body: body
        )

        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(response.statusCode)
        }

        return try decode(GitHubRelease.self, from: data)
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

    /// Fetch a page for every requested branch, bounded to four concurrent
    /// GitHub calls. A failure aborts the batch: callers never present a
    /// partially loaded All Branches history as though it were complete.
    func commitPages(
        repository: GitHubRepository,
        cursors: [GitHubBranchHistoryCursor],
        perPage: Int
    ) async throws -> [GitHubBranchHistoryPage] {
        let batchSize = 4
        var allPages: [GitHubBranchHistoryPage] = []
        allPages.reserveCapacity(cursors.count)

        for start in stride(from: 0, to: cursors.count, by: batchSize) {
            try Task.checkCancellation()
            let end = min(start + batchSize, cursors.count)
            let batch = Array(cursors[start..<end])

            let pages = try await withThrowingTaskGroup(
                of: GitHubBranchHistoryPage.self,
                returning: [GitHubBranchHistoryPage].self
            ) { group in
                for cursor in batch {
                    group.addTask {
                        let commits = try await self.commits(
                            repository: repository,
                            branch: cursor.headSHA,
                            page: cursor.page,
                            perPage: perPage
                        )
                        return GitHubBranchHistoryPage(
                            branch: cursor.branch,
                            headSHA: cursor.headSHA,
                            page: cursor.page,
                            commits: commits
                        )
                    }
                }

                var received: [GitHubBranchHistoryPage] = []
                for try await page in group {
                    received.append(page)
                }
                return received
            }

            allPages.append(contentsOf: pages)
        }

        return allPages
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

    func gitCommit(
        repository: GitHubRepository,
        sha: String
    ) async throws -> GitHubGitCommitObject {
        try await request(
            path: "/repos/\(repository.owner.login)/\(repository.name)/git/commits/\(sha)"
        )
    }

    func gitTree(
        repository: GitHubRepository,
        sha: String
    ) async throws -> GitHubGitTree {
        try await request(
            path: "/repos/\(repository.owner.login)/\(repository.name)/git/trees/\(sha)",
            queryItems: [URLQueryItem(name: "recursive", value: "1")]
        )
    }

    func commitFiles(
        repository: GitHubRepository,
        sha: String
    ) async throws -> [GitHubComparisonFile] {
        let pageSize = 100
        var page = 1
        var files: [GitHubComparisonFile] = []

        while true {
            let response: GitHubCommitFilesPage = try await request(
                path: "/repos/\(repository.owner.login)/\(repository.name)/commits/\(sha)",
                queryItems: [
                    URLQueryItem(name: "per_page", value: String(pageSize)),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )

            let batch = response.files ?? []
            files.append(contentsOf: batch)

            guard batch.count == pageSize else {
                return files
            }

            page += 1
        }
    }

    func createTree(
        repository: GitHubRepository,
        baseTreeSHA: String,
        entries: [GitHubTreeMutationEntry]
    ) async throws -> GitHubGitTree {
        let body = try jsonEncoder().encode(
            CreateTreeBody(baseTree: baseTreeSHA, tree: entries)
        )

        let (data, response) = try await perform(
            method: "POST",
            path: "/repos/\(repository.owner.login)/\(repository.name)/git/trees",
            body: body
        )

        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(response.statusCode)
        }

        return try decode(GitHubGitTree.self, from: data)
    }

    func createCommit(
        repository: GitHubRepository,
        message: String,
        treeSHA: String,
        parentSHA: String,
        author: GitHubCommitAuthorPayload?
    ) async throws -> GitHubGitCommitObject {
        let body = try jsonEncoder().encode(
            CreateCommitBody(
                message: message,
                tree: treeSHA,
                parents: [parentSHA],
                author: author
            )
        )

        let (data, response) = try await perform(
            method: "POST",
            path: "/repos/\(repository.owner.login)/\(repository.name)/git/commits",
            body: body
        )

        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(response.statusCode)
        }

        return try decode(GitHubGitCommitObject.self, from: data)
    }

    func updateRebasedBranchWithLease(
        repository: GitHubRepository,
        sourceBranch: String,
        expectedSourceSHA: String,
        newSourceSHA: String,
        destinationBranch: String,
        expectedDestinationSHA: String
    ) async throws {
        let query = """
        mutation UpdateRebasedBranch(
          $repositoryID: ID!,
          $sourceName: GitRefname!,
          $sourceBefore: GitObjectID!,
          $sourceAfter: GitObjectID!,
          $destinationName: GitRefname!,
          $destinationOID: GitObjectID!
        ) {
          updateRefs(input: {
            repositoryId: $repositoryID,
            refUpdates: [
              {
                name: $sourceName,
                beforeOid: $sourceBefore,
                afterOid: $sourceAfter,
                force: true
              },
              {
                name: $destinationName,
                beforeOid: $destinationOID,
                afterOid: $destinationOID,
                force: false
              }
            ]
          }) {
            clientMutationId
          }
        }
        """

        let payload = GraphQLUpdateRefsBody(
            query: query,
            variables: GraphQLUpdateRefsVariables(
                repositoryID: repository.nodeID,
                sourceName: "refs/heads/\(sourceBranch)",
                sourceBefore: expectedSourceSHA,
                sourceAfter: newSourceSHA,
                destinationName: "refs/heads/\(destinationBranch)",
                destinationOID: expectedDestinationSHA
            )
        )

        guard let url = URL(string: "https://api.github.com/graphql") else {
            throw GitHubAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try jsonEncoder().encode(payload)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MyApps", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(response.statusCode)
        }

        let decoded = try JSONDecoder().decode(GraphQLUpdateRefsResponse.self, from: data)
        if let message = decoded.errors?.first?.message {
            throw GitHubRebaseError.graphQL(
                "The branch changed or GitHub rejected the atomic ref update: \(message)"
            )
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

    private func createTagRef(
        repository: GitHubRepository,
        name: String,
        objectSHA: String
    ) async throws {
        let body = try jsonEncoder().encode(
            CreateRefBody(
                ref: "refs/tags/\(name)",
                sha: objectSHA
            )
        )

        let (data, response) = try await perform(
            method: "POST",
            path: "/repos/\(repository.owner.login)/\(repository.name)/git/refs",
            body: body
        )

        guard response.statusCode == 201 else {
            throw tagWriteError(status: response.statusCode, data: data)
        }

        _ = try decode(CreateRefResponse.self, from: data)
    }

    private func tagWriteError(status: Int, data: Data) -> GitHubAPIError {
        // GitHub's error message usually identifies insufficient PAT scopes,
        // tag protection rulesets, or an existing ref. Preserve that useful
        // explanation rather than reducing every rejection to HTTP 403/422.
        let response = try? JSONDecoder().decode(GitHubErrorMessage.self, from: data)
        let message = response?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .tagWriteFailed(status, message.flatMap {
            $0.isEmpty ? nil : String($0.prefix(300))
        })
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

    private func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

enum GitHubAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case mergeConflict
    case tagWriteFailed(Int, String?)
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
            return "GitHub rejected this operation as invalid or the ref already exists."
        case let .httpStatus(status):
            return "GitHub returned HTTP \(status)."
        case .mergeConflict:
            return "GitHub could not merge these branches automatically because they conflict."
        case let .tagWriteFailed(status, detail):
            let explanation: String
            switch status {
            case 401:
                explanation = "GitHub rejected the token. Check Settings → GitHub."
            case 403:
                explanation = "GitHub denied tag creation. The PAT needs Contents: read/write access, and tag rulesets may restrict creation."
            case 409, 422:
                explanation = "GitHub rejected the tag. It may already exist or violate a tag naming/protection rule."
            default:
                explanation = "GitHub could not create the tag (HTTP \(status))."
            }
            if let detail {
                return "\(explanation) GitHub: \(detail)"
            }
            return explanation
        case let .decoding(error):
            return "Could not read GitHub's response. \(error.localizedDescription)"
        }
    }
}
