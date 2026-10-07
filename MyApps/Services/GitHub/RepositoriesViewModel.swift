import Combine
import Foundation

@MainActor
final class RepositoriesViewModel: ObservableObject {
    @Published private(set) var repositories: [GitHubRepository] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var hasLoaded = false

    func load(using client: GitHubAPIClient?, force: Bool = false) async {
        guard let client else {
            repositories = []
            hasLoaded = false
            return
        }

        guard force || !hasLoaded else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            repositories = try await client.repositories()
            hasLoaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        repositories = []
        isLoading = false
        errorMessage = nil
        hasLoaded = false
    }
}
