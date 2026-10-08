import SwiftUI

struct ReleasesView: View {
    let repository: GitHubRepository
    let client: GitHubAPIClient?

    @StateObject private var model = ReleasesViewModel()

    private var tags: [GitHubTag] { model.tags }

    private var productReleases: [GitHubRelease] {
        model.releases.filter { !$0.isMyCLIBuild }
    }

    private var buildReleases: [GitHubRelease] {
        model.releases.filter { $0.isMyCLIBuild }
    }

    var body: some View {
        List {
            if model.isLoading && model.releases.isEmpty {
                ProgressView("Loading releases…")
            } else {
                Section {
                    NavigationLink {
                        CreateReleaseView(
                            repository: repository,
                            tags: tags,
                            existingReleases: model.releases,
                            client: client
                        ) {
                            Task {
                                await model.load(
                                    repository: repository,
                                    client: client,
                                    force: true
                                )
                            }
                        }
                    } label: {
                        Label("Create Release", systemImage: "plus.circle")
                    }
                    .disabled(
                        tags.isEmpty ||
                        !repository.canAttemptWrite
                    )
                }

                releaseSection(
                    title: "Product Releases",
                    releases: productReleases
                )

                if !buildReleases.isEmpty {
                    releaseSection(
                        title: "Build Prereleases",
                        releases: buildReleases
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await refresh()
        }
        .task {
            await refresh()
        }
        .alert(
            "GitHub",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func refresh() async {
        await model.load(
            repository: repository, client: client, force: true
        )
    }

    @ViewBuilder
    private func releaseSection(
        title: String,
        releases: [GitHubRelease]
    ) -> some View {
        Section(title) {
            if releases.isEmpty {
                Text("No releases")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(releases) { release in
                    Link(destination: release.htmlURL) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text(release.displayName)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                if release.draft {
                                    badge("Draft")
                                }

                                if release.prerelease {
                                    badge("Prerelease")
                                }
                            }

                            HStack(spacing: 8) {
                                Text(release.tagName)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))

                                Text(release.displayDate, style: .date)
                            }
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
