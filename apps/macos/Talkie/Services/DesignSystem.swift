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
import TalkieKit

// MARK: - Font Names (Central Definition)
/// All custom font names defined in one place.
/// Change here to update throughout the app.
enum FontName {
    // Geist by Vercel - Modern sans-serif for headers/UI
    static let geistRegular = "Geist-Regular"
    static let geistMedium = "Geist-Medium"
    static let geistSemiBold = "Geist-SemiBold"
    static let geistBold = "Geist-Bold"

    // GeistMono by Vercel - Monospace companion (alternative)
    static let geistMonoRegular = "GeistMono-Regular"
    static let geistMonoMedium = "GeistMono-Medium"

    // Monaspace Neon by GitHub - Texture-healing monospace
    // PRIMARY mono font for all content: transcripts, code, timestamps
    static let mono = "Monaspace Neon Var"
}

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
    /// 20pt - Card inset padding (2.5x grid) — standard padding inside cards
    static let cardInset: CGFloat = 20
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

// MARK: - Page Layout Constants
/// Standardized layout measurements for all page/screen content.
/// Uses 8pt grid values for consistent spacing across all views.
///
/// Usage:
///   .padding(.horizontal, PageLayout.horizontalPadding)
///   .padding(.top, PageLayout.topPadding)
///   VStack(spacing: PageLayout.sectionSpacing)
enum PageLayout {
    /// 44pt - Standard page header height (matches macOS toolbar conventions)
    static let headerHeight: CGFloat = 44
    /// Tight clearance below the chrome bar (TALKIE pill + shadow). The
    /// previous value (44+18=62) reserved a generous overlay footprint;
    /// the pill itself is short and the extra band read as empty space.
    static let headerOverlayClearance: CGFloat = 28
    /// 24pt - Horizontal padding for page content
    static let horizontalPadding: CGFloat = Spacing.xl
    /// 8pt - Top padding below navigation
    static let topPadding: CGFloat = Spacing.sm
    /// 24pt - Bottom padding for scroll content
    static let bottomPadding: CGFloat = Spacing.xl
    /// 16pt - Spacing between major sections
    static let sectionSpacing: CGFloat = Spacing.lg
    /// 24pt - Spacing between header and first content
    static let headerSpacing: CGFloat = Spacing.xl
    /// 1600pt - Detail bodies left-align by default; above this canvas
    /// width they re-center, since hugging the leading edge on giant
    /// monitors strands the body far from the masthead chrome.
    static let recenterAbove: CGFloat = 1600
}

// MARK: - Home Card Heights
/// Standard heights for home grid card rows (t-shirt sizes).
/// Cards in the same row share a height for visual alignment.
///
///   xs  (48pt)  - Action CTAs: icon + label, single row
///   sm  (80pt)  - Stats: number + label, compact
///   md  (280pt) - Content: widgets AND lists share this height
///
enum CardHeight {
    /// 48pt - Single-line CTAs (Record, Helpers, Workflows, Settings)
    static let xs: CGFloat = 48
    /// 80pt - Stat cards (number + label, compact)
    static let sm: CGFloat = 80
    /// 280pt - Content cards: widgets (top apps, shortcuts, activity) AND lists (recent memos/dictations)
    static let md: CGFloat = 280
}

// MARK: - Recordings Alignment Grid
/// Shared vertical rhythm for the recordings workspace:
/// sidebar brand header, list header/filter bar, and inspector header rows.
enum RecordingsHeaderLayout {
    /// Primary top band: TALKIE | Recordings | Detail title
    static let primaryBandHeight: CGFloat = PageLayout.headerHeight   // 44
    /// Secondary band: General | Filter chips | Detail metadata row
    static let secondaryBandHeight: CGFloat = 28
    /// Standard compact control height for pills/toggles in the top band
    static let controlHeight: CGFloat = 24
    /// Horizontal inset used by list header + filter bar
    static let horizontalInset: CGFloat = PageLayout.horizontalPadding
    /// Inspector top padding so first band aligns with list header band
    static let inspectorTopPadding: CGFloat = 0
}

// MARK: - Design Tokens (re-exported from TalkieKit)
// CornerRadius, BorderWidth, BorderOpacity are defined in TalkieKit.
// Re-export as typealiases so files in Talkie don't need explicit TalkieKit import.
typealias CornerRadius = TalkieKit.CornerRadius
typealias BorderWidth = TalkieKit.BorderWidth
typealias BorderOpacity = TalkieKit.BorderOpacity

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
    // Using Monaspace Neon for all content text (transcripts, etc.)
    /// 16pt Monaspace - Large body text
    static let bodyLarge = Font.custom(FontName.mono, size: 16)
    /// 14pt Monaspace - Standard body text (transcripts)
    static let bodyMedium = Font.custom(FontName.mono, size: 14)
    /// 12pt Monaspace - Compact body text
    static let bodySmall = Font.custom(FontName.mono, size: 12)

    // MARK: Label (UI chrome, navigation)
    /// 13pt medium - Large labels
    static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
    /// 11pt medium - Standard labels
    static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
    /// 10pt medium - Small labels
    static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)

    // MARK: Tech Labels (Section headers, status indicators)
    // Now using Monaspace Neon for all monospaced content
    /// 10pt Monaspace - Section headers (TRANSCRIPT, QUICK ACTIONS)
    static let techLabel = Font.custom(FontName.mono, size: 10)
    /// 9pt Monaspace - Metadata labels (dates, status)
    static let techLabelSmall = Font.custom(FontName.mono, size: 9)

    // MARK: Mono (Technical data, durations, counts)
    // Using Monaspace Neon - GitHub's texture-healing monospace
    /// 16pt Monaspace - Large technical values
    static let monoLarge = Font.custom(FontName.mono, size: 16)
    /// 14pt Monaspace - Standard technical values (transcripts)
    static let monoMedium = Font.custom(FontName.mono, size: 14)
    /// 12pt Monaspace - Small technical values (durations)
    static let monoSmall = Font.custom(FontName.mono, size: 12)
    /// 10pt Monaspace - Tiny technical values
    static let monoXSmall = Font.custom(FontName.mono, size: 10)
}

