//
//  RelativeTimeLabel.swift
//  Talkie macOS
//
//  Shared relative time label with periodic refresh.
//

import SwiftUI

struct RelativeTimeLabel: View {
    static let defaultRefreshInterval: TimeInterval = 60

    let date: Date
    var interval: TimeInterval = defaultRefreshInterval
    let formatter: (Date) -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { _ in
            Text(formatter(date))
        }
    }
}
