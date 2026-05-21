//
//  ScopeComponents.swift
//  TalkieKit
//
//  Small reusable shapes drawn from the oscilloscope vocabulary on
//  usetalkie.com. Each component is a thin convenience over native
//  SwiftUI — the goal is to keep the *vocabulary* portable, not to
//  hide structure behind heavy abstractions.
//
//  Pairs with ScopeDesign.swift for tokens.
//

import SwiftUI

// MARK: - Graticule background

/// Cross-hatched grid background — the "oscilloscope screen" texture.
/// Drawn with a Canvas at a fixed grid pitch and trace-faint stroke.
///
/// Use as a `.background` or in a ZStack behind content. The grid is
/// non-interactive and respects accessibility (skipped under reduce
/// motion / transparency? — no, it's static, so always rendered).
public struct GraticuleBackground: View {
    /// Distance between gridlines in points. 24pt = fine (Security
    /// panel etc.), 48pt = section background.
    public let pitch: CGFloat
    /// Stroke color — defaults to `ScopeTrace.faint`.
    public let color: Color
    /// Overall opacity multiplier — section graticules typically run
    /// 0.30–0.55 in the homepage CSS.
    public let opacity: Double

    public init(
        pitch: CGFloat = 48,
        color: Color = ScopeTrace.faint,
        opacity: Double = 0.40
    ) {
        self.pitch = pitch
        self.color = color
        self.opacity = opacity
    }

    public var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += pitch
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += pitch
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1)
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Eyebrow

/// Uppercase caption — the homepage's section header pattern
/// (`OWNERSHIP`, `CAPTURE MODES`).
public struct Eyebrow: View {
    public let text: String
    public let color: Color
    public let glow: Bool

    public init(
        _ text: String,
        color: Color = ScopeAmber.solid,
        glow: Bool = true
    ) {
        self.text = text
        self.color = color
        self.glow = glow
    }

    public var body: some View {
        Text(text.uppercased())
            .font(ScopeType.eyebrow)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(color)
            .modifier(PhosphorGlow(color: color, enabled: glow, radius: 4, opacity: 0.32))
    }
}

// MARK: - ChannelLabel

/// Tiny bordered uppercase tag — the homepage's pin badge pattern
/// (`U1`, `CH-01`, `AG-01`). Rectangular, hairline stroke, no fill.
public struct ChannelLabel: View {
    public let text: String
    public let color: Color
    public let strokeColor: Color

    public init(
        _ text: String,
        color: Color = ScopeAmber.solid,
        strokeColor: Color = ScopeEdge.faint
    ) {
        self.text = text
        self.color = color
        self.strokeColor = strokeColor
    }

    public var body: some View {
        Text(text.uppercased())
            .font(ScopeType.channel)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
    }
}

// MARK: - PhosphorDot

/// Glowing status dot — the "trigger / live / armed" indicator.
/// 6pt diameter with a soft colored halo.
public struct PhosphorDot: View {
    public let color: Color
    public let size: CGFloat

    public init(color: Color = ScopeAmber.solid, size: CGFloat = 6) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.45), radius: size * 0.6)
    }
}

// MARK: - PhosphorGlow modifier

/// Adds a soft colored halo to text or symbols — the analog of the
/// homepage's `text-shadow: 0 0 4px color-mix(...)` rule.
public struct PhosphorGlow: ViewModifier {
    public let color: Color
    public let enabled: Bool
    public let radius: CGFloat
    public let opacity: Double

    public init(
        color: Color = ScopeAmber.solid,
        enabled: Bool = true,
        radius: CGFloat = 4,
        opacity: Double = 0.32
    ) {
        self.color = color
        self.enabled = enabled
        self.radius = radius
        self.opacity = opacity
    }

    public func body(content: Content) -> some View {
        if enabled {
            content.shadow(color: color.opacity(opacity), radius: radius)
        } else {
            content
        }
    }
}

