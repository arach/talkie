//
//  DesignOverlay.swift
//  Talkie macOS
//
//  Design Tools overlay - Inspection tools and visual decorators
//  Appears when Design God Mode is enabled (⌘⇧D)
//
//  Pattern aligns with TalkieDebugToolbar for consistency:
//  - Pages provide designInfo: () -> [String: String] for contextual design data
//  - Pages provide custom content for page-specific design inspections
//  - Similar positioning/dismissal interactions as Debug Toolbar
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import DebugKit
import TalkieKit

#if DEBUG

// MARK: - Device Viewport Presets

/// Named device presets for responsive testing (Chrome DevTools style)
/// These match the ResponsiveSize values in DesignAuditor.swift
enum DevicePreset: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case standard = "Standard"
    case laptop = "Laptop"
    case expanded = "Expanded"

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .compact:  return CGSize(width: 800, height: 500)   // Minimum viable
        case .standard: return CGSize(width: 1000, height: 700)  // Typical window
        case .laptop:   return CGSize(width: 1280, height: 800)  // MacBook Air baseline
        case .expanded: return CGSize(width: 1400, height: 900)  // Large display
        }
    }

    var shortLabel: String {
        switch self {
        case .compact:  return "800×500"
        case .standard: return "1000×700"
        case .laptop:   return "1280×800"
        case .expanded: return "1400×900"
        }
    }

    var description: String {
        switch self {
        case .compact:  return "Minimum viable"
        case .standard: return "Typical window"
        case .laptop:   return "MacBook Air"
        case .expanded: return "Large display"
        }
    }
}

// MARK: - Design Tools Wrapper (matches TalkieDebugToolbar pattern)

/// Wrapper for Design Tools with page-contextual design information
/// Usage: DesignToolsOverlay { customContent } designInfo: { ["Spacing": "8pt", ...] }
struct DesignToolsOverlay<CustomContent: View>: View {
    let designInfo: () -> [String: String]
    let customContent: CustomContent

    // Use @Bindable for @Observable types when bindings are needed
    @Bindable private var designMode = DesignModeManager.shared
    @State private var isExpanded = false
    @State private var overlayPosition: DesignOverlayPosition = .bottomTrailing
    @State private var windowSize: CGSize = .zero
    @State private var contentSize: CGSize = .zero

    /// Initialize with custom content and optional design info
    init(
        @ViewBuilder content: @escaping () -> CustomContent,
        designInfo: @escaping () -> [String: String] = { [:] }
    ) {
        self.customContent = content()
        self.designInfo = designInfo
    }

    var body: some View {
        if designMode.isEnabled {
            ZStack {
                // Track content size via GeometryReader
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            contentSize = geometry.size
                            updateWindowSize()
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            contentSize = newSize
                            updateWindowSize()
                        }
                }
                .allowsHitTesting(false)

                // Grid overlay (when enabled) - uses configurable spacing
                if designMode.showGrid {
                    Color.clear
                        .layoutGrid(
                            showGrid: true,
                            gridSpacing: CGFloat(designMode.gridSpacing),
                            opacity: 0.3
                        )
                        .allowsHitTesting(false)
                }

                // Axis rulers (X/Y tick marks on edges)
                if designMode.showRulers {
                    AxisRulersOverlay(tickSpacing: designMode.gridSpacing)
                        .allowsHitTesting(false)
                }

                // Spacing decorator overlay (shows center guides + margin indicators)
                if designMode.showSpacing {
                    SpacingDecoratorOverlay()
                        .allowsHitTesting(false)
                }

                // Structural guides (interactive — draggable, creatable)
                if designMode.showGuides {
                    StructuralGuidesOverlay()
                }

                // Floating toolbar button
                VStack {
                    if overlayPosition.isTop {
                        Spacer()
                    }

                    HStack {
                        if overlayPosition.isTrailing {
                            Spacer()
                        }

                        toolbarContent

                        if !overlayPosition.isTrailing {
                            Spacer()
                        }
                    }

                    if !overlayPosition.isTop {
                        Spacer()
                    }
                }
                // Minimal padding at top to sit right against title bar, more on sides/bottom
                .padding(.top, 2)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.sm)

