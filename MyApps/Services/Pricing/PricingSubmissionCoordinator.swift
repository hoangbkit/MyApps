import Foundation

enum PricingSubmissionFailure: LocalizedError, Sendable {
    case alreadyActive
    case unresolvedPreviousOperation
    case invalidPlan(String)

    var errorDescription: String? {
        switch self {
        case .alreadyActive: "A price submission for this product is already running."
        case .unresolvedPreviousOperation:
            "A previous price request may still be active. Reconcile its outcome before submitting again."
        case .invalidPlan(let reason): reason
        }
    }
}

/// One process-wide mutation owner. State is persisted before calling the
/// non-idempotent schedule endpoint. No background work is promised after exit.
actor PricingSubmissionCoordinator {
    static let shared = PricingSubmissionCoordinator()

    private let journal: PricingSubmissionJournal
    private var active: Set<String> = []

    init(journal: PricingSubmissionJournal = .shared) {
        self.journal = journal
    }

    private func key(account: String, product: String) -> String { account + ":" + product }

    /// Preflight always performs uncached Apple reads and re-runs the pure
    /// proposal, checking every selected point. It does not write remotely.
    func prepare(proposal: RegionalPricingProposal,
                 client: AppStoreConnectAPIClient) async throws -> LifetimeSchedulePlan {
        guard client.pricingAccountScope == proposal.accountScope,
              proposal.product.kind == .lifetime else {
            throw PricingSubmissionFailure.invalidPlan("Account or product type does not match this proposal.")
        }
        let service = RegionalPricingService(client: client)
        let fresh = try await service.loadSnapshot(product: proposal.product, refresh: true)
        guard fresh.semanticFingerprint == proposal.snapshotFingerprint else {
            return LifetimeSchedulePlanner.plan(proposal: proposal, fresh: fresh)
        }
        let point = fresh.usPoints.first { $0.id == proposal.selectedUSPoint.id &&
            $0.customerPrice == proposal.selectedUSPoint.customerPrice &&
            $0.currency == proposal.selectedUSPoint.currency }
        guard let point else {
            throw PricingSubmissionFailure.invalidPlan("US price point is no longer available. Regenerate.")
        }
        let mapping = try RegionalPricingMappingLoader.bundled()
        guard mapping.version == proposal.mappingVersion else {
            throw PricingSubmissionFailure.invalidPlan("Country mapping changed. Review and regenerate.")
        }
        let references = try await service.loadReferenceSet(
            snapshot: fresh, selectedUSPoint: point, mapping: mapping,
            overrides: proposal.overrides)
        let regenerated = try RegionalPricingEngine.generate(
            snapshot: fresh, selectedUSPoint: point, mapping: mapping,
            effectiveDate: proposal.effectiveDate, references: references,
            existingOverrides: proposal.overrides,
            exclusions: Set(proposal.exclusions),
            subscriberPolicy: proposal.subscriberPolicy,
            acknowledgedWarnings: Set(proposal.acknowledgedWarnings),
            proposalID: proposal.id)
        guard regenerated.fingerprint == proposal.fingerprint else {
            throw PricingSubmissionFailure.invalidPlan(
                "The selected points, maintenance mode or Apple equalizations changed. Review and regenerate.")
        }
        return LifetimeSchedulePlanner.plan(proposal: regenerated, fresh: fresh)
    }

    func previous(accountScope: String, productID: String) async throws -> PricingSubmissionReport? {
        guard let operation = try await journal.load(
            accountScope: accountScope, productID: productID) else { return nil }
        return .make(from: operation)
    }

    /// Called only by the final confirmed action; double taps and another
    /// screen are serialized by this actor before any network requests.
    func submitConfirmed(proposal: RegionalPricingProposal, reviewedPlan: LifetimeSchedulePlan,
                         client: AppStoreConnectAPIClient) async throws -> PricingSubmissionReport {
        let scope = key(account: proposal.accountScope, product: proposal.product.id)
        guard active.insert(scope).inserted else { throw PricingSubmissionFailure.alreadyActive }
        defer { active.remove(scope) }
        if let last = try await journal.load(
            accountScope: proposal.accountScope, productID: proposal.product.id),
           [.inFlight, .unknown, .accepted, .pendingVerification, .planned].contains(last.state) {
            throw PricingSubmissionFailure.unresolvedPreviousOperation
        }

        let fresh = try await prepare(proposal: proposal, client: client)
        guard fresh.isExecutable, let _ = fresh.request,
              fresh.proposalFingerprint == reviewedPlan.proposalFingerprint,
              fresh.baselineFingerprint == reviewedPlan.baselineFingerprint,
              fresh.affectedTerritories == reviewedPlan.affectedTerritories,
              fresh.entries.map(\.pointID) == reviewedPlan.entries.map(\.pointID),
              fresh.entries.map(\.territoryID) == reviewedPlan.entries.map(\.territoryID),
              fresh.entries.map(\.startDate) == reviewedPlan.entries.map(\.startDate) else {
            throw PricingSubmissionFailure.invalidPlan(
                "Submission preflight no longer matches the confirmed schedule. Return to Review.")
        }

        var operation = PricingSubmissionOperation(
            id: UUID(), groupID: "iap-schedule-" + proposal.id.uuidString,
            accountScope: proposal.accountScope, appID: proposal.product.appID,
            productID: proposal.product.id, proposalID: proposal.id,
            proposalFingerprint: proposal.fingerprint,
            baselineFingerprint: fresh.baselineFingerprint,
            expectedBaseTerritory: fresh.baseTerritoryID,
            effectiveDate: fresh.effectiveDate,
            territories: fresh.affectedTerritories,
            plan: fresh, state: .planned, attempts: 0,
            remoteID: nil, error: nil, createdAt: Date(), updatedAt: Date()
        )
        try await journal.save(operation)
        guard !Task.isCancelled else { return .make(from: operation) }
        operation.state = .inFlight
        operation.attempts = 1
        operation.updatedAt = Date()
        try await journal.save(operation) // Required BEFORE network dispatch.

        do {
            guard let request = fresh.request else {
                throw PricingSubmissionFailure.invalidPlan("Missing frozen schedule body.")
            }
            let remoteID = try await client.createLifetimeSchedule(request)
            operation.remoteID = remoteID
            operation.state = .accepted
            operation.updatedAt = Date()
            try await journal.save(operation)
        } catch {
            // An ambiguous timeout, cancellation, crash, or unreadable response
            // may represent a committed Apple operation. Never retry it here.
            operation.state = Self.definitivelyRejected(error) ? .failed : .unknown
            operation.error = error.localizedDescription
            operation.updatedAt = Date()
            try await journal.save(operation)
            return .make(from: operation)
        }
        return try await verifyAccepted(operation: operation, client: client)
    }

    /// Safe read-only reconciliation. NEVER dispatches a POST, including after
    /// app restart or when an unknown outcome has no matching remote price yet.
    func reconcile(accountScope: String, productID: String,
                   client: AppStoreConnectAPIClient) async throws -> PricingSubmissionReport? {
        guard client.pricingAccountScope == accountScope else {
            throw RegionalPricingError.mismatchedAccount
        }
        let scope = key(account: accountScope, product: productID)
        guard active.insert(scope).inserted else { throw PricingSubmissionFailure.alreadyActive }
        defer { active.remove(scope) }

        guard let operation = try await journal.load(accountScope: accountScope,
                                                     productID: productID) else { return nil }
        guard operation.canReconcile else { return .make(from: operation) }
        return try await verifyAccepted(operation: operation, client: client, attemptCount: 1)
    }

    private func verifyAccepted(operation original: PricingSubmissionOperation,
                                client: AppStoreConnectAPIClient,
                                attemptCount: Int = 3) async throws -> PricingSubmissionReport {
        var operation = original
        let product = operation.plan.selectedUSPoint.productID
        guard product == operation.productID else {
            operation.state = .unknown
            operation.error = "Stored operation references a different product."
            try await journal.save(operation)
            return .make(from: operation)
        }
        for attempt in 0..<attemptCount {
            if Task.isCancelled { break }
            do {
                let service = RegionalPricingService(client: client)
                let snapshot = try await service.loadSnapshot(
                    product: operation.planProduct, refresh: true)
                guard snapshot.baseTerritoryID == operation.expectedBaseTerritory else {
                    operation.state = .unknown
                    operation.error = "Apple's base territory changed after dispatch."
                    break
                }
                let intended = operation.plan.entries.filter { !$0.preserved }
                let expectedAutomatic = operation.plan.expectedAutomaticPoints
                let intendedTerritories = Set(intended.map(\.territoryID))
                    .union(expectedAutomatic.keys)
                let manualVerified = intended.allSatisfy { desired in
                    snapshot.prices.contains(where: {
                        $0.territoryID == desired.territoryID &&
                        $0.origin == .manualIAP &&
                        $0.pricePointID == desired.pointID &&
                        (($0.startDate ?? "") == (desired.startDate ?? "") ||
                         (desired.startDate == nil &&
                          $0.startDate.map { $0 <= operation.effectiveDate } == true))
                    })
                }
                let automaticVerified = expectedAutomatic.allSatisfy { territory, pointID in
                    snapshot.publicPrice(territoryID: territory,
                        on: operation.effectiveDate)?.pricePointID == pointID
                }
                if intendedTerritories == Set(operation.plan.affectedTerritories) &&
                   manualVerified && automaticVerified {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    operation.state = operation.effectiveDate > formatter.string(from: Date())
                        ? .verifiedScheduled : .verifiedLive
                    operation.error = nil
                    break
                }
                operation.state = .pendingVerification
                operation.error = "Apple accepted the schedule, but the desired price state is not yet readable. No retry POST was sent."
            } catch {
                operation.state = .pendingVerification
                operation.error = "Verification read failed: " + error.localizedDescription
            }
            if attempt + 1 < attemptCount {
                try? await Task.sleep(for: .seconds(attempt == 0 ? 2 : 4))
            }
        }
        if original.state == .unknown || original.state == .inFlight {
            // A matching remote state can confirm success; an inconclusive read
            // must never relabel a lost POST response as definitely accepted.
            if operation.state == .pendingVerification {
                operation.state = .unknown
                operation.error = "Prior request outcome remains unknown. Reconcile again before any new submission."
            }
        }
        operation.updatedAt = Date()
        try await journal.save(operation)
        return .make(from: operation)
    }

    private static func definitivelyRejected(_ error: Error) -> Bool {
        guard let api = error as? AppStoreConnectAPIError else { return false }
        switch api {
        case let .httpStatus(code): return (400...499).contains(code) && code != 408
        case let .appleResponse(status, _, _, _, _, _):
            return (400...499).contains(status) && status != 408
        default: return false
        }
    }
}

private extension PricingSubmissionOperation {
    var planProduct: PricingProduct {
        // Frozen full product model is stored with the operation to ensure
        // a stable resource identity after a restart.
        plan.product
    }
}
