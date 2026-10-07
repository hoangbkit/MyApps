import SwiftUI

struct RepositoriesView: View {
    @StateObject private var session = GitHubSession()
    @StateObject private var repositoriesModel = RepositoriesViewModel()

    @State private var token = ""
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
                connectionView

            case let .connected(account):
                repositoriesView(account)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Repos")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await session.restore()
        }
        .alert(
            "GitHub",
            isPresented: Binding(
                get: { session.errorMessage != nil || repositoriesModel.errorMessage != nil },
                set: {
                    if !$0 {
                        session.errorMessage = nil
                        repositoriesModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? repositoriesModel.errorMessage ?? "")
        }
    }

    private var connectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect GitHub")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Connect your GitHub account to browse repositories and use Git operations from MyApps.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Personal access token")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    SecureField("github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .padding(12)
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    Text("The token is validated with GitHub and stored only in this device's Keychain. Use repository Contents read/write permission for private repos and Git write operations.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        if await session.connect(token: token) {
                            token = ""
                            await repositoriesModel.load(using: session.client(), force: true)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if session.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(session.isWorking ? "Connecting…" : "Connect GitHub")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    session.isWorking ||
                    token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func repositoriesView(_ account: GitHubAccount) -> some View {
        if repositoriesModel.isLoading && repositoriesModel.repositories.isEmpty {
            ProgressView("Loading repositories…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: account.id) {
                    await repositoriesModel.load(using: session.client())
                }
                .toolbar {
                    accountToolbar(account)
                }
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
            .task(id: account.id) {
                await repositoriesModel.load(using: session.client())
            }
            .toolbar {
                accountToolbar(account)
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
            .task(id: account.id) {
                await repositoriesModel.load(using: session.client())
            }
            .toolbar {
                accountToolbar(account)
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

    @ToolbarContentBuilder
    private func accountToolbar(_ account: GitHubAccount) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Label("@\(account.login)", systemImage: "person.crop.circle.badge.checkmark")

                Button(role: .destructive) {
                    repositoriesModel.reset()
                    searchText = ""
                    session.disconnect()
                } label: {
                    Label("Disconnect GitHub", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("GitHub Account")
        }
    }
}
