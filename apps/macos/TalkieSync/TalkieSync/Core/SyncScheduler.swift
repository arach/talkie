//
//  SyncScheduler.swift
//  TalkieSync
//
//  Handles periodic and background sync scheduling.
//  Uses NSBackgroundActivityScheduler for power-efficient background syncs.
//

import Foundation
import TalkieKit

private let log = Log(.sync)

/// Manages sync scheduling for TalkieSync
/// Supports both foreground timer-based sync and background activity sync
@MainActor
final class SyncScheduler {
    static let shared = SyncScheduler()

    // Sync intervals
    private let foregroundInterval: TimeInterval = 86400  // 1 day
    private let backgroundInterval: TimeInterval = 86400  // 1 day for background
    private let minimumTriggerInterval: TimeInterval = 86400
    private var lastTriggerAt: Date = .distantPast

    private var foregroundTimer: Timer?
    private var backgroundScheduler: NSBackgroundActivityScheduler?

    private init() {}

    // MARK: - Start/Stop

    /// Start sync scheduling.
    func start() {
        startForegroundTimer()
        startBackgroundScheduler()
        log.info("Sync scheduler started (foreground: \(Int(foregroundInterval))s, background: \(Int(backgroundInterval))s)")
    }

    /// Stop all sync scheduling
    func stop() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil

        backgroundScheduler?.invalidate()
        backgroundScheduler = nil

        log.info("Sync scheduler stopped")
    }

    // MARK: - Foreground Scheduling

    private func startForegroundTimer() {
        foregroundTimer?.invalidate()

        foregroundTimer = Timer.scheduledTimer(withTimeInterval: foregroundInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.triggerSync(reason: "scheduled")
            }
        }
    }

    // MARK: - Background Scheduling

    private func startBackgroundScheduler() {
        let env = TalkieEnvironment.current
        let scheduler = NSBackgroundActivityScheduler(
            identifier: "\(TalkieHelper.sync.bundleId(for: env)).background-sync"
        )

        scheduler.repeats = true
        scheduler.interval = backgroundInterval
        scheduler.qualityOfService = .utility

        scheduler.schedule { [weak self] completion in
            guard let self else {
                completion(.finished)
                return
            }

            Task { @MainActor in
                await self.triggerSync(reason: "background")
                completion(.finished)
            }
        }

        backgroundScheduler = scheduler
    }

    // MARK: - Sync Trigger

    private func triggerSync(reason: String) async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTriggerAt)
        guard elapsed >= minimumTriggerInterval else {
            let remaining = Int((minimumTriggerInterval - elapsed).rounded(.up))
            log.info("Skipping \(reason) sync - rate limited (\(remaining)s remaining)")
            return
        }
        lastTriggerAt = now

        log.info("Triggering sync (reason: \(reason))")

        // Use the XPC service's sync method to keep state consistent
        TalkieSyncXPCService.shared.syncNow { success, error in
            if let error = error {
                log.error("Scheduled sync failed: \(error)")
            } else if success {
                log.debug("Scheduled sync completed")
            }
        }
    }

    // MARK: - Manual Triggers

    /// Trigger an immediate sync
    func syncNow() {
        Task { @MainActor in
            await triggerSync(reason: "manual")
        }
    }
}
