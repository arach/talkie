//
//  NotchWingShape.swift
//  Talkie
//
//  Wing shape that extends from the notch with rounded corners.
//  Ported from TalkieAgent's NotchOverlay.swift.
//

import SwiftUI

// MARK: - Wing Side

enum NotchSide {
    case left   // Wing extends from left of notch
    case right  // Wing extends from right of notch
}

enum NotchInnerCurveMode: String, CaseIterable {
    case canonicalDownward
    case hardCorner
    case mirroredUpward
}

// MARK: - Wing Shape

struct NotchWingShape: Shape {
    let side: NotchSide
    let cornerRadius: CGFloat
    let topOuterRadius: CGFloat
    let topInnerRadius: CGFloat
    let innerCurveMode: NotchInnerCurveMode

    init(
        side: NotchSide,
        cornerRadius: CGFloat,
        topOuterRadius: CGFloat = 8,
        topInnerRadius: CGFloat = 0,
        innerCurveMode: NotchInnerCurveMode = .canonicalDownward
    ) {
        self.side = side
        self.cornerRadius = cornerRadius
        self.topOuterRadius = topOuterRadius
        self.topInnerRadius = topInnerRadius
        self.innerCurveMode = innerCurveMode
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cr = min(cornerRadius, min(w, h) / 2)
        let maxTr = min(w, h) / 2
        let tr = max(-maxTr, min(topOuterRadius, maxTr))
        let cornerDrop = abs(tr)
        let tir = max(0, min(topInnerRadius, max(0, w - cornerDrop), h / 2))

        switch side {
        case .right:
            // Top-left: rounded inner corner (next to notch)
            // Top-right: rounded outer corner
            // Bottom corners: rounded
            if tir > 0, innerCurveMode != .hardCorner {
                path.move(to: CGPoint(x: 0, y: tir))
                let control: CGPoint = {
                    switch innerCurveMode {
                    case .canonicalDownward:
                        return CGPoint(x: 0, y: 0)
                    case .mirroredUpward:
                        return CGPoint(x: tir, y: tir)
                    case .hardCorner:
                        return CGPoint(x: 0, y: 0)
                    }
                }()
                path.addQuadCurve(to: CGPoint(x: tir, y: 0), control: control)
            } else {
                path.move(to: CGPoint(x: 0, y: 0))
            }
            if cornerDrop > 0 {
                let shoulderX = w + tr
                path.addLine(to: CGPoint(x: shoulderX, y: 0))
                let center = CGPoint(x: shoulderX, y: cornerDrop)
                if tr >= 0 {
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
                path.addLine(to: CGPoint(x: w, y: 0))
            }
            // Outer bottom-right rounds; inner bottom-left stays square.
            path.addLine(to: CGPoint(x: w, y: h - cr))
            path.addQuadCurve(to: CGPoint(x: w - cr, y: h), control: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()

        case .left:
            // Top-left: rounded outer corner
            // Top-right: rounded inner corner (next to notch)
            // Bottom corners: rounded
            if cornerDrop > 0 {
                let shoulderX = -tr
                path.move(to: CGPoint(x: 0, y: cornerDrop))
                let center = CGPoint(x: shoulderX, y: cornerDrop)
                if tr >= 0 {
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
            if tir > 0, innerCurveMode != .hardCorner {
                path.addLine(to: CGPoint(x: w - tir, y: 0))
                let control: CGPoint = {
                    switch innerCurveMode {
                    case .canonicalDownward:
                        return CGPoint(x: w, y: 0)
                    case .mirroredUpward:
                        return CGPoint(x: w - tir, y: tir)
                    case .hardCorner:
                        return CGPoint(x: w, y: 0)
                    }
                }()
                path.addQuadCurve(to: CGPoint(x: w, y: tir), control: control)
            } else {
                path.addLine(to: CGPoint(x: w, y: 0))
            }
            // Inner bottom-right stays square; outer bottom-left rounds.
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: cr, y: h))
            path.addQuadCurve(to: CGPoint(x: 0, y: h - cr), control: CGPoint(x: 0, y: h))
            path.closeSubpath()
        }

        return path
    }
}
