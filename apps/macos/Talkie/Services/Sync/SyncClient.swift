//
//  SyncClient.swift
//  Talkie
//
//  XPC client for communicating with TalkieSync helper service.
//  Provides async/await interface for sync operations.
//

import Foundation
import Observation
import os
import TalkieKit

private let log = Log(.sync)
private enum SyncClientDefaults {
    static let maxActivityLogEntries = 80
    static let automaticSyncMinimumInterval: TimeInterval = 86400
    static let lastAutomaticSyncDateDefaultsKey = "SyncClient.lastAutomaticSyncDate"
}

/// Client for TalkieSync XPC service
///
/// Provides sync control and status monitoring for the main Talkie app.
/// All actual sync work happens in TalkieSync process.
@MainActor
@Observable
public final class SyncClient: TalkieSyncObserverProtocol {
    public static let shared = SyncClient()

    // MARK: - State

    public private(set) var isSyncing = false
    public private(set) var lastSyncDate: Date?
    public private(set) var syncError: String?
    public private(set) var iCloudAvailable = false
    public private(set) var syncProgress: Double = 0
    public private(set) var syncStatusMessage: String = ""
    public private(set) var lastSyncStats: SyncCompletionStats?
    private var syncStartTime: Date?
    private var lastSyncCompletedNotificationAt: Date = .distantPast
    private let syncCompletedNotificationMinIntervalSeconds: TimeInterval = 5
    private var inFlightSyncNowTask: Task<Void, Error>?
    private var lastAutomaticSyncDate: Date?

    // MARK: - Activity Log

    /// Live activity log entries visible in the Sync panel UI.
    /// Shows step-by-step what SyncClient is doing so the user isn't in the dark.
    public var activityLog: [SyncActivityEntry] = []
    private let maxActivityEntries = SyncClientDefaults.maxActivityLogEntries

    // MARK: - XPC

    private var connection: NSXPCConnection?
    public private(set) var isConnected = false
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private var remoteMemoDiagnosticsAvailable = true
    private var lastProgressMessageLogged: String = ""
    private var lastProgressMessageLoggedAt: Date = .distantPast

    private var readinessObserver: NSObjectProtocol?

    private init() {
        lastAutomaticSyncDate = UserDefaults.standard.object(
            forKey: SyncClientDefaults.lastAutomaticSyncDateDefaultsKey
        ) as? Date
        listenForReadinessSignal()
    }

    // MARK: - Readiness Signal

    /// Listen for TalkieSync's readiness notification (posted after XPC listener starts).
    /// Auto-connects when signal arrives, so Talkie doesn't try to connect before the pipe is ready.
    private func listenForReadinessSignal() {
        let env = TalkieEnvironment.current
        let noteName = TalkieHelper.sync.xpcReadyNotificationName(for: env)

        readinessObserver = DistributedNotificationCenter.default().addObserver(
            forName: noteName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            log.info("TalkieSync readiness signal received — connecting")
            Task { @MainActor in
                self.logActivity("Readiness signal received from TalkieSync")
                if !self.isConnected {
                    self.connect()
                }
            }
        }

        log.debug("Listening for readiness signal: \(noteName.rawValue)")
    }

    // MARK: - Connection Management

