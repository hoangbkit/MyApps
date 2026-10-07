import SwiftUI

struct RepositoryWorkspaceView: View {
    let repository: GitHubRepository

    var body: some View {
        List {
            Section {
                LabeledContent("Repository", value: repository.fullName)
                LabeledContent("Default Branch", value: repository.defaultBranch)

                if let language = repository.language {
                    LabeledContent("Language", value: language)
                }

                LabeledContent(
                    "Access",
                    value: repository.hasWriteAccess ? "Read & Write" : "Read Only"
                )
            }

            Section {
                ContentUnavailableView(
                    "Git Log Coming Next",
                    systemImage: "point.3.filled.connected.trianglepath.dotted",
                    description: Text("Phase 3 adds the visual commit graph and history for this repository.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
