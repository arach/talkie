//
//  ScreenZones.swift
//  Talkie iOS
//
//  Shared placement vocabulary for chrome complications + screen-
//  native top-row UI. Both sides name their position with the same
//  ScreenZone enum so the shell can coordinate visibility: when
//  chrome takes a corner, the screen's content in that corner
//  yields (fades out) until chrome dismisses. Polite by default.
//

import SwiftUI

/// One of the four corner anchor points on the screen. Used by
/// ChromeOverlay's complications (Done / Settings / Keyboard) and by
/// any per-screen header element that wants to coordinate visibility
/// with chrome (back chevron, title, ellipsis menus, etc).
enum ScreenZone: CaseIterable, Hashable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

/// Place content at a named screen corner using SwiftUI alignment.
/// Used inside overlay containers (ZStack-style) to anchor a single
/// piece of UI to a specific corner without re-deriving the maxWidth/
/// alignment dance at every call site.
struct InZone<Content: View>: View {
    let zone: ScreenZone
    @ViewBuilder var content: () -> Content

    init(_ zone: ScreenZone, @ViewBuilder content: @escaping () -> Content) {
        self.zone = zone
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: zone.alignment)
    }
}

/// Hide a piece of screen-native UI when chrome occupies its zone.
/// The complication wins the corner; the screen's local content (back
/// chevron, ellipsis menu, etc) fades out until chrome dismisses.
private struct YieldsToChromeZoneModifier: ViewModifier {
    let zone: ScreenZone
    @EnvironmentObject private var chrome: ShellChrome

    func body(content: Content) -> some View {
        content
            .opacity(chrome.occupiedZones.contains(zone) ? 0 : 1)
            .animation(.easeOut(duration: 0.20), value: chrome.occupiedZones)
    }
}

extension View {
    /// Fade this view out when chrome occupies the given zone. Apply
    /// to screen-native top-row content that would otherwise collide
    /// with a chrome corner pill.
    func yieldsToChromeZone(_ zone: ScreenZone) -> some View {
        modifier(YieldsToChromeZoneModifier(zone: zone))
    }
}
