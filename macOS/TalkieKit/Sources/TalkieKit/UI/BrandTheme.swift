//
//  BrandTheme.swift
//  TalkieKit
//
//  A brand-level design system that goes beyond colors.
//  Captures the full personality of a visual identity.
//
//  Usage:
//    let brand = Brand.anthropic
//    view.cornerRadius(brand.radius.card)
//    view.shadow(brand.elevation.raised)
//    view.animation(brand.motion.standard)
//

import SwiftUI

// MARK: - Brand Protocol

/// Complete brand identity - colors, shapes, motion, textures
public protocol BrandTheme {
    var id: String { get }
    var name: String { get }

    // Core palettes
    var palette: BrandPalette { get }
    var semantic: SemanticColors { get }

    // Shape language
    var radius: RadiusScale { get }
    var borders: BorderStyle { get }

    // Depth & dimension
    var elevation: ElevationScale { get }

    // Motion personality
    var motion: MotionStyle { get }

    // Typography
    var typography: TypographyScale { get }

    // Surface treatments
    var surface: SurfaceStyle { get }
}

// MARK: - Palette

/// Color palette with primary, secondary, and accent colors
public struct BrandPalette {
    // Backgrounds (layered)
    public let canvas: Color      // Deepest background
    public let surface1: Color    // Cards, panels
    public let surface2: Color    // Elevated elements
    public let surface3: Color    // Popovers, modals

    // Foregrounds
    public let foreground: Color          // Primary text
    public let foregroundSecondary: Color // Secondary text
    public let foregroundMuted: Color     // Disabled, hints

    // Accents (brands need more than one)
    public let accent: Color              // Primary interactive
    public let accentSecondary: Color     // Secondary actions
    public let accentSubtle: Color        // Backgrounds, hover states

    // Borders
    public let border: Color
    public let borderSubtle: Color

    public init(
        canvas: Color,
        surface1: Color,
        surface2: Color,
        surface3: Color,
        foreground: Color,
        foregroundSecondary: Color,
        foregroundMuted: Color,
        accent: Color,
        accentSecondary: Color,
        accentSubtle: Color,
        border: Color,
        borderSubtle: Color
    ) {
        self.canvas = canvas
        self.surface1 = surface1
        self.surface2 = surface2
        self.surface3 = surface3
        self.foreground = foreground
        self.foregroundSecondary = foregroundSecondary
        self.foregroundMuted = foregroundMuted
        self.accent = accent
        self.accentSecondary = accentSecondary
        self.accentSubtle = accentSubtle
        self.border = border
        self.borderSubtle = borderSubtle
    }
}

/// Semantic colors - consistent across brands
public struct SemanticColors {
    public let success: Color
    public let warning: Color
    public let error: Color
    public let info: Color

    public static let standard = SemanticColors(
        success: Color(red: 0.2, green: 0.8, blue: 0.4),
        warning: Color(red: 1.0, green: 0.7, blue: 0.2),
        error: Color(red: 1.0, green: 0.3, blue: 0.3),
        info: Color.cyan
    )

    public init(success: Color, warning: Color, error: Color, info: Color) {
        self.success = success
        self.warning = warning
        self.error = error
        self.info = info
    }
}

// MARK: - Shape Language

/// Corner radius scale - sharp vs soft brands
public struct RadiusScale {
    public let none: CGFloat      // 0
    public let xs: CGFloat        // Badges, small chips
    public let sm: CGFloat        // Buttons, inputs
    public let md: CGFloat        // Cards
    public let lg: CGFloat        // Modals, panels
    public let full: CGFloat      // Pills, circles

    /// Sharp/geometric brand (Vercel, Linear)
    public static let sharp = RadiusScale(none: 0, xs: 2, sm: 4, md: 6, lg: 8, full: 9999)

    /// Soft/friendly brand (Anthropic, Notion)
    public static let soft = RadiusScale(none: 0, xs: 6, sm: 10, md: 14, lg: 20, full: 9999)

    /// Standard (Apple-ish)
    public static let standard = RadiusScale(none: 0, xs: 4, sm: 8, md: 12, lg: 16, full: 9999)

    public init(none: CGFloat, xs: CGFloat, sm: CGFloat, md: CGFloat, lg: CGFloat, full: CGFloat) {
        self.none = none
        self.xs = xs
        self.sm = sm
        self.md = md
        self.lg = lg
        self.full = full
    }
}

/// Border styling
public struct BorderStyle {
    public let width: CGFloat
    public let opacity: Double
    public let style: BorderAppearance

