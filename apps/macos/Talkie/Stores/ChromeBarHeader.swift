//
//  ChromeBarHeader.swift
//  Talkie
//
//  Shared observable for page header content surfaced into the
//  TalkieChromeBar. Each page publishes its title + subtitle on
//  appear; the bar reads and renders them around the pill.
//

import Foundation
import Observation

@MainActor
@Observable
final class ChromeBarHeader {
    static let shared = ChromeBarHeader()

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

    private init() {}

    func set(title: String?, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    func clear() {
        title = nil
        subtitle = nil
    }
}
