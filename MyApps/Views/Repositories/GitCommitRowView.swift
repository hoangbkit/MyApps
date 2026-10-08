import SwiftUI

struct GitCommitRowView: View {
    let commit: GitHubCommit
    let references: GitHubCommitReferences
    let graph: GitGraphRowLayout
    let graphWidth: CGFloat
    let laneSpacing: CGFloat

    var body: some View {
        // Reserve a real column for the graph. Never overlay the graph over
        // the commit content: badges and wrapped titles must not cross lanes.
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: graphWidth)
                .accessibilityHidden(true)

            commitContent
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(alignment: .leading) {
            // The background receives this row's actual height, unlike the
            // previous fixed-height overlay. The graph stays in its column.
            GitGraphMarkerView(
                layout: graph,
                laneSpacing: laneSpacing,
                nodeY: references.isEmpty ? 20 : 46
            )
            .frame(width: graphWidth)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Color.primary.opacity(0.045)
                .frame(height: 0.5)
                .padding(.leading, graphWidth + 10)
        }
        .contentShape(Rectangle())
    }

    private var commitContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !references.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
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
                // Keep the scroll view clipped to the text column, including
                // after the user scrolls long branch/tag names horizontally.
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(commit.subject)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Text(commit.authorName)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let authoredAt = commit.authoredAt {
                    Text("·")
                    Text(authoredAt, style: .relative)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                if commit.isMerge {
                    Image(systemName: "arrow.triangle.merge")
                        .accessibilityLabel("Merge commit")
                }

                Spacer(minLength: 2)

                Text(commit.shortSHA)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GitReferencePill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.09), in: Capsule())
    }
}