// MARK: - Geist Fonts (Custom Typography)
/// Geist by Vercel - Modern sans-serif for headers and UI
/// GeistMono - Monospace companion for code and technical content
/// Monaspace Neon - GitHub's texture-healing monospace (alternative)
///
/// Usage:
///   Text("Header").font(.geistHeadline)
///   Text("Code").font(.geistMono(size: 14))
///
extension Font {

    // MARK: Geist Sans (Headers, UI)

    /// Create a Geist font with specific size and weight
    /// Falls back to SF Pro if Geist isn't available
    static func geist(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .bold, .heavy, .black:
            fontName = FontName.geistBold
        case .semibold:
            fontName = FontName.geistSemiBold
        case .medium:
            fontName = FontName.geistMedium
        default:
            fontName = FontName.geistRegular
        }
        return .custom(fontName, size: size)
    }

    /// 32pt Geist Bold - Hero titles, app headers
    static let geistDisplay = Font.custom(FontName.geistBold, size: 32)

    /// 24pt Geist SemiBold - Page titles
    static let geistTitle = Font.custom(FontName.geistSemiBold, size: 24)

    /// 18pt Geist SemiBold - Section headers (H1)
    static let geistHeadline = Font.custom(FontName.geistSemiBold, size: 18)

    /// 15pt Geist Medium - Subsection headers (H2)
    static let geistSubheadline = Font.custom(FontName.geistMedium, size: 15)

    /// 13pt Geist Medium - Labels, navigation
    static let geistLabel = Font.custom(FontName.geistMedium, size: 13)

    /// 11pt Geist Regular - Small labels, metadata
    static let geistCaption = Font.custom(FontName.geistRegular, size: 11)

    // MARK: Geist Mono (Code, Technical)

    /// Create a GeistMono font with specific size (alternative to Monaspace)
    static func geistMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName = weight == .medium ? FontName.geistMonoMedium : FontName.geistMonoRegular
        return .custom(fontName, size: size)
    }

    /// 14pt GeistMono - Standard code/transcript text (alternative)
    static let geistMonoBody = Font.custom(FontName.geistMonoRegular, size: 14)

    /// 12pt GeistMono Medium - Technical values, timestamps (alternative)
    static let geistMonoSmall = Font.custom(FontName.geistMonoMedium, size: 12)

    /// 10pt GeistMono - Tiny technical values (alternative)
    static let geistMonoXSmall = Font.custom(FontName.geistMonoRegular, size: 10)

    // MARK: Monaspace Neon (Alternative Mono)

    /// Create a Monaspace Neon font (variable font, supports any weight)
    /// Features texture healing for improved monospace readability
    static func monaspace(size: CGFloat) -> Font {
        return .custom(FontName.mono, size: size)
    }

    /// 14pt Monaspace - Code with texture healing
    static let monaspaceBody = Font.custom(FontName.mono, size: 14)

    /// 12pt Monaspace - Small technical text
    static let monaspaceSmall = Font.custom(FontName.mono, size: 12)
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
    /// Subtle spring for hover micro-interactions
    static let microSpring = Animation.spring(response: 0.25, dampingFraction: 0.6)
}

// MARK: - Hover Effects (Subtle Micro-Interactions)

/// Subtle hover bounce effect for icons and small elements.
/// Very lightweight - uses simple transforms, no complex animations.
///
/// Usage:
///   Image(systemName: "calendar")
///       .hoverBounce()
///
///   // Or with custom intensity
///   Image(systemName: "flame.fill")
///       .hoverBounce(intensity: .medium)
///
struct HoverBounceModifier: ViewModifier {
    enum Intensity {
        case subtle   // 1pt lift, 1.02 scale
        case medium   // 2pt lift, 1.05 scale
        case playful  // 3pt lift, 1.08 scale

        var offset: CGFloat {
            switch self {
            case .subtle: return -1
            case .medium: return -2
            case .playful: return -3
            }
        }

        var scale: CGFloat {
            switch self {
            case .subtle: return 1.02
            case .medium: return 1.05
            case .playful: return 1.08
            }
        }
    }

