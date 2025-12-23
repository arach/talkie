import SwiftUI
import AppKit

// MARK: - Preference Key for Canvas Frame

private struct CanvasFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Overlay Button Style

private struct OverlayButtonStyle: ButtonStyle {
    @Environment(\.wfTheme) private var theme
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed
                        ? (isDestructive ? theme.error.opacity(0.2) : theme.accent.opacity(0.2))
                        : Color.clear)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct HoverableOverlayButton<Content: View>: View {
    let action: () -> Void
    let isDestructive: Bool
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false
    @Environment(\.wfTheme) private var theme

    init(isDestructive: Bool = false, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.isDestructive = isDestructive
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered
                            ? (isDestructive ? theme.error.opacity(0.15) : theme.textSecondary.opacity(0.15))
                            : Color.clear)
                )
        }
        .buttonStyle(OverlayButtonStyle(isDestructive: isDestructive))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Workflow Canvas View

// MARK: - Cursor State

enum CanvasCursorState {
    case `default`
    case pan           // Hand cursor - panning mode (space held)
    case move          // Move cursor - dragging nodes
    case pointer       // Arrow pointer - hovering over selectable items
    case connecting    // Crosshair - creating connections
}

public struct WorkflowCanvas: View {
    @Bindable var state: CanvasState
    @State private var draggedNodeId: UUID?
    @State private var panDragOffset: CGSize = .zero
    @FocusState private var isFocused: Bool
    @State private var isSpacePressed: Bool = false
    @State private var isPanMode: Bool = false
    @State private var keyEventMonitor: Any?
    @State private var scrollEventMonitor: Any?
    @State private var canvasSize: CGSize = .zero
    @State private var isMouseOverCanvas: Bool = false
    @State private var canvasFrameInWindow: CGRect = .zero
    @State private var zoomTimer: Timer?
    @State private var contextMenuState = WFContextMenuState()
    @State private var rightClickMonitor: Any?
    @State private var lastRightClickPosition: CGPoint = .zero
    @State private var cursorState: CanvasCursorState = .default
    @Environment(\.wfTheme) private var theme
    @Environment(\.wfReadOnly) private var isReadOnly

    public init(state: CanvasState) {
        self.state = state
    }

    // MARK: - Cursor Management

    private func updateCursor(_ newState: CanvasCursorState) {
        guard cursorState != newState else { return }

        // Pop old cursor if we pushed one
        if cursorState != .default {
            NSCursor.pop()
        }

        cursorState = newState

        // Push new cursor
        switch newState {
        case .default:
            break // No cursor to push for default
        case .pan:
            NSCursor.openHand.push()
        case .move:
            NSCursor.crosshair.push()
        case .pointer:
            NSCursor.pointingHand.push()
        case .connecting:
            NSCursor.crosshair.push()
        }
    }

    public var body: some View {
        ZStack {
            canvasWithBasicKeyboard

            // Custom context menu overlay
            WFContextMenuOverlay(menuState: contextMenuState)
        }
        .onAppear {
            isFocused = true
            setupKeyboardMonitoring()
            startZoomInterpolation()
        }
        .onDisappear {
            cleanupKeyboardMonitoring()
            stopZoomInterpolation()
        }
    }

    @ViewBuilder
    private var canvasWithBasicKeyboard: some View {
        canvasGeometry
            .background(theme.canvasBackground)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .modifier(CanvasKeyboardModifier(
                state: state,
                onDelete: handleDelete,
                onArrowKey: handleArrowKey
            ))
    }

    // MARK: - Canvas Geometry

