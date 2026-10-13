import SwiftUI
import UIKit

/// Successful artwork is reused while browsing the App Store tab. URLSession's
/// shared URLCache also avoids repeat downloads across short app sessions.
@MainActor
private enum AppStoreArtworkCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
}

/// App Store Connect artwork → public App Store artwork → deterministic gradient.
/// The public URL is also tried when the primary image CDN request fails.
struct AppStoreAppIconView: View {
    let name: String
    let url: URL?
    var fallbackURL: URL? = nil
    var size: CGFloat = 52
    var appID: String? = nil

    @State private var artwork: UIImage?

    private var sources: [URL] {
        var sources: [URL] = []
        for candidate in [url, fallbackURL].compactMap({ $0 }) where !sources.contains(candidate) {
            if Self.isTrustedArtwork(candidate) { sources.append(candidate) }
        }
        return sources
    }

    var body: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                gradientPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true) // The adjacent app name is its accessible label.
        .task(id: sources.map(\.absoluteString).joined(separator: "|")) {
            await loadArtwork()
        }
    }

    private var gradientPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Circle()
                .fill(.white.opacity(0.13))
                .frame(width: size * 1.02, height: size * 1.02)
                .offset(x: -size * 0.34, y: -size * 0.36)

            Text(abbreviation)
                .font(.system(size: size * 0.31, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
    }

    private var gradientColors: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.26, green: 0.36, blue: 0.95), Color(red: 0.46, green: 0.25, blue: 0.78)],
            [Color(red: 0.06, green: 0.63, blue: 0.76), Color(red: 0.10, green: 0.33, blue: 0.68)],
            [Color(red: 0.87, green: 0.30, blue: 0.49), Color(red: 0.59, green: 0.27, blue: 0.76)],
            [Color(red: 0.16, green: 0.62, blue: 0.49), Color(red: 0.05, green: 0.40, blue: 0.54)],
            [Color(red: 0.94, green: 0.55, blue: 0.25), Color(red: 0.84, green: 0.30, blue: 0.41)],
            [Color(red: 0.40, green: 0.49, blue: 0.79), Color(red: 0.19, green: 0.28, blue: 0.55)]
        ]
        // Stable across launches and independent of Swift's randomized hash seed.
        let key = appID ?? name
        let hash = key.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return palettes[Int(hash % UInt64(palettes.count))]
    }

    private var abbreviation: String {
        let parts = name.split(whereSeparator: { $0.isWhitespace })
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    @MainActor
    private func loadArtwork() async {
        artwork = nil
        for source in sources {
            guard !Task.isCancelled else { return }
            let key = source.absoluteString as NSString
            if let cached = AppStoreArtworkCache.images.object(forKey: key) {
                artwork = cached
                return
            }

            do {
                var request = URLRequest(url: source, cachePolicy: .returnCacheDataElseLoad)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      data.count <= 8_000_000,
                      let image = UIImage(data: data) else { continue }
                let cost = Int(image.size.width * image.size.height * 4)
                AppStoreArtworkCache.images.setObject(image, forKey: key, cost: cost)
                artwork = image
                return
            } catch {
                if Task.isCancelled { return }
                // Try the public App Store URL if App Store Connect CDN fails.
            }
        }
        // Neither source is available: leave the attractive gradient visible.
    }

    private static func isTrustedArtwork(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "mzstatic.com" || host.hasSuffix(".mzstatic.com"),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return true
    }
}
