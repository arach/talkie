//
//  WorkflowRunModel.swift
//  Talkie
//
//  Workflow run model with Vercel-compatible schema
//  Event-sourcing ready for hybrid local/remote execution
//

import Foundation
import GRDB

// MARK: - Workflow Run Model

struct WorkflowRunModel: Identifiable, Codable, Hashable {
    // MARK: - Core Identity
    let id: UUID
    let memoId: UUID
    let workflowId: UUID
    var workflowName: String
    var workflowIcon: String?

    // MARK: - Status (Vercel-compatible enum)
    var status: Status

    // MARK: - Timestamps (Vercel-compatible)
    var createdAt: Date          // When run was created
    var updatedAt: Date          // Last status change
    var startedAt: Date?         // When first step began
    var completedAt: Date?       // When run finished
    var runDate: Date            // Legacy: same as createdAt (keep for compatibility)

    // MARK: - Execution Context Snapshot
    var inputTranscript: String?
    var inputTitle: String?
    var inputDate: Date?

    // MARK: - Results
    var output: String?          // Legacy: combined output (keep for compatibility)
    var finalOutputs: String?    // Vercel: JSON map of all outputs
    var errorMessage: String?    // If status = failed
    var errorStack: String?      // Full error details

    // MARK: - Metadata (Vercel-compatible)
    var durationMs: Int?         // Total execution time
    var stepCount: Int           // Number of steps executed
    var triggerSource: TriggerSource

    // MARK: - LLM Tracking (legacy compatibility)
    var modelId: String?
    var providerName: String?

    // MARK: - Step Details
    var stepOutputsJSON: String?  // JSON array of step outputs (legacy)

    // MARK: - Backend Info (WFKit)
    var backendId: String

    // MARK: - Versioning
    var workflowVersion: Int

    // MARK: - Enums

    enum Status: String, Codable, Hashable {
        case pending
        case running
        case completed
        case failed
        case cancelled
    }

    enum TriggerSource: String, Codable, Hashable {
        case manual
        case auto
        case api
        case live
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        memoId: UUID,
        workflowId: UUID,
        workflowName: String,
        workflowIcon: String? = nil,
        status: Status = .completed,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        runDate: Date? = nil,  // Legacy compatibility
        inputTranscript: String? = nil,
        inputTitle: String? = nil,
        inputDate: Date? = nil,
        output: String? = nil,
        finalOutputs: String? = nil,
        errorMessage: String? = nil,
        errorStack: String? = nil,
        durationMs: Int? = nil,
        stepCount: Int = 0,
        triggerSource: TriggerSource = .manual,
        modelId: String? = nil,
        providerName: String? = nil,
        stepOutputsJSON: String? = nil,
        backendId: String = "local-swift",
        workflowVersion: Int = 1
    ) {
        self.id = id
        self.memoId = memoId
        self.workflowId = workflowId
        self.workflowName = workflowName
        self.workflowIcon = workflowIcon
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.runDate = runDate ?? createdAt  // Default to createdAt
        self.inputTranscript = inputTranscript
        self.inputTitle = inputTitle
        self.inputDate = inputDate
        self.output = output
        self.finalOutputs = finalOutputs
        self.errorMessage = errorMessage
        self.errorStack = errorStack
        self.durationMs = durationMs
        self.stepCount = stepCount
        self.triggerSource = triggerSource
        self.modelId = modelId
        self.providerName = providerName
        self.stepOutputsJSON = stepOutputsJSON
        self.backendId = backendId
        self.workflowVersion = workflowVersion
    }
}

// MARK: - GRDB Record

extension WorkflowRunModel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "workflow_runs"

    enum Columns {
        // Core Identity
        static let id = Column(CodingKeys.id)
        static let memoId = Column(CodingKeys.memoId)
        static let workflowId = Column(CodingKeys.workflowId)
        static let workflowName = Column(CodingKeys.workflowName)
        static let workflowIcon = Column(CodingKeys.workflowIcon)

        // Status
        static let status = Column(CodingKeys.status)

        // Timestamps
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let startedAt = Column(CodingKeys.startedAt)
        static let completedAt = Column(CodingKeys.completedAt)
        static let runDate = Column(CodingKeys.runDate)

        // Execution Context
        static let inputTranscript = Column(CodingKeys.inputTranscript)
        static let inputTitle = Column(CodingKeys.inputTitle)
        static let inputDate = Column(CodingKeys.inputDate)

        // Results
        static let output = Column(CodingKeys.output)
        static let finalOutputs = Column(CodingKeys.finalOutputs)
        static let errorMessage = Column(CodingKeys.errorMessage)
        static let errorStack = Column(CodingKeys.errorStack)

        // Metadata
        static let durationMs = Column(CodingKeys.durationMs)
        static let stepCount = Column(CodingKeys.stepCount)
        static let triggerSource = Column(CodingKeys.triggerSource)

        // LLM Tracking
        static let modelId = Column(CodingKeys.modelId)
        static let providerName = Column(CodingKeys.providerName)

        // Step Details
        static let stepOutputsJSON = Column(CodingKeys.stepOutputsJSON)

        // Backend
        static let backendId = Column(CodingKeys.backendId)

        // Versioning
        static let workflowVersion = Column(CodingKeys.workflowVersion)
    }

    /// Association back to memo
    static let memo = belongsTo(MemoModel.self)
}

// MARK: - Computed Properties

extension WorkflowRunModel {
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

    var isCancelled: Bool {
        status == .cancelled
    }

    /// Parsed step outputs (legacy format)
    var stepOutputs: [StepOutput]? {
        guard let json = stepOutputsJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([StepOutput].self, from: data)
    }

    /// Parsed final outputs (Vercel format)
    var parsedFinalOutputs: [String: String]? {
        guard let json = finalOutputs,
              let data = json.data(using: .utf8),
              let outputs = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return outputs
    }

    /// Helper: Mark run as started
    mutating func markStarted() {
        self.status = .running
        self.startedAt = Date()
        self.updatedAt = Date()
    }

    /// Helper: Mark run as completed with outputs
    mutating func markCompleted(outputs: [String: String], duration: TimeInterval) {
        self.status = .completed
        self.completedAt = Date()
        self.updatedAt = Date()
        self.durationMs = Int(duration * 1000)

        // Serialize outputs to JSON
        if let jsonData = try? JSONEncoder().encode(outputs),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.finalOutputs = jsonString
            self.output = outputs.values.first  // Legacy: first output
        }
    }

    /// Helper: Mark run as failed with error
    mutating func markFailed(error: Error) {
        self.status = .failed
        self.completedAt = Date()
        self.updatedAt = Date()
        self.errorMessage = error.localizedDescription
        self.errorStack = String(describing: error)
    }
}

// MARK: - Supporting Types

struct StepOutput: Codable, Hashable {
    let stepName: String
    let output: String
    let timestamp: Date
}

// MARK: - Sendable Conformance

extension WorkflowRunModel: Sendable {}
extension WorkflowRunModel.Status: Sendable {}
extension WorkflowRunModel.TriggerSource: Sendable {}
extension StepOutput: Sendable {}
