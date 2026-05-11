//
//  NormalizedPlacement.swift
//  TalkieKit
//
//  Shared normalized placement model for draggable HUD and pill positioning.
//

import CoreGraphics

public struct NormalizedPlacement: Codable, Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
    }

    public func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (rect.width * x),
            y: rect.minY + (rect.height * y)
        )
    }

    public func screenAnchorPoint(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (rect.width * x),
            y: rect.maxY - (rect.height * y)
        )
    }

    public func origin(in rect: CGRect, itemSize: CGSize) -> CGPoint {
        let minX = rect.minX
        let maxX = max(minX, rect.maxX - itemSize.width)
        let minY = rect.minY
        let maxY = max(minY, rect.maxY - itemSize.height)
        let originX = minX + ((maxX - minX) * x)
        let originY = maxY - ((maxY - minY) * y)

        return CGPoint(
            x: min(max(originX, minX), maxX),
            y: min(max(originY, minY), maxY)
        )
    }

    public static func normalized(for point: CGPoint, in rect: CGRect) -> Self {
        guard rect.width > 0, rect.height > 0 else {
            return .init(x: 0.5, y: 0.5)
        }

        let normalizedX = (point.x - rect.minX) / rect.width
        let normalizedY = (point.y - rect.minY) / rect.height
        return .init(x: normalizedX, y: normalizedY)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

public extension NormalizedPlacement {
    private static let edgeTopY: CGFloat = 0
    private static let edgeBottomY: CGFloat = 1
    private static let previousEdgeTopY: CGFloat = 0.025
    private static let previousEdgeBottomY: CGFloat = 0.975
    private static let legacyIndicatorTopY: CGFloat = 0.12
    private static let legacyPillBottomY: CGFloat = 0.88
    private static let legacyPillTopY: CGFloat = 0.18

    static let hudDefault = NormalizedPlacement(x: 0.5, y: edgeTopY)
    static let pillDefault = NormalizedPlacement(x: 0.5, y: edgeBottomY)

    init(indicatorPosition: IndicatorPosition) {
        switch indicatorPosition {
        case .topLeft:
            self = .init(x: 0.16, y: Self.edgeTopY)
        case .topCenter:
            self = .init(x: 0.5, y: Self.edgeTopY)
        case .topRight:
            self = .init(x: 0.84, y: Self.edgeTopY)
        }
    }

    init(pillPosition: PillPosition) {
        switch pillPosition {
        case .bottomLeft:
            self = .init(x: 0.18, y: Self.edgeBottomY)
        case .bottomCenter:
            self = .init(x: 0.5, y: Self.edgeBottomY)
        case .bottomRight:
            self = .init(x: 0.82, y: Self.edgeBottomY)
        case .topCenter:
            self = .init(x: 0.5, y: Self.edgeTopY)
        }
    }

    func migratingLegacyIndicatorAnchor(
        for position: IndicatorPosition,
        tolerance: CGFloat = 0.03
    ) -> Self {
        let legacyAnchors = [
            Self.legacyIndicatorPlacement(for: position),
            Self.previousEdgeIndicatorPlacement(for: position)
        ]
        guard legacyAnchors.contains(where: { isNear($0, tolerance: tolerance) }) else { return self }
        return Self(indicatorPosition: position)
    }

    func migratingLegacyPillAnchor(
        for position: PillPosition,
        tolerance: CGFloat = 0.03
    ) -> Self {
        let legacyAnchors = [
            Self.legacyPillPlacement(for: position),
            Self.previousEdgePillPlacement(for: position)
        ]
        guard legacyAnchors.contains(where: { isNear($0, tolerance: tolerance) }) else { return self }
        return Self(pillPosition: position)
    }

    var nearestIndicatorPosition: IndicatorPosition {
        [
            IndicatorPosition.topLeft,
            .topCenter,
            .topRight,
        ]
        .min { distance(to: Self(indicatorPosition: $0)) < distance(to: Self(indicatorPosition: $1)) }
        ?? .topCenter
    }

    var nearestPillPosition: PillPosition {
        [
            PillPosition.bottomLeft,
            .bottomCenter,
            .bottomRight,
            .topCenter,
        ]
        .min { distance(to: Self(pillPosition: $0)) < distance(to: Self(pillPosition: $1)) }
        ?? .bottomCenter
    }

    func nearestAnchor(in anchors: [Self], tolerance: CGFloat = 0.04) -> Self? {
        guard let anchor = anchors.min(by: { distance(to: $0) < distance(to: $1) }) else {
            return nil
        }
        return distance(to: anchor) <= tolerance ? anchor : nil
    }

    func isNear(_ other: Self, tolerance: CGFloat = 0.04) -> Bool {
        distance(to: other) <= tolerance
    }

    func snappedToNearestIndicatorAnchor() -> Self {
        Self(indicatorPosition: nearestIndicatorPosition)
    }

    func snappedToNearestPillAnchor() -> Self {
        Self(pillPosition: nearestPillPosition)
    }

    private func distance(to other: Self) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt((dx * dx) + (dy * dy))
    }

    private static func legacyIndicatorPlacement(for position: IndicatorPosition) -> Self {
        switch position {
        case .topLeft:
            return .init(x: 0.16, y: legacyIndicatorTopY)
        case .topCenter:
            return .init(x: 0.5, y: legacyIndicatorTopY)
        case .topRight:
            return .init(x: 0.84, y: legacyIndicatorTopY)
        }
    }

    private static func previousEdgeIndicatorPlacement(for position: IndicatorPosition) -> Self {
        switch position {
        case .topLeft:
            return .init(x: 0.16, y: previousEdgeTopY)
        case .topCenter:
            return .init(x: 0.5, y: previousEdgeTopY)
        case .topRight:
            return .init(x: 0.84, y: previousEdgeTopY)
        }
    }

    private static func legacyPillPlacement(for position: PillPosition) -> Self {
        switch position {
        case .bottomLeft:
            return .init(x: 0.18, y: legacyPillBottomY)
        case .bottomCenter:
            return .init(x: 0.5, y: legacyPillBottomY)
        case .bottomRight:
            return .init(x: 0.82, y: legacyPillBottomY)
        case .topCenter:
            return .init(x: 0.5, y: legacyPillTopY)
        }
    }

    private static func previousEdgePillPlacement(for position: PillPosition) -> Self {
        switch position {
        case .bottomLeft:
            return .init(x: 0.18, y: previousEdgeBottomY)
        case .bottomCenter:
            return .init(x: 0.5, y: previousEdgeBottomY)
        case .bottomRight:
            return .init(x: 0.82, y: previousEdgeBottomY)
        case .topCenter:
            return .init(x: 0.5, y: previousEdgeTopY)
        }
    }
}
