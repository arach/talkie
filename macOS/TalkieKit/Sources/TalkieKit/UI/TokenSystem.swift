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

    // Brand colors
    public static let cyan500 = Color.cyan
    public static let cyan400 = Color(red: 0.4, green: 0.8, blue: 1.0)
    public static let cyan600 = Color(red: 0.0, green: 0.6, blue: 0.8)

    public static let orange500 = Color(red: 1.0, green: 0.6, blue: 0.2)
    public static let orange400 = Color(red: 1.0, green: 0.7, blue: 0.4)

    public static let green500 = Color(red: 0.2, green: 0.9, blue: 0.4)
    public static let green600 = Color(red: 0.15, green: 0.6, blue: 0.3)
    public static let green900 = Color(red: 0.02, green: 0.08, blue: 0.03)

    public static let blue500 = Color.blue

    // Warm tints
    public static let warmBlack = Color(red: 0.08, green: 0.06, blue: 0.04)
    public static let warmGray800 = Color(red: 0.12, green: 0.09, blue: 0.06)
    public static let warmGray700 = Color(red: 0.14, green: 0.11, blue: 0.08)
    public static let warmWhite = Color(red: 1.0, green: 0.95, blue: 0.9)
    public static let warmGray400 = Color(red: 0.85, green: 0.75, blue: 0.65)

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

    public static let none = ShadowPrimitive(color: .clear, radius: 0, x: 0, y: 0)
    public static let sm = ShadowPrimitive(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    public static let md = ShadowPrimitive(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    public static let lg = ShadowPrimitive(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

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

    public static let `default` = TableTokens()
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
        shadow: ShadowPrimitive = .sm,
        shadowHover: ShadowPrimitive = .md
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

    public static let `default` = CardTokens()

    /// Sharp cards with glow (Linear style)
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
    public static let soft = CardTokens(
        background: ColorPrimitive.warmGray800,
        backgroundHover: ColorPrimitive.warmGray700,
        border: .clear,
        borderWidth: 0,
        radius: RadiusPrimitive.lg,  // Rounder
        padding: SpacingPrimitive.x5,
        shadow: .md,
        shadowHover: .lg
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

    public static let `default` = ButtonTokens()

    /// Pill buttons (fully rounded)
    public static let pill = ButtonTokens(
        primaryRadius: RadiusPrimitive.full,
        pressScale: 0.95,
        animation: AnimationPrimitive.bouncy
    )

    /// Sharp buttons (Linear/Vercel style)
    public static let sharp = ButtonTokens(
        primaryRadius: RadiusPrimitive.sm,
        pressScale: 1.0,  // No scale, just color change
        animation: AnimationPrimitive.snappy
    )

    /// Warm buttons
    public static func warm(accent: Color = ColorPrimitive.orange500) -> ButtonTokens {
        ButtonTokens(
            primaryBg: accent,
            primaryFg: ColorPrimitive.warmBlack,
            primaryHover: ColorPrimitive.orange400,
            primaryRadius: RadiusPrimitive.lg,
            pressScale: 0.97,
            animation: AnimationPrimitive.springy
        )
    }
}

// MARK: - Default Implementation (Reference Theme)

/// Default values - themes only override what's different
public extension SemanticTokens {
    // Backgrounds - dark theme defaults
    var bgCanvas: Color { ColorPrimitive.gray900 }
    var bgSurface: Color { ColorPrimitive.gray850 }
    var bgElevated: Color { ColorPrimitive.gray800 }
    var bgHover: Color { ColorPrimitive.gray750 }
    var bgSelected: Color { accent.opacity(0.15) }

    // Foregrounds
    var fgPrimary: Color { ColorPrimitive.white }
    var fgSecondary: Color { ColorPrimitive.gray300 }
    var fgMuted: Color { ColorPrimitive.gray500 }

    // Borders
    var borderDefault: Color { ColorPrimitive.white.opacity(0.1) }
    var borderSubtle: Color { ColorPrimitive.white.opacity(0.05) }
    var borderFocused: Color { accent }
    var borderStyle: BorderPrimitive { .light }

    // Accent
    var accent: Color { ColorPrimitive.cyan500 }
    var accentHover: Color { ColorPrimitive.cyan400 }
    var accentSubtle: Color { accent.opacity(0.15) }

    // States
    var success: Color { ColorPrimitive.green500 }
    var warning: Color { ColorPrimitive.orange500 }
    var error: Color { Color.red }

    // Shadows
    var shadowCard: ShadowPrimitive { .sm }
    var shadowPopover: ShadowPrimitive { .md }
    var shadowHover: ShadowPrimitive { .md }

    // Radii
    var radiusButton: CGFloat { RadiusPrimitive.md }
    var radiusCard: CGFloat { RadiusPrimitive.md }
    var radiusModal: CGFloat { RadiusPrimitive.lg }
    var radiusPill: CGFloat { RadiusPrimitive.full }

    // Animations
    var animationFast: Animation { AnimationPrimitive.snappy }
    var animationDefault: Animation { AnimationPrimitive.smooth }
    var animationSpring: Animation { AnimationPrimitive.springy }

    // Highlights
    var highlightHover: Color { ColorPrimitive.white.opacity(0.05) }
    var highlightActive: Color { ColorPrimitive.white.opacity(0.1) }
    var highlightFocus: Color { accent.opacity(0.3) }

    // Component tokens (use defaults)
    var table: TableTokens { .default }
    var card: CardTokens { .default }
    var button: ButtonTokens { .default }
}

// MARK: - Concrete Themes (Just Override Deltas)

/// Midnight - Deep black, cyan accent (DEFAULT)
public struct MidnightTokens: SemanticTokens {
    public init() {}

    // Darker than default
    public var bgCanvas: Color { ColorPrimitive.gray950 }
    public var bgSurface: Color { ColorPrimitive.gray900 }
    public var bgElevated: Color { ColorPrimitive.gray850 }

    // Everything else uses defaults!
}

/// Terminal - Green on black
public struct TerminalTokens: SemanticTokens {
    public init() {}

    public var bgCanvas: Color { ColorPrimitive.green900 }
    public var fgPrimary: Color { ColorPrimitive.green500 }
    public var fgSecondary: Color { ColorPrimitive.green600 }
    public var fgMuted: Color { ColorPrimitive.green600.opacity(0.5) }
    public var accent: Color { ColorPrimitive.green500 }
    public var borderDefault: Color { ColorPrimitive.green500.opacity(0.2) }
    public var borderSubtle: Color { ColorPrimitive.green500.opacity(0.1) }
}

/// Warm - Cozy orange/brown, soft cards, bouncy buttons
public struct WarmTokens: SemanticTokens {
    public init() {}

    public var bgCanvas: Color { ColorPrimitive.warmBlack }
    public var bgSurface: Color { ColorPrimitive.warmGray800 }
    public var bgElevated: Color { ColorPrimitive.warmGray700 }
    public var fgPrimary: Color { ColorPrimitive.warmWhite }
    public var fgSecondary: Color { ColorPrimitive.warmGray400 }
    public var accent: Color { ColorPrimitive.orange500 }

    // COMPONENT OVERRIDES:

    // Soft, rounded cards with warm tones
    public var card: CardTokens { .soft }

    // Bouncy orange buttons
    public var button: ButtonTokens { .warm() }
}

/// Linear - True black, glow effects, snappy animations, sharp corners
public struct LinearTokens: SemanticTokens {
    public init() {}

    // True black background
    public var bgCanvas: Color { ColorPrimitive.black }
    public var bgSurface: Color { ColorPrimitive.gray900 }

    // Glow shadows instead of drop shadows
    public var shadowCard: ShadowPrimitive { .glow(ColorPrimitive.cyan500, radius: 8) }
    public var shadowPopover: ShadowPrimitive { .glow(ColorPrimitive.cyan500, radius: 16) }
    public var shadowHover: ShadowPrimitive { .glow(ColorPrimitive.cyan500, radius: 12) }

    // Snappier animations
    public var animationFast: Animation { AnimationPrimitive.snappy }
    public var animationDefault: Animation { AnimationPrimitive.snappy }
    public var animationSpring: Animation { Animation.spring(response: 0.3, dampingFraction: 0.8) }

    // Subtle highlight with glow
    public var highlightHover: Color { ColorPrimitive.cyan500.opacity(0.08) }
    public var highlightFocus: Color { ColorPrimitive.cyan500.opacity(0.2) }

    // COMPONENT OVERRIDES:

    // Glow cards with sharp corners
    public var card: CardTokens { .glow() }

    // Sharp buttons, no bounce
    public var button: ButtonTokens { .sharp }

    // Tighter table rows
    public var table: TableTokens {
        TableTokens(
            rowHeight: 36,  // Compact
            rowHover: ColorPrimitive.cyan500.opacity(0.06),
            rowSelected: ColorPrimitive.cyan500.opacity(0.12),
            divider: ColorPrimitive.cyan500.opacity(0.08)
        )
    }
}

/// Minimal - Subtle grays
public struct MinimalTokens: SemanticTokens {
    public init() {}

    public var accent: Color { ColorPrimitive.gray400 }
    public var accentHover: Color { ColorPrimitive.gray300 }
}

/// Classic - Blue accent
public struct ClassicTokens: SemanticTokens {
    public init() {}

    public var bgCanvas: Color { ColorPrimitive.gray800 }
    public var accent: Color { ColorPrimitive.blue500 }
}

// MARK: - Token Provider

/// Central access point for current theme tokens
public enum Tokens {
    /// Current theme tokens - set at app launch
    public static var current: SemanticTokens = MidnightTokens()

    /// Switch theme
    public static func setTheme(_ theme: SemanticTokens) {
        current = theme
    }

    /// Get theme by name
    public static func theme(named name: String) -> SemanticTokens {
        switch name {
        case "midnight", "talkiePro": return MidnightTokens()
        case "terminal": return TerminalTokens()
        case "warm": return WarmTokens()
        case "linear": return LinearTokens()
        case "minimal": return MinimalTokens()
        case "classic": return ClassicTokens()
        default: return MidnightTokens()
        }
    }
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

 // In a view:
 struct MyCard: View {
     var body: some View {
         VStack {
             Text("Title")
                 .foregroundColor(Tokens.current.fgPrimary)
             Text("Subtitle")
                 .foregroundColor(Tokens.current.fgSecondary)
         }
         .padding(SpacingPrimitive.x4)
         .background(Tokens.current.bgSurface)
         .cornerRadius(Tokens.current.radiusCard)
         .tokenShadow(Tokens.current.shadowCard)
     }
 }

 // At app launch:
 Tokens.setTheme(WarmTokens())

 // Or from user setting:
 Tokens.setTheme(Tokens.theme(named: userPreference))

 */
