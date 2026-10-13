import Combine
import Foundation

@MainActor
final class AppStoreConnectSession: ObservableObject {
    enum ConnectionState {
        case loading
        case disconnected
        case connected(keyID: String)
    }

    enum ValidationState {
        case unchecked
        case checking
        case valid
        case failed
    }

    @Published private(set) var connectionState: ConnectionState = .loading
    @Published private(set) var validationState: ValidationState = .unchecked
    @Published private(set) var isWorking = false
    @Published private(set) var connectionRevision = 0
    @Published var errorMessage: String?

    private var credentials: AppStoreConnectCredentials?
    private var hasRestored = false

    func restore() async {
        guard !hasRestored, !isWorking else { return }
        hasRestored = true
        do {
            guard let stored = try AppStoreConnectCredentialStore.load() else {
                connectionState = .disconnected
                return
            }
            // Restore the saved configuration before validating it. Network,
            // authentication, and decoding failures must not hide stored keys.
            credentials = stored
            connectionState = .connected(keyID: stored.keyID)
            connectionRevision += 1
            errorMessage = nil
            await validateSavedCredentials()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                hasRestored = false
                return
            }
            connectionState = .disconnected
            hasRestored = false
            errorMessage = error.localizedDescription
        }
    }

    func validateSavedCredentials() async {
        guard let credentials, !isWorking else { return }
        let revision = connectionRevision
        isWorking = true
        validationState = .checking
        errorMessage = nil
        defer { isWorking = false }

        do {
            let client = try AppStoreConnectAPIClient(credentials: credentials)
            try await client.validate()
            try Task.checkCancellation()
            guard revision == connectionRevision else { return }
            validationState = .valid
        } catch {
            guard revision == connectionRevision else { return }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                validationState = .unchecked
                return
            }
            validationState = .failed
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func connect(issuerID: String, keyID: String, privateKeyPEM: String) async -> Bool {
        guard !isWorking else { return false }
        let proposed = AppStoreConnectCredentials(
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: Self.normalizedPEM(privateKeyPEM)
        )
        isWorking = true
        defer { isWorking = false }
        do {
            let client = try AppStoreConnectAPIClient(credentials: proposed)
            try await client.validate()
            try Task.checkCancellation()
            // Do not replace valid stored credentials unless Apple's validation succeeds.
            try AppStoreConnectCredentialStore.save(proposed)
            credentials = proposed
            hasRestored = true
            connectionState = .connected(keyID: proposed.keyID)
            validationState = .valid
            connectionRevision += 1
            errorMessage = nil
            return true
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func normalizedPEM(_ raw: String) -> String {
        // iOS single-line SecureField paste may collapse the .p8 line breaks.
        // Reconstruct the standard PKCS#8 PEM armor before CryptoKit validates it.
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\n", with: "\n")
        let begin = "-----BEGIN PRIVATE KEY-----"
        let end = "-----END PRIVATE KEY-----"
        guard value.contains(begin), value.contains(end) else { return value }

        let body = value
            .replacingOccurrences(of: begin, with: "")
            .replacingOccurrences(of: end, with: "")
            .filter { !$0.isWhitespace }
        guard !body.isEmpty else { return value }

        var lines: [String] = []
        var offset = body.startIndex
        while offset < body.endIndex {
            let endIndex = body.index(offset, offsetBy: 64, limitedBy: body.endIndex) ?? body.endIndex
            lines.append(String(body[offset..<endIndex]))
            offset = endIndex
        }
        return begin + "\n" + lines.joined(separator: "\n") + "\n" + end
    }

    func disconnect() {
        do {
            try AppStoreConnectCredentialStore.delete()
            credentials = nil
            hasRestored = true
            connectionState = .disconnected
            validationState = .unchecked
            connectionRevision += 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func client() -> AppStoreConnectAPIClient? {
        guard let credentials else { return nil }
        return try? AppStoreConnectAPIClient(credentials: credentials)
    }
}
