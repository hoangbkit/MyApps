import Combine
import Foundation

@MainActor
final class ReleasesViewModel: ObservableObject {
    @Published private(set) var releases: [GitHubRelease] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var hasLoaded = false

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

        isLoading = true
        defer { isLoading = false }

        do {
            releases = try await client.releases(repository: repository)
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, !GitHubAPIClient.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }
}
