//
//  Sidebar.swift
//
//  Two parallel columns inside an HStack.
//
//      ┌──────┬───────────────────────────┐
//      │ rail │ label                     │
//      │      │                           │
//      │ 32pt │ 200pt → 0pt  (animates)   │
//      │ FIXED│                           │
//      └──────┴───────────────────────────┘
//
//  Icons live in the rail. They never move — there is no layout that
//  could move them. Logo, icons, and the bottom accent bar are all
//  centered in the rail's 32pt width.
//
//  Labels live in the label column. The column's WIDTH animates from
//  `labelWidth → 0`. Text inside is rendered at fixed font size,
//  left-anchored, with `.fixedSize(horizontal: true)`. As the column
//  narrows, `.clipped()` reveals less of the text from the right.
//  Text never resizes.
//
//  Selection is a single underlay shape that spans the sidebar width
//  at the selected row's y. There are no per-row backgrounds.
//
//  All animation flows from a single `progress: Double` (0 expanded,
//  1 compact). The host computes one value and passes it in.
//

import SwiftUI
import TalkieKit

// MARK: - Public types

public struct SidebarItem<Selection: Hashable>: Identifiable {
    public let id: Selection
    public let title: String
    public let icon: String
    public let selectedIcon: String?
    public let tooltipLabel: String?

    public init(
        id: Selection,
        title: String,
        icon: String,
        selectedIcon: String? = nil,
        tooltipLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.selectedIcon = selectedIcon
        self.tooltipLabel = tooltipLabel
    }
}
public enum SidebarEntry<Selection: Hashable>: Identifiable {
    case item(SidebarItem<Selection>)
    case section(id: String, title: String)

    public var id: String {
        switch self {
        case .item(let item):    return "item-\(item.id.hashValue)"
        case .section(let id, _): return "section-\(id)"
        }
    }
}

// MARK: - Sidebar

public struct Sidebar<Selection: Hashable, RailHeader: View, LabelHeader: View, Footer: View>: View {
    @Binding var selection: Selection?
    let entries: [SidebarEntry<Selection>]
    let progress: Double
    let accent: Color
    let allCaps: Bool
    let labelWidth: CGFloat
    let onHeaderTap: (() -> Void)?
    @ViewBuilder let railHeader: () -> RailHeader
    @ViewBuilder let labelHeader: () -> LabelHeader
    @ViewBuilder let footer: () -> Footer

    @Environment(\.sidebarStyle) private var style

    /// Currently hovered row id. Drives the full-row hover underlay
    /// rendered alongside (and below) the selection underlay.
    @State private var hoveredID: Selection? = nil

    public init(
        selection: Binding<Selection?>,
        entries: [SidebarEntry<Selection>],
        progress: Double,
        accent: Color = .accentColor,
        allCaps: Bool = false,
        labelWidth: CGFloat = SidebarLayout.labelWidth,
        onHeaderTap: (() -> Void)? = nil,
        @ViewBuilder railHeader: @escaping () -> RailHeader,
        @ViewBuilder labelHeader: @escaping () -> LabelHeader,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self._selection = selection
        self.entries = entries
        self.progress = progress
        self.accent = accent
        self.allCaps = allCaps
        self.labelWidth = labelWidth
        self.onHeaderTap = onHeaderTap
        self.railHeader = railHeader
        self.labelHeader = labelHeader
        self.footer = footer
    }

    /// The Sidebar's outer width is FIXED. It does not animate.
    /// The rail is at x=0..railWidth, the label column is at x=railWidth..(railWidth+labelWidth).
    /// "Shrinking" is done by the host (the NavigationSplitView column) clipping
    /// from the right as it animates. The icons cannot move because their x-position
    /// depends on nothing that animates.
    /// (Lives on `SidebarLayout` because Swift forbids static stored properties on generic types.)

    // MARK: Motion mode (test knob)

    /// True only when the sidebar is fully expanded (settled).
    private var labelsSettled: Bool {
        progress < 0.001
    }

    /// True only when the sidebar is fully compact (settled).
    private var compactSettled: Bool {
        progress > 0.999
    }

    /// Opacity for label-column content, given the current motion mode.
    private var labelOpacity: Double {
        switch SidebarMotion.mode {
        case .smoothFade:       return 1 - progress
        case .quietTransition,
             .snapEverything:   return labelsSettled ? 1 : 0
        }
    }

