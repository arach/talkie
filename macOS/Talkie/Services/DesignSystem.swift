//
//  DesignSystem.swift
//  Talkie macOS
//
//  Talkie Design System v1.0
//
//  ═══════════════════════════════════════════════════════════════════════════
//  PHILOSOPHY
//  ═══════════════════════════════════════════════════════════════════════════
//
//  Talkie is a professional voice tool. The design should feel:
//  • Precise    — Like a high-end audio interface (Logic Pro, Ableton)
//  • Focused    — Minimal distractions, content-first
//  • Trustworthy — Clean, predictable, no surprises
//
//  ═══════════════════════════════════════════════════════════════════════════
//  8PT GRID (Industry Standard)
//  ═══════════════════════════════════════════════════════════════════════════
//
//  Used by: Apple HIG, Material Design, IBM Carbon, Figma/Sketch defaults
//
//  Why 8pt?
//  • Divides evenly into common screen sizes (1920, 1440, 1080, 768)
//  • Scales well (4pt half-grid for fine adjustments)
//  • Creates consistent visual rhythm
//  • Matches Apple's SF font metrics
//
//  ═══════════════════════════════════════════════════════════════════════════
//  TYPOGRAPHY (Major Second Scale: 1.125)
//  ═══════════════════════════════════════════════════════════════════════════
//
//  Scale: 10pt → 11pt → 13pt → 15pt → 18pt → 32pt
//
//  Why Major Second (1.125)?
//  • Tight ratio suits dense UI — not overwhelming jumps
//  • Used by: Apple Notes, Notion, Linear
//  • Alternative: Major Third (1.25) for more dramatic hierarchy
//
//  Font usage:
//  • SF Pro     — UI chrome (labels, buttons, navigation)
//  • SF Mono    — Content (transcripts, timestamps, technical data)
//
//  ═══════════════════════════════════════════════════════════════════════════
//  TEXT OPACITY (WCAG-Informed)
//  ═══════════════════════════════════════════════════════════════════════════
//
//  Primary:     100%  — 21:1 contrast on dark bg
//  Secondary:    70%  — ~14:1 contrast (exceeds AAA)
//  Muted:        40%  — ~7:1 contrast (meets AA)
//  Disabled:     25%  — Intentionally low, de-emphasized
//
//  ═══════════════════════════════════════════════════════════════════════════
//  DEPENDABLE PATTERNS
//  ═══════════════════════════════════════════════════════════════════════════
//
//  A Title is always:      fontHeadlineBold (18pt) or fontTitleBold (15pt)
//  A Label is always:      fontXSBold (10pt) + tracking + secondary color
//  Secondary text:         fontSM (11pt) + foregroundSecondary
//  A Card is always:       surface2 + cornerRadius.sm (8pt) + padding.md (12pt)
//  A Button is always:     32pt height + padding.lg horizontal
//
//  When in doubt: round to the nearest 8pt value.
//
//  ═══════════════════════════════════════════════════════════════════════════

import SwiftUI

// MARK: - Spacing (8pt Grid System)
/// Consistent spacing scale based on 8pt grid.
/// Base unit: 4pt (half-grid for tight spacing)
/// Full grid: 8pt increments
///
/// Visual rhythm:
///   xxs (2pt) - Micro: icon-to-text, tight grouping
///   xs  (4pt) - Compact: related elements, inline spacing
///   sm  (8pt) - Standard: within components
///   md  (12pt) - Medium: between related sections
///   lg  (16pt) - Large: section padding
///   xl  (24pt) - Extra: major section breaks
///   xxl (32pt) - Maximum: page margins, hero spacing
///
enum Spacing {
    /// 2pt - Micro spacing for tight element grouping (icon gaps)
    static let xxs: CGFloat = 2
    /// 4pt - Compact spacing for related elements (half-grid)
    static let xs: CGFloat = 4
    /// 8pt - Standard spacing within components (1x grid)
    static let sm: CGFloat = 8
    /// 12pt - Medium spacing between related sections (1.5x grid)
    static let md: CGFloat = 12
    /// 16pt - Large spacing for section padding (2x grid)
    static let lg: CGFloat = 16
    /// 24pt - Extra large spacing for major breaks (3x grid)
    static let xl: CGFloat = 24
    /// 32pt - Maximum spacing for page margins (4x grid)
    static let xxl: CGFloat = 32
    /// 48pt - Hero spacing for major layout divisions (6x grid)
    static let xxxl: CGFloat = 48
}

