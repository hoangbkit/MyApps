import Foundation

// Read-only App Store Connect pricing endpoints. No POST/PATCH/DELETE methods exist here.
// Uses the existing client's JWT, URLSession, error handling and trusted-host policy.
extension AppStoreConnectAPIClient {
    typealias IAPResource = PricingWireResource<PricingIAPAttributes>
    typealias GroupResource = PricingWireResource<PricingGroupAttributes>
    typealias SubscriptionResource = PricingWireResource<PricingSubscriptionAttributes>
    typealias TerritoryResource = PricingWireResource<PricingTerritoryAttributes>
    typealias PricePointResource = PricingWireResource<PricingPricePointAttributes>
    typealias IAPPriceResource = PricingWireResource<PricingIAPPriceAttributes>
    typealias SubscriptionPriceResource = PricingWireResource<PricingSubscriptionPriceAttributes>
    typealias ScheduleResource = PricingWireResource<PricingOpaqueAttributes>
    typealias AvailabilityResource = PricingWireResource<PricingAvailabilityAttributes>
    typealias PlanResource = PricingWireResource<PricingPlanAvailabilityAttributes>

    // A page's "included" array is not the whole related collection. Always
    // exhaust primary pagination; use explicit relationship collection reads below.
    func pricingPages<Item: Decodable & Sendable>(
        path: String, query: [URLQueryItem] = []
    ) async throws -> (items: [Item], included: [PricingIncludedResource]) {
        var url = try apiURL(path: path, query: query)
        var visited = Set<URL>()
        var items: [Item] = []
        var included: [PricingIncludedResource] = []
        while visited.insert(url).inserted {
            try Task.checkCancellation()
            let page: PricingPage<Item> = try await get(url: url)
            items.append(contentsOf: page.data)
            included.append(contentsOf: page.included ?? [])
            guard let next = page.links?.next else { return (items, included) }
            guard let nextURL = URL(string: next, relativeTo: url)?.absoluteURL else {
                throw AppStoreConnectAPIError.invalidResponse
            }
            // get(url:) independently verifies HTTPS and the exact Apple API host.
            url = nextURL
        }
        throw AppStoreConnectAPIError.invalidResponse
    }

    func pricingIAPs(appID: String) async throws -> [IAPResource] {
        let result: (items: [IAPResource], included: [PricingIncludedResource]) =
            try await pricingPages(path: "/v1/apps/\(appID)/inAppPurchasesV2",
                query: [URLQueryItem(name: "limit", value: "200")])
        return result.items
    }

    func pricingGroups(appID: String) async throws -> [GroupResource] {
        let result: (items: [GroupResource], included: [PricingIncludedResource]) =
            try await pricingPages(path: "/v1/apps/\(appID)/subscriptionGroups",
                query: [URLQueryItem(name: "limit", value: "200")])
        return result.items
    }

    func pricingSubscriptions(groupID: String) async throws -> [SubscriptionResource] {
        let result: (items: [SubscriptionResource], included: [PricingIncludedResource]) =
            try await pricingPages(path: "/v1/subscriptionGroups/\(groupID)/subscriptions",
                query: [URLQueryItem(name: "limit", value: "200")])
        return result.items
    }

    func pricingTerritories() async throws -> [TerritoryResource] {
        let result: (items: [TerritoryResource], included: [PricingIncludedResource]) =
            try await pricingPages(path: "/v1/territories", query: [
                URLQueryItem(name: "limit", value: "200")
            ])
        return result.items
    }

    func pricingIAPSchedule(iapID: String) async throws -> ScheduleResource? {
        do {
            let response: PricingSingle<ScheduleResource> =
                try await get(path: "/v2/inAppPurchases/\(iapID)/iapPriceSchedule")
            return response.data
        } catch AppStoreConnectAPIError.httpStatus(404) {
            return nil // Unconfigured schedule is not a zero-dollar price.
        }
    }

