//
//  ChromeBarHeader.swift
//  Talkie
//
//  Window-local observable for page header content surfaced into the
//  TalkieChromeBar. Each root window injects its own instance so the
//  title, subtitle, and hover reveal do not mirror across windows.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ChromeBarHeader {
    nonisolated static let shared = ChromeBarHeader()

    /// Display-font page title (e.g., "Today", "Library", "Compose").
    /// nil hides the title row.
    var title: String? = nil

    /// Small chrome eyebrow line beneath the bar (e.g., "5-DAY STREAK · 12K WORDS").
    /// nil hides the subtitle row.
    var subtitle: String? = nil

    /// Whether the chrome bar is currently hovered. AppNavigation observes
    /// this to flip the window toolbar background to cream paper so the
    /// chrome bar's hover state visually extends across the title row.
    var hovered: Bool = false

    nonisolated init() {}

    func set(title: String?, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    func clear() {
        title = nil
        subtitle = nil
    }
}

// MARK: - Environment

private struct ChromeBarHeaderKey: EnvironmentKey {
    static let defaultValue = ChromeBarHeader.shared
}

extension EnvironmentValues {
    var chromeBarHeader: ChromeBarHeader {
        get { self[ChromeBarHeaderKey.self] }
        set { self[ChromeBarHeaderKey.self] = newValue }
    }
}

extension View {
    func withChromeBarHeader(_ header: ChromeBarHeader) -> some View {
        environment(\.chromeBarHeader, header)
    }
}