    @ViewBuilder
    private var canvasGeometry: some View {
        GeometryReader { geometry in
            canvasStack(geometry: geometry)
                .contentShape(Rectangle())
                .simultaneousGesture(backgroundPanGesture())
                .simultaneousGesture(magnificationGesture)
                .onTapGesture {
                    // Log the background tap with debugging info
                    handleBackgroundTap()

                    // Cancel connection mode if active
                    if state.isConnecting {
                        state.cancelPendingConnection()
                    } else {
                        state.clearSelection()
                        state.deselectConnection()
                    }
                    isFocused = true
                }
                .coordinateSpace(name: "canvas")
                .onChange(of: geometry.size) { _, newSize in
                    canvasSize = newSize
                }
                .onAppear {
                    canvasSize = geometry.size
                }
                .onHover { hovering in
                    isMouseOverCanvas = hovering
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CanvasFramePreferenceKey.self,
                            value: geo.frame(in: .global)
                        )
                    }
                )
                .onPreferenceChange(CanvasFramePreferenceKey.self) { frame in
                    canvasFrameInWindow = frame
                }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = state.scale * value
                state.targetScale = max(state.minScale, min(newScale, state.maxScale))
            }
    }

    @ViewBuilder
    private func canvasStack(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background with grid
            CanvasBackground(scale: state.scale, offset: state.offset)

            // Canvas content with scale - semantic zoom
            // scaleEffect handles node positions/sizes, NodeView counter-scales text for crispness
            canvasContent
                .scaleEffect(state.scale, anchor: .topLeading)
                .offset(state.offset)

            // Minimap overlay (bottom-left corner)
            minimapOverlay(canvasSize: geometry.size)

            // Pan mode indicator (top-left corner)
            panModeIndicator

            // Connection mode indicator (top-left corner, takes precedence over pan)
            connectionModeIndicator

            // Controls overlay (top-right corner)
            canvasControlsOverlay
        }
    }

    // MARK: - Canvas Controls Overlay

    @ViewBuilder
    private var canvasControlsOverlay: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    // Zoom controls
                    zoomControlsPanel

                    // Connection actions (when connection selected)
                    if state.selectedConnectionId != nil && !isReadOnly {
                        connectionActionsPanel
                    }
                    // Node selection actions (only when nodes selected, hidden in read-only mode)
                    else if state.hasSelection && !isReadOnly {
                        selectionActionsPanel
                    }
                }
                .padding(16)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var zoomControlsPanel: some View {
        HStack(spacing: 0) {
            HoverableOverlayButton(action: { state.zoomOut() }) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 32, height: 28)
            }
            .help("Zoom Out (⌘-)")

            // Zoom percentage badge
            Text("\(Int(state.scale * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(theme.sectionBackground.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: max(theme.panelRadius - 2, 2)))

            HoverableOverlayButton(action: { state.zoomIn() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 32, height: 28)
            }
            .help("Zoom In (⌘+)")

            Divider()
                .frame(height: 16)
                .padding(.leading, 4)

            HoverableOverlayButton(action: { state.resetView() }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 32, height: 28)
            }
            .help("Fit to View (⌘0)")
        }
        .foregroundColor(theme.textSecondary)
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .background(theme.panelBackground.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: theme.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.panelRadius)
                .strokeBorder(theme.border.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private var selectionActionsPanel: some View {
        HStack(spacing: 0) {
            // Selection badge
            HStack(spacing: 4) {
                Text("\(state.selectedNodeIds.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(state.selectedNodeIds.count == 1 ? "node" : "nodes")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.accent.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: max(theme.panelRadius - 2, 2)))

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 6)

            HoverableOverlayButton(action: { state.duplicateSelectedNodes() }) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 32, height: 28)
            }
            .foregroundColor(theme.textSecondary)
            .help("Duplicate (⌘D)")

            HoverableOverlayButton(isDestructive: true, action: { state.removeSelectedNodes() }) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 32, height: 28)
            }
            .foregroundColor(theme.error.opacity(0.85))
            .help("Delete (⌫)")
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .background(theme.panelBackground.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: theme.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.panelRadius)
                .strokeBorder(theme.border.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeInOut(duration: 0.15), value: state.hasSelection)
    }

    /// Get the currently selected connection
    private var selectedConnection: WorkflowConnection? {
        guard let id = state.selectedConnectionId else { return nil }
        return state.connections.first { $0.id == id }
    }

    @ViewBuilder
    private var connectionActionsPanel: some View {
        if let connection = selectedConnection {
            HStack(spacing: 0) {
                // Connection badge with waypoint count
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("1")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("path")
                        .font(.system(size: 11, weight: .medium))
                    if !connection.waypoints.isEmpty {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(theme.accent)
                        Text("\(connection.waypoints.count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.accent)
                    }
                }
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: max(theme.panelRadius - 2, 2)))

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 6)

                // Clear waypoints button (only show if waypoints exist)
                if !connection.waypoints.isEmpty {
                    HoverableOverlayButton(action: {
                        state.clearSelectedConnectionWaypoints()
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 28, height: 28)
                    }
                    .foregroundColor(theme.textSecondary)
                    .help("Reset path")

                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 6)
                }

                // Delete button
                HoverableOverlayButton(isDestructive: true, action: {
                    if let id = state.selectedConnectionId {
                        state.removeConnection(id)
                        state.deselectConnection()
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 32, height: 28)
                }
                .foregroundColor(theme.error.opacity(0.85))
                .help("Delete (⌫)")
            }
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .padding(.vertical, 2)
            .background(theme.panelBackground.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: theme.panelRadius))
            .overlay(
                RoundedRectangle(cornerRadius: theme.panelRadius)
                    .strokeBorder(theme.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.15), value: state.selectedConnectionId)
        }
    }

    @ViewBuilder
    private func routingButton(icon: String, preference: WFRoutingPreference, current: WFRoutingPreference, tooltip: String) -> some View {
        let isSelected = preference == current
        Button(action: {
            state.setSelectedConnectionRouting(preference)
        }) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundColor(isSelected ? .white : theme.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? theme.accent : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    @ViewBuilder
    private func minimapOverlay(canvasSize: CGSize) -> some View {
        VStack {
            Spacer()
            HStack {
                MinimapView(
                    state: state,
                    canvasSize: canvasSize
                )
                .padding(16)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var panModeIndicator: some View {
        if isPanMode {
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 11))
                        Text("Pan Mode")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.8))
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(16)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var connectionModeIndicator: some View {
        if state.isConnecting {
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Connecting...")
                            .font(.system(size: 12, weight: .medium))

                        // Divider
                        Rectangle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 1, height: 14)

                        // Cancel button
                        Button(action: {
                            state.cancelPendingConnection()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Cancel")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.9))
                    }
                    .foregroundColor(.white)
                    .padding(.leading, 12)
                    .padding(.trailing, 10)
                    .padding(.vertical, 7)
                    .background(theme.accent.opacity(0.9))
                    .clipShape(Capsule())
                    .shadow(color: theme.accent.opacity(0.3), radius: 8, x: 0, y: 2)
                    .padding(16)
                    Spacer()
                }
                Spacer()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.easeOut(duration: 0.15), value: state.isConnecting)
        }
    }

    // MARK: - Context Menu Items

    private func buildContextMenuItems() -> [WFMenuItem] {
        var items: [WFMenuItem] = []

        // Add Node and Paste only available in edit mode
        if !isReadOnly {
            let nodeSubmenu = NodeType.allCases.map { nodeType in
                WFMenuItem(
                    label: nodeType.rawValue,
                    icon: nodeType.icon,
                    action: { [self] in
                        state.addNode(type: nodeType, at: lastRightClickPosition)
                    }
                )
            }
            items.append(WFMenuItem(label: "Add Node", icon: "plus.circle", submenu: nodeSubmenu))
            items.append(.divider)
            items.append(WFMenuItem(
                label: "Paste",
                icon: "doc.on.clipboard",
                shortcut: "⌘V",
                isDisabled: !canPaste(),
                action: { [self] in state.pasteNodes() }
            ))
        }

        items.append(WFMenuItem(
            label: "Select All",
            icon: "checkmark.circle",
            shortcut: "⌘A",
            action: { [self] in state.selectAll() }
        ))
        items.append(.divider)
        items.append(WFMenuItem(
            label: "Zoom to Fit",
            icon: "arrow.up.left.and.arrow.down.right",
            shortcut: "⌘0",
            action: { [self] in state.zoomToFit(in: canvasSize) }
        ))
        items.append(WFMenuItem(
            label: "Reset View",
            icon: "1.magnifyingglass",
            action: { [self] in state.resetView() }
        ))

        return items
    }

    private func canPaste() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let jsonString = pasteboard.string(forType: .string),
              let data = jsonString.data(using: .utf8),
              let _ = try? JSONDecoder().decode(WorkflowData.self, from: data) else {
            return false
        }
        return true
    }

    // MARK: - Event Monitoring

    private func startZoomInterpolation() {
        zoomTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            let difference = state.targetScale - state.scale
            if abs(difference) > 0.001 {
                state.scale += difference * 0.15
            } else if difference != 0 {
                state.scale = state.targetScale
            }
        }
    }

    private func stopZoomInterpolation() {
        zoomTimer?.invalidate()
        zoomTimer = nil
    }

    private func setupKeyboardMonitoring() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            if event.keyCode == 49 { // Space bar
                if event.type == .keyDown && !self.isSpacePressed {
                    self.isSpacePressed = true
                    self.isPanMode = true
                    self.updateCursor(.pan)
                } else if event.type == .keyUp && self.isSpacePressed {
                    self.isSpacePressed = false
                    self.isPanMode = false
                    // Restore cursor based on current state
                    if self.state.isDragging {
                        self.updateCursor(.move)
                    } else if self.state.hoveredNodeId != nil || self.state.hoveredConnectionId != nil {
                        self.updateCursor(.pointer)
                    } else if self.state.isConnecting {
                        self.updateCursor(.connecting)
                    } else {
                        self.updateCursor(.default)
                    }
                }
            }

            if event.type == .keyDown && event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c":
                    // Copy allowed in read-only (for debugging/sharing)
                    self.state.copySelectedNodes()
                    return nil
                case "v":
                    // Paste disabled in read-only mode
                    if !self.isReadOnly {
                        self.state.pasteNodes()
                    }
                    return nil
                case "d":
                    // Duplicate disabled in read-only mode
                    if !self.isReadOnly {
                        self.state.duplicateSelectedNodes()
                    }
                    return nil
                case "a":
                    self.state.selectAll()
                    return nil
                default:
                    break
                }
            }
            return event
        }

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Only handle scroll events over the canvas, let others pass through
            // Use hover state combined with x-position check for inspector
            guard self.isMouseOverCanvas else { return event }

            // Additional check: if we have a valid canvas frame, verify mouse is within canvas X bounds
            // This catches the case where hover doesn't update correctly when inspector is open
            if self.canvasFrameInWindow.width > 0,
               let window = event.window {
                let mouseInWindow = event.locationInWindow
                // Inspector is on the right, so check if mouse X is within canvas width
                // (accounting for window content view coordinate conversion)
                if let contentView = window.contentView {
                    let mouseInView = contentView.convert(mouseInWindow, from: nil)
                    // If mouse X is beyond canvas width, it's over the inspector
                    if mouseInView.x > self.canvasFrameInWindow.width {
                        return event // Let inspector handle it
                    }
                }
            }

            self.handleScrollWheel(event: event)
            return nil // Consume the event to prevent propagation
        }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard self.isMouseOverCanvas else { return event }

            let mouseInWindow = event.locationInWindow
            if let window = event.window,
               let contentView = window.contentView {
                let mouseInView = contentView.convert(mouseInWindow, from: nil)
                let flippedY = contentView.bounds.height - mouseInView.y

                // Calculate canvas position for node placement
                let toolbarHeight: CGFloat = 34
                let canvasClickPoint = CGPoint(
                    x: (mouseInView.x - self.state.offset.width) / self.state.scale,
                    y: (flippedY - toolbarHeight - self.state.offset.height) / self.state.scale
                )
                self.lastRightClickPosition = canvasClickPoint

                self.contextMenuState.show(
                    at: CGPoint(x: mouseInView.x, y: flippedY),
                    items: self.buildContextMenuItems()
                )
            }
            return nil // Consume the event
        }
    }

    private func cleanupKeyboardMonitoring() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
            scrollEventMonitor = nil
        }
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
        // Reset cursor state
        if cursorState != .default {
            NSCursor.pop()
            cursorState = .default
        }
        isPanMode = false
        isSpacePressed = false
    }

    private func handleScrollWheel(event: NSEvent) {
        // Get mouse location for zoom-to-cursor
        let mouseInWindow = event.locationInWindow
        guard let window = event.window,
              let contentView = window.contentView else {
            // Fallback: zoom without cursor tracking
            let zoomDelta = event.scrollingDeltaY * 0.01
            let scaleFactor = 1.0 + zoomDelta
            let newScale = max(state.minScale, min(state.scale * scaleFactor, state.maxScale))
            state.scale = newScale
            state.targetScale = newScale
            return
        }

        let zoomDelta = event.scrollingDeltaY * 0.01
        let scaleFactor = 1.0 + zoomDelta
        let newScale = max(state.minScale, min(state.scale * scaleFactor, state.maxScale))

        // Convert mouse to view coordinates (flip Y for SwiftUI coordinate system)
        let mouseInView = contentView.convert(mouseInWindow, from: nil)
        let flippedY = contentView.bounds.height - mouseInView.y

        // Estimate canvas position (toolbar height ~34px)
        let toolbarHeight: CGFloat = 34
        let mouseInCanvas = CGPoint(
            x: mouseInView.x,
            y: flippedY - toolbarHeight
        )

        // Calculate the canvas point under the mouse before zoom
        let canvasPointX = (mouseInCanvas.x - state.offset.width) / state.scale
        let canvasPointY = (mouseInCanvas.y - state.offset.height) / state.scale

        // Update scale directly (bypass interpolation for precise cursor tracking)
        state.scale = newScale
        state.targetScale = newScale

        // Adjust offset so the same canvas point stays under the mouse
        let newOffsetX = mouseInCanvas.x - canvasPointX * newScale
        let newOffsetY = mouseInCanvas.y - canvasPointY * newScale

        state.offset = CGSize(width: newOffsetX, height: newOffsetY)
    }

    // MARK: - Canvas Content

    @ViewBuilder
    private var canvasContent: some View {
        ZStack {
            // Connections in a non-clipping container
            ZStack {
                connectionsLayer

                if let pending = state.pendingConnection {
                    let isSnapped = state.hoveredPortId != nil && state.validDropPortIds.contains(state.hoveredPortId ?? UUID())
                    PendingConnectionView(
                        from: pending.sourceAnchor.position,
                        to: pending.currentPoint,
                        color: isSnapped ? .green : .blue
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fixedSize(horizontal: false, vertical: false)

            nodesLayer
        }
    }

    // MARK: - Connections Layer

    @ViewBuilder
    private var connectionsLayer: some View {
        if let pending = state.pendingConnection,
           !state.validDropPortIds.isEmpty {
            ForEach(Array(state.validDropPortIds), id: \.self) { portId in
                if let (_, targetPos) = findPortPosition(portId: portId) {
                    let distance = hypot(
                        pending.currentPoint.x - targetPos.x,
                        pending.currentPoint.y - targetPos.y
                    )
                    if distance < 400 {
                        ConnectionPreviewView(
                            from: pending.sourceAnchor.position,
                            to: targetPos,
                            color: .blue.opacity(0.2)
                        )
                    }
                }
            }
        }

        ForEach(state.connections) { connection in
            let isBeingReconnected = state.reconnectingConnection?.id == connection.id

            if let startPos = state.portPosition(nodeId: connection.sourceNodeId, portId: connection.sourcePortId),
               let endPos = state.portPosition(nodeId: connection.targetNodeId, portId: connection.targetPortId) {
                let sourceNode = state.nodes.first(where: { $0.id == connection.sourceNodeId })
                let targetNode = state.nodes.first(where: { $0.id == connection.targetNodeId })
                let isHovered = state.hoveredConnectionId == connection.id
                let isSelected = state.selectedConnectionId == connection.id

                // For minimal theme, use grayscale; for other themes, use colorful gradients
                let connectionColor: Color = theme.useOutlineStyle
                    ? (theme.isDark ? Color(hex: "888888") : Color(hex: "555555"))
                    : (sourceNode?.type.color.opacity(0.8) ?? .gray)
                let srcColor: Color? = theme.useOutlineStyle ? nil : sourceNode?.type.color
                let tgtColor: Color? = theme.useOutlineStyle ? nil : targetNode?.type.color

                // Calculate obstacles (other nodes' bounding boxes, excluding source and target)
                let obstacles = state.nodes
                    .filter { $0.id != connection.sourceNodeId && $0.id != connection.targetNodeId }
                    .map { CGRect(origin: $0.position, size: $0.size) }

                // Only render the connection line if NOT being reconnected
                if !isBeingReconnected {
                    // Pass drag offset only for the selected connection during routing drag
                    let dragOffset = (isSelected && state.isRoutingDrag) ? state.routingDragOffset : .zero
                    // Pass live waypoint only for the selected connection during waypoint drag
                    let liveWaypoint = (isSelected && state.isWaypointDrag) ? state.liveWaypoint : nil

                    ConnectionView(
                        from: startPos,
                        to: endPos,
                        color: connectionColor,
                        sourceColor: srcColor,
                        targetColor: tgtColor,
                        isSelected: isSelected,
                        isHovered: isHovered,
                        curveStyle: theme.connectionStyle,
                        obstacles: obstacles,
                        routingPreference: connection.routingPreference,
                        routingDragOffset: dragOffset,
                        waypoints: connection.waypoints,
                        liveWaypoint: liveWaypoint
                    )
                    .contentShape(ConnectionHitShape(from: startPos, to: endPos, tolerance: 40, layoutMode: state.layoutMode))
                    .onTapGesture {
                        handleConnectionTap(connection)
                    }
                    .onHover { hovering in
                        if !state.isDragging && state.pendingConnection == nil && !isPanMode {
                            state.hoveredConnectionId = hovering ? connection.id : nil
                            // Update cursor - pointer for hovering connections
                            if hovering {
                                updateCursor(.pointer)
                            } else if state.hoveredNodeId == nil && !state.isConnecting {
                                updateCursor(.default)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Delete Connection") {
                            state.removeConnection(connection.id)
                        }
                    }
                }

                // Endpoint handles for drag-to-reconnect
                // Show when hovered, selected, OR being reconnected (to keep gesture alive)
                if isHovered || isSelected || isBeingReconnected {
                    // Source endpoint handle
                    ConnectionEndpointHandle(
                        position: startPos,
                        color: srcColor ?? connectionColor,
                        isSource: true,
                        connection: connection,
                        canvasState: state,
                        onReconnectionUpdate: handleReconnectionUpdate,
                        onReconnectionEnd: handleReconnectionEnd
                    )

                    // Target endpoint handle
                    ConnectionEndpointHandle(
                        position: endPos,
                        color: tgtColor ?? connectionColor,
                        isSource: false,
                        connection: connection,
                        canvasState: state,
                        onReconnectionUpdate: handleReconnectionUpdate,
                        onReconnectionEnd: handleReconnectionEnd
                    )

                    // Middle handle for adding/moving waypoints (show for all selected connections)
                    if !isBeingReconnected && isSelected && !isReadOnly {
                        // Show middle handle for dragging to add a waypoint
                        ConnectionMiddleHandle(
                            startPos: startPos,
                            endPos: endPos,
                            color: srcColor ?? connectionColor,
                            connection: connection,
                            canvasState: state,
                            layoutMode: state.layoutMode
                        )

                        // Show handles for existing waypoints
                        ForEach(Array(connection.waypoints.enumerated()), id: \.offset) { index, waypoint in
                            WaypointHandle(
                                position: waypoint.position,
                                color: srcColor ?? connectionColor,
                                waypointIndex: index,
                                connection: connection,
                                canvasState: state
                            )
                        }
                    }
                }
            }
        }
    }

    private func findPortPosition(portId: UUID) -> (UUID, CGPoint)? {
        for node in state.nodes {
            if let pos = state.portPosition(nodeId: node.id, portId: portId) {
                return (node.id, pos)
            }
        }
        return nil
    }

    // MARK: - Nodes Layer

    @ViewBuilder
    private var nodesLayer: some View {
        ForEach(state.nodes) { node in
            NodeView(
                node: node,
                isSelected: state.selectedNodeIds.contains(node.id),
                isHovered: state.hoveredNodeId == node.id,
                canvasState: state,
                scale: state.scale,
                onPortDragStart: isReadOnly ? nil : { anchor in
                    state.pendingConnection = PendingConnection(from: anchor)
                    state.updateValidDropPorts(for: anchor)
                },
                onPortDragUpdate: isReadOnly ? nil : { canvasPoint in
                    let snapThreshold: CGFloat = 25
                    var snappedPoint = canvasPoint
                    var closestDistance: CGFloat = snapThreshold

                    for portId in state.validDropPortIds {
                        if let (_, portPos) = findPortPosition(portId: portId) {
                            let distance = hypot(
                                canvasPoint.x - portPos.x,
                                canvasPoint.y - portPos.y
                            )
                            if distance < closestDistance {
                                closestDistance = distance
                                snappedPoint = portPos
                            }
                        }
                    }

                    state.pendingConnection?.currentPoint = snappedPoint

                    if closestDistance < snapThreshold {
                        for portId in state.validDropPortIds {
                            if let (_, portPos) = findPortPosition(portId: portId),
                               hypot(snappedPoint.x - portPos.x, snappedPoint.y - portPos.y) < 1 {
                                state.hoveredPortId = portId
                                break
                            }
                        }
                    }
                },
                onPortDragEnd: isReadOnly ? nil : { targetAnchor in
                    completePendingConnection(to: targetAnchor)
                },
                onPortHover: { portId in
                    state.hoveredPortId = portId
                },
                onNodeUpdate: { updatedNode in
                    state.updateNode(updatedNode)
                }
            )
            .contentShape(Rectangle())
            .highPriorityGesture(nodeDragGesture(for: node))
            .onTapGesture {
                handleNodeTap(node)
            }
            .onHover { isHovered in
                if !state.isDragging && !isPanMode {
                    state.hoveredNodeId = isHovered ? node.id : nil
                    // Update cursor - pointer for hovering nodes
                    if isHovered {
                        updateCursor(.pointer)
                    } else if state.hoveredConnectionId == nil && !state.isConnecting {
                        updateCursor(.default)
                    }
                }
            }
            .position(
                x: node.position.x + node.size.width / 2,
                y: node.position.y + node.size.height / 2
            )
        }
    }

    // MARK: - Gestures

    private func backgroundPanGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Skip panning during node drag, connection drag, or reconnection
                guard !state.isDragging,
                      state.pendingConnection == nil,
                      state.reconnectingConnection == nil else { return }

                state.isPanning = true
                let delta = CGSize(
                    width: value.translation.width - panDragOffset.width,
                    height: value.translation.height - panDragOffset.height
                )
                state.offset.width += delta.width
                state.offset.height += delta.height
                panDragOffset = value.translation
            }
            .onEnded { _ in
                state.isPanning = false
                panDragOffset = .zero
            }
    }

    @State private var dragStartLocation: CGPoint? = nil

    private func nodeDragGesture(for node: WorkflowNode) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .onChanged { value in
                // Disable node dragging in read-only mode
                guard !isReadOnly else { return }
                guard !isPanMode else { return }

                if !state.isDragging {
                    state.isDragging = true
                    state.beginNodeMove()
                    draggedNodeId = node.id
                    dragStartLocation = value.startLocation
                    // Show move cursor when dragging
                    updateCursor(.move)

                    if !state.selectedNodeIds.contains(node.id) {
                        state.selectNode(node.id, exclusive: true)
                    }
                }

                guard let startLoc = dragStartLocation else { return }
                let delta = CGSize(
                    width: (value.location.x - startLoc.x) / state.scale,
                    height: (value.location.y - startLoc.y) / state.scale
                )
                state.moveSelectedNodesFromSnapshot(by: delta)
            }
            .onEnded { _ in
                state.endNodeMove()
                state.isDragging = false
                draggedNodeId = nil
                dragStartLocation = nil
                // Reset cursor after dragging
                updateCursor(.default)

                // Snap to grid if enabled (shift temporarily disables)
                if theme.snapToGrid && !NSEvent.modifierFlags.contains(.shift) {
                    state.snapSelectedNodesToGrid(gridSize: theme.gridSnapSize)
                }
            }
    }

    // MARK: - Event Handlers

    public enum ArrowDirection {
        case up, down, left, right
    }

    private func handleArrowKey(direction: ArrowDirection) {
        // If a connection is selected, arrow keys cycle the routing preference
        if let connectionId = state.selectedConnectionId {
            // Left/Up = primary, Right/Down = secondary
            let newPreference: WFRoutingPreference
            switch direction {
            case .left, .up:
                newPreference = .primary
            case .right, .down:
                newPreference = .secondary
            }
            WFLogger.info("Setting routing preference to \(newPreference) for connection \(connectionId.uuidString.prefix(8))", category: .canvas)
            state.setSelectedConnectionRouting(newPreference)
            return
        }

        guard state.hasSelection else { return }

        let modifiers = NSEvent.modifierFlags

        let nudgeAmount: CGFloat
        if modifiers.contains(.shift) {
            nudgeAmount = 1
        } else if modifiers.contains(.command) {
            nudgeAmount = 100
        } else {
            nudgeAmount = 20
        }

        let delta: CGSize
        switch direction {
        case .up:
            delta = CGSize(width: 0, height: -nudgeAmount)
        case .down:
            delta = CGSize(width: 0, height: nudgeAmount)
        case .left:
            delta = CGSize(width: -nudgeAmount, height: 0)
        case .right:
            delta = CGSize(width: nudgeAmount, height: 0)
        }

        state.nudgeSelectedNodes(by: delta)
    }

    private func handleNodeTap(_ node: WorkflowNode) {
        let nodeRect = CGRect(origin: node.position, size: node.size)
        WFLogger.hitTest("✓ NODE TAP: \(node.title)", details: "id=\(node.id.uuidString.prefix(8)), type=\(node.type.rawValue), frame=\(Int(nodeRect.minX)),\(Int(nodeRect.minY)) \(Int(nodeRect.width))×\(Int(nodeRect.height))")

        if NSEvent.modifierFlags.contains(.command) {
            state.toggleNodeSelection(node.id)
        } else if NSEvent.modifierFlags.contains(.shift) {
            state.selectNode(node.id, exclusive: false)
        } else {
            state.selectNode(node.id, exclusive: true)
        }
    }

    private func completePendingConnection(to targetAnchor: ConnectionAnchor?) {
        defer {
            state.pendingConnection = nil
            state.validDropPortIds.removeAll()
        }

        guard let pending = state.pendingConnection,
              let target = targetAnchor else { return }

        let source = pending.sourceAnchor
        guard state.canConnect(from: source, to: target) else { return }

        let (outputAnchor, inputAnchor) = source.isInput ? (target, source) : (source, target)

        let connection = WorkflowConnection(
            sourceNodeId: outputAnchor.nodeId,
            sourcePortId: outputAnchor.portId,
            targetNodeId: inputAnchor.nodeId,
            targetPortId: inputAnchor.portId
        )

        state.addConnection(connection)
    }

    private func handleConnectionTap(_ connection: WorkflowConnection) {
        // Get source and target info for logging
        let sourceNode = state.nodes.first { $0.id == connection.sourceNodeId }
        let targetNode = state.nodes.first { $0.id == connection.targetNodeId }
        let sourceLabel = sourceNode?.title ?? "?"
        let targetLabel = targetNode?.title ?? "?"

        // Get positions
        let startPos = state.portPosition(nodeId: connection.sourceNodeId, portId: connection.sourcePortId) ?? .zero
        let endPos = state.portPosition(nodeId: connection.targetNodeId, portId: connection.targetPortId) ?? .zero

        WFLogger.hitTest("✓ CONNECTION TAP: \(sourceLabel) → \(targetLabel)",
            details: "id=\(connection.id.uuidString.prefix(8)), from=\(Int(startPos.x)),\(Int(startPos.y)) to=\(Int(endPos.x)),\(Int(endPos.y)), tolerance=40")

        state.selectConnection(connection.id)
    }

    // MARK: - Reconnection Handlers

    private func handleReconnectionUpdate(_ canvasPoint: CGPoint) {
        // Snap to valid ports
        let snapThreshold: CGFloat = 25
        var snappedPoint = canvasPoint
        var closestDistance: CGFloat = snapThreshold

        for portId in state.validDropPortIds {
            if let (_, portPos) = findPortPosition(portId: portId) {
                let distance = hypot(
                    canvasPoint.x - portPos.x,
                    canvasPoint.y - portPos.y
                )
                if distance < closestDistance {
                    closestDistance = distance
                    snappedPoint = portPos
                }
            }
        }

        state.pendingConnection?.currentPoint = snappedPoint

        // Update hovered port
        if closestDistance < snapThreshold {
            for portId in state.validDropPortIds {
                if let (_, portPos) = findPortPosition(portId: portId),
                   hypot(snappedPoint.x - portPos.x, snappedPoint.y - portPos.y) < 1 {
                    state.hoveredPortId = portId
                    break
                }
            }
        } else {
            state.hoveredPortId = nil
        }
    }

    private func handleReconnectionEnd(_ targetAnchor: ConnectionAnchor?) {
        state.completeReconnection(to: targetAnchor)
        state.hoveredConnectionId = nil
    }

    private func handleDelete() {
        // Disable delete in read-only mode
        guard !isReadOnly else { return }

        if let selectedConnectionId = state.selectedConnectionId {
            state.removeConnection(selectedConnectionId)
            state.deselectConnection()
        } else if !state.selectedNodeIds.isEmpty {
            state.removeSelectedNodes()
        }
    }

    // MARK: - Hit Test Debugging

    /// Handle background tap with logging of nearby objects
    private func handleBackgroundTap() {
        // Get mouse location from NSEvent
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else {
            WFLogger.hitTest("✗ BACKGROUND TAP (no window)")
            return
        }

        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = contentView.convert(mouseInWindow, from: nil)
        let flippedY = contentView.bounds.height - mouseInView.y

        // Convert to canvas coordinates
        let toolbarHeight: CGFloat = 34
        let canvasPoint = CGPoint(
            x: (mouseInView.x - state.offset.width) / state.scale,
            y: (flippedY - toolbarHeight - state.offset.height) / state.scale
        )

        // Calculate distances to all connections
        var connectionDistances: [(String, CGFloat)] = []
        for connection in state.connections {
            guard let startPos = state.portPosition(nodeId: connection.sourceNodeId, portId: connection.sourcePortId),
                  let endPos = state.portPosition(nodeId: connection.targetNodeId, portId: connection.targetPortId) else {
                continue
            }

            let sourceNode = state.nodes.first { $0.id == connection.sourceNodeId }
            let targetNode = state.nodes.first { $0.id == connection.targetNodeId }
            let label = "\(sourceNode?.title ?? "?") → \(targetNode?.title ?? "?")"

            // Calculate approximate distance to bezier curve
            let distance = approximateDistanceToBezier(point: canvasPoint, from: startPos, to: endPos)
            connectionDistances.append((label, distance))
        }

        // Sort by distance
        connectionDistances.sort { $0.1 < $1.1 }

        // Calculate distances to all nodes
        var nodeDistances: [(String, CGFloat)] = []
        for node in state.nodes {
            let nodeRect = CGRect(origin: node.position, size: node.size)
            let distance = distanceToRect(point: canvasPoint, rect: nodeRect)
            nodeDistances.append((node.title, distance))
        }
        nodeDistances.sort { $0.1 < $1.1 }

        // Build log message
        var details = "screenPos=\(Int(mouseInView.x)),\(Int(flippedY)) canvasPos=\(Int(canvasPoint.x)),\(Int(canvasPoint.y))"
        details += "\n   scale=\(String(format: "%.2f", state.scale)), offset=\(Int(state.offset.width)),\(Int(state.offset.height))"

        if !connectionDistances.isEmpty {
            details += "\n   Nearest connections:"
            for (label, dist) in connectionDistances.prefix(3) {
                let hitStatus = dist <= 40 ? "🎯" : "❌"
                details += "\n     \(hitStatus) \(label): \(Int(dist))px"
            }
        }

        if !nodeDistances.isEmpty {
            details += "\n   Nearest nodes:"
            for (label, dist) in nodeDistances.prefix(3) {
                let hitStatus = dist <= 0 ? "🎯" : "❌"
                details += "\n     \(hitStatus) \(label): \(Int(dist))px"
            }
        }

        WFLogger.hitTest("✗ BACKGROUND TAP (nothing hit)", details: details)
    }

    /// Calculate approximate distance from point to cubic bezier curve
    private func approximateDistanceToBezier(point: CGPoint, from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)

        // Calculate control points (same as ConnectionHitShape)
        let controlOffset: CGFloat
        if state.layoutMode == .vertical {
            if abs(dy) < 50 {
                controlOffset = max(abs(dx) * 0.3, 80)
            } else if abs(dx) < 50 {
                controlOffset = min(abs(dy) * 0.5, distance * 0.4)
            } else {
                controlOffset = min(max(abs(dy) * 0.4, 100), distance * 0.45)
            }
        } else {
            if abs(dx) < 50 {
                controlOffset = max(abs(dy) * 0.3, 80)
            } else if abs(dy) < 50 {
                controlOffset = min(abs(dx) * 0.5, distance * 0.4)
            } else {
                controlOffset = min(max(abs(dx) * 0.4, 100), distance * 0.45)
            }
        }

        // Sample points along bezier and find minimum distance
        var minDist: CGFloat = .greatestFiniteMagnitude
        let samples = 20

        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let bezierPoint: CGPoint

            if state.layoutMode == .vertical {
                let control1 = CGPoint(x: from.x, y: from.y + (dy >= 0 ? controlOffset : -controlOffset))
                let control2 = CGPoint(x: to.x, y: to.y - (dy >= 0 ? controlOffset : -controlOffset))
                bezierPoint = cubicBezier(t: t, p0: from, p1: control1, p2: control2, p3: to)
            } else {
                let control1 = CGPoint(x: from.x + controlOffset, y: from.y)
                let control2 = CGPoint(x: to.x - controlOffset, y: to.y)
                bezierPoint = cubicBezier(t: t, p0: from, p1: control1, p2: control2, p3: to)
            }

            let dist = hypot(point.x - bezierPoint.x, point.y - bezierPoint.y)
            minDist = min(minDist, dist)
        }

        return minDist
    }

    /// Cubic bezier interpolation
    private func cubicBezier(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
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

    /// Calculate distance from point to rectangle (0 if inside)
    private func distanceToRect(point: CGPoint, rect: CGRect) -> CGFloat {
        if rect.contains(point) {
            return 0
        }

        let closestX = max(rect.minX, min(point.x, rect.maxX))
        let closestY = max(rect.minY, min(point.y, rect.maxY))
        return hypot(point.x - closestX, point.y - closestY)
    }
}

