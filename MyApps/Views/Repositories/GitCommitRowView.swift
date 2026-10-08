import SwiftUI

struct GitCommitRowView: View {
    let commit: GitHubCommit
    let references: GitHubCommitReferences
    let graph: GitGraphRowLayout
    let graphWidth: CGFloat
    let laneSpacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !references.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(references.branches, id: \.self) { branch in
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .foregroundStyle(Color.accentColor)
                                .modifier(GitReferencePill())
                        }
                        ForEach(references.tags, id: \.self) { tag in
                            Label(tag, systemImage: "tag")
                                .foregroundStyle(.secondary)
                                .modifier(GitReferencePill())
                        }
                    }
                }
                .scrollClipDisabled()
            }

            Text(commit.subject)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            HStack(spacing: 6) {
                Text(commit.authorName)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let authoredAt = commit.authoredAt {
                    Text("·")
                    Text(authoredAt, style: .relative)
                        .lineLimit(1)
                }

                if commit.isMerge {
                    Text("·")
                    Image(systemName: "arrow.triangle.merge")
                        .accessibilityLabel("Merge commit")
                }

                Spacer(minLength: 6)

                Text(commit.shortSHA)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, graphWidth + 10)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 80, alignment: .topLeading)
        .overlay(alignment: .leading) {
            GitGraphMarkerView(layout: graph, laneSpacing: laneSpacing)
                .frame(width: graphWidth)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Color.primary.opacity(0.06)
                .frame(height: 0.5)
                .padding(.leading, graphWidth + 10)
        }
        .contentShape(Rectangle())
    }
}

private struct GitReferencePill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}
