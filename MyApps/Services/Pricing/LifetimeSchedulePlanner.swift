import Foundation

/// Exact JSON:API shape documented by Apple for POST /v1/inAppPurchasePriceSchedules.
/// All included point IDs are opaque IDs fetched from Apple's price-point ladders.
struct LifetimeScheduleCreateRequest: Codable, Sendable {
    let data: Schedule
    let included: [InlinePrice]

    struct Schedule: Codable, Sendable {
        let type = "inAppPurchasePriceSchedules"
        let relationships: Relationships
        enum CodingKeys: String, CodingKey { case type, relationships }

        struct Relationships: Codable, Sendable {
            let inAppPurchase: One
            let baseTerritory: One
            let manualPrices: Many
        }
    }

    struct One: Codable, Sendable {
        let data: PricingResourceID
    }

    struct Many: Codable, Sendable {
        let data: [PricingResourceID]
    }

    struct InlinePrice: Codable, Sendable {
        let type = "inAppPurchasePrices"
        let id: String
        let attributes: Attributes
        let relationships: Relationships

        enum CodingKeys: String, CodingKey { case type, id, attributes, relationships }

        struct Attributes: Codable, Sendable {
            let startDate: String?
            let endDate: String?

            enum CodingKeys: String, CodingKey { case startDate, endDate }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let startDate {
                    try container.encode(startDate, forKey: .startDate)
                } else {
                    try container.encodeNil(forKey: .startDate)
                }
                if let endDate { try container.encode(endDate, forKey: .endDate) }
            }
        }

        struct Relationships: Codable, Sendable {
            let inAppPurchaseV2: One
            let inAppPurchasePricePoint: One
        }
    }
}

struct LifetimeScheduleEntry: Codable, Sendable, Identifiable {
    let id: String // Stable within frozen request. Not a guessed Apple resource ID.
    let territoryID: String
    let pointID: String
    let startDate: String?
    let endDate: String?
    let preserved: Bool
}

struct LifetimeSchedulePlan: Codable, Sendable {
    let proposalID: UUID
    let product: PricingProduct
    let accountScope: String
    let appID: String
    let productID: String
    let proposalFingerprint: String
    let baselineFingerprint: String
    let baseTerritoryID: String
    let effectiveDate: String
    let selectedUSPoint: PricingPoint
    let roundingPolicy: RegionalPriceRoundingPolicy?
    let presetSnapshot: RegionalPricingPreset?
    let affectedTerritories: [String]
    let indirectTerritories: [String]
    let expectedAutomaticPoints: [String: String]
    let excludedTerritories: [String]
    let preservedEntries: [LifetimeScheduleEntry]
    let entries: [LifetimeScheduleEntry]
    let blockers: [String]
    let warnings: [String]
    let request: LifetimeScheduleCreateRequest?

    var isNoOp: Bool { request == nil && blockers.isEmpty }
    var isExecutable: Bool { request != nil && blockers.isEmpty }
}

