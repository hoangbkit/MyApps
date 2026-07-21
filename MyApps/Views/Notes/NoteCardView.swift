import SwiftUI
import UIKit

struct NoteCardView: View {
    let note: QuickNote
    var showsApp: Bool = false
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            NoteThumbnailLayout(contentPadding: 16) {
                VStack(alignment: .leading, spacing: 11) {
                    header

                    Text(excerpt.isEmpty ? "Empty note" : excerpt)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(excerpt.isEmpty ? .tertiary : .primary)
                        .lineSpacing(3)
                        .lineLimit(showsApp ? 3 : 5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if showsApp {
                        Label(
                            note.app?.name ?? "Unassigned",
                            systemImage: note.app == nil ? "tray" : "square.grid.2x2"
                        )
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.noteCardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.noteCardRadius, style: .continuous))
            .surfaceCard(cornerRadius: AppTheme.noteCardRadius)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = note.body
            } label: {
                Label("Copy Whole Text", systemImage: "doc.on.doc")
            }
            .disabled(note.body.isEmpty)

            Button(action: onTogglePin) {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var excerpt: String {
        MarkdownTextExtractor.excerpt(from: note.body)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Keeps every note thumbnail square. The child is placed at its natural height
/// and clipped by the rounded card bounds, so the plain-text excerpt fills the card.
private struct NoteThumbnailLayout: Layout {
    let contentPadding: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        let fallback = subview.sizeThatFits(.unspecified)
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = max(1, proposedWidth ?? fallback.width)

        return CGSize(width: width, height: width)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let contentWidth = max(0, bounds.width - (contentPadding * 2))

        subview.place(
            at: CGPoint(
                x: bounds.minX + contentPadding,
                y: bounds.minY + contentPadding
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: contentWidth, height: nil)
        )
    }
}
