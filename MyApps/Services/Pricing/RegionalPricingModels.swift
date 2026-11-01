import Foundation

/// A storefront day is a calendar value, never a device-timezone timestamp.
/// The picker and wire encoder must use the same calendar and timezone.
enum PricingDay {
    static let timeZone = TimeZone(secondsFromGMT: 0)!
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }

    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), string(from: date) == value else { return nil }
        return date
    }

    static func initialSelection(now: Date = Date(), localTimeZone: TimeZone = .current) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = localTimeZone
        let components = local.dateComponents([.year, .month, .day], from: now)
        return calendar.date(from: components) ?? now
    }
}

enum RegionalPricingTier: Int, Codable, CaseIterable, Sendable {
    case premium = 1, developed, midMarket, priceSensitive, lowestPurchasingPower

    var title: String {
        switch self {
        case .premium: "Premium"
        case .developed: "Developed"
        case .midMarket: "Mid-market"
        case .priceSensitive: "Price-sensitive"
        case .lowestPurchasingPower: "Lowest purchasing power"
        }
    }
}

struct RegionalPricingPreset: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let version: Int
    let factors: [Int: Decimal]
    let name: String?

    init(id: String, version: Int, factors: [Int: Decimal], name: String? = nil) {
        self.id = id
        self.version = version
        self.factors = factors
        self.name = name
    }

    var displayName: String { name ?? (id == "balanced" ? "Balanced" : "Custom Preset") }
    var isBuiltIn: Bool { id == Self.balanced.id }
    var hasValidFactors: Bool {
        guard factors.count == 5, factors[1] == 1 else { return false }
        for tier in 1...5 {
            guard let factor = factors[tier], factor > 0, factor <= 1 else { return false }
            if tier > 1, factor > (factors[tier - 1] ?? 0) { return false }
        }
        return true
    }

    var percentageSummary: String {
        (1...5).map { tier in
            NSDecimalNumber(decimal: (factors[tier] ?? 0) * 100).stringValue + "%"
        }.joined(separator: " / ")
    }

    static let balanced = Self(id: "balanced", version: 1, factors: [
        1: Decimal(string: "1.00")!, 2: Decimal(string: "0.85")!,
        3: Decimal(string: "0.65")!, 4: Decimal(string: "0.45")!,
        5: Decimal(string: "0.30")!
    ], name: "Balanced")
}

struct RegionalPricingAssignment: Codable, Sendable {
    let territoryID: String
    let tier: Int
    let incomeGroup: String?
    let source: String
    let rationale: String?
    let pppYear: Int?
    let pppValue: Decimal?
    let usPPPValue: Decimal?
    let needsReview: Bool
}

struct RegionalPricingMapping: Codable, Sendable {
    let version: String
    let ruleVersion: String
    let accessedOn: String
    let incomeClassificationEdition: String
    let incomeSourceURL: String
    let pppSourceURL: String
    let appleTerritorySourceURL: String
    let entries: [RegionalPricingAssignment]

    func assignment(for territory: String) -> RegionalPricingAssignment? {
        entries.first { $0.territoryID == territory }
    }

    /// Runtime validation must compare against the actual GET /v1/territories IDs.
    func validate(knownTerritories: [String]) throws -> [String] {
        guard !version.isEmpty, !ruleVersion.isEmpty, !entries.isEmpty else {
            throw RegionalPricingError.invalidMapping("Missing mapping metadata.")
        }
        let us = entries.filter { $0.territoryID == "USA" }
        guard us.count == 1, us[0].tier == 1, !us[0].needsReview else {
            throw RegionalPricingError.invalidMapping("USA must be a verified tier-1 entry.")
        }
        var seen = Set<String>()
        for entry in entries {
            guard seen.insert(entry.territoryID).inserted,
                  (1...5).contains(entry.tier),
                  entry.territoryID.count == 3,
                  !entry.source.isEmpty else {
                throw RegionalPricingError.invalidMapping("Invalid or duplicate territory: \(entry.territoryID).")
            }
            if entry.source == "high-income-ppp" {
                guard let value = entry.pppValue, let usa = entry.usPPPValue,
                      value > 0, usa > 0, entry.pppYear != nil,
                      entry.tier == ((value / usa >= Decimal(string: "0.80")!) ? 1 : 2) else {
                    throw RegionalPricingError.invalidMapping("PPP provenance inconsistent: \(entry.territoryID).")
                }
            }
        }
        // Unmapped Apple storefronts never inherit an arbitrary purchasing-power discount.
        return knownTerritories.filter { !seen.contains($0) }.sorted()
    }
}