    /// Opacity for the selection underlay (expanded-mode pill).
    private var underlayOpacity: Double {
        switch SidebarMotion.mode {
        case .smoothFade:       return max(0, 1 - progress * 2)
        case .quietTransition,
             .snapEverything:   return labelsSettled ? 1 : 0
        }
    }

    /// Opacity for the compact-mode bottom accent bar (per-row).
    /// Computed at the row level (RailIcon), but the rule lives here.
    fileprivate var compactBarOpacity: Double {
        switch SidebarMotion.mode {
        case .smoothFade:       return progress
        case .quietTransition,
             .snapEverything:   return compactSettled ? 1 : 0
        }
    }

    public var body: some View {
        // The effect axis (flush / floating / shadow / recessed) wraps the
        // core sidebar with different chrome. Surface fill is owned by
        // `coreSidebarContent`; effects only add wrapping geometry +
        // overlays so any effect composes with any surface style.
        switch style.effect {
        case .flush:
            coreSidebarContent
                .overlay(alignment: .trailing) {
                    SidebarTrailingSeparator(style: style.surface)
                }
        case .shadowRail:
            coreSidebarContent
                .overlay(alignment: .trailing) {
                    SidebarTrailingSeparator(style: style.surface)
                }
                .overlay(alignment: .trailing) {
                    SidebarTrailingShadow(style: style.surface)
                }
        case .recessed:
            coreSidebarContent
                .overlay {
                    SidebarInnerShadow(style: style.surface)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) {
                    SidebarTrailingSeparator(style: style.surface)
                }
        }
    }

    /// The sidebar's content + surface fill, without the depth/effect
    /// chrome layer. Always renders the same regardless of effect; the
    /// effect axis wraps this in different outer geometry.
    @ViewBuilder
    private var coreSidebarContent: some View {
        VStack(spacing: 0) {
            sidebarBody
            Spacer(minLength: 0)
            footerBlock
        }
        .frame(maxHeight: .infinity)
        // Sidebar self-sizes — rail is fixed 32pt, label column animates its
        // own width from labelWidth → 0 by progress. Host (HStack) honors
        // the intrinsic width; nothing slides because nothing is being
        // re-anchored by a shrinking parent column.
        .background(SidebarSurfaceBackground(style: style.surface))
        .overlay(alignment: .top) {
            // Editorial only: hairline at the very top so the rail reads
            // like a masthead under the title bar.
            if style.surface == .editorial {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: Body (header + entries)

    private var sidebarBody: some View {
        ZStack(alignment: .topLeading) {
            hoverUnderlay
            selectionUnderlay
            HStack(alignment: .top, spacing: 0) {
                railColumn
                labelColumn
            }
            // Single shared accent bar for compact mode. Slides between
            // selected rows instead of per-row fade-swap.
            compactAccentBar
        }
        .background(alignment: .top) { scopeHeaderStrip }
    }

    /// Scope only: the sidebar's TOP zone (logo + wordmark) is capped by the
    /// same hairline at the same Y as the content header band, so the two
    /// rules align into ONE continuous line under the header across the
    /// window — even when the rail is collapsed to icons. No surface fill
    /// (the gray strip read wrong); structure comes from the rule alone.
    @ViewBuilder
    private var scopeHeaderStrip: some View {
        if SettingsManager.shared.isScopeTheme {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: SidebarLayout.headerHeight + SidebarLayout.headerTopPadding)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(ScopeEdge.faint)
                            .frame(height: 0.5)
                    }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footerBlock: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.bottom, 4)

            HStack(alignment: .top, spacing: 0) {
                // Footer rail slot: always 32pt wide
                VStack(spacing: 0) { footer() }
                    .frame(width: SidebarLayout.railWidth)

                // No label-side footer for now (the rail-based footer slot
                // is enough; expansion can be added by the host if needed).
                Spacer(minLength: 0)
            }
            .frame(height: SidebarLayout.rowHeight)
        }
    }

    // MARK: Rail column