// MARK: - Component Sizes (8pt Grid)
/// Standard heights for interactive components.
/// All values on 8pt grid for visual consistency.
enum ComponentSize {
    /// 24pt - Tiny buttons, icon-only controls
    static let tiny: CGFloat = 24
    /// 28pt - Small buttons, compact rows
    static let small: CGFloat = 28
    /// 32pt - Standard buttons, form fields
    static let medium: CGFloat = 32
    /// 40pt - Large buttons, prominent actions
    static let large: CGFloat = 40
    /// 48pt - Extra large, hero buttons
    static let xlarge: CGFloat = 48
    /// 56pt - Maximum, primary CTAs
    static let xxlarge: CGFloat = 56
}

/// Icon sizes following 8pt grid
enum IconSize {
    /// 12pt - Inline icons, badges
    static let xs: CGFloat = 12
    /// 16pt - Standard inline icons
    static let sm: CGFloat = 16
    /// 20pt - Medium icons, navigation
    static let md: CGFloat = 20
    /// 24pt - Large icons, buttons
    static let lg: CGFloat = 24
    /// 32pt - Hero icons, empty states
    static let xl: CGFloat = 32
    /// 48pt - Feature icons, onboarding
    static let xxl: CGFloat = 48
}

// MARK: - Onboarding Layout Constants
/// Standardized layout measurements for onboarding flow.
/// Uses 8pt grid values for consistent spacing.
enum OnboardingLayout {
    /// 48pt - Header zone height (top icon/status area)
    static let headerHeight: CGFloat = ComponentSize.xlarge
    /// 48pt - Footer zone height (action button area)
    static let footerHeight: CGFloat = ComponentSize.xlarge
    /// 40pt - Standard button height in footer
    static let buttonHeight: CGFloat = ComponentSize.large
    /// 24pt - Top padding for content after header
    static let contentTopPadding: CGFloat = Spacing.xl
    /// 24pt - Horizontal padding for all content
    static let horizontalPadding: CGFloat = Spacing.xl
}

// MARK: - Corner Radius
/// Consistent corner radius scale for UI elements.
enum CornerRadius {
    /// 4pt - Minimal rounding for inline elements
    static let xs: CGFloat = 4
    /// 8pt - Small cards, buttons
    static let sm: CGFloat = 8
    /// 12pt - Medium cards, panels
    static let md: CGFloat = 12
    /// 16pt - Large cards, modals
    static let lg: CGFloat = 16
    /// 24pt - Extra large, hero elements
    static let xl: CGFloat = 24
}

// MARK: - Typography (Tactical/Technical)
/// Semantic font tokens for consistent typography.
/// Uses SF Pro + SF Mono for the tactical aesthetic.
extension Font {

    // MARK: Display (Large titles, hero text)
    /// 32pt bold - App title, onboarding headers
    static let displayLarge = Font.system(size: 32, weight: .bold, design: .default)
    /// 26pt bold - Section heroes
    static let displayMedium = Font.system(size: 26, weight: .bold, design: .default)
    /// 22pt semibold - Card titles
    static let displaySmall = Font.system(size: 22, weight: .semibold, design: .default)

    // MARK: Headline (Section titles, emphasis)
    /// 18pt semibold - Major section headers
    static let headlineLarge = Font.system(size: 18, weight: .semibold, design: .default)
    /// 16pt semibold - Subsection headers
    static let headlineMedium = Font.system(size: 16, weight: .semibold, design: .default)
    /// 14pt semibold - Minor headers
    static let headlineSmall = Font.system(size: 14, weight: .semibold, design: .default)

    // MARK: Body (Primary content, readable text)
    /// 16pt regular mono - Large body text
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .monospaced)
    /// 14pt regular mono - Standard body text
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .monospaced)
    /// 12pt regular mono - Compact body text
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .monospaced)

    // MARK: Label (UI chrome, navigation)
    /// 13pt medium - Large labels
    static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
    /// 11pt medium - Standard labels
    static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
    /// 10pt medium - Small labels
    static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)

    // MARK: Tech Labels (Section headers, status indicators)
    /// 10pt bold mono - Section headers (TRANSCRIPT, QUICK ACTIONS)
    /// Note: Avoid .tracking() on small text - causes subpixel blur
    static let techLabel = Font.system(size: 10, weight: .bold, design: .monospaced)
    /// 9pt bold mono - Metadata labels (dates, status)
    /// Note: Avoid .tracking() on small text - causes subpixel blur
    static let techLabelSmall = Font.system(size: 9, weight: .bold, design: .monospaced)

    // MARK: Mono (Technical data, durations, counts)
    /// 16pt medium mono - Large technical values
    static let monoLarge = Font.system(size: 16, weight: .medium, design: .monospaced)
    /// 14pt medium mono - Standard technical values
    static let monoMedium = Font.system(size: 14, weight: .medium, design: .monospaced)
    /// 12pt regular mono - Small technical values (durations)
    static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// 10pt regular mono - Tiny technical values
    static let monoXSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
}

