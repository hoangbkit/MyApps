import AppFoundation
import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private enum NoteDisplayMode: Equatable {
    case edit
    case preview
}

struct NoteEditorView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiWriting: AIWritingSession
    @Query(sort: \ManagedApp.name) private var apps: [ManagedApp]

    @Bindable var note: QuickNote

    @State private var mode = NoteDisplayMode.edit
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var copyFeedback = 0
    @State private var aiRequest: NoteAIRequest?
    @StateObject private var editorController = MarkdownEditorController()

    init(note: QuickNote) {
        self.note = note
        _selectedRange = State(initialValue: NSRange(location: (note.body as NSString).length, length: 0))
    }

    var body: some View {
        ZStack {
            // Retain the same Runestone instance through Edit/Preview changes.
            // Recreating the UIView would discard its native undo history.
            MarkdownTextEditor(
                text: $note.body,
                selectedRange: $selectedRange,
                editorController: editorController,
                focusOnAppear: mode == .edit
            )
            .opacity(mode == .edit ? 1 : 0)
            .allowsHitTesting(mode == .edit)
            .accessibilityHidden(mode != .edit)

            if mode == .preview {
                preview
            }
        }
        .myAppsPage()
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Rewrite") {
                        ForEach([
                            NoteAIAction.proofread, .improve, .shorten, .expand,
                            .summarize, .bullets
                        ]) { action in
                            Button {
                                transform(action)
                            } label: {
                                Label(action.title, systemImage: action.symbol)
                            }
                        }
                    }
                    Menu("Tone") {
                        ForEach([NoteAIAction.professional, .casual]) { action in
                            Button(action.title) { transform(action) }
                        }
                    }
                    Menu("Text Case") {
                        ForEach([
                            NoteAIAction.lowercaseAll, .lowercaseProtected,
                            .uppercaseAll, .titleCase, .sentenceCase
                        ]) { action in
                            Button(action.title) { transform(action) }
                        }
                    }
                    Button {
                        transform(.translate)
                    } label: {
                        Label("Translate…", systemImage: "character.book.closed")
                    }
                    Button {
                        transform(.custom)
                    } label: {
                        Label("Custom Rewrite…", systemImage: "pencil.line")
                    }
                } label: {
                    Image(systemName: "sparkles")
                }
                .disabled(note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("AI Writing Actions")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        mode = mode == .edit ? .preview : .edit
                    } label: {
                        Label(
                            mode == .edit ? "Preview" : "Edit",
                            systemImage: mode == .edit ? "doc.richtext" : "pencil"
                        )
                    }

                    Divider()

                    Button {
                        editorController.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!editorController.canUndo)

                    Button {
                        editorController.redo()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!editorController.canRedo)

                    Divider()

                    Button {
                        copyWholeText()
                    } label: {
                        Label("Copy Whole Text", systemImage: "doc.on.doc")
                    }
                    .disabled(note.body.isEmpty)

                    assignmentMenu

                    Button {
                        note.isPinned.toggle()
                        touchNote()
                    } label: {
                        Label(note.isPinned ? "Unpin Note" : "Pin Note", systemImage: note.isPinned ? "pin.slash" : "pin")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Note Actions")
            }

            if mode == .edit {
                ToolbarItem(placement: .keyboard) {
                    markdownKeyboardToolbar
                }
            }
        }
        .sheet(item: $aiRequest) { request in
            NoteAIReviewView(request: request) { operation, proposedText in
                applyAIResult(request: request, mode: operation, text: proposedText)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerCheckpoint)) { _ in
            editorController.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in
            editorController.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in
            editorController.refresh()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .preview {
                dismissKeyboard()
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await importImage(from: item) }
        }
        .onDisappear {
            guard !isDeleting else { return }
            cleanUpAndSave()
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive) {
                deleteNote()
            }
        }
        .sensoryFeedback(.success, trigger: copyFeedback)
    }

    private var preview: some View {
        ScrollView {
            GitHubMarkdownView(
                markdown: note.body,
                attachments: note.attachments,
                interactiveTasks: true
            ) { lineIndex in
                let before = note.body
                let after = MarkdownTaskParser.togglingTask(at: lineIndex, in: before)
                if editorController.applyChange(before: before, after: after, selectionAfter: selectedRange) {
                    touchNote()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 48)
            .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private var assignmentMenu: some View {
        Menu {
            Button {
                assign(to: nil)
            } label: {
                Label("Unassigned", systemImage: note.app == nil ? "checkmark" : "tray")
            }

            if !apps.isEmpty {
                Divider()
                ForEach(apps) { app in
                    Button {
                        assign(to: app)
                    } label: {
                        Label(app.name, systemImage: note.app?.id == app.id ? "checkmark" : "square.grid.2x2")
                    }
                }
            }
        } label: {
            Label("Assign to App", systemImage: "folder")
        }
    }

    private var markdownKeyboardToolbar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    Menu {
                        Button("Heading 1") { insertLinePrefix("# ") }
                        Button("Heading 2") { insertLinePrefix("## ") }
                        Button("Heading 3") { insertLinePrefix("### ") }
                    } label: {
                        markdownToolbarIcon("textformat.size")
                    }
                    .accessibilityLabel("Insert Heading")

                    markdownToolbarButton("bold", label: "Bold") {
                        wrapSelection(with: "**")
                    }

                    markdownToolbarButton("italic", label: "Italic") {
                        wrapSelection(with: "_")
                    }

                    markdownToolbarButton("strikethrough", label: "Strikethrough") {
                        wrapSelection(with: "~~")
                    }

                    markdownToolbarButton("chevron.left.forwardslash.chevron.right", label: "Inline Code") {
                        wrapSelection(with: "`")
                    }

                    markdownToolbarButton("link", label: "Insert Link") {
                        insertTemplate("[title](https://)", placeholder: "title")
                    }

                    markdownToolbarButton("list.bullet", label: "Bullet List") {
                        insertLinePrefix("- ")
                    }

                    markdownToolbarButton("list.number", label: "Numbered List") {
                        insertLinePrefix("1. ")
                    }

                    markdownToolbarButton("checklist", label: "Checklist Item") {
                        insertLinePrefix("- [ ] ")
                    }

                    markdownToolbarButton("text.quote", label: "Quote") {
                        insertLinePrefix("> ")
                    }

                    markdownToolbarButton("curlybraces", label: "Code Block") {
                        insertTemplate("\n```swift\ncode\n```\n", placeholder: "code")
                    }

                    markdownToolbarButton("tablecells", label: "Table") {
                        insertTemplate(
                            "\n| Column 1 | Column 2 |\n| --- | --- |\n| Value 1 | Value 2 |\n",
                            placeholder: "Column 1"
                        )
                    }

                    markdownToolbarButton("minus", label: "Divider") {
                        insertSnippet("\n\n---\n\n")
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        markdownToolbarIcon("photo")
                    }
                    .accessibilityLabel("Insert Image")
                }
            }

            Divider()
                .frame(height: 24)

            markdownToolbarButton("arrow.uturn.backward", label: "Undo") {
                editorController.undo()
            }
            .disabled(!editorController.canUndo)

            markdownToolbarButton("arrow.uturn.forward", label: "Redo") {
                editorController.redo()
            }
            .disabled(!editorController.canRedo)

            Button("Done") {
                dismissKeyboard()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }

    private func markdownToolbarButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            markdownToolbarIcon(symbol)
        }
        .accessibilityLabel(label)
    }

    nonisolated private func markdownToolbarIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 34, height: 30)
            .contentShape(Rectangle())
    }

    private func performMarkdownCommand(_ command: (inout String, inout NSRange) -> Void) {
        let before = note.body
        var after = before
        var selectionAfter = selectedRange
        command(&after, &selectionAfter)
        if editorController.applyChange(before: before, after: after, selectionAfter: selectionAfter) {
            selectedRange = selectionAfter
            touchNote()
        }
    }

    private func insertLinePrefix(_ prefix: String) {
        performMarkdownCommand { text, selection in
            MarkdownEditingCommand.insertLinePrefix(prefix, text: &text, selection: &selection)
        }
    }

    private func wrapSelection(with marker: String) {
        performMarkdownCommand { text, selection in
            MarkdownEditingCommand.wrapSelection(with: marker, text: &text, selection: &selection)
        }
    }

    private func insertSnippet(_ snippet: String) {
        performMarkdownCommand { text, selection in
            MarkdownEditingCommand.insert(snippet, text: &text, selection: &selection)
        }
    }

    private func insertTemplate(_ template: String, placeholder: String) {
        performMarkdownCommand { text, selection in
            MarkdownEditingCommand.insertTemplate(
                template, selecting: placeholder, text: &text, selection: &selection
            )
        }
    }

    @MainActor
    private func importImage(from item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        guard let sourceData = try? await item.loadTransferable(type: Data.self),
              let processed = NoteImageProcessor.process(data: sourceData) else {
            return
        }

        let attachmentID = UUID()
        let attachment = NoteAttachment(
            id: attachmentID,
            filename: "Image-\(attachmentID.uuidString.prefix(8)).jpg",
            pixelWidth: processed.pixelWidth,
            pixelHeight: processed.pixelHeight,
            data: processed.data
        )
        let token = "\n\n![Image](attachment://\(attachmentID.uuidString))\n\n"
        let before = note.body
        var after = before
        var selectionAfter = selectedRange
        MarkdownEditingCommand.insert(token, text: &after, selection: &selectionAfter)
        guard editorController.applyChange(before: before, after: after, selectionAfter: selectionAfter) else {
            return
        }
        selectedRange = selectionAfter
        modelContext.insert(attachment)
        attachment.note = note
        mode = .edit
        touchNote()
    }

    private func assign(to app: ManagedApp?) {
        let previousApp = note.app
        guard previousApp?.id != app?.id else { return }

        let now = Date()
        previousApp?.updatedAt = now
        note.app = app
        app?.updatedAt = now
        note.updatedAt = now
    }

    private func copyWholeText() {
        UIPasteboard.general.string = note.body
        copyFeedback += 1
    }

    private func transform(_ action: NoteAIAction) {
        guard let request = NoteAIRequest.capture(
            action: action,
            text: note.body,
            range: selectedRange,
            allowSelection: mode == .edit
        ) else { return }

        if action.isLocal {
            let output = NoteAIProtectedText.applyLocal(action, to: request.selectedText)
            _ = applyAIResult(request: request, mode: .replace, text: output)
        } else {
            aiRequest = request
        }
    }

    /// Never apply stale AI output to a note that changed while the sheet was
    /// open; preserve existing attachment references in the final Markdown.
    private func applyAIResult(request: NoteAIRequest, mode operation: NoteAIApplyMode, text: String) -> Bool {
        guard note.body == request.sourceBody else { return false }
        let source = request.sourceBody as NSString
        guard request.targetRange.location != NSNotFound,
              request.targetRange.location >= 0,
              request.targetRange.length <= source.length,
              request.targetRange.location <= source.length - request.targetRange.length else {
            return false
        }

        let editRange: NSRange
        let insertion: String
        switch operation {
        case .replace:
            editRange = request.targetRange
            insertion = text
        case .insertBelow:
            // Inserting source attachment references again would duplicate
            // their use within a note; offer Replace/Copy instead.
            guard NoteAIProtectedText.attachmentReferences(in: request.selectedText).isEmpty else {
                return false
            }
            editRange = NSRange(
                location: request.targetRange.location + request.targetRange.length,
                length: 0
            )
            insertion = "\n\n" + text
        }

        let updated = source.replacingCharacters(in: editRange, with: insertion)
        guard NoteAIProtectedText.attachmentReferences(in: updated) ==
              NoteAIProtectedText.attachmentReferences(in: request.sourceBody) else {
            return false
        }
        let selectionAfter = NSRange(
            location: editRange.location + insertion.utf16.count, length: 0
        )
        guard editorController.applyChange(
            before: request.sourceBody,
            after: updated,
            selectionAfter: selectionAfter
        ) else { return false }
        selectedRange = selectionAfter
        mode = .edit
        touchNote()
        return true
    }

    private func touchNote() {
        note.updatedAt = Date()
        note.app?.updatedAt = Date()
    }

    private func deleteNote() {
        isDeleting = true
        let app = note.app
        modelContext.delete(note)
        app?.updatedAt = Date()
        dismiss()
    }

    private func cleanUpAndSave() {
        note.title = ""
        note.legacyKind = .markdown
        note.body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)

        if note.isEffectivelyEmpty {
            let app = note.app
            modelContext.delete(note)
            app?.updatedAt = Date()
            return
        }

        touchNote()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
