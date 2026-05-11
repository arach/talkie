//
//  RelativeTimeTicker.swift
//  Talkie macOS
//
//  Shared timer for relative time labels.
//

import Foundation
import Observation

@MainActor
@Observable
final class RelativeTimeTicker {
    static let shared = RelativeTimeTicker()
    static let refreshInterval: TimeInterval = 60

    var now = Date()

    @ObservationIgnored private var timer: Timer?

    private init() {
        StartupProfiler.shared.mark("singleton.RelativeTimeTicker.start")
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.now = Date()
            }
        }
        StartupProfiler.shared.mark("singleton.RelativeTimeTicker.done")
    }

    deinit {
        timer?.invalidate()
    }
}
