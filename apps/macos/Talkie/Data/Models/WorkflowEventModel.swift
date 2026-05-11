//
//  WorkflowEventModel.swift
//  Talkie
//
//  Workflow event model for event sourcing (Vercel-compatible)
//  Immutable event log - the source of truth for workflow state
//

import Foundation
import GRDB

// MARK: - Workflow Event Model

struct WorkflowEventModel: Identifiable, Codable, Hashable {
    // MARK: - Identity
    let id: UUID
    let runId: UUID
    let sequence: Int  // Order within run (auto-increment)

    // MARK: - Event Type
    var eventType: EventType

    // MARK: - Timestamp
    var createdAt: Date

    // MARK: - Payload (event-specific data)
    var payload: String  // JSON: varies by event_type

    // MARK: - Optional Step Reference
    var stepId: UUID?

    // MARK: - Event Types

    enum EventType: String, Codable, Hashable {
        // Run Lifecycle
        case runCreated
        case runStarted
        case runCompleted
        case runFailed
        case runCancelled

        // Step Lifecycle
        case stepCreated
        case stepStarted
        case stepCompleted
        case stepFailed
        case stepSkipped
        case stepRetrying

        // Execution Events
        case outputGenerated
        case variableResolved
        case conditionEvaluated

        // External Events
        case webhookReceived
        case userIntervention

        // Backend Events
        case backendSwitched
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        runId: UUID,
        sequence: Int = 0,  // Will be auto-incremented by DB
        eventType: EventType,
        createdAt: Date = Date(),
        payload: String = "{}",
        stepId: UUID? = nil
    ) {
        self.id = id
        self.runId = runId
        self.sequence = sequence
        self.eventType = eventType
        self.createdAt = createdAt
        self.payload = payload
        self.stepId = stepId
    }

    /// Convenience initializer with dictionary payload
    init(
        id: UUID = UUID(),
        runId: UUID,
        sequence: Int = 0,
        eventType: EventType,
        createdAt: Date = Date(),
        payloadDict: [String: Any],
        stepId: UUID? = nil
    ) {
        self.id = id
        self.runId = runId
        self.sequence = sequence
        self.eventType = eventType
        self.createdAt = createdAt
        self.stepId = stepId

        // Serialize dictionary to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: payloadDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.payload = jsonString
        } else {
            self.payload = "{}"
        }
    }
}

// MARK: - GRDB Persistence

extension WorkflowEventModel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "workflow_events"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let runId = Column(CodingKeys.runId)
        static let sequence = Column(CodingKeys.sequence)
        static let eventType = Column(CodingKeys.eventType)
        static let createdAt = Column(CodingKeys.createdAt)
        static let payload = Column(CodingKeys.payload)
        static let stepId = Column(CodingKeys.stepId)
    }

    /// Association back to workflow run
    static let run = belongsTo(WorkflowRunModel.self)

    /// Optional association to step
    static let step = belongsTo(WorkflowStepModel.self)
}

// MARK: - Computed Properties

extension WorkflowEventModel {
    /// Parse payload as dictionary
    var parsedPayload: [String: Any]? {
        guard let data = payload.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    /// Check if event is a run lifecycle event
    var isRunEvent: Bool {
        switch eventType {
        case .runCreated, .runStarted, .runCompleted, .runFailed, .runCancelled:
            return true
        default:
            return false
        }
    }

    /// Check if event is a step lifecycle event
    var isStepEvent: Bool {
        switch eventType {
        case .stepCreated, .stepStarted, .stepCompleted, .stepFailed, .stepSkipped, .stepRetrying:
            return true
        default:
            return false
        }
    }
}

// MARK: - Event Helpers

extension WorkflowEventModel {
    /// Create a run created event
    static func runCreated(
        runId: UUID,
        workflowName: String,
        triggerSource: String
    ) -> WorkflowEventModel {
        WorkflowEventModel(
            runId: runId,
            eventType: .runCreated,
            payloadDict: [
                "workflow_name": workflowName,
                "trigger_source": triggerSource
            ]
        )
    }

    /// Create a run started event
    static func runStarted(runId: UUID) -> WorkflowEventModel {
        WorkflowEventModel(
            runId: runId,
            eventType: .runStarted
        )
    }

    /// Create a run completed event
    static func runCompleted(
        runId: UUID,
        outputCount: Int,
        duration: TimeInterval
    ) -> WorkflowEventModel {
        WorkflowEventModel(
            runId: runId,
            eventType: .runCompleted,
            payloadDict: [
                "output_count": outputCount,
                "duration_ms": Int(duration * 1000)
            ]
        )
    }

    /// Create a run failed event
    static func runFailed(
        runId: UUID,
        error: Error,
        failedStepNumber: Int? = nil
    ) -> WorkflowEventModel {
        var payload: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error_message": error.localizedDescription
        ]
        if let stepNum = failedStepNumber {
            payload["failed_step"] = stepNum
        }
        return WorkflowEventModel(
            runId: runId,
            eventType: .runFailed,
            payloadDict: payload
        )
    }

    /// Create a step completed event
    static func stepCompleted(
        runId: UUID,
        stepId: UUID,
        stepNumber: Int,
        stepType: String,
        outputKey: String,
        outputLength: Int,
        duration: TimeInterval
    ) -> WorkflowEventModel {
        WorkflowEventModel(
            runId: runId,
            eventType: .stepCompleted,
            payloadDict: [
                "step_number": stepNumber,
                "step_type": stepType,
                "output_key": outputKey,
                "output_length": outputLength,
                "duration_ms": Int(duration * 1000)
            ],
            stepId: stepId
        )
    }
}

// MARK: - Sendable Conformance

extension WorkflowEventModel: Sendable {}
extension WorkflowEventModel.EventType: Sendable {}