// MARK: - Tracking Presets
/// Letter spacing presets for tactical typography.
/// Apply via .tracking(Tracking.wide)
enum Tracking {
    /// 0.5 - Subtle spacing
    static let tight: CGFloat = 0.5
    /// 1.0 - Standard spacing for metadata
    static let normal: CGFloat = 1.0
    /// 1.5 - Medium spacing
    static let medium: CGFloat = 1.5
    /// 2.0 - Wide spacing for section headers
    static let wide: CGFloat = 2.0
}

// MARK: - Opacity Presets
/// Consistent opacity values for layering and emphasis.
enum Opacity {
    /// 0.03 - Barely visible backgrounds
    static let subtle: Double = 0.03
    /// 0.08 - Light backgrounds, hover states
    static let light: Double = 0.08
    /// 0.15 - Medium emphasis
    static let medium: Double = 0.15
    /// 0.3 - Borders, dividers
    static let strong: Double = 0.3
    /// 0.5 - Half opacity
    static let half: Double = 0.5
    /// 0.7 - Prominent but not full
    static let prominent: Double = 0.7
}

// MARK: - Animation Presets
/// Consistent animation durations and curves.
enum TalkieAnimation {
    static let fast = Animation.easeInOut(duration: 0.15)
    static let normal = Animation.easeInOut(duration: 0.25)
    static let slow = Animation.easeInOut(duration: 0.4)
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

// MARK: - Semantic Colors
/// Consistent colors for interactive elements and status indicators.
enum SemanticColor {
    /// Success/enabled state - active toggles, success messages
    static let success: Color = .green

    /// Warning state - caution messages, auto-run indicators
    static let warning: Color = .orange

    /// Error state - errors, destructive actions
    static let error: Color = .red

    /// Info/highlight state - notifications, info badges
    static let info: Color = .cyan

    /// Pin/favorite accent
    static let pin: Color = .blue

    /// Processing/activity state
    static let processing: Color = .purple
}

// MARK: - Midnight Theme Surface Colors
/// Core background colors for the Midnight (Talkie Pro) dark theme.
/// These provide a consistent, true-black aesthetic across the UI.
enum MidnightSurface {
    /// True black - primary content area (RGB: 0.02, 0.02, 0.03)
    static let content = Color(NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0))

    /// Near-black - sidebar, secondary panels (RGB: 0.06, 0.06, 0.07)
    static let sidebar = Color(NSColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0))

    /// Elevated - bottom bars, toolbars (RGB: 0.08, 0.08, 0.09)
    static let elevated = Color(NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0))

    /// Card - card backgrounds, hover states (RGB: 0.10, 0.10, 0.11)
    static let card = Color(NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0))

    /// Subtle divider color
    static let divider = Color.white.opacity(0.1)

    /// Text colors for Midnight theme
    enum Text {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.7)
        static let tertiary = Color.white.opacity(0.5)
        static let quaternary = Color.white.opacity(0.3)
    }
}

// MARK: - Toggle Styles
/// Custom colored toggle switch for consistent styling across the app.
struct TalkieToggleStyle: ToggleStyle {
    var onColor: Color = SemanticColor.success

    // Toggle dimensions on 4pt grid
    private let trackWidth: CGFloat = 36
    private let trackHeight: CGFloat = 20
    private let knobSize: CGFloat = 16
    private let knobOffset: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(configuration.isOn ? onColor : Color.secondary.opacity(Opacity.strong))
                    .frame(width: trackWidth, height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(Opacity.medium), radius: 1, x: 0, y: 1)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: configuration.isOn ? knobOffset : -knobOffset)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

// Semantic toggle style extensions for easy access
extension ToggleStyle where Self == TalkieToggleStyle {
    /// Custom color toggle
    static func talkie(_ color: Color) -> TalkieToggleStyle {
        TalkieToggleStyle(onColor: color)
    }

    /// Default enabled/success toggle (green)
    static var talkieSuccess: TalkieToggleStyle {
        TalkieToggleStyle(onColor: SemanticColor.success)
    }

    /// Info/notification toggle (cyan)
    static var talkieInfo: TalkieToggleStyle {
        TalkieToggleStyle(onColor: SemanticColor.info)
    }