public extension View {
    /// Apply a phosphor halo for amber / trace-colored text or dots.
    func phosphorGlow(
        color: Color = ScopeAmber.solid,
        radius: CGFloat = 4,
        opacity: Double = 0.32
    ) -> some View {
        modifier(PhosphorGlow(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - InsetStripe modifier

/// Left-edge accent stripe — the "lit row" / "armed channel" affordance.
/// CSS analog: `box-shadow: inset 2px 0 0 0 var(--trace)`.
///
/// Applied as an overlay so it doesn't push layout. Width is 2pt by
/// default; pass a different `Color.clear` to remove without restructuring.
public struct InsetStripe: ViewModifier {
    public let color: Color
    public let width: CGFloat

    public init(color: Color, width: CGFloat = 2) {
        self.color = color
        self.width = width
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: width)
                .allowsHitTesting(false)
        }
    }
}

public extension View {
    /// Apply a left-edge accent stripe (active / armed indicator).
    func insetStripe(_ color: Color, width: CGFloat = 2) -> some View {
        modifier(InsetStripe(color: color, width: width))
    }
}

// MARK: - ScopeDivider

/// Hairline gradient divider that fades at both ends — the homepage's
/// `.hairline` utility. Avoids the heavy "rule" feeling of a solid 1pt
/// line by tapering to transparent at the edges.
public struct ScopeDivider: View {
    public let color: Color
    public let height: CGFloat

    public init(color: Color = ScopeEdge.faint, height: CGFloat = 1) {
        self.color = color
        self.height = height
    }

    public var body: some View {
        LinearGradient(
            colors: [.clear, color, .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: height)
    }
}

// MARK: - ScopePageHero

/// Unified in-page hero for Scope-themed screens. Lives *below* the
/// universal 44pt top bar (which renders `CompactScopePageHeader`).
/// This is the second header band — eyebrow + two-tone Cormorant title
/// + optional trailing chrome + optional subtitle, capped with a
/// `ScopeDivider`.
///
/// Total height target: ~58pt (no subtitle) / ~76pt (with subtitle).
/// Previous bespoke heroes ran ~95–120pt. Halves the vertical real
/// estate while keeping the lab/instrument vocabulary intact.
public struct ScopePageHero: View {
    public enum Size {
        /// Default ~26pt Cormorant. Use for every secondary page.
        case compact
        /// ~32pt Cormorant. Reserved for the Home lobby where the hero
        /// earns slightly more presence.
        case expanded
    }

    public let eyebrow: String?
    public let titleHead: String
    public let titleTail: String?
    public let trailing: String?
    public let subtitle: String?
    public let size: Size

    public init(
        eyebrow: String? = nil,
        titleHead: String,
        titleTail: String? = nil,
        trailing: String? = nil,
        subtitle: String? = nil,
        size: Size = .compact
    ) {
        self.eyebrow = eyebrow
        self.titleHead = titleHead
        self.titleTail = titleTail
        self.trailing = trailing
        self.subtitle = subtitle
        self.size = size
    }

    private var displaySize: CGFloat {
        switch size {
        case .compact:  return 26
        case .expanded: return 32
        }
    }

    /// Cormorant Garamond resolver — same fallback chain as the other
    /// Scope files. Kept inline so the shared component doesn't need a
    /// separate font helper.
    private static func display(size: CGFloat) -> Font {
        #if os(macOS)
        for name in ["CormorantGaramond-Regular", "Cormorant Garamond", "CormorantGaramond"] {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        #endif
        return .system(size: size, weight: .regular, design: .serif)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Line 1 — eyebrow + trailing chrome (only rendered when
            // either piece is present; pages whose top-row identity now
            // lives in `ScopeTopBand` pass eyebrow=nil and skip this).
            if (eyebrow != nil && !(eyebrow ?? "").isEmpty) ||
               (trailing != nil && !(trailing ?? "").isEmpty) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let eyebrow, !eyebrow.isEmpty {
                        Eyebrow(eyebrow)
                    }
                    Spacer(minLength: 8)
                    if let trailing, !trailing.isEmpty {
                        Text(trailing.uppercased())
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.subtle)
                            .lineLimit(1)
                    }
                }
            }

            // Line 2 — two-tone Cormorant title
            Group {
                if let titleTail, !titleTail.isEmpty {
                    (
                        Text(titleHead)
                            .foregroundColor(ScopeInk.primary)
                        +
                        Text(" \(titleTail)")
                            .foregroundColor(ScopeInk.muted)
                            .italic()
                    )
                    .font(ScopePageHero.display(size: displaySize))
                    .tracking(-0.5)
                } else {
                    Text(titleHead)
                        .font(ScopePageHero.display(size: displaySize))
                        .foregroundColor(ScopeInk.primary)
                        .tracking(-0.5)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)

            // Optional line 3 — one-line mono caption
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 2)
            }

            ScopeDivider().padding(.top, 6)
        }
    }
}