    public enum BorderAppearance {
        case none           // No borders (rely on elevation)
        case subtle         // Barely visible
        case defined        // Clear separation
        case glow(Color)    // Neon/tech aesthetic
    }

    public static let none = BorderStyle(width: 0, opacity: 0, style: .none)
    public static let subtle = BorderStyle(width: 1, opacity: 0.1, style: .subtle)
    public static let defined = BorderStyle(width: 1, opacity: 0.2, style: .defined)

    public init(width: CGFloat, opacity: Double, style: BorderAppearance) {
        self.width = width
        self.opacity = opacity
        self.style = style
    }
}

// MARK: - Elevation

/// Shadow/elevation scale
public struct ElevationScale {
    public let flat: ShadowStyle
    public let raised: ShadowStyle
    public let floating: ShadowStyle
    public let overlay: ShadowStyle

    /// No shadows (minimal brands)
    public static let none = ElevationScale(
        flat: .none,
        raised: .none,
        floating: .none,
        overlay: .none
    )

    /// Soft diffuse shadows (warm brands)
    public static let soft = ElevationScale(
        flat: .none,
        raised: ShadowStyle(color: .black.opacity(0.08), radius: 8, y: 2),
        floating: ShadowStyle(color: .black.opacity(0.12), radius: 16, y: 4),
        overlay: ShadowStyle(color: .black.opacity(0.2), radius: 32, y: 8)
    )

    /// Sharp shadows (bold brands)
    public static let sharp = ElevationScale(
        flat: .none,
        raised: ShadowStyle(color: .black.opacity(0.2), radius: 2, y: 2),
        floating: ShadowStyle(color: .black.opacity(0.3), radius: 4, y: 4),
        overlay: ShadowStyle(color: .black.opacity(0.4), radius: 8, y: 8)
    )

    /// Glow effect (tech brands)
    public static func glow(_ color: Color) -> ElevationScale {
        ElevationScale(
            flat: .none,
            raised: ShadowStyle(color: color.opacity(0.2), radius: 8, y: 0),
            floating: ShadowStyle(color: color.opacity(0.3), radius: 16, y: 0),
            overlay: ShadowStyle(color: color.opacity(0.4), radius: 24, y: 0)
        )
    }

    public init(flat: ShadowStyle, raised: ShadowStyle, floating: ShadowStyle, overlay: ShadowStyle) {
        self.flat = flat
        self.raised = raised
        self.floating = floating
        self.overlay = overlay
    }
}

public struct ShadowStyle {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public static let none = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)

    public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

// MARK: - Motion

/// Animation personality
public struct MotionStyle {
    public let instant: Double    // Micro-interactions
    public let fast: Double       // Buttons, toggles
    public let standard: Double   // Panels, cards
    public let slow: Double       // Page transitions

    public let curve: Animation   // Default easing
    public let spring: Animation  // Bouncy interactions

    /// Snappy (Linear, Vercel)
    public static let snappy = MotionStyle(
        instant: 0.1,
        fast: 0.15,
        standard: 0.2,
        slow: 0.3,
        curve: .easeOut,
        spring: .spring(response: 0.3, dampingFraction: 0.8)
    )

    /// Smooth (Apple)
    public static let smooth = MotionStyle(
        instant: 0.15,
        fast: 0.2,
        standard: 0.3,
        slow: 0.5,
        curve: .easeInOut,
        spring: .spring(response: 0.4, dampingFraction: 0.7)
    )

    /// Playful (Anthropic, Notion)
    public static let playful = MotionStyle(
        instant: 0.12,
        fast: 0.2,
        standard: 0.35,
        slow: 0.5,
        curve: .easeOut,
        spring: .spring(response: 0.5, dampingFraction: 0.6)
    )

    public init(instant: Double, fast: Double, standard: Double, slow: Double, curve: Animation, spring: Animation) {
        self.instant = instant
        self.fast = fast
        self.standard = standard
        self.slow = slow
        self.curve = curve
        self.spring = spring
    }
}

// MARK: - Typography

/// Typography scale and style
public struct TypographyScale {
    public let family: Font.Design
    public let monoFamily: Font.Design

    // Size scale
    public let xs: CGFloat    // 10-11
    public let sm: CGFloat    // 12-13
    public let base: CGFloat  // 14-15
    public let lg: CGFloat    // 16-18
    public let xl: CGFloat    // 20-24
    public let xxl: CGFloat   // 28-32

