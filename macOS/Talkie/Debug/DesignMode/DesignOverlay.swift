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

// MARK: - Design Tools Wrapper (matches TalkieDebugToolbar pattern)

/// Wrapper for Design Tools with page-contextual design information
/// Usage: DesignToolsOverlay { customContent } designInfo: { ["Spacing": "8pt", ...] }
struct DesignToolsOverlay<CustomContent: View>: View {
    let designInfo: () -> [String: String]
    let customContent: CustomContent

    @State private var designMode = DesignModeManager.shared
    @State private var isExpanded = false
    @State private var overlayPosition: DesignOverlayPosition = .bottomTrailing

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
                // Grid overlay (when enabled)
                if designMode.showGrid {
                    Color.clear
                        .layoutGrid(
                            showGrid: true,
                            gridSpacing: 8,
                            opacity: 0.2
                        )
                        .allowsHitTesting(false)
                }

                // Spacing decorator (shows spacing between sections and elements)
                // TODO: Re-enable once SpacingDecoratorOverlay is added to Xcode project
                // if designMode.showSpacing {
                //     SpacingDecoratorOverlay()
                // }

                // Advanced layout tools (independent overlays)
                // TODO: Fix Swift compilation issue - tools not visible to DesignOverlay
                // if designMode.showCenterGuides {
                //     CenterGuidesOverlay()
                // }

                // if designMode.showEdgeGuides {
                //     EdgeGuidesOverlay()
                // }

                // if designMode.showElementBounds {
                //     ElementBoundsOverlay()
                // }

                // if designMode.pixelZoomLevel > 0 {
                //     PixelZoomOverlay(zoomLevel: designMode.pixelZoomLevel)
                // }

                // Active tool overlay
                // TODO: Fix tool visibility issue
                // if let activeTool = designMode.activeTool {
                //     toolOverlay(for: activeTool)
                // }

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
                .padding(Spacing.sm)
            }
        }
    }

    // TODO: Re-enable when tool visibility issue is fixed
    // @ViewBuilder
    // private func toolOverlay(for tool: DesignTool) -> some View {
    //     switch tool {
    //     case .ruler:
    //         RulerTool()
    //     case .colorPicker:
    //         ColorPickerTool()
    //     case .typography:
    //         TypographyInspectorTool()
    //     case .spacing:
    //         SpacingInspectorTool()
    //     }
    // }

    @ViewBuilder
    private var toolbarContent: some View {
        VStack(alignment: overlayPosition.horizontalAlignment, spacing: 8) {
            if isExpanded {
                controlsPanel
                    .transition(.scale(scale: 0.8, anchor: overlayPosition.scaleAnchor).combined(with: .opacity))
            }

            // Floating button
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "xmark.circle.fill" : "paintbrush.fill")
                        .font(.system(size: 14, weight: .semibold))

                    if !isExpanded {
                        Text("Design")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.cyan.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
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

            // Toggle controls
            toggleRow(
                icon: "grid",
                label: "8pt Grid",
                isOn: $designMode.showGrid
            )

            toggleRow(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                label: "Spacing",
                isOn: $designMode.showSpacing
            )

            toggleRow(
                icon: "textformat.size",
                label: "Typography",
                isOn: $designMode.showTypography
            )

            toggleRow(
                icon: "paintpalette",
                label: "Colors",
                isOn: $designMode.showColors
            )

            toggleRow(
                icon: "square.dashed",
                label: "Borders",
                isOn: $designMode.showBorders
            )

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)

            // Section: Advanced Layout Tools
            Text("Advanced Layout")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            toggleRow(
                icon: "plus.viewfinder",
                label: "Center Guides",
                isOn: $designMode.showCenterGuides
            )

            toggleRow(
                icon: "rectangle.inset.filled",
                label: "Edge Guides",
                isOn: $designMode.showEdgeGuides
            )

            toggleRow(
                icon: "viewfinder",
                label: "Element Bounds",
                isOn: $designMode.showElementBounds
            )

            // Pixel Zoom (multi-state)
            pixelZoomRow()

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
    private func pixelZoomRow() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(designMode.pixelZoomLevel > 0 ? .cyan : .white.opacity(0.5))
                .frame(width: 16)

            Text("Pixel Zoom")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            // Zoom level selector (Off, 2x, 4x)
            HStack(spacing: 4) {
                zoomButton(level: 0, label: "Off")
                zoomButton(level: 2, label: "2×")
                zoomButton(level: 4, label: "4×")
            }
        }
    }

    @ViewBuilder
    private func zoomButton(level: Int, label: String) -> some View {
        Button(action: { designMode.pixelZoomLevel = level }) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(designMode.pixelZoomLevel == level ? .black : .white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(designMode.pixelZoomLevel == level ? Color.cyan : Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
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