    let intensity: Intensity
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .offset(y: isHovered ? intensity.offset : 0)
            .scaleEffect(isHovered ? intensity.scale : 1.0)
            .animation(TalkieAnimation.microSpring, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Subtle rotation wiggle effect for icons (like a gentle shake).
/// Use sparingly for playful elements.
///
/// Usage:
///   Image(systemName: "bell.fill")
///       .hoverWiggle()
///
struct HoverWiggleModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isHovered ? 8 : 0))
            .animation(
                isHovered ?
                    Animation.easeInOut(duration: 0.1).repeatCount(3, autoreverses: true) :
                    Animation.easeOut(duration: 0.15),
                value: isHovered
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Subtle glow/brightness effect for icons on hover.
/// Increases brightness slightly without adding blur.
///
/// Usage:
///   Image(systemName: "star.fill")
///       .hoverGlow()
///
struct HoverGlowModifier: ViewModifier {
    let color: Color?
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovered ? 0.1 : 0)
            .shadow(color: isHovered ? (color ?? .white).opacity(0.3) : .clear, radius: isHovered ? 4 : 0)
            .animation(TalkieAnimation.fast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Combined hover effect: bounce + brightness.
/// Use for primary interactive icons.
///
/// Usage:
///   Image(systemName: "play.fill")
///       .hoverLift()
///
struct HoverLiftModifier: ViewModifier {
    let intensity: HoverBounceModifier.Intensity
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .offset(y: isHovered ? intensity.offset : 0)
            .scaleEffect(isHovered ? intensity.scale : 1.0)
            .brightness(isHovered ? 0.05 : 0)
            .animation(TalkieAnimation.microSpring, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    /// Add subtle bounce effect on hover (icon lifts up slightly)
    func hoverBounce(intensity: HoverBounceModifier.Intensity = .subtle) -> some View {
        modifier(HoverBounceModifier(intensity: intensity))
    }

    /// Add subtle wiggle effect on hover (icon rotates back and forth)
    func hoverWiggle() -> some View {
        modifier(HoverWiggleModifier())
    }

    /// Add subtle glow effect on hover (icon brightens slightly)
    func hoverGlow(color: Color? = nil) -> some View {
        modifier(HoverGlowModifier(color: color))
    }

    /// Add combined lift effect on hover (bounce + brightness)
    func hoverLift(intensity: HoverBounceModifier.Intensity = .subtle) -> some View {
        modifier(HoverLiftModifier(intensity: intensity))
    }
}

// MARK: - Responsive Layout System
/// Centralized breakpoints and responsive helpers.
///
/// Usage:
///   ResponsiveView { sizeClass in
///       if sizeClass == .compact {
///           CompactLayout()
///       } else {
///           WideLayout()
///       }
///   }
///
/// Or with the environment:
///   @Environment(\.windowSizeClass) var sizeClass

/// Semantic window size classes
enum WindowSizeClass: String, CaseIterable {
    /// < 700px - Single column, stacked layouts, sheets instead of split views
    case compact
    /// 700-1000px - Two column layouts, sidebars visible
    case medium
    /// 1000-1400px - Full three-column layouts, all panels visible
    case wide
    /// > 1400px - Spacious layouts, extra whitespace, larger content areas
    case spacious

    /// Human-readable description
    var description: String {
        switch self {
        case .compact: return "Compact (<700)"
        case .medium: return "Medium (700-1000)"
        case .wide: return "Wide (1000-1400)"
        case .spacious: return "Spacious (>1400)"
        }
    }
}

/// Centralized breakpoint definitions
enum Breakpoint {
    /// 700px - Below this: single column, sheets
    static let compact: CGFloat = 700
    /// 1000px - Below this: two columns, above: three columns
    static let medium: CGFloat = 1000
    /// 1400px - Above this: spacious mode with extra whitespace
    static let wide: CGFloat = 1400

    /// Get size class for a given width
    static func sizeClass(for width: CGFloat) -> WindowSizeClass {
        switch width {
        case ..<compact: return .compact
        case ..<medium: return .medium
        case ..<wide: return .wide
        default: return .spacious
        }
    }

    /// Check if width is at least a given breakpoint
    static func isAtLeast(_ breakpoint: CGFloat, width: CGFloat) -> Bool {
        width >= breakpoint
    }
}

/// Column width presets for consistent layouts
enum ColumnWidth {
    /// Sidebar column (navigation)
    enum Sidebar {
        static let min: CGFloat = 160
        static let ideal: CGFloat = 200
        static let max: CGFloat = 280
    }

    /// List column (memo list, model list)
    enum List {
        static let min: CGFloat = 220
        static let ideal: CGFloat = 300
        static let max: CGFloat = 400
    }

    /// Detail/content column
    enum Detail {
        static let min: CGFloat = 400
        static let ideal: CGFloat = 600
        static let max: CGFloat = .infinity
    }

    /// Inspector panel (right sidebar)
    enum Inspector {
        static let min: CGFloat = 280
        static let ideal: CGFloat = 320
        static let max: CGFloat = 400
    }
}

/// Environment key for window size class
private struct WindowSizeClassKey: EnvironmentKey {
    static let defaultValue: WindowSizeClass = .wide
}

extension EnvironmentValues {
    var windowSizeClass: WindowSizeClass {
        get { self[WindowSizeClassKey.self] }
        set { self[WindowSizeClassKey.self] = newValue }
    }
}

/// A container view that provides responsive size class to its content
struct ResponsiveView<Content: View>: View {
    let content: (WindowSizeClass) -> Content

    init(@ViewBuilder content: @escaping (WindowSizeClass) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let sizeClass = Breakpoint.sizeClass(for: geometry.size.width)
            content(sizeClass)
                .environment(\.windowSizeClass, sizeClass)
        }
    }
}

/// View modifier that injects window size class into environment
struct ResponsiveModifier: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let sizeClass = Breakpoint.sizeClass(for: geometry.size.width)
            content
                .environment(\.windowSizeClass, sizeClass)
        }
    }
}

extension View {
    /// Make this view responsive by injecting window size class into environment
    func responsive() -> some View {
        modifier(ResponsiveModifier())
    }

    /// Conditionally show this view based on size class
    @ViewBuilder
    func visible(when sizeClasses: WindowSizeClass...) -> some View {
        modifier(VisibleWhenModifier(sizeClasses: Set(sizeClasses)))
    }

    /// Hide this view in compact mode (useful for sidebars)
    @ViewBuilder
    func hideInCompact() -> some View {
        modifier(HideInCompactModifier())
    }
}

private struct VisibleWhenModifier: ViewModifier {
    let sizeClasses: Set<WindowSizeClass>
    @Environment(\.windowSizeClass) var currentSizeClass

    func body(content: Content) -> some View {
        if sizeClasses.contains(currentSizeClass) {
            content
        }
    }
}

private struct HideInCompactModifier: ViewModifier {
    @Environment(\.windowSizeClass) var sizeClass

