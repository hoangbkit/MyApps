import Foundation

/// Apple: POST /v1/subscriptionPrices, one price-point per territory.
/// The price-point ID already determines the territory.
struct SubscriptionPriceCreateRequest: Codable, Sendable {
    let data: Resource

    struct Resource: Codable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships

        init(subscriptionID: String, pointID: String, date: String?, preserve: Bool) {
            type = "subscriptionPrices"
            attributes = .init(startDate: date, preserveCurrentPrice: preserve, planType: "UPFRONT")
            relationships = .init(subscription: .init(data: .init(type: "subscriptions", id: subscriptionID)),
                                  subscriptionPricePoint: .init(data: .init(type: "subscriptionPricePoints", id: pointID)))
        }
    }

    struct Attributes: Codable, Sendable {
        let startDate: String?
        let preserveCurrentPrice: Bool
        let planType: String

        enum CodingKeys: String, CodingKey { case startDate, preserveCurrentPrice, planType }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let startDate {
                try container.encode(startDate, forKey: .startDate)
            } else {
                try container.encodeNil(forKey: .startDate)
            }
            try container.encode(preserveCurrentPrice, forKey: .preserveCurrentPrice)
            try container.encode(planType, forKey: .planType)
        }
    }

    struct Relationships: Codable, Sendable {
        let subscription: One
        let subscriptionPricePoint: One
    }

    struct One: Codable, Sendable {
        let data: PricingResourceID
    }
}

struct SubscriptionPriceChange: Codable, Sendable, Identifiable {
    var id: String { territoryID + ":" + planType }
    let territoryID: String
    let planType: String
    let point: PricingPoint
    let previous: PricingPriceRecord
    let effectiveDate: String
    let increase: Bool
    let preserveExistingPrice: Bool
    let preservedCohortCount: Int
    let request: SubscriptionPriceCreateRequest

    var subscriberImpact: String {
        if !increase { return "Decrease applies at renewal; lower preserved prices are not raised" }
        return preserveExistingPrice
            ? "Current-price subscribers keep their price"
            : "Current-price subscribers receive the increase under Apple's notice/consent rules"
    }
}

struct SubscriptionWritePlan: Codable, Sendable {
    let proposalID: UUID
    let product: PricingProduct
    let accountScope: String
    let proposalFingerprint: String
    let baselineFingerprint: String
    let effectiveDate: String
    // Optional so journals written before this field remain readable.
    let selectedUSPoint: PricingPoint?
    let subscriberPolicy: RegionalSubscriberPolicy
    let roundingPolicy: RegionalPriceRoundingPolicy?
    let presetSnapshot: RegionalPricingPreset?
    let excluded: [String]
    let changes: [SubscriptionPriceChange]
    let blockers: [String]
    let warnings: [String]
    let requiresDecreaseAcknowledgment: Bool

    var isExecutable: Bool { !changes.isEmpty && blockers.isEmpty }
    var isNoOp: Bool { changes.isEmpty && blockers.isEmpty }
    // Computed rather than stored so older journals remain compatible.
    var requiresIncreaseAcknowledgment: Bool {
        changes.contains { $0.increase && !$0.preserveExistingPrice }
    }
}

