//
//  LiveDataStore.swift
//  Talkie
//
//  Read-only access to TalkieLive's SQLite database (live.sqlite).
//  Uses shared Application Support directory (all apps are unsandboxed).
//

import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveDataStore")

/// Read-only data store for accessing TalkieLive's utterance database
@MainActor
final class LiveDataStore: ObservableObject {
    static let shared = LiveDataStore()

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

        // All apps are unsandboxed, so they share ~/Library/Application Support/Talkie/
        var possiblePaths: [URL] = []

        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // 1. New shared location: ~/Library/Application Support/Talkie/live.sqlite
            let sharedPath = appSupport
                .appendingPathComponent("Talkie", isDirectory: true)
                .appendingPathComponent("live.sqlite")
            possiblePaths.append(sharedPath)
            logger.info("[LiveDataStore] Checking shared location: \(sharedPath.path)")

            // 2. Old Group Container location (for migration)
            let oldGroupPath = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/group.com.jdi.talkie/TalkieLive/live.sqlite")
            if fm.fileExists(atPath: oldGroupPath.path) {
                possiblePaths.append(oldGroupPath)
                logger.info("[LiveDataStore] Found old Group Container data: \(oldGroupPath.path)")
            }

            // 3. Old Application Support location (for migration)
            let oldLocalPath = appSupport
                .appendingPathComponent("TalkieLive", isDirectory: true)
                .appendingPathComponent("live.sqlite")
            possiblePaths.append(oldLocalPath)
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
                           durationSeconds, wordCount, transcriptionModel, audioFilename,
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
                        transcriptionModel: row["transcriptionModel"],
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
