import SwiftUI

struct GitGraphMarkerView: View {
    let commit: GitHubCommit
    let isLast: Bool

    var body: some View {
        Canvas { context, size in
            let mainX: CGFloat = 12
            let mergeX: CGFloat = 28
            let nodeY: CGFloat = 18

            var mainLine = Path()
            mainLine.move(to: CGPoint(x: mainX, y: 0))
            mainLine.addLine(to: CGPoint(x: mainX, y: isLast ? nodeY : size.height))
            context.stroke(
                mainLine,
                with: .foreground,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            if commit.isMerge {
                var mergeLine = Path()
                mergeLine.move(to: CGPoint(x: mergeX, y: size.height))
                mergeLine.addLine(to: CGPoint(x: mergeX, y: nodeY + 6))
                mergeLine.addQuadCurve(
                    to: CGPoint(x: mainX, y: nodeY),
                    control: CGPoint(x: mergeX, y: nodeY)
                )
                context.stroke(
                    mergeLine,
                    with: .foreground,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }

            let nodeRect = CGRect(
                x: mainX - 5,
                y: nodeY - 5,
                width: 10,
                height: 10
            )
            context.fill(Path(ellipseIn: nodeRect), with: .foreground)
        }
        .foregroundStyle(commit.isMerge ? Color.accentColor : Color.secondary)
        .frame(width: 38, height: 70)
        .accessibilityHidden(true)
    }
}
