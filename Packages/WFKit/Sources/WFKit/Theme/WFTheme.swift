import SwiftUI
import AppKit

// MARK: - Appearance (Light/Dark)

public enum WFAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case system

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    public var icon: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Connection Style

public enum WFConnectionStyle: String, CaseIterable, Identifiable, Sendable {
    case bezier      // Smooth S-curve (current)
    case straight    // Direct line
    case step        // Right-angle orthogonal
    case smoothStep  // Orthogonal with rounded corners

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bezier: return "Bezier"
        case .straight: return "Straight"
        case .step: return "Step"
        case .smoothStep: return "Smooth Step"
        }
    }

    public var icon: String {
        switch self {
        case .bezier: return "point.topleft.down.to.point.bottomright.curvepath"
        case .straight: return "line.diagonal"
        case .step: return "arrow.turn.right.down"
        case .smoothStep: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        }
    }
}

// MARK: - Style Presets

public enum WFStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case technical
    case minimal
    case soft
    case neon

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .technical: return "Technical"
        case .minimal: return "Minimal"
        case .soft: return "Soft"
        case .neon: return "Neon"
        }
    }

    public var description: String {
        switch self {
        case .standard: return "Balanced, rounded corners"
        case .technical: return "Sharp edges, monospace"
        case .minimal: return "Pure grayscale, ultra-clean"
        case .soft: return "Extra rounded, warm tones"
        case .neon: return "Cyberpunk, glowing accents"
        }
    }

    public var icon: String {
        switch self {
        case .standard: return "square.on.square"
        case .technical: return "terminal"
        case .minimal: return "square.dashed"
        case .soft: return "cloud"
        case .neon: return "bolt.fill"
        }
    }

    // Style-specific properties
    public var nodeRadius: CGFloat {
        switch self {
        case .standard: return 10
        case .technical: return 2
        case .minimal: return 0           // Sharp edges, no rounding
        case .soft: return 16
        case .neon: return 4
        }
    }

    public var panelRadius: CGFloat {
        switch self {
        case .standard: return 8
        case .technical: return 0
        case .minimal: return 0           // Sharp edges
        case .soft: return 12
        case .neon: return 2
        }
    }

    public var inputRadius: CGFloat {
        switch self {
        case .standard: return 6
        case .technical: return 2
        case .minimal: return 0           // Sharp edges
        case .soft: return 10
        case .neon: return 2
        }
    }

    public var fontFamily: String? {
        switch self {
        case .standard: return nil
        case .technical: return "SF Mono"
        case .minimal: return "SF Mono"   // Monospace for technical look
        case .soft: return nil
        case .neon: return "SF Mono"
        }
    }

    public var useMonospace: Bool {
        switch self {
        case .standard, .soft: return false
        case .technical, .minimal, .neon: return true
        }
    }

    // Style-specific font sizes
    public var nodeTitleSize: CGFloat {
        switch self {
        case .standard: return 13
        case .technical: return 11        // Compact
        case .minimal: return 11          // Compact, same as technical
        case .soft: return 14             // Comfortable
        case .neon: return 12             // Slightly smaller monospace
        }
    }

    public var nodeSubtitleSize: CGFloat {
        switch self {
        case .standard: return 11
        case .technical: return 10        // Compact
        case .minimal: return 10          // Compact
        case .soft: return 12             // Comfortable
        case .neon: return 10
        }
    }

    public var bodySize: CGFloat {
        switch self {
        case .standard: return 13
        case .technical: return 12
        case .minimal: return 12
        case .soft: return 14
        case .neon: return 12
        }
    }

    public var accentHex: String {
        switch self {
        case .standard: return "0A84FF"   // Blue
        case .technical: return "00FF88"  // Matrix green
        case .minimal: return "8A8A8A"    // Medium gray - no color
        case .soft: return "FF9F0A"       // Warm orange
        case .neon: return "FFE500"       // Electric yellow
        }
    }

    public var accentGlowHex: String {
        switch self {
        case .standard: return "0084FF"
        case .technical: return "00FF88"
        case .minimal: return "A0A0A0"    // Slightly lighter gray
        case .soft: return "FFBF4A"
        case .neon: return "FFFF44"       // Bright yellow glow
        }
    }

    // Style-specific canvas colors (dark mode)
    public var canvasBackgroundDarkHex: String {
        switch self {
        case .standard: return "0D0D0D"   // Dark grey
        case .technical: return "0F0F0F"  // Slightly off-black
        case .minimal: return "0A0A0A"    // Near pure black
        case .soft: return "0F0A0A"       // Very dark warm
        case .neon: return "050505"       // Near black (dark background for contrast)
        }
    }

    public var canvasBackgroundLightHex: String {
        switch self {
        case .standard: return "F5F5F5"   // Light gray
        case .technical: return "FAFAFA"  // Near white
        case .minimal: return "FFFFFF"    // Pure white
        case .soft: return "FBF8F5"       // Warm white
        case .neon: return "FFFCF0"       // Light yellow tint
        }
    }

    public var gridDotDarkHex: String {
        switch self {
        case .standard: return "2A2A2A"   // Gray dots
        case .technical: return "505050"  // Light grey dots on black
        case .minimal: return "1F1F1F"    // Very subtle dots
        case .soft: return "3A2A2A"       // Warm-tinted dots
        case .neon: return "3A3000"       // Yellow/amber dots
        }
    }

    public var gridDotLightHex: String {
        switch self {
        case .standard: return "D5D5D5"   // Gray dots
        case .technical: return "C0C0C0"  // Medium gray dots
        case .minimal: return "E8E8E8"    // Very subtle dots on white
        case .soft: return "E5D5D0"       // Warm-tinted dots
        case .neon: return "E5D080"       // Yellow/gold dots
        }
    }

    public var gridDotSize: CGFloat {
        switch self {
        case .standard: return 1.5        // Normal dots
        case .technical: return 1.0       // Small precise dots
        case .minimal: return 0.5         // Tiny, barely visible dots
        case .soft: return 2.0            // Larger softer dots
        case .neon: return 1.5            // Normal with glow
        }
    }

    public enum GridDotStyle {
        case circle
        case cross
        case plus
        case lines    // Horizontal and vertical grid lines
    }

    public var gridDotStyle: GridDotStyle {
        switch self {
        case .standard: return .circle
        case .technical: return .lines    // Blueprint-style line grid
        case .minimal: return .circle     // Clean simple dots
        case .soft: return .circle
        case .neon: return .circle
        }
    }

    // Whether to use outlines instead of filled backgrounds
    public var useOutlineStyle: Bool {
        switch self {
        case .minimal: return true        // No fills, just borders
        default: return false
        }
    }

    // Border width for outline style
    public var outlineBorderWidth: CGFloat {
        switch self {
        case .minimal: return 1.0         // Thin, precise borders
        default: return 1.0
        }
    }

    // Connection curve style
    public var connectionStyle: WFConnectionStyle {
        switch self {
        case .standard: return .bezier    // Smooth curves
        case .technical: return .step     // 90-degree angles (circuit-like)
        case .minimal: return .straight   // Direct lines
        case .soft: return .smoothStep    // Rounded orthogonal
        case .neon: return .bezier        // Smooth glowing curves
        }
    }
}

