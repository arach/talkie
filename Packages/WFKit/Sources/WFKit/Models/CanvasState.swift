import Foundation
import SwiftUI
import AppKit

// MARK: - Layout Mode

/// Controls how nodes are positioned and connected on the canvas
public enum WFLayoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Freeform: nodes can be placed anywhere, left-to-right flow
    case freeform
    /// Vertical: auto-arranged top-to-bottom flow, compact nodes
    case vertical

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .freeform: return "Freeform"
        case .vertical: return "Vertical"
        }
    }

    public var icon: String {
        switch self {
        case .freeform: return "rectangle.3.group"
        case .vertical: return "arrow.down.to.line"
        }
    }
}

// MARK: - Layout Mode Environment Key

private struct WFLayoutModeKey: EnvironmentKey {
    static let defaultValue: WFLayoutMode = .freeform
}

extension EnvironmentValues {
    public var wfLayoutMode: WFLayoutMode {
        get { self[WFLayoutModeKey.self] }
        set { self[WFLayoutModeKey.self] = newValue }
    }
}

// MARK: - Canvas Snapshot (for Undo/Redo)

public struct CanvasSnapshot: Equatable, Sendable {
    public let nodes: [WorkflowNode]
    public let connections: [WorkflowConnection]
    public let selectedNodeIds: Set<UUID>

    public static func == (lhs: CanvasSnapshot, rhs: CanvasSnapshot) -> Bool {
        lhs.nodes == rhs.nodes &&
        lhs.connections == rhs.connections &&
        lhs.selectedNodeIds == rhs.selectedNodeIds
    }
}

// MARK: - Workflow Capture (Full Debug Snapshot)

/// A complete capture of the workflow editor state including raw client input,
/// current representation, and schema metadata. Used for debugging and snapshots.
public struct WFWorkflowCapture: Codable, Sendable {
    /// Timestamp when the capture was created
    public let timestamp: Date

    /// The raw input data as received from the client (before any transformation)
    public let rawInput: Data?

