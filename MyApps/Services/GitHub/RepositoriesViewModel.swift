import Combine
import Foundation

@MainActor
final class RepositoriesViewModel: ObservableObject {
    @Published private(set) var repositories: [GitHubRepository] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var hasLoaded = false
    private var loadGeneration = 0

    func load(using client: GitHubAPIClient?, force: Bool = false) async {
        guard let client else {
            reset()
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
            let fetched = try await client.repositories()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            repositories = fetched
            hasLoaded = true
        } catch {
            guard generation == loadGeneration,
                  !Task.isCancelled,
                  !GitHubAPIClient.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        loadGeneration += 1
        repositories = []
        isLoading = false
        errorMessage = nil
        hasLoaded = false
    }
}
