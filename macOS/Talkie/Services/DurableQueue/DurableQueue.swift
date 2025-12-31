//
//  DurableQueue.swift
//  Talkie
//
//  A GRDB-backed durable queue with retry, backoff, and persistence.
//  Inspired by SwiftQueue patterns but modernized for Swift Concurrency.
//
//  Design principles:
//  - Jobs survive app crashes (GRDB persistence)
//  - Retry policies are configurable and separated from enforcement
//  - Persister protocol allows swapping storage backends
//  - Generic over payload type for reuse across projects
//

import Foundation
import GRDB
import TalkieKit

private let log = Log(.sync)

// MARK: - Queue Priority

public enum QueuePriority: Int, Codable, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: QueuePriority, rhs: QueuePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Retry Policy

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let strategy: Strategy
    public let jitter: Bool  // Add randomness to prevent thundering herd

    public enum Strategy: Sendable {
        case none
        case immediate
        case fixed(delay: TimeInterval)
        case exponential(initial: TimeInterval, max: TimeInterval)
    }

    public init(maxAttempts: Int, strategy: Strategy, jitter: Bool = false) {
        self.maxAttempts = maxAttempts
        self.strategy = strategy
        self.jitter = jitter
    }

    // Presets
    public static let none = RetryPolicy(maxAttempts: 1, strategy: .none)
    public static let `default` = RetryPolicy(
        maxAttempts: 5,
        strategy: .exponential(initial: 1, max: 32),
        jitter: true
    )
    public static let aggressive = RetryPolicy(
        maxAttempts: 10,
        strategy: .exponential(initial: 0.5, max: 60),
        jitter: true
    )

    /// Calculate delay for given attempt (0-indexed)
    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt < maxAttempts else { return nil }

        var delay: TimeInterval
        switch strategy {
        case .none:
            return nil
        case .immediate:
            delay = 0
        case .fixed(let d):
            delay = d
        case .exponential(let initial, let max):
            delay = min(initial * pow(2.0, Double(attempt)), max)
        }

        // Add jitter: ±25% randomness
        if jitter && delay > 0 {
            let jitterRange = delay * 0.25
            delay += Double.random(in: -jitterRange...jitterRange)
            delay = max(0, delay)  // Don't go negative
        }

        return delay
    }
}

// MARK: - Job Status

public enum JobStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case pending    // Waiting to be processed
    case scheduled  // Waiting for scheduled time (retry backoff)
    case running    // Currently being processed
    case completed  // Successfully finished
    case failed     // Failed, will retry
    case dead       // Exceeded max retries, moved to dead letter
}

// MARK: - Queue Job Model

public struct QueueJob: Codable, Sendable, Identifiable {
    public let id: UUID
    public let queueName: String
    public let jobType: String
    public let payload: Data
    public let priority: QueuePriority
    public var status: JobStatus
    public var attempt: Int
    public var lastError: String?
    public let createdAt: Date
    public var scheduledAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        queueName: String,
        jobType: String,
        payload: Data,
        priority: QueuePriority = .normal,
        status: JobStatus = .pending,
        attempt: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        scheduledAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.queueName = queueName
        self.jobType = jobType
        self.payload = payload
        self.priority = priority
        self.status = status
        self.attempt = attempt
        self.lastError = lastError
        self.createdAt = createdAt
        self.scheduledAt = scheduledAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    /// Decode the payload as a specific type
    public func decodePayload<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: payload)
    }

    /// Short ID for logging
    public var shortId: String {
        String(id.uuidString.prefix(8))
    }
}

// MARK: - GRDB Persistence

extension QueueJob: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "queue_jobs"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let queueName = Column(CodingKeys.queueName)
        static let jobType = Column(CodingKeys.jobType)
        static let payload = Column(CodingKeys.payload)
        static let priority = Column(CodingKeys.priority)
        static let status = Column(CodingKeys.status)
        static let attempt = Column(CodingKeys.attempt)
        static let lastError = Column(CodingKeys.lastError)
        static let createdAt = Column(CodingKeys.createdAt)
        static let scheduledAt = Column(CodingKeys.scheduledAt)
        static let startedAt = Column(CodingKeys.startedAt)
        static let completedAt = Column(CodingKeys.completedAt)
    }
}

// MARK: - Persister Protocol

public protocol QueuePersister: Sendable {
    /// Save or update a job
    func save(_ job: QueueJob) async throws

    /// Remove a job by ID
    func remove(_ jobId: UUID) async throws

    /// Fetch jobs by queue and status
    func fetch(queueName: String, statuses: [JobStatus]) async throws -> [QueueJob]

    /// Fetch jobs that are due for processing (scheduledAt <= now)
    func fetchDue(queueName: String) async throws -> [QueueJob]