    private var railColumn: some View {
        VStack(spacing: 0) {
            // Header rail slot — host's logo lives here, centered in 32pt.
            railHeader()
                .frame(width: SidebarLayout.railWidth, height: SidebarLayout.headerHeight)
                .padding(.top, SidebarLayout.headerTopPadding)
                .padding(.bottom, SidebarLayout.headerBottomPadding)
                .contentShape(Rectangle())
                .onTapGesture { onHeaderTap?() }

            // Per-entry rail cells. Section headers are empty space here so
            // y-positions stay aligned with the label column.
            ForEach(entries) { entry in
                railCell(for: entry)
            }
        }
        .frame(width: SidebarLayout.railWidth)
    }

    @ViewBuilder
    private func railCell(for entry: SidebarEntry<Selection>) -> some View {
        switch entry {
        case .item(let item):
            RailIcon(
                item: item,
                isSelected: selection == item.id,
                accent: accent,
                progress: progress,
                compactBarOpacity: compactBarOpacity,
                onTap: { selection = item.id },
                onHoverChange: { hovering in
                    updateHover(item.id, hovering: hovering)
                }
            )
            .frame(width: SidebarLayout.railWidth, height: SidebarLayout.rowHeight)
        case .section:
            // Empty rail cell — same height as the label column's section
            // header so the two columns stay y-aligned.
            Color.clear
                .frame(
                    width: SidebarLayout.railWidth,
                    height: SidebarLayout.sectionTopGap + SidebarLayout.sectionHeaderHeight
                )
        }
    }

    // MARK: Label column

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header label slot — host's wordmark lives here, left-aligned.
            labelHeader()
                .frame(height: SidebarLayout.headerHeight, alignment: .leading)
                .padding(.top, SidebarLayout.headerTopPadding)
                .padding(.bottom, SidebarLayout.headerBottomPadding)
                .padding(.leading, SidebarLayout.labelLeading)
                .contentShape(Rectangle())
                .onTapGesture { onHeaderTap?() }

            ForEach(entries) { entry in
                labelCell(for: entry)
            }
        }
        // Width animates from labelWidth → 0 by progress. The label content
        // inside has fixed intrinsic widths (`.fixedSize`), so as our frame
        // shrinks the labels are clipped from the right. The rail to our
        // left never moves because it has its own fixed-width column.
        .frame(width: max(0, labelWidth * (1 - progress)), alignment: .leading)
        .clipped()
        .opacity(labelOpacity)
        .animation(nil, value: labelsSettled)
        .allowsHitTesting(labelsSettled)
    }

    @ViewBuilder
    private func labelCell(for entry: SidebarEntry<Selection>) -> some View {
        switch entry {
        case .item(let item):
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(selection == item.id ? Color.primary : Color.secondary)
                .padding(.leading, SidebarLayout.labelLeading)
                .frame(height: SidebarLayout.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { selection = item.id }
                .onContinuousHover { phase in
                    switch phase {
                    case .active: updateHover(item.id, hovering: true)
                    case .ended:  updateHover(item.id, hovering: false)
                    }
                }
        case .section(_, let title):
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: SidebarLayout.sectionTopGap)
                Text(allCaps ? title.uppercased() : title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, SidebarLayout.labelLeading)
                    .frame(height: SidebarLayout.sectionHeaderHeight, alignment: .bottomLeading)
            }
        }
    }

    // MARK: Selection underlay

    @ViewBuilder
    private var selectionUnderlay: some View {
        if let y = selectionY {
            SidebarSelectionIndicator(
                style: style.indicator,
                accent: accent
            )
            .opacity(underlayOpacity)
            .animation(nil, value: labelsSettled)
            .offset(y: y)
            // No slide on selection change — the main content swaps
            // instantly when selection flips, and animating the
            // indicator y over ~200ms made the indicator lag behind
            // the new content. Instant teleport keeps the indicator
            // synchronized with what the user just clicked.
            .animation(nil, value: y)
            .allowsHitTesting(false)
        }
    }

    /// Compact-mode accent. Style switches between a horizontal bottom bar
    /// (default), a vertical glowing rod (glass), and a leading stripe
    /// (editorial — same shape as the expanded selection so the indicator
    /// stays continuous through the transition).
    @ViewBuilder
    private var compactAccentBar: some View {
        if let y = selectionY {
            SidebarCompactAccent(
                style: style.indicator,
                accent: accent
            )
            .offset(y: y)
            .opacity(compactBarOpacity)
            .animation(nil, value: y)
            .animation(nil, value: compactSettled)
            .allowsHitTesting(false)
        }
    }

    /// Y-offset of the selected row's cell, relative to the sidebar body's
    /// top. Returns nil if nothing is selected. Computed from the entries
    /// list — no GeometryReader needed.
    private var selectionY: CGFloat? {
        rowY(for: selection)
    }

    /// Y-offset of the hovered row's cell. Same machinery as `selectionY`.
    private var hoveredY: CGFloat? {
        guard let id = hoveredID, id != selection else { return nil }
        return rowY(for: id)
    }

    /// Update the hovered row id from a hover phase. The `id == hoveredID`
    /// guard on the `ended` branch prevents a stale "ended" from the
    /// rail clearing hover state that the label just set (or vice versa)
    /// when the mouse crosses the rail↔label boundary inside the same row.
    private func updateHover(_ id: Selection, hovering: Bool) {
        if hovering {
            if hoveredID != id { hoveredID = id }
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    private func rowY(for id: Selection?) -> CGFloat? {
        guard let id else { return nil }
        var y: CGFloat = SidebarLayout.headerTopPadding
                       + SidebarLayout.headerHeight
                       + SidebarLayout.headerBottomPadding
        for entry in entries {
            switch entry {
            case .item(let item):
                if item.id == id { return y }
                y += SidebarLayout.rowHeight
            case .section:
                y += SidebarLayout.sectionTopGap + SidebarLayout.sectionHeaderHeight
            }
        }
        return nil
    }

    /// Full-row hover underlay. Sits below the selection underlay in the
    /// z-stack so a hover on the selected row doesn't paint over its
    /// accent fill. `Color.primary` adapts to light/dark and reads on
    /// the cream surface where the prior per-icon white-tint hover was
    /// invisible.
    ///
    /// Speed feel: position is *not* animated (`.animation(nil, value:)`)
    /// so the underlay teleports between rows under the cursor — any
    /// slide here would read as lag. Appearance gets a fast 60ms fade
    /// via `.transition(.opacity)`.
    @ViewBuilder
    private var hoverUnderlay: some View {
        if let y = hoveredY {
            RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75)
                )
                .frame(height: SidebarLayout.rowHeight - SidebarLayout.selectionVerticalInset * 2)
                .padding(.horizontal, SidebarLayout.selectionHorizontalInset)
                .padding(.vertical, SidebarLayout.selectionVerticalInset)
                .offset(y: y)
                .animation(nil, value: hoveredY)
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeOut(duration: 0.06)))
        }
    }
}

