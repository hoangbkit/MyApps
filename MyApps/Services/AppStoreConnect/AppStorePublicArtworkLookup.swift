import Foundation

/// Resolves public App Store artwork using exact Apple app IDs, never app-name
/// searches. Public lookup is independent of App Store Connect credentials.
///
/// A single request can carry multiple IDs. Only apps returned with matching
/// IDs (and, when present, matching bundle IDs) are accepted. Unreleased apps
/// naturally have no public artwork.
struct AppStorePublicArtworkLookup: Sendable {
    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let trackId: Int64?
        let bundleId: String?
        let artworkUrl512: URL?
        let artworkUrl100: URL?

        var artworkURL: URL? {
            [artworkUrl512, artworkUrl100].compactMap { $0 }.first(where: Self.isTrustedImage)
        }

        private static func isTrustedImage(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(),
                  host == "mzstatic.com" || host.hasSuffix(".mzstatic.com"),
                  url.user == nil, url.password == nil,
                  url.port == nil || url.port == 443 else { return false }
            return true
        }
    }

    static func lookup(apps: [AppStoreConnectApp]) async -> [String: URL] {
        let byID = Dictionary(uniqueKeysWithValues: apps.compactMap { app -> (String, AppStoreConnectApp)? in
            guard Int64(app.id) != nil else { return nil }
            return (app.id, app)
        })
        var remaining = Set(byID.keys)
        var found: [String: URL] = [:]

        // Exact storefront availability is not encoded in primaryLocale.
        // Try the current region, then common storefronts for globally and
        // locally released apps; don't make a name-based substitution.
        var countries: [String] = []
        for country in [Locale.current.region?.identifier.lowercased(), "us", "vn", "gb"].compactMap({ $0 }) {
            if country.count == 2 && !countries.contains(country) {
                countries.append(country)
            }
        }

        for country in countries where !remaining.isEmpty {
            for group in stride(from: 0, to: remaining.count, by: 40) {
                try? Task.checkCancellation()
                if Task.isCancelled { return found }

                let pending = remaining.sorted()
                guard group < pending.count else { break }
                let slice = Array(pending[group..<min(group + 40, pending.count)])
                guard let records = try? await request(ids: slice, country: country) else { continue }
                for item in records {
                    guard let trackId = item.trackId,
                          let app = byID[String(trackId)],
                          remaining.contains(app.id),
                          let url = item.artworkURL else { continue }

                    if let bundleID = app.attributes.bundleId,
                       let returnedBundle = item.bundleId,
                       bundleID.caseInsensitiveCompare(returnedBundle) != .orderedSame {
                        continue
                    }
                    found[app.id] = url
                }
            }
            remaining.subtract(found.keys)
        }
        return found
    }

    private static func request(ids: [String], country: String) async throws -> [Result] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software")
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              data.count <= 2_000_000 else { return [] }
        return try JSONDecoder().decode(Response.self, from: data).results
    }
}
