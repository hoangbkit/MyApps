import Foundation

struct MarkdownTaskLine: Identifiable, Hashable {
    let lineIndex: Int
    let indentation: String
    let bullet: Character
    let isCompleted: Bool
    let text: String

    var id: Int { lineIndex }
}

enum MarkdownTaskParser {
    static func task(at lineIndex: Int, in markdown: String) -> MarkdownTaskLine? {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return nil }
        return parse(line: lines[lineIndex], lineIndex: lineIndex)
    }

    static func tasks(in markdown: String) -> [MarkdownTaskLine] {
        markdown
            .components(separatedBy: "\n")
            .enumerated()
            .compactMap { parse(line: $0.element, lineIndex: $0.offset) }
    }

    static func openTaskCount(in markdown: String) -> Int {
        tasks(in: markdown).filter { !$0.isCompleted }.count
    }

    static func togglingTask(at lineIndex: Int, in markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex),
              let task = parse(line: lines[lineIndex], lineIndex: lineIndex) else {
            return markdown
        }

        let mark = task.isCompleted ? " " : "x"
        lines[lineIndex] = "\(task.indentation)\(task.bullet) [\(mark)] \(task.text)"
        return lines.joined(separator: "\n")
    }

    private static func parse(line: String, lineIndex: Int) -> MarkdownTaskLine? {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let remainder = String(line.dropFirst(indentation.count))
        guard remainder.count >= 6 else { return nil }

        let characters = Array(remainder)
        guard characters[0] == "-" || characters[0] == "*" || characters[0] == "+",
              characters[1] == " ",
              characters[2] == "[",
              characters[4] == "]",
              characters[5] == " " else {
            return nil
        }

        let marker = characters[3]
        guard marker == " " || marker == "x" || marker == "X" else { return nil }

        return MarkdownTaskLine(
            lineIndex: lineIndex,
            indentation: indentation,
            bullet: characters[0],
            isCompleted: marker == "x" || marker == "X",
            text: String(characters.dropFirst(6))
        )
    }
}
