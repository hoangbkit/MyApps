import CryptoKit
import Foundation

struct RestoredRegionalPricingDraft: Sendable {
    let proposal: RegionalPricingProposal
    // Saved snapshots are not trusted until Apple is refreshed and re-reviewed.
    let requiresRemoteReview: Bool = true
}

/// Device-local pricing drafts; deliberately outside SwiftData / CloudKit / backups.
/// This is NOT the Pass 4 operation journal and never triggers writes to Apple.
actor PricingDraftStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) throws {
        guard let location = directory ??
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("RegionalPricingDrafts", isDirectory: true) else {
            throw RegionalPricingError.invalidDraft("Application Support is unavailable.")
        }
        try FileManager.default.createDirectory(
            at: location, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var protected = location
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        self.directory = location
        encoder.outputFormatting = [.sortedKeys]
    }

    func save(_ proposal: RegionalPricingProposal) throws {
        guard proposal.schemaVersion == 1 else {
            throw RegionalPricingError.invalidDraft("Unsupported draft schema.")
        }
        // The document includes account scope and opaque product IDs, no credentials,
        // JWTs, key material or unencrypted secrets.
        let payload = try encoder.encode(proposal)
        try payload.write(to: fileURL(account: proposal.accountScope,
                                      product: proposal.product.id),
                          options: [.atomic, .completeFileProtection])
    }

    func load(accountScope: String, productID: String) throws -> RestoredRegionalPricingDraft? {
        let file = fileURL(account: accountScope, product: productID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let proposal = try decoder.decode(RegionalPricingProposal.self, from: data)
        guard proposal.schemaVersion == 1,
              proposal.accountScope == accountScope,
              proposal.product.id == productID else {
            throw RegionalPricingError.mismatchedAccount
        }
        return RestoredRegionalPricingDraft(proposal: proposal)
    }

    func remove(accountScope: String, productID: String) throws {
        let file = fileURL(account: accountScope, product: productID)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func fileURL(account: String, product: String) -> URL {
        // Never accept caller-provided identifiers as file path components.
        let source = Data((account + ":" + product).utf8)
        let hash = SHA256.hash(data: source)
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json", isDirectory: false)
    }
}
