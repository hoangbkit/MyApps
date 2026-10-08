import SwiftUI

struct RepositoriesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: GitHubSession
    @StateObject private var repositoriesModel = RepositoriesViewModel()

    let onOpenSettings: () -> Void

    @State private var searchText = ""

    private var filteredRepositories: [GitHubRepository] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return repositoriesModel.repositories
        }

        return repositoriesModel.repositories.filter { repository in
            repository.name.localizedCaseInsensitiveContains(query) ||
            repository.fullName.localizedCaseInsensitiveContains(query) ||
            (repository.language?.localizedCaseInsensitiveContains(query) ?? false)
        }
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
        .task(id: "\(session.connectionRevision)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            switch session.connectionState {
            case .loading:
                break
            case .disconnected:
                repositoriesModel.reset()
                searchText = ""
            case .connected:
                await repositoriesModel.load(using: session.client())
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
        if repositoriesModel.isLoading && repositoriesModel.repositories.isEmpty {
            ProgressView("Loading repositories…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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

        } else {
            List {
                if filteredRepositories.isEmpty {
                    ContentUnavailableView(
                        "No Matching Repositories",
                        systemImage: "magnifyingglass",
                        description: Text("No repositories match “\(searchText)”.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(filteredRepositories) { repository in
                            NavigationLink {
                                RepositoryWorkspaceView(
                                    repository: repository,
                                    client: session.client()
                                )
                            } label: {
                                repositoryRow(repository)
                            }
                        }
                    } header: {
                        Text("\(filteredRepositories.count) Repositories")
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
    }

    private func repositoryRow(_ repository: GitHubRepository) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
