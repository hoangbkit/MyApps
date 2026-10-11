import SwiftUI

private enum RepositorySortOption: String, CaseIterable, Identifiable {
    case updated, name

    static let storageKey = "myapps.repositories.sortOption"

    var id: Self { self }

    var title: String {
        switch self {
        case .updated: "Recently Updated"
        case .name: "Name"
        }
    }

    var symbolName: String {
        switch self {
        case .updated: "clock"
        case .name: "textformat.abc"
        }
    }
}

struct RepositoriesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: GitHubSession
    @StateObject private var repositoriesModel = RepositoriesViewModel()

    let onOpenSettings: () -> Void

    @State private var searchText = ""
    @AppStorage(RepositorySortOption.storageKey) private var sortRawValue = RepositorySortOption.updated.rawValue
    @AppStorage("myapps.repositories.pinnedIDs") private var pinnedIDsData = Data()

    private var sortOption: RepositorySortOption {
        RepositorySortOption(rawValue: sortRawValue) ?? .updated
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

                if sortOption == .updated {
                    let lhsDate = lhs.updatedAt ?? lhs.pushedAt ?? .distantPast
                    let rhsDate = rhs.updatedAt ?? rhs.pushedAt ?? .distantPast
                    if lhsDate != rhsDate { return lhsDate > rhsDate }
                }

                let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                let fullNameComparison = lhs.fullName.localizedStandardCompare(rhs.fullName)
                if fullNameComparison != .orderedSame {
                    return fullNameComparison == .orderedAscending
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Repos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort Repositories", selection: $sortRawValue) {
                        ForEach(RepositorySortOption.allCases) { option in
                            Label(option.title, systemImage: option.symbolName)
                                .tag(option.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort Repositories by \(sortOption.title)")
            }
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search repositories"
        )
        .refreshable {
            await repositoriesModel.load(using: session.client(), force: true)
        }
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