    // Weight preferences
    public let bodyWeight: Font.Weight
    public let headingWeight: Font.Weight

    /// System default
    public static let system = TypographyScale(
        family: .default,
        monoFamily: .monospaced,
        xs: 11, sm: 13, base: 14, lg: 17, xl: 22, xxl: 28,
        bodyWeight: .regular,
        headingWeight: .semibold
    )

    /// Rounded/friendly
    public static let rounded = TypographyScale(
        family: .rounded,
        monoFamily: .monospaced,
        xs: 11, sm: 13, base: 15, lg: 18, xl: 24, xxl: 32,
        bodyWeight: .regular,
        headingWeight: .bold
    )

    /// Technical/precise
    public static let technical = TypographyScale(
        family: .monospaced,
        monoFamily: .monospaced,
        xs: 10, sm: 12, base: 13, lg: 15, xl: 18, xxl: 24,
        bodyWeight: .regular,
        headingWeight: .medium
    )

    public init(family: Font.Design, monoFamily: Font.Design, xs: CGFloat, sm: CGFloat, base: CGFloat, lg: CGFloat, xl: CGFloat, xxl: CGFloat, bodyWeight: Font.Weight, headingWeight: Font.Weight) {
        self.family = family
        self.monoFamily = monoFamily
        self.xs = xs
        self.sm = sm
        self.base = base
        self.lg = lg
        self.xl = xl
        self.xxl = xxl
        self.bodyWeight = bodyWeight
        self.headingWeight = headingWeight
    }
}

// MARK: - Surface

/// Surface treatments beyond flat color
public struct SurfaceStyle {
    public let treatment: SurfaceTreatment
    public let blur: CGFloat?         // For glass effects
    public let noise: Double?         // Grain texture (0-1)

    public enum SurfaceTreatment {
        case flat           // Solid colors
        case glass          // Blur + transparency
        case gradient       // Subtle gradients
        case noise          // Grainy texture
    }

    public static let flat = SurfaceStyle(treatment: .flat, blur: nil, noise: nil)
    public static let glass = SurfaceStyle(treatment: .glass, blur: 20, noise: nil)
    public static let grainy = SurfaceStyle(treatment: .noise, blur: nil, noise: 0.03)

    public init(treatment: SurfaceTreatment, blur: CGFloat?, noise: Double?) {
        self.treatment = treatment
        self.blur = blur
        self.noise = noise
    }
}

// MARK: - Default Brand Implementation

/// Default Talkie brand - professional dark theme.
/// Additional branded themes can be added by conforming to BrandTheme.
public struct TalkieBrand: BrandTheme {
    public static let shared = TalkieBrand()

    public var id: String { "talkie" }
    public var name: String { "Talkie Pro" }

    public var palette: BrandPalette {
        BrandPalette(
            canvas: Color(white: 0.08),
            surface1: Color(white: 0.12),
            surface2: Color(white: 0.16),
            surface3: Color(white: 0.20),
            foreground: Color(white: 0.95),
            foregroundSecondary: Color(white: 0.7),
            foregroundMuted: Color(white: 0.5),
            accent: .cyan,
            accentSecondary: .purple,
            accentSubtle: Color.cyan.opacity(0.15),
            border: Color.white.opacity(0.1),
            borderSubtle: Color.white.opacity(0.05)
        )
    }

    public var semantic: SemanticColors { .standard }
    public var radius: RadiusScale { .standard }
    public var borders: BorderStyle { .subtle }
    public var elevation: ElevationScale { .soft }
    public var motion: MotionStyle { .smooth }
    public var typography: TypographyScale { .system }
    public var surface: SurfaceStyle { .flat }

    private init() {}
}

// MARK: - View Extensions

public extension View {
    /// Apply brand shadow
    func elevation(_ style: ShadowStyle) -> some View {
        self.shadow(
            color: style.color,
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }

    /// Apply brand animation
    func animate(_ motion: MotionStyle, duration: KeyPath<MotionStyle, Double> = \.standard) -> some View {
        self.animation(motion.curve.speed(1.0 / motion[keyPath: duration]), value: UUID())
    }
}

// MARK: - Environment
// Note: Component tokens moved to TokenSystem.swift for two-tier approach

private struct BrandKey: EnvironmentKey {
    static let defaultValue: any BrandTheme = TalkieBrand.shared
}

public extension EnvironmentValues {
    var brand: any BrandTheme {
        get { self[BrandKey.self] }
        set { self[BrandKey.self] = newValue }
    }
}