    /// Warning/auto-run toggle (orange)
    static var talkieWarning: TalkieToggleStyle {
        TalkieToggleStyle(onColor: SemanticColor.warning)
    }

    /// Pin/favorite toggle (blue)
    static var talkiePin: TalkieToggleStyle {
        TalkieToggleStyle(onColor: SemanticColor.pin)
    }

    /// Processing/activity toggle (purple)
    static var talkieProcessing: TalkieToggleStyle {
        TalkieToggleStyle(onColor: SemanticColor.processing)
    }
}

// MARK: - Icon Button Style
/// Circular hover highlight for small icon buttons (delete, settings, etc.)
struct IconButtonStyle: ButtonStyle {
    var hoverColor: Color = .primary
    var size: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        IconButtonStyleView(configuration: configuration, hoverColor: hoverColor, size: size)
    }
}

private struct IconButtonStyleView: View {
    let configuration: ButtonStyleConfiguration
    let hoverColor: Color
    let size: CGFloat

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isHovered ? hoverColor.opacity(Opacity.light) : Color.clear)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(TalkieAnimation.fast, value: configuration.isPressed)
            .animation(TalkieAnimation.fast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    /// Default icon button with subtle hover
    static var icon: IconButtonStyle {
        IconButtonStyle()
    }

    /// Icon button with custom hover color
    static func icon(color: Color, size: CGFloat = 24) -> IconButtonStyle {
        IconButtonStyle(hoverColor: color, size: size)
    }

    /// Destructive icon button (red hover)
    static var iconDestructive: IconButtonStyle {
        IconButtonStyle(hoverColor: SemanticColor.error, size: 24)
    }

    /// Small icon button (20pt)
    static var iconSmall: IconButtonStyle {
        IconButtonStyle(size: 20)
    }

    /// Tiny icon button (16pt)
    static var iconTiny: IconButtonStyle {
        IconButtonStyle(size: 16)
    }
}

// MARK: - Tiny Text Button Style
/// Small text button with background highlight on hover
struct TinyButtonStyle: ButtonStyle {
    var foregroundColor: Color = .secondary
    var hoverForeground: Color? = nil
    var hoverBackground: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        TinyButtonStyleView(
            configuration: configuration,
            foregroundColor: foregroundColor,
            hoverForeground: hoverForeground,
            hoverBackground: hoverBackground
        )
    }
}

private struct TinyButtonStyleView: View {
    let configuration: ButtonStyleConfiguration
    let foregroundColor: Color
    let hoverForeground: Color?
    let hoverBackground: Color

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundColor(isHovered ? (hoverForeground ?? foregroundColor) : foregroundColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isHovered ? hoverBackground.opacity(Opacity.light) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(TalkieAnimation.fast, value: configuration.isPressed)
            .animation(TalkieAnimation.fast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension ButtonStyle where Self == TinyButtonStyle {
    /// Default tiny button
    static var tiny: TinyButtonStyle {
        TinyButtonStyle()
    }

    /// Destructive tiny button (red)
    static var tinyDestructive: TinyButtonStyle {
        TinyButtonStyle(
            foregroundColor: .secondary,
            hoverForeground: SemanticColor.error,
            hoverBackground: SemanticColor.error
        )
    }

    /// Primary tiny button
    static var tinyPrimary: TinyButtonStyle {
        TinyButtonStyle(
            foregroundColor: .primary,
            hoverBackground: .primary
        )
    }
}

// MARK: - Chevron/Expand Button Style
/// Rounded square hover highlight for expand/collapse chevrons
struct ChevronButtonStyle: ButtonStyle {
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        ChevronButtonStyleView(configuration: configuration, size: size)
    }
}

private struct ChevronButtonStyleView: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isHovered ? Color.primary.opacity(Opacity.light) : Color.clear)
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(TalkieAnimation.fast, value: configuration.isPressed)
            .animation(TalkieAnimation.fast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension ButtonStyle where Self == ChevronButtonStyle {
    /// Default chevron button
    static var chevron: ChevronButtonStyle {
        ChevronButtonStyle()
    }

    /// Small chevron button (24pt)
    static var chevronSmall: ChevronButtonStyle {
        ChevronButtonStyle(size: 24)
    }

    /// Large chevron button (32pt)
    static var chevronLarge: ChevronButtonStyle {
        ChevronButtonStyle(size: 32)
    }
}

// MARK: - Expandable Row Style
/// Full-width hover highlight for clickable card headers/rows
struct ExpandableRowStyle: ButtonStyle {
    var cornerRadius: CGFloat = CornerRadius.sm

    func makeBody(configuration: Configuration) -> some View {
        ExpandableRowStyleView(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct ExpandableRowStyleView: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.995 : 1.0)
            .animation(TalkieAnimation.fast, value: configuration.isPressed)
            .animation(TalkieAnimation.fast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension ButtonStyle where Self == ExpandableRowStyle {
    /// Default expandable row style
    static var expandableRow: ExpandableRowStyle {
        ExpandableRowStyle()
    }

    /// Expandable row with custom corner radius
    static func expandableRow(cornerRadius: CGFloat) -> ExpandableRowStyle {
        ExpandableRowStyle(cornerRadius: cornerRadius)
    }
}

// MARK: - Settings Page Components

/// Standardized header for all settings pages
struct SettingsPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(Tracking.wide)
            }
            .foregroundColor(Theme.current.foreground)

            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }
}

/// Container for settings page content with consistent background and sticky header
struct SettingsPageContainer<Header: View, Content: View>: View {
    let header: Header
    let content: Content

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sticky header area
            header
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Theme.current.background)

            Divider()
                .opacity(0.3)

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    content
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minHeight: 500, maxHeight: .infinity)
        .background(Theme.current.background)
    }
}