    func body(content: Content) -> some View {
        if sizeClass != .compact {
            content
        }
    }
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

// MARK: - Page Header Component

/// Reusable page header for main screens (H1 equivalent)
/// Uses SF Pro 20pt Light for clean, native macOS typography
/// Usage: PageHeader("Memos") or PageHeader("Recordings", subtitle: "All your voice recordings")
///
/// Typography: 20pt light matches TitleWithToggle for visual consistency across all page headers
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    // Standard page title size - matches TitleWithToggle
    private static let titleSize: CGFloat = 20

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        if SettingsManager.shared.isScopeTheme {
            // Compact Scope variant — fits inside TalkiePage's 44pt bar.
            // PhosphorDot + eyebrow lockup, two-tone serif title, optional
            // mono subtitle. Full hero (with ScopeDivider) lives in
            // SettingsPageHeader / SettingsPageContainer where the header
            // band is flexible.
            CompactScopePageHeader(title: title, subtitle: subtitle)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                TalkieText(title, style: .pageTitle)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
        }
    }
}

/// Single-line Scope-flavored PageHeader. Cormorant serif title, sized to
/// fit inside PageLayout.headerHeight (44pt). This is THE source of page
/// identity in Scope — in-page heroes must not duplicate it.
struct CompactScopePageHeader: View {
    let title: String
    let subtitle: String?

    private static func display(size: CGFloat) -> Font {
        for name in ["CormorantGaramond-Regular", "Cormorant Garamond", "CormorantGaramond"] {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(CompactScopePageHeader.display(size: 24))
                .foregroundColor(ScopeInk.primary)
                .tracking(-0.3)
                .lineLimit(1)

            if let subtitle = subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
                    .padding(.bottom, 2)
            }
        }
    }
}

/// Reusable header for detail panes (H1.5 equivalent - used at top of inspector/detail views)
/// Usage: DetailHeader("Recording", editAction: { ... })
struct DetailHeader: View {
    let title: String
    var editAction: (() -> Void)? = nil
    var isEditing: Bool = false
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    init(_ title: String, editAction: (() -> Void)? = nil) {
        self.title = title
        self.editAction = editAction
    }

    init(_ title: String, isEditing: Bool, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.isEditing = isEditing
        self.onSave = onSave
        self.onCancel = onCancel
        self.editAction = nil
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.current.foregroundSecondary)
                .textCase(.uppercase)
                .tracking(Tracking.wide)

            Spacer()

            if isEditing {
                HStack(spacing: Spacing.sm) {
                    Button("Cancel") { onCancel?() }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Button("Save") { onSave?() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else if let editAction = editAction {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
                .help("Edit")
            }
        }
    }
}

/// Reusable section header for detail views (H2 equivalent)
/// Usage: DetailSectionHeader("Transcript") or DetailSectionHeader("METADATA", uppercase: true)
struct DetailSectionHeader: View {
    let title: String
    var uppercase: Bool = false

    init(_ title: String, uppercase: Bool = false) {
        self.title = title
        self.uppercase = uppercase
    }

    var body: some View {
        Text(uppercase ? title.uppercased() : title)
            .font(.system(size: uppercase ? 11 : 14, weight: uppercase ? .semibold : .semibold))
            .tracking(uppercase ? Tracking.normal : 0)
            .foregroundColor(Theme.current.foregroundSecondary)
    }
}

// MARK: - Settings Page Components

// MARK: Header Layout Constants
/// Standardized header dimensions for consistent alignment across all three columns
/// Primary line: TALKIE | SETTINGS | <Page Title> - all bottom-aligned (text only, no icons)
/// Secondary line: Category labels and descriptions
enum SettingsHeaderLayout {
    /// Height of the primary header line (wordmark-scale: 18pt small-caps in 20pt band)
    static let primaryLineHeight: CGFloat = 20
    /// Top padding from window edge to primary line top (aligns with H1 guide at ~15pt)
    static let topPadding: CGFloat = 15
    /// Space between primary and secondary lines
    static let lineGap: CGFloat = 6
    /// Bottom padding after header area before first content item
    static let bottomPadding: CGFloat = 10

    /// Shared header font — same scale as wordmark but distinct (Medium, no small-caps)
    static var headerFont: Font {
        Font.system(size: 18, weight: .medium)
    }
    /// Shared header tracking
    static let headerTracking: CGFloat = 0.3
}

/// Standardized header for all settings pages
/// Uses baseline-aligned primary line (text only) and separate secondary description line
struct SettingsPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    /// Display title in natural case (capitalize first letter of each word)
    private var displayTitle: String {
        title.localizedCapitalized
    }

    var body: some View {
        if SettingsManager.shared.isScopeTheme {
            ScopePageHeader(icon: icon, title: title, subtitle: subtitle)
        } else {
            TalkieText(displayTitle, style: .settingsTitle)
                .frame(height: SettingsHeaderLayout.primaryLineHeight, alignment: .center)
        }
    }
}

/// Container for settings page content with consistent background and sticky header
/// Uses SettingsHeaderLayout for consistent alignment with sidebar columns
struct SettingsPageContainer<Header: View, Content: View>: View {
    let header: Header
    let content: Content

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    private var isScope: Bool { SettingsManager.shared.isScopeTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sticky header area - uses standardized layout for cross-column alignment
            header
                .padding(.horizontal, isScope ? 28 : Spacing.lg)
                .padding(.top, isScope ? 22 : SettingsHeaderLayout.topPadding)
                .padding(.bottom, isScope ? 14 : Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(isScope ? ScopeCanvas.canvas : Theme.current.background)

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    content
                }
                .padding(isScope ? 28 : Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minHeight: 500, maxHeight: .infinity)
        .background(isScope ? ScopeCanvas.canvas : Theme.current.background)
    }
}

// MARK: - Scope Page Header

