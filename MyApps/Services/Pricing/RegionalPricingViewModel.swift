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
    private let presets = PricingPresetStore.shared
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
    var effectiveDate: Date = PricingDay.initialSelection()
    private(set) var subscriberPolicy: RegionalSubscriberPolicy = .preserveExistingOnIncrease
    private(set) var roundingPolicy: RegionalPriceRoundingPolicy = .nearestCommon
    private var selectedPresetID = RegionalPricingPreset.balanced.id

    var selectedPreset: RegionalPricingPreset {
        presets.preset(id: selectedPresetID) ?? .balanced
    }

    var presetNeedsRegeneration: Bool {
        guard let proposal else { return false }
        return proposal.effectivePreset != selectedPreset
    }

    private var draftRevision: UInt64 = 0
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

    var usPriceLoadingError: String? {
        guard let snapshot, snapshot.usPoints.isEmpty, !isWorking else { return nil }
        return snapshot.issues.first(where: { $0.resource == "US price points" })?.message
            ?? "Apple returned no selectable US prices for this product."
    }

    var effectiveDateString: String {
        PricingDay.string(from: effectiveDate)
    }

    var isReviewCurrent: Bool {
        proposal != nil && !isStale && !needsRegeneration && !restoredDraft &&
            !presetNeedsRegeneration &&
            proposal?.effectiveRoundingPolicy == roundingPolicy &&
            (product.kind != .subscription || proposal?.subscriberPolicy == subscriberPolicy)
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
        subscriberPolicy = .preserveExistingOnIncrease
        roundingPolicy = .nearestCommon
        selectedPresetID = RegionalPricingPreset.balanced.id
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
        defer {
            if requestID == token, phase == .loading {
                phase = proposal == nil ? (snapshot == nil ? .idle : .ready) : .reviewing
            }
        }
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
                subscriberPolicy = draft.proposal.subscriberPolicy
                roundingPolicy = draft.proposal.effectiveRoundingPolicy
                selectedPresetID = draft.proposal.presetID
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

    func changeSubscriberPolicy(_ policy: RegionalSubscriberPolicy) {
        guard product.kind == .subscription, !isWorking, subscriberPolicy != policy else { return }
        subscriberPolicy = policy
        needsRegeneration = proposal != nil
    }

    func selectPreset(_ id: String) {
        guard !isWorking, let preset = presets.preset(id: id), selectedPreset != preset else { return }
        selectedPresetID = preset.id
        referenceSet = nil
        needsRegeneration = proposal != nil
    }

    func changeRoundingPolicy(_ policy: RegionalPriceRoundingPolicy) {
        guard !isWorking, roundingPolicy != policy else { return }
        roundingPolicy = policy
        // Rounding can change a non-US IAP base point and its automatic effects.
        referenceSet = nil
        needsRegeneration = proposal != nil
    }

    func reviewUpdatedBaseline() async {
        // A full regeneration uses the last freshly loaded snapshot. If it
        // fails, the previous proposal and stale flags remain visible.
        await generate()
    }

    func generate() async {
        guard !isWorking else { return }
        if isStale {
            await load(refresh: true)
            guard errorMessage == nil, !Task.isCancelled else { return }
        }
        guard !isWorking, let snapshot, let mapping,
              let point = selectedUSPoint else {
            errorMessage = "Select a valid US price point first."
            return
        }
        let token = UUID()
        requestID = token
        phase = .generating
        errorMessage = nil
        defer {
            if requestID == token, phase == .generating {
                phase = proposal == nil ? .ready : .reviewing
            }
        }
        do {
            let previous = proposal
            // Pin values across awaits; another window can edit global presets.
            let preset = selectedPreset
            let references = try await service.loadReferenceSet(
                snapshot: snapshot, selectedUSPoint: point, mapping: mapping,
                preset: preset,
                roundingPolicy: roundingPolicy,
                overrides: previous?.overrides ?? []
            )
            try Task.checkCancellation()
            let generated = try RegionalPricingEngine.generate(
                snapshot: snapshot, selectedUSPoint: point,
                preset: preset,
                mapping: mapping, effectiveDate: effectiveDateString,
                references: references, existingOverrides: previous?.overrides ?? [],
                exclusions: Set(previous?.exclusions ?? []),
                subscriberPolicy: subscriberPolicy,
                roundingPolicy: roundingPolicy,
                acknowledgedWarnings: Set(previous?.acknowledgedWarnings ?? []),
                proposalID: previous?.id ?? UUID()
            )
            guard requestID == token, !Task.isCancelled else { return }
            referenceSet = references
            proposal = generated
            restoredDraft = false
            isStale = false
            needsRegeneration = selectedPreset != preset
            phase = .reviewing
            draftRevision &+= 1
            try await drafts?.save(generated, revision: draftRevision)
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
            var staged = prior
            staged.overrides = overrides
            proposal = staged
            needsRegeneration = true
            errorMessage = "Base-territory override changed. Generate again to reload Apple's automatic price effects."
            saveDraft(staged)
            return
        }
        guard let preset = prior.effectivePreset else {
            throw RegionalPricingError.invalidDraft("The proposal's saved preset is invalid. Generate again.")
        }
        let generated = try RegionalPricingEngine.generate(
            snapshot: snapshot, selectedUSPoint: references.sourceUSPoint,
            preset: preset,
            mapping: mapping, effectiveDate: prior.effectiveDate,
            references: references, existingOverrides: overrides,
            exclusions: exclusions ?? Set(prior.exclusions),
            subscriberPolicy: prior.subscriberPolicy,
            roundingPolicy: prior.effectiveRoundingPolicy,
            acknowledgedWarnings: Set(prior.acknowledgedWarnings),
            proposalID: prior.id
        )
        proposal = generated
        saveDraft(generated)
    }

    private func saveDraft(_ generated: RegionalPricingProposal) {
        draftRevision &+= 1
        let revision = draftRevision
        Task { [weak self, drafts] in
            do {
                try await drafts?.save(generated, revision: revision)
            } catch {
                guard let self, self.draftRevision == revision else { return }
                self.errorMessage = "Could not save pricing draft: " + error.localizedDescription
            }
        }
    }

    /// All accepted or remotely changed schedules require a fresh review.
    func markRemoteStale() {
        isStale = true
        needsRegeneration = true
        referenceSet = nil
    }

    func clearError() { errorMessage = nil }

    private static func parseDay(_ value: String) -> Date? {
        PricingDay.parse(value)
    }
}