    func pricingIAPPrices(scheduleID: String, manual: Bool, territory: String? = nil) async throws
        -> (items: [IAPPriceResource], included: [PricingIncludedResource]) {
        let relation = manual ? "manualPrices" : "automaticPrices"
        var query = [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "include", value: "inAppPurchasePricePoint,territory")
        ]
        if let territory { query.append(URLQueryItem(name: "filter[territory]", value: territory)) }
        return try await pricingPages(
            path: "/v1/inAppPurchasePriceSchedules/\(scheduleID)/\(relation)",
            query: query
        )
    }

    func pricingSubscriptionPrices(subscriptionID: String, territory: String? = nil) async throws
        -> (items: [SubscriptionPriceResource], included: [PricingIncludedResource]) {
        var query = [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "include", value: "subscriptionPricePoint,territory")
        ]
        if let territory { query.append(URLQueryItem(name: "filter[territory]", value: territory)) }
        return try await pricingPages(
            path: "/v1/subscriptions/\(subscriptionID)/prices", query: query
        )
    }

    func pricingPoints(for product: PricingProduct, territory: String) async throws
        -> (items: [PricePointResource], included: [PricingIncludedResource]) {
        let path: String
        switch product.kind {
        case .lifetime: path = "/v2/inAppPurchases/\(product.id)/pricePoints"
        case .subscription: path = "/v1/subscriptions/\(product.id)/pricePoints"
        case .unsupported: throw PricingReadError.unsupportedPlan(product.rawType ?? "unknown")
        }
        return try await pricingPages(path: path, query: [
            URLQueryItem(name: "filter[territory]", value: territory),
            URLQueryItem(name: "include", value: "territory"),
            URLQueryItem(name: "limit", value: "8000")
        ])
    }

    func pricingPoint(id: String, kind: PricingProductKind) async throws -> PricePointResource {
        let path: String
        switch kind {
        case .lifetime: path = "/v1/inAppPurchasePricePoints/\(id)"
        case .subscription: path = "/v1/subscriptionPricePoints/\(id)"
        case .unsupported: throw PricingReadError.unsupportedPlan("unsupported product")
        }
        let response: PricingSingle<PricePointResource> = try await get(path: path)
        guard let resource = response.data else { throw PricingReadError.missingResource(path) }
        return resource
    }

    // Standard subscription price equalizations are JSON. Adjusted equalizations
    // can respond text/csv and require plan-aware interpretation; do not guess.
    func pricingEqualizations(pointID: String, kind: PricingProductKind)
        async throws -> (items: [PricePointResource], included: [PricingIncludedResource]) {
        let path: String
        switch kind {
        case .lifetime: path = "/v1/inAppPurchasePricePoints/\(pointID)/equalizations"
        case .subscription: path = "/v1/subscriptionPricePoints/\(pointID)/equalizations"
        case .unsupported: throw PricingReadError.unsupportedPlan("unsupported product")
        }
        return try await pricingPages(path: path, query: [
            URLQueryItem(name: "include", value: "territory"),
            URLQueryItem(name: "limit", value: "8000")
        ])
    }

    func pricingIAPAvailableTerritories(iapID: String) async throws -> [TerritoryResource] {
        let response: PricingSingle<AvailabilityResource> =
            try await get(path: "/v2/inAppPurchases/\(iapID)/inAppPurchaseAvailability")
        guard let availability = response.data else {
            throw PricingReadError.incompleteAvailability(iapID)
        }
        let result: (items: [TerritoryResource], included: [PricingIncludedResource]) =
            try await pricingPages(
                path: "/v1/inAppPurchaseAvailabilities/\(availability.id)/availableTerritories",
                query: [URLQueryItem(name: "limit", value: "200")]
            )
        return result.items
    }

    func pricingSubscriptionPlanTerritories(subscriptionID: String) async throws
        -> [PricingPlanTerritories] {
        let response: (items: [PlanResource], included: [PricingIncludedResource]) =
            try await pricingPages(path: "/v1/subscriptions/\(subscriptionID)/planAvailabilities",
                query: [URLQueryItem(name: "limit", value: "200")])
        guard !response.items.isEmpty else {
            // The deprecated availability endpoint is NOT evidence of plan type.
            throw PricingReadError.incompleteAvailability(subscriptionID)
        }
        var result: [PricingPlanTerritories] = []
        for plan in response.items {
            guard let planType = plan.attributes?.planType else {
                throw PricingReadError.unsupportedPlan("unknown for \(plan.id)")
            }
            let collection: (items: [TerritoryResource], included: [PricingIncludedResource]) =
                try await pricingPages(
                    path: "/v1/subscriptionPlanAvailabilities/\(plan.id)/availableTerritories",
                    query: [URLQueryItem(name: "limit", value: "200")]
                )
            result.append(PricingPlanTerritories(
                planType: planType,
                territoryIDs: collection.items.map(\.id).sorted()
            ))
        }
        return result.sorted { $0.planType < $1.planType }
    }
}
