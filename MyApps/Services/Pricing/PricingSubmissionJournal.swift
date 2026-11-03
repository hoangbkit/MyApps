import CryptoKit
import Foundation

enum PricingSubmissionState: String, Codable, Sendable {
    case planned, inFlight, accepted, verifiedLive, verifiedScheduled
    case pendingVerification, failed, unknown, skipped

    var hasUncertainOutcome: Bool {
        [.unknown, .inFlight, .accepted, .pendingVerification].contains(self)
    }

    var isTerminal: Bool {
        switch self {
        case .verifiedLive, .verifiedScheduled, .failed, .skipped: true
        default: false
        }
    }
}

/// User-attested resolution in ASC, not proof that Apple canceled or reverted
/// anything. Original request outcomes remain intact in the closed report.
struct PricingASCResolution: Codable, Sendable {
    let confirmedAt: Date
    let refreshedSnapshotFingerprint: String
}

struct PricingSubmissionOperation: Codable, Sendable, Identifiable {
    let id: UUID
    let groupID: String
    let accountScope: String
    let appID: String
    let productID: String
    let proposalID: UUID
    let proposalFingerprint: String
    let baselineFingerprint: String
    let expectedBaseTerritory: String
    let effectiveDate: String
    let territories: [String]
    let plan: LifetimeSchedulePlan
    var state: PricingSubmissionState
    var attempts: Int
    var remoteID: String?
    var error: String?
    var createdAt: Date
    var updatedAt: Date
    // Optional fields preserve compatibility with existing operation journals.
    var closedAt: Date? = nil
    var ascResolution: PricingASCResolution? = nil

    var isClosed: Bool { closedAt != nil }
    var canResolveInASC: Bool { !isClosed && state.hasUncertainOutcome }

    var canReconcile: Bool {
        !isClosed && [.unknown, .inFlight, .accepted, .pendingVerification, .failed].contains(state)
    }
}

struct PricingTerritoryOutcome: Codable, Sendable, Identifiable {
    let id: String
    let state: PricingSubmissionState
    let detail: String
}

struct PricingSubmissionReport: Codable, Sendable {
    let operation: PricingSubmissionOperation
    let territoryResults: [PricingTerritoryOutcome]

    var accepted: Int { territoryResults.filter { $0.state == .accepted }.count }
    var verified: Int { territoryResults.filter {
        $0.state == .verifiedLive || $0.state == .verifiedScheduled
    }.count }
    var pendingVerification: Int { territoryResults.filter {
        $0.state == .pendingVerification
    }.count }
    var failed: Int { territoryResults.filter { $0.state == .failed }.count }
    var unknown: Int { territoryResults.filter { $0.state == .unknown }.count }
    var skipped: Int { territoryResults.filter { $0.state == .skipped }.count }

    static func make(from operation: PricingSubmissionOperation) -> Self {
        let affected = Set(operation.territories)
        let excluded = Set(operation.plan.excludedTerritories)
        var results = operation.territories.map { territory in
            PricingTerritoryOutcome(id: territory, state: operation.state,
                detail: operation.error ?? operation.state.rawValue)
        }
        results += excluded.subtracting(affected).sorted().map {
            PricingTerritoryOutcome(id: $0, state: .skipped,
                detail: "Explicitly excluded from reviewed submission.")
        }
        return .init(operation: operation, territoryResults: results)
    }
}

actor PricingSubmissionJournal {
    static let shared = PricingSubmissionJournal()

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ??
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PricingSubmissionJournal", isDirectory: true)
    }

    func load(accountScope: String, productID: String) throws -> PricingSubmissionOperation? {
        let file = location(accountScope: accountScope, productID: productID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let stored = try JSONDecoder().decode(PricingSubmissionOperation.self,
                                              from: Data(contentsOf: file))
        guard stored.accountScope == accountScope && stored.productID == productID else {
            throw RegionalPricingError.mismatchedAccount
        }
        return stored
    }

    func save(_ operation: PricingSubmissionOperation) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var url = directory
        var metadata = URLResourceValues()
        metadata.isExcludedFromBackup = true
        try url.setResourceValues(metadata)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(operation)
        if let previous = try load(accountScope: operation.accountScope,
                                   productID: operation.productID), previous.id != operation.id {
            guard previous.isClosed || !previous.state.hasUncertainOutcome else {
                throw PricingSubmissionFailure.unresolvedPreviousOperation
            }
            try encoder.encode(previous).write(
                to: directory.appendingPathComponent("closed-lifetime-" + previous.id.uuidString + ".json"),
                options: [.atomic, .completeFileProtection])
        }
        if operation.isClosed {
            try data.write(
                to: directory.appendingPathComponent("closed-lifetime-" + operation.id.uuidString + ".json"),
                options: [.atomic, .completeFileProtection])
        }
        try data.write(to: location(accountScope: operation.accountScope,
                                    productID: operation.productID),
                      options: [.atomic, .completeFileProtection])
    }

    /// Same protected Application Support journal as lifetime IAP, with a
    /// separate file for per-territory subscription batches.
    func loadSubscription(accountScope: String, productID: String) throws -> SubscriptionSubmissionBatch? {
        let file = subscriptionLocation(accountScope: accountScope, productID: productID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let batch = try JSONDecoder().decode(SubscriptionSubmissionBatch.self,
                                             from: Data(contentsOf: file))
        guard batch.schemaVersion == 1,
              batch.plan.accountScope == accountScope,
              batch.plan.product.id == productID,
              batch.entries.allSatisfy({
                  $0.change.request.data.relationships.subscription.data.id == productID
              }) else { throw RegionalPricingError.mismatchedAccount }
        return batch
    }

    func saveSubscription(_ batch: SubscriptionSubmissionBatch) throws {
        guard batch.schemaVersion == 1 else {
            throw RegionalPricingError.invalidDraft("Unsupported subscription journal version.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var protected = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(batch)
        // Keep the final report when a new proposal replaces closed work.
        if let previous = try loadSubscription(accountScope: batch.plan.accountScope,
                                               productID: batch.plan.product.id),
           previous.id != batch.id {
            guard previous.isClosed else {
                throw PricingSubmissionFailure.unresolvedPreviousOperation
            }
            try encoder.encode(previous).write(
                to: directory.appendingPathComponent("closed-subscription-" + previous.id.uuidString + ".json"),
                options: [.atomic, .completeFileProtection])
        }
        if batch.closedAt != nil {
            try data.write(
                to: directory.appendingPathComponent("closed-subscription-" + batch.id.uuidString + ".json"),
                options: [.atomic, .completeFileProtection])
        }
        try data.write(to: subscriptionLocation(accountScope: batch.plan.accountScope,
                                                productID: batch.plan.product.id),
                      options: [.atomic, .completeFileProtection])
    }

    private func subscriptionLocation(accountScope: String, productID: String) -> URL {
        let key = Data(("subscription:" + accountScope + ":" + productID).utf8)
        let hash = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json", isDirectory: false)
    }

    private func location(accountScope: String, productID: String) -> URL {
        let identifier = Data((accountScope + ":" + productID).utf8)
        let hash = SHA256.hash(data: identifier)
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json", isDirectory: false)
    }
}


