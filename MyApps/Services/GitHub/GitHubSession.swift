import Combine
import Foundation

@MainActor
final class GitHubSession: ObservableObject {
    enum ConnectionState: Equatable {
        case loading
        case disconnected
        case connected(GitHubAccount)
    }

    @Published private(set) var connectionState: ConnectionState = .loading
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private var token: String?
    private var hasRestored = false

    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true

        do {
            guard let storedToken = try GitHubCredentialStore.loadToken() else {
                connectionState = .disconnected
                return
            }

            token = storedToken
            let account = try await GitHubAPIClient(token: storedToken).currentUser()
            connectionState = .connected(account)
        } catch {
            connectionState = .disconnected
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func connect(token rawToken: String) async -> Bool {
        let candidate = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            errorMessage = "Enter a GitHub personal access token."
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let account = try await GitHubAPIClient(token: candidate).currentUser()
            try GitHubCredentialStore.saveToken(candidate)
            token = candidate
            connectionState = .connected(account)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func disconnect() {
        do {
            try GitHubCredentialStore.deleteToken()
            token = nil
            connectionState = .disconnected
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func client() -> GitHubAPIClient? {
        guard let token else { return nil }
        return GitHubAPIClient(token: token)
    }
}
