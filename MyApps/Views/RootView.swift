import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some View {
        NavigationStack {
            ProjectsView()
        }
        .preferredColorScheme(appearance.colorScheme)
        .fontDesign(.rounded)
        .task { @MainActor in
            P3MigrationService.run(in: modelContext)
        }
    }
}