// Convenience init for backward compatibility (no sticky header)
extension SettingsPageContainer where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.header = EmptyView()
        self.content = content()
    }
}

// MARK: - Settings Page Wrapper with Debug Overlay

/// Reusable wrapper for settings pages with consistent header and debug overlay positioning
#if DEBUG
import DebugKit

struct SettingsPageView<Content: View, DebugContent: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let debugInfo: () -> [String: String]
    let debugContent: DebugContent
    let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String,
        debugInfo: @escaping () -> [String: String] = { [:] },
        @ViewBuilder debugContent: () -> DebugContent,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.debugInfo = debugInfo
        self.debugContent = debugContent()
        self.content = content()
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(icon: icon, title: title, subtitle: subtitle)
        } content: {
            content
        }
        .overlay(alignment: .bottomTrailing) {
            TalkieDebugToolbar {
                debugContent
            } debugInfo: {
                var info = debugInfo()
                info["Page"] = title
                return info
            }
            .padding(.bottom, 40) // Clear the 32px StatusBar
        }
    }
}

// Convenience init for settings pages without custom debug content
extension SettingsPageView where DebugContent == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String,
        debugInfo: @escaping () -> [String: String] = { [:] },
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.debugInfo = debugInfo
        self.debugContent = EmptyView()
        self.content = content()
    }
}

#else
// Release build: just the page container (no debug overlay)
struct SettingsPageView<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(icon: icon, title: title, subtitle: subtitle)
        } content: {
            content
        }
    }
}
#endif

// MARK: - Settings Section Card

/// A reusable card style for settings sections with Liquid Glass effect
struct SettingsSectionCard: ViewModifier {
    var padding: CGFloat = Spacing.lg
    var cornerRadius: CGFloat = CornerRadius.sm

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .liquidGlassCard(cornerRadius: cornerRadius)
    }
}