    /// Connect to TalkieSync service
    ///
    /// Resumes the XPC connection but does NOT set `isConnected = true` until
    /// a ping() round-trip succeeds. This prevents the UI from showing "Connected"
    /// when the process is running but the XPC listener isn't ready yet.
    public func connect() {
        if let existing = connection {
            // Recover from half-open connections: retain only fully verified pipes.
            guard !isConnected else { return }
            invalidateConnection(existing)
            log.debug("Dropped stale TalkieSync connection before reconnect")
        }

        log.info("Connecting to TalkieSync...")
        logActivity("Connecting via MachService: \(kTalkieSyncXPCServiceName)")

        let conn = NSXPCConnection(machServiceName: kTalkieSyncXPCServiceName, options: [])

        // We export the observer protocol for callbacks
        conn.exportedInterface = NSXPCInterface(with: TalkieSyncObserverProtocol.self)
        conn.exportedObject = self

        // We call the service protocol
        conn.remoteObjectInterface = NSXPCInterface(with: TalkieSyncXPCProtocol.self)

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect()
            }
        }

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                log.warning("TalkieSync connection interrupted")
                self?.logActivity("Connection interrupted (process may have restarted)", level: .warning)
                self?.isConnected = false
                self?.scheduleReconnect()
            }
        }

        conn.resume()
        connection = conn
        reconnectAttempts = 0

        // Don't set isConnected = true yet — verify the pipe works first
        Task { [weak self, conn] in
            guard let self else { return }
            let alive = await ping()
            // If connection changed while we were pinging, ignore the result
            guard connection === conn else { return }
            if alive {
                isConnected = true
                remoteMemoDiagnosticsAvailable = true
                ServiceManager.shared.sync.updateConnectionState(connected: true, environment: TalkieEnvironment.current)
                log.info("Connected to TalkieSync (verified)")
                logActivity("Connected to TalkieSync (verified)", level: .success)
                await refreshStatus()
            } else {
                log.warning("TalkieSync connection resumed but ping failed — scheduling reconnect")
                logActivity("Ping failed — connection not usable", level: .warning)
                invalidateConnection(conn)
                scheduleReconnect()
            }
        }
    }

    /// Force reconnect - drops current connection and rescans for sync service
    public func reconnect() {
        log.info("Force reconnecting to TalkieSync...")
        disconnect()

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            connect()
        }
    }

    /// Disconnect from TalkieSync service
    public func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        connection?.invalidate()
        connection = nil
        isConnected = false

        // Update ServiceManager sync state
        ServiceManager.shared.sync.updateConnectionState(connected: false, environment: nil)

        log.info("Disconnected from TalkieSync")
    }

    private func handleDisconnect() {
        connection = nil
        isConnected = false

        // Update ServiceManager sync state
        ServiceManager.shared.sync.updateConnectionState(connected: false, environment: nil)

        if SettingsManager.shared.syncOnLaunch {
            log.warning("TalkieSync connection invalidated")
            logActivity("Connection invalidated", level: .warning)
        } else {
            log.debug("TalkieSync connection invalidated (on-demand mode)")
            logActivity("Connection invalidated (on-demand mode)")
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()

        // Only auto-reconnect if sync is configured to run continuously
        guard SettingsManager.shared.syncOnLaunch else {
            log.debug("Sync is on-demand, not scheduling reconnect")
            return
        }

        // Graduated backoff
        let delay: TimeInterval
        if reconnectAttempts < 5 {
            delay = 2  // First 5 attempts: 2s
        } else if reconnectAttempts < 10 {
            delay = 10  // Next 5: 10s
        } else {
            delay = 60  // After that: 60s
        }

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.reconnectAttempts += 1
                self?.connect()
            }
        }
    }

    /// Invalidate connection without running disconnect handlers.
    private func invalidateConnection(_ conn: NSXPCConnection) {
        guard connection === conn else { return }
        conn.invalidationHandler = nil
        conn.interruptionHandler = nil
        conn.invalidate()
        connection = nil
        isConnected = false
        ServiceManager.shared.sync.updateConnectionState(connected: false, environment: nil)
    }

    /// Create a proxy with error handler wired to an atomic guard.
    /// Returns nil if no connection. The `onError` closure fires at most once
    /// (guarded by `resumed`) when XPC can't deliver the message.
    private func makeProxy(
        resumed: OSAllocatedUnfairLock<Bool>,
        onError: @escaping @Sendable () -> Void
    ) -> TalkieSyncXPCProtocol? {
        guard let conn = connection else { return nil }
        return conn.remoteObjectProxyWithErrorHandler { error in
            let description = error.localizedDescription
            if SettingsManager.shared.syncOnLaunch {
                log.error("XPC error: \(description)")
            } else {
                log.warning("XPC unavailable in on-demand mode: \(description)")
            }
            if resumed.withLock({ old in let was = old; old = true; return !was }) {
                onError()
            }
        } as? TalkieSyncXPCProtocol
    }

    // MARK: - Sync Operations

    /// Run a one-time sync operation
    ///
    /// This is the preferred method for on-demand sync. It:
    /// 1. Launches TalkieSync if not running
    /// 2. Connects to the service
    /// 3. Captures before/after counts
    /// 4. Runs the sync
    /// 5. Records a sync event with meaningful stats
    /// 6. Optionally terminates TalkieSync after completion
    ///
    /// - Parameter keepRunning: If false, terminates TalkieSync after sync completes (default: false)
    /// - Throws: SyncClientError if sync fails
    public func runSyncOnce(keepRunning: Bool = false) async throws {
        guard !isSyncing else {
            log.info("Sync already in progress, skipping runSyncOnce")
            return
        }

        log.info("Running one-time sync (keepRunning: \(keepRunning))")

        // Set immediate feedback
        isSyncing = true
        syncProgress = 0
        syncError = nil
        syncStartTime = Date()
        lastProgressMessageLogged = ""
        lastProgressMessageLoggedAt = .distantPast

        // Track whether TalkieSync was already running — don't kill what we didn't start
        let wasAlreadyRunning = ServiceManager.shared.sync.isRunning
        let runActivityStartIndex = activityLog.count

        do {
            logActivity("Starting sync...")

            // 1. Verify existing connection is alive, or start fresh
            if isConnected {
                logActivity("Verifying existing connection...")
                let alive = await ping()
                if !alive {
                    log.warning("Stale connection detected — disconnecting")
                    logActivity("Stale connection — disconnecting", level: .warning)
                    disconnect()
                } else {
                    logActivity("Existing connection is healthy", level: .success)
                }
            }

            // 2. Launch TalkieSync if not running
            ServiceManager.shared.refreshStatus()
            if ServiceManager.shared.effectiveHelperEnvironment != .production,
               ServiceManager.shared.sync.isRunning,
               !isConnected {
                syncStatusMessage = "Refreshing sync service..."
                logActivity("Refreshing TalkieSync launch wiring...")
                ServiceManager.shared.launchSync(forceRefreshInDev: true)

                for i in 0..<20 {
                    try await Task.sleep(for: .milliseconds(500))
                    ServiceManager.shared.refreshStatus()
                    syncProgress = max(syncProgress, Double(i) / 60.0)
                    if ServiceManager.shared.sync.isRunning {
                        break
                    }
                }
            }

            ServiceManager.shared.refreshStatus()
            if !ServiceManager.shared.sync.isRunning {
                syncStatusMessage = "Launching sync service..."
                logActivity("TalkieSync not running — launching...")
                log.info("Launching TalkieSync for one-time sync...")
                ServiceManager.shared.launchSync()

                // Wait for it to start (up to 10 seconds)
                for i in 0..<20 {
                    try await Task.sleep(for: .milliseconds(500))
                    ServiceManager.shared.refreshStatus()
                    syncProgress = Double(i) / 60.0  // First third of progress
                    if ServiceManager.shared.sync.isRunning {
                        logActivity("TalkieSync started (PID \(ServiceManager.shared.sync.processId ?? 0))", level: .success)
                        break
                    }
                }

                guard ServiceManager.shared.sync.isRunning else {
                    logActivity("Failed to launch TalkieSync after 10s", level: .error)
                    throw SyncClientError.syncFailed("Failed to launch TalkieSync")
                }
            } else {
                let pid = ServiceManager.shared.sync.processId ?? 0
                logActivity("TalkieSync already running (PID \(pid))")
            }

            // 3. Connect if not connected
            if !isConnected {
                syncStatusMessage = "Connecting..."
                syncProgress = 0.33
                let maxConnectAttempts = 3
                let waitTicksPerAttempt = 12  // 12 * 500ms = 6s per attempt
                let totalTicks = maxConnectAttempts * waitTicksPerAttempt

                for attempt in 1...maxConnectAttempts {
                    if isConnected { break }
                    if attempt > 1 {
                        logActivity("Retrying XPC connection (\(attempt)/\(maxConnectAttempts))...")
                    }

                    connect()

                    for tick in 0..<waitTicksPerAttempt {
                        try await Task.sleep(for: .milliseconds(500))

                        // Advance through the second third of progress while we wait for XPC readiness.
                        let elapsedTicks = ((attempt - 1) * waitTicksPerAttempt) + tick + 1
                        syncProgress = 0.33 + (Double(elapsedTicks) / Double(totalTicks)) * 0.17

                        if isConnected {
                            break
                        }
                    }
                }

                if isConnected {
                    logActivity("XPC connected", level: .success)
                } else {
                    logActivity("Sync is running but XPC is not connected", level: .error)
                    throw SyncClientError.notConnected
                }
            }

            // 4. Clear any stale stats before running sync
            lastSyncStats = nil

            // 5. Run the sync
            syncStatusMessage = "Syncing data..."
            syncProgress = 0.5
            logActivity("Running sync via TalkieSync...")
            var syncChangeCount: Int?
            do {
                syncChangeCount = try await runSyncPass()
            } catch let error as SyncClientError where shouldFallbackToLegacySyncNow(error) {
                // Compatibility fallback for older helpers that don't expose runSyncPass reliably.
                log.warning("runSyncPass unavailable, falling back to syncNow: \(error.localizedDescription)")
                logActivity("Sync pass RPC unavailable — using compatibility path", level: .warning)
                try await syncNow(bypassRateLimit: true)
            }

            // 6. Use real stats from observer callback if available, else fall back to counts
            syncStatusMessage = "Verifying..."
            syncProgress = 0.9

            let syncDate = Date()
            let duration = syncStartTime.map { syncDate.timeIntervalSince($0) }

            // Real stats from syncDidCompleteWithStats (arrives before runSyncPass reply)
            let stats = lastSyncStats
            let itemsChanged: Int
            let localAfter: Int
            let remoteAfter: Int

            if let stats {
                itemsChanged = stats.totalChanged
                localAfter = stats.localCount
                remoteAfter = stats.remoteCount
                logActivity("+\(stats.inserted) new, ~\(stats.updated) updated, -\(stats.deleted) deleted, =\(stats.skipped) unchanged")
                logActivity("Local: \(stats.localCount) memos, Remote: \(stats.remoteCount)")
            } else {
                // Fallback: count memos before/after (less accurate but works with old TalkieSync)
                localAfter = (try? await LocalRepository().countMemos()) ?? 0
                remoteAfter = await getRemoteMemoCount()
                itemsChanged = syncChangeCount ?? 0
                logActivity("Local: \(localAfter) memos, Remote: \(remoteAfter >= 0 ? "\(remoteAfter)" : "n/a"), Changed: \(itemsChanged)")
            }

            if remoteAfter >= 0 && localAfter < remoteAfter {
                logActivity(
                    "Local is behind remote by \(remoteAfter - localAfter) memo(s); " +
                    "some records may still be reconciling",
                    level: .warning
                )
            }

            // 7. Only terminate TalkieSync if we launched it and caller doesn't want it kept running
            if !keepRunning && !wasAlreadyRunning {
                syncStatusMessage = "Finishing up..."
                log.info("Sync complete, terminating TalkieSync (we launched it)")
                logActivity("Terminating TalkieSync (we launched it)")
                disconnect()
                ServiceManager.shared.terminateSync()
            }

            // Success
            syncProgress = 1.0
            let durationStr = duration.map { String(format: "%.1fs", $0) } ?? ""
            if let stats, itemsChanged > 0 {
                syncStatusMessage = "+\(stats.inserted) new, ~\(stats.updated) updated, -\(stats.deleted) deleted"
                logActivity("Sync complete: +\(stats.inserted) new, ~\(stats.updated) updated, -\(stats.deleted) deleted \(durationStr)", level: .success)
            } else if itemsChanged > 0 {
                syncStatusMessage = "Synced \(itemsChanged) item\(itemsChanged == 1 ? "" : "s")"
                logActivity("Sync complete: \(itemsChanged) item(s) changed \(durationStr)", level: .success)
            } else {
                syncStatusMessage = "Up to date"
                logActivity("Sync complete: up to date \(durationStr)", level: .success)
            }

            let event = SyncEvent(
                timestamp: syncDate,
                status: .success,
                itemCount: itemsChanged,
                duration: duration,
                errorMessage: nil,
                activity: activityDetailsSince(runActivityStartIndex),
                localCount: localAfter,
                remoteCount: remoteAfter >= 0 ? remoteAfter : nil,
                inserted: stats?.inserted,
                updated: stats?.updated,
                deleted: stats?.deleted,
                skipped: stats?.skipped,
                fetchTimeMs: stats?.fetchTimeMs,
                totalTimeMs: stats?.totalTimeMs,
                syncMode: stats?.syncMode
            )
            CloudKitSyncManager.shared.addSyncEvent(event)

            lastSyncDate = syncDate
            isSyncing = false
            syncStartTime = nil

            if shouldPostSyncCompletedNotification(at: syncDate, error: nil) {
                NotificationCenter.default.post(name: .talkieSyncCompleted, object: nil)
            }

        } catch {
            // Update state on error
            syncError = error.localizedDescription
            syncStatusMessage = "Sync failed"
            logActivity("Sync failed: \(error.localizedDescription)", level: .error)

            // Record failed sync event
            let syncDate = Date()
            let duration = syncStartTime.map { syncDate.timeIntervalSince($0) }
            let event = SyncEvent(
                timestamp: syncDate,
                status: .failed,
                itemCount: 0,
                duration: duration,
                errorMessage: error.localizedDescription,
                activity: activityDetailsSince(runActivityStartIndex)
            )
            CloudKitSyncManager.shared.addSyncEvent(event)

            isSyncing = false
            syncStartTime = nil

            if shouldPostSyncCompletedNotification(at: syncDate, error: error.localizedDescription) {
                NotificationCenter.default.post(name: .talkieSyncCompleted, object: nil)
            }
            throw error
        }
    }

    /// Trigger a sync operation (requires TalkieSync to be running and connected)
    public func syncNow(bypassRateLimit: Bool = false) async throws {
        if !bypassRateLimit, let deferredUntil = nextAutomaticSyncAllowedDate(now: Date()) {
            let remaining = max(0, Int(deferredUntil.timeIntervalSinceNow.rounded()))
            log.info("Deferring auto sync due to daily rate limit (\(remaining)s remaining)")
            throw SyncClientError.rateLimited(until: deferredUntil)
        }

        if let inFlightSyncNowTask {
            return try await inFlightSyncNowTask.value
        }

        let task = Task {
            try await performSyncNowRPC()
        }
        inFlightSyncNowTask = task
        defer { inFlightSyncNowTask = nil }

        try await task.value

        if !bypassRateLimit {
            let now = Date()
            lastAutomaticSyncDate = now
            UserDefaults.standard.set(now, forKey: SyncClientDefaults.lastAutomaticSyncDateDefaultsKey)
        }
    }

    private func nextAutomaticSyncAllowedDate(now: Date) -> Date? {
        guard let lastAutomaticSyncDate else { return nil }

        let nextAllowed = lastAutomaticSyncDate.addingTimeInterval(SyncClientDefaults.automaticSyncMinimumInterval)
        return now < nextAllowed ? nextAllowed : nil
    }

    private func performSyncNowRPC() async throws {
        guard connection != nil else { throw SyncClientError.notConnected }
        let resumed = OSAllocatedUnfairLock(initialState: false)

        return try await withCheckedThrowingContinuation { continuation in
            // Sync can take a while — 120s timeout as a safety net
            DispatchQueue.global().asyncAfter(deadline: .now() + 120.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    log.warning("syncNow timed out after 120s")
                    continuation.resume(throwing: SyncClientError.syncFailed("Sync timed out"))
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                continuation.resume(throwing: SyncClientError.syncFailed("XPC connection failed"))
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(throwing: SyncClientError.notConnected)
                }
                return
            }
            proxy.syncNow { success, error in
                guard resumed.withLock({ old in let was = old; old = true; return !was }) else { return }
                if let error {
                    continuation.resume(throwing: SyncClientError.syncFailed(error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SyncClientError.syncFailed("Unknown error"))
                }
            }
        }
    }

    /// Cancel any in-progress sync
    public func cancelSync() async {
        guard connection != nil else { return }
        let resumed = OSAllocatedUnfairLock(initialState: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Timeout — don't hang forever if XPC is dead
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    log.debug("cancelSync timed out")
                    continuation.resume()
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                continuation.resume()
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume()
                }
                return
            }
            proxy.cancelSync {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume()
                }
            }
        }
    }

    /// Fetch audio for a specific memo from iCloud (targeted, not a full sync).
    /// Handles launching TalkieSync and connecting if not already connected.
    public func fetchAudioForMemo(memoID: UUID) async throws -> Bool {
        let wasAlreadyRunning = ServiceManager.shared.sync.isRunning

        // Ensure TalkieSync is running and connected
        if !isConnected {
            try await ensureSyncConnection()
        }

        defer {
            // Terminate TalkieSync if we launched it
            if !wasAlreadyRunning {
                disconnect()
                ServiceManager.shared.terminateSync()
            }
        }

        let resumed = OSAllocatedUnfairLock(initialState: false)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 30.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(throwing: SyncClientError.syncFailed("Fetch audio timed out"))
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                continuation.resume(throwing: SyncClientError.syncFailed("XPC connection failed"))
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(throwing: SyncClientError.notConnected)
                }
                return
            }
            proxy.fetchAudioForMemo(memoID.uuidString) { success, error in
                guard resumed.withLock({ old in let was = old; old = true; return !was }) else { return }
                if let error {
                    continuation.resume(throwing: SyncClientError.syncFailed(error))
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// Launch TalkieSync and establish XPC connection if needed.
    private func ensureSyncConnection() async throws {
        ServiceManager.shared.refreshStatus()
        if !ServiceManager.shared.sync.isRunning {
            log.info("Launching TalkieSync for audio fetch...")
            ServiceManager.shared.launchSync()

            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(500))
                ServiceManager.shared.refreshStatus()
                if ServiceManager.shared.sync.isRunning { break }
            }

            guard ServiceManager.shared.sync.isRunning else {
                throw SyncClientError.syncFailed("Failed to launch TalkieSync")
            }
        }

        if !isConnected {
            connect()
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(500))
                if isConnected { break }
            }
        }

        guard isConnected else {
            throw SyncClientError.notConnected
        }
    }

    /// Force an immediate sync pass.
    public func runSyncPass() async throws -> Int {
        guard connection != nil else { throw SyncClientError.notConnected }
        let resumed = OSAllocatedUnfairLock(initialState: false)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 120.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    log.warning("runSyncPass timed out after 120s")
                    continuation.resume(throwing: SyncClientError.syncFailed("Sync pass timed out"))
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                continuation.resume(throwing: SyncClientError.syncFailed("XPC connection failed"))
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(throwing: SyncClientError.notConnected)
                }
                return
            }
            proxy.runSyncPass { count, error in
                guard resumed.withLock({ old in let was = old; old = true; return !was }) else { return }
                if let error {
                    continuation.resume(throwing: SyncClientError.syncFailed(error))
                } else {
                    continuation.resume(returning: count)
                }
            }
        }
    }

    // MARK: - Status

    /// Refresh sync status from service
    public func refreshStatus() async {
        guard connection != nil else { return }
        let resumed = OSAllocatedUnfairLock(initialState: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    log.debug("refreshStatus timed out")
                    continuation.resume()
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                continuation.resume()
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume()
                }
                return
            }
            proxy.getStatus { [weak self] data in
                Task { @MainActor in
                    if let data = data,
                       let status = try? JSONDecoder().decode(SyncStatusInfo.self, from: data) {
                        self?.isSyncing = status.status == "syncing"
                        self?.lastSyncDate = status.lastSyncDate
                        self?.syncError = status.errorMessage
                        self?.iCloudAvailable = status.iCloudAvailable
                    }
                }
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume()
                }
            }
        }
    }

    /// Check iCloud availability
    public func checkiCloudAvailability() async -> (available: Bool, error: String?) {
        guard connection != nil else { return (false, "Not connected to sync service") }
        let resumed = OSAllocatedUnfairLock(initialState: false)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: (false, "Timed out"))
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                continuation.resume(returning: (false, "XPC connection failed"))
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: (false, "Not connected"))
                }
                return
            }
            proxy.checkiCloudAvailability { available, error in
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: (available, error))
                }
            }
        }
    }

    /// Get remote memo count from TalkieSync diagnostics.
    /// Returns -1 when unavailable (distinguishes from "0 records").
    public func getRemoteMemoCount() async -> Int {
        guard remoteMemoDiagnosticsAvailable else { return -1 }
        guard connection != nil else { return -1 }
        let resumed = OSAllocatedUnfairLock(initialState: false)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: -1)
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                Task { @MainActor in
                    SyncClient.shared.disableRemoteMemoDiagnostics(reason: "getRemoteMemoCount RPC failed")
                }
                continuation.resume(returning: -1)
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: -1)
                }
                return
            }
            proxy.getRemoteMemoCount { count in
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: count)
                }
            }
        }
    }

    /// Get latest remote memo trace from TalkieSync diagnostics.
    /// Returns nil when unavailable.
    public func getLatestRemoteMemoTrace() async -> String? {
        guard remoteMemoDiagnosticsAvailable else { return nil }
        guard connection != nil else { return nil }
        let resumed = OSAllocatedUnfairLock(initialState: false)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: nil)
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                Task { @MainActor in
                    SyncClient.shared.disableRemoteMemoDiagnostics(reason: "getLatestRemoteMemoTrace RPC failed")
                }
                continuation.resume(returning: nil)
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: nil)
                }
                return
            }
            proxy.getLatestRemoteMemoTrace { trace in
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: trace)
                }
            }
        }
    }

    private func disableRemoteMemoDiagnostics(reason: String) {
        guard remoteMemoDiagnosticsAvailable else { return }
        remoteMemoDiagnosticsAvailable = false
        log.warning("Disabling remote memo diagnostics for this session: \(reason)")
        logActivity("Remote diagnostics unavailable on this TalkieSync build", level: .warning)
    }

    private func shouldFallbackToLegacySyncNow(_ error: SyncClientError) -> Bool {
        guard case let .syncFailed(message) = error else { return false }
        return message.localizedStandardContains("XPC connection failed")
    }

    /// Ping the service
    public func ping() async -> Bool {
        guard connection != nil else { return false }
        let resumed = OSAllocatedUnfairLock(initialState: false)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: false)
                }
            }
            guard let proxy = makeProxy(resumed: resumed, onError: {
                continuation.resume(returning: false)
            }) else {
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: false)
                }
                return
            }
            proxy.ping { pong in
                if resumed.withLock({ old in let was = old; old = true; return !was }) {
                    continuation.resume(returning: pong)
                }
            }
        }
    }

    // MARK: - TalkieSyncObserverProtocol

    nonisolated public func syncDidStart() {
        Task { @MainActor in
            self.isSyncing = true
            self.syncProgress = 0
            self.syncStatusMessage = "Starting sync..."
            // Note: syncStartTime is only set by runSyncOnce() which manages its own lifecycle.
            // Setting it here would cause syncDidComplete() to think runSyncOnce is active
            // and skip resetting isSyncing.
            log.debug("Sync started")
        }
    }

    nonisolated public func syncProgressDidChange(_ progress: Double, _ message: String) {
        Task { @MainActor in
            self.syncProgress = progress
            self.syncStatusMessage = message
            self.logProgressActivityIfNeeded(message: message)
        }
    }

    nonisolated public func syncDidCompleteWithStats(_ statsJSON: Data, error: String?) {
        Task { @MainActor in
            if let stats = try? JSONDecoder().decode(SyncCompletionStats.self, from: statsJSON) {
                self.lastSyncStats = stats
                log.info("Received sync stats: +\(stats.inserted) new, ~\(stats.updated) updated, -\(stats.deleted) deleted")
            } else {
                log.warning("Failed to decode SyncCompletionStats from observer callback")
            }
            // syncDidComplete will be called separately for state management
        }
    }

    nonisolated public func syncDidComplete(_ error: String?) {
        Task { @MainActor in
            // Only update state from observer callback if runSyncOnce isn't managing the lifecycle
            // (runSyncOnce records its own events with before/after counts)
            let wasManaged = self.syncStartTime != nil && self.isSyncing

            self.syncError = error

            if let dur = self.syncStartTime.map({ Date().timeIntervalSince($0) }) {
                log.debug("Sync completed in \(String(format: "%.1f", dur))s (error: \(error ?? "none"))")
            } else {
                log.debug("Sync completed (error: \(error ?? "none"))")
            }

            // If runSyncOnce is managing the sync, let it handle state + event recording
            guard !wasManaged else { return }

            self.isSyncing = false
            self.syncProgress = 1.0

            let syncDate = Date()
            if error == nil {
                self.lastSyncDate = syncDate
                self.syncStatusMessage = "Sync completed"
            } else {
                self.syncStatusMessage = "Sync failed"
            }

            // Avoid completion notification storms from noisy callback loops.
            if shouldPostSyncCompletedNotification(at: syncDate, error: error) {
                NotificationCenter.default.post(name: .talkieSyncCompleted, object: nil)
            }
        }
    }

    private func shouldPostSyncCompletedNotification(at date: Date, error: String?) -> Bool {
        if error != nil {
            return true
        }

        guard date.timeIntervalSince(lastSyncCompletedNotificationAt) >= syncCompletedNotificationMinIntervalSeconds else {
            return false
        }

        lastSyncCompletedNotificationAt = date
        return true
    }

    private func logProgressActivityIfNeeded(message: String) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard normalized != lastProgressMessageLogged else { return }

        let now = Date()
        guard now.timeIntervalSince(lastProgressMessageLoggedAt) >= 0.75 else { return }

        lastProgressMessageLogged = normalized
        lastProgressMessageLoggedAt = now
        logActivity(normalized)
    }

    nonisolated public func newDataAvailable() {
        Task { @MainActor in
            log.info("New data available from sync - refreshing UI")
            // Post notification for views to refresh
            NotificationCenter.default.post(name: .syncDataAvailable, object: nil)
        }
    }

    nonisolated public func iCloudAvailabilityDidChange(_ available: Bool) {
        Task { @MainActor in
            self.iCloudAvailable = available
            log.info("iCloud availability changed: \(available)")
        }
    }
}

