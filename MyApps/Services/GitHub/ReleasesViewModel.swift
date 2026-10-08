import Combine
import Foundation

@MainActor
final class ReleasesViewModel: ObservableObject {
    @Published private(set) var releases: [GitHubRelease] = []
    @Published private(set) var tags: [GitHubTag] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var hasLoaded = false
    private var loadGeneration = 0

    func load(
        repository: GitHubRepository,
        client: GitHubAPIClient?,
        force: Bool = false
    ) async {
        guard let client else {
            errorMessage = "GitHub is not connected."
            return
        }

        guard force || !hasLoaded else { return }

        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            async let releasesRequest = client.releases(repository: repository)
            async let tagsRequest = client.tags(repository: repository)
            let (fetched, freshTags) = try await (releasesRequest, tagsRequest)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            releases = fetched
            tags = freshTags
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard generation == loadGeneration,
                  !Task.isCancelled, !GitHubAPIClient.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }
}