extension View {
    /// Apply settings section card styling with Liquid Glass
    func settingsSectionCard(padding: CGFloat = Spacing.lg, cornerRadius: CGFloat = CornerRadius.sm) -> some View {
        modifier(SettingsSectionCard(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Cached Theme

/// Pre-computed theme values for performance.
/// Instead of computing fonts/colors on every view access, we compute once and cache.
/// Access via `Theme.current` which is updated when settings change.
struct Theme: Equatable {
    // MARK: - UI Fonts (for chrome: labels, headers, buttons, navigation)
    let fontXS: Font
    let fontXSMedium: Font
    let fontXSBold: Font
    let fontSM: Font
    let fontSMMedium: Font
    let fontSMBold: Font
    let fontBody: Font
    let fontBodyMedium: Font
    let fontBodyBold: Font
    let fontTitle: Font
    let fontTitleMedium: Font
    let fontTitleBold: Font
    let fontHeadline: Font
    let fontHeadlineMedium: Font
    let fontHeadlineBold: Font
    let fontDisplay: Font
    let fontDisplayMedium: Font

    // MARK: - Content Fonts (for user content: transcripts, notes)
    let contentFontSM: Font
    let contentFontSMMedium: Font
    let contentFontBody: Font
    let contentFontBodyMedium: Font
    let contentFontBodyBold: Font
    let contentFontLarge: Font
    let contentFontLargeMedium: Font
    let contentFontLargeBold: Font

    // MARK: - Colors
    let background: Color
    let backgroundSecondary: Color
    let backgroundTertiary: Color
    let foreground: Color
    let foregroundSecondary: Color
    let foregroundMuted: Color
    let divider: Color

    // MARK: - Surface System
    let surfaceBase: Color
    let surface1: Color
    let surface2: Color
    let surface3: Color
    let surfaceInput: Color
    let surfaceHover: Color
    let surfaceSelected: Color
    let surfaceAlternate: Color
    let surfaceWarning: Color
    let surfaceInfo: Color

    // MARK: - Semantic Aliases (for TalkieTheme migration)
    /// Primary surface - use for main content areas
    var surface: Color { surfaceBase }
    /// Elevated surface - use for sidebars, toolbars
    var surfaceElevated: Color { surface1 }
    /// Card surface - use for cards, panels
    var surfaceCard: Color { surface2 }
    /// Primary text - use for main content
    var textPrimary: Color { foreground }
    /// Secondary text - use for descriptions
    var textSecondary: Color { foregroundSecondary }
    /// Tertiary text - use for timestamps, metadata
    var textTertiary: Color { foregroundSecondary.opacity(Opacity.prominent) }
    /// Muted text - use for placeholders, disabled
    var textMuted: Color { foregroundMuted }
    /// Border color - use for card borders
    var border: Color { divider }
    /// Subtle border - use for inner dividers
    var borderSubtle: Color { divider.opacity(Opacity.half) }
    /// Accent color
    var accent: Color { .accentColor }

    // MARK: - Current Theme (singleton access)

    /// The current cached theme. Updated automatically when settings change.
    /// Use this instead of SettingsManager.shared.fontXS etc.
    static var current: Theme = Theme.compute()

    /// Recompute the theme from current settings. Called when theme-affecting settings change.
    static func invalidate() {
        current = compute()
    }

    /// Compute theme from current SettingsManager values
    private static func compute() -> Theme {
        let settings = SettingsManager.shared

        return Theme(
            // UI Fonts
            fontXS: settings.themedFont(baseSize: 10, weight: settings.useLightFonts ? .regular : .regular),
            fontXSMedium: settings.themedFont(baseSize: 10, weight: settings.useLightFonts ? .medium : .medium),
            fontXSBold: settings.themedFont(baseSize: 10, weight: settings.useLightFonts ? .semibold : .semibold),
            fontSM: settings.themedFont(baseSize: 11, weight: settings.useLightFonts ? .regular : .regular),
            fontSMMedium: settings.themedFont(baseSize: 11, weight: settings.useLightFonts ? .medium : .medium),
            fontSMBold: settings.themedFont(baseSize: 11, weight: settings.useLightFonts ? .semibold : .semibold),
            fontBody: settings.themedFont(baseSize: 13, weight: settings.useLightFonts ? .regular : .regular),
            fontBodyMedium: settings.themedFont(baseSize: 13, weight: settings.useLightFonts ? .medium : .medium),
            fontBodyBold: settings.themedFont(baseSize: 13, weight: settings.useLightFonts ? .semibold : .semibold),
            fontTitle: settings.themedFont(baseSize: 15, weight: settings.useLightFonts ? .regular : .regular),
            fontTitleMedium: settings.themedFont(baseSize: 15, weight: settings.useLightFonts ? .medium : .medium),
            fontTitleBold: settings.themedFont(baseSize: 15, weight: settings.useLightFonts ? .semibold : .bold),
            fontHeadline: settings.themedFont(baseSize: 18, weight: settings.useLightFonts ? .regular : .regular),
            fontHeadlineMedium: settings.themedFont(baseSize: 18, weight: settings.useLightFonts ? .medium : .medium),
            fontHeadlineBold: settings.themedFont(baseSize: 18, weight: settings.useLightFonts ? .semibold : .bold),
            fontDisplay: settings.themedFont(baseSize: 32, weight: .light),
            fontDisplayMedium: settings.themedFont(baseSize: 32, weight: settings.useLightFonts ? .regular : .regular),

            // Content Fonts
            contentFontSM: settings.contentFont(baseSize: 10, weight: .regular),
            contentFontSMMedium: settings.contentFont(baseSize: 10, weight: .medium),
            contentFontBody: settings.contentFont(baseSize: 13, weight: .regular),
            contentFontBodyMedium: settings.contentFont(baseSize: 13, weight: .medium),
            contentFontBodyBold: settings.contentFont(baseSize: 13, weight: .bold),
            contentFontLarge: settings.contentFont(baseSize: 15, weight: .regular),
            contentFontLargeMedium: settings.contentFont(baseSize: 15, weight: .medium),
            contentFontLargeBold: settings.contentFont(baseSize: 15, weight: .bold),

            // Colors
            background: settings.tacticalBackground,
            backgroundSecondary: settings.tacticalBackgroundSecondary,
            backgroundTertiary: settings.tacticalBackgroundTertiary,
            foreground: settings.tacticalForeground,
            foregroundSecondary: settings.tacticalForegroundSecondary,
            foregroundMuted: settings.tacticalForegroundMuted,
            divider: settings.tacticalDivider,

            // Surfaces
            surfaceBase: settings.surfaceBase,
            surface1: settings.surface1,
            surface2: settings.surface2,
            surface3: settings.surface3,
            surfaceInput: settings.surfaceInput,
            surfaceHover: settings.surfaceHover,
            surfaceSelected: settings.surfaceSelected,
            surfaceAlternate: settings.surfaceAlternate,
            surfaceWarning: settings.surfaceWarning,
            surfaceInfo: settings.surfaceInfo
        )
    }
}

// MARK: - TalkieTheme (for Live UI)
// Uses system-adaptive colors that automatically respond to light/dark mode

enum TalkieTheme {
    // System backgrounds - automatically adapt to light/dark mode
    static let background = Color(NSColor.windowBackgroundColor)
    static let secondaryBackground = Color(NSColor.controlBackgroundColor)
    static let tertiaryBackground = Color(NSColor.underPageBackgroundColor)

    // Adaptive surface colors using NSColor which automatically adapts
    static var surface: Color {
        Color(NSColor.windowBackgroundColor)
    }

    static var surfaceElevated: Color {
        Color(NSColor.controlBackgroundColor)
    }

    static var surfaceCard: Color {
        Color(NSColor.controlBackgroundColor)
    }

    // Adaptive text colors
    static var textPrimary: Color {
        Color(NSColor.labelColor)
    }

    static var textSecondary: Color {
        Color(NSColor.secondaryLabelColor)
    }

    static var textTertiary: Color {
        Color(NSColor.tertiaryLabelColor)
    }

    static var textMuted: Color {
        Color(NSColor.tertiaryLabelColor)
    }

    // Adaptive border/divider colors
    static var border: Color {
        Color(NSColor.separatorColor)
    }

    static var borderSubtle: Color {
        Color(NSColor.separatorColor).opacity(0.5)
    }

    static var divider: Color {
        Color(NSColor.separatorColor)
    }

    // Hover state
    static var hover: Color {
        Color(NSColor.unemphasizedSelectedContentBackgroundColor)
    }

    // Accent
    static var accent: Color {
        Color.accentColor
    }

    static var selected: Color {
        Color.accentColor.opacity(0.2)
    }
}

struct ThemeColorPalette {
    let surface: Color
    let surfaceElevated: Color
    let surfaceCard: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textMuted: Color
    let border: Color
    let borderSubtle: Color
    let divider: Color
    let hover: Color
    let accent: Color

    static func midnight() -> ThemeColorPalette {
        ThemeColorPalette(
            surface: Color(NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)),
            surfaceElevated: Color(NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)),
            surfaceCard: Color(NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0)),
            textPrimary: Color.white,
            textSecondary: Color.white.opacity(0.7),
            textTertiary: Color.white.opacity(0.5),
            textMuted: Color.white.opacity(0.3),
            border: Color.white.opacity(0.1),
            borderSubtle: Color.white.opacity(0.06),
            divider: Color.white.opacity(0.1),
            hover: Color.white.opacity(0.05),
            accent: Color.cyan
        )
    }

    /// Daylight theme palette - clean light mode with proper contrast
    static func daylight() -> ThemeColorPalette {
        ThemeColorPalette(
            surface: Color(NSColor.windowBackgroundColor),
            surfaceElevated: Color(NSColor.controlBackgroundColor),
            surfaceCard: Color(white: 0.96),
            textPrimary: Color(white: 0.1),
            textSecondary: Color(white: 0.35),
            textTertiary: Color(white: 0.5),
            textMuted: Color(white: 0.6),
            border: Color.black.opacity(0.1),
            borderSubtle: Color.black.opacity(0.06),
            divider: Color.black.opacity(0.1),
            hover: Color.black.opacity(0.04),
            accent: Color.cyan
        )
    }

    /// Linear theme palette - Vercel/Linear inspired true black with subtle borders
    static func linear() -> ThemeColorPalette {
        ThemeColorPalette(
            surface: Color.black,
            surfaceElevated: Color(white: 0.04),
            surfaceCard: Color(white: 0.06),
            textPrimary: Color.white,
            textSecondary: Color(white: 0.6),
            textTertiary: Color(white: 0.45),
            textMuted: Color(white: 0.35),
            border: Color.white.opacity(0.08),
            borderSubtle: Color.white.opacity(0.05),
            divider: Color.white.opacity(0.08),
            hover: Color.white.opacity(0.06),
            accent: Color(red: 0.0, green: 0.83, blue: 1.0) // Linear cyan
        )
    }
}

// MARK: - Linear Theme Styling

/// Linear-specific styling utilities for Vercel/Linear-inspired design
enum LinearStyle {
    /// Subtle glow color for card borders
    static let glowColor = Color(red: 0.0, green: 0.83, blue: 1.0)