enum RegionalPricingMappingLoader {
    static func bundled(bundle: Bundle = .main) throws -> RegionalPricingMapping {
        guard let url = bundle.url(forResource: "country-tiers-v1", withExtension: "json") else {
            throw RegionalPricingError.invalidMapping("Bundled country-tiers-v1.json is missing.")
        }
        let result = try JSONDecoder().decode(RegionalPricingMapping.self, from: Data(contentsOf: url))
        _ = try result.validate(knownTerritories: [])
        return result
    }
}

enum RegionalPricingError: LocalizedError, Sendable {
    case invalidMapping(String)
    case invalidReference(String)
    case invalidDate
    case mismatchedAccount
    case invalidDraft(String)

    var errorDescription: String? {
        switch self {
        case .invalidMapping(let detail): detail
        case .invalidReference(let detail): detail
        case .invalidDate: "Choose a valid ISO date (YYYY-MM-DD)."
        case .mismatchedAccount: "Saved proposal belongs to a different App Store Connect account or product."
        case .invalidDraft(let detail): detail
        }
    }
}

enum RegionalPricingMode: String, Codable, Sendable {
    case base, automatic, manual, subscription, unknown
}

enum RegionalPriceRoundingPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case nearestCommon, nearestAvailable
    var id: Self { self }
    var title: String {
        switch self {
        case .nearestCommon: "Nearest Common Price"
        case .nearestAvailable: "Nearest Available Price"
        }
    }
    var explanation: String {
        switch self {
        case .nearestCommon:
            "Default. After applying the country tier, choose the nearest valid Apple price matching MyApps' currency-specific common-price rules. If no rule or matching point is available, use the nearest available price and show a warning."
        case .nearestAvailable:
            "After applying the country tier, choose the nearest price from Apple's full valid list, regardless of its ending."
        }
    }
}

enum RegionalSubscriberPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case preserveExistingOnIncrease
    // Keep the original wire value so existing drafts remain readable.
    case applyToExistingOnIncrease = "requireAcknowledgmentOnIncrease"

    var id: Self { self }

    var title: String {
        switch self {
        case .preserveExistingOnIncrease: "Keep Current Prices (Default)"
        case .applyToExistingOnIncrease: "Apply Increases to Existing Subscribers"
        }
    }

    var summary: String {
        switch self {
        case .preserveExistingOnIncrease: "Keep current prices"
        case .applyToExistingOnIncrease: "Apply increases to current-price subscribers"
        }
    }

    var explanation: String {
        switch self {
        case .preserveExistingOnIncrease:
            "When a country's price increases, subscribers paying its current public price keep that price. New subscribers pay the new price. This is the default."
        case .applyToExistingOnIncrease:
            "When a country's price increases, apply it to existing subscribers paying its current public price. Apple handles notice and any required consent; renewal timing can differ from the public price's start date."
        }
    }

    var confirmation: String {
        switch self {
        case .preserveExistingOnIncrease:
            "Existing subscribers keep their current price on increases."
        case .applyToExistingOnIncrease:
            "Increases also apply to subscribers paying the current public price, subject to Apple's notice and consent rules."
        }
    }
}

enum SubscriptionPricingGuidance {
    static let decreases = "Price decreases apply to existing subscribers at renewal. Apple does not offer a choice to keep a higher price. Subscribers already paying a lower preserved price are not raised by this setting."
    static let olderGroups = "Neither increase option changes older subscriber groups whose prices were already preserved. Removing their price preservation is a separate action in App Store Connect."
    static let consent = "Apple determines whether subscribers receive a notice or must consent. If required consent is not given, the subscription expires at the end of the current billing period. MyApps cannot preview Apple's final consent decision for every subscriber."
    static let helpURL = URL(string: "https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/")!
}

enum RegionalPricingDiff: String, Codable, Sendable {
    case increase, decrease, unchanged, unknown
}

enum RegionalPricingWarning: String, Codable, Hashable, Sendable {
    case unmapped, unverifiedMapping, missingReference, missingLadder, invalidLadder,
         clamped, invalidOverride, unknownBaseline, unknownAvailability,
         unsupportedPlan, scheduleConflict, missingBaseTerritory,
         indirectAutomaticChange, manualMaintenance, includedStateChanged,
         pendingFutureSchedule, incompleteSnapshot, commonPriceFallback

    var explanation: String {
        self == .commonPriceFallback
            ? "No common-price rule or matching Apple point is available for this currency. Used the nearest available Apple price instead."
            : rawValue
    }
}

struct RegionalPricingOverride: Codable, Sendable {
    let territoryID: String
    let planType: String?
    let point: PricingPoint
}

struct RegionalPricingRow: Codable, Sendable, Identifiable {
    var id: String { territoryID + ":" + (planType ?? "-") }
    let territoryID: String
    let planType: String?
    let tier: Int?
    let factor: Decimal
    let mappingSource: String
    let currency: String?
    let referencePoint: PricingPoint?
    let targetPrice: Decimal?
    let suggestedPoint: PricingPoint?
    let overridePoint: PricingPoint?
    let selectedPoint: PricingPoint?
    let baselinePrice: PricingPriceRecord?
    let baselineScheduled: [PricingPriceRecord]
    let oldMode: RegionalPricingMode
    let proposedMode: RegionalPricingMode
    let diff: RegionalPricingDiff
    let maintenanceChanged: Bool
    let indirectChange: Bool
    let excluded: Bool
    let warnings: [RegionalPricingWarning]
    let blockers: [String]