/// Pure and deterministic with an injected current day and explicit acknowledgement.
/// A subscription's duration is separate from the billing plan type.
enum SubscriptionPricePlanner {
    static func plan(
        proposal: RegionalPricingProposal,
        fresh: PricingSnapshot,
        today: String,
        acknowledgesRenewalDecrease: Bool,
        acknowledgesExistingSubscriberIncrease: Bool = false
    ) -> SubscriptionWritePlan {
        var blockers: [String] = []
        var warnings: [String] = []
        var changes: [SubscriptionPriceChange] = []
        let commonFallbacks = proposal.rows.filter {
            !$0.excluded && $0.warnings.contains(.commonPriceFallback)
        }.count
        if commonFallbacks > 0 {
            warnings.append("\(commonFallbacks) countries use nearest available prices because common-price rounding has no currency rule or matching Apple point.")
        }

        if proposal.product.kind != .subscription || fresh.product.kind != .subscription {
            blockers.append("Not an auto-renewable subscription.")
        }
        if !proposal.matchingSnapshot(fresh) {
            blockers.append("Apple's subscription prices changed since the review. Refresh and regenerate.")
        }
        if !proposal.canProceedToSubmissionPlanning {
            blockers.append("The reviewed proposal has unresolved country blockers.")
        }
        if fresh.issues.contains(where: {
            ["subscriptionPrices", "planAvailability", "US price points", "US price", "planType"].contains($0.resource)
        }) {
            blockers.append("An Apple subscription price or plan resource is incomplete.")
        }
        let plans = Set(fresh.planTerritories.map(\.planType))
        if plans != ["UPFRONT"] {
            blockers.append("Only standard UPFRONT billing plans are supported; commitment plans require adjusted pricing.")
        }
        if !validDay(today) || !validDay(proposal.effectiveDate) || proposal.effectiveDate < today {
            blockers.append("Choose a valid current or future effective date.")
        }
        if Set(proposal.exclusions) != Set(proposal.rows.filter(\.excluded).map(\.territoryID)) {
            blockers.append("Frozen excluded countries do not match reviewed rows.")
        }
        if proposal.rows.filter({ !$0.excluded }).contains(where: { $0.planType != "UPFRONT" }) {
            blockers.append("Reviewed subscription rows have missing or unsupported billing plan types.")
        }
        let eligible = fresh.planTerritories.first(where: { $0.planType == "UPFRONT" })?.territoryIDs ?? []
        var decreases = false
        for row in proposal.rows.sorted(by: { $0.id < $1.id }) {
            if row.excluded { continue }
            guard row.blockers.isEmpty, let selected = row.selectedPoint else {
                blockers.append("Country \(row.territoryID) is blocked or has no selected Apple price point.")
                continue
            }
            guard eligible.contains(row.territoryID),
                  fresh.territories.contains(where: { $0.id == row.territoryID && $0.available == true }) else {
                blockers.append("Subscription is not confirmed available in \(row.territoryID).")
                continue
            }
            guard let current = fresh.publicPrice(territoryID: row.territoryID,
                                                  planType: "UPFRONT",
                                                  on: proposal.effectiveDate),
                  let oldAmount = current.customerPrice, let newAmount = row.selectedPoint?.customerPrice,
                  let currency = current.currency, currency == selected.currency,
                  selected.productID == fresh.product.id, selected.territoryID == row.territoryID,
                  selected.planType == "UPFRONT" else {
                blockers.append("Current public price or selected point identity is unresolved for \(row.territoryID).")
                continue
            }
            if current.id != row.baselinePrice?.id ||
                current.pricePointID != row.baselinePrice?.pricePointID ||
                current.customerPrice != row.baselinePrice?.customerPrice {
                blockers.append("Reviewed baseline does not match fresh Apple state in \(row.territoryID).")
                continue
            }
            let upcoming = fresh.prices.contains {
                $0.territoryID == row.territoryID && $0.planType == "UPFRONT" &&
                $0.preserved != true && ($0.startDate ?? "") > today
            }
            if upcoming || !row.baselineScheduled.isEmpty {
                blockers.append("A scheduled price already exists for \(row.territoryID); it must not be overwritten.")
                continue
            }
            if newAmount == oldAmount && selected.id == current.pricePointID { continue }
            if newAmount == oldAmount {
                blockers.append("Same amount but different Apple point ID in \(row.territoryID) needs manual review.")
                continue
            }
            let increase = newAmount > oldAmount
            let preserve = increase && proposal.subscriberPolicy == .preserveExistingOnIncrease
            if !increase { decreases = true }
            let cohorts = fresh.prices.filter {
                $0.territoryID == row.territoryID && $0.planType == "UPFRONT" &&
                $0.preserved == true
            }.count
            let request = SubscriptionPriceCreateRequest(data: .init(
                subscriptionID: fresh.product.id, pointID: selected.id,
                date: proposal.effectiveDate == today ? nil : proposal.effectiveDate,
                preserve: preserve
            ))
            changes.append(.init(territoryID: row.territoryID, planType: "UPFRONT",
                                 point: selected, previous: current,
                                 effectiveDate: proposal.effectiveDate,
                                 increase: increase, preserveExistingPrice: preserve,
                                 preservedCohortCount: cohorts, request: request))
        }
        if decreases {
            warnings.append(SubscriptionPricingGuidance.decreases)
            if !acknowledgesRenewalDecrease {
                blockers.append("Acknowledge the effect of decreases on existing subscribers.")
            }
        }
        if changes.contains(where: { $0.increase }) {
            warnings.append(proposal.subscriberPolicy.confirmation)
            warnings.append(SubscriptionPricingGuidance.olderGroups)
        }
        if changes.contains(where: { $0.increase && !$0.preserveExistingPrice }) {
            warnings.append(SubscriptionPricingGuidance.consent)
            if !acknowledgesExistingSubscriberIncrease {
                blockers.append("Acknowledge that increases apply to existing current-price subscribers under Apple's notice and consent rules.")
            }
        }
        if !changes.isEmpty {
            warnings.append("One independent subscription price request is required per changed storefront; successful changes cannot be rolled back as one transaction.")
        }
        return SubscriptionWritePlan(
            proposalID: proposal.id, product: proposal.product,
            accountScope: proposal.accountScope, proposalFingerprint: proposal.fingerprint,
            baselineFingerprint: fresh.semanticFingerprint, effectiveDate: proposal.effectiveDate,
            selectedUSPoint: proposal.selectedUSPoint,
            subscriberPolicy: proposal.subscriberPolicy,
            roundingPolicy: proposal.effectiveRoundingPolicy,
            presetSnapshot: proposal.effectivePreset, excluded: proposal.exclusions.sorted(),
            changes: changes, blockers: Array(Set(blockers)).sorted(),
            warnings: Array(Set(warnings)).sorted(),
            requiresDecreaseAcknowledgment: decreases
        )
    }

    private static func validDay(_ date: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        return formatter.date(from: date).map { formatter.string(from: $0) == date } ?? false
    }
}




