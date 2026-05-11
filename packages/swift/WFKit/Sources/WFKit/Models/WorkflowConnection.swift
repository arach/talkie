import Foundation
import SwiftUI

// MARK: - Routing Preference

/// Controls how a connection routes around obstacles
public enum WFRoutingPreference: String, Codable, Hashable, Sendable {
    /// Automatically determine the best route
    case auto
    /// Route to the left (vertical mode) or above (freeform mode)
    case primary
    /// Route to the right (vertical mode) or below (freeform mode)
    case secondary

    /// Cycle to the next preference
    public mutating func cycle() {
        switch self {
        case .auto: self = .primary
        case .primary: self = .secondary
        case .secondary: self = .auto
        }
    }

    /// Get the next preference without mutating
    public var next: WFRoutingPreference {
        switch self {
        case .auto: return .primary
        case .primary: return .secondary
        case .secondary: return .auto
        }
    }
}

// MARK: - Connection Waypoint

/// A waypoint that the connection path should pass through
public struct ConnectionWaypoint: Codable, Hashable, Sendable {
    /// Position of the waypoint in canvas coordinates
    public var position: CGPoint

    /// How strongly this waypoint influences the curve (0.0 to 1.0)
    /// Higher values make the curve pass closer to the waypoint
    public var influence: CGFloat

    public init(position: CGPoint, influence: CGFloat = 1.0) {
        self.position = position
        self.influence = min(max(influence, 0.0), 1.0)
    }
}

// MARK: - Connection (Edge between nodes)

public struct WorkflowConnection: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var sourceNodeId: UUID
    public var sourcePortId: UUID
    public var targetNodeId: UUID
    public var targetPortId: UUID
    public var routingPreference: WFRoutingPreference

    /// Custom waypoints that the connection should pass through.
    /// These are used for Google Maps-style path dragging.
    /// When empty, the connection uses automatic routing.
    public var waypoints: [ConnectionWaypoint]

    public init(
        id: UUID = UUID(),
        sourceNodeId: UUID,
        sourcePortId: UUID,
        targetNodeId: UUID,
        targetPortId: UUID,
        routingPreference: WFRoutingPreference = .auto,
        waypoints: [ConnectionWaypoint] = []
    ) {
        self.id = id
        self.sourceNodeId = sourceNodeId
        self.sourcePortId = sourcePortId
        self.targetNodeId = targetNodeId
        self.targetPortId = targetPortId
        self.routingPreference = routingPreference
        self.waypoints = waypoints
    }

    /// Check if connection has custom waypoints
    public var hasCustomWaypoints: Bool {
        !waypoints.isEmpty
    }

    /// Add a waypoint at the given position
    public mutating func addWaypoint(at position: CGPoint, influence: CGFloat = 1.0) {
        waypoints.append(ConnectionWaypoint(position: position, influence: influence))
    }

    /// Remove all custom waypoints (revert to automatic routing)
    public mutating func clearWaypoints() {
        waypoints.removeAll()
    }

    /// Update a waypoint's position
    public mutating func updateWaypoint(at index: Int, position: CGPoint) {
        guard index >= 0 && index < waypoints.count else { return }
        waypoints[index].position = position
    }
}

// MARK: - Connection Anchor Point

public struct ConnectionAnchor: Sendable {
    public let nodeId: UUID
    public let portId: UUID
    public let position: CGPoint
    public let isInput: Bool

    public init(nodeId: UUID, portId: UUID, position: CGPoint, isInput: Bool) {
        self.nodeId = nodeId
        self.portId = portId
        self.position = position
        self.isInput = isInput
    }
}

// MARK: - Pending Connection (while dragging)

public struct PendingConnection: Sendable {
    public var sourceAnchor: ConnectionAnchor
    public var currentPoint: CGPoint

    public init(from anchor: ConnectionAnchor) {
        self.sourceAnchor = anchor
        self.currentPoint = anchor.position
    }
}
