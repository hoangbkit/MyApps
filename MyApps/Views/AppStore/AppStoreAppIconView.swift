import SwiftUI

/// Square app artwork with a consistent fallback for apps that have not
/// uploaded an icon (or whose image CDN request fails).
struct AppStoreAppIconView: View {
    let name: String
    let url: URL?
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.secondary.opacity(0.12))

            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true) // The adjacent app name is its accessible label.
    }

    private var initials: some View {
        Text(abbreviation)
            .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var abbreviation: String {
        let parts = name.split(whereSeparator: { $0.isWhitespace })
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
