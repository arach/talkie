//
//  DesignSystem.swift
//  TalkieKit
//
//  Shared design tokens for Talkie apps
//

import SwiftUI

// MARK: - Spacing

public enum Spacing {
    public static let tiny: CGFloat = 1
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 10
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 28
    public static let xxl: CGFloat = 40
}

// MARK: - Corner Radius

public enum CornerRadius {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

// MARK: - Tracking

public enum Tracking {
    public static let tight: CGFloat = 0.5
    public static let normal: CGFloat = 1.0
    public static let medium: CGFloat = 1.5
    public static let wide: CGFloat = 2.0
}

// MARK: - Typography

public extension Font {
    static let techLabel = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let techLabelSmall = Font.system(size: 9, weight: .bold, design: .monospaced)
    static let labelSmall = Font.system(size: 11, weight: .regular)
    static let monoXSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}

// MARK: - Button Styles

public struct TinyButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(configuration.isPressed ? TalkieTheme.hover : Color.clear)
            )
    }
}

public extension ButtonStyle where Self == TinyButtonStyle {
    static var tiny: TinyButtonStyle { TinyButtonStyle() }
}

// MARK: - Dynamic Color

public extension Color {
    /// Creates a color that adapts to light/dark appearance
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        }))
    }
}

// MARK: - Animation Presets

public enum TalkieAnimation {
    public static let fast = Animation.easeInOut(duration: 0.15)
    public static let normal = Animation.easeInOut(duration: 0.25)
    public static let slow = Animation.easeInOut(duration: 0.4)
    public static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

// MARK: - Semantic Colors

public enum SemanticColor {
    public static let success: Color = .green
    public static let warning: Color = .orange
    public static let error: Color = .red
    public static let info: Color = .cyan
    public static let pin: Color = .blue
    public static let processing: Color = .purple
}

// MARK: - TalkieTheme (System-aware)

public enum TalkieTheme {
    // Backgrounds
    public static let background = Color(NSColor.windowBackgroundColor)
    public static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
    public static let backgroundTertiary = Color(NSColor.underPageBackgroundColor)
    public static let secondaryBackground = Color(NSColor.controlBackgroundColor)
    public static let surface = Color(NSColor.controlBackgroundColor)
    public static let surfaceElevated = Color(NSColor.windowBackgroundColor)
    public static let surfaceCard = Color(NSColor.controlBackgroundColor)

    // Text
    public static let textPrimary = Color(NSColor.labelColor)
    public static let textSecondary = Color(NSColor.secondaryLabelColor)
    public static let textTertiary = Color(NSColor.tertiaryLabelColor)
    public static let textMuted = Color(NSColor.quaternaryLabelColor)

    // UI Elements
    public static let accent = Color.accentColor
    public static let border = Color(NSColor.separatorColor)
    public static let divider = Color(NSColor.separatorColor)
    public static let hover = Color(NSColor.unemphasizedSelectedContentBackgroundColor)
    public static let selected = Color.accentColor.opacity(0.15)

    // Aliases for compatibility
    public static var foreground: Color { textPrimary }
    public static var foregroundSecondary: Color { textSecondary }
    public static var foregroundMuted: Color { textMuted }
}

// MARK: - Design Namespace (Legacy)

public enum Design {
    public static let accentColor = Color.accentColor
    public static let divider = TalkieTheme.divider
    public static let fontXS = Font.system(size: 10)
    public static let fontSM = Font.system(size: 12)
}

// MARK: - MidnightSurface (Legacy theme compatibility)

/// Legacy surface colors - maps to system-aware equivalents
public enum MidnightSurface {
    public static let base = TalkieTheme.background
    public static let elevated = TalkieTheme.surfaceElevated
    public static let card = TalkieTheme.surfaceCard
    public static let overlay = Color(NSColor.windowBackgroundColor).opacity(0.95)
    public static let highlight = TalkieTheme.hover
    public static let border = TalkieTheme.border
    public static let divider = TalkieTheme.divider
    public static let content = TalkieTheme.surface
    public static let sidebar = TalkieTheme.backgroundSecondary

