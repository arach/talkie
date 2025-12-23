import SwiftUI
import os

private let portLogger = Logger(subsystem: "dev.arach.WFKit", category: "Ports")

// MARK: - Node View

public struct NodeView: View {
    let node: WorkflowNode
    let isSelected: Bool
    let isHovered: Bool
    let canvasState: CanvasState
    let scale: CGFloat

    var onPortDragStart: ((ConnectionAnchor) -> Void)?
    var onPortDragUpdate: ((CGPoint) -> Void)?
    var onPortDragEnd: ((ConnectionAnchor?) -> Void)?
    var onPortHover: ((UUID?) -> Void)?
    var onNodeUpdate: ((WorkflowNode) -> Void)?

    @State private var isDraggingPort: Bool = false
    @State private var showEditor: Bool = false
    @State private var editedNode: WorkflowNode
    @State private var hoverEdge: HoverEdge? = nil
    @State private var hideEdgeWorkItem: DispatchWorkItem? = nil
    @Environment(\.wfTheme) private var theme
    @Environment(\.wfLayoutMode) private var layoutMode

    // Edge proximity detection
    private enum HoverEdge {
        case left, right, top, bottom
    }

    // How close to edge (in points) to trigger port reveal
    private let edgeRevealThreshold: CGFloat = 30
    // How long to keep ports visible after leaving the edge zone
    private let portHideDelay: TimeInterval = 0.4

    // Counter-scale factor to keep text crisp (cancels out parent scaleEffect)
    // Clamped so text still scales somewhat at extreme zoom levels
    private var counterScale: CGFloat {
        let raw = 1.0 / scale
        // Clamp between 0.6 and 1.4 - text stays mostly fixed in 70%-170% zoom range
        // but starts scaling at extremes
        return min(max(raw, 0.6), 1.4)
    }

    // Debug mode to show scale values (use WFDebugToolbar instead)
    private let debugMode = false

    // Show ports when hovering near ANY edge, or connection drag is active, or node is selected
    private var showPorts: Bool {
        hoverEdge != nil || canvasState.pendingConnection != nil || isSelected
    }

    public init(
        node: WorkflowNode,
        isSelected: Bool,
        isHovered: Bool,
        canvasState: CanvasState,
        scale: CGFloat = 1.0,
        onPortDragStart: ((ConnectionAnchor) -> Void)? = nil,
        onPortDragUpdate: ((CGPoint) -> Void)? = nil,
        onPortDragEnd: ((ConnectionAnchor?) -> Void)? = nil,
        onPortHover: ((UUID?) -> Void)? = nil,
        onNodeUpdate: ((WorkflowNode) -> Void)? = nil
    ) {
        self.node = node
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.canvasState = canvasState
        self.scale = scale
        self.onPortDragStart = onPortDragStart
        self.onPortDragUpdate = onPortDragUpdate
        self.onPortDragEnd = onPortDragEnd
        self.onPortHover = onPortHover
        self.onNodeUpdate = onNodeUpdate
        self._editedNode = State(initialValue: node)
    }

    private let portSize: CGFloat = 10

    // Port area extends beyond node bounds - need extra width for hit testing
    private let portExtension: CGFloat = 20

