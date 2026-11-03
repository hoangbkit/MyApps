import AppFoundation
import Foundation
import SwiftUI

struct PricingPresetsView: View {
    @Environment(\.appFoundationTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let model: RegionalPricingViewModel
    @State private var store = PricingPresetStore.shared
    @State private var editor: PresetEditorRequest?
    @State private var pendingDeletion: RegionalPricingPreset?
    @State private var confirmingDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Group {
                if let error = store.loadError {
                    Text(error).foregroundStyle(.orange)
                    Button("Retry Loading Presets") { store.reload() }
                }
                ForEach(store.presets) { preset in
                    if preset.isBuiltIn {
                        presetRow(preset)
                    } else {
                        presetRow(preset)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { requestDeletion(preset) }
                                Button("Edit") { editor = .edit(preset) }
                                    .tint(.blue)
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editor = .edit(preset) }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    requestDeletion(preset)
                                }
                            }
                    }
                }
            }
            .listRowBackground(MyAppsGlassSurface())
            .listRowSeparatorTint(theme.borderColor)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .myAppsPage()
        .navigationTitle("Pricing Presets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = .create(from: model.selectedPreset)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create pricing preset")
                .disabled(store.loadError != nil || model.isWorking)
            }
        }
        .sheet(item: $editor) { request in
            PricingPresetEditorView(original: request.original, seed: request.seed, store: store)
        }
        .confirmationDialog("Delete Preset?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete Preset", role: .destructive) {
                guard let preset = pendingDeletion else { return }
                do { try store.delete(preset) }
                catch { errorMessage = error.localizedDescription }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Delete \(pendingDeletion?.displayName ?? "this preset") from all apps and products? An active selection falls back to Balanced. Existing proposals and submitted prices are retained.")
        }
        .alert("Could Not Update Presets", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func requestDeletion(_ preset: RegionalPricingPreset) {
        pendingDeletion = preset
        confirmingDeletion = true
    }

    private func presetRow(_ preset: RegionalPricingPreset) -> some View {
        Button {
            model.selectPreset(preset.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(preset.displayName)
                        .foregroundStyle(theme.primaryForegroundColor)
                    Text(preset.percentageSummary)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryForegroundColor)
                    if preset.isBuiltIn {
                        Text("Built-in · Read-only")
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryForegroundColor)
                    }
                }
                Spacer()
                if model.selectedPreset.id == preset.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)
        .accessibilityAddTraits(model.selectedPreset.id == preset.id ? .isSelected : [])
    }
}

private struct PresetEditorRequest: Identifiable {
    let id = UUID()
    let original: RegionalPricingPreset?
    let seed: RegionalPricingPreset

    static func create(from preset: RegionalPricingPreset) -> Self { .init(original: nil, seed: preset) }
    static func edit(_ preset: RegionalPricingPreset) -> Self { .init(original: preset, seed: preset) }
}

private struct PricingPresetEditorView: View {
    @Environment(\.appFoundationTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let original: RegionalPricingPreset?
    let store: PricingPresetStore
    @State private var name: String
    @State private var percentages: [String]
    @State private var errorMessage: String?

    init(original: RegionalPricingPreset?, seed: RegionalPricingPreset, store: PricingPresetStore) {
        self.original = original
        self.store = store
        _name = State(initialValue: original?.displayName ?? "")
        _percentages = State(initialValue: (1...5).map {
            NSDecimalNumber(decimal: (seed.factors[$0] ?? 1) * 100).stringValue
        })
    }

    private var factors: [Int: Decimal]? {
        var result: [Int: Decimal] = [:]
        for (index, text) in percentages.enumerated() {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard normalized.range(of: #"^\d{1,3}(\.\d{1,2})?$"#,
                options: .regularExpression) != nil,
                  let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
                return nil
            }
            result[index + 1] = amount / 100
        }
        return result
    }

    private var maySave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60, let factors else { return false }
        return RegionalPricingPreset(id: "validation", version: 1, factors: factors).hasValidFactors &&
            store.loadError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Name") {
                        TextField("Preset name", text: $name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                    }
                    Section {
                        ForEach(1...5, id: \.self) { tier in
                            HStack {
                                Text("Tier \(tier)")
                                Spacer()
                                TextField("Percent", text: $percentages[tier - 1])
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .disabled(tier == 1)
                                    .accessibilityLabel("Tier \(tier) percentage")
                                Text("%")
                            }
                        }
                    } header: {
                        Text("Tier Percentages")
                    } footer: {
                        Text("Tier 1 stays at 100%, and your exact US reference is unchanged. Other percentages must be greater than 0, no more than 100, and decrease or stay equal from Tier 1 to Tier 5. Up to two decimal places are supported. Country-to-tier assignments do not change.")
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.orange) }
                    }
                }
                .listRowBackground(MyAppsGlassSurface())
                .listRowSeparatorTint(theme.borderColor)
            }
            .scrollContentBackground(.hidden)
            .myAppsPage()
            .navigationTitle(original == nil ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let factors else { return }
                        do {
                            try store.save(name: name, factors: factors, editing: original)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(!maySave)
                }
            }
        }
    }
}
