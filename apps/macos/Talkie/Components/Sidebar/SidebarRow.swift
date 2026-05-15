//
//  SidebarRow.swift
//
//  Selectable sidebar row with mode-aware accent indicator.
//
//  Design contract:
//    • The row content is laid out via `SidebarLabel` (or a custom view),
//      which guarantees the icon sits in the fixed 32pt rail column.
//    • In compact mode, a horizontal accent bar appears below the icon —
//      also centered in the rail (16pt long, centered at x=16).
//    • In expanded mode, the selected row gets a subtle accent-tinted fill.
//      Compact mode skips the fill (the bottom bar carries the state, and
//      a fill in a 32pt-wide rail looks heavy).
//
//  Generic over `Selection: Hashable` so the same row works for any
//  enum-based or id-based navigation model.
//
//  TODO(donation): currently emits hover events to `SidebarTooltipState.shared`
//  for the compact-mode tooltip overlay. For HudsonKit, replace that with a
//  callback closure passed in by the host.
//

import SwiftUI

public struct SidebarRow<Selection: Hashable, Content: View>: View {
    let section: Selection
    @Binding var selectedSection: Selection?
    var tooltipLabel: String? = nil
    @ViewBuilder let content: (_ isSelected: Bool) -> Content

    @Environment(\.sidebarTransition) private var transition
    @Environment(\.sidebarAccent) private var accentColor

    @State private var isHovering = false
    @State private var rowFrame: CGRect = .zero

    public init(
        section: Selection,
        selectedSection: Binding<Selection?>,
        tooltipLabel: String? = nil,
        @ViewBuilder content: @escaping (_ isSelected: Bool) -> Content
    ) {
        self.section = section
        self._selectedSection = selectedSection
        self.tooltipLabel = tooltipLabel
        self.content = content
    }

    private var isSelected: Bool {
        selectedSection == section
    }

    public var body: some View {
        // No Button — Button centers its label, which pushes the row's
        // 248pt-wide internal content off-screen to the LEFT in compact mode
        // (label_left = (32 - 248) / 2 = -108). Use a plain HStack with a
        // tap gesture instead so leading alignment is honored end-to-end.
        ZStack(alignment: .topLeading) {
            rowBackground
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: SidebarLayout.accentToIconVerticalGap) {
                content(isSelected)

                // ── Bottom accent bar (compact only) ──
                // Centered in the rail column so its center-x = 16, matching
                // the icon glyph above it.
                RoundedRectangle(cornerRadius: 1)
                    .fill(transition.isCompact && isSelected ? accentColor : Color.clear)
                    .frame(
                        width: SidebarLayout.compactAccentBarWidth,
                        height: transition.isCompact ? SidebarLayout.compactAccentBarHeight : 0
                    )
                    .frame(width: SidebarLayout.railWidth, alignment: .center)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
            }
            .frame(width: SidebarLayout.totalWidth, alignment: .leading)
            .padding(.vertical, SidebarLayout.rowVerticalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .clipped()
        .onTapGesture {
            selectedSection = section
        }
        // VoiceOver: announce the row title and selection state. The
        // donor rail uses tap gestures on a plain HStack, so we have to
        // provide accessibility metadata ourselves — the native `List`
        // + `NavigationLink` pattern got this for free.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tooltipLabel ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Activate to navigate")
        .background {
            if transition.isCompact {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { rowFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            rowFrame = newFrame
                        }
                }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
                if transition.isCompact, let label = tooltipLabel {
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
                if transition.isCompact, let label = tooltipLabel {
                    SidebarTooltipState.shared.dismiss(matching: label)
                }
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if transition.isCompact {
            // Compact: hover-only highlight constrained to the rail column
            // (rail width − 4 = 28pt) and centered on the icon. Selection is
            // conveyed by the bottom accent bar, so we skip the fill for
            // selected rows to avoid double signaling.
            let borderOpacity: Double = isHovering ? 0.38 : 0.14
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovering ? 0.085 : 0))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(borderOpacity), lineWidth: isHovering ? 1 : 0.75)
                )
                .frame(width: SidebarLayout.railWidth - 4,
                       height: SidebarLayout.rowHeight - 2)
                .frame(width: SidebarLayout.railWidth, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.08), value: isHovering)
        } else {
            // Expanded: every row carries a soft resting border for
            // structural definition; hover lifts it noticeably so the
            // row reads as live. Selected uses accent fill and skips
            // the border (the fill alone is enough signal).
            //
            // Color.primary adapts to light/dark, but on light cream
            // surfaces the resting opacity needs to be ~15% with a
            // 0.75pt line to register at all — 8%/0.5pt vanished.
            let restingBorderOpacity: Double = 0.14
            let hoverBorderOpacity: Double = 0.38
            let borderOpacity: Double = isSelected
                ? 0.0
                : (isHovering ? hoverBorderOpacity : restingBorderOpacity)
            let borderWidth: CGFloat = isHovering ? 1 : 0.75
            RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius)
                .fill(
                    isSelected
                        ? accentColor.opacity(0.14)
                        : (isHovering ? Color.primary.opacity(0.06) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius)
                        .strokeBorder(Color.primary.opacity(borderOpacity), lineWidth: borderWidth)
                )
                .padding(.horizontal, SidebarLayout.selectionHorizontalInset)
                .animation(.easeOut(duration: 0.10), value: isSelected)
                .animation(.easeOut(duration: 0.10), value: isHovering)
        }
    }
}

// MARK: - Convenience: SidebarLabel content

public extension SidebarRow where Content == SidebarLabel {
    /// Convenience init that wires up a `SidebarLabel` as the row content
    /// and uses the title as the compact-mode tooltip.
    init(
        section: Selection,
        selectedSection: Binding<Selection?>,
        title: String,
        icon: String,
        tooltipLabel: String? = nil
    ) {
        self.section = section
        self._selectedSection = selectedSection
        self.tooltipLabel = tooltipLabel ?? title
        self.content = { isSelected in
            SidebarLabel(title: title, icon: icon, isSelected: isSelected)
        }
    }
}