    /// Check if Linear theme is currently active
    static var isActive: Bool {
        SettingsManager.shared.isLinearTheme
    }

    /// Card border color - subtle white or accent glow on hover
    static func cardBorder(isHovered: Bool) -> Color {
        if isHovered {
            return glowColor.opacity(0.3)
        }
        return Color.white.opacity(0.08)
    }

    /// Card shadow for subtle glow effect
    static func cardShadow(isHovered: Bool) -> Color {
        if isHovered {
            return glowColor.opacity(0.15)
        }
        return Color.clear
    }

    /// Card shadow radius
    static func cardShadowRadius(isHovered: Bool) -> CGFloat {
        isHovered ? 12 : 0
    }
}

/// View modifier for Linear-style cards with glow effect
struct LinearCardStyle: ViewModifier {
    let isHovered: Bool
    var accentColor: Color = LinearStyle.glowColor

    func body(content: Content) -> some View {
        if LinearStyle.isActive {
            content
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(isHovered ? Color(white: 0.07) : Color(white: 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(
                            isHovered ? accentColor.opacity(0.4) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isHovered ? accentColor.opacity(0.2) : Color.clear,
                    radius: isHovered ? 16 : 0,
                    x: 0, y: 0
                )
        } else {
            content
        }
    }
}

/// View modifier for Linear-style section headers with subtle accent
struct LinearSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        if LinearStyle.isActive {
            content
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Color(white: 0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                )
        } else {
            content
        }
    }
}

extension View {
    /// Apply Linear-style card with glow effect on hover
    func linearCard(isHovered: Bool, accent: Color = LinearStyle.glowColor) -> some View {
        modifier(LinearCardStyle(isHovered: isHovered, accentColor: accent))
    }

