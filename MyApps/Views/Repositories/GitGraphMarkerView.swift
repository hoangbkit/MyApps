import SwiftUI

/// A row-height-aware section of the commit DAG.
/// Adjacent rows share the same lane coordinates, so edges remain connected.
struct GitGraphMarkerView: View {
    let layout: GitGraphRowLayout
    let laneSpacing: CGFloat

    private static let laneColors: [Color] = [
        Color(red: 0.13, green: 0.55, blue: 0.95),
        Color(red: 0.92, green: 0.59, blue: 0.20),
        Color(red: 0.54, green: 0.41, blue: 0.88),
        Color(red: 0.20, green: 0.70, blue: 0.58),
        Color(red: 0.89, green: 0.37, blue: 0.53),
        Color(red: 0.21, green: 0.69, blue: 0.81)
    ]

    var body: some View {
        Canvas { context, size in
            let nodeY: CGFloat = 22
            let nodeX = x(for: layout.nodeLane)
            let bottomY = size.height

            for lane in layout.continuingLanes {
                var line = Path()
                line.move(to: CGPoint(x: x(for: lane), y: 0))
                line.addLine(to: CGPoint(x: x(for: lane), y: bottomY))
                stroke(line, color: color(for: lane), in: context)
            }

            for lane in layout.incomingLanes {
                let startX = x(for: lane)
                var line = Path()
                line.move(to: CGPoint(x: startX, y: 0))
                if startX == nodeX {
                    line.addLine(to: CGPoint(x: nodeX, y: nodeY))
                } else {
                    line.addCurve(
                        to: CGPoint(x: nodeX, y: nodeY),
                        control1: CGPoint(x: startX, y: nodeY * 0.58),
                        control2: CGPoint(x: nodeX, y: nodeY * 0.58)
                    )
                }
                stroke(line, color: color(for: lane), in: context)
            }

            for lane in layout.outgoingLanes {
                let endX = x(for: lane)
                var line = Path()
                line.move(to: CGPoint(x: nodeX, y: nodeY))
                if endX == nodeX {
                    line.addLine(to: CGPoint(x: nodeX, y: bottomY))
                } else {
                    line.addCurve(
                        to: CGPoint(x: endX, y: bottomY),
                        control1: CGPoint(x: nodeX, y: nodeY + 25),
                        control2: CGPoint(x: endX, y: bottomY - 20)
                    )
                }
                stroke(line, color: color(for: lane), in: context)
            }

            let nodeRadius: CGFloat = layout.isMerge ? 7 : 5
            let outer = CGRect(
                x: nodeX - nodeRadius - 2,
                y: nodeY - nodeRadius - 2,
                width: (nodeRadius + 2) * 2,
                height: (nodeRadius + 2) * 2
            )
            context.fill(Path(ellipseIn: outer), with: .color(Color(uiColor: .systemGroupedBackground)))

            let inner = CGRect(
                x: nodeX - nodeRadius,
                y: nodeY - nodeRadius,
                width: nodeRadius * 2,
                height: nodeRadius * 2
            )
            context.fill(Path(ellipseIn: inner), with: .color(color(for: layout.nodeLane)))
        }
        .accessibilityHidden(true)
    }

    private func x(for lane: Int) -> CGFloat {
        12 + CGFloat(lane) * laneSpacing
    }

    private func color(for lane: Int) -> Color {
        Self.laneColors[lane % Self.laneColors.count]
    }

    private func stroke(_ path: Path, color: Color, in context: GraphicsContext) {
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        )
    }
}
