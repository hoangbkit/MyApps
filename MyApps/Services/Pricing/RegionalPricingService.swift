import CryptoKit
import Foundation

/// Actor-owned, read-only pricing loader. The product list is deliberately cheap;
/// a full territory/schedule snapshot is fetched only for a selected product.
actor RegionalPricingService {
    private let client: AppStoreConnectAPIClient
    private var territoryCache: [AppStoreConnectAPIClient.TerritoryResource]?

    init(client: AppStoreConnectAPIClient) {
        self.client = client
    }

    func discoverProducts(appID: String) async throws -> [PricingProduct] {
        async let purchases = client.pricingIAPs(appID: appID)
        async let groups = client.pricingGroups(appID: appID)
        let (iapResources, groupResources) = try await (purchases, groups)
        var products: [PricingProduct] = iapResources.map { iap in
            let rawType = iap.attributes?.inAppPurchaseType
            let isLifetime = rawType == "NON_CONSUMABLE"
            return PricingProduct(
                id: iap.id, appID: appID, productID: iap.attributes?.productId,
                name: iap.attributes?.name ?? iap.attributes?.productId ?? iap.id,
                kind: isLifetime ? .lifetime : .unsupported, rawType: rawType,
                groupID: nil, groupName: nil, duration: nil,
                unsupportedReason: isLifetime ? nil : "Only non-consumable IAP pricing is supported."
            )
        }
        for group in groupResources {
            let subscriptions = try await client.pricingSubscriptions(groupID: group.id)
            for sub in subscriptions {
                products.append(PricingProduct(
                    id: sub.id, appID: appID, productID: sub.attributes?.productId,
                    name: sub.attributes?.name ?? sub.attributes?.productId ?? sub.id,
                    kind: .subscription, rawType: "AUTO_RENEWABLE_SUBSCRIPTION",
                    groupID: group.id, groupName: group.attributes?.referenceName,
                    duration: sub.attributes?.subscriptionPeriod, unsupportedReason: nil
                ))
            }
        }
        return products.sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Cheap per-product US listing summary. Does not fetch every territory
    /// or every price ladder and does not mistake preserved prices for public prices.
    func loadUSSummary(product: PricingProduct) async throws -> PricingUSSummary {
        guard product.kind != .unsupported else {
            throw PricingReadError.unsupportedPlan(product.unsupportedReason ?? "unsupported")
        }
        var issues: [PricingReadIssue] = []
        var seeds: [PriceSeed] = []
        var included: [PricingIncludedResource] = []
        switch product.kind {
        case .lifetime:
            if let schedule = try await client.pricingIAPSchedule(iapID: product.id) {
                for manual in [true, false] {
                    do {
                        let page = try await client.pricingIAPPrices(
                            scheduleID: schedule.id, manual: manual, territory: "USA"
                        )
                        seeds += page.items.map {
                            PriceSeed(id: $0.id, territory: $0.relatedID("territory"),
                                point: $0.relatedID("inAppPurchasePricePoint"),
                                start: $0.attributes?.startDate, end: $0.attributes?.endDate,
                                manual: $0.attributes?.manual ?? manual, preserved: nil,
                                plan: nil, origin: manual ? .manualIAP : .automaticIAP)
                        }
                        included += page.included
                    } catch {
                        issues.append(PricingReadIssue(resource: manual ? "US manual" : "US automatic",
                            message: error.localizedDescription))
                    }
                }
            } else {
                issues.append(PricingReadIssue(resource: "US schedule",
                    message: "No configured price schedule; US price is unknown."))
            }
        case .subscription:
            let page = try await client.pricingSubscriptionPrices(
                subscriptionID: product.id, territory: "USA"
            )
            seeds = page.items.map {
                PriceSeed(id: $0.id, territory: $0.relatedID("territory"),
                    point: $0.relatedID("subscriptionPricePoint"),
                    start: $0.attributes?.startDate, end: nil, manual: nil,
                    preserved: $0.attributes?.preserved, plan: $0.attributes?.planType,
                    origin: .subscription)
            }
            included = page.included
        case .unsupported:
            break
        }
        let catalogue = try await territories(refresh: false)
        let usa = catalogue.filter { $0.id == "USA" }.map {
            PricingTerritory(id: $0.id, currency: $0.attributes?.currency,
                available: nil, planType: nil)
        }
        let records = await resolvePrices(
            seeds: seeds, included: included, product: product,
            territories: usa, issues: &issues
        )
        if !records.contains(where: { $0.territoryID == "USA" && $0.preserved != true }) {
            issues.append(PricingReadIssue(resource: "US price",
                message: "No public US price found; do not infer zero."))
        }
        return PricingUSSummary(product: product, prices: records, issues: issues)
    }

    /// Call after choosing a product; never invoked merely to list all products.
    /// Errors affecting a related pricing resource are retained as snapshot issues.
    func loadSnapshot(product: PricingProduct, refresh: Bool = false) async throws -> PricingSnapshot {
        guard product.kind != .unsupported else {
            throw PricingReadError.unsupportedPlan(product.unsupportedReason ?? "unsupported IAP")
        }
        let catalogue = try await territories(refresh: refresh)
        let fetchedAt = Date()
        var issues: [PricingReadIssue] = []
        var availability: Set<String>?
        var planTerritories: [PricingPlanTerritories] = []
        var scheduleID: String?
        var baseTerritoryID: String?
        var seeds: [PriceSeed] = []
        var included: [PricingIncludedResource] = []

        switch product.kind {
        case .lifetime:
            do {
                availability = Set(try await client.pricingIAPAvailableTerritories(iapID: product.id).map(\.id))
            } catch {
                issues.append(PricingReadIssue(resource: "availability", message: error.localizedDescription))
            }
            do {
                if let schedule = try await client.pricingIAPSchedule(iapID: product.id) {
                    scheduleID = schedule.id
                    baseTerritoryID = schedule.relatedID("baseTerritory")
                    if baseTerritoryID == nil {
                        issues.append(PricingReadIssue(resource: "baseTerritory",
                            message: "Apple did not return a configured IAP base territory. Do not assume USA."))
                    }
                    do {
                        let page = try await client.pricingIAPPrices(scheduleID: schedule.id, manual: true)
                        seeds += page.items.map {
                            PriceSeed(id: $0.id, territory: $0.relatedID("territory"),
                                point: $0.relatedID("inAppPurchasePricePoint"),
                                start: $0.attributes?.startDate, end: $0.attributes?.endDate,
                                manual: $0.attributes?.manual ?? true, preserved: nil,
                                plan: nil, origin: .manualIAP)
                        }
                        included += page.included
                    } catch {
                        issues.append(PricingReadIssue(resource: "manualPrices", message: error.localizedDescription))
                    }
                    do {
                        let page = try await client.pricingIAPPrices(scheduleID: schedule.id, manual: false)
                        seeds += page.items.map {
                            PriceSeed(id: $0.id, territory: $0.relatedID("territory"),
                                point: $0.relatedID("inAppPurchasePricePoint"),
                                start: $0.attributes?.startDate, end: $0.attributes?.endDate,
                                manual: $0.attributes?.manual ?? false, preserved: nil,
                                plan: nil, origin: .automaticIAP)
                        }
                        included += page.included
                    } catch {
                        issues.append(PricingReadIssue(resource: "automaticPrices", message: error.localizedDescription))
                    }
                } else {
                    issues.append(PricingReadIssue(resource: "schedule",
                        message: "No IAP price schedule configured; no current price can be inferred."))
                }
            } catch {
                issues.append(PricingReadIssue(resource: "schedule", message: error.localizedDescription))
            }

        case .subscription:
            do {
                planTerritories = try await client.pricingSubscriptionPlanTerritories(subscriptionID: product.id)
                availability = Set(planTerritories.flatMap(\.territoryIDs))
                let unsupported = planTerritories.map(\.planType).filter {
                    $0 != "UPFRONT" && $0 != "MONTHLY"
                }
                if !unsupported.isEmpty {
                    issues.append(PricingReadIssue(resource: "planType",
                        message: "Unrecognized Apple billing plan type(s): \(unsupported.joined(separator: ", "))."))
                }
            } catch {
                issues.append(PricingReadIssue(resource: "planAvailability", message: error.localizedDescription))
            }
            do {
                let page = try await client.pricingSubscriptionPrices(subscriptionID: product.id)
                seeds = page.items.map {
                    PriceSeed(id: $0.id, territory: $0.relatedID("territory"),
                        point: $0.relatedID("subscriptionPricePoint"),
                        start: $0.attributes?.startDate, end: nil, manual: nil,
                        preserved: $0.attributes?.preserved, plan: $0.attributes?.planType,
                        origin: .subscription)
                }
                included = page.included
            } catch {
                issues.append(PricingReadIssue(resource: "subscriptionPrices",
                    message: error.localizedDescription))
            }

        case .unsupported:
            break
        }

        let availableTerritories = catalogue.map {
            PricingTerritory(id: $0.id, currency: $0.attributes?.currency,
                available: availability?.contains($0.id),
                planType: nil)
        }.sorted { $0.id < $1.id }

        let records = await resolvePrices(
            seeds: seeds, included: included, product: product,
            territories: availableTerritories, issues: &issues
        )

        var usPoints: [PricingPoint] = []
        do {
            usPoints = try await loadPoints(product: product, territoryID: "USA")
        } catch {
            issues.append(PricingReadIssue(resource: "US price points", message: error.localizedDescription))
        }

        if !records.contains(where: { $0.territoryID == "USA" && $0.preserved != true }) {
            issues.append(PricingReadIssue(resource: "US price",
                message: "No public US price was found. Require an explicit valid US reference point."))
        }

        // The fingerprint omits fetch times and response ordering. Passes 2/4
        // will extend its scope to cover selected-point and write-plan state.
        let fingerprint = Self.fingerprint(
            schedule: scheduleID, base: baseTerritoryID,
            territories: availableTerritories, plans: planTerritories, prices: records
        )
        return PricingSnapshot(
            accountScope: client.pricingAccountScope, product: product,
            fetchedAt: fetchedAt, territories: availableTerritories,
            planTerritories: planTerritories, baseTerritoryID: baseTerritoryID,
            scheduleID: scheduleID, prices: records,
            usPoints: usPoints, issues: issues, semanticFingerprint: fingerprint
        )
    }

    // On-demand ladders: Pass 2 can prefetch territory-specific data with a
    // concurrency bound; Pass 1 does not eagerly fetch ~175 price ladders.
    func loadPoints(product: PricingProduct, territoryID: String) async throws -> [PricingPoint] {
        let page = try await client.pricingPoints(for: product, territory: territoryID)
        let includedCurrencies = Dictionary(uniqueKeysWithValues: page.included.compactMap {
            resource -> (String, String)? in
            guard resource.type == "territories", let currency = resource.attributes?.currency
            else { return nil }
            return (resource.id, currency)
        })
        let fallbackCurrency = try await territories(refresh: false)
            .first(where: { $0.id == territoryID })?.attributes?.currency
        return page.items.compactMap { item in
            guard let rawAmount = PricingDecimal.parse(item.attributes?.customerPrice),
                  let territory = item.relatedID("territory"),
                  territory == territoryID else { return nil }
            return PricingPoint(
                id: item.id, productID: product.id, territoryID: territory,
                planType: nil, currency: includedCurrencies[territory] ?? fallbackCurrency,
                customerPrice: rawAmount
            )
        }.sorted {
            if $0.customerPrice != $1.customerPrice { return $0.customerPrice < $1.customerPrice }
            return $0.id < $1.id
        }
    }

    func loadEqualizedPoints(product: PricingProduct, sourcePointID: String) async throws -> [PricingPoint] {
        let page = try await client.pricingEqualizations(pointID: sourcePointID, kind: product.kind)
        let currencies = Dictionary(uniqueKeysWithValues: page.included.compactMap {
            resource -> (String, String)? in
            guard resource.type == "territories", let currency = resource.attributes?.currency
            else { return nil }
            return (resource.id, currency)
        })
        return page.items.compactMap { item in
            guard let territory = item.relatedID("territory"),
                  let amount = PricingDecimal.parse(item.attributes?.customerPrice) else { return nil }
            return PricingPoint(id: item.id, productID: product.id, territoryID: territory,
                planType: nil, currency: currencies[territory], customerPrice: amount)
        }.sorted {
            $0.territoryID == $1.territoryID ? $0.id < $1.id : $0.territoryID < $1.territoryID
        }
    }

    func invalidateCaches() {
        territoryCache = nil
    }

    private func territories(refresh: Bool) async throws -> [AppStoreConnectAPIClient.TerritoryResource] {
        if !refresh, let territoryCache { return territoryCache }
        let result = try await client.pricingTerritories()
        territoryCache = result
        return result
    }

    private struct PriceSeed: Sendable {
        let id: String
        let territory: String?
        let point: String?
        let start: String?
        let end: String?
        let manual: Bool?
        let preserved: Bool?
        let plan: String?
        let origin: PricingPriceOrigin
    }

    private func resolvePrices(
        seeds: [PriceSeed], included: [PricingIncludedResource],
        product: PricingProduct, territories: [PricingTerritory],
        issues: inout [PricingReadIssue]
    ) async -> [PricingPriceRecord] {
        var pointDetails: [String: (Decimal, String?)] = [:]
        var territoryByPoint: [String: String] = [:]
        let currencies = Dictionary(uniqueKeysWithValues: territories.map { ($0.id, $0.currency) })
        for resource in included {
            guard resource.type == "inAppPurchasePricePoints" ||
                  resource.type == "subscriptionPricePoints" else { continue }
            if let amount = PricingDecimal.parse(resource.attributes?.customerPrice) {
                pointDetails[resource.id] = (amount, resource.relatedID("territory"))
            }
            if let territory = resource.relatedID("territory") {
                territoryByPoint[resource.id] = territory
            }
        }
        // A response's included collection can be capped; resolve missing point
        // resources in bounded batches rather than silently treating them as free.
        let missing = Array(Set(seeds.compactMap(\.point).filter {
            pointDetails[$0] == nil || (pointDetails[$0]?.1 == nil && territoryByPoint[$0] == nil)
        })).sorted()
        for batchStart in stride(from: 0, to: missing.count, by: 4) {
            let batch = Array(missing[batchStart..<min(batchStart + 4, missing.count)])
            let responses = await withTaskGroup(
                of: (String, AppStoreConnectAPIClient.PricePointResource?, String?).self,
                returning: [(String, AppStoreConnectAPIClient.PricePointResource?, String?)].self
            ) { group in
                for point in batch {
                    group.addTask { [client] in
                        do { return (point, try await client.pricingPoint(id: point, kind: product.kind), nil) }
                        catch { return (point, nil, error.localizedDescription) }
                    }
                }
                var completed: [(String, AppStoreConnectAPIClient.PricePointResource?, String?)] = []
                for await response in group { completed.append(response) }
                return completed
            }
            for (point, resource, error) in responses {
                if let resource, let value = PricingDecimal.parse(resource.attributes?.customerPrice) {
                    pointDetails[point] = (value, resource.relatedID("territory"))
                    if let territory = resource.relatedID("territory") {
                        territoryByPoint[point] = territory
                    }
                } else {
                    issues.append(PricingReadIssue(resource: "point \(point)",
                        message: error ?? "Apple returned a missing or invalid point amount."))
                }
            }
        }
        return seeds.map { seed in
            let territory = seed.territory ?? seed.point.flatMap { territoryByPoint[$0] }
            if territory == nil {
                issues.append(PricingReadIssue(resource: "price \(seed.id)",
                    message: "Price territory could not be resolved."))
            }
            let value = seed.point.flatMap { pointDetails[$0]?.0 }
            if value == nil {
                issues.append(PricingReadIssue(resource: "price \(seed.id)",
                    message: "Missing valid price amount; not treated as zero."))
            }
            return PricingPriceRecord(
                id: seed.id, territoryID: territory, pricePointID: seed.point,
                customerPrice: value, currency: territory.flatMap { currencies[$0] } ?? nil,
                startDate: seed.start, endDate: seed.end, preserved: seed.preserved,
                manual: seed.manual, planType: seed.plan, origin: seed.origin
            )
        }.sorted {
            let a = [$0.territoryID ?? "", $0.planType ?? "", $0.startDate ?? "", $0.id]
            let b = [$1.territoryID ?? "", $1.planType ?? "", $1.startDate ?? "", $1.id]
            return a.lexicographicallyPrecedes(b)
        }
    }

    private static func fingerprint(
        schedule: String?, base: String?, territories: [PricingTerritory],
        plans: [PricingPlanTerritories], prices: [PricingPriceRecord]
    ) -> String {
        var parts = ["schedule=\(schedule ?? "-")", "base=\(base ?? "-")"]
        for territory in territories.sorted(by: { $0.id < $1.id }) {
            parts.append("t:\(territory.id):\(territory.currency ?? "-"):\(territory.available.map(String.init) ?? "?")")
        }
        for plan in plans.sorted(by: { $0.planType < $1.planType }) {
            parts.append("p:\(plan.planType):\(plan.territoryIDs.sorted().joined(separator: ","))")
        }
        for price in prices.sorted(by: { $0.id < $1.id }) {
            let amount = price.customerPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? "?"
            parts.append("r:\(price.id):\(price.territoryID ?? "?"):\(price.pricePointID ?? "?"):\(amount):\(price.startDate ?? ""):\(price.endDate ?? ""):\(price.preserved.map(String.init) ?? "?"):\(price.manual.map(String.init) ?? "?"):\(price.planType ?? "?"):\(price.origin.rawValue)")
        }
        return SHA256.hash(data: Data(parts.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
