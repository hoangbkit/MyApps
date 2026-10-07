import Foundation
import Security

enum GitHubCredentialStore {
    private static let service = "com.hoangbkit.myapps.github"
    private static let account = "access-token"

    static func loadToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let token = String(data: data, encoding: .utf8),
                !token.isEmpty
            else {
                throw GitHubCredentialError.invalidStoredCredential
            }
            return token

        case errSecItemNotFound:
            return nil

        default:
            throw GitHubCredentialError.keychain(status)
        }
    }

    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw GitHubCredentialError.keychain(updateStatus)
        }

        var add = lookup
        attributes.forEach { add[$0.key] = $0.value }

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GitHubCredentialError.keychain(addStatus)
        }
    }

    static func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubCredentialError.keychain(status)
        }
    }
}

enum GitHubCredentialError: LocalizedError {
    case invalidStoredCredential
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredCredential:
            return "The stored GitHub credential could not be read."
        case let .keychain(status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error: \(message)"
            }
            return "Keychain error \(status)."
        }
    }
}