// MARK: - Errors

public enum SyncClientError: Error, LocalizedError {
    case notConnected
    case syncFailed(String)
    case rateLimited(until: Date)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to sync service"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        case .rateLimited(let until):
            return "Sync rate-limited until \(until.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

// MARK: - Activity Log Entry

/// A timestamped log entry visible in the Sync panel UI.
public struct SyncActivityEntry: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let level: Level

    public enum Level {
        case info
        case success
        case warning
        case error
    }

    public var icon: String {
        switch level {
        case .info: return "circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

extension SyncClient {
    /// Append a log entry visible in the Sync panel.
    func logActivity(_ message: String, level: SyncActivityEntry.Level = .info) {
        let entry = SyncActivityEntry(timestamp: Date(), message: message, level: level)
        activityLog.append(entry)
        if activityLog.count > maxActivityEntries {
            activityLog.removeFirst(activityLog.count - maxActivityEntries)
        }
    }

    /// Capture activity entries for a single runSyncOnce lifecycle.
    func activityDetailsSince(_ startIndex: Int) -> [SyncActivityDetail] {
        guard !activityLog.isEmpty else { return [] }
        let safeStart = max(0, min(startIndex, activityLog.count))
        guard safeStart < activityLog.count else { return [] }

        return activityLog[safeStart...].map { entry in
            SyncActivityDetail(
                timestamp: entry.timestamp,
                level: persistedLevel(for: entry.level),
                message: entry.message
            )
        }
    }

    private func persistedLevel(for level: SyncActivityEntry.Level) -> SyncActivityDetail.Level {
        switch level {
        case .info: return .info
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when new data is available after sync
    static let syncDataAvailable = Notification.Name("syncDataAvailable")
}
