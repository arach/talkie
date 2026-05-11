//
//  DesignModeManager.swift
//  Talkie macOS
//
//  Design God Mode - State management for design debugging tools
//  Activated via ⌘⇧D keyboard shortcut
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Available design inspection tools (only implemented ones)
enum DesignTool: String, CaseIterable, Hashable {
    case measure = "Measure"

    var icon: String {
        switch self {
        case .measure: return "arrow.left.and.line.vertical.and.arrow.right"
        }
    }
}

// MARK: - Guide Color Palette

/// Named colors for guides — easily distinguishable, Codable-friendly.
enum GuideColor: String, Codable, CaseIterable, Identifiable {
    case cyan, orange, green, purple, red, yellow, pink, blue

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .cyan:   .cyan
        case .orange: .orange
        case .green:  .green
        case .purple: .purple
        case .red:    .red
        case .yellow: .yellow
        case .pink:   .pink
        case .blue:   .blue
        }
    }
}

// MARK: - Layout Guide Model

/// A draggable guide line — horizontal or vertical — for layout alignment.
struct LayoutGuide: Identifiable, Codable {
    let id: UUID
    var axis: Axis
    var position: CGFloat
    var label: String
    var guideColor: GuideColor
    var isBuiltIn: Bool
    var isHidden: Bool = false

    /// Convenience for SwiftUI views
    var color: Color { guideColor.color }

    init(axis: Axis, position: CGFloat, label: String, color: GuideColor, isBuiltIn: Bool) {
        self.id = UUID()
        self.axis = axis
        self.position = position
        self.label = label
        self.guideColor = color
        self.isBuiltIn = isBuiltIn
        self.isHidden = false
    }

    // Axis isn't Codable by default
    enum CodingKeys: String, CodingKey {
        case id, axisRaw, position, label, guideColor, isBuiltIn, isHidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let raw = try c.decode(String.self, forKey: .axisRaw)
        axis = raw == "vertical" ? .vertical : .horizontal
        position = try c.decode(CGFloat.self, forKey: .position)
        label = try c.decode(String.self, forKey: .label)
        guideColor = try c.decode(GuideColor.self, forKey: .guideColor)
        isBuiltIn = try c.decode(Bool.self, forKey: .isBuiltIn)
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(axis == .vertical ? "vertical" : "horizontal", forKey: .axisRaw)
        try c.encode(position, forKey: .position)
        try c.encode(label, forKey: .label)
        try c.encode(guideColor, forKey: .guideColor)
        try c.encode(isBuiltIn, forKey: .isBuiltIn)
        try c.encode(isHidden, forKey: .isHidden)
    }

    static var builtInGuides: [LayoutGuide] {
        // No built-in guides — add manually via the guide tray or design toolbar
        return []
    }
}

/// Central state manager for Design God Mode
/// Controls visibility of design tools, visual decorators, and debug navigation sections
@Observable
final class DesignModeManager {
    static let shared = DesignModeManager()

    // MARK: - Core State