// MARK: - ScopePageStrip

/// Unified slim header strip used at the top of every Scope utility
/// page (Library, Drafts, Models, Context, Workflows). Replaces the
/// bespoke per-page HStacks that drifted into slightly-different
/// paddings / orderings.
///
/// Anatomy (left → right):
/// - Leading: `PhosphorDot` + `Eyebrow(eyebrow)` (only when `eyebrow` set)
/// - Spacer
/// - Trailing chrome: right-aligned mono caption (e.g. `"127 ON FILE"`)
/// - Optional trailing accessory view (button, badge, etc.)
///
/// Two visual modes:
/// - `framed: false` — bare row, 8pt vertical padding only. For pages
///   whose parent already supplies horizontal padding.
/// - `framed: true` — wrapped in a section-card frame (cream surface,
///   hairline border, 6pt corner radius). Translates the Stats
///   `panelHeader` vocabulary onto the cream surface.
public struct ScopePageStrip<Trailing: View>: View {
    public let eyebrow: String?
    public let chrome: String?
    public let framed: Bool
    private let trailing: () -> Trailing

    public init(
        eyebrow: String? = nil,
        chrome: String? = nil,
        framed: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.chrome = chrome
        self.framed = framed
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let eyebrow, !eyebrow.isEmpty {
                PhosphorDot(color: ScopeAmber.solid, size: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                Eyebrow(eyebrow.uppercased(), color: ScopeAmber.solid)
            }
            Spacer(minLength: 8)
            if let chrome, !chrome.isEmpty {
                Text(chrome.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
            }
            trailing()
        }
        .padding(.horizontal, framed ? 14 : 0)
        .padding(.vertical, framed ? 10 : 8)
        .background(framedBackground)
    }

    @ViewBuilder
    private var framedBackground: some View {
        if framed {
            RoundedRectangle(cornerRadius: 6)
                .fill(ScopeCanvas.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ScopeEdge.normal, lineWidth: 1)
                )
        } else {
            Color.clear
        }
    }
}

public extension ScopePageStrip where Trailing == EmptyView {
    /// Convenience initializer for strips with no trailing accessory.
    init(eyebrow: String? = nil, chrome: String? = nil, framed: Bool = false) {
        self.init(eyebrow: eyebrow, chrome: chrome, framed: framed, trailing: { EmptyView() })
    }
}

// MARK: - ScopeTopBand
//
// The single, universal top row that every Scope-themed page renders
// at the very top of its detail column. Locks four things across all
// pages so the layout reads as one consistent shell:
//
// 1. 44pt vertical band height (matches the sidebar wordmark band).
// 2. Title baseline pinned to a constant Y from the top of the band,
//    so the bottoms of TALKIE (sidebar) and "Today" / "Drafts" / etc.
//    sit on exactly the same horizontal line regardless of font.
// 3. 32pt horizontal inset (matches every page's content grid).
// 4. Optional right-side chrome and trailing accessory slot — same
//    treatment everywhere (uppercase mono caption, hairline icon button
//    if used).
//
// Editorial pages (Home, Stats) may still render a larger in-page
// hero below — but the *top row* is owned by this band so the cross-
// column alignment with the wordmark is invariant.