    public enum Text {
        public static let primary = TalkieTheme.textPrimary
        public static let secondary = TalkieTheme.textSecondary
        public static let tertiary = TalkieTheme.textTertiary
        public static let muted = TalkieTheme.textMuted
        public static let quaternary = TalkieTheme.textMuted
    }
}

// MARK: - Glass Intensity

public enum GlassIntensity {
    case subtle
    case medium
    case strong

    public var opacity: Double {
        switch self {
        case .subtle: return 0.03
        case .medium: return 0.08
        case .strong: return 0.15
        }
    }

    public var blur: CGFloat {
        switch self {
        case .subtle: return 20
        case .medium: return 30
        case .strong: return 40
        }
    }
}

// MARK: - Glass Effects

public struct GlassSidebar<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background(.ultraThinMaterial)
    }
}

public struct GlassBackgroundModifier: ViewModifier {
    var intensity: GlassIntensity = .subtle
    var cornerRadius: CGFloat

    public init(intensity: GlassIntensity = .subtle, cornerRadius: CGFloat = CornerRadius.sm) {
        self.intensity = intensity
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(intensity.opacity * 10)
            )
    }
}

public struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var padding: Edge.Set
    var paddingAmount: CGFloat

    public init(cornerRadius: CGFloat = CGFloat(CornerRadius.md), padding: Edge.Set = .all, paddingAmount: CGFloat = Spacing.md) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.paddingAmount = paddingAmount
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding, paddingAmount)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            )
    }
}

public struct GlassHoverModifier: ViewModifier {
    @State private var isHovered = false
    var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = CGFloat(CornerRadius.sm)) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? TalkieTheme.hover : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

public struct GlassHoverExternalModifier: ViewModifier {
    var isHovered: Bool
    var isSelected: Bool
    var cornerRadius: CGFloat
    var baseOpacity: Double
    var hoverOpacity: Double
    var selectedOpacity: Double
    var accentColor: Color?

    public init(isHovered: Bool, isSelected: Bool = false, cornerRadius: CGFloat = CGFloat(CornerRadius.sm), baseOpacity: Double = 0, hoverOpacity: Double = 0.15, selectedOpacity: Double = 0.12, accentColor: Color? = nil) {
        self.isHovered = isHovered
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.baseOpacity = baseOpacity
        self.hoverOpacity = hoverOpacity
        self.selectedOpacity = selectedOpacity
        self.accentColor = accentColor
    }

    public func body(content: Content) -> some View {
        let fillColor = accentColor ?? TalkieTheme.hover
        let opacity = isSelected ? selectedOpacity : (isHovered ? hoverOpacity : baseOpacity)
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fillColor.opacity(opacity))
            )
    }
}

public extension View {
    func glassBackground(intensity: GlassIntensity = .subtle) -> some View {
        modifier(GlassBackgroundModifier(intensity: intensity))
    }

    func glassBackground(intensity: GlassIntensity = .subtle, cornerRadius: CGFloat) -> some View {
        modifier(GlassBackgroundModifier(intensity: intensity, cornerRadius: cornerRadius))
    }

    func glassPanel(cornerRadius: CGFloat = CGFloat(CornerRadius.md), padding: Edge.Set = .all, paddingAmount: CGFloat = Spacing.md) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, padding: padding, paddingAmount: paddingAmount))
    }

    func glassHover(cornerRadius: CGFloat = CGFloat(CornerRadius.sm)) -> some View {
        modifier(GlassHoverModifier(cornerRadius: cornerRadius))
    }

    func glassHover(isHovered: Bool, isSelected: Bool = false, cornerRadius: CGFloat = CGFloat(CornerRadius.sm), baseOpacity: Double = 0, hoverOpacity: Double = 0.15, selectedOpacity: Double = 0.12, accentColor: Color? = nil) -> some View {
        modifier(GlassHoverExternalModifier(isHovered: isHovered, isSelected: isSelected, cornerRadius: cornerRadius, baseOpacity: baseOpacity, hoverOpacity: hoverOpacity, selectedOpacity: selectedOpacity, accentColor: accentColor))
    }
}

