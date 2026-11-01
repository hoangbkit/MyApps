import Foundation
import Observation

@MainActor
@Observable
final class RegionalPricingViewModel {
    enum Phase: Equatable {
        case idle, loading, ready, generating, reviewing
    }

    let product: PricingProduct
    private let service: RegionalPricingService
    private let drafts: PricingDraftStore?
    private(set) var phase: Phase = .idle
    private(set) var snapshot: PricingSnapshot?
    private(set) var mapping: RegionalPricingMapping?
    private(set) var referenceSet: RegionalPricingReferenceSet?
    private(set) var proposal: RegionalPricingProposal?
    private(set) var errorMessage: String?
    private(set) var isStale = false
    private(set) var needsRegeneration = false
    private(set) var restoredDraft = false

    var selectedUSPointID: String = ""
    var effectiveDate: Date = Date()

    private var requestID = UUID()
    private var expectedAccountScope: String
    private var activeConnectionRevision: Int?

    init(product: PricingProduct, client: AppStoreConnectAPIClient) {
        self.product = product
        self.service = RegionalPricingService(client: client)
        self.expectedAccountScope = client.pricingAccountScope
        self.drafts = try? PricingDraftStore()
    }

    var isWorking: Bool { phase == .loading || phase == .generating }
    var selectedUSPoint: PricingPoint? {
        snapshot?.usPoints.first(where: { $0.id == selectedUSPointID })
    }