// MARK: - Theme Manager

@Observable
public final class WFThemeManager {
    public var appearance: WFAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "wfkitAppearance")
        }
    }

    public var style: WFStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: "wfkitStyle")
        }
    }

    // MARK: - Behavior Settings

    /// Enable snap-to-grid when dragging nodes
    public var snapToGrid: Bool = true

    /// Grid snap size in points
    public var gridSnapSize: CGFloat = 20

    // MARK: - Visual Settings

    /// Show glow/shadow effects on nodes
    public var showNodeGlow: Bool = true

    /// Show borders on nodes
    public var showNodeBorder: Bool = true

    /// Node border width
    public var nodeBorderWidth: CGFloat = 1.0

    /// Optional override for connection style (overrides theme default)
    public var connectionStyleOverride: WFConnectionStyle? = nil

    /// Show flow animation on connections
    public var showConnectionFlow: Bool = true

    /// Connection line width
    public var connectionLineWidth: CGFloat = 2.0

    public init() {
        // Load appearance
        if let saved = UserDefaults.standard.string(forKey: "wfkitAppearance"),
           let appearance = WFAppearance(rawValue: saved) {
            self.appearance = appearance
        } else {
            self.appearance = .dark
        }

        // Load style
        if let saved = UserDefaults.standard.string(forKey: "wfkitStyle"),
           let style = WFStyle(rawValue: saved) {
            self.style = style
        } else {
            self.style = .standard
        }
    }

    public var isDark: Bool {
        switch appearance {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            return NSApp.effectiveAppearance.name == .darkAqua
        }
    }

    // MARK: - Canvas Colors (style-dependent)

    public var canvasBackground: Color {
        isDark ? Color(hex: style.canvasBackgroundDarkHex) : Color(hex: style.canvasBackgroundLightHex)
    }

    public var gridDot: Color {
        isDark ? Color(hex: style.gridDotDarkHex) : Color(hex: style.gridDotLightHex)
    }

    // MARK: - Node Colors

    public var nodeBackground: Color {
        isDark ? Color(hex: "1A1A1A") : Color(hex: "FFFFFF")
    }

    public var nodeBackgroundHover: Color {
        isDark ? Color(hex: "2A2A2A") : Color(hex: "F0F0F0")
    }

    public var nodeBorder: Color {
        isDark ? Color(hex: "2A2A2A") : Color(hex: "D0D0D0")
    }

    public var nodeBorderHover: Color {
        isDark ? Color(hex: "3A3A3A") : Color(hex: "B0B0B0")
    }

    // MARK: - Panel/Inspector Colors

    public var panelBackground: Color {
        isDark ? Color(hex: "0D0D0D") : Color(hex: "F8F8F8")
    }

    public var sectionBackground: Color {
        isDark ? Color(hex: "161616") : Color(hex: "FFFFFF")
    }

    public var inputBackground: Color {
        isDark ? Color(hex: "1A1A1A") : Color(hex: "FFFFFF")
    }

    public var toolbarBackground: Color {
        isDark ? Color(hex: "1A1A1A") : Color(hex: "FFFFFF")
    }

    // MARK: - Border Colors

    public var border: Color {
        isDark ? Color(hex: "383838") : Color(hex: "D0D0D0")
    }

    public var borderHover: Color {
        isDark ? Color(hex: "484848") : Color(hex: "B0B0B0")
    }

    public var divider: Color {
        isDark ? Color(hex: "2A2A2A") : Color(hex: "E0E0E0")
    }

    // MARK: - Text Colors

    public var textPrimary: Color {
        isDark ? Color(hex: "F0F0F0") : Color(hex: "1A1A1A")
    }

    public var textSecondary: Color {
        isDark ? Color(hex: "B0B0B0") : Color(hex: "5A5A5A")
    }

    public var textTertiary: Color {
        isDark ? Color(hex: "707070") : Color(hex: "8A8A8A")
    }

    public var textPlaceholder: Color {
        isDark ? Color(hex: "5A5A5A") : Color(hex: "A0A0A0")
    }

    // MARK: - Accent Colors (style-dependent)

    public var accent: Color {
        Color(hex: style.accentHex)
    }

    public var accentGlow: Color {
        Color(hex: style.accentGlowHex)
    }

    // MARK: - Semantic Colors

    public var success: Color { Color(hex: "30D158") }
    public var warning: Color { Color(hex: "FF9F0A") }
    public var error: Color { Color(hex: "FF453A") }
    public var info: Color { Color(hex: "64D2FF") }

    // MARK: - Connection Colors

    public var connectionDefault: Color {
        isDark ? Color(hex: "9A9A9A") : Color(hex: "6A6A6A")
    }

    public var connectionActive: Color { accent }
    public var connectionHover: Color { accentGlow }

    // MARK: - Corner Radii (style-dependent)

    public var nodeRadius: CGFloat { style.nodeRadius }
    public var panelRadius: CGFloat { style.panelRadius }
    public var inputRadius: CGFloat { style.inputRadius }
    public var buttonRadius: CGFloat { style.inputRadius }

    // MARK: - Style-specific rendering

    /// Whether nodes should use outline style (no fills, just borders)
    public var useOutlineStyle: Bool { style.useOutlineStyle }

    /// Border width for outline style
    public var outlineBorderWidth: CGFloat { style.outlineBorderWidth }

    /// Connection curve style (bezier, straight, step, smoothStep)
    /// Uses override if set, otherwise falls back to theme default
    public var connectionStyle: WFConnectionStyle {
        connectionStyleOverride ?? style.connectionStyle
    }

    /// Node background for minimal/outline style (transparent or very subtle)
    public var nodeBackgroundMinimal: Color {
        isDark ? Color.clear : Color.clear
    }

    /// Node border color for minimal style
    public var nodeBorderMinimal: Color {
        isDark ? Color(hex: "3A3A3A") : Color(hex: "C0C0C0")
    }

    // MARK: - Typography (style-dependent)

    public var fontFamily: String? { style.fontFamily }

    public var nodeTitle: Font {
        if style.useMonospace {
            return .system(size: style.nodeTitleSize, weight: .semibold, design: .monospaced)
        }
        return .system(size: style.nodeTitleSize, weight: .semibold)
    }

    public var nodeSubtitle: Font {
        if style.useMonospace {
            return .system(size: style.nodeSubtitleSize, design: .monospaced)
        }
        return .system(size: style.nodeSubtitleSize)
    }

    public var bodyFont: Font {
        if style.useMonospace {
            return .system(size: style.bodySize, design: .monospaced)
        }
        return .system(size: style.bodySize)
    }

    public var monoFont: Font {
        .system(size: style.nodeSubtitleSize, design: .monospaced)
    }

    public var labelFont: Font {
        if style.useMonospace {
            return .system(size: style.nodeSubtitleSize, weight: .medium, design: .monospaced)
        }
        return .system(size: style.nodeSubtitleSize, weight: .medium)
    }
}