    var isNoOp: Bool {
        diff == .unchanged && !maintenanceChanged && !indirectChange &&
        selectedPoint?.id == baselinePrice?.pricePointID &&
        blockers.isEmpty && baselineScheduled.isEmpty
    }
}

struct RegionalPricingSummary: Codable, Sendable {
    let eligible: Int
    let increases: Int
    let decreases: Int
    let unchanged: Int
    let unknown: Int
    let warnings: Int
    let blocked: Int
    let excluded: Int
    let automaticToManual: Int
}

struct RegionalPricingProposal: Codable, Sendable, Identifiable {
    let id: UUID
    let schemaVersion: Int
    let accountScope: String
    let product: PricingProduct
    let snapshotFingerprint: String
    let snapshotFetchedAt: Date
    let selectedUSPoint: PricingPoint
    let presetID: String
    let presetVersion: Int
    // Frozen values are independent of later global preset edits/deletion.
    let presetSnapshot: RegionalPricingPreset?
    let mappingVersion: String
    let effectiveDate: String
    let configuredBaseTerritory: String?
    // May stage a base-country decision while the previous rows remain visible
    // and explicitly require regeneration of dependent Apple equalizations.
    var overrides: [RegionalPricingOverride]
    let exclusions: [String]
    let subscriberPolicy: RegionalSubscriberPolicy
    // Missing in old drafts means their original full-ladder rounding behavior.
    let roundingPolicy: RegionalPriceRoundingPolicy?
    let acknowledgedWarnings: [String]
    let rows: [RegionalPricingRow]
    let summary: RegionalPricingSummary
    let fingerprint: String

    var effectiveRoundingPolicy: RegionalPriceRoundingPolicy { roundingPolicy ?? .nearestAvailable }

    var effectivePreset: RegionalPricingPreset? {
        if let presetSnapshot {
            guard presetSnapshot.id == presetID, presetSnapshot.version == presetVersion,
                  presetSnapshot.hasValidFactors else { return nil }
            return presetSnapshot
        }
        // Only Balanced existed in older production drafts.
        return presetID == RegionalPricingPreset.balanced.id &&
            presetVersion == RegionalPricingPreset.balanced.version ? .balanced : nil
    }

    // A draft is always treated as unverified until the current Apple snapshot
    // and the valid Apple point ladders have been loaded again.
    var canProceedToSubmissionPlanning: Bool {
        !rows.isEmpty && rows.allSatisfy {
            $0.excluded ? !$0.blockers.contains(where: {
                $0.hasPrefix("Excluded country")
            }) : $0.blockers.isEmpty
        }
    }

    // An existing draft must never be treated as remotely verified after launch.
    func matchingSnapshot(_ fresh: PricingSnapshot) -> Bool {
        accountScope == fresh.accountScope && product.id == fresh.product.id &&
        snapshotFingerprint == fresh.semanticFingerprint
    }
}

struct RegionalPricingReferenceSet: Sendable {
    let sourceUSPoint: PricingPoint
    let equalizedByTerritory: [String: PricingPoint]
    let laddersByTerritory: [String: [PricingPoint]]
    // For lifetime prices, may be derived only after selecting the actual configured
    // base territory's proposed point and requesting its own equalizations.
    let automaticFromConfiguredBase: [String: PricingPoint]?
    let planType: String?
    let readIssues: [String]
}

struct RegionalPricingFixtureSibling: Sendable {
    let product: PricingProduct
    let explicitServiceLevelID: String?
    let currency: String
    let price: Decimal
    let durationMonths: Int?
}

enum RegionalPricingSiblingAdvisory {
    // Entitlements/service level are supplied as explicitly verified data; names
    // and shared groups alone are not sufficient to establish equivalence.
    static func warnings(for products: [RegionalPricingFixtureSibling]) -> [String] {
        var result: [String] = []
        for annual in products where annual.durationMonths == 12 {
            guard let level = annual.explicitServiceLevelID, annual.price > 0 else { continue }
            for monthly in products where monthly.durationMonths == 1 &&
                monthly.explicitServiceLevelID == level &&
                monthly.currency == annual.currency &&
                monthly.product.groupID == annual.product.groupID &&
                monthly.price > 0 {
                if annual.price > monthly.price * 12 {
                    result.append("\(annual.product.id): annual price exceeds twelve monthly payments (\(annual.currency)).")
                }
            }
        }
        return result.sorted()
    }
}




