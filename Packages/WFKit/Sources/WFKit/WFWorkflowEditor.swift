import SwiftUI
import AppKit
import DebugKit

// MARK: - Read-Only Environment Key

private struct WFReadOnlyKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var wfReadOnly: Bool {
        get { self[WFReadOnlyKey.self] }
        set { self[WFReadOnlyKey.self] = newValue }
    }
}

// MARK: - Inspector Style

/// Controls how the inspector is displayed in WFWorkflowEditor
public enum WFInspectorStyle {
    /// Uses SwiftUI's .inspector() modifier - requires WindowGroup context
    case system
    /// Uses HStack layout - works in modals, sheets, and panels
    case inline
    /// No inspector
    case none
}

// MARK: - WFWorkflowEditor

/// The main workflow editor component.
/// Drop this into your app to get a complete node-based workflow editor.
///
/// Usage:
/// ```swift
/// @State private var canvasState = CanvasState()
///
/// // Editable mode (default)
/// WFWorkflowEditor(state: canvasState)
///
/// // Read-only mode (for visualization only)
/// WFWorkflowEditor(state: canvasState, isReadOnly: true)
///
/// // With schema (for structured field display)
/// WFWorkflowEditor(state: canvasState, schema: MyAppSchema())
///
/// // In a modal/sheet context (use inline inspector)
/// WFWorkflowEditor(state: canvasState, inspectorStyle: .inline)
/// ```
public struct WFWorkflowEditor: View {
    @Bindable var state: CanvasState
    let isReadOnly: Bool
    let schema: (any WFSchemaProvider)?
    let inspectorStyle: WFInspectorStyle
    @Binding var showInspector: Bool
    @Environment(\.wfTheme) private var theme

    #if DEBUG
    @State private var showDebugToolbar: Bool = true
    @State private var isCapturingSnapshot: Bool = false
    @State private var debugReadOnly: Bool = false
    #endif

    public init(
        state: CanvasState,
        schema: (any WFSchemaProvider)? = nil,
        isReadOnly: Bool = false,
        inspectorStyle: WFInspectorStyle = .system,
        showInspector: Binding<Bool> = .constant(true)
    ) {
        self.state = state
        self.schema = schema
        self.isReadOnly = isReadOnly
        self.inspectorStyle = inspectorStyle
        self._showInspector = showInspector
    }

