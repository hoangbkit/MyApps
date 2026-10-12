import AppFoundation
import SwiftUI

private enum RepositorySortOption: String, CaseIterable, Identifiable {
    case updated, created, name

    static let storageKey = "myapps.repositories.sortOption"

    var id: Self { self }

    var title: String {
        switch self {
        case .updated: "Updated"
        case .created: "Created"
        case .name: "Name"
        }
    }

    var symbolName: String {
        switch self {
        case .updated: "clock"
        case .created: "calendar.badge.plus"
        case .name: "textformat.abc"
        }
    }

    var isText: Bool { self == .name }
}

struct RepositoriesView: View {
    @Environment(\.appFoundationTheme) private var foundationTheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: GitHubSession
    @StateObject private var repositoriesModel = RepositoriesViewModel()

    let onOpenSettings: () -> Void

    @State private var searchText = ""
    @AppStorage(RepositorySortOption.storageKey) private var sortRawValue = RepositorySortOption.updated.rawValue
    @AppStorage("myapps.repositories.sortDirection") private var directionRawValue = SortDirection.descending.rawValue
    @AppStorage("myapps.repositories.pinnedIDs") private var pinnedIDsData = Data()

    private var sortOption: RepositorySortOption {
        RepositorySortOption(rawValue: sortRawValue) ?? .updated
    }

    private var sortDirection: SortDirection {
        SortDirection(rawValue: directionRawValue) ?? .descending
    }

    private var pinnedRepositoryIDs: Set<Int> {
        (try? JSONDecoder().decode(Set<Int>.self, from: pinnedIDsData)) ?? []
    }

    private var filteredRepositories: [GitHubRepository] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinned = pinnedRepositoryIDs

