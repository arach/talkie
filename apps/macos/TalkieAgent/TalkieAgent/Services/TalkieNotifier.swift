//
//  TalkieNotifier.swift
//  TalkieAgent
//
//  Centralized notifications to Talkie.
//  All Live → Main communication goes through here for:
//  - Consistent logging
//  - Metrics tracking
//  - Environment-aware delivery
//
//  Internal state notifications (recording, transcribing, etc.) use
//  DistributedNotificationCenter to avoid bringing Talkie to the foreground.
//  User-facing navigations (compose, agent/recent) still use URL opening.
//

import Foundation
import AppKit
import TalkieKit
import os.log

private let logger = Logger(subsystem: "to.talkie.app.agent", category: "Notifier")

/// Notification name prefix for distributed notifications from TalkieAgent → Talkie
/// Format: to.talkie.app.agent.{path} (e.g., to.talkie.app.agent.recording.started)
let kTalkieAgentNotificationPrefix = "to.talkie.app.agent"

@MainActor
final class TalkieNotifier {
    static let shared = TalkieNotifier()

    // MARK: - Metrics

    private(set) var totalNotifications: Int = 0
    private(set) var notificationCounts: [String: Int] = [:]
    private(set) var lastNotificationTime: Date?
    private(set) var failureCount: Int = 0
    private(set) var skippedCount: Int = 0  // Skipped because Talkie not running

    private init() {}

    // MARK: - Talkie Detection

    /// Check if Talkie main app is running (any environment)
    private var isTalkieRunning: Bool {
        let talkieBundleIDs = [
            "to.talkie.app.mac",      // Production
            "to.talkie.app.mac.dev"   // Development
        ]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return talkieBundleIDs.contains(bundleID)
        }
    }

    // MARK: - State Notifications (silent — no window activation)

    /// Notify Talkie that recording started
    func recordingStarted() {
        sendSilent("recording.started")
    }

    /// Notify Talkie that recording stopped
    func recordingStopped() {
        sendSilent("recording.stopped")
    }

    /// Notify Talkie that recording was cancelled
    func recordingCancelled() {
        sendSilent("recording.cancelled")
    }

    /// Notify Talkie that transcription is in progress
    func transcribing() {
        sendSilent("transcribing")
    }

    /// Notify Talkie that output routing is in progress
    func routing() {
        sendSilent("routing")
    }

    // MARK: - Ambient Mode

    /// Notify Talkie of an ambient voice command
    func ambientCommand(_ command: String) {
        sendSilent("ambient.command", userInfo: ["cmd": command])
    }

    // MARK: - Data Notifications (silent — refresh without activation)

    /// Notify Talkie that a new dictation was saved
    func dictationAdded(id: String? = nil) {
        var info: [String: String] = [:]
        if let id { info["id"] = id }
        sendSilent("dictation.new", userInfo: info)
    }

    /// Notify Talkie that the queue was updated
    func queueUpdated(count: Int) {
        sendSilent("queue.updated", userInfo: ["count": String(count)])
    }

    /// Notify Talkie that a background Walkie executor finished and has a user-facing report.
    func walkieReport(
        sessionId: String,
        title: String,
        body: String,
        spokenSummary: String?,
        source: String?
    ) {
        var info: [String: String] = [
            "sessionId": sessionId,
            "title": Self.truncateForNotificationField(title, maxLength: 120),
            "body": Self.truncateForNotificationField(body, maxLength: 1_200),
        ]
        if let spokenSummary, !spokenSummary.isEmpty {
            info["spokenSummary"] = Self.truncateForNotificationField(spokenSummary, maxLength: 600)
        }
        if let source, !source.isEmpty {
            info["source"] = Self.truncateForNotificationField(source, maxLength: 80)
        }
        sendSilent("walkie.report", userInfo: info)
    }

    // MARK: - Lifecycle

    /// Notify Talkie that Live is ready
    func liveReady() {
        sendSilent("live.ready")
    }

    // MARK: - Errors

    /// Notify Talkie of an error
    func error(_ message: String) {
        sendSilent("error", userInfo: ["msg": message])
    }

    // MARK: - Silent Send (DistributedNotificationCenter)

    /// Send a notification via DistributedNotificationCenter — never activates Talkie
    private func sendSilent(_ name: String, userInfo: [String: String] = [:]) {
        guard isTalkieRunning else {
            skippedCount += 1
            logger.debug("↷ \(name) (Talkie not running, skipped)")
            return
        }

        // Track metrics
        totalNotifications += 1
        notificationCounts[name, default: 0] += 1
        lastNotificationTime = Date()

        logger.info("→ \(name)")

        let notificationName = Notification.Name("\(kTalkieAgentNotificationPrefix).\(name)")
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo,
            deliverImmediately: true
        )
    }

    // MARK: - URL Send (activates Talkie — for user-facing navigation)

    /// Send a URL notification — may activate Talkie (use for navigation only)
    func sendURL(_ path: String, params: [String: String] = [:]) {
        guard isTalkieRunning else {
            skippedCount += 1
            logger.debug("↷ \(path) (Talkie not running, skipped)")
            return
        }

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

        logger.info("→ \(path) (URL)")

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false

        NSWorkspace.shared.open(url, configuration: config) { [weak self] _, error in
            if let error = error {
                self?.failureCount += 1
                logger.debug("Notification delivery issue: \(error.localizedDescription)")
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
        print("Skipped (Talkie not running): \(skippedCount)")
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
        skippedCount = 0
    }

    private static func truncateForNotificationField(_ text: String, maxLength: Int) -> String {
        let clean = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard clean.count > maxLength else { return clean }
        return String(clean.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
