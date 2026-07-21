import Foundation

enum MarkdownListMarker: Hashable {
    case bullet
    case ordered(Int)
    case task(isCompleted: Bool)
}

struct MarkdownListItem: Identifiable, Hashable {
    let id: String
    let lineIndex: Int
    let depth: Int
    var marker: MarkdownListMarker
    var text: String
}

enum MarkdownTableAlignment: Hashable {
    case leading
    case center
    case trailing
}

enum MarkdownImageSource: Hashable {
    case attachment(UUID)
    case remote(String)
}

enum MarkdownBlock: Identifiable, Hashable {
    case heading(id: String, level: Int, text: String)
    case paragraph(id: String, text: String)
    case list(id: String, items: [MarkdownListItem])
    case quote(id: String, text: String)
    case code(id: String, language: String?, text: String)
    case image(id: String, source: MarkdownImageSource, alt: String)
    case table(
        id: String,
        headers: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    )
    case rule(id: String)

    var id: String {
        switch self {
        case let .heading(id, _, _), let .paragraph(id, _), let .list(id, _),
             let .quote(id, _), let .code(id, _, _), let .image(id, _, _),
             let .table(id, _, _, _), let .rule(id):
            id
        }
    }
}

enum MarkdownBlockParser {
    private struct Fence {
        let character: Character
        let count: Int
        let language: String?
    }

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var paragraphStart = 0
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(
                .paragraph(
                    id: "paragraph-\(paragraphStart)",
                    text: paragraphLines.joined(separator: "\n")
                )
            )
            paragraphLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let setext = parseSetextHeading(lines, startingAt: index) {
                flushParagraph()
                blocks.append(setext.block)
                index = setext.nextIndex
                continue
            }