/// Cream-phosphor settings page header. Eyebrow with leading PhosphorDot,
/// two-tone serif title (Cormorant), mono subtitle, ScopeDivider rule.
/// Replaces the standard icon-title-subtitle layout when isScopeTheme.
struct ScopePageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    private static let regularCandidates = [
        "CormorantGaramond-Regular",
        "Cormorant Garamond",
        "CormorantGaramond",
    ]
    private static let mediumCandidates = [
        "CormorantGaramond-Medium",
        "Cormorant Garamond Medium",
    ]

    /// Display font matched to other Scope screens (ScopeHomeView /
    /// ScopeContextView). Tries Cormorant Garamond, falls back to system
    /// serif so this works even when the homepage font isn't installed.
    private static func display(size: CGFloat, medium: Bool = false) -> Font {
        for name in (medium ? mediumCandidates : regularCandidates) {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: medium ? .medium : .regular, design: .serif)
    }

    /// Split the title on the first space for the two-tone treatment.
    /// Single-word titles render the entire word in primary ink.
    private var titleParts: (head: String, tail: String?) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if let spaceIdx = trimmed.firstIndex(of: " ") {
            let head = String(trimmed[..<spaceIdx])
            let tail = String(trimmed[trimmed.index(after: spaceIdx)...])
                .trimmingCharacters(in: .whitespaces)
            return (head, tail.isEmpty ? nil : tail)
        }
        return (trimmed, nil)
    }

    @ViewBuilder
    private var headline: some View {
        let parts = titleParts
        if let tail = parts.tail {
            (
                Text(parts.head.capitalized + " ")
                    .foregroundColor(ScopeInk.primary)
                +
                Text(tail.capitalized)
                    .foregroundColor(ScopeInk.muted)
                    .italic()
            )
            .font(ScopePageHeader.display(size: 32))
            .tracking(-0.4)
        } else {
            Text(parts.head.capitalized)
                .font(ScopePageHeader.display(size: 32))
                .foregroundColor(ScopeInk.primary)
                .tracking(-0.4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Eyebrow row: phosphor dot + uppercase tracked label
            HStack(spacing: 8) {
                PhosphorDot(color: ScopeAmber.solid, size: 5)
                Text(title.uppercased())
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 3, opacity: 0.28)
            }

            headline

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(ScopeInk.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640, alignment: .leading)
            }

            ScopeDivider().padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.bottom, Spacing.sm) // Small breathing room from bottom
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
        debugInfo: (() -> [String: String])? = nil,  // Accept but ignore in release
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
            .liquidGlassCard(
                cornerRadius: cornerRadius,
                fallbackFill: Theme.current.surface2,
                fallbackStroke: Theme.current.divider
            )
    }
}

extension View {
    /// Apply settings section card styling with Liquid Glass
    func settingsSectionCard(padding: CGFloat = Spacing.lg, cornerRadius: CGFloat = CornerRadius.card) -> some View {
        modifier(SettingsSectionCard(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Settings Tab Bar

/// Reusable tabbed settings panel — tab bar sits flush above content in a unified card.
/// Use for any settings page that has grouped sections (Surface, Capture, etc.).
///
/// Usage:
/// ```swift
/// SettingsTabSection(selection: $tab, tabs: MyTab.allCases) { tab in
///     tab.label // or custom view
/// } content: {
///     switch tab { ... }
/// }
/// ```
struct SettingsTabSection<Tab: Hashable & Identifiable, TabLabel: View, Content: View>: View {
    @Binding var selection: Tab
    let tabs: [Tab]
    @ViewBuilder let tabLabel: (Tab) -> TabLabel
    @ViewBuilder let content: () -> Content

    @Namespace private var tabIndicator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
                    } label: {
                        tabLabel(tab)
                            .font(Theme.current.fontSM.weight(selection == tab ? .semibold : .regular))
                            .foregroundColor(selection == tab ? Theme.current.foreground : Theme.current.foregroundMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if selection == tab {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.08))
                                        .matchedGeometryEffect(id: "settingsTab", in: tabIndicator)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)

            // Divider between tabs and content
            Rectangle()
                .fill(Theme.current.divider)
                .frame(height: 1)
                .padding(.top, Spacing.xs)

            // Content
            content()
                .padding(Spacing.lg)
        }
        .settingsSectionCard(padding: 0)
    }
}

// MARK: - Talkie Decision Bar

/// Declares where a decision bar should appear.
/// Current implementation anchors to the footer for all placements.
enum TalkieDecisionBarPlacement: String, Sendable {
    case footer
    case header
}

/// Reusable primary/secondary decision bar.
/// API includes placement for forward compatibility, but currently renders at one anchor point.
struct TalkieDecisionBar: View {
    let tertiaryTitle: String?
    let tertiaryRole: ButtonRole?
    let onTertiary: (() -> Void)?
    let primaryTitle: String
    let secondaryTitle: String
    let helperText: String?
    let isPrimaryEnabled: Bool
    let placement: TalkieDecisionBarPlacement
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    init(
        tertiaryTitle: String? = nil,
        tertiaryRole: ButtonRole? = nil,
        onTertiary: (() -> Void)? = nil,
        primaryTitle: String,
        secondaryTitle: String = "Cancel",
        helperText: String? = nil,
        isPrimaryEnabled: Bool = true,
        placement: TalkieDecisionBarPlacement = .footer,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) {
        self.tertiaryTitle = tertiaryTitle
        self.tertiaryRole = tertiaryRole
        self.onTertiary = onTertiary
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.helperText = helperText
        self.isPrimaryEnabled = isPrimaryEnabled
        self.placement = placement
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: Spacing.sm) {
                if let tertiaryTitle, let onTertiary {
                    Button(tertiaryTitle, role: tertiaryRole, action: onTertiary)
                }

                Spacer(minLength: Spacing.sm)

                Button(secondaryTitle, action: onSecondary)
                    .keyboardShortcut(.escape)

                Button(primaryTitle, action: onPrimary)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isPrimaryEnabled)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.surface1)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.current.divider)
                .frame(height: 1)
        }
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

    // MARK: - Activity
    let activityHeatmapColor: Color

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
    @MainActor static var current: Theme = Theme.compute()

    /// Configure design tokens during app initialization.
    /// Only sets up CornerRadius and BorderWidth - does NOT touch Theme.current
    /// to avoid recursive lock when SettingsManager is still initializing.
    /// Theme.current will be computed lazily on first access after SettingsManager is ready.
    static func configure(cornerMultiplier: CGFloat, borderMultiplier: CGFloat) {
        CornerRadius.recalculate(multiplier: cornerMultiplier)
        BorderWidth.recalculate(multiplier: borderMultiplier)
        // Note: Do NOT access Theme.current here - it triggers compute() which needs SettingsManager.shared
    }

    /// Refresh theme from current SettingsManager values. Use when settings change at runtime.
    @MainActor
    static func refresh() {
        CornerRadius.recalculate(multiplier: SettingsManager.shared.currentCornerRadiusMultiplier)
        BorderWidth.recalculate(multiplier: SettingsManager.shared.currentBorderWidth)
        current = compute()
    }

    /// Compute theme from current SettingsManager values
    @MainActor
    private static func compute() -> Theme {
        let settings = SettingsManager.shared
        let useLightFonts = settings.useLightFonts
        let regularWeight: Font.Weight = useLightFonts ? .light : .regular
        let mediumWeight: Font.Weight = useLightFonts ? .regular : .medium
        let boldWeight: Font.Weight = useLightFonts ? .medium : .semibold
        let strongWeight: Font.Weight = useLightFonts ? .semibold : .bold
        let displayWeight: Font.Weight = useLightFonts ? .light : .regular

        return Theme(
            // UI Fonts
            fontXS: settings.themedFont(baseSize: 10, weight: regularWeight),
            fontXSMedium: settings.themedFont(baseSize: 10, weight: mediumWeight),
            fontXSBold: settings.themedFont(baseSize: 10, weight: boldWeight),
            fontSM: settings.themedFont(baseSize: 11, weight: regularWeight),
            fontSMMedium: settings.themedFont(baseSize: 11, weight: mediumWeight),
            fontSMBold: settings.themedFont(baseSize: 11, weight: boldWeight),
            fontBody: settings.themedFont(baseSize: 13, weight: regularWeight),
            fontBodyMedium: settings.themedFont(baseSize: 13, weight: mediumWeight),
            fontBodyBold: settings.themedFont(baseSize: 13, weight: boldWeight),
            fontTitle: settings.themedFont(baseSize: 15, weight: regularWeight),
            fontTitleMedium: settings.themedFont(baseSize: 15, weight: mediumWeight),
            fontTitleBold: settings.themedFont(baseSize: 15, weight: strongWeight),
            fontHeadline: settings.themedFont(baseSize: 18, weight: regularWeight),
            fontHeadlineMedium: settings.themedFont(baseSize: 18, weight: mediumWeight),
            fontHeadlineBold: settings.themedFont(baseSize: 18, weight: strongWeight),
            fontDisplay: settings.themedFont(baseSize: 32, weight: displayWeight),
            fontDisplayMedium: settings.themedFont(baseSize: 32, weight: mediumWeight),

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
            surfaceInfo: settings.surfaceInfo,

            // Activity
            activityHeatmapColor: Color(red: 0.2, green: 0.8, blue: 0.7)
        )
    }
}

