//
//  TokenSystem.swift
//  TalkieKit
//
//  Two-tier design token system:
//  - Tier 1: Primitives (raw values, never used directly)
//  - Tier 2: Semantic tokens (what views use, maps to primitives)
//
//  Themes are just different semantic → primitive mappings.
//

import SwiftUI

// MARK: - Tier 1: Primitives (Raw Values)

/// Raw color values. Views should NEVER use these directly.
/// These are the "palette" - the building blocks.
public enum ColorPrimitive {
    // Grays (dark to light)
    public static let gray950 = Color(white: 0.02)
    public static let gray900 = Color(white: 0.06)
    public static let gray850 = Color(white: 0.08)
    public static let gray800 = Color(white: 0.10)
    public static let gray750 = Color(white: 0.12)
    public static let gray700 = Color(white: 0.15)
    public static let gray600 = Color(white: 0.20)
    public static let gray500 = Color(white: 0.35)
    public static let gray400 = Color(white: 0.50)
    public static let gray300 = Color(white: 0.65)
    public static let gray200 = Color(white: 0.80)
    public static let gray100 = Color(white: 0.92)
    public static let gray50  = Color(white: 0.97)
    public static let gray25  = Color(white: 0.99)

    // Brand colors
    public static let cyan500 = Color.cyan
    public static let cyan400 = Color(red: 0.4, green: 0.8, blue: 1.0)
    public static let cyan600 = Color(red: 0.0, green: 0.6, blue: 0.8)
    public static let cyan700 = Color(red: 0.0, green: 0.5, blue: 0.7)

    public static let orange500 = Color(red: 1.0, green: 0.6, blue: 0.2)
    public static let orange400 = Color(red: 1.0, green: 0.7, blue: 0.4)
    public static let orange600 = Color(red: 0.9, green: 0.5, blue: 0.1)

    public static let green500 = Color(red: 0.2, green: 0.9, blue: 0.4)
    public static let green600 = Color(red: 0.15, green: 0.6, blue: 0.3)
    public static let green700 = Color(red: 0.1, green: 0.5, blue: 0.25)
    public static let green900 = Color(red: 0.02, green: 0.08, blue: 0.03)
    public static let green50 = Color(red: 0.95, green: 0.99, blue: 0.95)

    public static let blue500 = Color.blue
    public static let blue600 = Color(red: 0.0, green: 0.4, blue: 0.9)

    // Warm tints (dark)
    public static let warmBlack = Color(red: 0.08, green: 0.06, blue: 0.04)
    public static let warmGray800 = Color(red: 0.12, green: 0.09, blue: 0.06)
    public static let warmGray700 = Color(red: 0.14, green: 0.11, blue: 0.08)
    public static let warmGray400 = Color(red: 0.85, green: 0.75, blue: 0.65)

    // Warm tints (light)
    public static let warmWhite = Color(red: 1.0, green: 0.98, blue: 0.95)
    public static let warmGray50 = Color(red: 0.99, green: 0.97, blue: 0.94)
    public static let warmGray100 = Color(red: 0.96, green: 0.93, blue: 0.88)
    public static let warmGray200 = Color(red: 0.92, green: 0.88, blue: 0.82)

    // Pure
    public static let white = Color.white
    public static let black = Color.black
    public static let clear = Color.clear
}

/// Raw spacing values.
public enum SpacingPrimitive {
    public static let x0: CGFloat = 0
    public static let x1: CGFloat = 2
    public static let x2: CGFloat = 4
    public static let x3: CGFloat = 8
    public static let x4: CGFloat = 12
    public static let x5: CGFloat = 16
    public static let x6: CGFloat = 24
    public static let x7: CGFloat = 32
    public static let x8: CGFloat = 48
}

/// Raw radius values.
public enum RadiusPrimitive {
    public static let none: CGFloat = 0
    public static let sm: CGFloat = 4
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let full: CGFloat = 9999
}