// MARK: - Rail icon cell

private struct RailIcon<Selection: Hashable>: View {
    let item: SidebarItem<Selection>
    let isSelected: Bool
    let accent: Color
    let progress: Double
    let compactBarOpacity: Double
    let onTap: () -> Void
    var onHoverChange: (Bool) -> Void = { _ in }

    @Environment(\.sidebarStyle) private var style

    @State private var isHovering = false
    @State private var isPressing = false
    @State private var rowFrame: CGRect = .zero

    private var glyphName: String {
        if isSelected, let s = item.selectedIcon { return s }
        return item.icon
    }

    private var isCompact: Bool { progress > 0.5 }
    private var compactSettled: Bool { progress > 0.999 }

    private var tooltipLabel: String? {
        item.tooltipLabel ?? item.title
    }

    /// Selected = accent; hovered = primary; otherwise muted secondary.
    /// Spring on color makes the hover/select transition feel intentional.
    private var iconColor: Color {
        if isSelected { return accent }
        if isHovering { return Color.primary }
        return Color.secondary
    }

    var body: some View {
        Image(systemName: glyphName)
            .font(.system(size: SidebarLayout.iconSize))
            .foregroundColor(iconColor)
            .frame(width: SidebarLayout.railWidth, height: SidebarLayout.rowHeight)
            // Hover changes color only; the full-row underlay carries the
            // background affordance. Tap gives a brief scale-down for
            // click feedback — applies across all styles (was kinetic-
            // only) so every click feels acknowledged.
            .scaleEffect(isPressing ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isHovering)
            .animation(.spring(response: 0.20, dampingFraction: 0.65), value: isPressing)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressing = true }
                    .onEnded   { _ in isPressing = false }
            )
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, new in rowFrame = new }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
                onHoverChange(true)
                if isCompact, let label = tooltipLabel {
                    let tooltip = SidebarTooltipState.shared
                    let anchor = CGPoint(x: rowFrame.maxX, y: rowFrame.midY)
                    if tooltip.label == label {
                        tooltip.updateAnchor(anchor)
                    } else {
                        tooltip.show(label: label, anchor: anchor)
                    }
                }
            case .ended:
                isHovering = false
                onHoverChange(false)
                if isCompact, let label = tooltipLabel {
                    SidebarTooltipState.shared.dismiss(matching: label)
                }
            }
        }
    }

}