    /// Whether Design God Mode is enabled (toggled via ⌘⇧D)
    /// When enabled: shows design sections in sidebar + enables overlays
    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                print("🎨 Design God Mode: ENABLED")
            } else {
                print("🎨 Design God Mode: DISABLED")
                // Reset tool when disabled
                activeTool = nil
                // Optionally reset decorator states when disabled
                // showGrid = false
                // showSpacing = false
                // etc.
            }
        }
    }

    // MARK: - Active Tool

    /// Currently active design inspection tool (mutually exclusive)
    var activeTool: DesignTool? = nil {
        didSet {
            if let tool = activeTool {
                print("🔧 Design Tool: \(tool.rawValue)")
            }
        }
    }

    // MARK: - Grid Settings

    /// Show grid overlay (from DebugKit)
    var showGrid: Bool = false

    /// Grid spacing in points - flexible values (8-500pt range)
    /// Use preset buttons or cycleGridSpacing() to change
    var gridSpacing: Int = 50

    /// Preset grid spacing options
    static let gridPresets: [Int] = [16, 24, 50, 100, 200]

    /// Cycle through grid spacing presets
    func cycleGridSpacing() {
        if let idx = Self.gridPresets.firstIndex(of: gridSpacing) {
            gridSpacing = Self.gridPresets[(idx + 1) % Self.gridPresets.count]
        } else {
            // Find closest preset
            gridSpacing = Self.gridPresets.min(by: { abs($0 - gridSpacing) < abs($1 - gridSpacing) }) ?? 50
        }
    }

    // MARK: - Visual Decorator Toggles

    /// Show axis rulers with tick marks (X/Y edges)
    var showRulers: Bool = false

    /// Show spacing decorators (center guides + margin indicators)
    var showSpacing: Bool = false

    /// Show typography decorators (font size/weight labels)
    var showTypography: Bool = false

    /// Show color decorators (color chips with token names)
    var showColors: Bool = false

    /// Show border decorators (outlines of major layout areas)
    var showBorders: Bool = false

    /// Show structural guides (horizontal/vertical datum lines)
    var showGuides: Bool = false

    /// All layout guides (user-created)
    var layoutGuides: [LayoutGuide] = LayoutGuide.builtInGuides {
        didSet { persistGuides() }
    }

    /// Add a new user guide
    func addGuide(axis: Axis, position: CGFloat, color: GuideColor? = nil) {
        let index = layoutGuides.filter({ !$0.isBuiltIn }).count + 1
        let label = axis == .horizontal ? "H\(index)" : "V\(index)"
        let guideColor = color ?? (axis == .horizontal ? .green : .purple)
        layoutGuides.append(LayoutGuide(axis: axis, position: position, label: label, color: guideColor, isBuiltIn: false))
    }

    /// Remove a user guide by id
    func removeGuide(id: UUID) {
        layoutGuides.removeAll { $0.id == id && !$0.isBuiltIn }
    }

    /// Remove all user guides
    func clearUserGuides() {
        layoutGuides.removeAll { !$0.isBuiltIn }
    }

    /// Change a guide's color
    func setGuideColor(id: UUID, color: GuideColor) {
        guard let idx = layoutGuides.firstIndex(where: { $0.id == id }) else { return }
        layoutGuides[idx].guideColor = color
    }

    /// Rename a guide
    func renameGuide(id: UUID, label: String) {
        guard let idx = layoutGuides.firstIndex(where: { $0.id == id }) else { return }
        layoutGuides[idx].label = label
    }

    /// Toggle guide visibility
    func toggleGuideHidden(id: UUID) {
        guard let idx = layoutGuides.firstIndex(where: { $0.id == id }) else { return }
        layoutGuides[idx].isHidden.toggle()
    }

    /// Summary string for sharing guide positions
    var guidesSummary: String {
        layoutGuides.map { guide in
            let axis = guide.axis == .horizontal ? "H" : "V"
            let builtIn = guide.isBuiltIn ? " (built-in)" : ""
            return "\(axis) \(Int(guide.position))pt — \(guide.label) [\(guide.guideColor.rawValue)]\(builtIn)"
        }.joined(separator: "\n")
    }

    // MARK: - Guide Persistence

    private static var guidesFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Talkie/DesignMode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("guides.json")
    }

    private func persistGuides() {
        let userGuides = layoutGuides.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(userGuides) else { return }
        try? data.write(to: Self.guidesFileURL, options: .atomic)
    }

    func loadPersistedGuides() {
        guard let data = try? Data(contentsOf: Self.guidesFileURL),
              let saved = try? JSONDecoder().decode([LayoutGuide].self, from: data) else { return }
        // Merge: built-ins first, then persisted user guides
        layoutGuides = LayoutGuide.builtInGuides + saved
    }

    // MARK: - Advanced Layout Tools

    /// Show vertical and horizontal center guides
    var showCenterGuides: Bool = false

    /// Show window margins and safe areas
    var showEdgeGuides: Bool = false

    /// Show element bounding boxes with dimensions on hover
    var showElementBounds: Bool = false

    /// Pixel zoom magnification level (0 = disabled, 2 = 2x, 4 = 4x)
    var pixelZoomLevel: Int = 0

    // MARK: - Liquid Glass Tuning

    /// Whether glass tuning overrides are active
    var glassOverrideEnabled: Bool = false

    /// Material opacity (0.0 = fully transparent, 1.0 = opaque)
    var glassMaterialOpacity: Double = 0.7

    /// Blur intensity multiplier (0.5 = half blur, 2.0 = double blur)
    var glassBlurMultiplier: Double = 1.0

    /// Highlight/reflection opacity at top edge (0.0 - 1.0)
    var glassHighlightOpacity: Double = 0.30

    /// Border glow opacity (0.0 - 1.0)
    var glassBorderOpacity: Double = 0.40

    /// Inner glow radius for extreme shimmer effect
    var glassInnerGlowRadius: CGFloat = 8.0

    /// Tint color intensity (0.0 = no tint, 1.0 = full tint)
    var glassTintIntensity: Double = 0.25

    /// Reset glass tuning to extreme defaults
    func resetGlassTuning() {
        glassMaterialOpacity = 0.7
        glassBlurMultiplier = 1.0
        glassHighlightOpacity = 0.30
        glassBorderOpacity = 0.40
        glassInnerGlowRadius = 8.0
        glassTintIntensity = 0.25
    }

    /// Preset: Subtle glass (minimal effects)
    func applySubtleGlass() {
        glassMaterialOpacity = 0.85
        glassBlurMultiplier = 0.5
        glassHighlightOpacity = 0.08
        glassBorderOpacity = 0.12
        glassInnerGlowRadius = 0
        glassTintIntensity = 0.10
    }

    /// Preset: Maximum glass (push to the limit)
    func applyMaxGlass() {
        glassMaterialOpacity = 0.4
        glassBlurMultiplier = 2.0
        glassHighlightOpacity = 0.50
        glassBorderOpacity = 0.60
        glassInnerGlowRadius = 12
        glassTintIntensity = 0.35
    }

    // MARK: - List Tuning

    /// Whether list tuning overrides are active
    var listTuningEnabled: Bool = false

    /// Horizontal padding for list rows (default: Spacing.sm = 8pt)
    var listHorizontalPadding: CGFloat = 8

    /// Vertical padding for list rows (default: Spacing.sm = 8pt)
    var listVerticalPadding: CGFloat = 8

    /// Spacing between leading icon and content (default: Spacing.md = 12pt)
    var listLeadingSpacing: CGFloat = 12

    /// Spacing between content and trailing (default: Spacing.md = 12pt)
    var listTrailingSpacing: CGFloat = 12

    /// Icon frame size (default: 44pt for standard, 40pt for compact)
    var listIconSize: CGFloat = 44

    /// Icon corner radius (default: 8pt)
    var listIconCornerRadius: CGFloat = 8

    /// Icon border width (0 = no border, default: 0.5pt)
    var listIconBorderWidth: CGFloat = 0.5

    /// Icon border opacity (default: 0.1)
    var listIconBorderOpacity: Double = 0.1

    func resetListTuning() {
        listHorizontalPadding = 8
        listVerticalPadding = 8
        listLeadingSpacing = 12
        listTrailingSpacing = 12
        listIconSize = 44
        listIconCornerRadius = 8
        listIconBorderWidth = 0.5
        listIconBorderOpacity = 0.1
    }

    // MARK: - Wordmark Tuning

    /// Font size for the TALKIE wordmark
    var wordmarkFontSize: CGFloat = 18

    /// Font weight (0 = ultraLight ... 9 = black)  — 2 = .light
    var wordmarkWeightIndex: Int = 2

    /// Letter spacing / tracking
    var wordmarkTracking: CGFloat = 0.8

    /// Vertical offset from center
    var wordmarkOffsetY: CGFloat = -2

    /// Gap between logo icon and wordmark
    var wordmarkGap: CGFloat = -4

    /// Use small caps style
    var wordmarkSmallCaps: Bool = true

    /// Use monospaced design
    var wordmarkMonospaced: Bool = false

    var wordmarkWeight: Font.Weight {
        let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        // Index 9 maps to .black but array only has 9 entries
        return weights[min(wordmarkWeightIndex, weights.count - 1)]
    }

    static let weightLabels = ["UltraLight", "Thin", "Light", "Regular", "Medium", "SemiBold", "Bold", "Heavy", "Black"]

    func resetWordmark() {
        wordmarkFontSize = 13
        wordmarkWeightIndex = 6
        wordmarkTracking = 1.6
        wordmarkOffsetY = 0
        wordmarkGap = 0
        wordmarkSmallCaps = false
        wordmarkMonospaced = false
    }

    // MARK: - Convenience

    /// Whether any decorator is currently active
    var hasActiveDecorators: Bool {
        showGrid || showSpacing || showTypography || showColors || showBorders || showGuides
    }

    /// Toggle all decorators on/off at once
    func toggleAllDecorators() {
        let newState = !hasActiveDecorators
        showGrid = newState
        showSpacing = newState
        showTypography = newState
        showColors = newState
        showBorders = newState
        showGuides = newState
    }

    /// Reset all decorator states to off
    func resetDecorators() {
        showGrid = false
        showSpacing = false
        showTypography = false
        showColors = false
        showBorders = false
        showGuides = false
    }

    private init() {
        loadPersistedGuides()
    }

    // MARK: - Screenshot

    /// Capture current main window and save to Desktop
    /// Temporarily hides design overlay during capture
    /// Returns the file path on success
    @discardableResult
    func captureScreenshot() -> String? {
        guard let window = NSApplication.shared.mainWindow else {
            print("🎨 Screenshot: No main window")
            return nil
        }

        // Hide design overlay temporarily
        let wasEnabled = isEnabled
        isEnabled = false

        // Flush pending UI updates (synchronous, minimal delay)
        CATransaction.flush()

        // Capture window content
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            print("🎨 Screenshot: Failed to capture")
            isEnabled = wasEnabled
            return nil
        }

        // Restore design overlay
        isEnabled = wasEnabled

        // Create filename with timestamp and dimensions
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let width = Int(window.frame.width)
        let height = Int(window.frame.height)
        let filename = "talkie-\(timestamp)-\(width)x\(height).png"

        // Save to Desktop
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let filepath = desktop.appendingPathComponent(filename)

        // Write PNG
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("🎨 Screenshot: Failed to encode PNG")
            return nil
        }

        do {
            try pngData.write(to: filepath)
            print("🎨 Screenshot saved: \(filepath.path)")

            // Copy path to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(filepath.path, forType: .string)

            return filepath.path
        } catch {
            print("🎨 Screenshot: Failed to save - \(error)")
            return nil
        }
    }
}

#endif
