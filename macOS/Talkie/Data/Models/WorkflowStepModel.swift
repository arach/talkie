//
//  WorkflowStepModel.swift
//  Talkie
//
//  Individual workflow step execution model (Vercel-compatible)
//  Tracks each step within a workflow run
//

import Foundation
import GRDB

// MARK: - Workflow Step Model

struct WorkflowStepModel: Identifiable, Codable, Hashable {
    // MARK: - Identity
    let id: UUID
    let runId: UUID
    let stepNumber: Int  // Execution order (0-indexed)

    // MARK: - Step Definition
    var stepType: String        // 'llm', 'shell', 'transcribe', etc.
    var stepConfig: String      // JSON config for this step
    var outputKey: String       // Variable name for output

    // MARK: - Execution Status
    var status: Status

    // MARK: - Timestamps
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    // MARK: - Input/Output
    var inputSnapshot: String?   // Resolved input (after template vars)
    var outputValue: String?     // Step result

    // MARK: - Metadata
    var durationMs: Int?
    var retryCount: Int

    // MARK: - LLM-specific (nullable)
    var providerName: String?
    var modelId: String?
    var tokensUsed: Int?
    var costUsd: Double?

    // MARK: - Error Handling
    var errorMessage: String?
    var errorStack: String?

    // MARK: - Backend
    var backendId: String

    // MARK: - Enums

    enum Status: String, Codable, Hashable {
        case pending
        case running
        case completed
        case failed
        case skipped
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        runId: UUID,
        stepNumber: Int,
        stepType: String,
        stepConfig: String = "{}",
        outputKey: String,
        status: Status = .pending,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        inputSnapshot: String? = nil,
        outputValue: String? = nil,
        durationMs: Int? = nil,
        retryCount: Int = 0,
        providerName: String? = nil,
        modelId: String? = nil,
        tokensUsed: Int? = nil,
        costUsd: Double? = nil,
        errorMessage: String? = nil,
        errorStack: String? = nil,
        backendId: String = "local-swift"
    ) {
        self.id = id
        self.runId = runId
        self.stepNumber = stepNumber
        self.stepType = stepType
        self.stepConfig = stepConfig
        self.outputKey = outputKey
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.inputSnapshot = inputSnapshot
        self.outputValue = outputValue
        self.durationMs = durationMs
        self.retryCount = retryCount
        self.providerName = providerName
        self.modelId = modelId
        self.tokensUsed = tokensUsed
        self.costUsd = costUsd
        self.errorMessage = errorMessage
        self.errorStack = errorStack
        self.backendId = backendId
    }
}

// MARK: - GRDB Persistence

extension WorkflowStepModel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "workflow_steps"

    enum Columns {
        // Identity
        static let id = Column(CodingKeys.id)
        static let runId = Column(CodingKeys.runId)
        static let stepNumber = Column(CodingKeys.stepNumber)

        // Step Definition
        static let stepType = Column(CodingKeys.stepType)
        static let stepConfig = Column(CodingKeys.stepConfig)
        static let outputKey = Column(CodingKeys.outputKey)

        // Status
        static let status = Column(CodingKeys.status)

        // Timestamps
        static let createdAt = Column(CodingKeys.createdAt)
        static let startedAt = Column(CodingKeys.startedAt)
        static let completedAt = Column(CodingKeys.completedAt)

        // Input/Output
        static let inputSnapshot = Column(CodingKeys.inputSnapshot)
        static let outputValue = Column(CodingKeys.outputValue)

        // Metadata
        static let durationMs = Column(CodingKeys.durationMs)
        static let retryCount = Column(CodingKeys.retryCount)

        // LLM-specific
        static let providerName = Column(CodingKeys.providerName)
        static let modelId = Column(CodingKeys.modelId)
        static let tokensUsed = Column(CodingKeys.tokensUsed)
        static let costUsd = Column(CodingKeys.costUsd)

        // Error Handling
        static let errorMessage = Column(CodingKeys.errorMessage)
        static let errorStack = Column(CodingKeys.errorStack)

        // Backend
        static let backendId = Column(CodingKeys.backendId)
    }

    /// Association back to workflow run
    static let run = belongsTo(WorkflowRunModel.self)
}

// MARK: - Computed Properties

extension WorkflowStepModel {
    var isCompleted: Bool {
        status == .completed
    }

    var isFailed: Bool {
        status == .failed
    }

    var isRunning: Bool {
        status == .running
    }

    var isPending: Bool {
        status == .pending
    }

    var isSkipped: Bool {
        status == .skipped
    }

    /// Helper: Mark step as started
    mutating func markStarted() {
        self.status = .running
        self.startedAt = Date()
    }

    /// Helper: Mark step as completed with output
    mutating func markCompleted(output: String, duration: TimeInterval) {
        self.status = .completed
        self.completedAt = Date()
        self.durationMs = Int(duration * 1000)
        self.outputValue = output
    }

    /// Helper: Mark step as failed with error
    mutating func markFailed(error: Error) {
        self.status = .failed
        self.completedAt = Date()
        self.errorMessage = error.localizedDescription
        self.errorStack = String(describing: error)
    }

    /// Helper: Mark step as skipped
    mutating func markSkipped(reason: String? = nil) {
        self.status = .skipped
        self.completedAt = Date()
        if let reason = reason {
            self.errorMessage = reason
        }
    }
}

// MARK: - Sendable Conformance

extension WorkflowStepModel: Sendable {}
extension WorkflowStepModel.Status: Sendable {}