// MARK: - Connection Hit Shape

struct ConnectionHitShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let tolerance: CGFloat
    var layoutMode: WFLayoutMode = .freeform

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)

        var controlOffset: CGFloat

        if layoutMode == .vertical {
            // Vertical bezier control points
            if abs(dy) < 50 {
                controlOffset = max(abs(dx) * 0.3, 80)
            } else if abs(dx) < 50 {
                controlOffset = min(abs(dy) * 0.5, distance * 0.4)
            } else {
                controlOffset = min(max(abs(dy) * 0.4, 100), distance * 0.45)
            }

            let control1: CGPoint
            let control2: CGPoint
            if dy >= 0 {
                control1 = CGPoint(x: from.x, y: from.y + controlOffset)
                control2 = CGPoint(x: to.x, y: to.y - controlOffset)
            } else {
                control1 = CGPoint(x: from.x, y: from.y - controlOffset)
                control2 = CGPoint(x: to.x, y: to.y + controlOffset)
            }

            path.move(to: from)
            path.addCurve(to: to, control1: control1, control2: control2)
        } else {
            // Horizontal bezier control points (freeform mode)
            if abs(dx) < 50 {
                controlOffset = max(abs(dy) * 0.3, 80)
            } else if abs(dy) < 50 {
                controlOffset = min(abs(dx) * 0.5, distance * 0.4)
            } else {
                controlOffset = min(max(abs(dx) * 0.4, 100), distance * 0.45)
            }

            let control1 = CGPoint(x: from.x + controlOffset, y: from.y)
            let control2 = CGPoint(x: to.x - controlOffset, y: to.y)

            path.move(to: from)
            path.addCurve(to: to, control1: control1, control2: control2)
        }

        return path.strokedPath(StrokeStyle(lineWidth: tolerance * 2, lineCap: .round))
    }
}