// MARK: - TalkieTheme (for Live UI)
// Uses system-adaptive colors that automatically respond to light/dark mode

@MainActor
enum TalkieTheme {
    // System backgrounds - automatically adapt to light/dark mode
    // Technical theme overrides these with true blacks
    static var background: Color {
        TechnicalStyle.isActive ? TechnicalStyle.surface0 : Color(NSColor.windowBackgroundColor)
    }
    static var secondaryBackground: Color {
        TechnicalStyle.isActive ? TechnicalStyle.surface1 : Color(NSColor.controlBackgroundColor)
    }
    static var tertiaryBackground: Color {
        TechnicalStyle.isActive ? TechnicalStyle.surface2 : Color(NSColor.underPageBackgroundColor)
    }

    // Adaptive surface colors using NSColor which automatically adapts
    // Technical theme uses pure blacks
    static var surface: Color {
        TechnicalStyle.isActive ? TechnicalStyle.surface0 : Color(NSColor.windowBackgroundColor)
    }

    static var surfaceElevated: Color {
        TechnicalStyle.isActive ? TechnicalStyle.surface1 : Color(NSColor.controlBackgroundColor)
    }

    static var surfaceCard: Color {
        TechnicalStyle.isActive ? TechnicalStyle.surface1 : Color(NSColor.controlBackgroundColor)
    }

    // Adaptive text colors
    // Technical theme uses high-contrast whites
    static var textPrimary: Color {
        TechnicalStyle.isActive ? TechnicalStyle.textPrimary : Color(NSColor.labelColor)
    }

    static var textSecondary: Color {
        TechnicalStyle.isActive ? TechnicalStyle.textSecondary : Color(NSColor.secondaryLabelColor)
    }

    static var textTertiary: Color {
        TechnicalStyle.isActive ? TechnicalStyle.textTertiary : Color(NSColor.tertiaryLabelColor)
    }

    static var textMuted: Color {
        TechnicalStyle.isActive ? TechnicalStyle.textMuted : Color(NSColor.tertiaryLabelColor)
    }

    // Adaptive border/divider colors
    // Technical theme uses smart borders (subtle gradation from surface)
    static var border: Color {
        TechnicalStyle.isActive ? TechnicalStyle.borderLevel1 : Color(NSColor.separatorColor)
    }

    static var borderSubtle: Color {
        TechnicalStyle.isActive ? TechnicalStyle.borderLevel0 : Color(NSColor.separatorColor).opacity(0.5)
    }

    static var divider: Color {
        TechnicalStyle.isActive ? TechnicalStyle.borderLevel1 : Color(NSColor.separatorColor)
    }

