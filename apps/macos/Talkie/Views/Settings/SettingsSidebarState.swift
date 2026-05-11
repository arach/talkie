//
//  SettingsSidebarState.swift
//  Talkie macOS
//
//  State machine for the collapsible settings sidebar.
//  Uses the same proven pattern as the main sidebar:
//  - Compact: locked at 52px (all three constraints identical)
//  - Expanded: min 120 forces clamp up from 52 on toggle
//  - Toggle is the primary collapse/expand mechanism
//

import Foundation

struct SettingsSidebarState {

    enum RenderMode: Equatable {
        case compact   // Icons only, centered
        case expanded  // Icons + labels, leading-aligned
    }

    /// User's explicit preference (mirrored through the file-backed settings config)
    var iconsOnly: Bool

    /// Derived from iconsOnly
    private(set) var renderMode: RenderMode

    /// Locked at 52 — toggle is the only way out (same as main sidebar pattern)
    static let compactColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (52, 52, 52)
    /// Min 140 forces position up from 52 when expanding (52 < 140 → clamps to 140)
    /// High enough to prevent label wrapping in sidebar items
    static let expandedColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (140, 160, 360)

    init(iconsOnly: Bool = false) {
        self.iconsOnly = iconsOnly
        self.renderMode = iconsOnly ? .compact : .expanded
    }

    /// User clicked gear header or edge handle
    mutating func toggle() {
        iconsOnly.toggle()
        renderMode = iconsOnly ? .compact : .expanded
    }

    // MARK: - Visual properties

    var isCompact: Bool { renderMode == .compact }
    var labelsVisible: Bool { renderMode == .expanded }
    var sectionHeadersVisible: Bool { renderMode == .expanded }

    // MARK: - Column width output

    var desiredColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        isCompact ? Self.compactColumnWidth : Self.expandedColumnWidth
    }
}
