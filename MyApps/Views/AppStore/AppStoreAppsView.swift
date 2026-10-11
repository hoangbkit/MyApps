import SwiftUI

struct AppStoreAppsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppStoreConnectSession

    let onOpenSettings: () -> Void

    @State private var apps: [AppStoreConnectApp] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var errorMessage: String?

    private var filteredApps: [AppStoreConnectApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter {
            query.isEmpty ||
            $0.attributes.name.localizedCaseInsensitiveContains(query) ||
            ($0.attributes.bundleId?.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.attributes.sku?.localizedCaseInsensitiveContains(query) ?? false)
        }
        .sorted {
            let result = $0.attributes.name.localizedStandardCompare($1.attributes.name)
            return result == .orderedSame ? $0.id < $1.id : result == .orderedAscending
        }
    }

    var body: some View {
        Group {
            switch session.connectionState {
            case .loading:
                ProgressView("Connecting to App Store Connect…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .disconnected:
                ContentUnavailableView {
                    Label("Connect App Store Connect", systemImage: "app.badge.checkmark")
                } description: {
                    Text("Add your App Store Connect API key in Settings to see apps and Xcode Cloud builds.")
                } actions: {
                    Button("Open Settings", action: onOpenSettings)
                        .buttonStyle(.borderedProminent)
                }
            case .connected:
                appList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("App Store")
        .navigationBarTitleDisplayMode(.large)
        .task(id: "\(session.connectionRevision)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            switch session.connectionState {
            case .loading:
                break
            case .disconnected:
                apps = []
                hasLoaded = false
                searchText = ""
            case .connected:
                await loadApps()
            }
        }
        .alert(
            "App Store Connect",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var appList: some View {
        List {
            if isLoading && !hasLoaded {
                ProgressView("Loading apps…")
            } else if !hasLoaded && loadFailed {
                ContentUnavailableView {
                    Label("Could Not Load Apps", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Retry") { Task { await loadApps() } }
                }
                .listRowBackground(Color.clear)
            } else if apps.isEmpty {
                ContentUnavailableView {
                    Label("No Apps", systemImage: "square.grid.2x2")
                } description: {
                    Text("No apps are available to this App Store Connect API key.")
                }
                .listRowBackground(Color.clear)
            } else if filteredApps.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredApps) { app in
                        NavigationLink {
                            AppStoreAppDetailView(app: app, client: session.client())
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(app.attributes.name)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                if let bundleID = app.attributes.bundleId {
                                    Text(bundleID)
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                } header: {
                    Text("\(filteredApps.count) Apps")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search apps")
        .refreshable {
            await loadApps()
        }
    }

    @MainActor
    private func loadApps() async {
        guard let client = session.client() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await client.apps()
            guard !Task.isCancelled else { return }
            apps = fetched
            hasLoaded = true
            loadFailed = false
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
            errorMessage = error.localizedDescription
        }
    }
}