                // Measure tool (when active) - must be on top for hit testing
                if designMode.activeTool == .measure {
                    MeasureTool()
                        .zIndex(1000)  // Ensure it's on top
                }
            }
        }
    }


    // MARK: - Window Size Tracking

    private func updateWindowSize() {
        if let window = NSApplication.shared.mainWindow {
            windowSize = window.frame.size
        }
    }

    private func copyDimensionsToClipboard() {
        let text = "Window: \(Int(windowSize.width))×\(Int(windowSize.height)) | Content: \(Int(contentSize.width))×\(Int(contentSize.height))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    private var toolbarContent: some View {
        VStack(alignment: overlayPosition.horizontalAlignment, spacing: 8) {
            if isExpanded {
                controlsPanel
                    .transition(.scale(scale: 0.8, anchor: overlayPosition.scaleAnchor).combined(with: .opacity))
            }

            // Floating button - compact circle when collapsed
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                Image(systemName: isExpanded ? "xmark" : "paintbrush.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.cyan.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .onTapGesture(count: 2) {
                // Double-click to cycle position
                withAnimation(.spring(response: 0.3)) {
                    overlayPosition = overlayPosition.next
                }
            }
        }
    }

    @ViewBuilder
    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Design Tools")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Position indicator
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        overlayPosition = overlayPosition.next
                    }
                }) {
                    Image(systemName: overlayPosition.icon)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Section: Window Info (dimensions)
            windowInfoSection

            Divider()
                .background(Color.white.opacity(0.2))

            // Section: Inspection Tools
            Text("Inspection Tools")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 4)

            ForEach(DesignTool.allCases, id: \.self) { tool in
                toolToggleRow(tool: tool)
            }

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)

            // Section: Visual Decorators
            Text("Visual Decorators")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            // Grid with spacing selector
            gridToggleRow()

            toggleRow(
                icon: "ruler",
                label: "Rulers",
                isOn: $designMode.showRulers
            )

            toggleRow(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                label: "Spacing",
                isOn: $designMode.showSpacing
            )

            toggleRow(
                icon: "square.dashed",
                label: "Borders",
                isOn: $designMode.showBorders
            )

            toggleRow(
                icon: "line.horizontal.3",
                label: "Guides",
                isOn: $designMode.showGuides
            )

            // Quick-add guide buttons (when guides visible)
            if designMode.showGuides {
                HStack(spacing: 4) {
                    Button(action: { designMode.addGuide(axis: .horizontal, position: 100) }) {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 7, weight: .bold))
                            Text("H")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Add horizontal guide")

                    Button(action: { designMode.addGuide(axis: .vertical, position: 100) }) {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 7, weight: .bold))
                            Text("V")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Add vertical guide")

                    Spacer()

                    if designMode.layoutGuides.contains(where: { !$0.isBuiltIn }) {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(designMode.guidesSummary, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Copy guide positions")
                    }
                }
                .padding(.leading, 4)
            }

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)

            // Section: TalkieText Inspector
            TalkieTextInspectorPanel()

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)

            // Section: List Tuning
            listTuningSection

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)

            // Section: Tooltip Tuning
            tooltipTuningSection

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)

            // Section: Liquid Glass Tuning
            liquidGlassSection

            Divider()
                .background(Color.white.opacity(0.2))

            // Quick actions
            HStack(spacing: 6) {
                Button(action: { designMode.toggleAllDecorators() }) {
                    Text(designMode.hasActiveDecorators ? "All Off" : "All On")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { designMode.resetDecorators() }) {
                    Text("Reset")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Page Design Context (if provided)
            let info = designInfo()
            if !info.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 4)

                Text("PAGE CONTEXT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(info.keys.sorted(), id: \.self) { key in
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(info[key] ?? "-")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }

            // Custom page content (if provided)
            if CustomContent.self != EmptyView.self {
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 4)

                customContent
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
        .frame(width: 200)
    }

    @ViewBuilder
    private func toolToggleRow(tool: DesignTool) -> some View {
        Button(action: {
            // Toggle tool - if already active, deactivate; otherwise activate
            if designMode.activeTool == tool {
                designMode.activeTool = nil
            } else {
                designMode.activeTool = tool
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: tool.icon)
                    .font(.system(size: 12))
                    .foregroundColor(designMode.activeTool == tool ? .cyan : .white.opacity(0.5))
                    .frame(width: 16)

                Text(tool.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Active indicator (circle instead of toggle)
                Circle()
                    .fill(designMode.activeTool == tool ? Color.cyan : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isOn.wrappedValue ? .cyan : .white.opacity(0.5))
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Toggle indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn.wrappedValue ? Color.cyan : Color.white.opacity(0.2))
                        .frame(width: 32, height: 18)

                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .offset(x: isOn.wrappedValue ? 7 : -7)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gridToggleRow() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main toggle row - entire row is clickable
            Button(action: { designMode.showGrid.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "grid")
                        .font(.system(size: 12))
                        .foregroundColor(designMode.showGrid ? .cyan : .white.opacity(0.5))
                        .frame(width: 16)

                    Text("Grid")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    if !designMode.showGrid {
                        // Toggle indicator when off
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 32, height: 18)

                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .offset(x: -7)
                        }
                    } else {
                        // Toggle indicator when on
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.cyan)
                                .frame(width: 32, height: 18)

                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .offset(x: 7)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            // Spacing selector (only show when grid is on)
            if designMode.showGrid {
                HStack(spacing: 3) {
                    ForEach(DesignModeManager.gridPresets, id: \.self) { spacing in
                        Button(action: { designMode.gridSpacing = spacing }) {
                            Text("\(spacing)")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(designMode.gridSpacing == spacing ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(designMode.gridSpacing == spacing ? Color.cyan : Color.white.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Window Info Section

    @State private var screenshotFlash = false

    @ViewBuilder
    private var windowInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)

                Text("Window Info")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                // Screenshot button
                Button(action: {
                    screenshotFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        screenshotFlash = false
                        _ = designMode.captureScreenshot()
                    }
                }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 9))
                        .foregroundColor(screenshotFlash ? .cyan : .white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Screenshot (⌘⇧⌥D)")

                // Copy dimensions button
                Button(action: copyDimensionsToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Copy dimensions to clipboard")
            }

            // Window dimensions
            HStack(spacing: 4) {
                Text("Window")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(Int(windowSize.width)) × \(Int(windowSize.height))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            // Content area dimensions
            HStack(spacing: 4) {
                Text("Content")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(Int(contentSize.width)) × \(Int(contentSize.height))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.green)
            }

            // Breakpoint indicators
            HStack(spacing: 4) {
                Text("Layout")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(layoutBreakpointLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(layoutBreakpointColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(layoutBreakpointColor.opacity(0.2))
                    )
            }

            // Device preset buttons
            viewportPresetsRow
        }
    }

    // MARK: - Viewport Presets

    @ViewBuilder
    private var viewportPresetsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quick Resize")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.4))

            HStack(spacing: 3) {
                ForEach(DevicePreset.allCases) { preset in
                    viewportPresetButton(preset)
                }
            }
        }
        .padding(.top, 4)
    }

    private func viewportPresetButton(_ preset: DevicePreset) -> some View {
        let isActive = abs(windowSize.width - preset.size.width) < 10 &&
                       abs(windowSize.height - preset.size.height) < 10

        return Button(action: { applyViewportPreset(preset) }) {
            VStack(spacing: 1) {
                Text(preset.shortLabel)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                Text(preset.rawValue)
                    .font(.system(size: 6))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.cyan.opacity(0.3) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isActive ? Color.cyan : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(preset.rawValue): \(preset.description)")
    }

    private func applyViewportPreset(_ preset: DevicePreset) {
        guard let window = NSApp.mainWindow else { return }

        var frame = window.frame
        let newSize = preset.size

        // Keep the window's top-left corner in place
        frame.origin.y = frame.origin.y + frame.size.height - newSize.height
        frame.size = newSize

        window.setFrame(frame, display: true, animate: true)

        // Refresh after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            updateWindowSize()
        }
    }

    private var layoutBreakpointLabel: String {
        let width = contentSize.width
        if width < 600 { return "COMPACT" }
        if width < 800 { return "REGULAR" }
        if width < 1000 { return "WIDE" }
        return "EXPANDED"
    }

    private var layoutBreakpointColor: Color {
        let width = contentSize.width
        if width < 600 { return .orange }
        if width < 800 { return .yellow }
        if width < 1000 { return .green }
        return .cyan
    }

    // MARK: - List Tuning Section

    @ViewBuilder
    private var listTuningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with enable toggle
            HStack {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10))
                    .foregroundColor(designMode.listTuningEnabled ? .cyan : .white.opacity(0.5))

                Text("List Tuning")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Button(action: { designMode.listTuningEnabled.toggle() }) {
                    Text(designMode.listTuningEnabled ? "ON" : "OFF")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(designMode.listTuningEnabled ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(designMode.listTuningEnabled ? Color.cyan : Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            if designMode.listTuningEnabled {
                // Row padding
                glassSlider(label: "H Padding", value: cgFloatBinding($designMode.listHorizontalPadding), range: 0...24, format: "%.0fpt", multiplier: 1)
                glassSlider(label: "V Padding", value: cgFloatBinding($designMode.listVerticalPadding), range: 0...20, format: "%.0fpt", multiplier: 1)

                // Spacing between slots
                glassSlider(label: "Lead Gap", value: cgFloatBinding($designMode.listLeadingSpacing), range: 0...24, format: "%.0fpt", multiplier: 1)
                glassSlider(label: "Trail Gap", value: cgFloatBinding($designMode.listTrailingSpacing), range: 0...24, format: "%.0fpt", multiplier: 1)

                // Icon
                glassSlider(label: "Icon Size", value: cgFloatBinding($designMode.listIconSize), range: 24...56, format: "%.0fpt", multiplier: 1)
                glassSlider(label: "Icon Radius", value: cgFloatBinding($designMode.listIconCornerRadius), range: 0...28, format: "%.0fpt", multiplier: 1)
                glassSlider(label: "Icon Border", value: cgFloatBinding($designMode.listIconBorderWidth), range: 0...3, format: "%.1fpt", multiplier: 1)
                glassSlider(label: "Border Op.", value: $designMode.listIconBorderOpacity, range: 0...1, format: "%.0f%%", multiplier: 100)

                // Copy + Reset buttons
                HStack(spacing: 4) {
                    Button(action: { copyListTuningValues() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 7))
                            Text("Copy")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.cyan.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: { designMode.resetListTuning() }) {
                        Text("Reset")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func copyListTuningValues() {
        let dm = designMode
        let text = """
        List Tuning Values:
        H Padding: \(Int(dm.listHorizontalPadding))pt
        V Padding: \(Int(dm.listVerticalPadding))pt
        Lead Gap: \(Int(dm.listLeadingSpacing))pt
        Trail Gap: \(Int(dm.listTrailingSpacing))pt
        Icon Size: \(Int(dm.listIconSize))pt
        Icon Radius: \(Int(dm.listIconCornerRadius))pt
        Icon Border: \(String(format: "%.1f", dm.listIconBorderWidth))pt
        Border Opacity: \(Int(dm.listIconBorderOpacity * 100))%
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Tooltip Tuning Section

    @ViewBuilder
    private var tooltipTuningSection: some View {
        let tune = TooltipTuning.shared
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.bubble")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)

                Text("Tooltip Tuning")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()
            }

            glassSlider(label: "Offset", value: Binding(get: { Double(tune.offsetDistance) }, set: { tune.offsetDistance = CGFloat($0) }), range: 0...20, format: "%.0fpt", multiplier: 1)
            glassSlider(label: "Font", value: Binding(get: { Double(tune.fontSize) }, set: { tune.fontSize = CGFloat($0) }), range: 8...16, format: "%.0fpt", multiplier: 1)
            glassSlider(label: "H Pad", value: Binding(get: { Double(tune.horizontalPadding) }, set: { tune.horizontalPadding = CGFloat($0) }), range: 2...20, format: "%.0fpt", multiplier: 1)
            glassSlider(label: "V Pad", value: Binding(get: { Double(tune.verticalPadding) }, set: { tune.verticalPadding = CGFloat($0) }), range: 1...12, format: "%.0fpt", multiplier: 1)
            glassSlider(label: "Radius", value: Binding(get: { Double(tune.cornerRadius) }, set: { tune.cornerRadius = CGFloat($0) }), range: 0...16, format: "%.0fpt", multiplier: 1)
            glassSlider(label: "Shadow R", value: Binding(get: { Double(tune.shadowRadius) }, set: { tune.shadowRadius = CGFloat($0) }), range: 0...20, format: "%.0f", multiplier: 1)
            glassSlider(label: "Shadow α", value: Binding(get: { Double(tune.shadowOpacity) }, set: { tune.shadowOpacity = CGFloat($0) }), range: 0...1, format: "%.0f%%", multiplier: 100)
            glassSlider(label: "Arrow", value: Binding(get: { Double(tune.arrowSize) }, set: { tune.arrowSize = CGFloat($0) }), range: 0...12, format: "%.0fpt", multiplier: 1)
        }
    }

    // MARK: - Liquid Glass Tuning Section

    /// Sync DesignModeManager values to TalkieKit's GlassTuning
    private func syncGlassTuning() {
        let tuning = GlassTuning.shared
        tuning.isEnabled = designMode.glassOverrideEnabled
        tuning.materialOpacity = designMode.glassMaterialOpacity
        tuning.blurMultiplier = designMode.glassBlurMultiplier
        tuning.highlightOpacity = designMode.glassHighlightOpacity
        tuning.borderOpacity = designMode.glassBorderOpacity
        tuning.innerGlowRadius = designMode.glassInnerGlowRadius
        tuning.tintIntensity = designMode.glassTintIntensity
    }

    @ViewBuilder
    private var liquidGlassSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with enable toggle
            HStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 10))
                    .foregroundColor(designMode.glassOverrideEnabled ? .cyan : .white.opacity(0.5))

                Text("Liquid Glass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                // Enable toggle
                Button(action: {
                    designMode.glassOverrideEnabled.toggle()
                    syncGlassTuning()
                }) {
                    Text(designMode.glassOverrideEnabled ? "ON" : "OFF")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(designMode.glassOverrideEnabled ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(designMode.glassOverrideEnabled ? Color.cyan : Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            if designMode.glassOverrideEnabled {
                // Transparency slider
                glassSlider(
                    label: "Transparency",
                    value: Binding(
                        get: { 1.0 - designMode.glassMaterialOpacity },
                        set: { designMode.glassMaterialOpacity = 1.0 - $0 }
                    ),
                    range: 0...1,
                    format: "%.0f%%",
                    multiplier: 100
                )

                // Blur slider
                glassSlider(
                    label: "Blur",
                    value: $designMode.glassBlurMultiplier,
                    range: 0...3,
                    format: "%.1fx",
                    multiplier: 1
                )

                // Highlight opacity slider
                glassSlider(
                    label: "Highlight",
                    value: $designMode.glassHighlightOpacity,
                    range: 0...1,
                    format: "%.0f%%",
                    multiplier: 100
                )

                // Border glow slider
                glassSlider(
                    label: "Border Glow",
                    value: $designMode.glassBorderOpacity,
                    range: 0...1,
                    format: "%.0f%%",
                    multiplier: 100
                )

                // Inner glow slider
                glassSlider(
                    label: "Inner Glow",
                    value: Binding(
                        get: { Double(designMode.glassInnerGlowRadius) },
                        set: { designMode.glassInnerGlowRadius = CGFloat($0) }
                    ),
                    range: 0...20,
                    format: "%.0fpt",
                    multiplier: 1
                )

                // Tint intensity slider
                glassSlider(
                    label: "Tint",
                    value: $designMode.glassTintIntensity,
                    range: 0...1,
                    format: "%.0f%%",
                    multiplier: 100
                )

                // Preset buttons
                HStack(spacing: 4) {
                    glassPresetButton(label: "Subtle") {
                        designMode.applySubtleGlass()
                        syncGlassTuning()
                    }
                    glassPresetButton(label: "Default") {
                        designMode.resetGlassTuning()
                        syncGlassTuning()
                    }
                    glassPresetButton(label: "MAX") {
                        designMode.applyMaxGlass()
                        syncGlassTuning()
                    }
                }
                .padding(.top, 4)
            }
        }
        // Sync to GlassTuning whenever any value changes
        .onChange(of: designMode.glassMaterialOpacity) { _, _ in syncGlassTuning() }
        .onChange(of: designMode.glassBlurMultiplier) { _, _ in syncGlassTuning() }
        .onChange(of: designMode.glassHighlightOpacity) { _, _ in syncGlassTuning() }
        .onChange(of: designMode.glassBorderOpacity) { _, _ in syncGlassTuning() }
        .onChange(of: designMode.glassInnerGlowRadius) { _, _ in syncGlassTuning() }
        .onChange(of: designMode.glassTintIntensity) { _, _ in syncGlassTuning() }
    }

    @ViewBuilder
    private func glassSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        multiplier: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text(String(format: format, value.wrappedValue * multiplier))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
                    .frame(width: 40, alignment: .trailing)
            }

            // Custom slider track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    // Filled portion
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.cyan)
                        .frame(
                            width: geo.size.width * CGFloat((value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound)),
                            height: 4
                        )

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: geo.size.width * CGFloat((value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound)) - 5)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let percent = max(0, min(1, gesture.location.x / geo.size.width))
                            value.wrappedValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(percent)
                        }
                )
            }
            .frame(height: 10)
        }
    }

    /// Bridge CGFloat ↔ Double for slider bindings
    private func cgFloatBinding(_ binding: Binding<CGFloat>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(binding.wrappedValue) },
            set: { binding.wrappedValue = CGFloat($0) }
        )
    }

    @ViewBuilder
    private func glassPresetButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overlay Position

enum DesignOverlayPosition {
    case bottomTrailing
    case bottomLeading
    case topTrailing
    case topLeading

    var isTop: Bool {
        self == .topTrailing || self == .topLeading
    }

    var isTrailing: Bool {
        self == .bottomTrailing || self == .topTrailing
    }

    var horizontalAlignment: HorizontalAlignment {
        isTrailing ? .trailing : .leading
    }

    var scaleAnchor: UnitPoint {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        case .topTrailing: return .topTrailing
        case .topLeading: return .topLeading
        }
    }

    var icon: String {
        switch self {
        case .bottomTrailing: return "arrow.down.right"
        case .bottomLeading: return "arrow.down.left"
        case .topTrailing: return "arrow.up.right"
        case .topLeading: return "arrow.up.left"
        }
    }

    var next: DesignOverlayPosition {
        switch self {
        case .bottomTrailing: return .bottomLeading
        case .bottomLeading: return .topLeading
        case .topLeading: return .topTrailing
        case .topTrailing: return .bottomTrailing
        }
    }
}

// MARK: - Convenience Extensions

extension DesignToolsOverlay where CustomContent == EmptyView {
    /// Convenience init with no custom content (system-only tools)
    init() {
        self.init(content: { EmptyView() }, designInfo: { [:] })
    }
}

/// Typealias for consistency with TalkieDebugToolbar pattern
typealias DesignOverlay = DesignToolsOverlay<EmptyView>

#Preview("Design Overlay") {
    ZStack {
        Color.gray.opacity(0.1)

        DesignOverlay()
    }
    .frame(width: 800, height: 600)
    .onAppear {
        DesignModeManager.shared.isEnabled = true
    }
}

#endif