    /// Update job status
    func updateStatus(_ jobId: UUID, status: JobStatus, error: String?) async throws

    /// Mark job as started
    func markStarted(_ jobId: UUID) async throws

    /// Count jobs by status
    func count(queueName: String, status: JobStatus) async throws -> Int

    /// Get all queue names that have pending work
    func activeQueueNames() async throws -> [String]

    /// Migrate/create schema
    func migrate() async throws
}

// MARK: - GRDB Persister Implementation

public actor GRDBQueuePersister: QueuePersister {
    private let dbPool: DatabasePool

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    public init(path: String) throws {
        self.dbPool = try DatabasePool(path: path)
    }

    public func migrate() async throws {
        try await dbPool.write { db in
            try db.create(table: QueueJob.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("queueName", .text).notNull().indexed()
                t.column("jobType", .text).notNull()
                t.column("payload", .blob).notNull()
                t.column("priority", .integer).notNull()
                t.column("status", .text).notNull().indexed()
                t.column("attempt", .integer).notNull()
                t.column("lastError", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("scheduledAt", .datetime).notNull().indexed()
                t.column("startedAt", .datetime)
                t.column("completedAt", .datetime)
            }

            // Compound index for efficient job fetching
            try db.create(
                index: "idx_queue_jobs_fetch",
                on: QueueJob.databaseTableName,
                columns: ["queueName", "status", "scheduledAt", "priority"],
                ifNotExists: true
            )
        }
    }

    public func save(_ job: QueueJob) async throws {
        try await dbPool.write { db in
            try job.save(db)
        }
    }

    public func remove(_ jobId: UUID) async throws {
        try await dbPool.write { db in
            _ = try QueueJob.deleteOne(db, key: jobId)
        }
    }

    public func fetch(queueName: String, statuses: [JobStatus]) async throws -> [QueueJob] {
        try await dbPool.read { db in
            try QueueJob
                .filter(QueueJob.Columns.queueName == queueName)
                .filter(statuses.map(\.rawValue).contains(QueueJob.Columns.status))
                .order(QueueJob.Columns.priority.desc, QueueJob.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    public func fetchDue(queueName: String) async throws -> [QueueJob] {
        try await dbPool.read { db in
            try QueueJob
                .filter(QueueJob.Columns.queueName == queueName)
                .filter([JobStatus.pending.rawValue, JobStatus.scheduled.rawValue].contains(QueueJob.Columns.status))
                .filter(QueueJob.Columns.scheduledAt <= Date())
                .order(QueueJob.Columns.priority.desc, QueueJob.Columns.scheduledAt.asc)
                .fetchAll(db)
        }
    }

    public func updateStatus(_ jobId: UUID, status: JobStatus, error: String?) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE \(QueueJob.databaseTableName)
                    SET status = ?, lastError = ?
                    WHERE id = ?
                    """,
                arguments: [status.rawValue, error, jobId.uuidString]
            )
        }
    }

    public func markStarted(_ jobId: UUID) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE \(QueueJob.databaseTableName)
                    SET status = ?, startedAt = ?
                    WHERE id = ?
                    """,
                arguments: [JobStatus.running.rawValue, Date(), jobId.uuidString]
            )
        }
    }

    public func count(queueName: String, status: JobStatus) async throws -> Int {
        try await dbPool.read { db in
            try QueueJob
                .filter(QueueJob.Columns.queueName == queueName)
                .filter(QueueJob.Columns.status == status.rawValue)
                .fetchCount(db)
        }
    }

    public func activeQueueNames() async throws -> [String] {
        try await dbPool.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT queueName FROM \(QueueJob.databaseTableName)
                WHERE status IN (?, ?, ?)
                """,
                arguments: [JobStatus.pending.rawValue, JobStatus.scheduled.rawValue, JobStatus.running.rawValue]
            )
        }
    }
}

// MARK: - Durable Queue

public actor DurableQueue<Payload: Codable & Sendable> {
    // Configuration
    public let name: String
    public let jobType: String
    public let retryPolicy: RetryPolicy

    // Dependencies
    private let persister: QueuePersister

    // State
    private var isProcessing = false
    private var processTask: Task<Void, Never>?
    private var handler: ((Payload) async throws -> Void)?
    private var pollInterval: Duration = .seconds(1)

    // Stats
    private(set) var totalProcessed: Int = 0
    private(set) var totalSucceeded: Int = 0
    private(set) var totalFailed: Int = 0
    private(set) var totalRetries: Int = 0

    public init(
        name: String,
        jobType: String? = nil,
        persister: QueuePersister,
        retryPolicy: RetryPolicy = .default
    ) {
        self.name = name
        self.jobType = jobType ?? String(describing: Payload.self)
        self.persister = persister
        self.retryPolicy = retryPolicy
    }

    // MARK: - Public API

    /// Enqueue a job for processing
    public func enqueue(_ payload: Payload, priority: QueuePriority = .normal) async throws {
        let data = try JSONEncoder().encode(payload)
        let job = QueueJob(
            queueName: name,
            jobType: jobType,
            payload: data,
            priority: priority
        )

        try await persister.save(job)
        log.debug("[\(job.shortId)] Enqueued \(jobType) (\(priority))")

        // Kick processing if we have a handler
        if handler != nil {
            scheduleProcessing()
        }
    }

    /// Start processing with the given handler
    public func start(handler: @escaping (Payload) async throws -> Void) {
        self.handler = handler
        scheduleProcessing()
        log.info("[\(name)] Queue started")
    }

    /// Stop processing
    public func stop() {
        processTask?.cancel()
        processTask = nil
        handler = nil
        log.info("[\(name)] Queue stopped")
    }

    /// Process all pending jobs and wait for completion
    public func flush() async {
        while await hasPendingWork() {
            await processOnce()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Check if there's pending work
    public func hasPendingWork() async -> Bool {
        do {
            let pending = try await persister.count(queueName: name, status: .pending)
            let scheduled = try await persister.count(queueName: name, status: .scheduled)
            return pending + scheduled > 0
        } catch {
            return false
        }
    }

    /// Get current stats
    public func stats() -> (processed: Int, succeeded: Int, failed: Int, retries: Int) {
        (totalProcessed, totalSucceeded, totalFailed, totalRetries)
    }

    /// Get counts by status
    public func counts() async throws -> (pending: Int, running: Int, dead: Int) {
        let pendingCount = try await persister.count(queueName: name, status: .pending)
        let scheduledCount = try await persister.count(queueName: name, status: .scheduled)
        let running = try await persister.count(queueName: name, status: .running)
        let dead = try await persister.count(queueName: name, status: .dead)
        return (pendingCount + scheduledCount, running, dead)
    }

    // MARK: - Processing

    private func scheduleProcessing() {
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

        do {
            let jobs = try await persister.fetchDue(queueName: name)

            for job in jobs {
                await processJob(job, handler: handler)
            }
        } catch {
            log.error("[\(name)] Failed to fetch jobs: \(error.localizedDescription)")
        }
    }

    private func processJob(_ job: QueueJob, handler: (Payload) async throws -> Void) async {
        let start = Date()
        totalProcessed += 1

        do {
            // Mark as running
            try await persister.markStarted(job.id)

            // Decode and execute
            let payload = try job.decodePayload(as: Payload.self)
            try await handler(payload)

            // Success - remove from queue
            try await persister.remove(job.id)
            totalSucceeded += 1

            let duration = Date().timeIntervalSince(start)
            let retryInfo = job.attempt > 0 ? " (attempt #\(job.attempt + 1))" : ""
            log.info("[\(job.shortId)] Completed in \(String(format: "%.0fms", duration * 1000))\(retryInfo)")

        } catch {
            await handleFailure(job: job, error: error)
        }
    }

    private func handleFailure(job: QueueJob, error: Error) async {
        var updatedJob = job
        updatedJob.attempt += 1
        updatedJob.lastError = error.localizedDescription

        // Check if we should retry
        if let delay = retryPolicy.delay(forAttempt: updatedJob.attempt) {
            // Schedule retry
            updatedJob.status = .scheduled
            updatedJob.scheduledAt = Date().addingTimeInterval(delay)
            totalRetries += 1

            do {
                try await persister.save(updatedJob)
                log.warning("[\(job.shortId)] Retry #\(updatedJob.attempt) in \(delay)s: \(error.localizedDescription)")
            } catch {
                log.error("[\(job.shortId)] Failed to schedule retry: \(error.localizedDescription)")
            }
        } else {
            // Move to dead letter
            updatedJob.status = .dead
            updatedJob.completedAt = Date()
            totalFailed += 1

            do {
                try await persister.save(updatedJob)
                log.error("[\(job.shortId)] Dead after \(updatedJob.attempt) attempts: \(error.localizedDescription)")
            } catch {
                log.error("[\(job.shortId)] Failed to mark as dead: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Convenience Factory

extension DurableQueue {
    /// Create a queue with a new GRDB database at the specified path
    public static func create(
        name: String,
        dbPath: String,
        retryPolicy: RetryPolicy = .default
    ) async throws -> DurableQueue {
        let persister = try GRDBQueuePersister(path: dbPath)
        try await persister.migrate()
        return DurableQueue(name: name, persister: persister, retryPolicy: retryPolicy)
    }
}
