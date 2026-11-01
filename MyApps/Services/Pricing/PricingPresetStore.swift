import Foundation
import Observation

/// Global user presets, independent of App Store accounts, apps and products.
/// Persist before publishing changes so failed saves never appear successful.
@MainActor
@Observable
final class PricingPresetStore {
    static let shared = PricingPresetStore()

    private(set) var customPresets: [RegionalPricingPreset] = []
    private(set) var loadError: String?
    private var fileURL: URL?

    var presets: [RegionalPricingPreset] { [.balanced] + customPresets }

    private struct Document: Codable, Sendable {
        let schemaVersion: Int
        let presets: [RegionalPricingPreset]
    }

    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PricingPresets", isDirectory: true)
        fileURL = root?.appendingPathComponent("presets-v1.json")
        reload()
    }

    func preset(id: String) -> RegionalPricingPreset? {
        presets.first { $0.id == id }
    }

    func reload() {
        do {
            guard let fileURL else { throw failure("Preset storage is unavailable.") }
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                customPresets = []
            } else {
                let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
                guard document.schemaVersion == 1 else {
                    throw failure("This preset storage version is not supported.")
                }
                try validate(document.presets)
                customPresets = document.presets
            }
            loadError = nil
        } catch {
            // Keep the last usable in-memory list; block writes instead of
            // overwriting an unreadable file with an empty list.
            loadError = "Could not load saved presets: " + error.localizedDescription
        }
    }

    @discardableResult
    func save(name: String, factors: [Int: Decimal], editing original: RegionalPricingPreset?)
        throws -> RegionalPricingPreset {
        guard loadError == nil else { throw failure("Reload saved presets before making changes.") }
        var updated = customPresets
        let result: RegionalPricingPreset
        if let original {
            guard !original.isBuiltIn,
                  let index = updated.firstIndex(where: { $0.id == original.id }),
                  updated[index] == original, original.version < Int.max else {
                throw failure("This preset changed or was deleted. Reopen it before editing.")
            }
            result = RegionalPricingPreset(id: original.id, version: original.version + 1,
                factors: factors, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            updated[index] = result
        } else {
            result = RegionalPricingPreset(id: UUID().uuidString, version: 1,
                factors: factors, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            updated.append(result)
        }
        try validate(updated)
        try persist(updated)
        customPresets = updated
        return result
    }

    func delete(_ preset: RegionalPricingPreset) throws {
        guard loadError == nil else { throw failure("Reload saved presets before making changes.") }
        guard !preset.isBuiltIn,
              customPresets.contains(preset) else {
            throw failure("This preset changed or was deleted. Refresh the list before deleting.")
        }
        let updated = customPresets.filter { $0.id != preset.id }
        try persist(updated)
        customPresets = updated
    }

    private func validate(_ presets: [RegionalPricingPreset]) throws {
        var ids: Set<String> = []
        var names: Set<String> = [RegionalPricingPreset.balanced.displayName.lowercased()]
        for preset in presets {
            let name = preset.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !preset.isBuiltIn, UUID(uuidString: preset.id) != nil,
                  preset.version > 0, preset.hasValidFactors,
                  preset.name != nil, !name.isEmpty, name.count <= 60,
                  ids.insert(preset.id).inserted,
                  names.insert(name.lowercased()).inserted else {
                throw failure("Use a unique name of 1–60 characters and five positive, non-increasing percentages. Tier 1 must be 100%.")
            }
        }
    }

    private func persist(_ presets: [RegionalPricingPreset]) throws {
        guard let fileURL else { throw failure("Preset storage is unavailable.") }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Document(schemaVersion: 1, presets: presets))
            .write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func failure(_ message: String) -> RegionalPricingError { .invalidDraft(message) }
}
