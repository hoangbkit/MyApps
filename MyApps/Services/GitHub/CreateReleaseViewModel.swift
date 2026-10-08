import Combine
import Foundation

@MainActor
final class CreateReleaseViewModel: ObservableObject {
    @Published var selectedTagName: String
    @Published var title: String
    @Published var notes = ""
    @Published var isDraft = false
    @Published var isPrerelease = false
    @Published private(set) var isCreating = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let repositoryName: String
    private let existingReleases: [GitHubRelease]

    init(
        repositoryName: String,
        tags: [GitHubTag],
        existingReleases: [GitHubRelease]
    ) {
        self.repositoryName = repositoryName
        self.existingReleases = existingReleases

        let firstTag = tags.first(where: { !$0.name.hasPrefix("mycli-build-") })?.name
            ?? tags.first?.name
            ?? ""
        selectedTagName = firstTag
        title = firstTag.isEmpty ? "" : "\(repositoryName) \(firstTag)"
    }

    var canCreate: Bool {
        !selectedTagName.isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !existingReleases.contains(where: { $0.tagName == selectedTagName })
    }

    var validationMessage: String? {
        guard !selectedTagName.isEmpty else {
            return "Choose a tag."
        }

        if existingReleases.contains(where: { $0.tagName == selectedTagName }) {
            return "A release already exists for \(selectedTagName)."
        }

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a release title."
        }

        return nil
    }

    func selectTag(_ tag: String) {
        let previousDefault = selectedTagName.isEmpty ? "" : "\(repositoryName) \(selectedTagName)"
        let shouldReplaceTitle =
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            title == previousDefault

        selectedTagName = tag

        if shouldReplaceTitle {
            title = "\(repositoryName) \(tag)"
        }
    }

    @discardableResult
    func create(
        repository: GitHubRepository,
        client: GitHubAPIClient?
    ) async -> Bool {
        guard let client else {
            errorMessage = "GitHub is not connected."
            return false
        }

        guard canCreate else {
            errorMessage = validationMessage ?? "Complete the release details."
            return false
        }

        isCreating = true
        defer { isCreating = false }

        do {
            let latestReleases = try await client.releases(repository: repository)
            guard !latestReleases.contains(where: { $0.tagName == selectedTagName }) else {
                errorMessage = "A release already exists for \(selectedTagName)."
                return false
            }

            let latestTags = try await client.tags(repository: repository)
            guard latestTags.contains(where: { $0.name == selectedTagName }) else {
                errorMessage = "Tag \(selectedTagName) no longer exists."
                return false
            }

            let request = GitHubCreateReleaseRequest(
                tagName: selectedTagName,
                targetCommitish: repository.defaultBranch,
                name: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                draft: isDraft,
                prerelease: isPrerelease
            )

            _ = try await client.createRelease(
                repository: repository,
                request: request
            )

            successMessage = "Created release \(selectedTagName)."
            errorMessage = nil
            return true
        } catch {
            guard !Task.isCancelled, !GitHubAPIClient.isCancellation(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