    // Hover state
    static var hover: Color {
        TechnicalStyle.isActive ? TechnicalStyle.surfaceHover(level: 0) : Color(NSColor.unemphasizedSelectedContentBackgroundColor)
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

// MARK: - Technical Theme Styling

/// Technical theme styling utilities - V0/Vercel-inspired flat design
/// No glows, no gradients, just subtle gradation borders
@MainActor
enum TechnicalStyle {
    /// Check if Technical theme is currently active
    static var isActive: Bool {
        SettingsManager.shared.isTechnicalTheme
    }

    private static var isDark: Bool {
        SettingsManager.shared.isDarkMode
    }

    // MARK: - Smart Borders (subtle gradation from surface)

    /// Border color that's a subtle step lighter/darker than a given surface
    static func smartBorder(surfaceWhite: CGFloat, delta: CGFloat = 0.04) -> Color {
        if isDark {
            return Color(white: min(surfaceWhite + delta, 1.0))
        } else {
            return Color(white: max(surfaceWhite - delta, 0.0))
        }
    }

    private static let darkSurfaceWhites: [CGFloat] = [0.0, 0.04, 0.06, 0.08]
    private static let lightSurfaceWhites: [CGFloat] = [1.0, 0.98, 0.96, 0.94]
    private static let darkHoverSurfaceWhites: [CGFloat] = [0.03, 0.06, 0.08, 0.10]
    private static let lightHoverSurfaceWhites: [CGFloat] = [0.97, 0.95, 0.93, 0.91]

    private static func surfaceWhite(level: Int, hovered: Bool = false) -> CGFloat {
        let palette = if hovered {
            isDark ? darkHoverSurfaceWhites : lightHoverSurfaceWhites
        } else {
            isDark ? darkSurfaceWhites : lightSurfaceWhites
        }
        return palette[min(level, palette.count - 1)]
    }

    /// Surface level borders
    static var borderLevel0: Color { smartBorder(surfaceWhite: surfaceWhite(level: 0)) }
    static var borderLevel1: Color { smartBorder(surfaceWhite: surfaceWhite(level: 1)) }
    static var borderLevel2: Color { smartBorder(surfaceWhite: surfaceWhite(level: 2)) }
    static var borderLevel3: Color { smartBorder(surfaceWhite: surfaceWhite(level: 3)) }

    /// Hover state border
    static func borderHover(baseLevel: Int) -> Color {
        smartBorder(surfaceWhite: surfaceWhite(level: baseLevel, hovered: true), delta: 0.05)
    }

    // MARK: - Surface Colors

    static var surface0: Color { Color(white: surfaceWhite(level: 0)) }
    static var surface1: Color { Color(white: surfaceWhite(level: 1)) }
    static var surface2: Color { Color(white: surfaceWhite(level: 2)) }
    static var surface3: Color { Color(white: surfaceWhite(level: 3)) }

    /// Hover background - subtle lift
    static func surfaceHover(level: Int) -> Color {
        Color(white: surfaceWhite(level: level, hovered: true))
    }

    // MARK: - Typography Colors

    static var textPrimary: Color { isDark ? Color.white : Color(white: 0.06) }
    static var textSecondary: Color { isDark ? Color(white: 0.60) : Color(white: 0.35) }
    static var textTertiary: Color { isDark ? Color(white: 0.45) : Color(white: 0.50) }
    static var textMuted: Color { isDark ? Color(white: 0.35) : Color(white: 0.55) }

    // MARK: - Accent (subtle, muted)

    static var accent: Color { isDark ? Color(white: 0.70) : Color(white: 0.30) }
    static var accentSubtle: Color { isDark ? Color(white: 0.50) : Color(white: 0.50) }

    // MARK: - Matte Highlight (subtle top-edge light reflection)

    static func matteHighlight(surfaceLevel: Int) -> LinearGradient {
        if isDark {
            let topOpacity: CGFloat = surfaceLevel == 0 ? 0.06 : 0.04
            return LinearGradient(
                colors: [Color.white.opacity(topOpacity), Color.white.opacity(0)],
                startPoint: .top, endPoint: .center
            )
        } else {
            let topOpacity: CGFloat = surfaceLevel == 0 ? 0.04 : 0.02
            return LinearGradient(
                colors: [Color.black.opacity(topOpacity), Color.black.opacity(0)],
                startPoint: .top, endPoint: .center
            )
        }
    }

    /// Inner highlight for matte effect
    static func matteInnerHighlight(height: CGFloat = 1) -> some View {
        VStack(spacing: 0) {
            (isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                .frame(height: height)
            Spacer()
        }
    }
}

// Backwards compatibility alias
typealias LinearStyle = TechnicalStyle

/// View modifier for Technical-style cards with subtle gradation borders
struct TechnicalCardStyle: ViewModifier {
    let isHovered: Bool
    let surfaceLevel: Int

    init(isHovered: Bool, surfaceLevel: Int = 1) {
        self.isHovered = isHovered
        self.surfaceLevel = surfaceLevel
    }

    func body(content: Content) -> some View {
        if TechnicalStyle.isActive {
            let radius = CornerRadius.sm * (SettingsManager.shared.currentCornerRadiusMultiplier)
            let surfaces = [TechnicalStyle.surface0, TechnicalStyle.surface1, TechnicalStyle.surface2, TechnicalStyle.surface3]
            let surface = surfaces[min(surfaceLevel, surfaces.count - 1)]
            let hoverSurface = TechnicalStyle.surfaceHover(level: surfaceLevel)

            let borders = [TechnicalStyle.borderLevel0, TechnicalStyle.borderLevel1, TechnicalStyle.borderLevel2, TechnicalStyle.borderLevel3]
            let border = borders[min(surfaceLevel, borders.count - 1)]
            let hoverBorder = TechnicalStyle.borderHover(baseLevel: surfaceLevel)

            let borderWidth = SettingsManager.shared.currentBorderWidth

            content
                .background(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(isHovered ? hoverSurface : surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(
                            isHovered ? hoverBorder : border,
                            lineWidth: borderWidth
                        )
                )
        } else {
            content
        }
    }
}

// Backwards compatibility
typealias LinearCardStyle = TechnicalCardStyle

/// View modifier for Technical-style section headers
struct TechnicalSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        if TechnicalStyle.isActive {
            let radius = CornerRadius.sm * (SettingsManager.shared.currentCornerRadiusMultiplier)
            let borderWidth = SettingsManager.shared.currentBorderWidth
            content
                .background(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(TechnicalStyle.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: radius)
                                .strokeBorder(TechnicalStyle.borderLevel1, lineWidth: borderWidth)
                        )
                )
        } else {
            content
        }
    }
}

// Backwards compatibility
typealias LinearSectionStyle = TechnicalSectionStyle

extension View {
    /// Apply Technical-style card with subtle gradation border
    func technicalCard(isHovered: Bool, surfaceLevel: Int = 1) -> some View {
        modifier(TechnicalCardStyle(isHovered: isHovered, surfaceLevel: surfaceLevel))
    }

