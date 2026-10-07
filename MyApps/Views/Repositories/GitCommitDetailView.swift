import SwiftUI
import UIKit

struct GitCommitDetailView: View {
    let commit: GitHubCommit
    let references: GitHubCommitReferences

    @State private var didCopySHA = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(commit.subject)
                        .font(.system(size: 21, weight: .bold, design: .rounded))

                    Text(commit.authorName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    if let authoredAt = commit.authoredAt {
                        Text(authoredAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !references.isEmpty {
                Section("Refs") {
                    ForEach(references.branches, id: \.self) { branch in
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }

                    ForEach(references.tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                    }
                }
            }

            Section("Commit") {
                LabeledContent("SHA", value: commit.sha)

                if commit.parents.isEmpty {
                    LabeledContent("Parents", value: "None")
                } else {
                    ForEach(Array(commit.parents.enumerated()), id: \.element.sha) { index, parent in
                        LabeledContent(
                            commit.parents.count == 1 ? "Parent" : "Parent \(index + 1)",
                            value: String(parent.sha.prefix(12))
                        )
                    }
                }

                if commit.isMerge {
                    Label("Merge commit", systemImage: "arrow.triangle.merge")
                }
            }

            if commit.commit.message != commit.subject {
                Section("Message") {
                    Text(commit.commit.message)
                        .textSelection(.enabled)
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = commit.sha
                    didCopySHA = true
                } label: {
                    Label(didCopySHA ? "SHA Copied" : "Copy SHA", systemImage: "doc.on.doc")
                }

                Link(destination: commit.htmlURL) {
                    Label("Open on GitHub", systemImage: "safari")
                }
            }
        }
        .navigationTitle(commit.shortSHA)
        .navigationBarTitleDisplayMode(.inline)
    }
}
