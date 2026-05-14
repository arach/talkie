//
//  SidebarLayout.swift
//
//  Geometry tokens for the Sidebar component.
//
//  The mental model: two parallel columns inside an HStack.
//
//      ┌──────┬───────────────────────────┐
//      │ rail │ label                     │   railWidth + labelWidth
//      │  32  │   200 → 0  (animates)     │   = sidebar's intrinsic width
//      └──────┴───────────────────────────┘
//
//  Rail: fixed 32pt column for icons/logo. Center-x = 16. Never animates.
//  Label: variable width column for text. Width animates from labelWidth → 0.
//  Text inside the label column is fixed-size; the column's width animation
//  reveals it from the right (or hides it).
//
//  All measurements derive from the 8pt grid (Spacing.*).
//
//  TODO(donation): replace `Spacing.*` with `HudsonSpacing.*` for HudsonKit.
//

import SwiftUI

public enum SidebarLayout {
    // ── Columns ──
    /// Fixed icon column at the leading edge. Never animates.
    public static let railWidth: CGFloat = 32

    /// Maximum width of the label column when fully expanded.
    public static let labelWidth: CGFloat = 200

    /// Static breathing room between the window's leading edge and the
    /// rail's leading edge. Applied at the host level (outside the
    /// Sidebar view) so the rail's internal geometry — including icon
    /// x-positions — stays exactly the same. Only the rail-as-a-whole
    /// shifts inward by this amount, once, statically.
    public static let leadingInset: CGFloat = 6

    // ── Cells ──
    /// Height of a row cell (icon row, label row).
    public static let rowHeight: CGFloat = 30

    /// Height of a section header cell in the label column.
    public static let sectionHeaderHeight: CGFloat = 28

    /// Vertical gap between sections (padding above section header).
    public static let sectionTopGap: CGFloat = Spacing.sm   // 8pt

    /// Height of the header (logo + wordmark) row at the top of the sidebar.
    public static let headerHeight: CGFloat = 44

    /// Vertical padding above the header. Generous on purpose — gives the
    /// logo + wordmark room to breathe and keeps the first row off the
    /// window's traffic-light cluster.
    public static let headerTopPadding: CGFloat = 18

    /// Vertical padding below the header before first row.
    public static let headerBottomPadding: CGFloat = Spacing.xs  // 4pt

    // ── Glyphs ──
    /// SF Symbol point size for row icons.
    public static let iconSize: CGFloat = 15

    /// Logo image size (centered in the rail).
    public static let logoSize: CGFloat = 24

    // ── Label inset ──
    /// Horizontal inset between the rail's trailing edge and label text.
    /// Visual gap = labelLeading (so text starts at x = railWidth + labelLeading
    /// in the sidebar's coordinate space).
    public static let labelLeading: CGFloat = 4

    // ── Selection ──
    /// Corner radius of the selection underlay.
    public static let selectionCornerRadius: CGFloat = 6

    /// Horizontal inset of the selection underlay from the sidebar edges.
    /// The pill sits inside this margin.
    public static let selectionHorizontalInset: CGFloat = 4

    /// Vertical inset of the selection underlay (so the pill is shorter
    /// than the cell, leaving breathing room above/below).
    public static let selectionVerticalInset: CGFloat = 2

    // ── Compact accent bar ──
    /// Width of the bottom accent bar shown under the selected icon in compact mode.
    public static let compactAccentBarWidth: CGFloat = 16

    /// Height of the bottom accent bar.
    public static let compactAccentBarHeight: CGFloat = 2

    // ── Row ──
    /// Vertical padding inside a row cell (top and bottom).
    public static let rowVerticalPadding: CGFloat = Spacing.xs  // 4pt

    // ── Convenience ──
    /// Sidebar's intrinsic width when fully expanded (rail + label columns).
    public static let totalWidth: CGFloat = railWidth + labelWidth

    /// Sidebar's intrinsic width at progress p (0 = expanded, 1 = compact).
    public static func intrinsicWidth(progress: Double) -> CGFloat {
        railWidth + labelWidth * CGFloat(1 - progress)
    }

    // ── Sibling-component compat ──
    /// Legacy compact sidebar content width used by ConsoleTabRail. The app
    /// sidebar itself uses `railWidth` for compact mode.
    public static let compactWidth: CGFloat = 48

    /// Legacy bottom accent height used by ConsoleTabRail.
    public static let accentBarHeight: CGFloat = compactAccentBarHeight

    /// Hit-target frame width (20pt) used by ConsoleTabRail. Not used by
    /// the Sidebar component itself.
    public static let iconFrameWidth: CGFloat = 20

    /// Vertical gap between an icon and a sibling element. Not used by
    /// the Sidebar component itself; kept for ConsoleTabRail.
    public static let accentToIconVerticalGap: CGFloat = Spacing.xxs  // 2pt
}
