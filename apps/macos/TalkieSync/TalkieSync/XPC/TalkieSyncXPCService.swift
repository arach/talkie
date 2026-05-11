//
//  TalkieSyncXPCService.swift
//  TalkieSync
//
//  XPC service that exposes sync functionality to Talkie main app.
//  Handles CloudKit sync, bridge sync, and provider management.
//

import Foundation
import AppKit
import TalkieKit

private let log = Log(.xpc)

@MainActor
final class TalkieSyncXPCService: NSObject, TalkieSyncXPCProtocol, ObservableObject {
    static let shared = TalkieSyncXPCService()

    private var listener: NSXPCListener?
    private var observersByPID: [pid_t: NSXPCConnection] = [:]
    private var schedulerStarted = false

    // Sync state
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncError: String?

    private static let lastSyncDateKey = "talkieSync.lastSyncDate"
    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private override init() {
        super.init()
        // Restore lastSyncDate from UserDefaults so it survives process restarts
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncDateKey) as? Date
        if let restored = lastSyncDate {
            log.info("Restored lastSyncDate from UserDefaults: \(restored)")
        }
    }

    // MARK: - Service Lifecycle

    /// Start the XPC service. Starts listener + posts readiness signal.
    /// Prefer `startListenerOnly()` + `postReadinessSignal()` for controlled startup.
    func startService() {
        startListenerOnly()
        postReadinessSignal()
    }

    /// Start the XPC listener only (no readiness signal).
    /// Call `postReadinessSignal()` separately after startup wiring is complete.
    func startListenerOnly() {
        listener = NSXPCListener(machServiceName: kTalkieSyncXPCServiceName)
        listener?.delegate = self
        listener?.resume()
        log.info("TalkieSync XPC listener started: \(kTalkieSyncXPCServiceName)")
    }

    /// Post the readiness signal so Talkie knows we're fully ready to sync.
    /// Should only be called after the service can accept sync requests.
    func postReadinessSignal() {
        let readyName = TalkieHelper.sync.xpcReadyNotificationName(for: TalkieEnvironment.current)
        DistributedNotificationCenter.default().postNotificationName(
            readyName,
            object: nil,
            deliverImmediately: true
        )
        log.info("Posted readiness signal: \(readyName.rawValue)")
    }

    func stopService() {
        listener?.invalidate()
        listener = nil
        observersByPID.removeAll()
        log.info("TalkieSync XPC service stopped")
    }

    // MARK: - Observer Management

    func addObserverConnection(_ connection: NSXPCConnection) {
        let pid = connection.processIdentifier
        if let existing = observersByPID[pid], existing !== connection {
            log.warning("Replacing stale observer connection for pid \(pid)")
        }
        observersByPID[pid] = connection
        log.info("Talkie connected (pid: \(pid), total observers: \(observersByPID.count))")
    }

    func removeObserverConnection(_ connection: NSXPCConnection) {
        let pid = connection.processIdentifier
        guard let existing = observersByPID[pid] else { return }
        if existing === connection {
            observersByPID.removeValue(forKey: pid)
        }
        log.info("Talkie disconnected (pid: \(pid), remaining observers: \(observersByPID.count))")
    }

    // MARK: - Notifications to Observers

    func notifyNewDataAvailable() {
        for connection in observerConnections {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ error in
                log.warning("Error notifying observer: \(error.localizedDescription)")
            }) as? TalkieSyncObserverProtocol else { continue }

            observer.newDataAvailable()
        }
        log.debug("Notified \(observerConnections.count) observer(s) of new data")
    }

    private func notifySyncStarted() {
        for connection in observerConnections {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? TalkieSyncObserverProtocol else { continue }
            observer.syncDidStart()
        }
    }

    private func notifySyncProgress(_ progress: Double, message: String) {
        for connection in observerConnections {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? TalkieSyncObserverProtocol else { continue }
            observer.syncProgressDidChange(progress, message)
        }
    }

    private func notifySyncCompleted(stats: SyncCompletionStats?, error: String?) {
        log.info("Notifying \(observerConnections.count) observer(s) of sync completion (error: \(error ?? "none"))")

        // Encode stats once for all observers
        let statsJSON: Data? = stats.flatMap { try? Self.jsonEncoder.encode($0) }

        for connection in observerConnections {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ err in
                log.warning("Error getting observer proxy: \(err.localizedDescription)")
            }) as? TalkieSyncObserverProtocol else {
                log.warning("Failed to get observer proxy")
                continue
            }

            // Send stats via the new optional method (if observer implements it)
            if let statsJSON {
                observer.syncDidCompleteWithStats?(statsJSON, error: error)
            }

            // Always call the legacy method for backward compat
            observer.syncDidComplete(error)
            log.debug("Called syncDidComplete on observer")
        }
    }

    private func notifyiCloudAvailabilityChanged(_ available: Bool) {
        for connection in observerConnections {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? TalkieSyncObserverProtocol else { continue }
            observer.iCloudAvailabilityDidChange(available)
        }
    }

    private var observerConnections: [NSXPCConnection] {
        Array(observersByPID.values)
    }

    private func startSchedulerIfNeeded() {
        guard !schedulerStarted else { return }
        SyncScheduler.shared.start()
        schedulerStarted = true
    }

    /// Persist lastSyncDate to UserDefaults so it survives process restarts.
    private func persistLastSyncDate(_ date: Date) {
        lastSyncDate = date
        UserDefaults.standard.set(date, forKey: Self.lastSyncDateKey)
    }

    /// Build incremental sync options: if we have a previous sync date, fetch only records
    /// modified since then (with a 60s safety margin for clock skew / in-flight writes).
    /// First sync is always full (no lastSyncDate yet).
    func incrementalOptions() -> CloudKitDirectSyncEngine.SyncOptions {
        guard let lastSync = lastSyncDate else {
            return .all
        }
        var options = CloudKitDirectSyncEngine.SyncOptions.all
        options.since = lastSync.addingTimeInterval(-60)
        return options
    }

    private func ensureSyncEngineReady() -> Bool {
        guard CloudKitDirectSyncEngine.shared.ensureReady() else {
            log.error("Direct CloudKit sync engine is not ready")
            return false
        }
        startSchedulerIfNeeded()
        return true
    }

    // MARK: - TalkieSyncXPCProtocol Implementation

    nonisolated func syncNow(reply: @escaping (Bool, String?) -> Void) {
        Task { @MainActor in
            let options = self.incrementalOptions()
            self.performSync(options: options) { result, error in
                reply(result != nil, error)
            }
        }
    }

    nonisolated func syncNowWithOptions(_ limit: Int, since: Date?, reply: @escaping (Bool, String?) -> Void) {
        var options = CloudKitDirectSyncEngine.SyncOptions.all
        if limit > 0 { options.limit = limit }
        options.since = since
        performSync(options: options) { result, error in
            reply(result != nil, error)
        }
    }

    /// Internal sync that returns full stats dictionary. Used by bridge handler and XPC methods.
    nonisolated func performSync(
        options: CloudKitDirectSyncEngine.SyncOptions,
        onProgress: ((_ event: String, _ data: [String: Any]) -> Void)? = nil,
        reply: @escaping (_ stats: [String: Any]?, _ error: String?) -> Void
    ) {
        Task { @MainActor in
            guard !self.isSyncing else {
                reply(nil, "Sync already in progress")
                return
            }

            guard ensureSyncEngineReady() else {
                reply(nil, "Sync engine not ready")
                return
            }

            self.isSyncing = true
            self.notifySyncStarted()

            let constraintDesc = describeConstraints(
                limit: options.limit, since: options.since
            )

            do {
                let syncMode = options.since != nil ? "incremental" : "full"
                log.info("┌─ Sync starting (\(syncMode) CloudKit pull\(constraintDesc)) ─────────────")
                let stats = try await CloudKitDirectSyncEngine.shared.syncNow(options: options) { [weak self] progress, message in
                    Task { @MainActor in
                        self?.notifySyncProgress(progress, message: message)
                    }
                    onProgress?("syncProgress", [
                        "progress": progress,
                        "message": message,
                    ])
                }

                let completionStats = SyncCompletionStats(
                    inserted: stats.inserted,
                    updated: stats.updated,
                    deleted: stats.deleted,
                    skipped: stats.skipped,
                    remoteCount: stats.remoteCount,
                    localCount: stats.localCount,
                    fetchTimeMs: Int(stats.fetchTimeMs),
                    totalTimeMs: Int(stats.totalTimeMs),
                    schema: stats.schema,
                    syncMode: syncMode
                )

                self.isSyncing = false
                self.persistLastSyncDate(Date())
                self.syncError = nil
                self.notifySyncCompleted(stats: completionStats, error: nil)

                if stats.inserted > 0 || stats.updated > 0 || stats.deleted > 0 {
                    self.notifyNewDataAvailable()
                }

                log.info(
                    "│ CloudKit → GRDB (\(stats.schema)): +\(stats.inserted) new, " +
                    "~\(stats.updated) updated, -\(stats.deleted) deleted, =\(stats.skipped) unchanged"
                )
                log.info("│ Remote memos: \(stats.remoteCount), local memos: \(stats.localCount)")
                log.info("│ Latest remote memo: \(stats.latestMemoTrace)")
                log.info(
                    "└─ Sync completed ✓ [fetch \(String(format: "%.0f", stats.fetchTimeMs))ms, " +
                    "total \(String(format: "%.0f", stats.totalTimeMs))ms]"
                )

                reply([
                    "success": true,
                    "inserted": stats.inserted,
                    "updated": stats.updated,
                    "deleted": stats.deleted,
                    "skipped": stats.skipped,
                    "remoteCount": stats.remoteCount,
                    "localCount": stats.localCount,
                    "fetchTimeMs": Int(stats.fetchTimeMs),
                    "totalTimeMs": Int(stats.totalTimeMs),
                    "schema": stats.schema,
                    "syncMode": syncMode,
                ], nil)
            } catch {
                self.isSyncing = false
                self.syncError = error.localizedDescription
                self.notifySyncCompleted(stats: nil, error: error.localizedDescription)
                log.error("└─ Direct sync FAILED: \(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
        }
    }

    private func describeConstraints(limit: Int?, since: Date?) -> String {
        var parts: [String] = []
        if let limit { parts.append("limit=\(limit)") }
        if let since {
            let fmt = ISO8601DateFormatter()
            parts.append("since=\(fmt.string(from: since))")
        }
        return parts.isEmpty ? "" : ", \(parts.joined(separator: ", "))"
    }

    nonisolated func cancelSync(reply: @escaping () -> Void) {
        Task { @MainActor in
            // For now, sync operations are atomic and can't be cancelled
            // Future: Add cancellation support for long-running syncs
            log.info("Cancel sync requested (no-op)")
            reply()
        }
    }

    nonisolated func getStatus(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            var errorMessage = self.syncError
            let result = await withTimeoutResult(seconds: 3.0) {
                await CloudKitDirectSyncEngine.shared.checkiCloudAvailability()
            }

            let iCloudAvailable: Bool
            switch result {
            case .success(let (available, availabilityError)):
                iCloudAvailable = available
                if errorMessage == nil {
                    errorMessage = availabilityError
                }
            case .timedOut:
                iCloudAvailable = false
                log.warning("iCloud availability check timed out")
                errorMessage = errorMessage ?? "iCloud check timed out"
            }

            let status = SyncStatusInfo(
                status: self.isSyncing ? "syncing" : (self.syncError != nil ? "failed" : "idle"),
                lastSyncDate: self.lastSyncDate,
                pendingChanges: 0,  // TODO: Track pending changes
                iCloudAvailable: iCloudAvailable,
                errorMessage: errorMessage,
                activeProvider: "icloud-direct"
            )

            let data = try? Self.jsonEncoder.encode(status)
            reply(data)
        }
    }

    /// Execute an async operation with a timeout
    private func withTimeoutResult<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> TimeoutResult<T> {
        await withTaskGroup(of: TimeoutResult<T>.self) { group in
            group.addTask {
                let result = await operation()
                return .success(result)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return .timedOut
            }
            // Return first to complete
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }

    nonisolated func getLastSyncDate(reply: @escaping (Date?) -> Void) {
        Task { @MainActor in
            reply(self.lastSyncDate)
        }
    }

    nonisolated func checkiCloudAvailability(reply: @escaping (Bool, String?) -> Void) {
        Task { @MainActor in
            let (available, error) = await CloudKitDirectSyncEngine.shared.checkiCloudAvailability()
            notifyiCloudAvailabilityChanged(available)
            reply(available, error)
        }
    }

    nonisolated func enableProvider(_ providerId: String, config: Data?, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            // For now, only iCloud is supported
            if providerId == "icloud" {
                log.info("iCloud provider enabled")
                reply(nil)
            } else {
                reply("Unknown provider: \(providerId)")
            }
        }
    }

    nonisolated func disableProvider(_ providerId: String, reply: @escaping () -> Void) {
        Task { @MainActor in
            log.info("Provider disabled: \(providerId)")
            reply()
        }
    }

    nonisolated func listProviders(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            let (iCloudAvailable, errorMessage) = await CloudKitDirectSyncEngine.shared.checkiCloudAvailability()

            let providers = [
                SyncProviderInfo(
                    id: "icloud",
                    displayName: "iCloud (direct)",
                    isEnabled: true,
                    isConnected: iCloudAvailable,
                    lastSyncDate: self.lastSyncDate,
                    errorMessage: errorMessage
                )
            ]

            let data = try? Self.jsonEncoder.encode(providers)
            reply(data)
        }
    }

    nonisolated func getRemoteMemoCount(reply: @escaping (Int) -> Void) {
        Task { @MainActor in
            let count = CloudKitDirectSyncEngine.shared.lastRemoteMemoCount
            reply(count)
        }
    }

    nonisolated func getLatestRemoteMemoTrace(reply: @escaping (String) -> Void) {
        Task { @MainActor in
            let trace = CloudKitDirectSyncEngine.shared.lastLatestMemoTrace
            reply(trace)
        }
    }

    nonisolated func runSyncPass(reply: @escaping (Int, String?) -> Void) {
        Task { @MainActor in
            guard !self.isSyncing else {
                reply(0, "Sync already in progress")
                return
            }
            guard ensureSyncEngineReady() else {
                reply(0, "Sync engine not ready")
                return
            }

            let options = self.incrementalOptions()
            let syncMode = options.since != nil ? "incremental" : "full"

            self.isSyncing = true
            self.notifySyncStarted()

            do {
                let stats = try await CloudKitDirectSyncEngine.shared.syncNow(options: options) { [weak self] progress, message in
                    Task { @MainActor in
                        self?.notifySyncProgress(progress, message: message)
                    }
                }

                let completionStats = SyncCompletionStats(
                    inserted: stats.inserted,
                    updated: stats.updated,
                    deleted: stats.deleted,
                    skipped: stats.skipped,
                    remoteCount: stats.remoteCount,
                    localCount: stats.localCount,
                    fetchTimeMs: Int(stats.fetchTimeMs),
                    totalTimeMs: Int(stats.totalTimeMs),
                    schema: stats.schema,
                    syncMode: syncMode
                )

                self.isSyncing = false
                self.persistLastSyncDate(Date())
                self.syncError = nil
                self.notifySyncCompleted(stats: completionStats, error: nil)
                if stats.inserted > 0 || stats.updated > 0 || stats.deleted > 0 {
                    self.notifyNewDataAvailable()
                }
                reply(stats.inserted + stats.updated + stats.deleted, nil)
            } catch {
                self.isSyncing = false
                self.syncError = error.localizedDescription
                self.notifySyncCompleted(stats: nil, error: error.localizedDescription)
                reply(0, error.localizedDescription)
            }
        }
    }

    nonisolated func fetchAudioForMemo(_ memoID: String, reply: @escaping (Bool, String?) -> Void) {
        Task { @MainActor in
            guard let uuid = UUID(uuidString: memoID) else {
                reply(false, "Invalid memo ID")
                return
            }
            guard ensureSyncEngineReady() else {
                reply(false, "Sync engine not ready")
                return
            }
            let (success, error) = await CloudKitDirectSyncEngine.shared.fetchAudioForMemo(memoID: uuid)
            if success {
                self.notifyNewDataAvailable()
            }
            reply(success, error)
        }
    }

    nonisolated func ping(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            reply(true)
        }
    }

    nonisolated func shutdown(reply: @escaping () -> Void) {
        Task { @MainActor in
            log.info("Shutdown requested")
            reply()

            // Give time for reply, then exit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - NSXPCListenerDelegate

extension TalkieSyncXPCService: NSXPCListenerDelegate {
    nonisolated func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure exported interface (what we expose)
        newConnection.exportedInterface = NSXPCInterface(with: TalkieSyncXPCProtocol.self)
        newConnection.exportedObject = self

        // Configure remote interface (for callbacks)
        newConnection.remoteObjectInterface = NSXPCInterface(with: TalkieSyncObserverProtocol.self)

        // Handle connection lifecycle
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            Task { @MainActor in
                guard let self, let conn = newConnection else { return }
                self.removeObserverConnection(conn)
            }
        }

        newConnection.interruptionHandler = {
            log.warning("XPC connection interrupted")
        }

        // Add to observers
        Task { @MainActor [weak self, weak newConnection] in
            guard let self, let conn = newConnection else { return }
            self.addObserverConnection(conn)
        }

        newConnection.resume()
        log.info("Accepted new XPC connection")
        return true
    }
}

// MARK: - Timeout Helper

private enum TimeoutResult<T> {
    case success(T)
    case timedOut
}
