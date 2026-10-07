import Combine
import Foundation

enum GitHubTagKind: String, CaseIterable, Identifiable, Sendable {
    case lightweight = "Lightweight"
    case annotated = "Annotated"

    var id: String { rawValue }
}

@MainActor
final class CreateTagViewModel: ObservableObject {
    @Published var name = ""
    @Published var kind: GitHubTagKind = .lightweight
    @Published var message = ""
    @Published private(set) var isCreating = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let existingTags: [GitHubTag]

    init(existingTags: [GitHubTag]) {
        self.existingTags = existingTags
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCreate: Bool {
        validationError == nil &&
        (kind == .lightweight || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var validationError: String? {
        let value = normalizedName

        guard !value.isEmpty else {
            return "Enter a tag name."
        }

        if existingTags.contains(where: { $0.name == value }) {
            return "Tag \(value) already exists."
        }

        if value == "@" ||
            value.hasPrefix(".") ||
            value.hasSuffix(".") ||
            value.hasPrefix("/") ||
            value.hasSuffix("/") ||
            value.hasSuffix(".lock") ||
            value.contains("..") ||
            value.contains("//") ||
            value.contains("@{") {
            return "Enter a valid Git tag name."
        }

        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\")
            .union(.controlCharacters)

        if value.unicodeScalars.contains(where: { forbidden.contains($0) }) {
            return "Enter a valid Git tag name."
        }

        return nil
    }

    @discardableResult
    func create(
        repository: GitHubRepository,
        targetSHA: String,
        client: GitHubAPIClient?
    ) async -> Bool {
        guard let client else {
            errorMessage = "GitHub is not connected."
            return false
        }

        guard canCreate else {
            errorMessage = validationError ?? "Complete the tag details."
            return false
        }

        isCreating = true
        defer { isCreating = false }

        do {
            let latestTags = try await client.tags(repository: repository)
            guard !latestTags.contains(where: { $0.name == normalizedName }) else {
                errorMessage = "Tag \(normalizedName) already exists."
                return false
            }

            _ = try await client.gitCommit(repository: repository, sha: targetSHA)

            switch kind {
            case .lightweight:
                try await client.createLightweightTag(
                    repository: repository,
                    name: normalizedName,
                    targetSHA: targetSHA
                )

            case .annotated:
                try await client.createAnnotatedTag(
                    repository: repository,
                    name: normalizedName,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    targetSHA: targetSHA
                )
            }

            successMessage = "Created tag \(normalizedName)."
            errorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