    public var body: some View {
        ZStack {
            nodeBackground
                .frame(width: node.size.width, height: node.size.height)

            VStack(spacing: 0) {
                nodeHeader
                nodeBody
            }
            .frame(width: node.size.width, height: node.size.height)

            // Input ports - positioned based on layout mode
            inputPorts
                .opacity(showPorts ? 1 : 0)
                .allowsHitTesting(showPorts)
                .animation(.easeOut(duration: 0.15), value: showPorts)
                .offset(
                    x: layoutMode == .vertical ? 0 : -node.size.width / 2,
                    y: layoutMode == .vertical ? -node.size.height / 2 : 0
                )

            // Output ports - positioned based on layout mode
            outputPorts
                .opacity(showPorts ? 1 : 0)
                .allowsHitTesting(showPorts)
                .animation(.easeOut(duration: 0.15), value: showPorts)
                .offset(
                    x: layoutMode == .vertical ? 0 : node.size.width / 2,
                    y: layoutMode == .vertical ? node.size.height / 2 : 0
                )
        }
        // Expand frame to include port hit areas
        .frame(
            width: node.size.width + (layoutMode == .freeform ? portExtension * 2 : 0),
            height: node.size.height + (layoutMode == .vertical ? portExtension * 2 : 0)
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // Adjust location to be relative to node bounds (not the expanded frame)
                let adjustedX = location.x - (layoutMode == .freeform ? portExtension : 0)
                let adjustedY = location.y - (layoutMode == .vertical ? portExtension : 0)

                // Calculate which edge is closest based on cursor position and layout mode
                let newEdge: HoverEdge?

                if layoutMode == .vertical {
                    // Vertical mode: check top/bottom edges
                    let distanceToTop = adjustedY
                    let distanceToBottom = node.size.height - adjustedY

                    if distanceToTop < edgeRevealThreshold {
                        newEdge = .top
                    } else if distanceToBottom < edgeRevealThreshold {
                        newEdge = .bottom
                    } else {
                        newEdge = nil
                    }
                } else {
                    // Freeform mode: check left/right edges
                    let distanceToLeft = adjustedX
                    let distanceToRight = node.size.width - adjustedX

                    if distanceToLeft < edgeRevealThreshold {
                        newEdge = .left
                    } else if distanceToRight < edgeRevealThreshold {
                        newEdge = .right
                    } else {
                        newEdge = nil
                    }
                }

                if let edge = newEdge {
                    // Entering an edge zone - cancel any pending hide and show immediately
                    hideEdgeWorkItem?.cancel()
                    hideEdgeWorkItem = nil
                    if hoverEdge != edge {
                        withAnimation(.easeOut(duration: 0.15)) {
                            hoverEdge = edge
                        }
                    }
                } else if hoverEdge != nil {
                    // Left edge zone but still on node - schedule delayed hide
                    scheduleHideEdge()
                }

            case .ended:
                // Left the node entirely - schedule delayed hide
                scheduleHideEdge()
            }
        }
        .onTapGesture(count: 2) {
            editedNode = node
            showEditor = true
        }
        .contextMenu {
            nodeContextMenu
        }
        .popover(isPresented: $showEditor, arrowEdge: .trailing) {
            NodeEditorView(node: $editedNode, onSave: {
                onNodeUpdate?(editedNode)
                showEditor = false
            })
            .frame(width: 320, height: 400)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var nodeContextMenu: some View {
        Button("Edit") {
            editedNode = node
            showEditor = true
        }
        .keyboardShortcut(.return, modifiers: [])

        Button("Duplicate") {
            canvasState.selectNode(node.id, exclusive: true)
            canvasState.duplicateSelectedNodes()
        }
        .keyboardShortcut("d", modifiers: .command)

        Button("Copy") {
            canvasState.selectNode(node.id, exclusive: true)
            canvasState.copySelectedNodes()
        }
        .keyboardShortcut("c", modifiers: .command)

        Divider()

        Button("Delete", role: .destructive) {
            canvasState.removeNode(node.id)
        }
        .keyboardShortcut(.delete, modifiers: [])

        Divider()

        Menu("Change Color") {
            ForEach(NodeType.allCases) { nodeType in
                Button {
                    var updatedNode = node
                    updatedNode.type = nodeType
                    onNodeUpdate?(updatedNode)
                } label: {
                    Label(nodeType.rawValue, systemImage: nodeType.icon)
                }
            }
        }

        Divider()

        Button("Bring to Front") {
            canvasState.selectNode(node.id, exclusive: true)
            canvasState.bringSelectedToFront()
        }
        .keyboardShortcut("]", modifiers: .command)

        Button("Send to Back") {
            canvasState.selectNode(node.id, exclusive: true)
            canvasState.sendSelectedToBack()
        }
        .keyboardShortcut("[", modifiers: .command)
    }

    // MARK: - Node Background

    @ViewBuilder
    private var nodeBackground: some View {
        if theme.useOutlineStyle {
            // Minimal style: transparent background with thin border only
            RoundedRectangle(cornerRadius: theme.nodeRadius)
                .fill(theme.isDark ? Color(hex: "0A0A0A") : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.nodeRadius)
                        .strokeBorder(
                            isSelected
                                ? theme.textSecondary
                                : (isHovered ? theme.nodeBorderHover : theme.nodeBorderMinimal),
                            lineWidth: theme.outlineBorderWidth
                        )
                )
        } else {
            // Standard style: filled background with shadow
            RoundedRectangle(cornerRadius: theme.nodeRadius)
                .fill(theme.nodeBackground)
                .overlay(
                    Group {
                        if theme.showNodeBorder {
                            RoundedRectangle(cornerRadius: theme.nodeRadius)
                                .strokeBorder(
                                    isSelected
                                        ? node.effectiveColor
                                        : (isHovered ? theme.nodeBorderHover : theme.nodeBorder),
                                    lineWidth: isSelected ? theme.nodeBorderWidth + 0.5 : theme.nodeBorderWidth
                                )
                        }
                    }
                )
                .shadow(
                    color: theme.showNodeGlow
                        ? (isSelected ? node.effectiveColor.opacity(0.25) : (theme.isDark ? Color.black.opacity(0.3) : Color.black.opacity(0.15)))
                        : Color.clear,
                    radius: isSelected ? 8 : 4,
                    x: 0,
                    y: isSelected ? 4 : 2
                )
                .shadow(
                    color: theme.showNodeGlow
                        ? (theme.isDark ? Color.black.opacity(0.2) : Color.black.opacity(0.1))
                        : Color.clear,
                    radius: 2,
                    x: 0,
                    y: 1
                )
        }
    }