// MARK: - Liquid Glass (iOS 26 / macOS 26)

/// Global glass configuration - set at app launch
public enum GlassConfig {
    /// Whether to use glass effects (set at launch based on user preference or system capability)
    public static var enableGlassEffects: Bool = true

    /// Auto-detect if glass should be disabled (call at app launch)
    /// Checks system reduce transparency setting
    public static func configureFromSystem() {
        #if os(macOS)
        enableGlassEffects = !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        #endif
    }
}

/// Glass depth intensity for fallback effects
public enum GlassDepth {
    case subtle
    case standard
    case prominent

    var highlightOpacity: Double {
        switch self {
        case .subtle: return 0.08
        case .standard: return 0.12
        case .prominent: return 0.18
        }
    }

    var borderOpacity: Double {
        switch self {
        case .subtle: return 0.12
        case .standard: return 0.18
        case .prominent: return 0.25
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .subtle: return 6
        case .standard: return 10
        case .prominent: return 14
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .subtle: return 0.12
        case .standard: return 0.18
        case .prominent: return 0.25
        }
    }
}

/// Liquid Glass card modifier - uses native .glassEffect() on macOS 26+, falls back to material
public struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var isInteractive: Bool
    var depth: GlassDepth

    public init(cornerRadius: CGFloat = CornerRadius.md, tint: Color? = nil, isInteractive: Bool = false, depth: GlassDepth = .standard) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isInteractive = isInteractive
        self.depth = depth
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        if !GlassConfig.enableGlassEffects {
            // Simple mode - minimal overhead for older machines or reduced transparency
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(white: 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        } else if #available(macOS 26.0, *) {
            let glass: Glass = {
                var g: Glass = .regular
                if let tint = tint {
                    g = g.tint(tint)
                }
                if isInteractive {
                    g = g.interactive()
                }
                return g
            }()
            content
                .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            // Enhanced fallback with depth effects
            // Use drawingGroup() to flatten layers into single GPU texture for better scroll performance
            content
                .background(
                    ZStack {
                        // Base material
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)

                        // Tint overlay
                        if let tint = tint {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(tint.opacity(0.15))
                        }

                        // Combined glass overlay - merge inner glow + convex into single gradient
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(depth.highlightOpacity * 1.5),
                                        Color.white.opacity(depth.highlightOpacity * 0.3),
                                        Color.black.opacity(0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Combined border + highlight stroke
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(depth.borderOpacity * 1.5),
                                        Color.white.opacity(depth.borderOpacity * 0.3)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .drawingGroup() // Flatten to single texture for GPU efficiency
                    .shadow(color: .black.opacity(depth.shadowOpacity), radius: depth.shadowRadius, y: depth.shadowRadius / 2)
                )
        }
    }
}

/// Liquid Glass pill/capsule modifier
public struct LiquidGlassPillModifier: ViewModifier {
    var tint: Color?
    var isInteractive: Bool
    var depth: GlassDepth