// MARK: - Style variant views

/// Background plane that switches per surface style.
struct SidebarSurfaceBackground: View {
    let style: SidebarSurfaceStyle

    var body: some View {
        switch style {
        case .default:
            // Theme-adaptive surface: Color.primary at very low opacity
            // shifts the sidebar a few shades off the window background
            // — on light/cream themes this reads as a subtly darker
            // panel, on dark themes as a subtly lifted one. Either way
            // the sidebar is unambiguously a *different surface* than
            // the main content area, which is what a thin border alone
            // couldn't reliably deliver (white-on-white invisibility).
            //
            // Gradient (top brighter, bottom slightly darker) preserves
            // the existing depth feel.
            if SettingsManager.shared.isScopeTheme {
                // Scope: the rail is the SAME white canvas as the content —
                // no gray surface. The rail is usually collapsed, and a
                // distinct gray panel read wrong; structure comes from the
                // header rule + the rail|content divider, not a fill.
                ScopeCanvas.canvas
                    .allowsHitTesting(false)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.055),
                            Color.primary.opacity(0.040),
                            Color.primary.opacity(0.030)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    VStack(spacing: 0) {
                        // Top hairline — sits under the title bar, defines the
                        // surface boundary without being loud.
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 0.5)
                        Spacer(minLength: 0)
                    }
                }
                .allowsHitTesting(false)
            }
        case .glass:
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(0.55)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.040),
                        Color.white.opacity(0.018),
                        Color.black.opacity(0.060)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 24)
                    .blendMode(.plusLighter)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.18)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 80)
                }
            }
            .allowsHitTesting(false)
        case .editorial:
            Color.white.opacity(0.045)
        }
    }
}

/// Trailing hairline that defines the rail's right edge.
struct SidebarTrailingSeparator: View {
    let style: SidebarSurfaceStyle

    var body: some View {
        switch style {
        case .glass:
            // Glass is dark by design — white gradient reads against it.
            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.02)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 0.5)
        case .editorial, .default:
            // Color.primary so the line is visible on both the cream
            // light theme and the dark theme. The prior `Color.white`
            // value vanished on light surfaces (white-on-white).
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 0.5)
        }
    }
}

/// Outward shadow that bleeds from the sidebar's trailing edge into the
/// content area. 16pt-wide linear gradient anchored just past the hairline
/// so the two don't fight. Used by the `.shadowRail` effect to suggest the
/// sidebar sits on a slightly higher z-plane than the content.
///
/// Skipped on `.glass` — that surface already paints its own white
/// trailing gradient; a dark fade on top would muddy it.
struct SidebarTrailingShadow: View {
    let style: SidebarSurfaceStyle

    /// How far the shadow bleeds into the content column.
    private static let bleed: CGFloat = 16
    /// Edge opacity — cool charcoal at low alpha, neutral enough not to
    /// feel like a drop shadow.
    private static let edgeOpacity: Double = 0.10

    var body: some View {
        switch style {
        case .glass:
            EmptyView()
        case .default, .editorial:
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.067, blue: 0.071).opacity(Self.edgeOpacity),
                    Color(red: 0.06, green: 0.067, blue: 0.071).opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: Self.bleed)
            // Push the gradient *outside* the sidebar so it lands on the
            // content column. The 0.5pt offset clears the hairline.
            .offset(x: Self.bleed + 0.5)
            .allowsHitTesting(false)
        }
    }
}