/// Shared layout constants for the universal top band. Pinned here so
/// the sidebar wordmark and every page's title pull from the same
/// numbers — change them once and the whole shell moves together.
public enum ScopeTopBandLayout {
    /// 44pt — matches the sidebar wordmark frame.
    public static let height: CGFloat = 44
    /// 32pt — matches the standardized page horizontal padding.
    public static let horizontalPadding: CGFloat = 32
    /// 30pt — vertical position of the text baseline measured from the
    /// top of the band. The wordmark anchors to the same value so the
    /// bottoms of the two glyph rows align across columns.
    public static let baselineFromTop: CGFloat = 30
    /// 7pt — top inset applied above the page-title band. Locked to
    /// `SidebarLayout.headerTopPadding` so the page title, sidebar
    /// wordmark, and the persistent GlobalActionBar overlay (also at
    /// `.padding(.top, 7)`) share one horizontal rail across the window.
    public static let topInset: CGFloat = 4
}

public struct ScopeTopBand<Trailing: View>: View {
    public let title: String
    public let breadcrumb: String?
    public let chrome: String?
    public let horizontalPadding: CGFloat
    private let trailing: () -> Trailing

    public init(
        title: String,
        breadcrumb: String? = nil,
        chrome: String? = nil,
        horizontalPadding: CGFloat = ScopeTopBandLayout.horizontalPadding,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.breadcrumb = breadcrumb
        self.chrome = chrome
        self.horizontalPadding = horizontalPadding
        self.trailing = trailing
    }

    /// Cormorant Garamond resolver — same fallback chain as the rest of
    /// the Scope components.
    private static func display(size: CGFloat) -> Font {
        #if os(macOS)
        for name in ["CormorantGaramond-Regular", "Cormorant Garamond", "CormorantGaramond"] {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        #endif
        return .system(size: size, weight: .regular, design: .serif)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: ScopeTopBandLayout.height)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(ScopeTopBand.display(size: 24))
                    .foregroundColor(ScopeInk.primary)
                    .tracking(-0.3)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let breadcrumb, !breadcrumb.isEmpty {
                    // Amber chevron embellishment — small, tracking-wide
                    // typographic flourish between the section title and
                    // the active filter, keyed to the same baseline so it
                    // reads as part of the title row, not a separate line.
                    Text("›")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(ScopeAmber.solid.opacity(0.75))
                        .baselineOffset(2)
                    Text(breadcrumb)
                        .font(ScopeTopBand.display(size: 18))
                        .italic()
                        .foregroundColor(ScopeInk.muted)
                        .tracking(-0.2)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 8)

                if let chrome, !chrome.isEmpty {
                    Text(chrome.uppercased())
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                }

                trailing()
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.top) { dim in
                // Pin the HStack's firstTextBaseline to a fixed Y from
                // the top of the band so the title bottom always lands
                // on the same horizontal line as the wordmark.
                dim[.firstTextBaseline] - ScopeTopBandLayout.baselineFromTop
            }
        }
        .frame(height: ScopeTopBandLayout.height, alignment: .topLeading)
        // Push the band down so its baseline lines up with the donor
        // sidebar's wordmark, which is itself offset by
        // `SidebarLayout.headerTopPadding` (18pt) at the top of the
        // sidebar column. Without this inset the page title sits 18pt
        // above the wordmark — visible as the title "flying too high".
        .padding(.top, ScopeTopBandLayout.topInset)
    }
}

public extension ScopeTopBand where Trailing == EmptyView {
    /// Convenience initializer for bands with no trailing accessory.
    init(
        title: String,
        breadcrumb: String? = nil,
        chrome: String? = nil,
        horizontalPadding: CGFloat = ScopeTopBandLayout.horizontalPadding
    ) {
        self.init(
            title: title,
            breadcrumb: breadcrumb,
            chrome: chrome,
            horizontalPadding: horizontalPadding,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - SignalPath

/// Two-node connector with a glowing gradient arrow — the homepage's
/// `SecurityArrow` pattern. Used between architecture diagram nodes.
public struct SignalPath: View {
    public let color: Color
    public let width: CGFloat

    public init(color: Color = ScopeAmber.solid, width: CGFloat = 40) {
        self.color = color
        self.width = width
    }

    public var body: some View {
        LinearGradient(
            colors: [color.opacity(0.10), color, color.opacity(0.10)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width, height: 1)
        .shadow(color: color.opacity(0.35), radius: 3)
    }
}