enum LifetimeSchedulePlanner {
    /// Pure planning with a fresh semantic snapshot. No hidden price changes,
    /// no independent per-country requests and no automatic schedule deletion.
    static func plan(proposal: RegionalPricingProposal, fresh: PricingSnapshot,
                     today: String) -> LifetimeSchedulePlan {
        var blockers: [String] = []
        var warnings: [String] = []
        let commonFallbacks = proposal.rows.filter {
            !$0.excluded && $0.warnings.contains(.commonPriceFallback)
        }.count
        if commonFallbacks > 0 {
            warnings.append("\(commonFallbacks) countries use nearest available prices because common-price rounding has no currency rule or matching Apple point.")
        }
        let unchanged = proposal.matchingSnapshot(fresh)
        if !unchanged { blockers.append("Apple pricing state has changed since review. Refresh and regenerate.") }
        if proposal.product.kind != .lifetime || fresh.product.kind != .lifetime {
            blockers.append("Only non-consumable lifetime products are supported in this pass.")
        }
        if !proposal.canProceedToSubmissionPlanning {
            blockers.append("The reviewed proposal contains unresolved included-country blockers.")
        }
        if fresh.issues.contains(where: {
            ["schedule", "manualPrices", "automaticPrices", "baseTerritory", "availability"].contains($0.resource)
        }) {
            blockers.append("The fresh Apple schedule, prices, base, or availability are incomplete.")
        }
        guard let base = fresh.baseTerritoryID, !base.isEmpty,
              base == proposal.configuredBaseTerritory,
              let scheduleID = fresh.scheduleID, !scheduleID.isEmpty else {
            blockers.append("The configured Apple base territory or existing schedule is missing.")
            return blocked(proposal, fresh, blockers, warnings)
        }
        let date = proposal.effectiveDate
        if !Self.isValidDate(today) {
            blockers.append("Trusted current-day reference is invalid.")
        }
        if date < today { blockers.append("Effective date is in the past.") }
        if !Self.isValidDate(date) { blockers.append("Effective date is invalid.") }

        let selected = proposal.rows.filter { !$0.excluded }
        let excluded = proposal.rows.filter(\.excluded)
        if Set(proposal.exclusions) != Set(excluded.map(\.territoryID)) {
            blockers.append("Excluded territories do not match the frozen reviewed country rows.")
        }
        var indirect: [String] = []
        for row in excluded {
            if row.indirectChange || row.territoryID == base && row.diff != .unchanged {
                blockers.append("Excluded \(row.territoryID) may change through Apple's base-territory equalization.")
            }
        }
        var changes: [RegionalPricingRow] = []
        for row in selected {
            if !row.blockers.isEmpty || row.selectedPoint == nil {
                blockers.append("Unresolved country \(row.territoryID).")
                continue
            }
            guard let territory = fresh.territories.first(where: { $0.id == row.territoryID }),
                  territory.available == true else {
                blockers.append("Country \(row.territoryID) is not confirmed available.")
                continue
            }
            if !row.baselineScheduled.isEmpty {
                blockers.append("Country \(row.territoryID) already has a future schedule.")
                continue
            }
            if row.indirectChange { indirect.append(row.territoryID) }
            if row.diff != .unchanged || row.maintenanceChanged || row.indirectChange ||
               row.selectedPoint?.id != row.baselinePrice?.pricePointID {
                changes.append(row)
            }
        }
        // Date-window loss or a hidden future change is never allowed, even for
        // an otherwise untouched manually maintained territory.
        let currentManual = fresh.prices.filter { $0.origin == .manualIAP }
        for manual in currentManual {
            if manual.territoryID == nil || manual.pricePointID == nil ||
               manual.customerPrice == nil || manual.endDate != nil {
                blockers.append("An existing manual price has an unresolved relationship/window.")
            }
            if let start = manual.startDate, start > today {
                blockers.append("Existing future manual schedule \(manual.id) must be reviewed separately.")
            }
        }
        let allFuture = fresh.prices.filter {
            $0.origin == .automaticIAP && ($0.startDate ?? "") > today
        }
        if !allFuture.isEmpty {
            blockers.append("Existing future automatic schedule may be affected; preserve it before writing.")
        }
        // Require a complete, uniquely addressed current manual schedule and
        // forbid a planned automatic-to-manual change that masks a preserved row.
        let grouped = Dictionary(grouping: currentManual) { $0.territoryID ?? "?" }
        if grouped.values.contains(where: { $0.count > 1 }) {
            blockers.append("Multiple historical/manual schedule entries require explicit window preservation.")
        }
        var persisted: [LifetimeScheduleEntry] = []
        for row in currentManual.sorted(by: { $0.id < $1.id }) {
            guard let territory = row.territoryID, let point = row.pricePointID else { continue }
            persisted.append(LifetimeScheduleEntry(id: row.id, territoryID: territory,
                pointID: point, startDate: row.startDate, endDate: row.endDate,
                preserved: true))
        }
        let changedTerritories = Set(changes.map(\.territoryID))
        // Retain an existing current manual entry when scheduling a FUTURE
        // price. Same-day replacement semantics remain unverified and blocked.
        for entry in persisted where changedTerritories.contains(entry.territoryID) {
            if date <= today {
                blockers.append("Same-day replacement of current manual price in \(entry.territoryID) is not verified; choose a future date.")
            }
        }
        // Any US base change may affect excluded automatic countries, even if
        // their rows happen to compare unchanged due to stale reference data.
        if changes.contains(where: { $0.territoryID == base }) &&
            !excluded.isEmpty {
            blockers.append("Base change with excluded storefronts requires independently verified indirect effects.")
        }
        if selected.contains(where: { $0.oldMode == .automatic && $0.proposedMode == .manual }) {
            warnings.append("Selected storefronts will lose automatic Apple equalization.")
        }
        let newEntries: [LifetimeScheduleEntry] = changes.sorted(by: {
            $0.territoryID < $1.territoryID
        }).compactMap { row in
            guard row.proposedMode == .manual || row.proposedMode == .base,
                  let point = row.selectedPoint else { return nil }
            return LifetimeScheduleEntry(
                id: "price-" + proposal.id.uuidString.lowercased() + "-" + row.territoryID,
                territoryID: row.territoryID, pointID: point.id,
                startDate: date == today ? nil : date, endDate: nil, preserved: false
            )
        }
        if changes.contains(where: { $0.proposedMode == .automatic }) &&
            !changes.filter({ $0.proposedMode == .automatic })
               .allSatisfy({ $0.indirectChange }) {
            blockers.append("Automatic-mode changes require base equalization preflight.")
        }
        let entries = persisted + newEntries
        let payload: LifetimeScheduleCreateRequest? =
            changes.isEmpty ? nil : Self.request(
                productID: proposal.product.id, base: base, entries: entries)
        // A schedule POST with zero intended new prices is never sent.
        if changes.count > 0 && newEntries.isEmpty {
            blockers.append("No valid manual entries were generated for requested changes.")
        }
        return LifetimeSchedulePlan(
            proposalID: proposal.id, product: proposal.product, accountScope: proposal.accountScope,
            appID: proposal.product.appID, productID: proposal.product.id,
            proposalFingerprint: proposal.fingerprint,
            baselineFingerprint: fresh.semanticFingerprint, baseTerritoryID: base,
            effectiveDate: date, selectedUSPoint: proposal.selectedUSPoint,
            roundingPolicy: proposal.effectiveRoundingPolicy,
            presetSnapshot: proposal.effectivePreset,
            affectedTerritories: changes.map(\.territoryID).sorted(),
            indirectTerritories: indirect.sorted(),
            expectedAutomaticPoints: Dictionary(uniqueKeysWithValues: changes.compactMap {
                $0.proposedMode == .automatic ? $0.selectedPoint.map { ($0.territoryID, $0.id) } : nil
            }),
            excludedTerritories: excluded.map(\.territoryID).sorted(),
            preservedEntries: persisted, entries: entries,
            blockers: Array(Set(blockers)).sorted(),
            warnings: Array(Set(warnings)).sorted(),
            request: blockers.isEmpty ? payload : nil
        )
    }

