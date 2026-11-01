import Foundation

// Read-only JSON:API wire models. Apple resource IDs are opaque; never decode or synthesize them.
struct PricingResourceID: Codable, Hashable, Sendable {
    let type: String
    let id: String
}

struct PricingWireLink: Decodable, Sendable {
    let related: String?
    let next: String?
}

struct PricingWireRelationship: Decodable, Sendable {
    let identifiers: [PricingResourceID]?
    let links: PricingWireLink?

    enum CodingKeys: String, CodingKey { case data, links }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        links = try container.decodeIfPresent(PricingWireLink.self, forKey: .links)
        if let one = try? container.decode(PricingResourceID.self, forKey: .data) {
            identifiers = [one]
        } else {
            identifiers = try container.decodeIfPresent([PricingResourceID].self, forKey: .data)
        }
    }

    var firstID: String? { identifiers?.first?.id }
}

struct PricingWireResource<Attributes: Decodable & Sendable>: Decodable, Sendable {
    let id: String
    let type: String
    let attributes: Attributes?
    let relationships: [String: PricingWireRelationship]?

    func relatedID(_ name: String) -> String? { relationships?[name]?.firstID }
    func relatedIDs(_ name: String) -> [String]? { relationships?[name]?.identifiers?.map(\.id) }
}

struct PricingPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let data: [Item]
    let included: [PricingIncludedResource]?
    let links: Paging?
    struct Paging: Decodable, Sendable { let next: String? }
}

struct PricingSingle<Item: Decodable & Sendable>: Decodable, Sendable {
    let data: Item?
}

struct PricingIncludedResource: Decodable, Sendable {
    let id: String
    let type: String
    let attributes: PricingCommonAttributes?
    let relationships: [String: PricingWireRelationship]?
    func relatedID(_ name: String) -> String? { relationships?[name]?.firstID }
}

struct PricingCommonAttributes: Decodable, Sendable {
    let currency: String?
    let customerPrice: String?
    let startDate: String?
    let endDate: String?
    let manual: Bool?
    let preserved: Bool?
    let planType: String?
}

struct PricingIAPAttributes: Decodable, Sendable {
    let name: String?
    let productId: String?
    let inAppPurchaseType: String?
    let state: String?
}

struct PricingGroupAttributes: Decodable, Sendable {
    let referenceName: String?
}

struct PricingSubscriptionAttributes: Decodable, Sendable {
    let name: String?
    let productId: String?
    let subscriptionPeriod: String?
    let state: String?
    let groupLevel: Int?
}

struct PricingTerritoryAttributes: Decodable, Sendable {
    let currency: String?
}

struct PricingPricePointAttributes: Decodable, Sendable {
    let customerPrice: String?
}

struct PricingIAPPriceAttributes: Decodable, Sendable {
    let startDate: String?
    let endDate: String?
    let manual: Bool?
}

struct PricingSubscriptionPriceAttributes: Decodable, Sendable {
    let startDate: String?
    let preserved: Bool?
    let planType: String?
}

struct PricingPlanAvailabilityAttributes: Decodable, Sendable {
    let planType: String?
    let availableInNewTerritories: Bool?
}

struct PricingAvailabilityAttributes: Decodable, Sendable {
    let availableInNewTerritories: Bool?
}

struct PricingOpaqueAttributes: Decodable, Sendable {}

// Normalized read models. Distinct from the Apple wire format so the suggestion
// engine can operate on verified snapshots without network or token dependencies.
enum PricingProductKind: String, Codable, Sendable {
    case lifetime
    case subscription
    case unsupported
}

struct PricingProduct: Codable, Hashable, Sendable, Identifiable {
    let id: String                  // App Store Connect resource ID, not productId
    let appID: String
    let productID: String?
    let name: String
    let kind: PricingProductKind
    let rawType: String?
    let groupID: String?
    let groupName: String?
    let serviceLevel: String?
    let duration: String?
    let unsupportedReason: String?
}

