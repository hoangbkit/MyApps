import Foundation
import Security

struct AppStoreConnectCredentials: Codable, Sendable {
    let issuerID: String
    let keyID: String
    let privateKeyPEM: String
}

/// Secrets stay in this device's Keychain, not SwiftData, UserDefaults, analytics,
/// debug logs, or the app's export/restore backup.
enum AppStoreConnectCredentialStore {
    private static let service = "com.hoangbkit.myapps.appstoreconnect"
    private static let account = "api-key"

    static func load() throws -> AppStoreConnectCredentials? {
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
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data = result as? Data,
                  let credentials = try? JSONDecoder().decode(AppStoreConnectCredentials.self, from: data)
            else { throw AppStoreConnectCredentialError.invalidStoredCredential }
            return credentials
        default:
            throw AppStoreConnectCredentialError.keychain(status)
        }
    }

    static func save(_ credentials: AppStoreConnectCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw AppStoreConnectCredentialError.keychain(status)
        }
        var item = query
        for (key, value) in attributes { item[key] = value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppStoreConnectCredentialError.keychain(addStatus)
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppStoreConnectCredentialError.keychain(status)
        }
    }
}

enum AppStoreConnectCredentialError: LocalizedError {
    case invalidStoredCredential
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredCredential:
            "The stored App Store Connect credentials could not be read."
        case let .keychain(status):
            "Unable to access the device Keychain (status \(status))."
        }
    }
}