    var effectiveDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: effectiveDate)
    }

    var isReviewCurrent: Bool {
        proposal != nil && !isStale && !needsRegeneration && !restoredDraft
    }

    func begin(connectionRevision: Int, currentClient: AppStoreConnectAPIClient?) async {
        guard let currentClient,
              currentClient.pricingAccountScope == expectedAccountScope else {
            invalidateForAccountChange()
            errorMessage = "App Store Connect account changed. Reopen pricing from the current connection."
            return
        }
        if let revision = activeConnectionRevision, revision == connectionRevision,
           phase != .idle { return }
        activeConnectionRevision = connectionRevision
        await load(initial: true, refresh: true)
    }

    func invalidateForAccountChange() {
        requestID = UUID()
        phase = .idle
        snapshot = nil
        mapping = nil
        referenceSet = nil
        proposal = nil
        selectedUSPointID = ""
        isStale = true
        needsRegeneration = true
        restoredDraft = false
        activeConnectionRevision = nil
    }

    func load(initial: Bool = false, refresh: Bool = false) async {
        guard !isWorking else { return }
        let token = UUID()
        requestID = token
        phase = .loading
        errorMessage = nil
        do {
            let bundleMapping = try RegionalPricingMappingLoader.bundled()
            let fresh = try await service.loadSnapshot(product: product, refresh: refresh)
            guard requestID == token, !Task.isCancelled else { return }
            let unmatched = try bundleMapping.validate(
                knownTerritories: fresh.territories.map(\.id))
            mapping = bundleMapping
            snapshot = fresh
            if !unmatched.isEmpty {
                // Unmatched codes stay at Apple reference × 1.00 and display warnings.
            }
            if initial, proposal == nil, let draft = try await drafts?.load(
                accountScope: expectedAccountScope, productID: product.id
            ) {
                guard requestID == token else { return }
                proposal = draft.proposal
                selectedUSPointID = draft.proposal.selectedUSPoint.id
                if let date = Self.parseDay(draft.proposal.effectiveDate) {
                    effectiveDate = date
                }
                restoredDraft = draft.requiresRemoteReview
                isStale = !draft.proposal.matchingSnapshot(fresh)
                needsRegeneration = true
            } else if let existing = proposal {
                if !existing.matchingSnapshot(fresh) { isStale = true }
            }
            if selectedUSPointID.isEmpty, proposal == nil,
               let pointID = fresh.currentUSPrice?.pricePointID,
               fresh.usPoints.contains(where: { $0.id == pointID }) {
                selectedUSPointID = pointID
            }
            phase = proposal == nil ? .ready : .reviewing
        } catch {
            guard requestID == token, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            phase = proposal == nil ? .idle : .reviewing
        }
    }

    func changeUSPoint(_ pointID: String) {
        guard !isWorking, selectedUSPointID != pointID else { return }
        selectedUSPointID = pointID
        referenceSet = nil
        needsRegeneration = proposal != nil
    }

    func changeDate(_ date: Date) {
        guard !isWorking else { return }
        effectiveDate = date
        needsRegeneration = proposal != nil
    }

    func reviewUpdatedBaseline() async {
        // A full regeneration uses the last freshly loaded snapshot. If it
        // fails, the previous proposal and stale flags remain visible.
        await generate()
    }

    func generate() async {
        guard !isWorking, let snapshot, let mapping,
              let point = selectedUSPoint else {
            errorMessage = "Select a valid US price point first."
            return
        }
        let token = UUID()
        requestID = token
        phase = .generating
        errorMessage = nil
        do {
            let previous = proposal
            let references = try await service.loadReferenceSet(
                snapshot: snapshot, selectedUSPoint: point, mapping: mapping,
                overrides: previous?.overrides ?? []
            )
            try Task.checkCancellation()
            let generated = try RegionalPricingEngine.generate(
                snapshot: snapshot, selectedUSPoint: point,
                mapping: mapping, effectiveDate: effectiveDateString,
                references: references, existingOverrides: previous?.overrides ?? [],
                exclusions: Set(previous?.exclusions ?? []),
                subscriberPolicy: previous?.subscriberPolicy ?? .preserveExistingOnIncrease,
                acknowledgedWarnings: Set(previous?.acknowledgedWarnings ?? []),
                proposalID: previous?.id ?? UUID()
            )
            guard requestID == token, !Task.isCancelled else { return }
            referenceSet = references
            proposal = generated
            restoredDraft = false
            isStale = false
            needsRegeneration = false
            phase = .reviewing
            try await drafts?.save(generated)
        } catch {
            guard requestID == token, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            phase = proposal == nil ? .ready : .reviewing
        }
    }

    func overridePrice(territoryID: String, point: PricingPoint) {
        guard let current = proposal, let references = referenceSet,
              let snapshot, let mapping, !isWorking, isReviewCurrent else { return }
        do {
            let validated = try RegionalPricingEngine.validatedOverride(
                RegionalPricingOverride(territoryID: territoryID,
                    planType: references.planType, point: point),
                points: references.laddersByTerritory[territoryID] ?? [],
                productID: product.id, territoryID: territoryID,
                planType: references.planType, existing: current.overrides
            )
            try rebuild(snapshot: snapshot, mapping: mapping, references: references,
                prior: current, overrides: validated)
        } catch { errorMessage = error.localizedDescription }
    }

    func resetOverride(territoryID: String) {
        guard let current = proposal, let references = referenceSet,
              let snapshot, let mapping, !isWorking, isReviewCurrent else { return }
        do {
            let revised = RegionalPricingEngine.reset(
                territory: territoryID, plan: references.planType,
                overrides: current.overrides)
            try rebuild(snapshot: snapshot, mapping: mapping, references: references,
                prior: current, overrides: revised)
        } catch { errorMessage = error.localizedDescription }
    }

    func resetAllOverrides() {
        guard let current = proposal, let references = referenceSet,
              let snapshot, let mapping, !isWorking, isReviewCurrent else { return }
        do {
            try rebuild(snapshot: snapshot, mapping: mapping, references: references,
                prior: current, overrides: [])
        } catch { errorMessage = error.localizedDescription }
    }

    func setExcluded(territoryID: String, excluded: Bool) {
        guard let current = proposal, let references = referenceSet,
              let snapshot, let mapping, !isWorking, isReviewCurrent else { return }
        do {
            var ids = Set(current.exclusions)
            if excluded { ids.insert(territoryID) } else { ids.remove(territoryID) }
            try rebuild(snapshot: snapshot, mapping: mapping, references: references,
                prior: current, overrides: current.overrides, exclusions: ids)
        } catch { errorMessage = error.localizedDescription }
    }

    private func rebuild(snapshot: PricingSnapshot,
                         mapping: RegionalPricingMapping,
                         references: RegionalPricingReferenceSet,
                         prior: RegionalPricingProposal,
                         overrides: [RegionalPricingOverride],
                         exclusions: Set<String>? = nil) throws {
        // A base-territory override can affect all automatic IAP equalizations.
        // Do not reuse the old reference snapshot in this case.
        if product.kind == .lifetime,
           let base = snapshot.baseTerritoryID, base != "USA",
           prior.overrides.first(where: { $0.territoryID == base })?.point.id !=
             overrides.first(where: { $0.territoryID == base })?.point.id {
            needsRegeneration = true
            errorMessage = "Base-territory override changed. Generate again to reload Apple's automatic price effects."
            return
        }
        let generated = try RegionalPricingEngine.generate(
            snapshot: snapshot, selectedUSPoint: references.sourceUSPoint,
            mapping: mapping, effectiveDate: prior.effectiveDate,
            references: references, existingOverrides: overrides,
            exclusions: exclusions ?? Set(prior.exclusions),
            subscriberPolicy: prior.subscriberPolicy,
            acknowledgedWarnings: Set(prior.acknowledgedWarnings),
            proposalID: prior.id
        )
        proposal = generated
        Task { [drafts] in try? await drafts?.save(generated) }
    }

    func clearError() { errorMessage = nil }

    private static func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }
}