    /// The raw input as a string (for JSON/text inputs)
    public var rawInputString: String? {
        guard let data = rawInput else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The current workflow representation (nodes + connections)
    public let currentState: WorkflowData

    /// Schema metadata (node type names and field counts, not full schema)
    public let schemaInfo: SchemaInfo?

    /// Optional metadata from the client
    public let clientMetadata: [String: String]?

    public init(
        rawInput: Data?,
        currentState: WorkflowData,
        schemaInfo: SchemaInfo?,
        clientMetadata: [String: String]? = nil
    ) {
        self.timestamp = Date()
        self.rawInput = rawInput
        self.currentState = currentState
        self.schemaInfo = schemaInfo
        self.clientMetadata = clientMetadata
    }

    /// Lightweight schema info for capture (avoids serializing full schema)
    public struct SchemaInfo: Codable, Sendable {
        public let nodeTypeCount: Int
        public let nodeTypeIds: [String]
        public let totalFieldCount: Int

        public init(nodeTypeCount: Int, nodeTypeIds: [String], totalFieldCount: Int) {
            self.nodeTypeCount = nodeTypeCount
            self.nodeTypeIds = nodeTypeIds
            self.totalFieldCount = totalFieldCount
        }
    }

    /// Export capture to JSON
    public func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Serializable Data

public struct WorkflowData: Codable, Sendable {
    public var nodes: [WorkflowNode]
    public var connections: [WorkflowConnection]

    public init(nodes: [WorkflowNode], connections: [WorkflowConnection]) {
        self.nodes = nodes
        self.connections = connections
    }
}

// MARK: - Canvas State (Observable)

@Observable
public final class CanvasState {
    // MARK: - Workflow Data
    public var nodes: [WorkflowNode] = []
    public var connections: [WorkflowConnection] = []

    // MARK: - Raw Input Capture

    /// The raw input data as received from the client (before transformation).
    /// Set this when loading data from your client to enable full capture/snapshots.
    public var rawInput: Data?

    /// Optional metadata from the client (e.g., source file path, workflow ID, version)
    public var clientMetadata: [String: String]?

    // MARK: - Canvas Transform
    public var offset: CGSize = .zero
    public var scale: CGFloat = 1.0
    public var minScale: CGFloat = 0.25
    public var maxScale: CGFloat = 3.0
    public var targetScale: CGFloat = 1.0 // For smooth zoom animations

    // MARK: - Selection State
    public var selectedNodeIds: Set<UUID> = []
    public var hoveredNodeId: UUID? = nil
    public var selectedConnectionId: UUID? = nil
    public var hoveredConnectionId: UUID? = nil

    // MARK: - Inspector Navigation History (for back button)

    /// Represents an item that can be navigated to in the inspector
    public enum InspectorItem: Equatable {
        case node(UUID)
        case connection(UUID)
    }

    /// The previous item before the current selection (for "back" navigation)
    public var previousInspectorItem: InspectorItem? = nil


    // MARK: - Connection State
    public var pendingConnection: PendingConnection? = nil
    public var hoveredPortId: UUID? = nil
    public var validDropPortIds: Set<UUID> = []

    // MARK: - Interaction State
    public var isDragging: Bool = false
    public var isPanning: Bool = false

    // MARK: - Layout Mode
    public var layoutMode: WFLayoutMode = .freeform

    // MARK: - Drag Snapshot (for smooth dragging from initial position)
    private var dragSnapshot: [UUID: CGPoint] = [:]

    // MARK: - Undo/Redo State
    private var undoStack: [CanvasSnapshot] = []
    private var redoStack: [CanvasSnapshot] = []
    private let maxUndoStackSize = 50
    private var isPerformingUndoRedo = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Computed Properties

    public var selectedNodes: [WorkflowNode] {
        nodes.filter { selectedNodeIds.contains($0.id) }
    }

    public var hasSelection: Bool {
        !selectedNodeIds.isEmpty
    }

    public var singleSelectedNode: WorkflowNode? {
        guard selectedNodeIds.count == 1,
              let id = selectedNodeIds.first else { return nil }
        return nodes.first { $0.id == id }
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    // MARK: - Undo/Redo Operations

    private func createSnapshot() -> CanvasSnapshot {
        CanvasSnapshot(
            nodes: nodes,
            connections: connections,
            selectedNodeIds: selectedNodeIds
        )
    }

    private func restoreSnapshot(_ snapshot: CanvasSnapshot) {
        isPerformingUndoRedo = true
        nodes = snapshot.nodes
        connections = snapshot.connections
        selectedNodeIds = snapshot.selectedNodeIds
        isPerformingUndoRedo = false
    }

    private func saveSnapshot() {
        guard !isPerformingUndoRedo else { return }

        let snapshot = createSnapshot()

        // Don't save if nothing changed
        if let lastSnapshot = undoStack.last, lastSnapshot == snapshot {
            return
        }

        undoStack.append(snapshot)

        // Limit stack size
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }

        // Clear redo stack on new action
        redoStack.removeAll()
    }

    public func undo() {
        guard !undoStack.isEmpty else { return }

        // Save current state to redo stack
        redoStack.append(createSnapshot())

        // Restore previous state
        let snapshot = undoStack.removeLast()
        restoreSnapshot(snapshot)
    }

    public func redo() {
        guard !redoStack.isEmpty else { return }

        // Save current state to undo stack
        undoStack.append(createSnapshot())

        // Restore next state
        let snapshot = redoStack.removeLast()
        restoreSnapshot(snapshot)
    }

    // MARK: - Node Operations

    public func addNode(_ node: WorkflowNode) {
        saveSnapshot()
        nodes.append(node)
    }

    public func addNode(type: NodeType, at position: CGPoint) {
        saveSnapshot()
        let node = WorkflowNode(type: type, position: position)
        nodes.append(node)
        selectNode(node.id, exclusive: true)
    }

    // MARK: - Convenience API (Auto-positioned)

    /// Add a node without specifying position - use autoLayout() after adding all nodes
    @discardableResult
    public func addNode(
        type: NodeType,
        title: String? = nil,
        configuration: NodeConfiguration = NodeConfiguration(),
        position: CGPoint? = nil
    ) -> WorkflowNode {
        saveSnapshot()
        let node = WorkflowNode(
            type: type,
            title: title,
            position: position ?? nextAutoPosition(),
            configuration: configuration
        )
        nodes.append(node)
        return node
    }

    /// Connect two nodes using first available output → first available input
    public func connect(_ source: WorkflowNode, to target: WorkflowNode) {
        guard let sourcePort = source.outputs.first,
              let targetPort = target.inputs.first else { return }

        let connection = WorkflowConnection(
            sourceNodeId: source.id,
            sourcePortId: sourcePort.id,
            targetNodeId: target.id,
            targetPortId: targetPort.id
        )
        addConnection(connection)
    }

    /// Connect from a specific named output port to target's input
    public func connect(_ source: WorkflowNode, port portLabel: String, to target: WorkflowNode) {
        guard let sourcePort = source.outputs.first(where: { $0.label == portLabel }),
              let targetPort = target.inputs.first else { return }

        let connection = WorkflowConnection(
            sourceNodeId: source.id,
            sourcePortId: sourcePort.id,
            targetNodeId: target.id,
            targetPortId: targetPort.id
        )
        addConnection(connection)
    }

    /// Auto-layout all nodes based on graph structure (left-to-right flow)
    public func autoLayout(spacing: CGSize = CGSize(width: 280, height: 160), origin: CGPoint = CGPoint(x: 100, y: 100)) {
        guard !nodes.isEmpty else { return }

        // Build adjacency for topological sort
        var inDegree: [UUID: Int] = [:]
        var outEdges: [UUID: [UUID]] = [:]

        for node in nodes {
            inDegree[node.id] = 0
            outEdges[node.id] = []
        }

        for conn in connections {
            inDegree[conn.targetNodeId, default: 0] += 1
            outEdges[conn.sourceNodeId, default: []].append(conn.targetNodeId)
        }

        // Kahn's algorithm for topological levels
        var levels: [[UUID]] = []
        var queue = nodes.filter { inDegree[$0.id] == 0 }.map { $0.id }
        var remaining = inDegree

        while !queue.isEmpty {
            levels.append(queue)
            var nextQueue: [UUID] = []

            for nodeId in queue {
                for targetId in outEdges[nodeId] ?? [] {
                    remaining[targetId, default: 0] -= 1
                    if remaining[targetId] == 0 {
                        nextQueue.append(targetId)
                    }
                }
            }
            queue = nextQueue
        }

        // Handle any remaining nodes (cycles or disconnected)
        let positioned = Set(levels.flatMap { $0 })
        let unpositioned = nodes.filter { !positioned.contains($0.id) }.map { $0.id }
        if !unpositioned.isEmpty {
            levels.append(unpositioned)
        }

        // Position nodes by level
        for (col, level) in levels.enumerated() {
            for (row, nodeId) in level.enumerated() {
                if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                    nodes[index].position = CGPoint(
                        x: origin.x + CGFloat(col) * spacing.width,
                        y: origin.y + CGFloat(row) * spacing.height
                    )
                }
            }
        }
    }

    /// Get next auto-position for incrementally added nodes
    private func nextAutoPosition() -> CGPoint {
        guard let lastNode = nodes.last else {
            return CGPoint(x: 100, y: 100)
        }
        // Stack vertically with some offset
        return CGPoint(
            x: lastNode.position.x,
            y: lastNode.position.y + lastNode.size.height + 40
        )
    }

    // MARK: - Layout Mode Operations

    /// Switch layout mode and optionally trigger auto-layout
    public func setLayoutMode(_ mode: WFLayoutMode, autoLayout: Bool = true) {
        guard mode != layoutMode else { return }
        layoutMode = mode
        if autoLayout {
            switch mode {
            case .freeform:
                self.autoLayout()
            case .vertical:
                autoLayoutVertical()
            }
        }
    }

    /// Auto-layout for vertical mode (top-to-bottom flow)
    /// Nodes are arranged in rows by topological level, flowing downward
    public func autoLayoutVertical(spacing: CGSize = CGSize(width: 220, height: 100), origin: CGPoint = CGPoint(x: 200, y: 80)) {
        guard !nodes.isEmpty else { return }

        // Build adjacency for topological sort
        var inDegree: [UUID: Int] = [:]
        var outEdges: [UUID: [UUID]] = [:]

        for node in nodes {
            inDegree[node.id] = 0
            outEdges[node.id] = []
        }

        for conn in connections {
            inDegree[conn.targetNodeId, default: 0] += 1
            outEdges[conn.sourceNodeId, default: []].append(conn.targetNodeId)
        }

        // Kahn's algorithm for topological levels
        var levels: [[UUID]] = []
        var queue = nodes.filter { inDegree[$0.id] == 0 }.map { $0.id }
        var remaining = inDegree

        while !queue.isEmpty {
            levels.append(queue)
            var nextQueue: [UUID] = []

            for nodeId in queue {
                for targetId in outEdges[nodeId] ?? [] {
                    remaining[targetId, default: 0] -= 1
                    if remaining[targetId] == 0 {
                        nextQueue.append(targetId)
                    }
                }
            }
            queue = nextQueue
        }

        // Handle any remaining nodes (cycles or disconnected)
        let positioned = Set(levels.flatMap { $0 })
        let unpositioned = nodes.filter { !positioned.contains($0.id) }.map { $0.id }
        if !unpositioned.isEmpty {
            levels.append(unpositioned)
        }

        // Position nodes by level - VERTICAL: rows go down, columns go right
        // Track cumulative Y to account for actual node heights
        var currentY = origin.y
        let verticalGap: CGFloat = spacing.height  // Gap between rows (not total row height)

        for (_, level) in levels.enumerated() {
            // Find the tallest node in this row
            let rowNodeHeights = level.compactMap { nodeId in
                nodes.first(where: { $0.id == nodeId })?.size.height
            }
            let maxRowHeight = rowNodeHeights.max() ?? 120

            // Center nodes horizontally within this row
            let rowWidth = CGFloat(level.count) * spacing.width
            let startX = origin.x - rowWidth / 2 + spacing.width / 2

            for (col, nodeId) in level.enumerated() {
                if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                    nodes[index].position = CGPoint(
                        x: startX + CGFloat(col) * spacing.width,
                        y: currentY
                    )
                }
            }

            // Move to next row: current row height + gap
            currentY += maxRowHeight + verticalGap
        }
    }

