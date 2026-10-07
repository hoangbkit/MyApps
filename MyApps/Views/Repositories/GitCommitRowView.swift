import SwiftUI

struct GitCommitRowView: View {
    let commit: GitHubCommit
    let references: GitHubCommitReferences
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GitGraphMarkerView(commit: commit, isLast: isLast)

            VStack(alignment: .leading, spacing: 7) {
                if !references.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(references.branches, id: \.self) { branch in
                                Label(branch, systemImage: "arrow.triangle.branch")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }

                            ForEach(references.tags, id: \.self) { tag in
                                Label(tag, systemImage: "tag")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .scrollClipDisabled()
                }

                Text(commit.subject)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 7) {
                    Text(commit.shortSHA)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if commit.isMerge {
                        Label("Merge", systemImage: "arrow.triangle.merge")
                    }

                    Text(commit.authorName)

                    if let authoredAt = commit.authoredAt {
                        Text(authoredAt, format: .relative(presentation: .named))
                    }
                }
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.top, 7)
            .padding(.bottom, 10)
        }
        .contentShape(Rectangle())
    }
}
