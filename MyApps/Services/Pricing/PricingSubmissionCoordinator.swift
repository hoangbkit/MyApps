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
    private var paused: Set<String> = []

    init(journal: PricingSubmissionJournal = .shared) {
        self.journal = journal
    }

    private func key(account: String, product: String) -> String { account + ":" + product }

    func pausePendingOperations(accountScope: String, productID: String) {
        paused.insert(key(account: accountScope, product: productID))
    }

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
            return LifetimeSchedulePlanner.plan(proposal: proposal, fresh: fresh, today: Self.today())
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
        return LifetimeSchedulePlanner.plan(proposal: regenerated, fresh: fresh, today: Self.today())
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
           [.inFlight, .unknown, .accepted, .pendingVerification].contains(last.state) {
            throw PricingSubmissionFailure.unresolvedPreviousOperation
        }

        let fresh = try await prepare(proposal: proposal, client: client)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let freshPayload = try fresh.request.map { try encoder.encode($0) }
        let reviewedPayload = try reviewedPlan.request.map { try encoder.encode($0) }
        guard fresh.isExecutable, freshPayload != nil,
              freshPayload == reviewedPayload,
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
        } else if original.state == .failed && operation.state == .pendingVerification {
            operation.state = .failed
            operation.error = "Apple rejected the request. No automatic retry was performed."
        }
        operation.updatedAt = Date()
        try await journal.save(operation)
        return .make(from: operation)
    }

    // MARK: - Subscription pricing (independent territory requests)

    func prepareSubscription(proposal: RegionalPricingProposal,
                             acknowledgesDecrease: Bool,
                             client: AppStoreConnectAPIClient) async throws -> SubscriptionWritePlan {
        guard client.pricingAccountScope == proposal.accountScope,
              proposal.product.kind == .subscription else {
            throw PricingSubmissionFailure.invalidPlan("Subscription product/account mismatch.")
        }
        let service = RegionalPricingService(client: client)
        let fresh = try await service.loadSnapshot(product: proposal.product, refresh: true)
        if fresh.semanticFingerprint != proposal.snapshotFingerprint {
            return SubscriptionPricePlanner.plan(
                proposal: proposal, fresh: fresh, today: Self.today(),
                acknowledgesRenewalDecrease: acknowledgesDecrease)
        }
        let validUS = fresh.usPoints.first {
            $0 == proposal.selectedUSPoint
        }
        guard let point = validUS else {
            throw PricingSubmissionFailure.invalidPlan("The selected US price point is no longer valid.")
        }
        let mapping = try RegionalPricingMappingLoader.bundled()
        guard mapping.version == proposal.mappingVersion else {
            throw PricingSubmissionFailure.invalidPlan("The pricing preset changed. Review again.")
        }
        let references = try await service.loadReferenceSet(
            snapshot: fresh, selectedUSPoint: point, mapping: mapping,
            overrides: proposal.overrides)
        let regenerated = try RegionalPricingEngine.generate(
            snapshot: fresh, selectedUSPoint: point, mapping: mapping,
            effectiveDate: proposal.effectiveDate, references: references,
            existingOverrides: proposal.overrides, exclusions: Set(proposal.exclusions),
            subscriberPolicy: proposal.subscriberPolicy,
            acknowledgedWarnings: Set(proposal.acknowledgedWarnings),
            proposalID: proposal.id)
        guard regenerated.fingerprint == proposal.fingerprint else {
            throw PricingSubmissionFailure.invalidPlan(
                "Apple prices, point ladders, or reviewed subscriber settings changed. Regenerate before submitting.")
        }
        return SubscriptionPricePlanner.plan(
            proposal: regenerated, fresh: fresh, today: Self.today(),
            acknowledgesRenewalDecrease: acknowledgesDecrease)
    }

    func previousSubscription(accountScope: String, productID: String)
        async throws -> SubscriptionSubmissionReport? {
        guard let batch = try await journal.loadSubscription(
            accountScope: accountScope, productID: productID) else { return nil }
        return .init(batch: batch)
    }

    func submitSubscriptionConfirmed(
        proposal: RegionalPricingProposal,
        reviewed: SubscriptionWritePlan,
        acknowledgesDecrease: Bool,
        client: AppStoreConnectAPIClient
    ) async throws -> SubscriptionSubmissionReport {
        let scope = key(account: proposal.accountScope, product: proposal.product.id)
        guard active.insert(scope).inserted else { throw PricingSubmissionFailure.alreadyActive }
        defer { active.remove(scope) }
        if let previous = try await journal.loadSubscription(
            accountScope: proposal.accountScope, productID: proposal.product.id),
           !previous.isComplete {
            throw PricingSubmissionFailure.unresolvedPreviousOperation
        }
        let fresh = try await prepareSubscription(
            proposal: proposal, acknowledgesDecrease: acknowledgesDecrease, client: client)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard fresh.isExecutable,
              try encoder.encode(fresh) == encoder.encode(reviewed) else {
            throw PricingSubmissionFailure.invalidPlan("Remote prices or confirmed scope changed. Review again.")
        }
        let now = Date()
        var batch = SubscriptionSubmissionBatch(
            id: UUID(), schemaVersion: 1, plan: fresh,
            entries: fresh.changes.map {
                SubscriptionSubmissionEntry(
                    change: $0, state: .planned, attempts: 0, remoteID: nil,
                    error: nil, preservationVerified: nil, lastUpdated: now)
            },
            stoppedReason: nil, retryNotBefore: nil, createdAt: now, updatedAt: now)
        try await journal.saveSubscription(batch) // No POST before this durable write.
        return try await dispatchSubscription(&batch, client: client)
    }

    /// Read-only recovery. A dropped response never results in a repeat POST.
    func reconcileSubscription(accountScope: String, productID: String,
                               client: AppStoreConnectAPIClient)
        async throws -> SubscriptionSubmissionReport? {
        guard client.pricingAccountScope == accountScope else {
            throw RegionalPricingError.mismatchedAccount
        }
        let scope = key(account: accountScope, product: productID)
        guard active.insert(scope).inserted else { throw PricingSubmissionFailure.alreadyActive }
        defer { active.remove(scope) }
        guard var batch = try await journal.loadSubscription(
            accountScope: accountScope, productID: productID) else { return nil }
        try await reconcileSubscriptionEntries(&batch, client: client)
        return .init(batch: batch)
    }

    /// Explicit resume can dispatch only entries that never left the client
    /// or whose prior POST received a definite failure. Unknown outcomes block.
    /// It never replays accepted, verified, in-flight, or unknown requests.
    func resumeSubscription(accountScope: String, productID: String,
                            client: AppStoreConnectAPIClient) async throws
        -> SubscriptionSubmissionReport {
        guard client.pricingAccountScope == accountScope else {
            throw RegionalPricingError.mismatchedAccount
        }
        let scope = key(account: accountScope, product: productID)
        guard active.insert(scope).inserted else { throw PricingSubmissionFailure.alreadyActive }
        defer { active.remove(scope) }
        guard var batch = try await journal.loadSubscription(
            accountScope: accountScope, productID: productID) else {
            throw PricingSubmissionFailure.invalidPlan("No saved subscription operation exists.")
        }
        if let deadline = batch.retryNotBefore, Date() < deadline {
            throw PricingSubmissionFailure.invalidPlan(
                "Apple rate limit is active until \(deadline.formatted(date: .abbreviated, time: .standard))."
            )
        }
        // Reconcile before any possible retry. No write is allowed when an
        // uncertain operation could already have been accepted by Apple.
        try await reconcileSubscriptionEntries(&batch, client: client)
        if batch.uncertainCount > 0 {
            throw PricingSubmissionFailure.unresolvedPreviousOperation
        }
        return try await dispatchSubscription(&batch, client: client, explicitResume: true)
    }

    private struct SubscriptionAttempt: Sendable {
        let id: String
        let remoteID: String?
        let error: String?
        let state: PricingSubmissionState
        let stop: Bool
        let retryNotBefore: Date?
    }

    private func dispatchSubscription(
        _ batch: inout SubscriptionSubmissionBatch,
        client: AppStoreConnectAPIClient,
        explicitResume: Bool = false
    ) async throws -> SubscriptionSubmissionReport {
        let candidates = batch.entries.indices.filter {
            batch.entries[$0].state == .planned ||
            (explicitResume && batch.entries[$0].state == .failed)
        }
        guard !candidates.isEmpty else { return .init(batch: batch) }
        let scope = key(account: batch.plan.accountScope, product: batch.plan.product.id)
        paused.remove(scope) // A newly explicit Submit/Resume clears previous pause.
        batch.stoppedReason = nil
        batch.retryNotBefore = nil
        batch.updatedAt = Date()
        try await journal.saveSubscription(batch)
        for offset in stride(from: 0, to: candidates.count, by: 3) {
            if Task.isCancelled || paused.contains(scope) {
                batch.stoppedReason = "Task canceled. Unsent entries remain planned."
                break
            }
            let indices = Array(candidates[offset..<min(offset + 3, candidates.count)])
            // A batch may follow earlier accepted prices, so a global snapshot
            // fingerprint is no longer a valid precondition here. Verify the
            // STILL-UNSENT territories and their Apple point identities instead.
            let service = RegionalPricingService(client: client)
            let snapshot = try await service.loadSnapshot(
                product: batch.plan.product, refresh: true)
            var preflightFailure: String?
            let upFront = snapshot.planTerritories.filter { $0.planType == "UPFRONT" }
            if snapshot.planTerritories.count != 1 || upFront.count != 1 ||
               snapshot.issues.contains(where: {
                   ["subscriptionPrices", "planAvailability", "planType"].contains($0.resource)
               }) {
                preflightFailure = "Apple's subscription billing plan or prices are incomplete or changed."
            }
            for index in indices {
                if preflightFailure != nil { break }
                let change = batch.entries[index].change
                if !snapshot.territories.contains(where: {
                    $0.id == change.territoryID && $0.available == true
                }) || upFront.first?.territoryIDs.contains(change.territoryID) != true {
                    preflightFailure = "Territory \(change.territoryID) is no longer confirmed available for UPFRONT billing."
                    break
                }
                let current = snapshot.publicPrice(
                    territoryID: change.territoryID, planType: change.planType,
                    on: batch.plan.effectiveDate)
                if current?.id != change.previous.id ||
                   current?.pricePointID != change.previous.pricePointID ||
                   current?.customerPrice != change.previous.customerPrice {
                    preflightFailure = "A remaining territory price changed: \(change.territoryID)."
                    break
                }
                if snapshot.prices.contains(where: {
                    $0.territoryID == change.territoryID && $0.planType == change.planType &&
                    $0.preserved != true && ($0.startDate ?? "") > Self.today()
                }) {
                    preflightFailure = "A future price is already scheduled in \(change.territoryID)."
                    break
                }
                do {
                    let ladder = try await service.loadPoints(
                        product: batch.plan.product, territoryID: change.territoryID)
                    if !ladder.contains(where: {
                        $0.id == change.point.id &&
                        $0.customerPrice == change.point.customerPrice &&
                        $0.currency == change.point.currency
                    }) {
                        preflightFailure = "Price point withdrawn for \(change.territoryID)."
                        break
                    }
                } catch {
                    preflightFailure = "Unable to revalidate \(change.territoryID): \(error.localizedDescription)"
                    break
                }
            }
            if let preflightFailure {
                batch.stoppedReason = preflightFailure
                batch.updatedAt = Date()
                try await journal.saveSubscription(batch)
                break
            }
            for index in indices {
                batch.entries[index].state = .inFlight
                batch.entries[index].attempts += 1
                batch.entries[index].lastUpdated = Date()
                batch.entries[index].error = nil
            }
            batch.updatedAt = Date()
            try await journal.saveSubscription(batch) // MUST precede every POST.
            let jobs = indices.map { batch.entries[$0].change }
            let responses = await withTaskGroup(
                of: SubscriptionAttempt.self, returning: [SubscriptionAttempt].self
            ) { group in
                for change in jobs {
                    group.addTask {
                        do {
                            let remoteID = try await client.createSubscriptionPrice(change.request)
                            return SubscriptionAttempt(id: change.id, remoteID: remoteID,
                                                       error: nil, state: .accepted,
                                                       stop: false, retryNotBefore: nil)
                        } catch {
                            let rejected = Self.definitivelyRejected(error)
                            let stop: Bool
                            var retryDeadline: Date?
                            if let api = error as? AppStoreConnectAPIError {
                                switch api {
                                case .httpStatus(let status):
                                    stop = [401, 403, 429].contains(status)
                                    if status == 429 { retryDeadline = Date().addingTimeInterval(60) }
                                case .appleResponse(let status, _, _, _, _, let retryAfter):
                                    stop = [401, 403, 429].contains(status)
                                    if status == 429 {
                                        let seconds = retryAfter.flatMap(Double.init) ?? 60
                                        retryDeadline = Date().addingTimeInterval(
                                            min(max(seconds, 1), 3600))
                                    }
                                default: stop = false
                                }
                            } else { stop = false }
                            return SubscriptionAttempt(id: change.id, remoteID: nil,
                                error: error.localizedDescription,
                                state: rejected ? .failed : .unknown, stop: stop,
                                retryNotBefore: retryDeadline)
                        }
                    }
                }
                var items: [SubscriptionAttempt] = []
                for await response in group { items.append(response) }
                return items
            }
            let byID = Dictionary(uniqueKeysWithValues: responses.map { ($0.id, $0) })
            for index in indices {
                let id = batch.entries[index].id
                guard let response = byID[id] else {
                    batch.entries[index].state = .unknown
                    batch.entries[index].error = "Dispatched request had no recorded response."
                    continue
                }
                batch.entries[index].state = response.state
                batch.entries[index].remoteID = response.remoteID
                batch.entries[index].error = response.error
                batch.entries[index].lastUpdated = Date()
            }
            batch.updatedAt = Date()
            if responses.contains(where: \.stop) {
                batch.stoppedReason = "Apple returned an authentication/permission/rate-limit error. Remaining requests were not sent. Review the error before resuming."
            }
            batch.retryNotBefore = responses.compactMap(\.retryNotBefore).max()
            try await journal.saveSubscription(batch)
            try await reconcileSubscriptionEntries(&batch, client: client, attempts: 1)
            if batch.stoppedReason != nil ||
               batch.entries.contains(where: { $0.state == .unknown || $0.state == .inFlight }) {
                break
            }
        }
        return .init(batch: batch)
    }

    private func reconcileSubscriptionEntries(
        _ batch: inout SubscriptionSubmissionBatch,
        client: AppStoreConnectAPIClient,
        attempts: Int = 2
    ) async throws {
        guard batch.plan.accountScope == client.pricingAccountScope else {
            throw RegionalPricingError.mismatchedAccount
        }
        let indices = batch.entries.indices.filter {
            [.inFlight, .unknown, .accepted, .pendingVerification].contains(batch.entries[$0].state)
        }
        guard !indices.isEmpty else { return }
        for attempt in 0..<attempts {
            if Task.isCancelled { break }
            let snapshot: PricingSnapshot
            do {
                snapshot = try await RegionalPricingService(client: client)
                    .loadSnapshot(product: batch.plan.product, refresh: true)
            } catch {
                batch.stoppedReason = "Read-only verification failed: \(error.localizedDescription)"
                break
            }
            for index in indices {
                if [.verifiedLive, .verifiedScheduled].contains(batch.entries[index].state) { continue }
                let entry = batch.entries[index]
                let matches = snapshot.prices.contains {
                    $0.territoryID == entry.change.territoryID &&
                    $0.planType == entry.change.planType &&
                    $0.preserved != true &&
                    $0.pricePointID == entry.change.point.id &&
                    (($0.startDate ?? "") == entry.change.effectiveDate ||
                     ($0.startDate == nil && entry.change.effectiveDate <= Self.today()))
                }
                if matches {
                    batch.entries[index].state =
                        entry.change.effectiveDate > Self.today() ? .verifiedScheduled : .verifiedLive
                    batch.entries[index].preservationVerified = nil
                    batch.entries[index].error = entry.change.increase
                        ? "Public price verified. Existing-subscriber preservation cannot be independently confirmed from this API."
                        : nil
                } else if entry.state == .accepted || entry.state == .pendingVerification {
                    batch.entries[index].state = .pendingVerification
                    batch.entries[index].error = "Apple accepted the price change; public price is not yet verifiable."
                } else {
                    batch.entries[index].state = .unknown
                    batch.entries[index].error = "Outcome unknown; no automatic retry. Reconcile before any resume."
                }
                batch.entries[index].lastUpdated = Date()
            }
            batch.updatedAt = Date()
            try await journal.saveSubscription(batch)
            if indices.allSatisfy({ [.verifiedLive, .verifiedScheduled].contains(batch.entries[$0].state) }) {
                break
            }
            if attempt + 1 < attempts {
                try? await Task.sleep(for: .seconds(attempt == 0 ? 2 : 4))
            }
        }
    }

    private static func today() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: Date())
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