    public var body: some View {
        ZStack {
            Group {
                switch inspectorStyle {
                case .system:
                    systemInspectorLayout
                case .inline:
                    inlineInspectorLayout
                case .none:
                    canvasOnly
                }
            }
            #if DEBUG
            .environment(\.wfReadOnly, isReadOnly || debugReadOnly)
            #else
            .environment(\.wfReadOnly, isReadOnly)
            #endif
            .environment(\.wfSchema, schema)
            .environment(\.wfLayoutMode, state.layoutMode)
            .onChange(of: state.selectedNodeIds) { _, newSelection in
                // Auto-show inspector when a node is selected
                if !newSelection.isEmpty && !showInspector && inspectorStyle != .none {
                    showInspector = true
                }
            }

            #if DEBUG
            // Debug toolbar overlay - positioned at bottom-right of entire window
            if showDebugToolbar && !isCapturingSnapshot {
                debugToolbar
                    .padding(.bottom, statusBarHeight) // Account for status bar
            }
            #endif

            // Status bar overlay at bottom
            statusBar
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack {
            Spacer()
            HStack {
                // Node and connection counts
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Nodes:")
                            .foregroundColor(theme.textTertiary)
                        Text("\(state.nodes.count)")
                            .foregroundColor(theme.textSecondary)
                    }

                    HStack(spacing: 6) {
                        Text("Connections:")
                            .foregroundColor(theme.textTertiary)
                        Text("\(state.connections.count)")
                            .foregroundColor(theme.textSecondary)
                    }
                }

                Spacer()

                // Ready status
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Ready")
                        .foregroundColor(theme.textSecondary)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.panelBackground.opacity(0.95))
            .overlay(
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1),
                alignment: .top
            )
        }
    }

    // MARK: - Debug Toolbar

    #if DEBUG
    private var debugToolbar: some View {
        let counterScale = min(max(1.0 / state.scale, 0.6), 1.4)

        let effectiveReadOnly = isReadOnly || debugReadOnly

        var sections: [DebugSection] = [
            DebugSection("CANVAS", [
                ("Zoom", String(format: "%.0f%%", state.scale * 100)),
                ("Counter Scale", String(format: "%.2f", counterScale)),
                ("Offset", "(\(Int(state.offset.width)), \(Int(state.offset.height)))"),
                ("Nodes", "\(state.nodes.count)"),
                ("Connections", "\(state.connections.count)"),
                ("Selected", "\(state.selectedNodeIds.count)"),
                ("Layout", state.layoutMode.displayName),
                ("Line Width", String(format: "%.1f", theme.connectionLineWidth)),
                ("Read-Only", effectiveReadOnly ? "ON" : "off")
            ])
        ]

        // Add selected node info when single node is selected
        if state.selectedNodeIds.count == 1,
           let nodeId = state.selectedNodeIds.first,
           let node = state.nodes.first(where: { $0.id == nodeId }) {
            sections.append(DebugSection("SELECTED NODE", [
                ("Title", node.title),
                ("Type", node.type.rawValue),
                ("Position", "(\(Int(node.position.x)), \(Int(node.position.y)))"),
                ("Size", "\(Int(node.size.width))x\(Int(node.size.height))"),
                ("Inputs", "\(node.inputs.count)"),
                ("Outputs", "\(node.outputs.count)")
            ]))
        }

        return DebugToolbar(
            sections: sections,
            actions: [
                DebugAction(debugReadOnly ? "Exit Read-Only" : "Read-Only Mode", icon: debugReadOnly ? "pencil" : "eye") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        debugReadOnly.toggle()
                    }
                },
                DebugAction(
                    state.layoutMode == .freeform ? "Vertical Layout" : "Freeform Layout",
                    icon: state.layoutMode == .freeform ? "arrow.down.to.line" : "rectangle.3.group"
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        let newMode: WFLayoutMode = state.layoutMode == .freeform ? .vertical : .freeform
                        state.setLayoutMode(newMode, autoLayout: true)
                    }
                },
                DebugAction("Capture Snapshot", icon: "camera.fill") {
                    captureSnapshot()
                },
                DebugAction("Reset Zoom", icon: "arrow.up.left.and.arrow.down.right") {
                    withAnimation(.spring(response: 0.3)) {
                        state.scale = 1.0
                        state.offset = .zero
                    }
                },
                DebugAction("Fit to Content", icon: "arrow.down.forward.and.arrow.up.backward") {
                    fitToContent()
                },
                // Connection style quick switches
                DebugAction("Bezier", icon: WFConnectionStyle.bezier.icon) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        theme.connectionStyleOverride = .bezier
                    }
                },
                DebugAction("Straight", icon: WFConnectionStyle.straight.icon) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        theme.connectionStyleOverride = .straight
                    }
                },
                DebugAction("Step", icon: WFConnectionStyle.step.icon) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        theme.connectionStyleOverride = .step
                    }
                },
                DebugAction("Smooth", icon: WFConnectionStyle.smoothStep.icon) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        theme.connectionStyleOverride = .smoothStep
                    }
                },
                // Line thickness controls
                DebugAction("Line −", icon: "minus") {
                    theme.connectionLineWidth = max(1.0, theme.connectionLineWidth - 0.5)
                },
                DebugAction("Line +", icon: "plus") {
                    theme.connectionLineWidth = min(6.0, theme.connectionLineWidth + 0.5)
                }
            ],
            onCopy: { buildDebugCopyText() }
        ) {
            EmptyView()
        }
    }

    private func captureSnapshot() {
        // Hide debug toolbar before capture
        isCapturingSnapshot = true

        // Wait for next render cycle, then capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.performSnapshotCapture()
            self.isCapturingSnapshot = false
        }
    }

    private func performSnapshotCapture() {
        // Create snapshots directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let snapshotsDir = documentsPath.appendingPathComponent("WFKit-Snapshots")

        do {
            try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        } catch {
            WFLogger.error("Failed to create snapshots directory: \(error)", category: .canvas)
            return
        }

        // Generate timestamp for filenames
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let baseName = "snapshot_\(timestamp)"

        // Save JSON state
        if let json = state.exportJSON() {
            let jsonPath = snapshotsDir.appendingPathComponent("\(baseName).json")
            do {
                try json.write(to: jsonPath, atomically: true, encoding: .utf8)
                WFLogger.info("Saved JSON to \(jsonPath.lastPathComponent)", category: .canvas)
            } catch {
                WFLogger.error("Failed to save JSON: \(error)", category: .canvas)
            }
        }

        // Capture window screenshot (shows exactly what's on screen, minus debug toolbar)
        if let window = NSApp.keyWindow {
            let windowId = CGWindowID(window.windowNumber)
            if let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowId,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                if let tiffData = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                    let pngPath = snapshotsDir.appendingPathComponent("\(baseName).png")
                    do {
                        try pngData.write(to: pngPath)
                        WFLogger.info("Saved PNG to \(pngPath.lastPathComponent)", category: .canvas)
                    } catch {
                        WFLogger.error("Failed to save PNG: \(error)", category: .canvas)
                    }
                }
            }
        }

        // Open folder in Finder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: snapshotsDir.path)
    }

    private func fitToContent() {
        guard !state.nodes.isEmpty else { return }

        let minX = state.nodes.map { $0.position.x }.min() ?? 0
        let maxX = state.nodes.map { $0.position.x + $0.size.width }.max() ?? 0
        let minY = state.nodes.map { $0.position.y }.min() ?? 0
        let maxY = state.nodes.map { $0.position.y + $0.size.height }.max() ?? 0

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        withAnimation(.spring(response: 0.4)) {
            state.scale = 0.8
            state.offset = CGSize(
                width: -centerX * state.scale + 400,
                height: -centerY * state.scale + 300
            )
        }
    }

    private func buildDebugCopyText() -> String {
        var lines: [String] = []

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        lines.append("WFKit \(appVersion) (\(buildNumber))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")

        lines.append("Canvas State:")
        lines.append("  Zoom: \(String(format: "%.0f%%", state.scale * 100))")
        lines.append("  Offset: (\(Int(state.offset.width)), \(Int(state.offset.height)))")
        lines.append("  Nodes: \(state.nodes.count)")
        lines.append("  Connections: \(state.connections.count)")
        lines.append("  Selected: \(state.selectedNodeIds.count)")
        lines.append("")

        if state.selectedNodeIds.count == 1,
           let nodeId = state.selectedNodeIds.first,
           let node = state.nodes.first(where: { $0.id == nodeId }) {
            lines.append("Selected Node:")
            lines.append("  Title: \(node.title)")
            lines.append("  Type: \(node.type.rawValue)")
            lines.append("  Position: (\(Int(node.position.x)), \(Int(node.position.y)))")
            lines.append("  Size: \(Int(node.size.width))x\(Int(node.size.height))")
            lines.append("")
        }

        lines.append("All Nodes:")
        for node in state.nodes {
            lines.append("  [\(node.type.rawValue)] \(node.title) @ (\(Int(node.position.x)), \(Int(node.position.y)))")
        }

        return lines.joined(separator: "\n")
    }

    func toggleDebugToolbar() {
        showDebugToolbar.toggle()
    }
    #endif

    // MARK: - Layout Variants

    /// Height of the status bar at the bottom
    private let statusBarHeight: CGFloat = 30

    /// Canvas with system .inspector() modifier - requires WindowGroup
    @ViewBuilder
    private var systemInspectorLayout: some View {
        WorkflowCanvas(state: state)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: statusBarHeight)
            }
            .inspector(isPresented: $showInspector) {
                InspectorView(state: state, isVisible: $showInspector)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
            }
    }

    /// Canvas with inline HStack inspector - works in modals/sheets
    @ViewBuilder
    private var inlineInspectorLayout: some View {
        HStack(spacing: 0) {
            WorkflowCanvas(state: state)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: statusBarHeight)
                }

            if showInspector {
                Rectangle()
                    .fill(theme.divider)
                    .frame(width: 1)

                InspectorView(state: state, isVisible: $showInspector)
                    .frame(width: 320)
            }
        }
    }

    /// Canvas only, no inspector
    @ViewBuilder
    private var canvasOnly: some View {
        WorkflowCanvas(state: state)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: statusBarHeight)
            }
    }
}

// MARK: - Preview

#Preview("WFWorkflowEditor - System Inspector") {
    WFWorkflowEditor(state: CanvasState.sampleState(), inspectorStyle: .system)
        .frame(width: 1200, height: 800)
        .environment(WFThemeManager())
}

#Preview("WFWorkflowEditor - Inline Inspector") {
    WFWorkflowEditor(state: CanvasState.sampleState(), inspectorStyle: .inline)
        .frame(width: 1200, height: 800)
        .environment(WFThemeManager())
}
