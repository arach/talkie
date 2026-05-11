import CoreGraphics

enum NotchCornerKind: Equatable {
    case external
    case inward
}

struct NotchCornerGeometry {
    static func rightCornerKind(anchorX: CGFloat) -> NotchCornerKind {
        anchorX >= 0 ? .external : .inward
    }

    static func leftCornerKind(anchorX: CGFloat) -> NotchCornerKind {
        anchorX >= 0 ? .external : .inward
    }

    // Right notch edge: top anchor y is fixed at topY; edge anchor y is fixed at topY + drop.
    static func rightAnchors(edgeX: CGFloat, topY: CGFloat, drop: CGFloat, anchorX: CGFloat) -> (shoulder: CGPoint, edge: CGPoint) {
        (
            shoulder: CGPoint(x: edgeX + anchorX, y: topY),
            edge: CGPoint(x: edgeX, y: topY + drop)
        )
    }
}
