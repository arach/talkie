import SwiftUI

struct NotchGuideOverlay: View {
    let parameters: NotchParameters
    let curveMode: InnerCurveMode

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let baseWing = max(0, min(parameters.pokeOut, w / 2))
                let baseGap = max(0, min(parameters.notchWidth, w - (baseWing * 2)))
                let overlap = baseWing > 0
                    ? max(0, min(parameters.notchOverlap, baseGap / 2))
                    : 0

                let wing = baseWing + overlap
                let gap = max(0, baseGap - (overlap * 2))
                let tor = min(abs(parameters.topOuterRadius), min(wing, h) / 2)
                let ir = max(0, min(parameters.topInnerRadius, max(0, wing - tor), h / 2))

                let innerLeft = wing
                let innerRight = wing + gap

                var topEdge = Path()
                topEdge.move(to: CGPoint(x: 0, y: 0))
                topEdge.addLine(to: CGPoint(x: w, y: 0))
                context.stroke(topEdge, with: .color(.yellow.opacity(0.7)), lineWidth: 1)

                var boundaries = Path()
                boundaries.move(to: CGPoint(x: innerLeft, y: 0))
                boundaries.addLine(to: CGPoint(x: innerLeft, y: h))
                boundaries.move(to: CGPoint(x: innerRight, y: 0))
                boundaries.addLine(to: CGPoint(x: innerRight, y: h))
                context.stroke(boundaries, with: .color(.mint.opacity(0.65)), lineWidth: 1)

                guard ir > 0, curveMode != .hardCorner else { return }

                let leftStart = CGPoint(x: innerLeft - ir, y: 0)
                let leftEnd = CGPoint(x: innerLeft, y: ir)
                let rightStart = CGPoint(x: innerRight, y: ir)
                let rightEnd = CGPoint(x: innerRight + ir, y: 0)

                let leftControl: CGPoint
                let rightControl: CGPoint
                switch curveMode {
                case .canonicalDownward:
                    leftControl = CGPoint(x: innerLeft, y: 0)
                    rightControl = CGPoint(x: innerRight, y: 0)
                case .mirroredUpward:
                    leftControl = CGPoint(x: innerLeft - ir, y: ir)
                    rightControl = CGPoint(x: innerRight + ir, y: ir)
                case .hardCorner:
                    return
                }

                drawHandle(context: context, start: leftStart, control: leftControl, end: leftEnd, color: .orange)
                drawHandle(context: context, start: rightStart, control: rightControl, end: rightEnd, color: .orange)
            }
        }
    }

    private func drawHandle(
        context: GraphicsContext,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        color: Color
    ) {
        var line = Path()
        line.move(to: start)
        line.addLine(to: control)
        line.addLine(to: end)
        context.stroke(line, with: .color(color.opacity(0.7)), style: .init(lineWidth: 1, dash: [4, 3]))

        let dotSize: CGFloat = 6
        context.fill(
            Circle().path(in: CGRect(x: start.x - dotSize / 2, y: start.y - dotSize / 2, width: dotSize, height: dotSize)),
            with: .color(.white.opacity(0.9))
        )
        context.fill(
            Circle().path(in: CGRect(x: control.x - dotSize / 2, y: control.y - dotSize / 2, width: dotSize, height: dotSize)),
            with: .color(color)
        )
        context.fill(
            Circle().path(in: CGRect(x: end.x - dotSize / 2, y: end.y - dotSize / 2, width: dotSize, height: dotSize)),
            with: .color(.white.opacity(0.9))
        )
    }
}