struct PricingTerritory: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let currency: String?
    let available: Bool? // nil = unknown, not false
    let planType: String?
}

struct PricingPoint: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let productID: String
    let territoryID: String
    let planType: String?
    let currency: String?
    let customerPrice: Decimal
}

enum PricingPriceOrigin: String, Codable, Sendable {
    case manualIAP
    case automaticIAP
    case subscription
}

struct PricingPriceRecord: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let territoryID: String?
    let pricePointID: String?
    let customerPrice: Decimal?
    let currency: String?
    let startDate: String?
    let endDate: String?
    let preserved: Bool?
    let manual: Bool?
    let planType: String?
    let origin: PricingPriceOrigin
}

struct PricingReadIssue: Codable, Hashable, Sendable {
    let resource: String
    let message: String
}

struct PricingPlanTerritories: Codable, Hashable, Sendable {
    let planType: String
    let territoryIDs: [String]
}

struct PricingUSSummary: Codable, Sendable {
    let product: PricingProduct
    let prices: [PricingPriceRecord]
    let issues: [PricingReadIssue]

    var current: PricingPriceRecord? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let date = formatter.string(from: Date())
        let candidates = prices.filter {
            $0.territoryID == "USA" && $0.preserved != true &&
            ($0.startDate == nil || $0.startDate! <= date) &&
            ($0.endDate == nil || $0.endDate! >= date)
        }
        if Set(candidates.compactMap(\.planType)).count > 1 { return nil }
        return candidates.sorted {
            if $0.startDate != $1.startDate { return ($0.startDate ?? "") > ($1.startDate ?? "") }
            if $0.manual != $1.manual { return $0.manual == true }
            return $0.id < $1.id
        }.first
    }
}

struct PricingSnapshot: Codable, Sendable {
    let accountScope: String
    let product: PricingProduct
    let fetchedAt: Date
    let territories: [PricingTerritory]
    let planTerritories: [PricingPlanTerritories]
    let baseTerritoryID: String?
    let scheduleID: String?
    let prices: [PricingPriceRecord]
    let usPoints: [PricingPoint]
    let issues: [PricingReadIssue]
    let semanticFingerprint: String

    // Preserved subscriber prices are NOT public new-subscriber prices.
    func publicPrice(territoryID: String, planType: String? = nil, on date: String) -> PricingPriceRecord? {
        let candidates = prices.filter {
            $0.territoryID == territoryID &&
            $0.preserved != true &&
            (planType == nil || $0.planType == planType) &&
            ($0.startDate == nil || $0.startDate! <= date) &&
            ($0.endDate == nil || $0.endDate! >= date)
        }
        // Multiple billing plans cannot be collapsed into a single "current" price.
        if planType == nil && Set(candidates.compactMap(\.planType)).count > 1 { return nil }
        return candidates.sorted {
            if $0.startDate != $1.startDate {
                return ($0.startDate ?? "") > ($1.startDate ?? "")
            }
            // Explicit manual entries win over automatic entries on same date.
            if $0.manual != $1.manual { return $0.manual == true }
            return $0.id < $1.id
        }.first
    }

    var currentUSPrice: PricingPriceRecord? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let today = formatter.string(from: Date())
        return publicPrice(territoryID: "USA", on: today)
    }
}

enum PricingDecimal {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func parse(_ text: String?, allowingZero: Bool = false) -> Decimal? {
        guard let text, !text.isEmpty,
              text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: posix),
              (allowingZero ? amount >= 0 : amount > 0) else { return nil }
        return amount
    }
}

enum PricingReadError: LocalizedError, Sendable {
    case missingResource(String)
    case incompleteAvailability(String)
    case unsupportedPlan(String)
    case unsupportedRepresentation(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let item): "Missing Apple pricing resource: \(item)."
        case .incompleteAvailability(let item): "Territory availability could not be established for \(item)."
        case .unsupportedPlan(let plan): "Subscription plan \(plan) is not supported by the read-only pricing flow."
        case .unsupportedRepresentation(let reason): reason
        }
    }
}

