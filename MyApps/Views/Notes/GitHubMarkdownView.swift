import Foundation
import MarkdownView
import SwiftUI
import UIKit

/// The app-facing Markdown preview. MarkdownView owns standards-compliant rendering,
/// while this wrapper retains MyApps-specific task toggles and sandboxed attachments.
struct GitHubMarkdownView: View {
    let markdown: String
    let attachments: [NoteAttachment]
    var compact = false
    var interactiveTasks = false
    var onToggleTask: ((Int) -> Void)?

    private var segments: [PreviewSegment] {
        MarkdownPreviewSegmenter.segments(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Empty note")
                    .font(.system(size: compact ? 16 : 17, design: .rounded))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(segments.indices, id: \.self) { index in
                    segmentView(segments[index])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .allowsHitTesting(!compact)
        .environment(\.openURL, OpenURLAction { url in
            UIApplication.shared.open(url)
            return .handled
        })
    }

    @ViewBuilder
    private func segmentView(_ segment: PreviewSegment) -> some View {
        switch segment {
        case let .markdown(source):
            renderedMarkdown(source)

        case let .task(task):
            taskRow(task)
        }
    }

    private func renderedMarkdown(_ source: String) -> some View {
        MarkdownView(source)
            .markdownTableStyle(ScrollableGitHubMarkdownTableStyle())
            .markdownBlockQuoteStyle(.github)
            .markdownCodeBlockStyle(
                .default(lightTheme: "xcode", darkTheme: "dark")
            )
            .markdownListIndent(compact ? 14 : 20)
            .markdownElementRenderer(
                .image(
                    AttachmentImageRenderer(
                        attachments: attachments,
                        compact: compact
                    ),
                    urlScheme: "attachment"
                )
            )
            .font(.system(size: compact ? 15 : 17, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func taskRow(_ task: MarkdownPreviewTaskLine) -> some View {
        let row = HStack(alignment: .top, spacing: compact ? 8 : 10) {
            RoundedCheckbox(isChecked: task.isCompleted, size: compact ? 17 : 20)
                .padding(.top, compact ? 1 : 2)

            renderedMarkdown(task.content)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .strikethrough(task.isCompleted, color: .secondary)
        }
        .padding(.leading, CGFloat(task.depth) * (compact ? 13 : 18))
        .contentShape(Rectangle())

        if interactiveTasks, let onToggleTask {
            Button {
                onToggleTask(task.lineIndex)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                task.isCompleted
                    ? "Mark incomplete: \(task.plainText)"
                    : "Mark complete: \(task.plainText)"
            )
        } else {
            row
        }
    }
}

private struct ScrollableGitHubMarkdownTableStyle: MarkdownTableStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollableGitHubMarkdownTable(configuration: configuration)
    }
}

private struct ScrollableGitHubMarkdownTable: View {
    let configuration: MarkdownTableStyleConfiguration

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 14 / 255, green: 17 / 255, blue: 22 / 255)
            : .white
    }

    private var alternateRowColor: Color {
        colorScheme == .dark
            ? Color(red: 21 / 255, green: 27 / 255, blue: 35 / 255)
            : Color(red: 246 / 255, green: 248 / 255, blue: 250 / 255)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color(red: 61 / 255, green: 68 / 255, blue: 67 / 255)
            : Color(red: 209 / 255, green: 217 / 255, blue: 224 / 255)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                configuration.table.header

                ForEach(Array(configuration.table.rows.enumerated()), id: \.offset) { index, row in
                    row.markdownTableRowBackgroundStyle(
                        index.isMultiple(of: 2) ? backgroundColor : alternateRowColor
                    )
                }
            }
            .markdownTableRowBackgroundStyle(backgroundColor)
            .markdownTableCellPadding(.vertical, 6)
            .markdownTableCellPadding(.horizontal, 13)
            .markdownTableCellOverlay {
                Rectangle()
                    .strokeBorder(borderColor)
                    .opacity(0.5)
            }
            .overlay {
                Rectangle()
                    .strokeBorder(borderColor)
                    .opacity(0.5)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AttachmentImageRenderer: MarkdownImageRenderer {
    let attachments: [NoteAttachment]
    let compact: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if let id = configuration.url.attachmentID,
           let attachment = attachments.first(where: { $0.id == id }),
           let data = attachment.data,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: compact ? 9 : 13,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: compact ? 9 : 13,
                        style: .continuous
                    )
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                }
                .accessibilityLabel(attachment.filename)
        } else {
            HStack(spacing: 9) {
                Image(systemName: "photo.badge.exclamationmark")
                Text("Image unavailable")
            }
            .font(.system(size: compact ? 13 : 15, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(compact ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))
        }
    }
}

private extension URL {
    var attachmentID: UUID? {
        guard scheme?.lowercased() == "attachment" else { return nil }

        if let host, let id = UUID(uuidString: host) {
            return id
        }

        let pathValue = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: pathValue)
    }
}

private enum PreviewSegment {
    case markdown(String)
    case task(MarkdownPreviewTaskLine)
}

private struct MarkdownPreviewTaskLine {
    let lineIndex: Int
    let depth: Int
    let isCompleted: Bool
    let content: String

    var plainText: String {
        content
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}

private enum MarkdownPreviewSegmenter {
    private static let taskExpression = try! NSRegularExpression(
        pattern: #"^(\s*)[-+*]\s+\[([ xX])\]\s+(.*)$"#
    )

    static func segments(from markdown: String) -> [PreviewSegment] {
        let lines = markdown.components(separatedBy: "\n")
        var result: [PreviewSegment] = []
        var markdownLines: [String] = []
        var fence: Character?

        func flushMarkdown() {
            guard !markdownLines.isEmpty else { return }
            result.append(.markdown(markdownLines.joined(separator: "\n")))
            markdownLines.removeAll(keepingCapacity: true)
        }

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = fence {
                markdownLines.append(line)
                if isFence(trimmed, marker: marker) {
                    fence = nil
                }
                continue
            }

            if let marker = openingFenceMarker(in: trimmed) {
                markdownLines.append(line)
                fence = marker
                continue
            }

            if let task = taskLine(from: line, lineIndex: lineIndex) {
                flushMarkdown()
                result.append(.task(task))
            } else {
                markdownLines.append(line)
            }
        }

        flushMarkdown()
        return result
    }

    private static func taskLine(from line: String, lineIndex: Int) -> MarkdownPreviewTaskLine? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = taskExpression.firstMatch(in: line, range: range),
              let indentationRange = Range(match.range(at: 1), in: line),
              let stateRange = Range(match.range(at: 2), in: line),
              let contentRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let indentation = String(line[indentationRange])
        let expandedIndentation = indentation.reduce(into: 0) { count, character in
            count += character == "\t" ? 4 : 1
        }
        let state = line[stateRange]

        return MarkdownPreviewTaskLine(
            lineIndex: lineIndex,
            depth: max(0, expandedIndentation / 2),
            isCompleted: state == "x" || state == "X",
            content: String(line[contentRange])
        )
    }

    private static func openingFenceMarker(in line: String) -> Character? {
        if line.hasPrefix("```") { return "`" }
        if line.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func isFence(_ line: String, marker: Character) -> Bool {
        line.hasPrefix(String(repeating: marker, count: 3))
    }
}

struct RoundedCheckbox: View {
    let isChecked: Bool
    var size: CGFloat = 21

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(isChecked ? Color.accentColor : Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(
                            isChecked ? Color.accentColor : Color.secondary.opacity(0.55),
                            lineWidth: 1.6
                        )
                }

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