// MARK: - Canvas Background

struct CanvasBackground: View {
    let scale: CGFloat
    let offset: CGSize
    @Environment(\.wfTheme) private var theme

    private let gridSize: CGFloat = 20
    private let majorGridInterval: Int = 5
    private let parallaxFactor: CGFloat = 0.95

    var body: some View {
        ZStack {
            theme.canvasBackground

            Canvas { context, size in
                let parallaxOffset = CGSize(
                    width: offset.width * parallaxFactor,
                    height: offset.height * parallaxFactor
                )

                let scaledGridSize = gridSize * scale
                let startX = -parallaxOffset.width.truncatingRemainder(dividingBy: scaledGridSize)
                let startY = -parallaxOffset.height.truncatingRemainder(dividingBy: scaledGridSize)

                drawDotGrid(
                    context: context,
                    size: size,
                    startX: startX,
                    startY: startY,
                    gridSize: scaledGridSize
                )
            }
            .drawingGroup()
        }
    }

    private func drawDotGrid(
        context: GraphicsContext,
        size: CGSize,
        startX: CGFloat,
        startY: CGFloat,
        gridSize: CGFloat
    ) {
        let baseDotSize = theme.style.gridDotSize
        let minorDotRadius: CGFloat = baseDotSize * 0.67
        let majorDotRadius: CGFloat = baseDotSize
        let minorDotColor = theme.gridDot.opacity(0.45)
        let majorDotColor = theme.gridDot.opacity(0.5)
        let dotStyle = theme.style.gridDotStyle

        var row = 0
        var y = startY
        while y < size.height + gridSize {
            var col = 0
            var x = startX
            while x < size.width + gridSize {
                let isMajor = (row % majorGridInterval == 0) && (col % majorGridInterval == 0)
                let dotRadius = isMajor ? majorDotRadius : minorDotRadius
                let dotColor = isMajor ? majorDotColor : minorDotColor

                let dotPath: Path
                switch dotStyle {
                case .circle:
                    let dotRect = CGRect(
                        x: x - dotRadius,
                        y: y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    dotPath = Path(ellipseIn: dotRect)

                case .plus:
                    // Plus/crosshair style for technical theme
                    var path = Path()
                    let armLength = dotRadius * 1.2
                    // Horizontal arm
                    path.move(to: CGPoint(x: x - armLength, y: y))
                    path.addLine(to: CGPoint(x: x + armLength, y: y))
                    // Vertical arm
                    path.move(to: CGPoint(x: x, y: y - armLength))
                    path.addLine(to: CGPoint(x: x, y: y + armLength))
                    dotPath = path.strokedPath(StrokeStyle(lineWidth: 0.5, lineCap: .round))

                case .cross:
                    // X-shaped cross
                    var path = Path()
                    let armLength = dotRadius * 1.0
                    path.move(to: CGPoint(x: x - armLength, y: y - armLength))
                    path.addLine(to: CGPoint(x: x + armLength, y: y + armLength))
                    path.move(to: CGPoint(x: x + armLength, y: y - armLength))
                    path.addLine(to: CGPoint(x: x - armLength, y: y + armLength))
                    dotPath = path.strokedPath(StrokeStyle(lineWidth: 0.5, lineCap: .round))

                case .lines:
                    // Lines are drawn separately below, skip dot drawing
                    dotPath = Path()
                }

                context.fill(dotPath, with: .color(dotColor))

                x += gridSize
                col += 1
            }
            y += gridSize
            row += 1
        }

        // Draw line grid if style is .lines
        if dotStyle == .lines {
            drawLineGrid(context: context, size: size, startX: startX, startY: startY, gridSize: gridSize)
        }
    }

    private func drawLineGrid(
        context: GraphicsContext,
        size: CGSize,
        startX: CGFloat,
        startY: CGFloat,
        gridSize: CGFloat
    ) {
        let minorLineColor = theme.gridDot.opacity(0.15)
        let majorLineColor = theme.gridDot.opacity(0.25)
        let minorLineWidth: CGFloat = 0.5
        let majorLineWidth: CGFloat = 0.5

        // Draw vertical lines
        var col = 0
        var x = startX
        while x < size.width + gridSize {
            let isMajor = col % majorGridInterval == 0
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))

            context.stroke(
                path,
                with: .color(isMajor ? majorLineColor : minorLineColor),
                lineWidth: isMajor ? majorLineWidth : minorLineWidth
            )

            x += gridSize
            col += 1
        }

