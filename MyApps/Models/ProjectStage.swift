import Foundation

// Retained only to read the P1 `stageRawValue` field without changing the
// SwiftData schema. P2 has a single project kind: app.
enum ProjectStage: String, Identifiable, Codable {
    case app = "App"

    var id: String { rawValue }
}
