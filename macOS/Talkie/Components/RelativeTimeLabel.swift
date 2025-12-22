//
//  RelativeTimeLabel.swift
//  Talkie macOS
//
//  Shared relative time label with periodic refresh.
//

import SwiftUI

struct RelativeTimeLabel: View {
    @Environment(RelativeTimeTicker.self) private var ticker

    let date: Date
    let formatter: (Date) -> String

    var body: some View {
        // Reference ticker time to invalidate the view on each tick.
        let _ = ticker.now
        Text(formatter(date))
    }
}