// MARK: - Environment Key

private struct WFThemeManagerKey: EnvironmentKey {
    static let defaultValue = WFThemeManager()
}

public extension EnvironmentValues {
    var wfTheme: WFThemeManager {
        get { self[WFThemeManagerKey.self] }
        set { self[WFThemeManagerKey.self] = newValue }
    }
}

public extension View {
    func wfTheme(_ manager: WFThemeManager) -> some View {
        environment(\.wfTheme, manager)
    }
}

// MARK: - Design Constants

public enum WFDesign {
    // MARK: - Spacing

    public static let spacingXXS: CGFloat = 2
    public static let spacingXS: CGFloat = 6
    public static let spacingSM: CGFloat = 10
    public static let spacingMD: CGFloat = 14
    public static let spacingLG: CGFloat = 20
    public static let spacingXL: CGFloat = 28
    public static let spacingXXL: CGFloat = 40

    // MARK: - Node Layout

    public static let nodePadding: CGFloat = 12
    public static let nodeHandleSize: CGFloat = 10
    public static let nodeMinWidth: CGFloat = 180
    public static let nodeMinHeight: CGFloat = 60

    // MARK: - Grid

    public static let gridSize: CGFloat = 20
    public static let gridDotSize: CGFloat = 1.5

    // MARK: - Corner Radius

