import Combine
import Runestone
import SwiftUI
import UIKit

/// Keeps one native Runestone undo stack for typing, Markdown commands,
/// preview checkbox changes, image insertion, and accepted AI rewrites.
/// The editor stays mounted behind Preview so history is not discarded.
@MainActor
final class MarkdownEditorController: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private weak var textView: Runestone.TextView?

    func attach(_ view: Runestone.TextView) {
        textView = view
        refresh()
    }

    func refresh() {
        let undoManager = textView?.undoManager
        canUndo = undoManager?.canUndo == true
        canRedo = undoManager?.canRedo == true
    }

    func undo() {
        guard let undoManager = textView?.undoManager, undoManager.canUndo else { return }
        undoManager.undo()
        refresh()
    }

    func redo() {
        guard let undoManager = textView?.undoManager, undoManager.canRedo else { return }
        undoManager.redo()
        refresh()
    }

    /// Calculate a single grapheme-safe contiguous edit, then let Runestone
    /// register its native undo operation instead of assigning .text directly
    /// (which resets its undo manager).
    @discardableResult
    func applyChange(before: String, after: String, selectionAfter: NSRange) -> Bool {
        guard let view = textView, view.text == before else { return false }
        guard before != after else {
            view.selectedRange = clamp(selectionAfter, length: (after as NSString).length)
            return true
        }

        let old = Array(before)
        let new = Array(after)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }

        let location = String(old[..<prefix]).utf16.count
        let oldLength = String(old[prefix..<(old.count - suffix)]).utf16.count
        let replacement = String(new[prefix..<(new.count - suffix)])
        let range = NSRange(location: location, length: oldLength)

        // Separate this command from nearby typed characters, so a single
        // Undo reliably reverts one toolbar command or accepted AI result.
        view.undoManager?.endUndoGrouping()
        view.replace(range, withText: replacement)
        view.undoManager?.endUndoGrouping()

        guard view.text == after else {
            refresh()
            return false
        }
        view.selectedRange = clamp(selectionAfter, length: (after as NSString).length)
        refresh()
        return true
    }

    private func clamp(_ range: NSRange, length: Int) -> NSRange {
        let location = range.location == NSNotFound ? length : min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
}


struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @ObservedObject var editorController: MarkdownEditorController
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> Runestone.TextView {
        let textView = Runestone.TextView()
        textView.editorDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.theme = NoteEditorTheme()
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.isLineWrappingEnabled = true
        textView.showLineNumbers = false
        textView.lineSelectionDisplayType = .disabled
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
        editorController.attach(textView)
        return textView
    }

    func updateUIView(_ textView: Runestone.TextView, context: Context) {
        context.coordinator.parent = self
        editorController.attach(textView)

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
            parent.editorController.refresh()
        }

        func textViewDidChangeSelection(_ textView: Runestone.TextView) {
            parent.selectedRange = textView.selectedRange
        }
    }
}


/// Keeps Runestone's default colors and syntax styling while making Markdown
/// notes readable at the same comfortable size as other iOS body text.
private final class NoteEditorTheme: Runestone.Theme {
    private let base = Runestone.DefaultTheme()

    let font = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    var textColor: UIColor { base.textColor }
    var gutterBackgroundColor: UIColor { base.gutterBackgroundColor }
    var gutterHairlineColor: UIColor { base.gutterHairlineColor }
    var lineNumberColor: UIColor { base.lineNumberColor }
    var lineNumberFont: UIFont { base.lineNumberFont }
    var selectedLineBackgroundColor: UIColor { base.selectedLineBackgroundColor }
    var selectedLinesLineNumberColor: UIColor { base.selectedLinesLineNumberColor }
    var selectedLinesGutterBackgroundColor: UIColor { base.selectedLinesGutterBackgroundColor }
    var invisibleCharactersColor: UIColor { base.invisibleCharactersColor }
    var pageGuideHairlineColor: UIColor { base.pageGuideHairlineColor }
    var pageGuideBackgroundColor: UIColor { base.pageGuideBackgroundColor }
    var markedTextBackgroundColor: UIColor { base.markedTextBackgroundColor }

    func textColor(for highlightName: String) -> UIColor? {
        base.textColor(for: highlightName)
    }

    func fontTraits(for highlightName: String) -> Runestone.FontTraits {
        base.fontTraits(for: highlightName)
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
