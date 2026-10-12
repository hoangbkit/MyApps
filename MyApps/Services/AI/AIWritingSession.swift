import Combine
import Foundation
import Security

struct AIWritingProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var identity: String
    var style: String
    var audience: String
    var topics: String
    var instructions: String
    var protectedTerms: String

    static let indieBuilder = AIWritingProfile(
        id: UUID(uuidString: "B209C733-BA8C-40F9-9280-765153C7E563")!,
        name: "Indie Builder",
        identity: "Independent software developer and product builder creating native iOS/macOS apps, developer tools, and AI-powered products. Works with Swift and SwiftUI; builds Spokio and BYOKchat.",
        style: "Direct, concise, practical and opinionated but thoughtful. Natural first-person voice, occasionally witty or sarcastic, never aggressive.",
        audience: "Indie developers, technical founders, Apple developers, and people interested in shipping software.",
        topics: "iOS, macOS, Swift, SwiftUI, AI, developer tools, independent software businesses, product building.",
        instructions: "Use short paragraphs and precise words. Avoid corporate language, hype, filler and generic AI phrases. Preserve meaning and technical accuracy; never invent personal experiences, results, achievements or opinions. Write in the source language unless translation is requested.",
        protectedTerms: "iOS, macOS, SwiftUI, GitHub, Xcode Cloud, App Store Connect, DeepSeek, OpenAI, Spokio, BYOKchat, API, APIs"
    )

    var systemContext: String {
        """
        Writer identity: \(identity)
        Writing style: \(style)
        Intended audience: \(audience)
        Relevant subjects: \(topics)
        Writing preferences: \(instructions)
        Protected terminology (retain exact case/spelling): \(protectedTerms)
        """
    }
}

enum DeepSeekModel: String, CaseIterable, Identifiable, Sendable {
    case flash = "deepseek-flash"
    case pro = "deepseek-v4-pro"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .flash: "DeepSeek Flash"
        case .pro: "DeepSeek V4 Pro"
        }
    }
}

/// Store only the DeepSeek API key in Keychain; never in user defaults or backups.
enum DeepSeekKeychain {
    private static let service = "com.hoangbkit.myapps.deepseek"
    private static let account = "api-key"

    static func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DeepSeekKeychainError.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { throw DeepSeekKeychainError.invalidStoredKey }
        return key
    }

    static func save(_ token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw DeepSeekKeychainError.keychain(status) }
        var item = query
        for (key, value) in attributes { item[key] = value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw DeepSeekKeychainError.keychain(addStatus) }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DeepSeekKeychainError.keychain(status)
        }
    }
}

enum DeepSeekKeychainError: LocalizedError {
    case keychain(OSStatus)
    case invalidStoredKey
    var errorDescription: String? {
        switch self {
        case let .keychain(code): "Keychain operation failed (\(code))."
        case .invalidStoredKey: "The stored DeepSeek key could not be read."
        }
    }
}

struct AIWritingPreferences: Codable, Sendable {
    var profiles: [AIWritingProfile]
    var defaultProfileID: UUID
    var modelRawValue: String

    static var starter: Self {
        Self(profiles: [.indieBuilder], defaultProfileID: .indieBuilder.id, modelRawValue: DeepSeekModel.flash.rawValue)
    }
}

@MainActor
final class AIWritingSession: ObservableObject {
    static let storageKey = "myapps.ai.writing.preferences.v1"

    @Published private(set) var preferences: AIWritingPreferences
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published var errorMessage: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let value = try? JSONDecoder().decode(AIWritingPreferences.self, from: data),
           !value.profiles.isEmpty {
            preferences = value
        } else {
            preferences = .starter
        }
        isConnected = (try? DeepSeekKeychain.load()) != nil
    }

    var profiles: [AIWritingProfile] { preferences.profiles }
    var defaultProfileID: UUID { preferences.defaultProfileID }
    var model: DeepSeekModel {
        DeepSeekModel(rawValue: preferences.modelRawValue) ?? .flash
    }

    var defaultProfile: AIWritingProfile {
        profiles.first(where: { $0.id == defaultProfileID }) ?? profiles[0]
    }

    func setModel(_ value: DeepSeekModel) {
        preferences.modelRawValue = value.rawValue
        persist()
    }

    func makeProfile() -> AIWritingProfile {
        AIWritingProfile(
            id: UUID(), name: "New Profile", identity: "", style: "",
            audience: "", topics: "", instructions: "", protectedTerms: ""
        )
    }

    func saveProfile(_ profile: AIWritingProfile) {
        if let index = preferences.profiles.firstIndex(where: { $0.id == profile.id }) {
            preferences.profiles[index] = profile
        } else {
            preferences.profiles.append(profile)
        }
        persist()
    }

    func duplicate(_ profile: AIWritingProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name += " Copy"
        preferences.profiles.append(copy)
        persist()
    }

    func setDefault(_ id: UUID) {
        guard preferences.profiles.contains(where: { $0.id == id }) else { return }
        preferences.defaultProfileID = id
        persist()
    }

    func delete(_ id: UUID) {
        guard preferences.profiles.count > 1 else { return }
        preferences.profiles.removeAll { $0.id == id }
        if preferences.defaultProfileID == id {
            preferences.defaultProfileID = preferences.profiles[0].id
        }
        persist()
    }

    func restoreProfiles(_ value: AIWritingPreferences) {
        guard !value.profiles.isEmpty,
              Set(value.profiles.map(\.id)).count == value.profiles.count else { return }
        preferences = value
        if !profiles.contains(where: { $0.id == defaultProfileID }) {
            preferences.defaultProfileID = profiles[0].id
        }
        persist()
    }

    func connect(_ rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Enter a DeepSeek API key."
            return false
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            // Test the key with the lightweight model-list endpoint, without
            // sending any note content or incurring a rewrite request.
            try await DeepSeekClient(apiKey: key, model: model).validate()
            try Task.checkCancellation()
            try DeepSeekKeychain.save(key)
            isConnected = true
            errorMessage = nil
            return true
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
            return false
        }
    }

    func disconnect() {
        do {
            try DeepSeekKeychain.delete()
            isConnected = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func client() throws -> DeepSeekClient {
        guard let key = try DeepSeekKeychain.load() else {
            throw DeepSeekClientError.missingAPIKey
        }
        return DeepSeekClient(apiKey: key, model: model)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
