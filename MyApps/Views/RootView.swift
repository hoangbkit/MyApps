import SwiftData
import SwiftUI

private enum RootTab: Hashable {
    case apps, repos, appStore, notes, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var gitHubSession = GitHubSession()
    @State private var selectedTab: RootTab = .apps
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ProjectsView()
            }
            .tabItem {
                Label("Apps", systemImage: "square.grid.2x2")
            }
            .tag(RootTab.apps)

            NavigationStack {
                RepositoriesView {
                    selectedTab = .settings
                }
            }
            .id(gitHubSession.connectionRevision)
            .tabItem {
                Label("Repos", systemImage: "shippingbox")
            }
            .tag(RootTab.repos)

            NavigationStack {
                AppStorePlaceholderView()
            }
            .tabItem {
                Label("App Store", systemImage: "storefront")
            }
            .tag(RootTab.appStore)

            NavigationStack {
                NotesInboxView()
            }
            .tabItem {
                Label("Notes", systemImage: "note.text")
            }
            .tag(RootTab.notes)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(RootTab.settings)
        }
        .environmentObject(gitHubSession)
        .preferredColorScheme(appearance.colorScheme)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await gitHubSession.restore()
        }
        .fontDesign(.rounded)
        .task { @MainActor in
            P3MigrationService.run(in: modelContext)
        }
    }
}