/// Inner-frame inset overlay — gives the sidebar a recessed-well feel
/// without changing the surface fill. Two layered gradients:
///
///   1. A top edge inner shadow (8pt) — the lip catching shadow because
///      the implied light source is bottom-left.
///   2. A bottom-edge soft drop shadow (14pt) — the well floor where
///      the sidebar meets the window bottom. Sits *above* the footer's
///      0.5pt divider so the divider still defines the boundary; the
///      shadow only darkens the lower half of the footer slot.
///
/// We deliberately do *not* shade the right edge — the trailing 0.5pt
/// separator already does that job; doubling them would read as a
/// chunky border, not a well. The asymmetric "top only" feel paired
/// with the trailing hairline is what sells "recessed."
///
/// Color is `Color.primary` at low alpha so the effect tracks the
/// theme: charcoal ink on the cool-slate light theme, off-white on
/// dark. Tuned for subtlety — the gradient maxes out at ~6% alpha.
struct SidebarInnerShadow: View {
    let style: SidebarSurfaceStyle

    var body: some View {
        // Glass already paints its own bottom shade (~80pt black gradient);
        // we drop our bottom band there and keep only the top lip so we
        // don't double-darken.
        let drawsBottom = style != .glass

        ZStack {
            // Top edge inner shadow — 8pt fall-off.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.06),
                        Color.primary.opacity(0.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 8)
                Spacer(minLength: 0)
            }

            // Bottom drop shadow — 14pt fall-off, slightly weaker so the
            // top still reads as the dominant lip.
            if drawsBottom {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.0),
                            Color.primary.opacity(0.05)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 14)
                }
            }
        }
    }
}

/// Expanded-mode selection indicator. Switches per indicator style.
struct SidebarSelectionIndicator: View {
    let style: SidebarIndicatorStyle
    let accent: Color

    var body: some View {
        switch style {
        case .default:
            RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius)
                .fill(accent.opacity(0.14))
                .frame(height: SidebarLayout.rowHeight - SidebarLayout.selectionVerticalInset * 2)
                .padding(.horizontal, SidebarLayout.selectionHorizontalInset)
                .padding(.vertical, SidebarLayout.selectionVerticalInset)

        case .glass:
            ZStack {
                RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius + 2)
                    .fill(accent.opacity(0.22))
                    .blur(radius: 8)
                    .padding(.horizontal, max(0, SidebarLayout.selectionHorizontalInset - 2))
                    .padding(.vertical, max(0, SidebarLayout.selectionVerticalInset - 1))

                RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.10)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius)
                            .strokeBorder(accent.opacity(0.35), lineWidth: 0.5)
                    )
                    .padding(.horizontal, SidebarLayout.selectionHorizontalInset)
                    .padding(.vertical, SidebarLayout.selectionVerticalInset)
            }
            .frame(height: SidebarLayout.rowHeight)

        case .editorial:
            // 2pt vertical stripe at the leading edge — same shape stays
            // visible in compact mode for visual continuity.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 2)
                    .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
            .frame(height: SidebarLayout.rowHeight)

        case .kinetic:
            // Same shape as default; the kinetic feel comes from the spring
            // (motion style) and a slightly more vivid fill.
            RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius)
                .fill(accent.opacity(0.18))
                .frame(height: SidebarLayout.rowHeight - SidebarLayout.selectionVerticalInset * 2)
                .padding(.horizontal, SidebarLayout.selectionHorizontalInset)
                .padding(.vertical, SidebarLayout.selectionVerticalInset)
        }
    }
}

/// Compact-mode accent. Sits at the selected row's y-offset; the parent
/// view positions and animates it.
struct SidebarCompactAccent: View {
    let style: SidebarIndicatorStyle
    let accent: Color

    var body: some View {
        switch style {
        case .default, .kinetic:
            RoundedRectangle(cornerRadius: 1)
                .fill(accent)
                .frame(
                    width: SidebarLayout.compactAccentBarWidth,
                    height: SidebarLayout.compactAccentBarHeight
                )
                .frame(width: SidebarLayout.railWidth, alignment: .center)
                .frame(height: SidebarLayout.rowHeight, alignment: .bottom)

        case .glass:
            ZStack {
                Capsule()
                    .fill(accent.opacity(0.55))
                    .frame(width: 6, height: 18)
                    .blur(radius: 4)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.65)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: 16)
            }
            .frame(width: SidebarLayout.railWidth, alignment: .leading)
            .frame(height: SidebarLayout.rowHeight, alignment: .center)
            .padding(.leading, 2)

        case .editorial:
            // Same leading 2pt stripe as the expanded indicator — continuous
            // through the transition.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 2)
                    .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
            .frame(width: SidebarLayout.railWidth, height: SidebarLayout.rowHeight)
        }
    }
}
