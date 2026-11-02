import Foundation

struct SubscriptionSubmissionEntry: Codable, Sendable, Identifiable {
    var id: String { change.id }
    let change: SubscriptionPriceChange
    var state: PricingSubmissionState
    var attempts: Int
    var remoteID: String?
    var error: String?
    var preservationVerified: Bool?
    var lastUpdated: Date
}

struct SubscriptionSubmissionBatch: Codable, Sendable, Identifiable {
    let id: UUID
    let schemaVersion: Int
    let plan: SubscriptionWritePlan
    var entries: [SubscriptionSubmissionEntry]
    var stoppedReason: String?
    var retryNotBefore: Date?
    let createdAt: Date
    var updatedAt: Date
    // Missing in older journals means the batch is still open.
    var closedAt: Date? = nil
    var ascResolution: PricingASCResolution? = nil

    var pendingCount: Int {
        entries.filter { $0.state == .planned }.count
    }
    var uncertainCount: Int {
        entries.filter { $0.state.hasUncertainOutcome }.count
    }

    var isComplete: Bool {
        entries.allSatisfy { $0.state == .verifiedLive || $0.state == .verifiedScheduled }
    }

    var isClosed: Bool { isComplete || closedAt != nil }

    var canClose: Bool { !isClosed && uncertainCount == 0 }
    var canResolveInASC: Bool { !isClosed && uncertainCount > 0 }

    func outcome(for territory: String) -> SubscriptionSubmissionEntry? {
        entries.first { $0.change.territoryID == territory }
    }
}

struct SubscriptionSubmissionReport: Sendable {
    let batch: SubscriptionSubmissionBatch

    var results: [PricingTerritoryOutcome] {
        let completed = batch.entries.map { entry in
            PricingTerritoryOutcome(id: entry.change.id, state: entry.state,
                                    detail: entry.error ?? entry.state.rawValue)
        }
        let skipped = batch.plan.excluded.map {
            PricingTerritoryOutcome(id: $0 + ":UPFRONT", state: .skipped,
                                    detail: "Explicitly excluded.")
        }
        return (completed + skipped).sorted { $0.id < $1.id }
    }
    func count(_ state: PricingSubmissionState) -> Int {
        results.filter { $0.state == state }.count
    }
    var verifiedCount: Int { count(.verifiedLive) + count(.verifiedScheduled) }
    var acceptedCount: Int { count(.accepted) }
    var pendingCount: Int { count(.planned) + count(.pendingVerification) }
    var unknownCount: Int { count(.unknown) + count(.inFlight) }
    var failedCount: Int { count(.failed) }
    var skippedCount: Int { count(.skipped) }
    var requiresReconciliation: Bool { !batch.isClosed && batch.uncertainCount > 0 }
    var hasUnsent: Bool { batch.pendingCount > 0 }
}


