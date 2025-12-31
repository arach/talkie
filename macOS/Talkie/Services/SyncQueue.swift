//
//  SyncQueue.swift
//  Talkie
//
//  Fire-and-forget queue for CloudKit sync operations.
//  Decouples "I made a change" from "sync it to cloud".
//  Includes retry with exponential backoff.
//

import Foundation
import TalkieKit

private let log = Log(.sync)

/// Priority levels for sync operations
enum SyncPriority: Int, Comparable, CustomStringConvertible {
    case immediate = 0   // Workflow results - user waiting on iOS
    case high = 1        // User-initiated actions
    case normal = 2      // Regular edits
    case background = 3  // Bulk operations, cleanup

    static func < (lhs: SyncPriority, rhs: SyncPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .immediate: return "immediate"
        case .high: return "high"
        case .normal: return "normal"
        case .background: return "background"
        }
    }
}

/// What type of change needs syncing
enum SyncItemType: Sendable, CustomStringConvertible {
    case memo(UUID)
    case workflowRun(UUID)
    case transcriptVersion(UUID)
    case deletion(UUID)

    var id: UUID {
        switch self {
        case .memo(let id), .workflowRun(let id),
             .transcriptVersion(let id), .deletion(let id):
            return id
        }
    }

    var description: String {
        switch self {
        case .memo: return "memo"
        case .workflowRun: return "workflow"
        case .transcriptVersion: return "transcript"
        case .deletion: return "deletion"
        }
    }
}

/// Wrapper that tracks retry state
private struct PendingItem: Sendable {
    let item: SyncItemType
    let priority: SyncPriority
    var retryCount: Int = 0
    var lastError: String?
    let enqueuedAt: Date = Date()
    var nextRetryAt: Date?

    var id: UUID { item.id }
    var shortId: String { String(id.uuidString.prefix(8)) }

    /// Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s (max)
    var backoffDelay: Duration {
        let seconds = min(pow(2.0, Double(retryCount)), 32.0)
        return .seconds(seconds)
    }

    var isReadyForRetry: Bool {
        guard let nextRetry = nextRetryAt else { return true }
        return Date() >= nextRetry
    }
}

