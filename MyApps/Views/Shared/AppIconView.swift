import SwiftUI
import UIKit

struct AppIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    let name: String
    let iconData: Data?
    let defaultIconStyle: DefaultAppIconStyle
    var size: CGFloat = 58

    init(app: ManagedApp, size: CGFloat = 58) {
        self.name = app.name
        self.iconData = app.iconData
        self.defaultIconStyle = app.defaultIconStyle
        self.size = size
    }

    nonisolated init(
        name: String,
        iconData: Data?,
        defaultIconStyle: DefaultAppIconStyle = .ocean,
        size: CGFloat = 58
    ) {
        self.name = name
        self.iconData = iconData
        self.defaultIconStyle = defaultIconStyle
        self.size = size
    }

    var body: some View {
        Group {
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.075),
                    lineWidth: 0.75
                )
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10),
            radius: 5,
            y: 2
        )
    }

    private var fallbackIcon: some View {
        ZStack {
            defaultIconStyle.gradient

            Text(monogram)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
    }

    private var monogram: String {
        let words = name.split { !$0.isLetter && !$0.isNumber }

        if words.count >= 2 {
            return String(words.prefix(2).compactMap(\.first)).uppercased()
        }

        guard let word = words.first, let first = word.first else { return "A" }
        let remaining = word.dropFirst()
        let second = remaining.first(where: \.isUppercase) ?? remaining.first
        var characters = [first]
        if let second { characters.append(second) }
        return String(characters).uppercased()
    }
}