    /// Apply Technical-style section background
    func technicalSection() -> some View {
        modifier(TechnicalSectionStyle())
    }

    /// Apply matte finish with subtle top-edge highlight
    /// EDC gear aesthetic - like light catching machined aluminum
    @ViewBuilder
    func matteFinish(surfaceLevel: Int = 1, cornerRadius: CGFloat? = nil) -> some View {
        if TechnicalStyle.isActive {
            let radius = cornerRadius ?? (CornerRadius.sm * SettingsManager.shared.currentCornerRadiusMultiplier)
            self
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(TechnicalStyle.matteHighlight(surfaceLevel: surfaceLevel))
                        .allowsHitTesting(false)
                )
        } else {
            self
        }
    }

    /// Full EDC-style card: surface + border + matte highlight
    /// Use for primary interactive elements
    @ViewBuilder
    func edcCard(isHovered: Bool, surfaceLevel: Int = 1) -> some View {
        self
            .technicalCard(isHovered: isHovered, surfaceLevel: surfaceLevel)
            .matteFinish(surfaceLevel: surfaceLevel)
    }

    // Backwards compatibility
    func linearCard(isHovered: Bool, accent: Color = .accentColor) -> some View {
        technicalCard(isHovered: isHovered, surfaceLevel: 1)
    }

    func linearSection() -> some View {
        technicalSection()
    }
}

/// Modifier that uses Technical flat card style or falls back to liquidGlassCard
/// Use this for cards that should adapt to Technical theme
struct TechnicalCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var surfaceLevel: Int

    init(cornerRadius: CGFloat = CornerRadius.card, surfaceLevel: Int = 1) {
        self.cornerRadius = cornerRadius
        self.surfaceLevel = surfaceLevel
    }

    func body(content: Content) -> some View {
        if TechnicalStyle.isActive {
            let surfaces = [TechnicalStyle.surface0, TechnicalStyle.surface1, TechnicalStyle.surface2, TechnicalStyle.surface3]
            let surface = surfaces[min(surfaceLevel, surfaces.count - 1)]
            let border = TechnicalStyle.borderLevel1
            let borderWidth = SettingsManager.shared.currentBorderWidth

            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(border, lineWidth: borderWidth)
                )
        } else {
            content
                .liquidGlassCard(
                    cornerRadius: cornerRadius,
                    depth: .subtle,
                    fallbackFill: Theme.current.surface2,
                    fallbackStroke: Theme.current.divider
                )
        }
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

    // Mirror the active theme instead of pinning legacy consumers to midnight surfaces.
    @MainActor static var background: Color { Theme.current.background }
    @MainActor static var backgroundSecondary: Color { Theme.current.backgroundSecondary }
    @MainActor static var backgroundTertiary: Color { Theme.current.backgroundTertiary }

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
    @Environment(AgentSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .refreshThemeOnAppearanceChange()
            .id("theme-\(settings.visualTheme.rawValue)-\(settings.appearanceMode.rawValue)-\(colorScheme)")
    }
}

struct ThemeRefreshModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var refreshTick = 0

    func body(content: Content) -> some View {
        let _ = refreshTick

        content
            .onAppear {
                Theme.refresh()
                refreshTick &+= 1
            }
            .onChange(of: colorScheme) { _, _ in
                Theme.refresh()
                refreshTick &+= 1
            }
    }
}

extension View {
    func refreshThemeOnAppearanceChange() -> some View {
        modifier(ThemeRefreshModifier())
    }

    /// Apply this modifier to views that need to react to theme changes
    func observeTheme() -> some View {
        modifier(ThemeObserver())
    }
}

// MARK: - Stage Center

enum StageCoordinateSpace {
    static let name = "talkie_stage"
}

private struct StageCenterKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var stageCenterX: CGFloat? {
        get { self[StageCenterKey.self] }
        set { self[StageCenterKey.self] = newValue }
    }
}

extension View {
    func stageContainer() -> some View {
        modifier(StageContainerModifier())
    }

    func stageCentered() -> some View {
        modifier(StageCenteredModifier())
    }
}

private struct StageContainerModifier: ViewModifier {
    @State private var stageWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: StageCoordinateSpace.name)
            .overlay(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { stageWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in stageWidth = w }
                }
            )
            .environment(\.stageCenterX, stageWidth > 0 ? stageWidth / 2 : nil)
    }
}

private struct StageCenteredModifier: ViewModifier {
    @Environment(\.stageCenterX) private var stageCenterX
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size, initial: true) { _, _ in
                            recalculate(geo: geo)
                        }
                        .onChange(of: stageCenterX) { _, _ in
                            recalculate(geo: geo)
                        }
                }
            )
            .offset(x: offset)
    }

    private func recalculate(geo: GeometryProxy) {
        guard let stageCenter = stageCenterX else {
            if offset != 0 { offset = 0 }
            return
        }
        let localFrame = geo.frame(in: .named(StageCoordinateSpace.name))
        let newOffset = stageCenter - localFrame.midX
        if abs(newOffset - offset) > 0.5 {
            offset = newOffset
        }
    }
}
