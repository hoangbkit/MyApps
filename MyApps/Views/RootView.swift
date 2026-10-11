import SwiftData
import SwiftUI

private enum RootTab: Hashable {
    case repos, apps, appStore, notes, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var gitHubSession = GitHubSession()
    @StateObject private var appStoreSession = AppStoreConnectSession()
    @State private var selectedTab: RootTab = .repos
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some View {
        TabView(selection: $selectedTab) {
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
                ProjectsView()
            }
            .tabItem {
                Label("Apps", systemImage: "square.grid.2x2")
            }
            .tag(RootTab.apps)

            NavigationStack {
                AppStoreAppsView {
                    selectedTab = .settings
                }
            }
            .id(appStoreSession.connectionRevision)
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
        .environmentObject(appStoreSession)
        .preferredColorScheme(appearance.colorScheme)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            async let restoreGitHub: Void = gitHubSession.restore()
            async let restoreAppStore: Void = appStoreSession.restore()
            _ = await (restoreGitHub, restoreAppStore)
        }
        .fontDesign(.rounded)
        .task { @MainActor in
            P3MigrationService.run(in: modelContext)
        }
    }
}
