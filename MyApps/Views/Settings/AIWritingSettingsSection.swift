import AppFoundation
import SwiftUI

struct DeepSeekSettingsSection: View {
    @EnvironmentObject private var ai: AIWritingSession
    @State private var pendingKey = ""
    @State private var replacing = false
    @State private var confirmDisconnect = false

    var body: some View {
        Section {
            LabeledContent("Status", value: ai.isConnected ? "Connected" : "Not Connected")
            Picker("Model", selection: Binding(
                get: { ai.model },
                set: { ai.setModel($0) }
            )) {
                ForEach(DeepSeekModel.allCases) { value in
                    Text(value.title).tag(value)
                }
            }

            if !ai.isConnected || replacing {
                SecureField("DeepSeek API key", text: $pendingKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .disabled(ai.isConnecting)

                Button {
                    Task {
                        if await ai.connect(pendingKey) {
                            pendingKey = ""
                            replacing = false
                        }
                    }
                } label: {
                    if ai.isConnecting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Testing Connection…")
                        }
                    } else {
                        Text(ai.isConnected ? "Save Replacement Key" : "Connect DeepSeek")
                    }
                }
                .disabled(ai.isConnecting || pendingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if ai.isConnected {
                    Button("Cancel Replacement") {
                        replacing = false
                        pendingKey = ""
                    }
                }
            } else {
                Button("Replace API Key") { replacing = true }
                Button("Disconnect DeepSeek", role: .destructive) {
                    confirmDisconnect = true
                }
            }
        } header: {
            Text("DeepSeek")
        } footer: {
            Text("Your key is saved only in this device's Keychain and never exported. AI transforms send the selected note text and profile instructions directly to DeepSeek. Model usage may incur charges.")
        }
        .confirmationDialog("Disconnect DeepSeek?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) {
                ai.disconnect()
                pendingKey = ""
                replacing = false
            }
        } message: {
            Text("The API key will be deleted from this device. AI profiles and notes stay intact.")
        }
        .onDisappear { pendingKey = "" }
    }
}

struct AIProfilesSettingsSection: View {
    @Environment(\.appFoundationTheme) private var foundationTheme

    @EnvironmentObject private var ai: AIWritingSession
    @State private var editingProfile: AIWritingProfile?

    var body: some View {
        Section {
            Picker("Default Profile", selection: Binding(
                get: { ai.defaultProfileID },
                set: { ai.setDefault($0) }
            )) {
                ForEach(ai.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }

            ForEach(ai.profiles) { profile in
                HStack {
                    Button {
                        editingProfile = profile
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: ai.defaultProfileID == profile.id ? "checkmark.circle.fill" : "person.crop.circle")
                                .foregroundStyle(ai.defaultProfileID == profile.id ? Color.accentColor : foundationTheme.secondaryForegroundColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .foregroundStyle(foundationTheme.primaryForegroundColor)
                                Text(profile.style.isEmpty ? "Custom writing profile" : profile.style)
                                    .font(.footnote)
                                    .foregroundStyle(foundationTheme.secondaryForegroundColor)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(foundationTheme.secondaryForegroundColor.opacity(0.75))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .contextMenu {
                    Button("Set as Default") { ai.setDefault(profile.id) }
                    Button("Duplicate") { ai.duplicate(profile) }
                    if ai.profiles.count > 1 {
                        Button("Delete", role: .destructive) { ai.delete(profile.id) }
                    }
                }
            }

            Button {
                editingProfile = ai.makeProfile()
            } label: {
                Label("Add Profile", systemImage: "plus")
            }
        } header: {
            Text("AI Profiles")
        } footer: {
            Text("Profiles define your writing voice and protected terminology. Long-press a profile to duplicate or delete it. Profiles are saved locally and included in full backups.")
        }
        .sheet(item: $editingProfile) { profile in
            AIProfileEditorView(profile: profile) { edited in
                ai.saveProfile(edited)
            }
        }
    }
}

private struct AIProfileEditorView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AIWritingProfile
    let onSave: (AIWritingProfile) -> Void

    init(profile: AIWritingProfile, onSave: @escaping (AIWritingProfile) -> Void) {
        _draft = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Profile") {
                        TextField("Name", text: $draft.name)
                            .textInputAutocapitalization(.words)
                        TextField("Identity", text: $draft.identity, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    Section("Writing Preferences") {
                        TextField("Writing Style", text: $draft.style, axis: .vertical)
                            .lineLimit(3...8)
                        TextField("Audience", text: $draft.audience, axis: .vertical)
                            .lineLimit(2...6)
                        TextField("Topics", text: $draft.topics, axis: .vertical)
                            .lineLimit(2...6)
                        TextField("Custom Instructions", text: $draft.instructions, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    Section {
                        TextField("Protected Terms", text: $draft.protectedTerms, axis: .vertical)
                            .lineLimit(3...8)
                    } header: {
                        Text("Protected Terminology")
                    } footer: {
                        Text("Separate terms with commas. Case-preserving rewrites keep these names, brands and technical terms unchanged.")
                    }
                }
                .listRowBackground(MyAppsGlassSurface())
                .listRowSeparatorTint(foundationTheme.borderColor)
            }
            .scrollContentBackground(.hidden)
            .myAppsPage()
            .navigationTitle("AI Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
