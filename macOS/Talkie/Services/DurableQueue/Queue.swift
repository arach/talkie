//
//  Queue.swift
//  Talkie
//
//  Unified queue with optional durability.
//  - durable: false → in-memory (fast, ephemeral)
//  - durable: true  → SQLite-backed (crash-safe, resumes on launch)
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.sync)

// MARK: - Queue

public actor Queue<Payload: Codable & Sendable> {
    // Configuration
    public let name: String
    public let durable: Bool
    public let retryPolicy: RetryPolicy

    // State
    private var memoryStore: [UUID: PendingJob] = [:]
    private var durableStore: GRDBQueuePersister?
    private var isProcessing = false
    private var processTask: Task<Void, Never>?
    private var handler: ((Payload) async throws -> Void)?
    private let pollInterval: Duration = .seconds(1)

    // Stats
    private(set) public var totalProcessed: Int = 0
    private(set) public var totalSucceeded: Int = 0
    private(set) public var totalFailed: Int = 0

    // In-memory job wrapper
    private struct PendingJob {
        let job: QueueJob
        var nextRetryAt: Date?

        var isReady: Bool {
            guard let next = nextRetryAt else { return true }
            return Date() >= next
        }
    }

    // MARK: - Initialization

    private let dbPath: String?
    private var didInitialize = false

    public init(
        name: String,
        durable: Bool = false,
        dbPath: String? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        self.name = name
        self.durable = durable
        self.dbPath = dbPath
        self.retryPolicy = retryPolicy
    }

    /// Auto-initialize durable storage on first use
    private func ensureInitialized() async throws {
        guard durable, !didInitialize else { return }

        let path = dbPath ?? Self.defaultDbPath(name: name)
        log.info("[\(name)] Initializing durable queue at \(path)")

        durableStore = try GRDBQueuePersister(path: path)
        try await durableStore?.migrate()
        didInitialize = true
    }

    // MARK: - Public API

    /// Enqueue a job - fire and forget
    public func enqueue(_ payload: Payload, priority: QueuePriority = .normal) async throws {
        try await ensureInitialized()

        let data = try JSONEncoder().encode(payload)
        let job = QueueJob(
            queueName: name,
            jobType: String(describing: Payload.self),
            payload: data,
            priority: priority
        )

        if durable, let store = durableStore {
            try await store.save(job)
        } else {
            memoryStore[job.id] = PendingJob(job: job)
        }

        log.debug("[\(job.shortId)] Enqueued (\(priority))")
        scheduleProcessing()
    }

    /// Start processing with handler
    public func start(handler: @escaping (Payload) async throws -> Void) async {
        try? await ensureInitialized()
        self.handler = handler

        // Recover stuck jobs (crashed while running)
        if durable, let store = durableStore {
            await recoverStuckJobs(store: store)
        }

        // Log resumed jobs for durable queues
        if durable, let counts = try? await counts(), counts.pending > 0 {
            log.info("[\(name)] Resuming \(counts.pending) pending job(s)")
        }

        scheduleProcessing()
        log.info("[\(name)] Started")
    }

    /// Reset jobs stuck in 'running' state (crashed mid-process)
    private func recoverStuckJobs(store: GRDBQueuePersister) async {
        do {
            let stuckJobs = try await store.fetch(queueName: name, statuses: [.running])
            for var job in stuckJobs {
                job.status = .pending
                job.attempt += 1  // Count the failed attempt
                job.lastError = "Recovered after crash (was stuck in running state)"
                try await store.save(job)
                log.warning("[\(job.shortId)] Recovered stuck job (attempt #\(job.attempt))")
            }
            if !stuckJobs.isEmpty {
                log.info("[\(name)] Recovered \(stuckJobs.count) stuck job(s)")
            }
        } catch {
            log.error("[\(name)] Failed to recover stuck jobs: \(error.localizedDescription)")
        }
    }

    /// Stop processing
    public func stop() {
        processTask?.cancel()
        processTask = nil
        handler = nil
        log.info("[\(name)] Stopped")
    }

    /// Get current counts
    public func counts() async throws -> (pending: Int, running: Int, failed: Int) {
        if durable, let store = durableStore {
            let pendingCount = try await store.count(queueName: name, status: .pending)
            let scheduledCount = try await store.count(queueName: name, status: .scheduled)
            let running = try await store.count(queueName: name, status: .running)
            let failed = try await store.count(queueName: name, status: .dead)
            return (pendingCount + scheduledCount, running, failed)
        } else {
            let pending = memoryStore.values.filter {
                $0.job.status == .pending || $0.job.status == .scheduled
            }.count
            return (pending, 0, 0)
        }
    }

    /// Flush all pending jobs
    public func flush() async {
        while (try? await counts().pending) ?? 0 > 0 {
            await processOnce()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Processing

    private func scheduleProcessing() {
        guard handler != nil else { return }
        guard processTask == nil || processTask?.isCancelled == true else { return }

        processTask = Task {
            while !Task.isCancelled {
                await processOnce()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func processOnce() async {
        guard let handler = handler else { return }
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        let jobs: [QueueJob]

        if durable, let store = durableStore {
            jobs = (try? await store.fetchDue(queueName: name)) ?? []
        } else {
            jobs = memoryStore.values
                .filter { $0.isReady }
                .map { $0.job }
                .sorted { $0.priority > $1.priority || $0.createdAt < $1.createdAt }
        }

        for job in jobs {
            await processJob(job, handler: handler)
        }
    }

    private func processJob(_ job: QueueJob, handler: (Payload) async throws -> Void) async {
        let start = Date()
        totalProcessed += 1

        do {
            // Mark running (durable only)
            if durable, let store = durableStore {
                do {
                    try await store.markStarted(job.id)
                } catch {
                    log.error("[\(job.shortId)] Failed to mark started: \(error.localizedDescription)")
                }
            }

            // Execute
            let payload = try job.decodePayload(as: Payload.self)
            try await handler(payload)

            // Success - remove
            if durable, let store = durableStore {
                do {
                    try await store.remove(job.id)
                } catch {
                    log.error("[\(job.shortId)] Failed to remove completed job: \(error.localizedDescription)")
                }
            } else {
                memoryStore.removeValue(forKey: job.id)
            }

            totalSucceeded += 1
            let duration = Date().timeIntervalSince(start)
            let retryInfo = job.attempt > 0 ? " (attempt #\(job.attempt + 1))" : ""
            log.info("[\(job.shortId)] Done in \(String(format: "%.0fms", duration * 1000))\(retryInfo)")

        } catch {
            await handleFailure(job: job, error: error)
        }
    }

    private func handleFailure(job: QueueJob, error: Error) async {
        var updatedJob = job
        updatedJob.attempt += 1
        updatedJob.lastError = error.localizedDescription

        if let delay = retryPolicy.delay(forAttempt: updatedJob.attempt) {
            // Schedule retry
            updatedJob.status = .scheduled
            updatedJob.scheduledAt = Date().addingTimeInterval(delay)

            if durable, let store = durableStore {
                do {
                    try await store.save(updatedJob)
                } catch let saveError {
                    log.error("[\(job.shortId)] Failed to schedule retry: \(saveError.localizedDescription)")
                }
            } else {
                memoryStore[job.id] = PendingJob(
                    job: updatedJob,
                    nextRetryAt: updatedJob.scheduledAt
                )
            }

            log.warning("[\(job.shortId)] Retry #\(updatedJob.attempt) in \(String(format: "%.1fs", delay))")
        } else {
            // Dead
            totalFailed += 1

            if durable, let store = durableStore {
                updatedJob.status = .dead
                do {
                    try await store.save(updatedJob)
                } catch let saveError {
                    log.error("[\(job.shortId)] Failed to mark as dead: \(saveError.localizedDescription)")
                }
            } else {
                memoryStore.removeValue(forKey: job.id)
            }

            log.error("[\(job.shortId)] Failed after \(updatedJob.attempt) attempts: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func defaultDbPath(name: String) -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dir = appSupport.appendingPathComponent("Talkie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return dir.appendingPathComponent("\(name)_queue.sqlite").path
    }
}