    private static func blocked(_ proposal: RegionalPricingProposal, _ fresh: PricingSnapshot,
                                _ blockers: [String], _ warnings: [String]) -> LifetimeSchedulePlan {
        LifetimeSchedulePlan(
            proposalID: proposal.id, product: proposal.product, accountScope: proposal.accountScope,
            appID: proposal.product.appID, productID: proposal.product.id,
            proposalFingerprint: proposal.fingerprint, baselineFingerprint: fresh.semanticFingerprint,
            baseTerritoryID: fresh.baseTerritoryID ?? "",
            effectiveDate: proposal.effectiveDate, selectedUSPoint: proposal.selectedUSPoint,
            roundingPolicy: proposal.effectiveRoundingPolicy,
            presetSnapshot: proposal.effectivePreset,
            affectedTerritories: [], indirectTerritories: [],
            expectedAutomaticPoints: [:],
            excludedTerritories: proposal.exclusions.sorted(),
            preservedEntries: [], entries: [], blockers: blockers, warnings: warnings,
            request: nil)
    }

    private static func request(productID: String, base: String,
                                entries: [LifetimeScheduleEntry]) -> LifetimeScheduleCreateRequest {
        LifetimeScheduleCreateRequest(
            data: .init(relationships: .init(
                inAppPurchase: .init(data: .init(type: "inAppPurchases", id: productID)),
                baseTerritory: .init(data: .init(type: "territories", id: base)),
                manualPrices: .init(data: entries.map { .init(type: "inAppPurchasePrices", id: $0.id) })
            )),
            included: entries.map { price in
                .init(id: price.id, attributes: .init(
                    startDate: price.startDate, endDate: price.endDate),
                    relationships: .init(
                        // Apple schema uses the legacy resource type spelling in this
                        // relationship even though the property is named inAppPurchaseV2.
                        inAppPurchaseV2: .init(data: .init(type: "inAppPurchases", id: productID)),
                        inAppPurchasePricePoint: .init(
                            data: .init(type: "inAppPurchasePricePoints", id: price.pointID))
                    ))
            }
        )
    }

    private static func isValidDate(_ value: String) -> Bool {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.isLenient = false
        return parser.date(from: value).map { parser.string(from: $0) == value } ?? false
    }
}