    public func removeNode(_ id: UUID) {
        saveSnapshot()
        nodes.removeAll { $0.id == id }
        // Remove connections involving this node
        connections.removeAll { $0.sourceNodeId == id || $0.targetNodeId == id }
        selectedNodeIds.remove(id)
    }

    public func removeSelectedNodes() {
        guard !selectedNodeIds.isEmpty else { return }
        saveSnapshot()
        for id in selectedNodeIds {
            // Don't save snapshot for each individual removal
            let currentFlag = isPerformingUndoRedo
            isPerformingUndoRedo = true
            nodes.removeAll { $0.id == id }
            connections.removeAll { $0.sourceNodeId == id || $0.targetNodeId == id }
            isPerformingUndoRedo = currentFlag
        }
        selectedNodeIds.removeAll()
    }

    public func updateNode(_ node: WorkflowNode) {
        saveSnapshot()
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[index] = node
        }
    }

    public func moveNode(_ id: UUID, to position: CGPoint) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes[index].position = position
        }
    }

    public func moveSelectedNodes(by delta: CGSize) {
        for id in selectedNodeIds {
            if let index = nodes.firstIndex(where: { $0.id == id }) {
                nodes[index].position.x += delta.width
                nodes[index].position.y += delta.height
            }
        }
    }

    public func beginNodeMove() {
        saveSnapshot()
        // Capture initial positions of selected nodes
        dragSnapshot.removeAll()
        for id in selectedNodeIds {
            if let node = nodes.first(where: { $0.id == id }) {
                dragSnapshot[id] = node.position
            }
        }
    }

    public func moveSelectedNodesFromSnapshot(by delta: CGSize) {
        for id in selectedNodeIds {
            if let index = nodes.firstIndex(where: { $0.id == id }),
               let initialPosition = dragSnapshot[id] {
                nodes[index].position = CGPoint(
                    x: initialPosition.x + delta.width,
                    y: initialPosition.y + delta.height
                )
            }
        }
    }

    public func endNodeMove() {
        dragSnapshot.removeAll()
    }

    // MARK: - Selection Operations

    public func selectNode(_ id: UUID, exclusive: Bool = false) {
        if exclusive {
            selectedNodeIds = [id]
        } else {
            selectedNodeIds.insert(id)
        }
    }

    public func deselectNode(_ id: UUID) {
        selectedNodeIds.remove(id)
    }

    public func toggleNodeSelection(_ id: UUID) {
        if selectedNodeIds.contains(id) {
            selectedNodeIds.remove(id)
        } else {
            selectedNodeIds.insert(id)
        }
    }

    public func clearSelection() {
        selectedNodeIds.removeAll()
        selectedConnectionId = nil
    }

    public func selectAll() {
        selectedNodeIds = Set(nodes.map { $0.id })
    }

    public func selectConnection(_ id: UUID) {
        selectedConnectionId = id
        selectedNodeIds.removeAll() // Deselect nodes when selecting a connection
    }

    public func deselectConnection() {
        selectedConnectionId = nil
    }

    // MARK: - Inspector Navigation (with history)

    /// Get the current inspector item
    public var currentInspectorItem: InspectorItem? {
        if let connectionId = selectedConnectionId {
            return .connection(connectionId)
        } else if selectedNodeIds.count == 1, let nodeId = selectedNodeIds.first {
            return .node(nodeId)
        }
        return nil
    }

    /// Navigate to a node from inspector (tracks history)
    public func navigateToNode(_ id: UUID) {
        // Save current item as previous (for back navigation)
        previousInspectorItem = currentInspectorItem

        // Select the node
        selectedConnectionId = nil
        selectedNodeIds = [id]
    }

    /// Navigate to a connection from inspector (tracks history)
    public func navigateToConnection(_ id: UUID) {
        // Save current item as previous (for back navigation)
        previousInspectorItem = currentInspectorItem

        // Select the connection
        selectedNodeIds.removeAll()
        selectedConnectionId = id
    }

    /// Navigate back to previous inspector item
    public func navigateBack() {
        guard let previous = previousInspectorItem else { return }

        // Clear the previous (no more back after this)
        previousInspectorItem = nil

        // Navigate to the previous item (without tracking history)
        switch previous {
        case .node(let nodeId):
            selectedConnectionId = nil
            selectedNodeIds = [nodeId]
        case .connection(let connectionId):
            selectedNodeIds.removeAll()
            selectedConnectionId = connectionId
        }
    }

    /// Get display info for the previous item (for back button label)
    public func previousItemInfo() -> (icon: String, title: String, color: Color)? {
        guard let previous = previousInspectorItem else { return nil }

        switch previous {
        case .node(let nodeId):
            guard let node = nodes.first(where: { $0.id == nodeId }) else { return nil }
            return (node.type.icon, node.title, node.effectiveColor)
        case .connection:
            return ("arrow.right", "Connection", Color.blue)
        }
    }

    // MARK: - Related Nodes (for Inspector)

    /// Get nodes that connect TO this node (upstream/input nodes)
    public func upstreamNodes(for nodeId: UUID) -> [WorkflowNode] {
        let sourceNodeIds = connections
            .filter { $0.targetNodeId == nodeId }
            .map { $0.sourceNodeId }
        return nodes.filter { sourceNodeIds.contains($0.id) }
    }

    /// Get nodes that this node connects TO (downstream/output nodes)
    public func downstreamNodes(for nodeId: UUID) -> [WorkflowNode] {
        let targetNodeIds = connections
            .filter { $0.sourceNodeId == nodeId }
            .map { $0.targetNodeId }
        return nodes.filter { targetNodeIds.contains($0.id) }
    }

    /// Get all connected nodes (both upstream and downstream)
    public func connectedNodes(for nodeId: UUID) -> (upstream: [WorkflowNode], downstream: [WorkflowNode]) {
        return (upstreamNodes(for: nodeId), downstreamNodes(for: nodeId))
    }

    /// Live routing drag offset for real-time preview while dragging the middle handle
    /// This is applied to the obstacle avoidance path during drag
    public var routingDragOffset: CGSize = .zero

    /// Whether a routing drag is in progress
    public var isRoutingDrag: Bool = false

    /// Live waypoint position during drag preview (Google Maps-style path editing)
    public var liveWaypoint: CGPoint? = nil

    /// Whether a waypoint drag is in progress
    public var isWaypointDrag: Bool = false

    /// Cycle the routing preference of the selected connection
    public func cycleSelectedConnectionRouting() {
        guard let connectionId = selectedConnectionId,
              let index = connections.firstIndex(where: { $0.id == connectionId }) else {
            return
        }
        connections[index].routingPreference.cycle()
    }

    /// Set a specific routing preference for the selected connection
    public func setSelectedConnectionRouting(_ preference: WFRoutingPreference) {
        guard let connectionId = selectedConnectionId,
              let index = connections.firstIndex(where: { $0.id == connectionId }) else {
            WFLogger.warning("setSelectedConnectionRouting: No connection selected or not found", category: .connection)
            return
        }
        let oldPreference = connections[index].routingPreference
        guard oldPreference != preference else {
            WFLogger.debug("Routing preference unchanged: \(preference)", category: .connection)
            return
        }
        // Create a new connection with updated routing to ensure SwiftUI detects the change
        var updatedConnection = connections[index]
        updatedConnection.routingPreference = preference
        connections[index] = updatedConnection
        WFLogger.info("Connection routing changed: \(oldPreference) -> \(preference)", category: .connection)
    }

    // MARK: - Waypoint Management

    /// Add a waypoint to the selected connection
    public func addWaypointToSelectedConnection(at position: CGPoint) {
        guard let connectionId = selectedConnectionId,
              let index = connections.firstIndex(where: { $0.id == connectionId }) else {
            WFLogger.warning("addWaypointToSelectedConnection: No connection selected", category: .connection)
            return
        }
        saveSnapshot()
        var updatedConnection = connections[index]
        updatedConnection.addWaypoint(at: position)
        connections[index] = updatedConnection
        WFLogger.info("Added waypoint to connection at \(position)", category: .connection)
    }

    /// Clear all waypoints from the selected connection
    public func clearSelectedConnectionWaypoints() {
        guard let connectionId = selectedConnectionId,
              let index = connections.firstIndex(where: { $0.id == connectionId }) else {
            WFLogger.warning("clearSelectedConnectionWaypoints: No connection selected", category: .connection)
            return
        }
        guard !connections[index].waypoints.isEmpty else { return }
        saveSnapshot()
        var updatedConnection = connections[index]
        updatedConnection.clearWaypoints()
        connections[index] = updatedConnection
        WFLogger.info("Cleared waypoints from connection", category: .connection)
    }

    /// Update a waypoint's position on the selected connection
    public func updateSelectedConnectionWaypoint(at waypointIndex: Int, position: CGPoint) {
        guard let connectionId = selectedConnectionId,
              let index = connections.firstIndex(where: { $0.id == connectionId }) else {
            return
        }
        var updatedConnection = connections[index]
        updatedConnection.updateWaypoint(at: waypointIndex, position: position)
        connections[index] = updatedConnection
    }

    /// Start a waypoint drag - sets the live waypoint for preview
    public func startWaypointDrag(at position: CGPoint) {
        isWaypointDrag = true
        liveWaypoint = position
    }

    /// Update the live waypoint during drag
    public func updateLiveWaypoint(to position: CGPoint) {
        liveWaypoint = position
    }

    /// End a waypoint drag and optionally commit the waypoint
    public func endWaypointDrag(commit: Bool) {
        if commit, let position = liveWaypoint {
            addWaypointToSelectedConnection(at: position)
        }
        isWaypointDrag = false
        liveWaypoint = nil
    }

    // MARK: - Connection Operations

    /// The connection currently being reconnected (if any)
    public var reconnectingConnection: WorkflowConnection? = nil

    /// Start reconnecting an existing connection by dragging one of its endpoints
    /// - Parameters:
    ///   - connection: The connection to reconnect
    ///   - draggingSource: If true, dragging the source endpoint. If false, dragging the target endpoint.
    public func startReconnection(_ connection: WorkflowConnection, fromSource draggingSource: Bool) {
        WFLogger.connection("START reconnection", details: "draggingSource=\(draggingSource), id=\(connection.id.uuidString.prefix(8))")

        // Store the connection being reconnected (keep it in the array, just mark it)
        reconnectingConnection = connection

        // Get the anchor position for the fixed end (the end that's NOT being dragged)
        let anchorNodeId: UUID
        let anchorPortId: UUID
        let isInput: Bool

        if draggingSource {
            // Dragging the source endpoint → target stays fixed
            // The fixed anchor is the target (an input port)
            anchorNodeId = connection.targetNodeId
            anchorPortId = connection.targetPortId
            isInput = true // Target is an input port
            WFLogger.debug("Anchor: TARGET (input port)", category: .connection)
        } else {
            // Dragging the target endpoint → source stays fixed
            // The fixed anchor is the source (an output port)
            anchorNodeId = connection.sourceNodeId
            anchorPortId = connection.sourcePortId
            isInput = false // Source is an output port
            WFLogger.debug("Anchor: SOURCE (output port)", category: .connection)
        }

        guard let anchorPosition = portPosition(nodeId: anchorNodeId, portId: anchorPortId) else {
            WFLogger.error("Failed to get anchor position!", category: .connection)
            reconnectingConnection = nil
            return
        }

        WFLogger.debug("Anchor position: \(anchorPosition)", category: .connection)

        // Create the pending connection from the fixed anchor
        let anchor = ConnectionAnchor(
            nodeId: anchorNodeId,
            portId: anchorPortId,
            position: anchorPosition,
            isInput: isInput
        )

        pendingConnection = PendingConnection(from: anchor)
        updateValidDropPorts(for: anchor)

        WFLogger.info("Valid drop ports: \(validDropPortIds.count)", category: .connection)
    }

    /// Complete or cancel a reconnection
    public func completeReconnection(to targetAnchor: ConnectionAnchor?) {
        WFLogger.connection("END reconnection", details: "targetAnchor=\(targetAnchor != nil ? "provided" : "nil")")

        defer {
            WFLogger.debug("Cleanup: clearing state", category: .connection)
            pendingConnection = nil
            validDropPortIds.removeAll()
            reconnectingConnection = nil
            hoveredPortId = nil
        }

        guard let pending = pendingConnection,
              let originalConnection = reconnectingConnection else {
            WFLogger.error("No pending connection or original connection!", category: .connection)
            return
        }

        if let target = targetAnchor {
            WFLogger.debug("Target: nodeId=\(target.nodeId.uuidString.prefix(8)), isInput=\(target.isInput)", category: .connection)
            // Exclude the original connection from duplicate check (we're replacing it)
            let canConnectResult = canConnect(from: pending.sourceAnchor, to: target, excluding: originalConnection.id)
            WFLogger.debug("canConnect: \(canConnectResult)", category: .connection)

            if canConnectResult {
                saveSnapshot()

                // Remove the original connection
                connections.removeAll { $0.id == originalConnection.id }

                let source = pending.sourceAnchor
                let (outputAnchor, inputAnchor) = source.isInput ? (target, source) : (source, target)

                let newConnection = WorkflowConnection(
                    sourceNodeId: outputAnchor.nodeId,
                    sourcePortId: outputAnchor.portId,
                    targetNodeId: inputAnchor.nodeId,
                    targetPortId: inputAnchor.portId
                )
                // Use withAnimation to ensure the connection appears immediately
                withAnimation(.easeOut(duration: 0.2)) {
                    connections.append(newConnection)
                }
                WFLogger.info("Created new connection: \(newConnection.id.uuidString.prefix(8))", category: .connection)
            } else {
                WFLogger.warning("Cannot connect - keeping original", category: .connection)
            }
        } else {
            WFLogger.warning("No target - cancelled, keeping original", category: .connection)
        }
    }

    public func addConnection(_ connection: WorkflowConnection) {
        // Prevent duplicate connections
        guard !connections.contains(where: {
            $0.sourceNodeId == connection.sourceNodeId &&
            $0.sourcePortId == connection.sourcePortId &&
            $0.targetNodeId == connection.targetNodeId &&
            $0.targetPortId == connection.targetPortId
        }) else { return }

        // Prevent self-connections
        guard connection.sourceNodeId != connection.targetNodeId else { return }

        saveSnapshot()
        // Use withAnimation to ensure the connection appears immediately with a smooth entrance
        withAnimation(.easeOut(duration: 0.2)) {
            connections.append(connection)
        }
    }

    public func removeConnection(_ id: UUID) {
        saveSnapshot()
        connections.removeAll { $0.id == id }
    }

    public func removeConnectionsForPort(nodeId: UUID, portId: UUID) {
        saveSnapshot()
        connections.removeAll {
            ($0.sourceNodeId == nodeId && $0.sourcePortId == portId) ||
            ($0.targetNodeId == nodeId && $0.targetPortId == portId)
        }
    }

    /// Start a new connection from a port (initiated from inspector or programmatically)
    /// - Parameters:
    ///   - nodeId: The node containing the port
    ///   - portId: The port to start the connection from
    ///   - isInput: Whether the port is an input port
    public func startConnectionFromPort(nodeId: UUID, portId: UUID, isInput: Bool) {
        guard let position = portPosition(nodeId: nodeId, portId: portId) else { return }

        let anchor = ConnectionAnchor(
            nodeId: nodeId,
            portId: portId,
            position: position,
            isInput: isInput
        )

        pendingConnection = PendingConnection(from: anchor)
        updateValidDropPorts(for: anchor)
    }

    /// Complete a pending connection to a target port
    public func completeConnection(to targetNodeId: UUID, targetPortId: UUID, isInput: Bool) {
        defer {
            pendingConnection = nil
            validDropPortIds.removeAll()
            hoveredPortId = nil
        }

        guard let pending = pendingConnection,
              let targetPosition = portPosition(nodeId: targetNodeId, portId: targetPortId) else {
            return
        }

        let targetAnchor = ConnectionAnchor(
            nodeId: targetNodeId,
            portId: targetPortId,
            position: targetPosition,
            isInput: isInput
        )

        if canConnect(from: pending.sourceAnchor, to: targetAnchor) {
            saveSnapshot()

            let source = pending.sourceAnchor
            let (outputAnchor, inputAnchor) = source.isInput ? (targetAnchor, source) : (source, targetAnchor)

            let newConnection = WorkflowConnection(
                sourceNodeId: outputAnchor.nodeId,
                sourcePortId: outputAnchor.portId,
                targetNodeId: inputAnchor.nodeId,
                targetPortId: inputAnchor.portId
            )
            // Use withAnimation to ensure the connection appears immediately
            withAnimation(.easeOut(duration: 0.2)) {
                connections.append(newConnection)
            }
        }
    }

    /// Cancel the pending connection
    public func cancelPendingConnection() {
        pendingConnection = nil
        validDropPortIds.removeAll()
        hoveredPortId = nil
    }

    /// Check if we're in connection mode
    public var isConnecting: Bool {
        pendingConnection != nil
    }

    // MARK: - Canvas Operations

    public func resetView() {
        offset = .zero
        scale = 1.0
        targetScale = 1.0
    }

    public func zoomIn(animated: Bool = true) {
        let newScale = min(scale * 1.25, maxScale)
        if animated {
            targetScale = newScale
        } else {
            scale = newScale
            targetScale = newScale
        }
    }

    public func zoomOut(animated: Bool = true) {
        let newScale = max(scale / 1.25, minScale)
        if animated {
            targetScale = newScale
        } else {
            scale = newScale
            targetScale = newScale
        }
    }

    public func setZoom(to newScale: CGFloat, animated: Bool = true) {
        let clampedScale = max(minScale, min(newScale, maxScale))
        if animated {
            targetScale = clampedScale
        } else {
            scale = clampedScale
            targetScale = clampedScale
        }
    }

    public func zoomToFit(in size: CGSize, padding: CGFloat = 50) {
        guard !nodes.isEmpty else {
            resetView()
            return
        }

        // Calculate bounding box of all nodes
        let minX = nodes.map { $0.position.x }.min() ?? 0
        let maxX = nodes.map { $0.position.x + $0.size.width }.max() ?? 0
        let minY = nodes.map { $0.position.y }.min() ?? 0
        let maxY = nodes.map { $0.position.y + $0.size.height }.max() ?? 0

        let contentWidth = maxX - minX + padding * 2
        let contentHeight = maxY - minY + padding * 2

        let scaleX = size.width / contentWidth
        let scaleY = size.height / contentHeight
        scale = max(minScale, min(min(scaleX, scaleY), maxScale))
        targetScale = scale

        // Center the content
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        offset = CGSize(
            width: size.width / 2 - centerX * scale,
            height: size.height / 2 - centerY * scale
        )
    }

    public func zoomToward(point: CGPoint, scaleFactor: CGFloat, canvasSize: CGSize) {
        let newScale = max(minScale, min(scale * scaleFactor, maxScale))

        // Calculate the canvas point under the cursor
        let canvasPointValue = canvasPoint(from: point)

        // Apply the new scale
        scale = newScale

        // Adjust offset to keep the canvas point under the cursor
        let newScreenPoint = screenPoint(from: canvasPointValue)
        offset.width += point.x - newScreenPoint.x
        offset.height += point.y - newScreenPoint.y
    }

    // MARK: - Grid Snapping

    public var gridSize: CGFloat = 20

    public func snapToGrid(_ point: CGPoint, gridSize: CGFloat? = nil) -> CGPoint {
        let size = gridSize ?? self.gridSize
        return CGPoint(
            x: round(point.x / size) * size,
            y: round(point.y / size) * size
        )
    }

    public func snapSelectedNodesToGrid(gridSize: CGFloat? = nil) {
        let size = gridSize ?? self.gridSize
        for id in selectedNodeIds {
            if let index = nodes.firstIndex(where: { $0.id == id }) {
                nodes[index].position = snapToGrid(nodes[index].position, gridSize: size)
            }
        }
    }

    // MARK: - Keyboard Navigation

    public func nudgeSelectedNodes(by delta: CGSize) {
        guard !selectedNodeIds.isEmpty else { return }
        saveSnapshot()
        moveSelectedNodes(by: delta)
    }

    public func selectNextNode() {
        guard !nodes.isEmpty else { return }

        if let currentId = selectedNodeIds.first,
           let currentIndex = nodes.firstIndex(where: { $0.id == currentId }) {
            let nextIndex = (currentIndex + 1) % nodes.count
            selectNode(nodes[nextIndex].id, exclusive: true)
        } else {
            // No selection, select first node
            selectNode(nodes[0].id, exclusive: true)
        }
    }

    public func selectPreviousNode() {
        guard !nodes.isEmpty else { return }

        if let currentId = selectedNodeIds.first,
           let currentIndex = nodes.firstIndex(where: { $0.id == currentId }) {
            let previousIndex = currentIndex == 0 ? nodes.count - 1 : currentIndex - 1
            selectNode(nodes[previousIndex].id, exclusive: true)
        } else {
            // No selection, select last node
            selectNode(nodes[nodes.count - 1].id, exclusive: true)
        }
    }

    // MARK: - Coordinate Conversion

    public func canvasPoint(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - offset.width) / scale,
            y: (screenPoint.y - offset.height) / scale
        )
    }

    public func screenPoint(from canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * scale + offset.width,
            y: canvasPoint.y * scale + offset.height
        )
    }

    // MARK: - Hit Testing

    public func nodeAt(point: CGPoint) -> WorkflowNode? {
        // Return topmost node (last in array) at point
        nodes.last { node in
            let rect = CGRect(origin: node.position, size: node.size)
            return rect.contains(point)
        }
    }

    public func connectionAt(point: CGPoint, tolerance: CGFloat = 10) -> UUID? {
        // Iterate connections in reverse order (topmost first)
        for connection in connections.reversed() {
            guard let startPos = portPosition(nodeId: connection.sourceNodeId, portId: connection.sourcePortId),
                  let endPos = portPosition(nodeId: connection.targetNodeId, portId: connection.targetPortId) else {
                continue
            }

            if isPointNearBezierCurve(point: point, from: startPos, to: endPos, tolerance: tolerance) {
                return connection.id
            }
        }
        return nil
    }

    private func isPointNearBezierCurve(point: CGPoint, from start: CGPoint, to end: CGPoint, tolerance: CGFloat) -> Bool {
        // Calculate control points (same as ConnectionView bezierPath)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx * dx + dy * dy)

        var controlOffset: CGFloat
        if abs(dx) < 50 {
            controlOffset = max(abs(dy) * 0.3, 80)
        } else if abs(dy) < 50 {
            controlOffset = min(abs(dx) * 0.5, distance * 0.4)
        } else {
            controlOffset = min(max(abs(dx) * 0.4, 100), distance * 0.45)
        }

        let control1 = CGPoint(x: start.x + controlOffset, y: start.y)
        let control2 = CGPoint(x: end.x - controlOffset, y: end.y)

        // Sample the bezier curve and find minimum distance
        let samples = 50
        var minDistance: CGFloat = .infinity

        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let curvePoint = bezierPoint(t: t, p0: start, p1: control1, p2: control2, p3: end)
            let dist = hypot(point.x - curvePoint.x, point.y - curvePoint.y)
            minDistance = min(minDistance, dist)
        }

        return minDistance <= tolerance
    }

    private func bezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        let t2 = t * t
        let t3 = t2 * t

        return CGPoint(
            x: mt3 * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t3 * p3.x,
            y: mt3 * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t3 * p3.y
        )
    }

    // MARK: - Port Positions

    public func portPosition(nodeId: UUID, portId: UUID) -> CGPoint? {
        guard let node = nodes.first(where: { $0.id == nodeId }) else {
            WFLogger.warning("portPosition: Node not found - nodeId=\(nodeId.uuidString.prefix(8))", category: .connection)
            return nil
        }

        switch layoutMode {
        case .freeform:
            // Freeform mode: inputs on left, outputs on right (vertical distribution)
            // Check inputs
            if let inputIndex = node.inputs.firstIndex(where: { $0.id == portId }) {
                let portHeight = node.size.height / CGFloat(node.inputs.count)
                let portCenterY = portHeight * CGFloat(inputIndex) + portHeight / 2
                return CGPoint(
                    x: node.position.x,
                    y: node.position.y + portCenterY
                )
            }

            // Check outputs
            if let outputIndex = node.outputs.firstIndex(where: { $0.id == portId }) {
                let portHeight = node.size.height / CGFloat(node.outputs.count)
                let portCenterY = portHeight * CGFloat(outputIndex) + portHeight / 2
                return CGPoint(
                    x: node.position.x + node.size.width,
                    y: node.position.y + portCenterY
                )
            }

        case .vertical:
            // Vertical mode: inputs on top, outputs on bottom (horizontal distribution)
            // Check inputs
            if let inputIndex = node.inputs.firstIndex(where: { $0.id == portId }) {
                let portWidth = node.size.width / CGFloat(node.inputs.count)
                let portCenterX = portWidth * CGFloat(inputIndex) + portWidth / 2
                return CGPoint(
                    x: node.position.x + portCenterX,
                    y: node.position.y
                )
            }

            // Check outputs
            if let outputIndex = node.outputs.firstIndex(where: { $0.id == portId }) {
                let portWidth = node.size.width / CGFloat(node.outputs.count)
                let portCenterX = portWidth * CGFloat(outputIndex) + portWidth / 2
                return CGPoint(
                    x: node.position.x + portCenterX,
                    y: node.position.y + node.size.height
                )
            }
        }

        // Port not found - expected case when looking up connections, no need to log
        // (This happens frequently when searching for ports across all nodes)
        return nil
    }

    // MARK: - Port Hit Testing

    public func portAt(canvasPoint: CGPoint, tolerance: CGFloat = 15) -> (nodeId: UUID, portId: UUID, isInput: Bool)? {
        for node in nodes {
            switch layoutMode {
            case .freeform:
                // Freeform mode: inputs on left, outputs on right (vertical distribution)
                // Check input ports
                for (index, port) in node.inputs.enumerated() {
                    let portHeight = node.size.height / CGFloat(node.inputs.count)
                    let portCenterY = portHeight * CGFloat(index) + portHeight / 2
                    let portPos = CGPoint(
                        x: node.position.x,
                        y: node.position.y + portCenterY
                    )

                    let distance = sqrt(
                        pow(canvasPoint.x - portPos.x, 2) +
                        pow(canvasPoint.y - portPos.y, 2)
                    )

                    if distance <= tolerance {
                        return (nodeId: node.id, portId: port.id, isInput: true)
                    }
                }

                // Check output ports
                for (index, port) in node.outputs.enumerated() {
                    let portHeight = node.size.height / CGFloat(node.outputs.count)
                    let portCenterY = portHeight * CGFloat(index) + portHeight / 2
                    let portPos = CGPoint(
                        x: node.position.x + node.size.width,
                        y: node.position.y + portCenterY
                    )

                    let distance = sqrt(
                        pow(canvasPoint.x - portPos.x, 2) +
                        pow(canvasPoint.y - portPos.y, 2)
                    )

                    if distance <= tolerance {
                        return (nodeId: node.id, portId: port.id, isInput: false)
                    }
                }

            case .vertical:
                // Vertical mode: inputs on top, outputs on bottom (horizontal distribution)
                // Check input ports
                for (index, port) in node.inputs.enumerated() {
                    let portWidth = node.size.width / CGFloat(node.inputs.count)
                    let portCenterX = portWidth * CGFloat(index) + portWidth / 2
                    let portPos = CGPoint(
                        x: node.position.x + portCenterX,
                        y: node.position.y
                    )

                    let distance = sqrt(
                        pow(canvasPoint.x - portPos.x, 2) +
                        pow(canvasPoint.y - portPos.y, 2)
                    )

                    if distance <= tolerance {
                        return (nodeId: node.id, portId: port.id, isInput: true)
                    }
                }

                // Check output ports
                for (index, port) in node.outputs.enumerated() {
                    let portWidth = node.size.width / CGFloat(node.outputs.count)
                    let portCenterX = portWidth * CGFloat(index) + portWidth / 2
                    let portPos = CGPoint(
                        x: node.position.x + portCenterX,
                        y: node.position.y + node.size.height
                    )

                    let distance = sqrt(
                        pow(canvasPoint.x - portPos.x, 2) +
                        pow(canvasPoint.y - portPos.y, 2)
                    )

                    if distance <= tolerance {
                        return (nodeId: node.id, portId: port.id, isInput: false)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Connection Validation

    public func canConnect(from sourceAnchor: ConnectionAnchor, to targetAnchor: ConnectionAnchor, excluding excludedConnectionId: UUID? = nil) -> Bool {
        // Cannot connect a port to itself
        if sourceAnchor.nodeId == targetAnchor.nodeId && sourceAnchor.portId == targetAnchor.portId {
            return false
        }

        // Cannot connect two nodes to themselves (self-loop)
        if sourceAnchor.nodeId == targetAnchor.nodeId {
            return false
        }

        // Must connect input to output or output to input (not same type)
        if sourceAnchor.isInput == targetAnchor.isInput {
            return false
        }

        // Check if connection already exists (excluding the connection being reconnected)
        let (outputAnchor, inputAnchor) = sourceAnchor.isInput ? (targetAnchor, sourceAnchor) : (sourceAnchor, targetAnchor)

        let alreadyExists = connections.contains { connection in
            // Skip the connection being reconnected
            if let excludeId = excludedConnectionId, connection.id == excludeId {
                return false
            }
            return connection.sourceNodeId == outputAnchor.nodeId &&
                connection.sourcePortId == outputAnchor.portId &&
                connection.targetNodeId == inputAnchor.nodeId &&
                connection.targetPortId == inputAnchor.portId
        }

        return !alreadyExists
    }

    public func updateValidDropPorts(for sourceAnchor: ConnectionAnchor) {
        validDropPortIds.removeAll()

        // When reconnecting, exclude the original connection from validation
        let excludeId = reconnectingConnection?.id

        for node in nodes {
            // Skip the source node (no self-connections)
            if node.id == sourceAnchor.nodeId {
                continue
            }

            // Check input ports if dragging from output
            if !sourceAnchor.isInput {
                for port in node.inputs {
                    let targetAnchor = ConnectionAnchor(
                        nodeId: node.id,
                        portId: port.id,
                        position: .zero,
                        isInput: true
                    )
                    if canConnect(from: sourceAnchor, to: targetAnchor, excluding: excludeId) {
                        validDropPortIds.insert(port.id)
                    }
                }
            } else {
                // Check output ports if dragging from input
                for port in node.outputs {
                    let targetAnchor = ConnectionAnchor(
                        nodeId: node.id,
                        portId: port.id,
                        position: .zero,
                        isInput: false
                    )
                    if canConnect(from: sourceAnchor, to: targetAnchor, excluding: excludeId) {
                        validDropPortIds.insert(port.id)
                    }
                }
            }
        }
    }

    // MARK: - Clipboard Operations

    public func copySelectedNodes() {
        guard !selectedNodeIds.isEmpty else { return }

        let selectedNodesData = nodes.filter { selectedNodeIds.contains($0.id) }

        // Also copy connections between selected nodes
        let selectedConnections = connections.filter { connection in
            selectedNodeIds.contains(connection.sourceNodeId) &&
            selectedNodeIds.contains(connection.targetNodeId)
        }

        let clipboardData = WorkflowData(nodes: selectedNodesData, connections: selectedConnections)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(clipboardData),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonString, forType: .string)
    }

    public func pasteNodes() {
        let pasteboard = NSPasteboard.general
        guard let jsonString = pasteboard.string(forType: .string),
              let data = jsonString.data(using: .utf8),
              let clipboardData = try? JSONDecoder().decode(WorkflowData.self, from: data) else {
            return
        }

        saveSnapshot()

        // Create ID mapping for pasted nodes
        var idMapping: [UUID: UUID] = [:]

        // Calculate offset for pasted nodes (shift by 20,20 from original)
        let pasteOffset = CGPoint(x: 20, y: 20)

        // Add nodes with new IDs and offset positions
        var newNodeIds: Set<UUID> = []
        for oldNode in clipboardData.nodes {
            let newId = UUID()
            idMapping[oldNode.id] = newId
            newNodeIds.insert(newId)

            let newNode = WorkflowNode(
                id: newId,
                type: oldNode.type,
                title: oldNode.title,
                position: CGPoint(
                    x: oldNode.position.x + pasteOffset.x,
                    y: oldNode.position.y + pasteOffset.y
                ),
                size: oldNode.size,
                inputs: oldNode.inputs,
                outputs: oldNode.outputs,
                configuration: oldNode.configuration,
                isCollapsed: oldNode.isCollapsed
            )
            nodes.append(newNode)
        }

        // Add connections with remapped node IDs
        for oldConnection in clipboardData.connections {
            if let newSourceId = idMapping[oldConnection.sourceNodeId],
               let newTargetId = idMapping[oldConnection.targetNodeId] {
                let newConnection = WorkflowConnection(
                    sourceNodeId: newSourceId,
                    sourcePortId: oldConnection.sourcePortId,
                    targetNodeId: newTargetId,
                    targetPortId: oldConnection.targetPortId
                )
                connections.append(newConnection)
            }
        }

        // Select the newly pasted nodes
        selectedNodeIds = newNodeIds
    }

    public func duplicateSelectedNodes() {
        guard !selectedNodeIds.isEmpty else { return }

        // Copy to clipboard and paste (reuses the logic)
        copySelectedNodes()
        pasteNodes()
    }

    // MARK: - Node Ordering Operations

    public func bringSelectedToFront() {
        guard !selectedNodeIds.isEmpty else { return }
        saveSnapshot()

        // Separate selected and unselected nodes
        let selected = nodes.filter { selectedNodeIds.contains($0.id) }
        let unselected = nodes.filter { !selectedNodeIds.contains($0.id) }

        // Place selected nodes at the end (on top)
        nodes = unselected + selected
    }

    public func sendSelectedToBack() {
        guard !selectedNodeIds.isEmpty else { return }
        saveSnapshot()

        // Separate selected and unselected nodes
        let selected = nodes.filter { selectedNodeIds.contains($0.id) }
        let unselected = nodes.filter { !selectedNodeIds.contains($0.id) }

        // Place selected nodes at the beginning (on bottom)
        nodes = selected + unselected
    }

    // MARK: - Serialization

    public func exportJSON() -> String? {
        let data = WorkflowData(nodes: nodes, connections: connections)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let jsonData = try? encoder.encode(data) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }

    public func importJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let workflowData = try? JSONDecoder().decode(WorkflowData.self, from: data) else {
            return false
        }
        nodes = workflowData.nodes
        connections = workflowData.connections
        return true
    }

    /// Import JSON and store the raw input for capture
    public func importJSON(_ json: String, storeRawInput: Bool) -> Bool {
        if storeRawInput {
            rawInput = json.data(using: .utf8)
        }
        return importJSON(json)
    }

    // MARK: - Full Capture

    /// Create a complete capture of the workflow state for debugging/snapshots.
    /// Includes raw input (if stored), current state, and schema metadata.
    public func capture(schema: (any WFSchemaProvider)? = nil) -> WFWorkflowCapture {
        let currentState = WorkflowData(nodes: nodes, connections: connections)

        let schemaInfo: WFWorkflowCapture.SchemaInfo?
        if let schema = schema {
            let nodeTypes = schema.nodeTypes
            let totalFields = nodeTypes.reduce(0) { $0 + $1.fields.count }
            schemaInfo = WFWorkflowCapture.SchemaInfo(
                nodeTypeCount: nodeTypes.count,
                nodeTypeIds: nodeTypes.map { $0.id },
                totalFieldCount: totalFields
            )
        } else {
            schemaInfo = nil
        }

        return WFWorkflowCapture(
            rawInput: rawInput,
            currentState: currentState,
            schemaInfo: schemaInfo,
            clientMetadata: clientMetadata
        )
    }

    /// Export a full capture as JSON string
    public func exportCapture(schema: (any WFSchemaProvider)? = nil) -> String? {
        capture(schema: schema).toJSON()
    }
}

// MARK: - Sample Data

public extension CanvasState {
    static func sampleState() -> CanvasState {
        let state = CanvasState()

        // Create sample nodes using convenience API (positions will be auto-laid out)
        let trigger = state.addNode(
            type: .trigger,
            title: "Voice Input"
        )

        let llm = state.addNode(
            type: .llm,
            title: "Summarize",
            configuration: NodeConfiguration(
                prompt: "Summarize the following transcript:\n{{input}}",
                model: "gemini-2.0-flash",
                temperature: 0.7
            )
        )

        let condition = state.addNode(
            type: .condition,
            title: "Has Tasks?",
            configuration: NodeConfiguration(
                condition: "output contains 'task'"
            )
        )

        let action = state.addNode(
            type: .action,
            title: "Create Reminder",
            configuration: NodeConfiguration(
                actionType: "reminder"
            )
        )

        let output = state.addNode(
            type: .output,
            title: "Save Result"
        )

        // Create connections
        state.connect(trigger, to: llm)
        state.connect(llm, to: condition)
        state.connect(condition, port: "True", to: action)
        state.connect(condition, port: "False", to: output)

        // Apply auto-layout for a nice flow
        state.autoLayout(
            spacing: CGSize(width: 300, height: 140),
            origin: CGPoint(x: 100, y: 100)
        )

        return state
    }
}