/// Fire-and-forget sync queue with retry
/// Usage: SyncQueue.shared.enqueue(.workflowRun(id), priority: .immediate)
actor SyncQueue {
    static let shared = SyncQueue()

    // MARK: - Configuration

    private let maxRetries = 5
    private let batchDelay: Duration = .milliseconds(50)
    private let immediateDelay: Duration = .zero
    private let retryCheckInterval: Duration = .seconds(1)

    // MARK: - State

    private var pending: [UUID: PendingItem] = [:]
    private var failed: [UUID: PendingItem] = [:]  // Exceeded max retries
    private var isProcessing = false
    private var processTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    // MARK: - Stats (for monitoring)

    private(set) var totalEnqueued: Int = 0
    private(set) var totalSucceeded: Int = 0
    private(set) var totalFailed: Int = 0
    private(set) var totalRetries: Int = 0

    // MARK: - Public API

    /// Enqueue a sync item - returns immediately (fire and forget)
    nonisolated func enqueue(_ item: SyncItemType, priority: SyncPriority = .normal) {
        Task {
            await _enqueue(item, priority: priority)
        }
    }

    /// Enqueue multiple items at once
    nonisolated func enqueue(_ items: [SyncItemType], priority: SyncPriority = .normal) {
        Task {
            for item in items {
                await _enqueue(item, priority: priority)
            }
        }
    }

    /// Wait for all pending syncs to complete (for testing/shutdown)
    func flush() async {
        // Wait for current processing
        await processTask?.value

        // Process any remaining items
        while !pending.isEmpty {
            await processQueues()
        }
    }

    /// Current queue depth
    var pendingCount: Int { pending.count }

    /// Items that exceeded max retries
    var failedCount: Int { failed.count }

    /// Get failed items for inspection/manual retry
    func getFailedItems() -> [(id: UUID, type: String, error: String?, retries: Int)] {
        failed.values.map { item in
            (item.id, item.item.description, item.lastError, item.retryCount)
        }
    }

    /// Retry all failed items
    func retryFailed() {
        for (id, item) in failed {
            var retryItem = item
            retryItem.retryCount = 0
            retryItem.nextRetryAt = nil
            pending[id] = retryItem
        }
        failed.removeAll()
        scheduleProcessing(priority: .normal)
    }

    /// Clear failed items
    func clearFailed() {
        failed.removeAll()
    }

    // MARK: - Internal

    private func _enqueue(_ item: SyncItemType, priority: SyncPriority) {
        // Dedupe - don't add if already queued
        if pending[item.id] != nil {
            log.debug("[\(item.id.uuidString.prefix(8))] Already queued, skipping")
            return
        }

        // Remove from failed if re-enqueueing
        failed.removeValue(forKey: item.id)

        let pendingItem = PendingItem(item: item, priority: priority)
        pending[item.id] = pendingItem
        totalEnqueued += 1

        log.debug("[\(pendingItem.shortId)] Enqueued \(item.description) (\(priority)) - depth: \(pendingCount)")

        scheduleProcessing(priority: priority)
    }

    private func scheduleProcessing(priority: SyncPriority) {
        guard !isProcessing else { return }

        let delay = priority == .immediate ? immediateDelay : batchDelay

        processTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            await processQueues()
        }
    }

    private func processQueues() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer {
            isProcessing = false
            scheduleRetryCheck()
        }

        // Sort by priority, then by enqueue time
        let sortedItems = pending.values
            .filter { $0.isReadyForRetry }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority < rhs.priority
                }
                return lhs.enqueuedAt < rhs.enqueuedAt
            }

        for item in sortedItems {
            await processItem(item)
        }
    }

    private func processItem(_ item: PendingItem) async {
        let start = Date()
        var mutableItem = item

        do {
            try await performSync(item.item)

            // Success - remove from pending
            pending.removeValue(forKey: item.id)
            totalSucceeded += 1

            let duration = Date().timeIntervalSince(start)
            if item.priority == .immediate || item.retryCount > 0 {
                let retryInfo = item.retryCount > 0 ? " (retry #\(item.retryCount))" : ""
                log.info("[\(item.shortId)] Synced in \(String(format: "%.0fms", duration * 1000))\(retryInfo)")
            } else {
                log.debug("[\(item.shortId)] Synced")
            }

        } catch {
            mutableItem.retryCount += 1
            mutableItem.lastError = error.localizedDescription
            totalRetries += 1

            if mutableItem.retryCount >= maxRetries {
                // Move to failed
                pending.removeValue(forKey: item.id)
                failed[item.id] = mutableItem
                totalFailed += 1
                log.error("[\(item.shortId)] Failed permanently after \(maxRetries) retries: \(error.localizedDescription)")
            } else {
                // Schedule retry with backoff
                mutableItem.nextRetryAt = Date().addingTimeInterval(mutableItem.backoffDelay.seconds)
                pending[item.id] = mutableItem
                log.warning("[\(item.shortId)] Retry #\(mutableItem.retryCount) in \(mutableItem.backoffDelay.seconds)s: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleRetryCheck() {
        // Check if there are items waiting for retry
        let hasRetryItems = pending.values.contains { $0.nextRetryAt != nil }
        guard hasRetryItems else { return }

        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(for: retryCheckInterval)
            guard !Task.isCancelled else { return }
            await processQueues()
        }
    }

    // MARK: - Sync Operations

    private func performSync(_ item: SyncItemType) async throws {
        switch item {
        case .memo:
            try await syncMemo()
        case .workflowRun:
            try await syncWorkflowRun()
        case .transcriptVersion:
            try await syncTranscriptVersion()
        case .deletion:
            try await syncDeletion()
        }
    }

    private func syncMemo() async throws {
        try await triggerCloudKitExport()
    }

    private func syncWorkflowRun() async throws {
        try await triggerCloudKitExport()
    }

    private func syncTranscriptVersion() async throws {
        try await triggerCloudKitExport()
    }

    private func syncDeletion() async throws {
        try await triggerCloudKitExport()
    }

    /// Trigger CloudKit to export pending changes
    private func triggerCloudKitExport() async throws {
        // NSPersistentCloudKitContainer automatically exports on save,
        // but we can nudge it by refreshing the context
        await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            context.refreshAllObjects()
        }

        // Small delay to allow CloudKit to process
        try await Task.sleep(for: .milliseconds(100))
    }
}

// MARK: - Duration Extension

private extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

// MARK: - Convenience Extensions

extension SyncQueue {
    /// Convenience for workflow completion
    nonisolated func workflowCompleted(runId: UUID, memoId: UUID) {
        enqueue(.workflowRun(runId), priority: .immediate)
        enqueue(.memo(memoId), priority: .immediate)
    }

    /// Convenience for memo edits
    nonisolated func memoUpdated(_ id: UUID) {
        enqueue(.memo(id), priority: .normal)
    }

    /// Convenience for transcript changes
    nonisolated func transcriptUpdated(memoId: UUID, versionId: UUID) {
        enqueue(.transcriptVersion(versionId), priority: .high)
        enqueue(.memo(memoId), priority: .high)
    }
}

// MARK: - Debug/Monitoring

extension SyncQueue {
    /// Get current stats for debugging
    func getStats() -> (pending: Int, failed: Int, succeeded: Int, retries: Int) {
        (pendingCount, failedCount, totalSucceeded, totalRetries)
    }

    /// Log current state
    func logState() {
        let stats = "pending=\(pendingCount) failed=\(failedCount) succeeded=\(totalSucceeded) retries=\(totalRetries)"
        log.info("SyncQueue: \(stats)")

        if !failed.isEmpty {
            for item in failed.values {
                log.warning("  Failed: \(item.shortId) (\(item.item.description)) - \(item.lastError ?? "unknown")")
            }
        }
    }
}