            if isIndentedCodeLine(rawLine) {
                flushParagraph()
                let start = index
                var codeLines: [String] = []

                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                        codeLines.append("")
                        index += 1
                        continue
                    }
                    guard isIndentedCodeLine(candidate) else { break }
                    codeLines.append(removingCodeIndent(from: candidate))
                    index += 1
                }

                while codeLines.last == "" { codeLines.removeLast() }
                blocks.append(.code(id: "code-\(start)", language: nil, text: codeLines.joined(separator: "\n")))
                continue
            }

            if let openingFence = parseFence(trimmed) {
                flushParagraph()
                let start = index
                var codeLines: [String] = []
                index += 1

                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if isClosingFence(candidate, matching: openingFence) {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }

                blocks.append(
                    .code(
                        id: "code-\(start)",
                        language: openingFence.language,
                        text: codeLines.joined(separator: "\n")
                    )
                )
                continue
            }

            if let table = parseTable(lines, startingAt: index) {
                flushParagraph()
                blocks.append(table.block)
                index = table.nextIndex
                continue
            }

            if let image = parseImage(trimmed, lineIndex: index) ?? parseBareImageURL(trimmed, lineIndex: index) {
                flushParagraph()
                blocks.append(image)
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed, lineIndex: index) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule(id: "rule-\(index)"))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let start = index
                var quoteLines: [String] = []

                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    var content = String(quoteLine.dropFirst())
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quoteLines.append(content)
                    index += 1
                }

                blocks.append(
                    .quote(
                        id: "quote-\(start)",
                        text: quoteLines.joined(separator: "\n")
                    )
                )
                continue
            }

            if parseListLine(rawLine, lineIndex: index) != nil {
                flushParagraph()
                let start = index
                var items: [MarkdownListItem] = []

                while index < lines.count {
                    guard var item = parseListLine(lines[index], lineIndex: index) else { break }
                    let baseIndent = leadingWhitespaceWidth(in: lines[index])
                    index += 1

                    while index < lines.count {
                        let continuation = lines[index]
                        let continuationTrimmed = continuation.trimmingCharacters(in: .whitespaces)
                        guard !continuationTrimmed.isEmpty,
                              parseListLine(continuation, lineIndex: index) == nil,
                              leadingWhitespaceWidth(in: continuation) > baseIndent else {
                            break
                        }

                        item.text += "\n" + continuationTrimmed
                        index += 1
                    }

                    items.append(item)
                }

                blocks.append(.list(id: "list-\(start)", items: normalizedListNumbers(items)))
                continue
            }

            if paragraphLines.isEmpty {
                paragraphStart = index
            }
            paragraphLines.append(rawLine)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func normalizedListNumbers(_ items: [MarkdownListItem]) -> [MarkdownListItem] {
        var result = items
        var counters: [Int: Int] = [:]

        for index in result.indices {
            let depth = result[index].depth
            counters = counters.filter { $0.key <= depth }

            switch result[index].marker {
            case let .ordered(sourceNumber):
                let displayNumber = counters[depth].map { $0 + 1 } ?? sourceNumber
                result[index].marker = .ordered(displayNumber)
                counters[depth] = displayNumber

            case .bullet, .task:
                counters[depth] = nil
            }
        }

        return result
    }

    private static func parseSetextHeading(
        _ lines: [String],
        startingAt index: Int
    ) -> (block: MarkdownBlock, nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let title = lines[index].trimmingCharacters(in: .whitespaces)
        let underline = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, underline.count >= 3 else { return nil }

        let level: Int
        if underline.allSatisfy({ $0 == "=" }) {
            level = 1
        } else if underline.allSatisfy({ $0 == "-" }) {
            level = 2
        } else {
            return nil
        }

        return (
            .heading(id: "heading-\(index)", level: level, text: title),
            index + 2
        )
    }

    private static func isIndentedCodeLine(_ line: String) -> Bool {
        line.hasPrefix("    ") || line.hasPrefix("\t")
    }

    private static func removingCodeIndent(from line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
        return line
    }

    private static func parseHeading(_ line: String, lineIndex: Int) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let remainder = line.dropFirst(hashes.count)
        guard remainder.first == " " else { return nil }
        return .heading(
            id: "heading-\(lineIndex)",
            level: hashes.count,
            text: String(remainder.dropFirst())
        )
    }

    private static func parseListLine(_ rawLine: String, lineIndex: Int) -> MarkdownListItem? {
        let indentation = leadingWhitespaceWidth(in: rawLine)
        let depth = min(6, indentation / 2)
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        if let bulletContent = contentAfterBullet(in: line) {
            let lowered = bulletContent.lowercased()
            if lowered.hasPrefix("[ ] ") || lowered.hasPrefix("[x] ") {
                let isCompleted = lowered.hasPrefix("[x] ")
                return MarkdownListItem(
                    id: "list-item-\(lineIndex)",
                    lineIndex: lineIndex,
                    depth: depth,
                    marker: .task(isCompleted: isCompleted),
                    text: String(bulletContent.dropFirst(4))
                )
            }

            return MarkdownListItem(
                id: "list-item-\(lineIndex)",
                lineIndex: lineIndex,
                depth: depth,
                marker: .bullet,
                text: bulletContent
            )
        }

        var digitEnd = line.startIndex
        while digitEnd < line.endIndex, line[digitEnd].isNumber {
            digitEnd = line.index(after: digitEnd)
        }

        guard digitEnd > line.startIndex,
              digitEnd < line.endIndex,
              line[digitEnd] == "." || line[digitEnd] == ")",
              let number = Int(line[..<digitEnd]) else {
            return nil
        }

        let markerEnd = line.index(after: digitEnd)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }
        let textStart = line.index(after: markerEnd)

        return MarkdownListItem(
            id: "list-item-\(lineIndex)",
            lineIndex: lineIndex,
            depth: depth,
            marker: .ordered(number),
            text: textStart <= line.endIndex ? String(line[textStart...]) : ""
        )
    }

    private static func contentAfterBullet(in line: String) -> String? {
        guard let first = line.first, first == "-" || first == "*" || first == "+" else {
            return nil
        }
        let markerEnd = line.index(after: line.startIndex)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }
        let contentStart = line.index(after: markerEnd)
        return contentStart <= line.endIndex ? String(line[contentStart...]) : ""
    }

    private static func parseImage(_ line: String, lineIndex: Int) -> MarkdownBlock? {
        guard line.hasPrefix("!["),
              let altEnd = line.firstIndex(of: "]"),
              line.index(after: altEnd) < line.endIndex,
              line[line.index(after: altEnd)] == "(",
              line.hasSuffix(")") else {
            return nil
        }

        let altStart = line.index(line.startIndex, offsetBy: 2)
        let alt = String(line[altStart..<altEnd])
        let sourceStart = line.index(altEnd, offsetBy: 2)
        let sourceEnd = line.index(before: line.endIndex)
        var source = String(line[sourceStart..<sourceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        if source.hasPrefix("<"), source.hasSuffix(">") {
            source.removeFirst()
            source.removeLast()
        } else if let titleSeparator = source.firstIndex(where: { $0.isWhitespace }) {
            source = String(source[..<titleSeparator])
        }

        let imageSource: MarkdownImageSource
        if source.hasPrefix("attachment://"),
           let id = UUID(uuidString: String(source.dropFirst("attachment://".count))) {
            imageSource = .attachment(id)
        } else if source.lowercased().hasPrefix("https://") || source.lowercased().hasPrefix("http://") {
            imageSource = .remote(source)
        } else {
            return nil
        }

        return .image(id: "image-\(lineIndex)", source: imageSource, alt: alt)
    }

    private static func parseBareImageURL(_ line: String, lineIndex: Int) -> MarkdownBlock? {
        guard line.lowercased().hasPrefix("https://") || line.lowercased().hasPrefix("http://") else {
            return nil
        }

        let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard looksLikeImageURL(cleaned) else { return nil }
        return .image(id: "image-\(lineIndex)", source: .remote(cleaned), alt: "")
    }

    private static func looksLikeImageURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value) else { return false }
        let path = components.path.lowercased()
        let extensions = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic", ".heif", ".bmp", ".tiff", ".svg"]
        if extensions.contains(where: path.hasSuffix) { return true }

        let query = components.queryItems ?? []
        return query.contains { item in
            guard let value = item.value?.lowercased() else { return false }
            return ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(value)
        }
    }

    private static func parseTable(
        _ lines: [String],
        startingAt start: Int
    ) -> (block: MarkdownBlock, nextIndex: Int)? {
        guard start + 1 < lines.count else { return nil }

        let headerCells = parseTableCells(lines[start])
        let dividerCells = parseTableCells(lines[start + 1])
        guard headerCells.count >= 2,
              dividerCells.count == headerCells.count,
              dividerCells.allSatisfy(isTableDividerCell) else {
            return nil
        }

        let alignments = dividerCells.map(tableAlignment)
        var rows: [[String]] = []
        var index = start + 2

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }

            let cells = normalizedTableRow(parseTableCells(lines[index]), columnCount: headerCells.count)
            rows.append(cells)
            index += 1
        }

        return (
            .table(
                id: "table-\(start)",
                headers: headerCells,
                alignments: alignments,
                rows: rows
            ),
            index
        )
    }

    private static func parseTableCells(_ rawLine: String) -> [String] {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }

        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in line {
            if isEscaped {
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }

        if isEscaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isTableDividerCell(_ cell: String) -> Bool {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        var core = trimmed
        if core.hasPrefix(":") { core.removeFirst() }
        if core.hasSuffix(":") { core.removeLast() }
        return core.count >= 3 && core.allSatisfy { $0 == "-" }
    }

    private static func tableAlignment(_ divider: String) -> MarkdownTableAlignment {
        let trimmed = divider.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(":"), trimmed.hasSuffix(":") { return .center }
        if trimmed.hasSuffix(":") { return .trailing }
        return .leading
    }

    private static func normalizedTableRow(_ cells: [String], columnCount: Int) -> [String] {
        var result = Array(cells.prefix(columnCount))
        if result.count < columnCount {
            result.append(contentsOf: repeatElement("", count: columnCount - result.count))
        }
        return result
    }

    private static func parseFence(_ line: String) -> Fence? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        let info = String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        return Fence(character: first, count: count, language: info.isEmpty ? nil : info)
    }

    private static func isClosingFence(_ line: String, matching fence: Fence) -> Bool {
        let count = line.prefix { $0 == fence.character }.count
        guard count >= fence.count else { return false }
        return line.dropFirst(count).allSatisfy(\.isWhitespace)
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && (
            Set(compact) == Set(["-"]) ||
            Set(compact) == Set(["*"]) ||
            Set(compact) == Set(["_"])
        )
    }

    private static func leadingWhitespaceWidth(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(into: 0) { width, character in
            width += character == "\t" ? 4 : 1
        }
    }
}
