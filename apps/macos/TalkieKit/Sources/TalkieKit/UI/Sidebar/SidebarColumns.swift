//
//  SidebarColumns.swift
//
//  Composes the Sidebar atom with a trailing content area in a deterministic
//  HStack layout. Replaces NavigationSplitView for the sidebar-leading slot.
//
//  Why this exists:
//    NavigationSplitView is backed by NSSplitViewController, which refuses to
//    honor sidebar column widths below ~80pt and applies its own positioning
//    to too-wide inner content (the "shifts to the left" bug). Driving the
//    expanded ↔ compact transition through the OS column means fighting AppKit
//    every frame.
//
//    SidebarColumns is a plain SwiftUI HStack. The Sidebar declares its own
//    intrinsic width (animated by progress); we honor it via .fixedSize.
//    The trailing content stretches to fill. No AppKit, no clamping, no
//    centering. The rail icons can't slide because nothing about their
//    parent's leading edge is ever animated.
//
//  Donation target: HudsonSplitView in HudsonKit (per ADR-002).
//

import SwiftUI

/// 2-column composition: a leading Sidebar with deterministic intrinsic
/// width, and a trailing content area that fills the remaining space.
public struct SidebarColumns<Sidebar: View, Trailing: View>: View {
    private let isHidden: Bool
    private let sidebar: () -> Sidebar
    private let trailing: () -> Trailing

    public init(
        isHidden: Bool = false,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.isHidden = isHidden
        self.sidebar = sidebar
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 0) {
            if !isHidden {
                sidebar()
                    // Honor the Sidebar's intrinsic width — it varies with
                    // progress, and SwiftUI must not stretch or squeeze it.
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        )
                    )
            }

            trailing()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
