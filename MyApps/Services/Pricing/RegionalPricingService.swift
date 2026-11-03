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
                groupID: nil, groupName: nil, serviceLevel: nil, duration: nil,
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
                    serviceLevel: sub.attributes?.groupLevel.map(String.init),
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
                        do {
                            baseTerritoryID = try await client.pricingBaseTerritory(scheduleID: schedule.id)?.id
                        } catch {
                            issues.append(PricingReadIssue(resource: "baseTerritory",
                                message: error.localizedDescription))
                        }
                    }
                    if baseTerritoryID == nil {
                        issues.append(PricingReadIssue(resource: "baseTerritory",
                            message: "The configured base territory is unknown; USA cannot be assumed."))
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
            // Normalize the US anchor with the same verified plan identity as
            // references, country ladders, overrides, and submission rows.
            let standardPlan: String? = product.kind == .subscription &&
                Set(planTerritories.map(\.planType)) == ["UPFRONT"] ? "UPFRONT" : nil
            usPoints = try await loadPoints(product: product, territoryID: "USA",
                                           planType: standardPlan)
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
    func loadPoints(product: PricingProduct, territoryID: String,
                    planType: String? = nil) async throws -> [PricingPoint] {
        let page = try await client.pricingPoints(for: product, territory: territoryID)
        // Paginated JSON:API includes can repeat the same territory resource.
        // Never use uniqueKeysWithValues here (duplicate IDs would trap).
        var includedCurrencies: [String: String] = [:]
        for resource in page.included where resource.type == "territories" {
            if let currency = resource.attributes?.currency {
                if let existing = includedCurrencies[resource.id], existing != currency {
                    throw PricingReadError.unsupportedRepresentation(
                        "Conflicting currencies for Apple territory \(resource.id).")
                }
                includedCurrencies[resource.id] = currency
            }
        }
        let fallbackCurrency = try await territories(refresh: false)
            .first(where: { $0.id == territoryID })?.attributes?.currency
        let expectedType = product.kind == .lifetime ? "inAppPurchasePricePoints" : "subscriptionPricePoints"
        var pointsByID: [String: PricingPoint] = [:]
        for item in page.items {
            guard item.type == expectedType, !item.id.isEmpty else {
                throw PricingReadError.unsupportedRepresentation(
                    "Apple returned an unexpected price-point resource for \(territoryID).")
            }
            guard let rawAmount = PricingDecimal.parse(item.attributes?.customerPrice, allowingZero: true) else {
                throw PricingReadError.unsupportedRepresentation(
                    "An Apple price point for \(territoryID) has a missing or invalid amount.")
            }
            // The product-scoped collection is explicitly filtered to this
            // territory. That request scope also identifies link-only rows;
            // reject contradictory territory data instead of guessing an ID.
            let territory = item.relatedID("territory") ?? territoryID
            guard territory == territoryID,
                  let currency = includedCurrencies[territory] ?? fallbackCurrency else {
                throw PricingReadError.unsupportedRepresentation(
                    "Apple price-point territory or currency does not match \(territoryID).")
            }
            // A known zero point is intentionally ineligible for this paid
            // pricing tool, not evidence that the entire ladder is corrupt.
            guard rawAmount > 0 else { continue }
            let point = PricingPoint(
                id: item.id, productID: product.id, territoryID: territory,
                planType: planType, currency: currency,
                customerPrice: rawAmount
            )
            if let prior = pointsByID[item.id], prior != point {
                throw PricingReadError.unsupportedRepresentation(
                    "Apple returned conflicting values for a price point in \(territoryID).")
            }
            pointsByID[item.id] = point
        }
        let points = pointsByID.values.sorted {
            if $0.customerPrice != $1.customerPrice { return $0.customerPrice < $1.customerPrice }
            return $0.id < $1.id
        }
        guard !points.isEmpty else {
            throw PricingReadError.unsupportedRepresentation(
                "Apple returned no selectable positive price points for \(territoryID)."
            )
        }
        return points
    }

    func loadEqualizedPoints(product: PricingProduct, sourcePointID: String) async throws -> [PricingPoint] {
        let page: (items: [AppStoreConnectAPIClient.PricePointResource],
                   included: [PricingIncludedResource])
        do {
            page = try await client.pricingEqualizations(
                pointID: sourcePointID, kind: product.kind)
        } catch AppStoreConnectAPIError.unsupportedPricingMediaType(let mime)
                    where mime == "text/csv" || mime == "application/csv" {
            return try await equalizationsFromLinkage(
                product: product, sourcePointID: sourcePointID)
        }
        // Apple may omit included territory resources even when a price point
        // contains the relationship. Fall back to the separately fetched catalog.
        let catalogue = try await territories(refresh: false)
        var currencies: [String: String] = [:]
        for territory in catalogue {
            if let currency = territory.attributes?.currency { currencies[territory.id] = currency }
        }
        for resource in page.included where resource.type == "territories" {
            if let currency = resource.attributes?.currency { currencies[resource.id] = currency }
        }
        let points: [PricingPoint] = page.items.compactMap { item in
            guard let territory = item.relatedID("territory"),
                  let amount = PricingDecimal.parse(item.attributes?.customerPrice) else { return nil }
            return PricingPoint(id: item.id, productID: product.id, territoryID: territory,
                planType: nil, currency: currencies[territory], customerPrice: amount)
        }.sorted {
            $0.territoryID == $1.territoryID ? $0.id < $1.id : $0.territoryID < $1.territoryID
        }
        guard !points.isEmpty, points.count == page.items.count,
              Set(points.map(\.territoryID)).count == points.count,
              points.allSatisfy({ $0.currency != nil }) else {
            throw PricingReadError.unsupportedRepresentation(
                "Apple equalization returned missing, duplicate, or conflicting territory/price data."
            )
        }
        return points
    }

    private func equalizationsFromLinkage(
        product: PricingProduct, sourcePointID: String
    ) async throws -> [PricingPoint] {
        let links = try await client.pricingEqualizationIDs(
            pointID: sourcePointID, kind: product.kind)
        let expected = product.kind == .lifetime
            ? "inAppPurchasePricePoints" : "subscriptionPricePoints"
        guard !links.isEmpty, links.allSatisfy({ $0.type == expected }),
              Set(links.map(\.id)).count == links.count else {
            throw PricingReadError.unsupportedRepresentation(
                "Apple returned empty, duplicate, or unexpected equalization IDs.")
        }
        let catalogue = try await territories(refresh: false)
        var currencies: [String: String] = [:]
        for territory in catalogue {
            guard let currency = territory.attributes?.currency else { continue }
            if let existing = currencies[territory.id], existing != currency {
                throw PricingReadError.unsupportedRepresentation(
                    "Conflicting Apple currency for \(territory.id).")
            }
            currencies[territory.id] = currency
        }
        var result: [PricingPoint] = []
        for start in stride(from: 0, to: links.count, by: 4) {
            try Task.checkCancellation()
            let slice = Array(links[start..<min(start + 4, links.count)])
            let details = try await withThrowingTaskGroup(
                of: AppStoreConnectAPIClient.PricePointResource.self,
                returning: [AppStoreConnectAPIClient.PricePointResource].self
            ) { group in
                for id in slice {
                    group.addTask { [client] in
                        try await client.pricingPoint(id: id.id, kind: product.kind)
                    }
                }
                var completed: [AppStoreConnectAPIClient.PricePointResource] = []
                for try await item in group { completed.append(item) }
                return completed
            }
            guard Set(details.map(\.id)) == Set(slice.map(\.id)) else {
                throw PricingReadError.unsupportedRepresentation(
                    "Apple returned price-point details inconsistent with equalization IDs.")
            }
            for detail in details {
                guard let territoryID = detail.relatedID("territory"),
                      let currency = currencies[territoryID],
                      let price = PricingDecimal.parse(detail.attributes?.customerPrice) else {
                    throw PricingReadError.unsupportedRepresentation(
                        "Equalized Apple point has no verified territory, currency, or amount.")
                }
                result.append(PricingPoint(
                    id: detail.id, productID: product.id, territoryID: territoryID,
                    planType: nil, currency: currency, customerPrice: price))
            }
        }
        guard result.count == links.count,
              Set(result.map(\.territoryID)).count == result.count else {
            throw PricingReadError.unsupportedRepresentation(
                "Apple returned conflicting or incomplete territory equalizations.")
        }
        return result.sorted { $0.territoryID < $1.territoryID }
    }

    /// Prepare all network-dependent inputs before the pure Pass 2 engine runs.
    /// Never derive Apple point identities from an encoded price or cached discount.
    func loadReferenceSet(
        snapshot: PricingSnapshot,
        selectedUSPoint: PricingPoint,
        mapping: RegionalPricingMapping,
        preset: RegionalPricingPreset = .balanced,
        roundingPolicy: RegionalPriceRoundingPolicy = .nearestCommon,
        overrides: [RegionalPricingOverride] = []
    ) async throws -> RegionalPricingReferenceSet {
        guard selectedUSPoint.productID == snapshot.product.id,
              selectedUSPoint.territoryID == "USA",
              snapshot.usPoints.contains(where: { $0.id == selectedUSPoint.id }) else {
            throw RegionalPricingError.invalidReference("US point is not part of the selected product.")
        }
        let plan: String?
        if snapshot.product.kind == .subscription {
            let types = Set(snapshot.planTerritories.map(\.planType))
            guard types == ["UPFRONT"] else {
                throw PricingReadError.unsupportedPlan(
                    "Only confirmed standard UPFRONT subscriptions are supported; additional plans need adjusted equalizations."
                )
            }
            plan = "UPFRONT"
        } else {
            plan = nil
        }
        var issues: [String] = []
        let rawEqualized: [PricingPoint]
        do {
            rawEqualized = try await loadEqualizedPoints(
                product: snapshot.product, sourcePointID: selectedUSPoint.id)
        } catch {
            // Missing/CSV/ambiguous equalization is never replaced by naive FX.
            rawEqualized = []
            issues.append("GLOBAL: Apple US-point equalizations unavailable: \(error.localizedDescription)")
        }
        func typed(_ point: PricingPoint) -> PricingPoint {
            PricingPoint(id: point.id, productID: point.productID,
                territoryID: point.territoryID, planType: plan,
                currency: point.currency, customerPrice: point.customerPrice)
        }
        let equalized = Dictionary(rawEqualized.map { ($0.territoryID, typed($0)) },
                                   uniquingKeysWith: { first, _ in first })
        var ladders: [String: [PricingPoint]] = [:]
        let eligible = snapshot.territories.filter { $0.available != false }.sorted { $0.id < $1.id }
        // Bound networking to four concurrent territory ladders; no eager
        // fetching of ladders for unrelated products.
        for offset in stride(from: 0, to: eligible.count, by: 4) {
            let batch = Array(eligible[offset..<min(offset + 4, eligible.count)])
            let responses = await withTaskGroup(
                of: (String, [PricingPoint]?, String?).self,
                returning: [(String, [PricingPoint]?, String?)].self
            ) { group in
                for territory in batch {
                    group.addTask { [self] in
                        do {
                            let points = try await loadPoints(product: snapshot.product,
                                                              territoryID: territory.id)
                            return (territory.id, points, nil)
                        } catch {
                            return (territory.id, nil, error.localizedDescription)
                        }
                    }
                }
                var collected: [(String, [PricingPoint]?, String?)] = []
                for await response in group { collected.append(response) }
                return collected
            }
            for (territory, points, failure) in responses {
                if let points {
                    ladders[territory] = points.map(typed)
                } else {
                    issues.append("\(territory): \(failure ?? "Price ladder unavailable.")")
                }
            }
        }

        // Select the actual configured base's proposal first, then ask Apple
        // for THAT base point's automatic equalizations. This is deliberately
        // distinct from the US reference when baseTerritory != USA.
        var baseAutomatic: [String: PricingPoint]? = nil
        if snapshot.product.kind == .lifetime {
            if snapshot.baseTerritoryID == "USA" {
                baseAutomatic = equalized
            } else if let base = snapshot.baseTerritoryID,
                      let baseReference = equalized[base],
                      let baseLadder = ladders[base], !baseLadder.isEmpty {
                let baseMapping = mapping.assignment(for: base)
                let factor = (baseMapping == nil || baseMapping?.needsReview == true)
                    ? Decimal(1) : preset.factors[baseMapping?.tier ?? 1] ?? 1
                let target = baseReference.customerPrice * factor
                let saved = overrides.first { $0.territoryID == base && $0.planType == nil }
                let chosen = saved.flatMap { saved in
                    baseLadder.first { $0.id == saved.point.id &&
                        $0.customerPrice == saved.point.customerPrice }
                } ?? RegionalPricingEngine.roundedPrice(
                    to: target, points: baseLadder, referenceID: baseReference.id,
                    policy: roundingPolicy).point
                if let chosen {
                    do {
                        let result = try await loadEqualizedPoints(
                            product: snapshot.product, sourcePointID: chosen.id)
                        baseAutomatic = Dictionary(
                            result.map { ($0.territoryID, typed($0)) },
                            uniquingKeysWith: { first, _ in first }
                        )
                    } catch {
                        issues.append("GLOBAL: Configured-base equalizations unavailable: \(error.localizedDescription)")
                    }
                }
            } else {
                issues.append("GLOBAL: Configured base price point missing; automatic consequences unknown.")
            }
        }
        return RegionalPricingReferenceSet(
            sourceUSPoint: typed(selectedUSPoint),
            equalizedByTerritory: equalized,
            laddersByTerritory: ladders,
            automaticFromConfiguredBase: baseAutomatic,
            planType: plan,
            readIssues: issues.sorted()
        )
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
        // Do not trap if Apple's paged territory catalog repeats an ID.
        var currencies: [String: String?] = [:]
        for territory in territories {
            currencies[territory.id] = territory.currency
        }
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
        // Apple documents lifetime point lookup through the product's
        // territory-filtered pricePoints collection, not a standalone IAP
        // point detail read. Resolve missing amounts from that authoritative
        // list. Subscription point details have a documented single GET.
        for seed in seeds {
            if let point = seed.point, let territory = seed.territory {
                territoryByPoint[point] = territory
            }
        }
        if product.kind == .lifetime {
            var ladderFailures: [(territory: String, message: String)] = []
            let neededTerritories = Array(Set(seeds.compactMap { seed -> String? in
                guard let point = seed.point, pointDetails[point] == nil else { return nil }
                return seed.territory ?? territoryByPoint[point]
            })).sorted()
            for start in stride(from: 0, to: neededTerritories.count, by: 4) {
                let batch = Array(neededTerritories[start..<min(start + 4, neededTerritories.count)])
                let results = await withTaskGroup(
                    of: (String, [PricingPoint]?, String?).self,
                    returning: [(String, [PricingPoint]?, String?)].self
                ) { group in
                    for territory in batch {
                        group.addTask { [self] in
                            do {
                                return (territory,
                                    try await loadPoints(product: product, territoryID: territory), nil)
                            } catch {
                                return (territory, nil, error.localizedDescription)
                            }
                        }
                    }
                    var completed: [(String, [PricingPoint]?, String?)] = []
                    for await item in group { completed.append(item) }
                    return completed
                }
                for (territory, ladder, failure) in results {
                    if let ladder {
                        for point in ladder {
                            pointDetails[point.id] = (point.customerPrice, territory)
                            territoryByPoint[point.id] = territory
                        }
                    } else {
                        ladderFailures.append((territory,
                            failure ?? "Unable to resolve lifetime price amounts."))
                    }
                }
            }
            if let first = ladderFailures.sorted(by: { $0.territory < $1.territory }).first {
                issues.append(PricingReadIssue(resource: "Lifetime price points",
                    message: "Price-point reads failed for \(ladderFailures.count) storefronts. First failure (\(first.territory)): \(first.message)"))
            }
        } else {
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
        }
        var missingTerritories = 0
        var missingAmounts = 0
        let records = seeds.map { seed in
            let territory = seed.territory ?? seed.point.flatMap { territoryByPoint[$0] }
            if territory == nil {
                missingTerritories += 1
            }
            let value = seed.point.flatMap { pointDetails[$0]?.0 }
            if value == nil {
                missingAmounts += 1
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
        if missingTerritories > 0 {
            issues.append(PricingReadIssue(resource: "Price territories",
                message: "Apple territory relationships could not be resolved for \(missingTerritories) price records. Refresh pricing to retry."))
        }
        if missingAmounts > 0 {
            issues.append(PricingReadIssue(resource: "Price amounts",
                message: "Amounts could not be resolved for \(missingAmounts) price records. These prices remain unknown and cannot be submitted."))
        }
        return records
    }

    private static func fingerprint(
        schedule: String?, base: String?, territories: [PricingTerritory],
        plans: [PricingPlanTerritories], prices: [PricingPriceRecord]
    ) -> String {
        var parts = ["schedule=\(schedule ?? "-")", "base=\(base ?? "-")"]
        for territory in territories.sorted(by: { $0.id < $1.id }) {
            parts.append("t:\(territory.id):\(territory.currency ?? "-"):\(territory.available.map { $0 ? "true" : "false" } ?? "?")")
        }
        for plan in plans.sorted(by: { $0.planType < $1.planType }) {
            parts.append("p:\(plan.planType):\(plan.territoryIDs.sorted().joined(separator: ","))")
        }
        for price in prices.sorted(by: { $0.id < $1.id }) {
            let amount = price.customerPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? "?"
            parts.append("r:\(price.id):\(price.territoryID ?? "?"):\(price.pricePointID ?? "?"):\(amount):\(price.startDate ?? ""):\(price.endDate ?? ""):\(price.preserved.map { $0 ? "true" : "false" } ?? "?"):\(price.manual.map { $0 ? "true" : "false" } ?? "?"):\(price.planType ?? "?"):\(price.origin.rawValue)")
        }
        return SHA256.hash(data: Data(parts.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}