        return repositoriesModel.repositories
            .filter { repository in
                query.isEmpty ||
                repository.name.localizedCaseInsensitiveContains(query) ||
                repository.fullName.localizedCaseInsensitiveContains(query) ||
                (repository.language?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { lhs, rhs in
                let lhsPinned = pinned.contains(lhs.id)
                let rhsPinned = pinned.contains(rhs.id)
                if lhsPinned != rhsPinned { return lhsPinned }

                let ascending = sortDirection == .ascending
                // GitHub can omit dates. Such repositories stay last in either
                // direction, without forcing them above real dated entries.
                let lhsDate: Date?
                let rhsDate: Date?
                switch sortOption {
                case .created:
                    lhsDate = lhs.createdAt
                    rhsDate = rhs.createdAt
                case .updated:
                    lhsDate = lhs.updatedAt ?? lhs.pushedAt
                    rhsDate = rhs.updatedAt ?? rhs.pushedAt
                case .name:
                    lhsDate = nil
                    rhsDate = nil
                }
                if sortOption != .name {
                    if lhsDate == nil && rhsDate != nil { return false }
                    if lhsDate != nil && rhsDate == nil { return true }
                    if let lhsDate, let rhsDate, lhsDate != rhsDate {
                        return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
                    }
                }

                let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return sortOption == .name && !ascending
                        ? nameComparison == .orderedDescending
                        : nameComparison == .orderedAscending
                }
                let fullNameComparison = lhs.fullName.localizedStandardCompare(rhs.fullName)
                if fullNameComparison != .orderedSame {
                    return sortOption == .name && !ascending
                        ? fullNameComparison == .orderedDescending
                        : fullNameComparison == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }

    private var pinnedRepositories: [GitHubRepository] {
        let pinned = pinnedRepositoryIDs
        return filteredRepositories.filter { pinned.contains($0.id) }
    }

    private var unpinnedRepositories: [GitHubRepository] {
        let pinned = pinnedRepositoryIDs
        return filteredRepositories.filter { !pinned.contains($0.id) }
    }

    var body: some View {
        Group {
            switch session.connectionState {
            case .loading:
                ProgressView("Connecting to GitHub…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .disconnected:
                ContentUnavailableView {
                    Label("Connect GitHub", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Add your personal access token in Settings → GitHub to browse repositories.")
                } actions: {
                    Button("Open Settings", action: onOpenSettings)
                        .buttonStyle(.borderedProminent)
                }

            case .connected:
                repositoriesView
            }
        }
        .background(foundationTheme.backgroundColor)
        .navigationTitle("Repos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Sort By") {
                        Picker("Sort Field", selection: $sortRawValue) {
                            ForEach(RepositorySortOption.allCases) { option in
                                Label(option.title, systemImage: option.symbolName)
                                    .tag(option.rawValue)
                            }
                        }
                    }

                    Section("Order") {
                        Picker("Sort Order", selection: $directionRawValue) {
                            ForEach(SortDirection.allCases) { direction in
                                Label(direction.title(isText: sortOption.isText), systemImage: direction.symbolName)
                                    .tag(direction.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort Repositories by \(sortOption.title), \(sortDirection.title(isText: sortOption.isText))")
            }
        }
        .onChange(of: sortRawValue) { _, newField in
            let option = RepositorySortOption(rawValue: newField) ?? .updated
            directionRawValue = SortDirection.defaultForText(option.isText).rawValue
        }
        .task(id: "\(session.connectionRevision)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            switch session.connectionState {
            case .loading:
                break
            case .disconnected:
                repositoriesModel.reset()
                searchText = ""
            case .connected:
                await repositoriesModel.load(using: session.client(), force: true)
            }
        }
        .alert(
            "GitHub",
            isPresented: Binding(
                get: { repositoriesModel.errorMessage != nil },
                set: {
                    if !$0 { repositoriesModel.errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(repositoriesModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var repositoriesView: some View {
        List {
            // A regular list row, not a navigation-bar search drawer:
            // search scrolls away with the repositories.
            searchField
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))

            if repositoriesModel.isLoading && repositoriesModel.repositories.isEmpty {
                ProgressView("Loading repositories…")
            } else if repositoriesModel.repositories.isEmpty {
                ContentUnavailableView {
                    Label("No Repositories", systemImage: "shippingbox")
                } description: {
                    Text("No repositories are available to this GitHub connection.")
                } actions: {
                    Button("Try Again") {
                        Task {
                            await repositoriesModel.load(using: session.client(), force: true)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                if filteredRepositories.isEmpty {
                    ContentUnavailableView(
                        "No Matching Repositories",
                        systemImage: "magnifyingglass",
                        description: Text("No repositories match “\(searchText)”.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    if !pinnedRepositories.isEmpty {
                        Section {
                            ForEach(pinnedRepositories) { repository in
                                repositoryLink(repository)
                            }
                        } header: {
                            Text("Pinned (\(pinnedRepositories.count))")
                        }
                    }

                    if !unpinnedRepositories.isEmpty {
                        Section {
                            ForEach(unpinnedRepositories) { repository in
                                repositoryLink(repository)
                            }
                        } header: {
                            Text("\(unpinnedRepositories.count) Repositories")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await repositoriesModel.load(using: session.client(), force: true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search repositories", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search repositories")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear repository search")
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func repositoryLink(_ repository: GitHubRepository) -> some View {
        let isPinned = pinnedRepositoryIDs.contains(repository.id)

        return NavigationLink {
            RepositoryWorkspaceView(
                repository: repository,
                client: session.client()
            )
        } label: {
            repositoryRow(repository)
        }
        .listRowBackground(foundationTheme.elevatedSurfaceColor)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                togglePin(repository)
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                togglePin(repository)
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
    }

    private func togglePin(_ repository: GitHubRepository) {
        var ids = pinnedRepositoryIDs
        if ids.contains(repository.id) {
            ids.remove(repository.id)
        } else {
            ids.insert(repository.id)
        }
        if let data = try? JSONEncoder().encode(ids) {
            pinnedIDsData = data
        }
    }

    private func repositoryRow(_ repository: GitHubRepository) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if pinnedRepositoryIDs.contains(repository.id) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pinned")
                }

                Text(repository.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                if repository.isPrivate {
                    Text("Private")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                if repository.isArchived {
                    Text("Archived")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            Text(repository.fullName)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let language = repository.language {
                    Label(language, systemImage: "chevron.left.forwardslash.chevron.right")
                }

                if repository.isFork {
                    Label("Fork", systemImage: "tuningfork")
                }

                if repository.permissions != nil && !repository.hasWriteAccess {
                    Label("Read Only", systemImage: "lock")
                }
            }
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

}
