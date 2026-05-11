import Foundation
import AppKit
import TalkieKit

private let log = Log(.system)

@MainActor
final class IdleWatchdog {
    static let shared = IdleWatchdog()

    private let idleTimeout: TimeInterval = 120
    private let checkInterval: TimeInterval = 15

    private var timer: Timer?
    private var lastActivityAt = Date()
    private var activeSessionCount = 0

    private init() {}

    func start() {
        stop()
        lastActivityAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdle()
            }
        }
        log.info("TalkieMic idle watchdog started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markActivity() {
        lastActivityAt = Date()
    }

    func setActiveSessionCount(_ count: Int) {
        activeSessionCount = count
        lastActivityAt = Date()
    }

    private func checkIdle() {
        guard activeSessionCount == 0 else { return }

        let idleSeconds = Date().timeIntervalSince(lastActivityAt)
        guard idleSeconds >= idleTimeout else { return }

        log.info("TalkieMic idle timeout reached, terminating")
        NSApp.terminate(nil)
    }
}
