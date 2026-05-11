import SwiftUI

/// Draws only the wing pair. The center notch area remains transparent.
struct CanonicalNotchShape: Shape {
    let parameters: NotchParameters
    let curveMode: InnerCurveMode

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let baseWing = max(0, min(parameters.pokeOut, w / 2))
        let baseGap = max(0, min(parameters.notchWidth, w - (baseWing * 2)))
        let overlap = baseWing > 0
            ? max(0, min(parameters.notchOverlap, baseGap / 2))
            : 0

        let wing = baseWing + overlap
        let gap = max(0, baseGap - (overlap * 2))

        let maxTor = min(wing, h) / 2
        let tor = max(-maxTor, min(parameters.topOuterRadius, maxTor))
        let br = min(parameters.bottomRadius, min(wing, h) / 2)
        let ir = max(0, min(parameters.topInnerRadius, max(0, wing - abs(tor)), h / 2))

        var p = Path()
        addLeftWing(path: &p, wing: wing, height: h, tor: tor, br: br, ir: ir)
        addRightWing(path: &p, wing: wing, gap: gap, height: h, tor: tor, br: br, ir: ir)
        return p
    }

    private func addLeftWing(
        path: inout Path,
        wing: CGFloat,
        height: CGFloat,
        tor: CGFloat,
        br: CGFloat,
        ir: CGFloat
    ) {
        let cornerDrop = abs(tor)
        if cornerDrop > 0 {
            let shoulderX = -tor
            path.move(to: CGPoint(x: 0, y: cornerDrop))
            let center = CGPoint(x: shoulderX, y: cornerDrop)
            if tor >= 0 {
                path.addArc(
                    center: center,
                    radius: cornerDrop,
                    startAngle: .degrees(0),
                    endAngle: .degrees(-90),
                    clockwise: true
                )
            } else {
                path.addArc(
                    center: center,
                    radius: cornerDrop,
                    startAngle: .degrees(180),
                    endAngle: .degrees(-90),
                    clockwise: false
                )
            }
        } else {
            path.move(to: CGPoint(x: 0, y: 0))
        }

        if ir > 0, curveMode != .hardCorner {
            path.addLine(to: CGPoint(x: wing - ir, y: 0))
            let control: CGPoint = {
                switch curveMode {
                case .canonicalDownward:
                    return CGPoint(x: wing, y: 0)
                case .mirroredUpward:
                    return CGPoint(x: wing - ir, y: ir)
                case .hardCorner:
                    return CGPoint(x: wing, y: 0)
                }
            }()
            path.addQuadCurve(to: CGPoint(x: wing, y: ir), control: control)
        } else {
            path.addLine(to: CGPoint(x: wing, y: 0))
        }

        // Inner bottom-right stays square; outer bottom-left rounds.
        path.addLine(to: CGPoint(x: wing, y: height))
        path.addLine(to: CGPoint(x: br, y: height))
        path.addQuadCurve(to: CGPoint(x: 0, y: height - br), control: CGPoint(x: 0, y: height))
        path.closeSubpath()
    }

    private func addRightWing(
        path: inout Path,
        wing: CGFloat,
        gap: CGFloat,
        height: CGFloat,
        tor: CGFloat,
        br: CGFloat,
        ir: CGFloat
    ) {
        let x0 = wing + gap
        let x1 = x0 + wing

        if ir > 0, curveMode != .hardCorner {
            path.move(to: CGPoint(x: x0, y: ir))
            let control: CGPoint = {
                switch curveMode {
                case .canonicalDownward:
                    return CGPoint(x: x0, y: 0)
                case .mirroredUpward:
                    return CGPoint(x: x0 + ir, y: ir)
                case .hardCorner:
                    return CGPoint(x: x0, y: 0)
                }
            }()
            path.addQuadCurve(to: CGPoint(x: x0 + ir, y: 0), control: control)
        } else {
            path.move(to: CGPoint(x: x0, y: 0))
        }

        let cornerDrop = abs(tor)
        if cornerDrop > 0 {
            let shoulderX = x1 + tor
            path.addLine(to: CGPoint(x: shoulderX, y: 0))
            let center = CGPoint(x: shoulderX, y: cornerDrop)
            if tor >= 0 {
                path.addArc(
                    center: center,
                    radius: cornerDrop,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-180),
                    clockwise: true
                )
            } else {
                path.addArc(
                    center: center,
                    radius: cornerDrop,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(0),
                    clockwise: false
                )
            }
        } else {
            path.addLine(to: CGPoint(x: x1, y: 0))
        }
        // Outer bottom-right rounds; inner bottom-left stays square.
        path.addLine(to: CGPoint(x: x1, y: height - br))
        path.addQuadCurve(to: CGPoint(x: x1 - br, y: height), control: CGPoint(x: x1, y: height))
        path.addLine(to: CGPoint(x: x0, y: height))
        path.closeSubpath()
    }
}

struct PhysicalNotchShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let br = min(bottomRadius, min(w, h) / 2)

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - br))
        p.addQuadCurve(to: CGPoint(x: w - br, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: br, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - br), control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}
