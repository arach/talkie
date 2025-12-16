//
//  LiveDataStore.swift
//  Talkie
//
//  Read-only access to TalkieLive's SQLite database (PastLives.sqlite).
//  Uses shared App Group container for cross-app data sharing.
//

import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveDataStore")

/// Read-only data store for accessing TalkieLive's utterance database
@MainActor
final class LiveDataStore: ObservableObject {
    static let shared = LiveDataStore()

    /// App Group identifier shared with TalkieLive
    static let appGroupID = "group.com.jdi.talkie"

    // MARK: - Published State

    @Published private(set) var utterances: [LiveUtterance] = []
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var error: String?
    @Published private(set) var databasePath: String = ""

    // MARK: - Private

    private var dbQueue: DatabaseQueue?
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 5.0

    private init() {
        connectToDatabase()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Database Connection

    private func connectToDatabase() {
        let fm = FileManager.default

        // Try to find the database in order of preference:
        // 1. Shared App Group container (production)
        // 2. Unsandboxed Application Support (dev mode)

        var possiblePaths: [URL] = []

        // 1. App Group container (shared with TalkieLive) - current filename
        if let groupContainer = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            let groupPath = groupContainer
                .appendingPathComponent("TalkieLive", isDirectory: true)
                .appendingPathComponent("live.sqlite")
            possiblePaths.append(groupPath)
            logger.info("[LiveDataStore] Checking App Group: \(groupPath.path)")
        }

        // 2. Unsandboxed Application Support (fallback for dev)
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let localPath = appSupport
                .appendingPathComponent("TalkieLive", isDirectory: true)
                .appendingPathComponent("live.sqlite")
            possiblePaths.append(localPath)
        }

        // Try each path
        for path in possiblePaths {
            if fm.fileExists(atPath: path.path) {
                do {
                    // Open in read-only mode
                    var config = Configuration()
                    config.readonly = true

                    dbQueue = try DatabaseQueue(path: path.path, configuration: config)
                    databasePath = path.path
                    isAvailable = true
                    logger.info("[LiveDataStore] Connected to database: \(path.path)")
                    refresh()
                    return
                } catch {
                    logger.error("[LiveDataStore] Failed to open \(path.path): \(error.localizedDescription)")
                }
            } else {
                logger.debug("[LiveDataStore] Not found: \(path.path)")
            }
        }

        logger.warning("[LiveDataStore] TalkieLive database not found")
        isAvailable = false
        error = "TalkieLive database not found. Make sure TalkieLive has been run."
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard refreshTimer == nil else { return }

        logger.info("[LiveDataStore] Starting periodic refresh (every \(Int(self.refreshInterval))s)")
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        logger.info("[LiveDataStore] Stopped periodic refresh")
    }

    // MARK: - Data Access

    func refresh() {
        guard let dbQueue = dbQueue else {
            // Try to reconnect
            connectToDatabase()
            return
        }

        do {
            let fetched = try dbQueue.read { db -> [LiveUtterance] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, createdAt, text, mode, appBundleID, appName, windowTitle,
                           durationSeconds, wordCount, whisperModel, audioFilename,
                           transcriptionStatus, promotionStatus, talkieMemoID
                    FROM utterances
                    ORDER BY createdAt DESC
                    LIMIT 500
                    """)

                return rows.compactMap { row -> LiveUtterance? in
                    guard let id: Int64 = row["id"],
                          let createdAtTs: Double = row["createdAt"] else {
                        return nil
                    }

                    return LiveUtterance(
                        id: id,
                        createdAt: Date(timeIntervalSince1970: createdAtTs),
                        text: row["text"] ?? "",
                        mode: row["mode"] ?? "default",
                        appBundleID: row["appBundleID"],
                        appName: row["appName"],
                        windowTitle: row["windowTitle"],
                        durationSeconds: row["durationSeconds"],
                        wordCount: row["wordCount"],
                        whisperModel: row["whisperModel"],
                        audioFilename: row["audioFilename"],
                        transcriptionStatus: LiveTranscriptionStatus(rawValue: row["transcriptionStatus"] ?? "success") ?? .success,
                        promotionStatus: LivePromotionStatus(rawValue: row["promotionStatus"] ?? "none") ?? .none,
                        talkieMemoID: row["talkieMemoID"]
                    )
                }
            }

            utterances = fetched
            lastRefresh = Date()
            error = nil

        } catch {
            logger.error("[LiveDataStore] Refresh failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    // MARK: - Filtering

    func utterances(withStatus status: LivePromotionStatus) -> [LiveUtterance] {
        utterances.filter { $0.promotionStatus == status }
    }

    var promotableUtterances: [LiveUtterance] {
        utterances.filter { $0.canPromote }
    }

    var needsActionCount: Int {
        promotableUtterances.count
    }

    func search(_ query: String) -> [LiveUtterance] {
        guard !query.isEmpty else { return utterances }
        let lowercased = query.lowercased()
        return utterances.filter { $0.text.lowercased().contains(lowercased) }
    }

    func utterance(id: Int64) -> LiveUtterance? {
        utterances.first { $0.id == id }
    }

    /// Fetch the most recent utterance (for debug/test purposes)
    func fetchRecentUtterance() -> LiveUtterance? {
        // Ensure we have fresh data
        if utterances.isEmpty {
            refresh()
        }
        return utterances.first
    }

    // MARK: - Statistics

    var totalCount: Int {
        utterances.count
    }

    func count(byStatus status: LivePromotionStatus) -> Int {
        utterances.filter { $0.promotionStatus == status }.count
    }

    var lastRefreshAgo: String {
        guard let lastRefresh = lastRefresh else { return "—" }

        let interval = Date().timeIntervalSince(lastRefresh)
        if interval < 5 {
            return "just now"
        } else if interval < 60 {
            return "\(Int(interval))s ago"
        } else {
            return "\(Int(interval / 60))m ago"
        }
    }
}
