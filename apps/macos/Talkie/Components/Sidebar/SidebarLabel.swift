//
//  SidebarLabel.swift
//
//  Icon + label primitive for sidebar rows.
//
//  Design contract:
//    • Icon lives in a FIXED 32pt rail column at the leading edge, glyph
//      centered. Its visual position never changes — not during the
//      transition, not in any state.
//    • Label sits immediately to the right of the rail with a small gap.
//      Text is rendered at fixed font size and left-aligned. As the row's
//      available width shrinks, the parent's clip mask hides text from
//      the right (no font resize, no layout reflow).
//    • Opacity also fades the label proportional to transition.progress
//      so the residual fully disappears in compact mode.
//
//  TODO(donation): the `selectedIcon` mapping below is Talkie-specific.
//  Move it to the host as a parameter (e.g., `selectedIcon: String?`).
//  Also: `DesignGuideFrameKey` is a Talkie debug-overlay preference key.
//

import SwiftUI

public struct SidebarLabel: View {
    public let title: String
    public let icon: String
    public let isSelected: Bool
    @Environment(\.sidebarTransition) private var transition
    @Environment(\.sidebarShowMeasurements) private var showMeasurements

    public init(title: String, icon: String, isSelected: Bool) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
    }

    private var selectedIcon: String {
        if icon.hasSuffix(".fill") { return icon }

        let fillableMappings: [String: String] = [
            // Core navigation
            "house": "house.fill",
            "square.and.pencil": "square.and.pencil.circle.fill",
            "note.text": "doc.text.fill",
            "doc.text": "doc.text.fill",
            "square.stack": "square.stack.fill",
            "gear": "gearshape.fill",
            "brain": "brain.fill",
            "paintbrush": "paintbrush.fill",
            "checkmark.seal": "checkmark.seal.fill",
            "square.grid.2x2": "square.grid.2x2.fill",
            // Library & content
            "rectangle.stack": "rectangle.stack.fill",
            "waveform.badge.mic": "mic.circle.fill",
            "square.stack.3d.forward.dottedline": "square.stack.3d.forward.dottedline.fill",
            "chart.line.uptrend.xyaxis": "chart.xyaxis.line",
            "clock.arrow.circlepath": "clock.fill",
            // Stats & capture
            "waveform.path.ecg": "chart.bar.fill",
            "wand.and.stars": "wand.and.rays.inverse",
            "camera.viewfinder": "camera.fill",
        ]

        return fillableMappings[icon] ?? icon
    }

    public var body: some View {
        HStack(spacing: 0) {
            // ── Icon rail: 32pt fixed column, glyph centered ──
            Image(systemName: isSelected ? selectedIcon : icon)
                .font(.system(size: SidebarLayout.iconSize))
                .foregroundColor(.white)
                .frame(width: SidebarLayout.railWidth, alignment: .center)
                .border(showMeasurements ? Color.pink : .clear, width: 1.5)
                #if DEBUG
                .background {
                    if isSelected {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: DesignGuideFrameKey.self,
                                value: ["iconBox": geo.frame(in: .named("designGuides"))]
                            )
                        }
                    }
                }
                #endif

            // ── Label region: text rendered at fixed size, clipped by parent ──
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, SidebarLayout.labelLeading)
                .opacity(transition.labelOpacity)
                .accessibilityHidden(transition.isCompact)
                .border(showMeasurements ? Color.cyan : .clear, width: 1)
        }
        .border(showMeasurements ? Color.yellow.opacity(0.6) : .clear, width: 1)
    }
}