/// Raw shadow definitions.
public struct ShadowPrimitive {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }

    public static let none = ShadowPrimitive(color: .clear, radius: 0, x: 0, y: 0)

    // Dark mode shadows (softer)
    public static let smDark = ShadowPrimitive(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    public static let mdDark = ShadowPrimitive(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
    public static let lgDark = ShadowPrimitive(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)

    // Light mode shadows (more visible)
    public static let smLight = ShadowPrimitive(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    public static let mdLight = ShadowPrimitive(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    public static let lgLight = ShadowPrimitive(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)

    // Convenience - picks based on scheme
    public static func sm(for scheme: ColorScheme) -> ShadowPrimitive {
        scheme == .dark ? smDark : smLight
    }

    public static func md(for scheme: ColorScheme) -> ShadowPrimitive {
        scheme == .dark ? mdDark : mdLight
    }

    public static func lg(for scheme: ColorScheme) -> ShadowPrimitive {
        scheme == .dark ? lgDark : lgLight
    }

    public static func glow(_ color: Color, radius: CGFloat = 12) -> ShadowPrimitive {
        ShadowPrimitive(color: color.opacity(0.4), radius: radius, x: 0, y: 0)
    }
}

/// Raw border definitions.
public struct BorderPrimitive {
    public let width: CGFloat
    public let opacity: Double

    public static let none = BorderPrimitive(width: 0, opacity: 0)
    public static let subtle = BorderPrimitive(width: 1, opacity: 0.08)
    public static let light = BorderPrimitive(width: 1, opacity: 0.12)
    public static let medium = BorderPrimitive(width: 1, opacity: 0.2)
    public static let strong = BorderPrimitive(width: 1, opacity: 0.3)
    public static let thick = BorderPrimitive(width: 2, opacity: 0.2)
}

/// Raw animation durations.
public enum DurationPrimitive {
    public static let instant: Double = 0.1
    public static let fast: Double = 0.15
    public static let normal: Double = 0.25
    public static let slow: Double = 0.4
    public static let slower: Double = 0.6
}

/// Animation curve primitives.
public enum AnimationPrimitive {
    public static let snappy = Animation.easeOut(duration: DurationPrimitive.fast)
    public static let smooth = Animation.easeInOut(duration: DurationPrimitive.normal)
    public static let gentle = Animation.easeInOut(duration: DurationPrimitive.slow)
    public static let springy = Animation.spring(response: 0.4, dampingFraction: 0.7)
    public static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.6)
}

/// Opacity primitives for consistent transparency.
public enum OpacityPrimitive {
    public static let invisible: Double = 0
    public static let faint: Double = 0.03
    public static let subtle: Double = 0.08
    public static let light: Double = 0.15
    public static let medium: Double = 0.3
    public static let half: Double = 0.5
    public static let prominent: Double = 0.7
    public static let strong: Double = 0.85
    public static let opaque: Double = 1.0
}

// MARK: - Tier 2: Semantic Tokens (What Views Use)

/// Semantic tokens protocol. Views use THESE, not primitives.
/// Each theme provides a different mapping to primitives.
public protocol SemanticTokens {
    // MARK: Color Scheme
    var colorScheme: ColorScheme { get }

    // MARK: Backgrounds
    var bgCanvas: Color { get }        // App background
    var bgSurface: Color { get }       // Cards, panels
    var bgElevated: Color { get }      // Popovers, modals
    var bgHover: Color { get }         // Hover state
    var bgSelected: Color { get }      // Selected item

    // MARK: Foregrounds
    var fgPrimary: Color { get }       // Main text
    var fgSecondary: Color { get }     // Secondary text
    var fgMuted: Color { get }         // Disabled, hints

    // MARK: Borders
    var borderDefault: Color { get }   // Standard borders
    var borderSubtle: Color { get }    // Subtle dividers
    var borderFocused: Color { get }   // Focused input border
    var borderStyle: BorderPrimitive { get }  // Width + opacity

    // MARK: Accent
    var accent: Color { get }          // Primary actions
    var accentHover: Color { get }     // Accent on hover
    var accentSubtle: Color { get }    // Accent backgrounds

    // MARK: Semantic States
    var success: Color { get }
    var warning: Color { get }
    var error: Color { get }

    // MARK: Shadows
    var shadowCard: ShadowPrimitive { get }
    var shadowPopover: ShadowPrimitive { get }
    var shadowHover: ShadowPrimitive { get }  // Card on hover

    // MARK: Radii
    var radiusButton: CGFloat { get }
    var radiusCard: CGFloat { get }
    var radiusModal: CGFloat { get }
    var radiusPill: CGFloat { get }    // Pills, tags

    // MARK: Animations
    var animationFast: Animation { get }    // Micro-interactions
    var animationDefault: Animation { get } // Standard transitions
    var animationSpring: Animation { get }  // Bouncy feedback

    // MARK: Highlights
    var highlightHover: Color { get }      // Row/item hover
    var highlightActive: Color { get }     // Active/pressed
    var highlightFocus: Color { get }      // Focus ring

    // MARK: Component Tokens
    var table: TableTokens { get }         // List/table styling
    var card: CardTokens { get }           // Card styling
    var button: ButtonTokens { get }       // Button styling
}

// MARK: - Component Token Structs

/// Table/List component tokens (light customization example)
public struct TableTokens {
    public let rowHeight: CGFloat
    public let rowPadding: CGFloat
    public let rowSpacing: CGFloat
    public let rowHover: Color
    public let rowSelected: Color
    public let rowAlt: Color              // Zebra striping (clear = none)
    public let divider: Color

    public init(
        rowHeight: CGFloat = 44,
        rowPadding: CGFloat = SpacingPrimitive.x4,
        rowSpacing: CGFloat = SpacingPrimitive.x1,
        rowHover: Color = ColorPrimitive.white.opacity(0.05),
        rowSelected: Color = ColorPrimitive.cyan500.opacity(0.15),
        rowAlt: Color = .clear,
        divider: Color = ColorPrimitive.white.opacity(0.06)
    ) {
        self.rowHeight = rowHeight
        self.rowPadding = rowPadding
        self.rowSpacing = rowSpacing
        self.rowHover = rowHover
        self.rowSelected = rowSelected
        self.rowAlt = rowAlt
        self.divider = divider
    }

    public static func `default`(for scheme: ColorScheme) -> TableTokens {
        scheme == .dark ? defaultDark : defaultLight
    }

    public static let defaultDark = TableTokens()

    public static let defaultLight = TableTokens(
        rowHover: ColorPrimitive.black.opacity(0.04),
        rowSelected: ColorPrimitive.cyan600.opacity(0.12),
        rowAlt: .clear,
        divider: ColorPrimitive.black.opacity(0.06)
    )
}

/// Card component tokens (medium customization example)
public struct CardTokens {
    public let background: Color
    public let backgroundHover: Color
    public let border: Color
    public let borderWidth: CGFloat
    public let radius: CGFloat
    public let padding: CGFloat
    public let shadow: ShadowPrimitive
    public let shadowHover: ShadowPrimitive

    public init(
        background: Color = ColorPrimitive.gray850,
        backgroundHover: Color = ColorPrimitive.gray800,
        border: Color = ColorPrimitive.white.opacity(0.08),
        borderWidth: CGFloat = 1,
        radius: CGFloat = RadiusPrimitive.md,
        padding: CGFloat = SpacingPrimitive.x4,
        shadow: ShadowPrimitive = .smDark,
        shadowHover: ShadowPrimitive = .mdDark
    ) {
        self.background = background
        self.backgroundHover = backgroundHover
        self.border = border
        self.borderWidth = borderWidth
        self.radius = radius
        self.padding = padding
        self.shadow = shadow
        self.shadowHover = shadowHover
    }

    public static func `default`(for scheme: ColorScheme) -> CardTokens {
        scheme == .dark ? defaultDark : defaultLight
    }

    public static let defaultDark = CardTokens()

    public static let defaultLight = CardTokens(
        background: ColorPrimitive.white,
        backgroundHover: ColorPrimitive.gray50,
        border: ColorPrimitive.black.opacity(0.08),
        borderWidth: 1,
        radius: RadiusPrimitive.md,
        padding: SpacingPrimitive.x4,
        shadow: .smLight,
        shadowHover: .mdLight
    )

    /// Sharp cards with glow (Linear style) - dark mode only
    public static func glow(accent: Color = ColorPrimitive.cyan500) -> CardTokens {
        CardTokens(
            background: ColorPrimitive.gray900,
            backgroundHover: ColorPrimitive.gray850,
            border: accent.opacity(0.2),
            borderWidth: 1,
            radius: RadiusPrimitive.sm,  // Sharper
            padding: SpacingPrimitive.x4,
            shadow: .glow(accent, radius: 6),
            shadowHover: .glow(accent, radius: 12)
        )
    }

    /// Soft cards (Warm style)
    public static func soft(for scheme: ColorScheme) -> CardTokens {
        scheme == .dark ? softDark : softLight
    }

    public static let softDark = CardTokens(
        background: ColorPrimitive.warmGray800,
        backgroundHover: ColorPrimitive.warmGray700,
        border: .clear,
        borderWidth: 0,
        radius: RadiusPrimitive.lg,
        padding: SpacingPrimitive.x5,
        shadow: .mdDark,
        shadowHover: .lgDark
    )

    public static let softLight = CardTokens(
        background: ColorPrimitive.warmGray50,
        backgroundHover: ColorPrimitive.warmGray100,
        border: .clear,
        borderWidth: 0,
        radius: RadiusPrimitive.lg,
        padding: SpacingPrimitive.x5,
        shadow: .mdLight,
        shadowHover: .lgLight
    )
}

/// Button component tokens (heavy customization example)
public struct ButtonTokens {
    // Primary button
    public let primaryBg: Color
    public let primaryFg: Color
    public let primaryHover: Color
    public let primaryRadius: CGFloat

    // Secondary/ghost button
    public let secondaryBg: Color
    public let secondaryFg: Color
    public let secondaryBorder: Color
    public let secondaryHover: Color

    // Sizing
    public let heightSm: CGFloat
    public let heightMd: CGFloat
    public let heightLg: CGFloat
    public let paddingH: CGFloat

    // Animation
    public let pressScale: CGFloat
    public let animation: Animation

    public init(
        primaryBg: Color = ColorPrimitive.cyan500,
        primaryFg: Color = ColorPrimitive.black,
        primaryHover: Color = ColorPrimitive.cyan400,
        primaryRadius: CGFloat = RadiusPrimitive.md,
        secondaryBg: Color = .clear,
        secondaryFg: Color = ColorPrimitive.white,
        secondaryBorder: Color = ColorPrimitive.white.opacity(0.2),
        secondaryHover: Color = ColorPrimitive.white.opacity(0.1),
        heightSm: CGFloat = 28,
        heightMd: CGFloat = 36,
        heightLg: CGFloat = 44,
        paddingH: CGFloat = SpacingPrimitive.x4,
        pressScale: CGFloat = 0.98,
        animation: Animation = AnimationPrimitive.snappy
    ) {
        self.primaryBg = primaryBg
        self.primaryFg = primaryFg
        self.primaryHover = primaryHover
        self.primaryRadius = primaryRadius
        self.secondaryBg = secondaryBg
        self.secondaryFg = secondaryFg
        self.secondaryBorder = secondaryBorder
        self.secondaryHover = secondaryHover
        self.heightSm = heightSm
        self.heightMd = heightMd
        self.heightLg = heightLg
        self.paddingH = paddingH
        self.pressScale = pressScale
        self.animation = animation
    }

    public static func `default`(for scheme: ColorScheme) -> ButtonTokens {
        scheme == .dark ? defaultDark : defaultLight
    }

    public static let defaultDark = ButtonTokens()

    public static let defaultLight = ButtonTokens(
        primaryBg: ColorPrimitive.cyan600,
        primaryFg: ColorPrimitive.white,
        primaryHover: ColorPrimitive.cyan700,
        primaryRadius: RadiusPrimitive.md,
        secondaryBg: .clear,
        secondaryFg: ColorPrimitive.gray800,
        secondaryBorder: ColorPrimitive.black.opacity(0.15),
        secondaryHover: ColorPrimitive.black.opacity(0.05)
    )

    /// Pill buttons (fully rounded)
    public static func pill(for scheme: ColorScheme) -> ButtonTokens {
        let base = Self.default(for: scheme)
        return ButtonTokens(
            primaryBg: base.primaryBg,
            primaryFg: base.primaryFg,
            primaryHover: base.primaryHover,
            primaryRadius: RadiusPrimitive.full,
            secondaryBg: base.secondaryBg,
            secondaryFg: base.secondaryFg,
            secondaryBorder: base.secondaryBorder,
            secondaryHover: base.secondaryHover,
            pressScale: 0.95,
            animation: AnimationPrimitive.bouncy
        )
    }

    /// Sharp buttons (Linear/Vercel style) - dark mode only
    public static let sharp = ButtonTokens(
        primaryRadius: RadiusPrimitive.sm,
        pressScale: 1.0,  // No scale, just color change
        animation: AnimationPrimitive.snappy
    )

    /// Warm buttons
    public static func warm(for scheme: ColorScheme, accent: Color = ColorPrimitive.orange500) -> ButtonTokens {
        if scheme == .dark {
            return ButtonTokens(
                primaryBg: accent,
                primaryFg: ColorPrimitive.warmBlack,
                primaryHover: ColorPrimitive.orange400,
                primaryRadius: RadiusPrimitive.lg,
                secondaryBg: .clear,
                secondaryFg: ColorPrimitive.warmWhite,
                secondaryBorder: ColorPrimitive.warmWhite.opacity(0.2),
                secondaryHover: ColorPrimitive.warmWhite.opacity(0.1),
                pressScale: 0.97,
                animation: AnimationPrimitive.springy
            )
        } else {
            return ButtonTokens(
                primaryBg: ColorPrimitive.orange600,
                primaryFg: ColorPrimitive.white,
                primaryHover: ColorPrimitive.orange500,
                primaryRadius: RadiusPrimitive.lg,
                secondaryBg: .clear,
                secondaryFg: ColorPrimitive.warmGray400,
                secondaryBorder: ColorPrimitive.black.opacity(0.12),
                secondaryHover: ColorPrimitive.black.opacity(0.05),
                pressScale: 0.97,
                animation: AnimationPrimitive.springy
            )
        }
    }
}

// MARK: - Default Implementation (Reference Theme)

/// Default values - themes only override what's different.
/// These defaults adapt to color scheme.
public extension SemanticTokens {
    // Default colorScheme (themes should override this)
    var colorScheme: ColorScheme { .dark }

    // Helper for scheme-aware defaults
    private var isDark: Bool { colorScheme == .dark }

    // Backgrounds - adapt to scheme
    var bgCanvas: Color { isDark ? ColorPrimitive.gray900 : ColorPrimitive.gray50 }
    var bgSurface: Color { isDark ? ColorPrimitive.gray850 : ColorPrimitive.white }
    var bgElevated: Color { isDark ? ColorPrimitive.gray800 : ColorPrimitive.white }
    var bgHover: Color { isDark ? ColorPrimitive.gray750 : ColorPrimitive.gray100 }
    var bgSelected: Color { accent.opacity(isDark ? 0.15 : 0.12) }

    // Foregrounds
    var fgPrimary: Color { isDark ? ColorPrimitive.white : ColorPrimitive.gray900 }
    var fgSecondary: Color { isDark ? ColorPrimitive.gray300 : ColorPrimitive.gray600 }
    var fgMuted: Color { isDark ? ColorPrimitive.gray500 : ColorPrimitive.gray400 }

    // Borders
    var borderDefault: Color { isDark ? ColorPrimitive.white.opacity(0.1) : ColorPrimitive.black.opacity(0.1) }
    var borderSubtle: Color { isDark ? ColorPrimitive.white.opacity(0.05) : ColorPrimitive.black.opacity(0.05) }
    var borderFocused: Color { isDark ? accent : ColorPrimitive.cyan600 }
    var borderStyle: BorderPrimitive { .light }

    // Accent - slightly darker in light mode for contrast
    var accent: Color { isDark ? ColorPrimitive.cyan500 : ColorPrimitive.cyan600 }
    var accentHover: Color { isDark ? ColorPrimitive.cyan400 : ColorPrimitive.cyan700 }
    var accentSubtle: Color { accent.opacity(isDark ? 0.15 : 0.1) }

    // States - darker variants in light mode
    var success: Color { isDark ? ColorPrimitive.green500 : ColorPrimitive.green600 }
    var warning: Color { isDark ? ColorPrimitive.orange500 : ColorPrimitive.orange600 }
    var error: Color { Color.red }

    // Shadows - adapt to scheme
    var shadowCard: ShadowPrimitive { ShadowPrimitive.sm(for: colorScheme) }
    var shadowPopover: ShadowPrimitive { ShadowPrimitive.md(for: colorScheme) }
    var shadowHover: ShadowPrimitive { ShadowPrimitive.md(for: colorScheme) }

    // Radii (same for both modes)
    var radiusButton: CGFloat { RadiusPrimitive.md }
    var radiusCard: CGFloat { RadiusPrimitive.md }
    var radiusModal: CGFloat { RadiusPrimitive.lg }
    var radiusPill: CGFloat { RadiusPrimitive.full }

    // Animations (same for both modes)
    var animationFast: Animation { AnimationPrimitive.snappy }
    var animationDefault: Animation { AnimationPrimitive.smooth }
    var animationSpring: Animation { AnimationPrimitive.springy }

    // Highlights - adapt to scheme
    var highlightHover: Color { isDark ? ColorPrimitive.white.opacity(0.05) : ColorPrimitive.black.opacity(0.04) }
    var highlightActive: Color { isDark ? ColorPrimitive.white.opacity(0.1) : ColorPrimitive.black.opacity(0.08) }
    var highlightFocus: Color { accent.opacity(0.3) }

    // Component tokens - adapt to scheme
    var table: TableTokens { TableTokens.default(for: colorScheme) }
    var card: CardTokens { CardTokens.default(for: colorScheme) }
    var button: ButtonTokens { ButtonTokens.default(for: colorScheme) }
}

// MARK: - Concrete Themes (Just Override Deltas)

/// Midnight - Deep black, cyan accent (DEFAULT)
public struct MidnightTokens: SemanticTokens {
    public let colorScheme: ColorScheme

    public init(_ scheme: ColorScheme = .dark) {
        self.colorScheme = scheme
    }

    private var isDark: Bool { colorScheme == .dark }

    // Darker than default in dark mode, lighter in light mode
    public var bgCanvas: Color { isDark ? ColorPrimitive.gray950 : ColorPrimitive.gray25 }
    public var bgSurface: Color { isDark ? ColorPrimitive.gray900 : ColorPrimitive.white }
    public var bgElevated: Color { isDark ? ColorPrimitive.gray850 : ColorPrimitive.white }

    // Everything else uses defaults (which adapt to colorScheme)!
}

/// Terminal - Green terminal aesthetic, adapts to light/dark
public struct TerminalTokens: SemanticTokens {
    public let colorScheme: ColorScheme

    public init(_ scheme: ColorScheme = .dark) {
        self.colorScheme = scheme
    }

    private var isDark: Bool { colorScheme == .dark }

    // Dark: green on black | Light: dark green on cream
    public var bgCanvas: Color { isDark ? ColorPrimitive.green900 : ColorPrimitive.green50 }
    public var bgSurface: Color { isDark ? Color(red: 0.04, green: 0.10, blue: 0.05) : Color(red: 0.96, green: 0.99, blue: 0.96) }
    public var bgElevated: Color { isDark ? Color(red: 0.06, green: 0.12, blue: 0.07) : ColorPrimitive.white }
    public var fgPrimary: Color { isDark ? ColorPrimitive.green500 : ColorPrimitive.green700 }
    public var fgSecondary: Color { isDark ? ColorPrimitive.green600 : Color(red: 0.2, green: 0.5, blue: 0.3) }
    public var fgMuted: Color { isDark ? ColorPrimitive.green600.opacity(0.5) : ColorPrimitive.green600.opacity(0.6) }
    public var accent: Color { isDark ? ColorPrimitive.green500 : ColorPrimitive.green700 }
    public var borderDefault: Color { isDark ? ColorPrimitive.green500.opacity(0.2) : ColorPrimitive.green700.opacity(0.2) }
    public var borderSubtle: Color { isDark ? ColorPrimitive.green500.opacity(0.1) : ColorPrimitive.green700.opacity(0.1) }

    // Semantic states - green-tinted versions
    public var success: Color { isDark ? ColorPrimitive.green500 : ColorPrimitive.green700 }
    public var warning: Color { isDark ? Color(red: 0.8, green: 0.9, blue: 0.2) : Color(red: 0.6, green: 0.5, blue: 0.0) }
    public var error: Color { isDark ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color(red: 0.8, green: 0.2, blue: 0.2) }
}

/// Warm - Cozy orange/brown, soft cards, bouncy buttons
public struct WarmTokens: SemanticTokens {
    public let colorScheme: ColorScheme

    public init(_ scheme: ColorScheme = .dark) {
        self.colorScheme = scheme
    }

    private var isDark: Bool { colorScheme == .dark }

    public var bgCanvas: Color { isDark ? ColorPrimitive.warmBlack : ColorPrimitive.warmWhite }
    public var bgSurface: Color { isDark ? ColorPrimitive.warmGray800 : ColorPrimitive.warmGray50 }
    public var bgElevated: Color { isDark ? ColorPrimitive.warmGray700 : ColorPrimitive.white }
    public var bgHover: Color { isDark ? ColorPrimitive.warmGray700 : ColorPrimitive.warmGray100 }
    public var fgPrimary: Color { isDark ? ColorPrimitive.warmWhite : ColorPrimitive.warmBlack }
    public var fgSecondary: Color { isDark ? ColorPrimitive.warmGray400 : ColorPrimitive.warmGray400 }
    public var accent: Color { isDark ? ColorPrimitive.orange500 : ColorPrimitive.orange600 }

    // COMPONENT OVERRIDES:

    // Soft, rounded cards with warm tones
    public var card: CardTokens { CardTokens.soft(for: colorScheme) }

    // Bouncy orange buttons
    public var button: ButtonTokens { ButtonTokens.warm(for: colorScheme) }
}

/// Linear - Sharp, minimal, Vercel-inspired. Adapts to light/dark
public struct LinearTokens: SemanticTokens {
    public let colorScheme: ColorScheme

    public init(_ scheme: ColorScheme = .dark) {
        self.colorScheme = scheme
    }

    private var isDark: Bool { colorScheme == .dark }

    // Dark: true black | Light: pure white
    public var bgCanvas: Color { isDark ? ColorPrimitive.black : ColorPrimitive.white }
    public var bgSurface: Color { isDark ? ColorPrimitive.gray900 : ColorPrimitive.gray25 }
    public var bgElevated: Color { isDark ? ColorPrimitive.gray850 : ColorPrimitive.white }
    public var bgHover: Color { isDark ? ColorPrimitive.gray800 : ColorPrimitive.gray50 }

    // Text colors
    public var fgPrimary: Color { isDark ? ColorPrimitive.white : ColorPrimitive.black }
    public var fgSecondary: Color { isDark ? ColorPrimitive.gray300 : ColorPrimitive.gray600 }
    public var fgMuted: Color { isDark ? ColorPrimitive.gray500 : ColorPrimitive.gray400 }

    // Borders - sharp and defined
    public var borderDefault: Color { isDark ? ColorPrimitive.white.opacity(0.12) : ColorPrimitive.black.opacity(0.12) }
    public var borderSubtle: Color { isDark ? ColorPrimitive.white.opacity(0.06) : ColorPrimitive.black.opacity(0.06) }

    // Accent
    public var accent: Color { isDark ? ColorPrimitive.cyan500 : ColorPrimitive.cyan700 }

    // Shadows - glows in dark, subtle shadows in light
    public var shadowCard: ShadowPrimitive { isDark ? .glow(ColorPrimitive.cyan500, radius: 8) : .smLight }
    public var shadowPopover: ShadowPrimitive { isDark ? .glow(ColorPrimitive.cyan500, radius: 16) : .mdLight }
    public var shadowHover: ShadowPrimitive { isDark ? .glow(ColorPrimitive.cyan500, radius: 12) : .mdLight }

    // Snappier animations (same for both modes)
    public var animationFast: Animation { AnimationPrimitive.snappy }
    public var animationDefault: Animation { AnimationPrimitive.snappy }
    public var animationSpring: Animation { Animation.spring(response: 0.3, dampingFraction: 0.8) }

    // Highlights
    public var highlightHover: Color { isDark ? ColorPrimitive.cyan500.opacity(0.08) : ColorPrimitive.cyan700.opacity(0.06) }
    public var highlightFocus: Color { isDark ? ColorPrimitive.cyan500.opacity(0.2) : ColorPrimitive.cyan700.opacity(0.15) }

    // COMPONENT OVERRIDES:

    // Sharp cards - glow in dark, clean in light
    public var card: CardTokens {
        if isDark {
            return .glow()
        } else {
            return CardTokens(
                background: ColorPrimitive.white,
                backgroundHover: ColorPrimitive.gray50,
                border: ColorPrimitive.black.opacity(0.1),
                borderWidth: 1,
                radius: RadiusPrimitive.sm,  // Sharp
                padding: SpacingPrimitive.x4,
                shadow: .smLight,
                shadowHover: .mdLight
            )
        }
    }

    // Sharp buttons, no bounce
    public var button: ButtonTokens {
        if isDark {
            return .sharp
        } else {
            return ButtonTokens(
                primaryBg: ColorPrimitive.cyan700,
                primaryFg: ColorPrimitive.white,
                primaryHover: ColorPrimitive.cyan600,
                primaryRadius: RadiusPrimitive.sm,
                secondaryBg: .clear,
                secondaryFg: ColorPrimitive.gray800,
                secondaryBorder: ColorPrimitive.black.opacity(0.15),
                secondaryHover: ColorPrimitive.black.opacity(0.05),
                pressScale: 1.0,
                animation: AnimationPrimitive.snappy
            )
        }
    }

    // Tighter table rows
    public var table: TableTokens {
        TableTokens(
            rowHeight: 36,  // Compact
            rowHover: isDark ? ColorPrimitive.cyan500.opacity(0.06) : ColorPrimitive.cyan700.opacity(0.04),
            rowSelected: isDark ? ColorPrimitive.cyan500.opacity(0.12) : ColorPrimitive.cyan700.opacity(0.1),
            divider: isDark ? ColorPrimitive.cyan500.opacity(0.08) : ColorPrimitive.black.opacity(0.06)
        )
    }
}

/// Minimal - Subtle grays
public struct MinimalTokens: SemanticTokens {
    public let colorScheme: ColorScheme

    public init(_ scheme: ColorScheme = .dark) {
        self.colorScheme = scheme
    }

    private var isDark: Bool { colorScheme == .dark }

    public var accent: Color { isDark ? ColorPrimitive.gray400 : ColorPrimitive.gray500 }
    public var accentHover: Color { isDark ? ColorPrimitive.gray300 : ColorPrimitive.gray600 }
}

/// Classic - Blue accent
public struct ClassicTokens: SemanticTokens {
    public let colorScheme: ColorScheme

    public init(_ scheme: ColorScheme = .dark) {
        self.colorScheme = scheme
    }

    private var isDark: Bool { colorScheme == .dark }

    public var bgCanvas: Color { isDark ? ColorPrimitive.gray800 : ColorPrimitive.gray100 }
    public var accent: Color { isDark ? ColorPrimitive.blue500 : ColorPrimitive.blue600 }
}

// MARK: - Token Provider

/// Central access point for current theme tokens
public enum Tokens {
    /// Current theme name
    private static var currentThemeName: String = "midnight"

    /// Current color scheme
    private static var currentScheme: ColorScheme = .dark

    /// Current theme tokens - computed from name + scheme
    public static var current: SemanticTokens {
        theme(named: currentThemeName, scheme: currentScheme)
    }

    /// Set both theme name and scheme at once
    public static func setTheme(named name: String, scheme: ColorScheme) {
        currentThemeName = name
        currentScheme = scheme
    }

    /// Update just the color scheme (keeps current theme)
    public static func setScheme(_ scheme: ColorScheme) {
        currentScheme = scheme
    }

    /// Update just the theme name (keeps current scheme)
    public static func setThemeName(_ name: String) {
        currentThemeName = name
    }

    /// Get theme by name for a specific scheme
    public static func theme(named name: String, scheme: ColorScheme = .dark) -> SemanticTokens {
        switch name {
        case "midnight", "talkiePro": return MidnightTokens(scheme)
        case "terminal": return TerminalTokens(scheme)
        case "warm": return WarmTokens(scheme)
        case "linear": return LinearTokens(scheme)
        case "minimal": return MinimalTokens(scheme)
        case "classic": return ClassicTokens(scheme)
        default: return MidnightTokens(scheme)
        }
    }

    /// List of available theme names
    public static let availableThemes = ["midnight", "terminal", "warm", "linear", "minimal", "classic"]

    /// All themes now respect light/dark mode
    public static let adaptiveThemes = availableThemes

    /// No themes are dark-only anymore - all adapt to system appearance
    public static let darkOnlyThemes: [String] = []
}

// MARK: - View Extensions

public extension View {
    /// Apply shadow from token
    func tokenShadow(_ shadow: ShadowPrimitive) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Usage Example
/*

 // In a view that responds to color scheme:
 struct MyCard: View {
     @Environment(\.colorScheme) private var colorScheme

     private var tokens: SemanticTokens {
         Tokens.theme(named: "midnight", scheme: colorScheme)
     }

     var body: some View {
         VStack {
             Text("Title")
                 .foregroundColor(tokens.fgPrimary)
             Text("Subtitle")
                 .foregroundColor(tokens.fgSecondary)
         }
         .padding(SpacingPrimitive.x4)
         .background(tokens.bgSurface)
         .cornerRadius(tokens.radiusCard)
         .tokenShadow(tokens.shadowCard)
     }
 }

 // At app launch, set the theme:
 Tokens.setTheme(named: "warm", scheme: .dark)

 // When system appearance changes:
 Tokens.setScheme(.light)  // or .dark

 // Get a theme instance directly for a specific scheme:
 let darkWarm = Tokens.theme(named: "warm", scheme: .dark)
 let lightWarm = Tokens.theme(named: "warm", scheme: .light)

 // Check if theme adapts to light mode:
 if Tokens.adaptiveThemes.contains("midnight") {
     // Theme supports light mode
 }

 */
