//
//  TalkieNotifier.swift
//  TalkieLive
//
//  Centralized URL notifications to Talkie.
//  All Live → Main communication goes through here for:
//  - Consistent logging
//  - Metrics tracking
//  - Environment-aware URLs
//

import Foundation
import AppKit
import TalkieKit
import os.log

private let logger = Logger(subsystem: "com.jdi.talkie.live", category: "Notifier")

@MainActor
final class TalkieNotifier {
    static let shared = TalkieNotifier()

    // MARK: - Metrics

    private(set) var totalNotifications: Int = 0
    private(set) var notificationCounts: [String: Int] = [:]
    private(set) var lastNotificationTime: Date?
    private(set) var failureCount: Int = 0

    private init() {}

    // MARK: - State Notifications

    /// Notify Talkie that recording started
    func recordingStarted() {
        send("recording/started")
    }

    /// Notify Talkie that recording stopped
    func recordingStopped() {
        send("recording/stopped")
    }

    /// Notify Talkie that recording was cancelled
    func recordingCancelled() {
        send("recording/cancelled")
    }

    /// Notify Talkie that transcription is in progress
    func transcribing() {
        send("transcribing")
    }

    /// Notify Talkie that output routing is in progress
    func routing() {
        send("routing")
    }

    // MARK: - Ambient Mode

    /// Notify Talkie of an ambient voice command
    func ambientCommand(_ command: String) {
        // URL-encode the command for safe transmission
        send("ambient/command", params: ["cmd": command])
    }

    // MARK: - Data Notifications

    /// Notify Talkie that a new dictation was saved
    func dictationAdded(id: String? = nil) {
        if let id = id {
            send("dictation/new", params: ["id": id])
        } else {
            send("dictation/new")
        }
    }

    /// Notify Talkie that the queue was updated
    func queueUpdated(count: Int) {
        send("queue/updated", params: ["count": String(count)])
    }

    // MARK: - Lifecycle

    /// Notify Talkie that Live is ready
    func liveReady() {
        send("live/ready")
    }

    // MARK: - Errors

    /// Notify Talkie of an error
    func error(_ message: String) {
        send("error", params: ["msg": message])
    }

    // MARK: - Core Send

    private func send(_ path: String, params: [String: String] = [:]) {
        let scheme = TalkieEnvironment.current.talkieURLScheme
        var urlString = "\(scheme)://\(path)"

        if !params.isEmpty {
            let query = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
                .joined(separator: "&")
            urlString += "?\(query)"
        }

        guard let url = URL(string: urlString) else {
            logger.error("Invalid URL: \(urlString)")
            return
        }

        // Track metrics
        totalNotifications += 1
        notificationCounts[path, default: 0] += 1
        lastNotificationTime = Date()

        logger.info("→ \(path)")

        // Send without activating Talkie
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false

        NSWorkspace.shared.open(url, configuration: config) { [weak self] _, error in
            if let error = error {
                self?.failureCount += 1
                // Log at debug level - Talkie not running is normal
                logger.debug("Notification not delivered (Talkie may not be running): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Debug

    func printMetrics() {
        print("")
        print("╔══════════════════════════════════════╗")
        print("║     TALKIE NOTIFIER METRICS          ║")
        print("╚══════════════════════════════════════╝")
        print("")
        print("Total sent: \(totalNotifications)")
        print("Failures: \(failureCount)")
        print("")
        print("By type:")
        for (path, count) in notificationCounts.sorted(by: { $0.value > $1.value }) {
            print("  \(path): \(count)")
        }
        print("")
    }

    func resetMetrics() {
        totalNotifications = 0
        notificationCounts = [:]
        failureCount = 0
    }
}
