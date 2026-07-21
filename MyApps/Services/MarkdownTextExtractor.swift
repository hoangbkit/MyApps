import Foundation

enum MarkdownTextExtractor {
    static func excerpt(from markdown: String, characterLimit: Int = 120) -> String {
        let text = plainText(from: markdown)
        guard text.count > characterLimit else { return text }

        let endIndex = text.index(text.startIndex, offsetBy: characterLimit)
        let excerpt = String(text[..<endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return excerpt + "…"
    }

    static func plainText(from markdown: String) -> String {
        var result: [String] = []
        var isInCodeFence = false

        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                isInCodeFence.toggle()
                continue
            }

            if isInCodeFence {
                if !trimmed.isEmpty {
                    result.append(trimmed)
                }
                continue
            }

            if isAttachmentImageLine(trimmed) {
                result.append("Image")
                continue
            }

            if let task = MarkdownTaskParser.task(at: 0, in: rawLine) {
                let text = task.text.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    result.append(text)
                }
                continue
            }

            var line = trimmed
            while line.hasPrefix("#") { line.removeFirst() }
            line = line.trimmingCharacters(in: .whitespaces)

            for prefix in ["> ", "- ", "* "] where line.hasPrefix(prefix) {
                line.removeFirst(prefix.count)
                break
            }

            line = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")

            if !line.isEmpty {
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }

    static func attachmentIDs(in markdown: String) -> Set<UUID> {
        let pattern = #"attachment://([0-9A-Fa-f-]{36})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)

        return Set(regex.matches(in: markdown, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: markdown) else { return nil }
            return UUID(uuidString: String(markdown[idRange]))
        })
    }

    private static func isAttachmentImageLine(_ line: String) -> Bool {
        line.hasPrefix("![") && line.contains("](attachment://") && line.hasSuffix(")")
    }
}
