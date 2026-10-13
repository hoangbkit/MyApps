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

private enum StoreVersionStatus: Hashable {
    case live
    case pending
    case problem
    case inactive

    init(_ rawValue: String?) {
        switch rawValue?.uppercased() {
        case "READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "PREORDER_READY_FOR_SALE":
            self = .live
        case "DEVELOPER_REJECTED", "INVALID_BINARY", "METADATA_REJECTED", "REJECTED":
            self = .problem
        case "ACCEPTED", "IN_REVIEW", "PENDING_APPLE_RELEASE", "PENDING_CONTRACT",
             "PENDING_DEVELOPER_RELEASE", "PREPARE_FOR_SUBMISSION", "PROCESSING_FOR_APP_STORE",
             "PROCESSING_FOR_DISTRIBUTION", "READY_FOR_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE",
             "WAITING_FOR_REVIEW":
            self = .pending
        default:
            self = .inactive
        }
    }

    func color(fallback: Color) -> Color {
        switch self {
        case .live: .green
        case .pending: .yellow
        case .problem: .red
        case .inactive: fallback
        }
    }
}

private struct StoreVersionSummary {
    let platform: String
    let version: String
    let state: String?
    let status: StoreVersionStatus

    var label: String { "\(platform) \(version)" }
}

private struct StoreVersionGroup: Identifiable {
    let status: StoreVersionStatus
    var versions: [StoreVersionSummary]

    var id: StoreVersionStatus { status }
    var label: String { versions.map(\.label).joined(separator: ", ") }
}

struct AppStoreAppsView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppStoreConnectSession

    let onOpenSettings: () -> Void

    @State private var apps: [AppStoreConnectApp] = []
    @State private var iconURLsByAppID: [String: URL] = [:]
    @State private var versionsByAppID: [String: [AppStoreConnectVersion]] = [:]
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
        .myAppsPage()
        .navigationTitle("Apps")
        .navigationSubtitle("\(filteredApps.count) Apps")
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
                versionsByAppID = [:]
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
            Group {
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
                                    versionSummary(for: app)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(foundationTheme.borderColor)
        }
        .scrollContentBackground(.hidden)
        .myAppsPage()
        .listStyle(.plain)

        .searchable(text: $searchText, prompt: "Search apps")
        .refreshable {
            await loadApps(bypassCache: true)
        }
    }

    @MainActor
    private func loadApps(bypassCache: Bool = false) async {
        guard let client = session.client() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog = try await client.appsWithIcons(bypassCache: bypassCache)
            guard !Task.isCancelled else { return }
            apps = catalog.apps
            iconURLsByAppID = catalog.iconURLsByAppID
            versionsByAppID = catalog.versionsByAppID
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

    @ViewBuilder
    private func versionSummary(for app: AppStoreConnectApp) -> some View {
        let groups = versionGroups(for: app)
        if groups.isEmpty {
            Text("No App Store Versions")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(foundationTheme.secondaryForegroundColor)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(groups) { group in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(group.status.color(fallback: foundationTheme.secondaryForegroundColor))
                            .frame(width: 7, height: 7)
                        Text(group.label)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: group))
                }
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(foundationTheme.secondaryForegroundColor)
        }
    }

    private func versionGroups(for app: AppStoreConnectApp) -> [StoreVersionGroup] {
        let versions = versionsByAppID[app.id] ?? []
        let byPlatform = Dictionary(grouping: versions) {
            $0.attributes.platform ?? ""
        }
        let latestByPlatform = byPlatform.compactMap { platform, versions -> StoreVersionSummary? in
            guard !platform.isEmpty,
                  let latest = versions.max(by: versionIsOlder),
                  let version = latest.attributes.versionString,
                  !version.isEmpty else { return nil }
            return StoreVersionSummary(
                platform: displayPlatform(platform),
                version: version,
                state: latest.attributes.state,
                status: StoreVersionStatus(latest.attributes.state)
            )
        }
        .sorted { lhs, rhs in
            let leftRank = platformRank(lhs.platform)
            let rightRank = platformRank(rhs.platform)
            return leftRank == rightRank
                ? lhs.platform.localizedStandardCompare(rhs.platform) == .orderedAscending
                : leftRank < rightRank
        }

        var groups: [StoreVersionGroup] = []
        for version in latestByPlatform {
            if let index = groups.firstIndex(where: { $0.status == version.status }) {
                groups[index].versions.append(version)
            } else {
                groups.append(StoreVersionGroup(status: version.status, versions: [version]))
            }
        }
        return groups
    }

    private func versionIsOlder(_ lhs: AppStoreConnectVersion, _ rhs: AppStoreConnectVersion) -> Bool {
        let leftDate = lhs.attributes.createdDate ?? ""
        let rightDate = rhs.attributes.createdDate ?? ""
        if leftDate != rightDate { return leftDate < rightDate }

        let leftVersion = lhs.attributes.versionString ?? ""
        let rightVersion = rhs.attributes.versionString ?? ""
        let comparison = leftVersion.localizedStandardCompare(rightVersion)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func displayPlatform(_ platform: String) -> String {
        switch platform.uppercased() {
        case "IOS": "iOS"
        case "MAC_OS": "macOS"
        case "TV_OS": "tvOS"
        case "VISION_OS": "visionOS"
        default: platform
        }
    }

    private func platformRank(_ platform: String) -> Int {
        switch platform {
        case "iOS": 0
        case "macOS": 1
        case "tvOS": 2
        case "visionOS": 3
        default: 4
        }
    }

    private func accessibilityLabel(for group: StoreVersionGroup) -> String {
        let states = Set(group.versions.compactMap(\.state)).sorted()
        let status = states.isEmpty
            ? "Unknown status"
            : states.map {
                $0.replacingOccurrences(of: "_", with: " ").localizedCapitalized
            }.joined(separator: ", ")
        return "\(group.label), \(status)"
    }
}