        // Draw horizontal lines
        var row = 0
        var y = startY
        while y < size.height + gridSize {
            let isMajor = row % majorGridInterval == 0
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))

            context.stroke(
                path,
                with: .color(isMajor ? majorLineColor : minorLineColor),
                lineWidth: isMajor ? majorLineWidth : minorLineWidth
            )

            y += gridSize
            row += 1
        }
    }
}

// MARK: - Canvas Keyboard Modifier

struct CanvasKeyboardModifier: ViewModifier {
    @Bindable var state: CanvasState
    let onDelete: () -> Void
    let onArrowKey: (WorkflowCanvas.ArrowDirection) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.delete) {
                onDelete()
                return .handled
            }
            .onKeyPress(.deleteForward) {
                onDelete()
                return .handled
            }
            .onKeyPress(.escape) {
                // Cancel connection mode if active, otherwise clear selection
                if state.isConnecting {
                    state.cancelPendingConnection()
                } else {
                    state.clearSelection()
                }
                return .handled
            }
            .onKeyPress(.tab) {
                handleTab()
                return .handled
            }
            .modifier(ArrowKeyModifier(onArrowKey: onArrowKey))
    }

    private func handleTab() {
        if NSEvent.modifierFlags.contains(.shift) {
            state.selectPreviousNode()
        } else {
            state.selectNextNode()
        }
    }
}

// MARK: - Arrow Key Modifier

struct ArrowKeyModifier: ViewModifier {
    let onArrowKey: (WorkflowCanvas.ArrowDirection) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow) {
                onArrowKey(.up)
                return .handled
            }
            .onKeyPress(.downArrow) {
                onArrowKey(.down)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                onArrowKey(.left)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                onArrowKey(.right)
                return .handled
            }
    }
}

