import Runestone
import SwiftUI
import UIKit

struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> Runestone.TextView {
        let textView = Runestone.TextView()
        textView.editorDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.isLineWrappingEnabled = true
        textView.showLineNumbers = false
        textView.lineSelectionDisplayType = .line
        textView.lineHeightMultiplier = 1.28
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 13, bottom: 120, right: 13)
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.insertionPointColor = .systemBlue
        textView.selectionBarColor = .systemBlue
        textView.selectionHighlightColor = UIColor.systemBlue.withAlphaComponent(0.22)
        textView.verticalOverscrollFactor = 0.35
        textView.isFindInteractionEnabled = true
        textView.text = text
        textView.selectedRange = clampedSelection(for: text)
        return textView
    }

    func updateUIView(_ textView: Runestone.TextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            let offset = textView.contentOffset
            textView.text = text
            textView.contentOffset = offset
        }

        let validRange = clampedSelection(for: text)
        if textView.selectedRange != validRange {
            textView.selectedRange = validRange
        }

        if focusOnAppear, !context.coordinator.didRequestFocus {
            context.coordinator.didRequestFocus = true
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    private func clampedSelection(for value: String) -> NSRange {
        let length = (value as NSString).length
        let location = min(max(0, selectedRange.location), length)
        let rangeLength = min(max(0, selectedRange.length), length - location)
        return NSRange(location: location, length: rangeLength)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency TextViewDelegate {
        var parent: MarkdownTextEditor
        var didRequestFocus = false

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: Runestone.TextView) {
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: Runestone.TextView) {
            parent.selectedRange = textView.selectedRange
        }
    }
}

enum MarkdownEditingCommand {
    static func insertLinePrefix(_ prefix: String, text: inout String, selection: inout NSRange) {
        let source = text as NSString
        let safeRange = clamped(selection, length: source.length)
        let lineRange = source.lineRange(for: safeRange)
        let selectedText = source.substring(with: lineRange)
        let hasTrailingNewline = selectedText.hasSuffix("\n")
        let lines = selectedText.components(separatedBy: "\n")
        let effectiveLines = hasTrailingNewline ? lines.dropLast() : ArraySlice(lines)
        let transformed = effectiveLines.map { line in
            line.isEmpty ? prefix : prefix + line
        }.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")

        text = source.replacingCharacters(in: lineRange, with: transformed)
        selection = NSRange(location: lineRange.location + transformed.utf16.count, length: 0)
    }

    static func wrapSelection(with marker: String, text: inout String, selection: inout NSRange) {
        let source = text as NSString
        let safeRange = clamped(selection, length: source.length)
        let selected = source.substring(with: safeRange)
        let replacement = marker + selected + marker
        text = source.replacingCharacters(in: safeRange, with: replacement)

        if selected.isEmpty {
            selection = NSRange(location: safeRange.location + marker.utf16.count, length: 0)
        } else {
            selection = NSRange(location: safeRange.location, length: replacement.utf16.count)
        }
    }

    static func insert(_ insertion: String, text: inout String, selection: inout NSRange) {
        let source = text as NSString
        let safeRange = clamped(selection, length: source.length)
        text = source.replacingCharacters(in: safeRange, with: insertion)
        selection = NSRange(location: safeRange.location + insertion.utf16.count, length: 0)
    }

    static func insertTemplate(
        _ template: String,
        selecting placeholder: String,
        text: inout String,
        selection: inout NSRange
    ) {
        let source = text as NSString
        let safeRange = clamped(selection, length: source.length)
        text = source.replacingCharacters(in: safeRange, with: template)

        let templateNSString = template as NSString
        let placeholderRange = templateNSString.range(of: placeholder)
        if placeholderRange.location == NSNotFound {
            selection = NSRange(location: safeRange.location + template.utf16.count, length: 0)
        } else {
            selection = NSRange(
                location: safeRange.location + placeholderRange.location,
                length: placeholderRange.length
            )
        }
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let rangeLength = min(max(0, range.length), length - location)
        return NSRange(location: location, length: rangeLength)
    }
}
