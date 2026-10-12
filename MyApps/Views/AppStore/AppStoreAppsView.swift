import AppFoundation
import SwiftUI

private enum StoreAppSortOption: String, CaseIterable, Identifiable {
    case name, bundleID

    static let storageKey = "myapps.appstore.sortOption"
    static let directionStorageKey = "myapps.appstore.sortDirection"

    var id: Self { self }

    var title: String {
        switch self {
        case .name: "Name"
        case .bundleID: "Bundle ID"
        }
    }

    var symbolName: String {
        switch self {
        case .name: "textformat.abc"
        case .bundleID: "number"
        }
    }
}

struct AppStoreAppsView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppStoreConnectSession

    let onOpenSettings: () -> Void

    @State private var apps: [AppStoreConnectApp] = []
    @State private var iconURLsByAppID: [String: URL] = [:]
    @State private var publicIconURLsByAppID: [String: URL] = [:]
    @State private var searchText = ""
    @AppStorage(StoreAppSortOption.storageKey) private var sortRawValue = StoreAppSortOption.name.rawValue
    @AppStorage(StoreAppSortOption.directionStorageKey) private var directionRawValue = SortDirection.ascending.rawValue

    private var sortOption: StoreAppSortOption {
        StoreAppSortOption(rawValue: sortRawValue) ?? .name
    }

    private var sortDirection: SortDirection {
        SortDirection(rawValue: directionRawValue) ?? .ascending
    }
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
        .sorted { lhs, rhs in
            let ascending = sortDirection == .ascending
            if sortOption == .bundleID {
                // Apps without a bundle ID stay at the end in both directions.
                let left = lhs.attributes.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let right = rhs.attributes.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let leftMissing = left?.isEmpty != false
                let rightMissing = right?.isEmpty != false
                if leftMissing != rightMissing { return !leftMissing }
                if let left, let right {
                    let comparison = left.localizedStandardCompare(right)
                    if comparison != .orderedSame {
                        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                    }
                }
            }
            let comparison = lhs.attributes.name.localizedStandardCompare(rhs.attributes.name)
            if comparison != .orderedSame {
                return sortOption == .name && !ascending
                    ? comparison == .orderedDescending
                    : comparison == .orderedAscending
            }
            return lhs.id < rhs.id
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
        .background(foundationTheme.backgroundColor)
        .navigationTitle("Apps")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Sort By") {
                        Picker("Sort Field", selection: $sortRawValue) {
                            ForEach(StoreAppSortOption.allCases) { option in
                                Label(option.title, systemImage: option.symbolName)
                                    .tag(option.rawValue)
                            }
                        }
                    }
                    Section("Order") {
                        Picker("Sort Order", selection: $directionRawValue) {
                            ForEach(SortDirection.allCases) { direction in
                                Label(direction.title(isText: true), systemImage: direction.symbolName)
                                    .tag(direction.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort Apps by \(sortOption.title), \(sortDirection.title(isText: true))")
            }
        }
        .onChange(of: sortRawValue) { _, _ in
            directionRawValue = SortDirection.ascending.rawValue
        }
        .task(id: "\(session.connectionRevision)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            switch session.connectionState {
            case .loading:
                break
            case .disconnected:
                apps = []
                iconURLsByAppID = [:]
                publicIconURLsByAppID = [:]
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
                            AppStoreAppDetailView(
                                app: app,
                                client: session.client(),
                                iconURL: iconURLsByAppID[app.id],
                                publicIconURL: publicIconURLsByAppID[app.id]
                            )
                        } label: {
                            HStack(spacing: 12) {
                                AppStoreAppIconView(
                                    name: app.attributes.name,
                                    url: iconURLsByAppID[app.id],
                                    fallbackURL: publicIconURLsByAppID[app.id],
                                    appID: app.id
                                )

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
        .scrollContentBackground(.hidden)
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
            let catalog = try await client.appsWithIcons()
            guard !Task.isCancelled else { return }
            apps = catalog.apps
            iconURLsByAppID = catalog.iconURLsByAppID
            hasLoaded = true
            loadFailed = false
            errorMessage = nil

            // Resolve the published artwork in batched requests using exact
            // Apple app IDs. Do this AFTER showing the ASC app list so public
            // lookup never blocks a successfully loaded catalog.
            // Fetch even when ASC has an icon: its CDN download might fail.
            let unresolved = catalog.apps.filter { publicIconURLsByAppID[$0.id] == nil }
            if !unresolved.isEmpty {
                let publicArtwork = await AppStorePublicArtworkLookup.lookup(apps: unresolved)
                guard !Task.isCancelled else { return }
                publicIconURLsByAppID.merge(publicArtwork) { _, newURL in newURL }
            }
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
            errorMessage = error.localizedDescription
        }
    }
}
