import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some View {
        TabView {
            NavigationStack {
                ProjectsView()
            }
            .tabItem {
                Label("Apps", systemImage: "square.grid.2x2")
            }

            NavigationStack {
                RepositoriesView()
            }
            .tabItem {
                Label("Repos", systemImage: "shippingbox")
            }

            NavigationStack {
                AppStorePlaceholderView()
            }
            .tabItem {
                Label("App Store", systemImage: "storefront")
            }

            NavigationStack {
                NotesInboxView()
            }
            .tabItem {
                Label("Notes", systemImage: "note.text")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .fontDesign(.rounded)
        .task { @MainActor in
            P3MigrationService.run(in: modelContext)
        }
    }
}
