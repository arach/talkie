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
        do {
            try await ensureInitialized()
        } catch {
            log.error("[\(name)] Failed to initialize: \(error.localizedDescription)")
        }

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
            var recovered = 0
            var dead = 0

            for var job in stuckJobs {
                job.attempt += 1
                job.lastError = "Crashed while running"

                // Check if exhausted retries
                if retryPolicy.delay(forAttempt: job.attempt) == nil {
                    job.status = .dead
                    job.completedAt = Date()
                    dead += 1
                    log.error("[\(job.shortId)] Dead after crash (exhausted \(job.attempt) attempts)")
                } else {
                    job.status = .pending
                    recovered += 1
                    log.warning("[\(job.shortId)] Recovered stuck job (attempt #\(job.attempt))")
                }

                try await store.save(job)
            }

            if recovered > 0 || dead > 0 {
                log.info("[\(name)] Stuck jobs: \(recovered) recovered, \(dead) dead")
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

    /// Flush all pending jobs (with safety limit to prevent infinite loops)
    public func flush(maxIterations: Int = 100) async {
        var iterations = 0
        while (try? await counts().pending) ?? 0 > 0 {
            await processOnce()
            iterations += 1
            if iterations >= maxIterations {
                log.warning("[\(name)] Flush hit max iterations (\(maxIterations)), stopping")
                break
            }
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
            // Atomic claim: fetches AND marks as running in one transaction
            do {
                jobs = try await store.claimDue(queueName: name, limit: 10)
            } catch {
                log.error("[\(name)] Failed to claim jobs: \(error.localizedDescription)")
                return
            }
        } else {
            // Memory store: mark as running manually
            var claimed: [QueueJob] = []
            let ready = memoryStore.values
                .filter { $0.isReady }
                .sorted {
                    if $0.job.priority != $1.job.priority {
                        return $0.job.priority > $1.job.priority
                    }
                    return $0.job.createdAt < $1.job.createdAt
                }
            for pending in ready {
                var job = pending.job
                job.status = .running
                job.startedAt = Date()
                memoryStore[job.id] = PendingJob(job: job, nextRetryAt: nil)
                claimed.append(job)
            }
            jobs = claimed
        }

        for job in jobs {
            await processJob(job, handler: handler)
        }
    }

    private func processJob(_ job: QueueJob, handler: (Payload) async throws -> Void) async {
        let start = Date()
        totalProcessed += 1

        do {
            // Job is already marked as running by claimDue/processOnce
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