    /// Apply Linear-style section background
    func linearSection() -> some View {
        modifier(LinearSectionStyle())
    }
}

// MARK: - Design (for Live HistoryView)

struct Design {
    static let fontXS = Font.system(size: 10, weight: .regular)
    static let fontXSMedium = Font.system(size: 10, weight: .medium)
    static let fontXSBold = Font.system(size: 10, weight: .semibold)

    static let fontSM = Font.system(size: 11, weight: .regular)
    static let fontSMMedium = Font.system(size: 11, weight: .medium)
    static let fontSMBold = Font.system(size: 11, weight: .semibold)

    static let fontBody = Font.system(size: 13, weight: .regular)
    static let fontBodyMedium = Font.system(size: 13, weight: .medium)
    static let fontBodyBold = Font.system(size: 13, weight: .semibold)

    static let fontTitle = Font.system(size: 15, weight: .medium)
    static let fontTitleBold = Font.system(size: 15, weight: .bold)

    static let fontHeadline = Font.system(size: 18, weight: .medium)

    // Use MidnightSurface colors for consistent dark theme
    static var background: Color { MidnightSurface.content }
    static var backgroundSecondary: Color { MidnightSurface.sidebar }
    static var backgroundTertiary: Color { MidnightSurface.elevated }

    static var foreground: Color { Color.primary }
    static var foregroundSecondary: Color { Color.secondary }
    static var foregroundMuted: Color { Color.secondary.opacity(0.7) }

    static var divider: Color { Color(NSColor.separatorColor) }
    static var accent: Color { Color.accentColor }
}

// MARK: - Reusable Components for HistoryView

struct SidebarSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(Design.fontXS)
                .foregroundColor(TalkieTheme.textMuted)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Design.fontXS)
                .foregroundColor(TalkieTheme.textPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(TalkieTheme.surfaceElevated)
        .cornerRadius(CornerRadius.xs)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Theme Observer for HistoryView

struct ThemeObserver: ViewModifier {
    @Environment(LiveSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .id("theme-\(settings.visualTheme.rawValue)-\(settings.appearanceMode.rawValue)-\(colorScheme)")
    }
}

extension View {
    /// Apply this modifier to views that need to react to theme changes
    func observeTheme() -> some View {
        modifier(ThemeObserver())
    }
}
