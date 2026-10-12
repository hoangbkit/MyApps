import SwiftUI
import UIKit

enum NoteAIApplyMode {
    case replace, insertBelow
}

/// Review results without mutating the original note. The editor validates
/// the captured note snapshot again when the user explicitly applies a result.
struct NoteAIReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ai: AIWritingSession

    let request: NoteAIRequest
    let onApply: (NoteAIApplyMode, String) -> Bool

    @State private var selectedProfileID: UUID?
    @State private var instruction = ""
    @State private var output: String?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var currentTask: Task<Void, Never>?

    private var selectedProfile: AIWritingProfile {
        ai.profiles.first(where: { $0.id == (selectedProfileID ?? ai.defaultProfileID) }) ?? ai.defaultProfile
    }

    private var requiresInstruction: Bool {
        request.action == .custom || request.action == .translate
    }

    private var canGenerate: Bool {
        !isGenerating && (!requiresInstruction || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var canInsert: Bool {
        NoteAIProtectedText.attachmentReferences(in: request.selectedText).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Action") {
                    LabeledContent("Transform", value: request.action.title)
                    LabeledContent("Scope", value: request.isSelection ? "Selected Text" : "Whole Note")
                    Picker("Profile", selection: Binding(
                        get: { selectedProfileID ?? ai.defaultProfileID },
                        set: { selectedProfileID = $0 }
                    )) {
                        ForEach(ai.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .onChange(of: selectedProfileID) { _, _ in
                        output = nil
                        errorMessage = nil
                    }
                    if requiresInstruction {
                        TextField(
                            request.action == .translate ? "Target language (e.g. Vietnamese)" : "What should AI change?",
                            text: $instruction,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                    }
                }

                Section("Original") {
                    Text(request.selectedText)
                        .font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled)
                }

                Section("Result") {
                    if isGenerating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Generating with \(ai.model.title)…")
                                .foregroundStyle(.secondary)
                        }
                        Button("Cancel Request") {
                            currentTask?.cancel()
                            currentTask = nil
                            isGenerating = false
                        }
                    } else if let output {
                        Text(output)
                            .font(.system(size: 14, design: .monospaced))
                            .textSelection(.enabled)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(requiresInstruction ? "Enter an instruction, then generate a result." : "No result yet.")
                            .foregroundStyle(.secondary)
                    }

                    Button(output == nil ? "Generate" : "Retry") {
                        startGeneration()
                    }
                    .disabled(!canGenerate)

                    if let output {
                        Button {
                            apply(.replace, output: output)
                        } label: {
                            Label("Replace Original", systemImage: "checkmark.circle")
                        }

                        if canInsert {
                            Button {
                                apply(.insertBelow, output: output)
                            } label: {
                                Label("Insert Below", systemImage: "text.insert")
                            }
                        }

                        Button {
                            UIPasteboard.general.string = output
                        } label: {
                            Label("Copy Result", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .navigationTitle("AI Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if selectedProfileID == nil { selectedProfileID = ai.defaultProfileID }
                if !requiresInstruction { await generate() }
            }
            .onDisappear {
                currentTask?.cancel()
                currentTask = nil
            }
            .alert(
                "Cannot Apply Result",
                isPresented: Binding(
                    get: { errorMessage != nil && output != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func apply(_ mode: NoteAIApplyMode, output: String) {
        guard onApply(mode, output) else {
            errorMessage = NoteAITextError.staleNote.localizedDescription
            return
        }
        dismiss()
    }

    private func startGeneration() {
        currentTask?.cancel()
        currentTask = Task { await generate() }
    }

    @MainActor
    private func generate() async {
        guard canGenerate else { return }
        isGenerating = true
        output = nil
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let client = try ai.client()
            let value = try await client.transform(
                request.selectedText,
                action: request.action,
                profile: selectedProfile,
                extraInstruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try Task.checkCancellation()
            // Reject attempts to modify or omit existing image attachments.
            guard NoteAIProtectedText.attachmentReferences(in: request.selectedText) ==
                    NoteAIProtectedText.attachmentReferences(in: value) else {
                throw NoteAITextError.protectedContentChanged
            }
            output = value
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