    // MARK: - Node Header

    @ViewBuilder
    private var nodeHeader: some View {
        HStack(spacing: 8) {
            // Icon badge - grayscale for minimal, colored for other styles
            Image(systemName: node.type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.useOutlineStyle
                    ? theme.textSecondary
                    : (theme.isDark ? Color(hex: "0D0D0D") : Color(hex: "1A1A1A")))
                .frame(width: 20, height: 20)
                .background(theme.useOutlineStyle
                    ? theme.nodeBorderMinimal
                    : node.effectiveColor)
                .clipShape(RoundedRectangle(cornerRadius: max(2, theme.nodeRadius / 4)))
                .scaleEffect(counterScale, anchor: .leading)

            Text(node.title)
                .font(theme.nodeTitle)
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .scaleEffect(counterScale, anchor: .leading)

            Spacer()

            Text(node.type.rawValue.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(theme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(theme.useOutlineStyle
                    ? Color.clear
                    : theme.sectionBackground.opacity(0.8))
                .overlay(
                    Group {
                        if theme.useOutlineStyle {
                            RoundedRectangle(cornerRadius: max(2, theme.nodeRadius / 4))
                                .strokeBorder(theme.nodeBorderMinimal, lineWidth: 0.5)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: max(2, theme.nodeRadius / 4)))
                .scaleEffect(counterScale, anchor: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Group {
                if theme.useOutlineStyle {
                    // Minimal: no colored gradient, just subtle gray
                    Color.clear
                } else {
                    // Standard: colored gradient
                    LinearGradient(
                        gradient: Gradient(colors: [
                            node.effectiveColor.opacity(0.12),
                            node.effectiveColor.opacity(0.06)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: theme.nodeRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: theme.nodeRadius
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.useOutlineStyle
                    ? theme.nodeBorderMinimal
                    : node.effectiveColor.opacity(0.2))
                .frame(height: theme.useOutlineStyle ? 0.5 : 1)
        }
    }

    // MARK: - Node Body

    @ViewBuilder
    private var nodeBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Summary text - counter-scale for crisp rendering
            Text(nodeSummary)
                .font(theme.nodeSubtitle)
                .foregroundColor(theme.textSecondary)
                .lineLimit(2)
                .scaleEffect(counterScale, anchor: .topLeading)
                .padding(.horizontal, 12)

            Spacer()

            // Debug overlay
            if debugMode {
                debugOverlay
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Debug Overlay

    @ViewBuilder
    private var debugOverlay: some View {
        HStack(spacing: 4) {
            Text("z:\(String(format: "%.0f", scale * 100))%")
            Text("cs:\(String(format: "%.2f", counterScale))")
            Text("sz:\(Int(node.size.width))x\(Int(node.size.height))")
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .scaleEffect(counterScale, anchor: .bottomLeading)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Edge Hover Helpers

    private func scheduleHideEdge() {
        // Cancel any existing scheduled hide
        hideEdgeWorkItem?.cancel()

        // Schedule a new delayed hide
        let workItem = DispatchWorkItem { [self] in
            withAnimation(.easeOut(duration: 0.2)) {
                hoverEdge = nil
            }
        }
        hideEdgeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + portHideDelay, execute: workItem)
    }

    private var nodeSummary: String {
        switch node.type {
        case .trigger:
            return "Starts the workflow"

        case .llm:
            var parts: [String] = []
            if let model = node.configuration.model {
                let shortModel = model.split(separator: "-").last.map(String.init) ?? model
                parts.append(shortModel)
            }
            if let temp = node.configuration.temperature {
                parts.append("t:\(String(format: "%.1f", temp))")
            }
            if let maxTokens = node.configuration.maxTokens {
                parts.append("\(maxTokens)tok")
            }
            if parts.isEmpty {
                return "AI processing"
            }
            return parts.joined(separator: " · ")

        case .transform:
            if let expr = node.configuration.expression, !expr.isEmpty {
                let preview = expr.prefix(35).replacingOccurrences(of: "\n", with: " ")
                return "\(preview)\(expr.count > 35 ? "…" : "")"
            }
            return "Transform data"

        case .condition:
            if let cond = node.configuration.condition, !cond.isEmpty {
                let preview = cond.prefix(30).replacingOccurrences(of: "\n", with: " ")
                return "if \(preview)\(cond.count > 30 ? "…" : "")"
            }
            return "Conditional branch"

        case .action:
            if let actionType = node.configuration.actionType, !actionType.isEmpty {
                return actionType
            }
            return "Perform action"

        case .notification:
            var parts: [String] = []
            if let channel = node.configuration.notificationChannel {
                parts.append(channel.rawValue)
            }
            if let title = node.configuration.notificationTitle, !title.isEmpty {
                let preview = title.prefix(20)
                parts.append("\"\(preview)\(title.count > 20 ? "…" : "")\"")
            }
            if parts.isEmpty {
                return "Send notification"
            }
            return parts.joined(separator: " · ")

        case .output:
            return "Output result"
        }
    }

    // MARK: - Input Ports

    @ViewBuilder
    private var inputPorts: some View {
        if !node.inputs.isEmpty {
            if layoutMode == .vertical {
                // Horizontal arrangement for vertical mode (top edge)
                HStack(spacing: 0) {
                    ForEach(Array(node.inputs.enumerated()), id: \.element.id) { index, port in
                        PortView(
                            port: port,
                            nodeId: node.id,
                            color: node.effectiveColor,
                            canvasState: canvasState,
                            scale: scale,
                            onDragStart: onPortDragStart,
                            onDragUpdate: onPortDragUpdate,
                            onDragEnd: onPortDragEnd,
                            onHover: onPortHover
                        )
                        .frame(width: node.size.width / CGFloat(node.inputs.count))
                    }
                }
                .frame(height: portSize * 3 + portExtension)
            } else {
                // Vertical arrangement for freeform mode (left edge)
                VStack(spacing: 0) {
                    ForEach(Array(node.inputs.enumerated()), id: \.element.id) { index, port in
                        PortView(
                            port: port,
                            nodeId: node.id,
                            color: node.effectiveColor,
                            canvasState: canvasState,
                            scale: scale,
                            onDragStart: onPortDragStart,
                            onDragUpdate: onPortDragUpdate,
                            onDragEnd: onPortDragEnd,
                            onHover: onPortHover
                        )
                        .frame(height: node.size.height / CGFloat(node.inputs.count))
                    }
                }
                .frame(width: portSize * 3 + portExtension)
            }
        }
    }

    // MARK: - Output Ports

    @ViewBuilder
    private var outputPorts: some View {
        if !node.outputs.isEmpty {
            if layoutMode == .vertical {
                // Horizontal arrangement for vertical mode (bottom edge)
                HStack(spacing: 0) {
                    ForEach(Array(node.outputs.enumerated()), id: \.element.id) { index, port in
                        PortView(
                            port: port,
                            nodeId: node.id,
                            color: node.effectiveColor,
                            canvasState: canvasState,
                            scale: scale,
                            onDragStart: onPortDragStart,
                            onDragUpdate: onPortDragUpdate,
                            onDragEnd: onPortDragEnd,
                            onHover: onPortHover
                        )
                        .frame(width: node.size.width / CGFloat(node.outputs.count))
                    }
                }
                .frame(height: portSize * 3 + portExtension)
            } else {
                // Vertical arrangement for freeform mode (right edge)
                VStack(spacing: 0) {
                    ForEach(Array(node.outputs.enumerated()), id: \.element.id) { index, port in
                        PortView(
                            port: port,
                            nodeId: node.id,
                            color: node.effectiveColor,
                            canvasState: canvasState,
                            scale: scale,
                            onDragStart: onPortDragStart,
                            onDragUpdate: onPortDragUpdate,
                            onDragEnd: onPortDragEnd,
                            onHover: onPortHover
                        )
                        .frame(height: node.size.height / CGFloat(node.outputs.count))
                    }
                }
                .frame(width: portSize * 3 + portExtension)
            }
        }
    }
}

// MARK: - Port View

struct PortView: View {
    let port: Port
    let nodeId: UUID
    let color: Color
    let canvasState: CanvasState
    let scale: CGFloat

    var onDragStart: ((ConnectionAnchor) -> Void)?
    var onDragUpdate: ((CGPoint) -> Void)?
    var onDragEnd: ((ConnectionAnchor?) -> Void)?
    var onHover: ((UUID?) -> Void)?

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false
    @State private var pulsePhase: CGFloat = 0
    @Environment(\.wfTheme) private var theme
    @Environment(\.wfReadOnly) private var isReadOnly
    @Environment(\.wfLayoutMode) private var layoutMode

    private let portSize: CGFloat = 12

    // Counter-scale factor to keep text crisp
    private var counterScale: CGFloat { 1.0 / scale }

    // Computed states for visual feedback
    private var isConnectionDragActive: Bool {
        canvasState.pendingConnection != nil
    }

    private var isValidDropTarget: Bool {
        canvasState.validDropPortIds.contains(port.id)
    }

    private var isPendingSource: Bool {
        canvasState.pendingConnection?.sourceAnchor.portId == port.id
    }

    private var isSnapped: Bool {
        canvasState.hoveredPortId == port.id && isValidDropTarget
    }

    private var isInvalidDuringDrag: Bool {
        isConnectionDragActive && !isValidDropTarget && !isPendingSource
    }

    var body: some View {
        GeometryReader { geometry in
            if layoutMode == .vertical {
                // Vertical mode: center ports horizontally
                VStack(spacing: 0) {
                    if !port.isInput {
                        Spacer()
                    }

                    portCircle

                    if port.isInput {
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                // Freeform mode: ports on left/right edges
                HStack(spacing: 0) {
                    if !port.isInput {
                        Spacer()
                    }

                    portCircle

                    if port.isInput {
                        Spacer()
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var portCircle: some View {
        ZStack {
            // Outer pulsing glow for valid drop targets
            if isValidDropTarget {
                Circle()
                    .fill(Color.green.opacity(0.15 + pulsePhase * 0.15))
                    .frame(width: portSize + 16, height: portSize + 16)
                    .blur(radius: 4)

                Circle()
                    .strokeBorder(Color.green.opacity(0.4 + pulsePhase * 0.3), lineWidth: 2)
                    .frame(width: portSize + 10, height: portSize + 10)
            }

            // Snapped indicator ring
            if isSnapped {
                Circle()
                    .strokeBorder(Color.green, lineWidth: 2.5)
                    .frame(width: portSize + 6, height: portSize + 6)
                    .shadow(color: Color.green.opacity(0.6), radius: 4)
            }

            // Hover glow (when not in drag mode)
            if isHovered && !isConnectionDragActive {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: portSize + 8, height: portSize + 8)
            }

            // Main port circle
            Circle()
                .fill(portFillColor)
                .overlay(
                    Circle()
                        .strokeBorder(portBorderColor, lineWidth: portBorderWidth)
                )
                .frame(width: portSize, height: portSize)
                .shadow(
                    color: portShadowColor,
                    radius: isSnapped ? 4 : 2,
                    x: 0,
                    y: 1
                )

            // Center dot for valid targets
            if isValidDropTarget && !isSnapped {
                Circle()
                    .fill(Color.green)
                    .frame(width: 4, height: 4)
            }

            // Checkmark for snapped state
            if isSnapped {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: portSize + 20, height: portSize + 20)
        .contentShape(Rectangle())
        // No scaleEffect - position stays consistent across all states
        .opacity(portOpacity)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isValidDropTarget)
        .animation(.easeInOut(duration: 0.15), value: isSnapped)
        .animation(.easeInOut(duration: 0.15), value: isConnectionDragActive)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                portLogger.debug("hover: \(port.label, privacy: .public) isInput=\(port.isInput) isValidTarget=\(isValidDropTarget)")
            }
            onHover?(hovering ? port.id : nil)
        }
        .onAppear {
            // Start pulse animation
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsePhase = 1.0
            }
        }
        .onTapGesture {
            // Don't allow connection creation in read-only mode
            guard !isReadOnly else { return }

            portLogger.info("tap: \(port.label, privacy: .public) isInput=\(port.isInput) connectionActive=\(isConnectionDragActive) isValidTarget=\(isValidDropTarget)")

            if isConnectionDragActive {
                // Complete connection if this is a valid target
                if isValidDropTarget {
                    portLogger.notice("complete: \(port.label, privacy: .public)")
                    canvasState.completeConnection(
                        to: nodeId,
                        targetPortId: port.id,
                        isInput: port.isInput
                    )
                } else {
                    portLogger.debug("rejected: not a valid target")
                }
            } else {
                // Start a new connection from this port
                if let portPos = canvasState.portPosition(nodeId: nodeId, portId: port.id) {
                    portLogger.info("start: \(port.label, privacy: .public) at (\(portPos.x, format: .fixed(precision: 0)), \(portPos.y, format: .fixed(precision: 0)))")
                    let anchor = ConnectionAnchor(
                        nodeId: nodeId,
                        portId: port.id,
                        position: portPos,
                        isInput: port.isInput
                    )
                    onDragStart?(anchor)
                } else {
                    portLogger.warning("no position for \(port.label, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Visual Properties

    private var portFillColor: Color {
        if isSnapped {
            return Color.green
        } else if isValidDropTarget {
            return Color.green.opacity(0.8)
        } else if isPendingSource || isDragging {
            return color
        } else if isHovered {
            return color
        } else if isInvalidDuringDrag {
            return theme.border.opacity(0.5)
        } else {
            return theme.border
        }
    }

    private var portBorderColor: Color {
        if isSnapped {
            return Color.white
        } else if isValidDropTarget {
            return Color.green
        } else if isPendingSource {
            return color
        } else if isInvalidDuringDrag {
            return color.opacity(0.2)
        } else {
            return color.opacity(0.5)
        }
    }

    private var portBorderWidth: CGFloat {
        if isSnapped || isValidDropTarget {
            return 2.0
        } else {
            return 1.5
        }
    }

    private var portShadowColor: Color {
        if isSnapped {
            return Color.green.opacity(0.5)
        } else if isValidDropTarget {
            return Color.green.opacity(0.3)
        } else {
            return Color.black.opacity(0.2)
        }
    }

    private var portOpacity: CGFloat {
        if isInvalidDuringDrag {
            return 0.4
        } else {
            return 1.0
        }
    }
}

// MARK: - Node Editor View

struct NodeEditorView: View {
    @Binding var node: WorkflowNode
    var onSave: () -> Void

    @State private var title: String
    @State private var prompt: String
    @State private var systemPrompt: String
    @State private var model: String
    @State private var temperature: Double
    @State private var condition: String
    @State private var actionType: String

    init(node: Binding<WorkflowNode>, onSave: @escaping () -> Void) {
        self._node = node
        self.onSave = onSave
        self._title = State(initialValue: node.wrappedValue.title)
        self._prompt = State(initialValue: node.wrappedValue.configuration.prompt ?? "")
        self._systemPrompt = State(initialValue: node.wrappedValue.configuration.systemPrompt ?? "")
        self._model = State(initialValue: node.wrappedValue.configuration.model ?? "gemini-2.0-flash")
        self._temperature = State(initialValue: node.wrappedValue.configuration.temperature ?? 0.7)
        self._condition = State(initialValue: node.wrappedValue.configuration.condition ?? "")
        self._actionType = State(initialValue: node.wrappedValue.configuration.actionType ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: node.type.icon)
                    .foregroundColor(node.type.color)
                Text("Edit \(node.type.rawValue)")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Node title", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    switch node.type {
                    case .llm:
                        llmFields
                    case .condition:
                        conditionFields
                    case .action:
                        actionFields
                    case .transform:
                        transformFields
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onSave()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveChanges()
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var llmFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $prompt)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 100)
                .border(Color.gray.opacity(0.3))
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("System Prompt (optional)")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $systemPrompt)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 60)
                .border(Color.gray.opacity(0.3))
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Model")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Model name", text: $model)
                .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Temperature: \(temperature, specifier: "%.2f")")
                .font(.caption)
                .foregroundColor(.secondary)
            Slider(value: $temperature, in: 0...2, step: 0.1)
        }
    }

    @ViewBuilder
    private var conditionFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Condition Expression")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $condition)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 80)
                .border(Color.gray.opacity(0.3))
            Text("Example: output.contains('important')")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var actionFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Action Type")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("e.g., reminder, notification", text: $actionType)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var transformFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transform Expression")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $prompt)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 80)
                .border(Color.gray.opacity(0.3))
        }
    }

    private func saveChanges() {
        node.title = title

        switch node.type {
        case .llm:
            node.configuration.prompt = prompt.isEmpty ? nil : prompt
            node.configuration.systemPrompt = systemPrompt.isEmpty ? nil : systemPrompt
            node.configuration.model = model.isEmpty ? nil : model
            node.configuration.temperature = temperature
        case .condition:
            node.configuration.condition = condition.isEmpty ? nil : condition
        case .action:
            node.configuration.actionType = actionType.isEmpty ? nil : actionType
        case .transform:
            node.configuration.expression = prompt.isEmpty ? nil : prompt
        default:
            break
        }
    }
}
