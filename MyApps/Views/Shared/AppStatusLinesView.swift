import SwiftUI

struct AppStatusLinesView: View {
    let items: [AppStatusItem]

    private var status: ProjectStatus? {
        items.compactMap(\.status).first
    }

    private var textItems: [AppStatusItem] {
        items.filter { $0.text != nil }
    }

    private var lines: [[AppStatusItem]] {
        if textItems.count <= 3 {
            return textItems.isEmpty ? [[]] : [textItems]
        }

        return stride(from: 0, to: textItems.count, by: 2).map { startIndex in
            Array(textItems[startIndex..<min(startIndex + 2, textItems.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines.indices, id: \.self) { lineIndex in
                HStack(spacing: 7) {
                    if lineIndex == 0, let status {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Status: \(status.rawValue)")
                    }

                    ForEach(lines[lineIndex].indices, id: \.self) { itemIndex in
                        if itemIndex > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                        }

                        if let text = displayText(for: lines[lineIndex][itemIndex]) {
                            Text(text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                }
            }
        }
        .font(.system(size: 16, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func displayText(for item: AppStatusItem) -> String? {
        guard let text = item.text else { return nil }

        switch item.field {
        case .liveVersion:
            return text.normalizedVersionPrefix("v")
        case .developmentVersion:
            return text.normalizedVersionPrefix("P")
        default:
            return text
        }
    }
}

private extension String {
    func normalizedVersionPrefix(_ prefix: Character) -> String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }

        if value.first?.lowercased() == prefix.lowercased() {
            return String(prefix) + String(value.dropFirst())
        }
        return String(prefix) + value
    }
}