    public init(tint: Color? = nil, isInteractive: Bool = true, depth: GlassDepth = .standard) {
        self.tint = tint
        self.isInteractive = isInteractive
        self.depth = depth
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        if !GlassConfig.enableGlassEffects {
            // Simple mode - minimal overhead
            content
                .background(
                    Capsule()
                        .fill(Color(white: 0.12))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        } else if #available(macOS 26.0, *) {
            let glass: Glass = {
                var g: Glass = .regular
                if let tint = tint {
                    g = g.tint(tint)
                }
                if isInteractive {
                    g = g.interactive()
                }
                return g
            }()
            content
                .glassEffect(glass, in: .capsule)
        } else {
            // Enhanced fallback with depth effects
            // Use drawingGroup() to flatten layers into single GPU texture
            content
                .background(
                    ZStack {
                        // Base material
                        Capsule()
                            .fill(.ultraThinMaterial)

                        // Tint overlay
                        if let tint = tint {
                            Capsule()
                                .fill(tint.opacity(0.15))
                        }

                        // Combined glass overlay
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(depth.highlightOpacity * 1.5),
                                        Color.white.opacity(depth.highlightOpacity * 0.3),
                                        Color.black.opacity(0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Combined border
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(depth.borderOpacity * 1.5),
                                        Color.white.opacity(depth.borderOpacity * 0.3)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .drawingGroup() // Flatten to single texture
                    .shadow(color: .black.opacity(depth.shadowOpacity), radius: depth.shadowRadius, y: depth.shadowRadius / 2)
                )
        }
    }
}

/// Liquid Glass container for morphing effects between glass views
@available(macOS 26.0, *)
public struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    public init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

public extension View {
    /// Apply Liquid Glass card effect (macOS 26+) with fallback
    func liquidGlassCard(cornerRadius: CGFloat = CornerRadius.md, tint: Color? = nil, isInteractive: Bool = false, depth: GlassDepth = .standard) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, isInteractive: isInteractive, depth: depth))
    }

    /// Apply Liquid Glass pill/capsule effect (macOS 26+) with fallback
    func liquidGlassPill(tint: Color? = nil, isInteractive: Bool = true, depth: GlassDepth = .standard) -> some View {
        modifier(LiquidGlassPillModifier(tint: tint, isInteractive: isInteractive, depth: depth))
    }

    /// Apply Liquid Glass effect with custom shape (macOS 26+ only, no-op on older)
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = {
                var g: Glass = .regular
                if let tint = tint {
                    g = g.tint(tint)
                }
                if isInteractive {
                    g = g.interactive()
                }
                return g
            }()
            self.glassEffect(glass, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }
}

// MARK: - Liquid Glass Button Styles

/// Glass button style for macOS 26+
@available(macOS 26.0, *)
public struct LiquidGlassButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .buttonStyle(.glass)
    }
}

/// Prominent glass button style for macOS 26+
@available(macOS 26.0, *)
public struct LiquidGlassProminentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .buttonStyle(.glassProminent)
    }
}

/// Cross-platform glass button style with fallback
public struct AdaptiveGlassButtonStyle: ButtonStyle {
    var isProminent: Bool
    var tint: Color?

    public init(prominent: Bool = false, tint: Color? = nil) {
        self.isProminent = prominent
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = {
                var g: Glass = .regular.interactive()
                if let tint = tint {
                    g = g.tint(tint)
                }
                return g
            }()
            if isProminent {
                configuration.label
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .glassEffect(glass, in: .capsule)
                    .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            } else {
                configuration.label
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .glassEffect(glass, in: .rect(cornerRadius: CornerRadius.sm))
                    .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            }
        } else {
            // Enhanced fallback with depth effects
            configuration.label
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    Group {
                        if isProminent {
                            ZStack {
                                Capsule().fill(.ultraThinMaterial)
                                if let tint = tint {
                                    Capsule().fill(tint.opacity(0.2))
                                }
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                Capsule().stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.08)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                            }
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: CornerRadius.sm).fill(.ultraThinMaterial)
                                if let tint = tint {
                                    RoundedRectangle(cornerRadius: CornerRadius.sm).fill(tint.opacity(0.2))
                                }
                                RoundedRectangle(cornerRadius: CornerRadius.sm).fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                RoundedRectangle(cornerRadius: CornerRadius.sm).stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.08)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                            }
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        }
                    }
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

public extension ButtonStyle where Self == AdaptiveGlassButtonStyle {
    static var adaptiveGlass: AdaptiveGlassButtonStyle { AdaptiveGlassButtonStyle() }
    static var adaptiveGlassProminent: AdaptiveGlassButtonStyle { AdaptiveGlassButtonStyle(prominent: true) }

    static func adaptiveGlass(tint: Color) -> AdaptiveGlassButtonStyle {
        AdaptiveGlassButtonStyle(prominent: false, tint: tint)
    }

    static func adaptiveGlassProminent(tint: Color) -> AdaptiveGlassButtonStyle {
        AdaptiveGlassButtonStyle(prominent: true, tint: tint)
    }
}