    public static let radiusXS: CGFloat = 4
    public static let radiusSM: CGFloat = 6
    public static let radiusMD: CGFloat = 8
    public static let radiusLG: CGFloat = 12
    public static let radiusXL: CGFloat = 16

    public static let nodeRadius: CGFloat = 10
    public static let nodeHandleRadius: CGFloat = 5

    // MARK: - Borders

    public static let borderThin: CGFloat = 1
    public static let borderMedium: CGFloat = 1.5
    public static let borderThick: CGFloat = 2
    public static let borderFocus: CGFloat = 2.5

    // MARK: - Input Fields

    public static let inputPadding: CGFloat = 10
    public static let sectionSpacing: CGFloat = 16
    public static let fieldSpacing: CGFloat = 12

    // MARK: - Animation Durations

    public static let animationFast: Double = 0.15
    public static let animationNormal: Double = 0.25
    public static let animationSlow: Double = 0.4

    // MARK: - Z-Index

    public static let zCanvas: Double = 0
    public static let zGrid: Double = 1
    public static let zConnections: Double = 10
    public static let zNodes: Double = 20
    public static let zNodeSelected: Double = 30
    public static let zPanels: Double = 40
    public static let zModals: Double = 50
}

// MARK: - Typography

public enum WFTypography {
    // Display
    public static let displayLarge = Font.system(size: 32, weight: .bold)
    public static let displayMedium = Font.system(size: 24, weight: .semibold)
    public static let displaySmall = Font.system(size: 20, weight: .semibold)

    // Body
    public static let bodyLarge = Font.system(size: 15, weight: .regular)
    public static let bodyMedium = Font.system(size: 13, weight: .regular)
    public static let bodySmall = Font.system(size: 11, weight: .regular)

    // Monospace
    public static let monoLarge = Font.system(size: 14, weight: .regular, design: .monospaced)
    public static let monoMedium = Font.system(size: 12, weight: .regular, design: .monospaced)
    public static let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)

    // Labels
    public static let labelLarge = Font.system(size: 13, weight: .medium)
    public static let labelMedium = Font.system(size: 11, weight: .medium)
    public static let labelSmall = Font.system(size: 9, weight: .semibold)

    // Node
    public static let nodeTitle = Font.system(size: 13, weight: .semibold)
    public static let nodeSubtitle = Font.system(size: 11, weight: .regular)
    public static let nodeData = Font.system(size: 11, weight: .regular, design: .monospaced)
}

// MARK: - Color Presets

public enum WFColorPresets {
    public static let all = [
        "#FF9F0A", // Orange
        "#FFD60A", // Yellow
        "#30D158", // Green
        "#64D2FF", // Cyan
        "#0A84FF", // Blue
        "#BF5AF2", // Purple
        "#FF375F", // Pink
        "#FF453A", // Red
        "#AC8E68", // Brown
        "#98989D"  // Gray
    ]
}
