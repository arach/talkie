//
//  ChromeBarPageHeaderOverlay.swift
//  Talkie
//
//  Renders the page title + chrome line at the band Y position, layered
//  *above* the TalkieChromeBar in z-order. Driven by the window-local
//  `ChromeBarHeader`, which each page updates on appear. Lets the band
//  text stay visually
//  on top of the bar's cream capsule where they overlap horizontally,
//  instead of being overwritten.
//

import SwiftUI
import TalkieKit

struct ChromeBarPageHeaderOverlay: View {
    @Environment(\.chromeBarHeader) private var header

    var body: some View {
        if let title = header.title, !title.isEmpty {
            ScopeTopBand(title: title, chrome: header.subtitle)
        }
    }
}
