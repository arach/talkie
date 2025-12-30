//
//  WorkflowWorld.swift
//  Talkie
//
//  Workflow World - Vercel-compatible state persistence abstraction
//  The "World" abstraction defines how workflows persist their state
//

import Foundation

// MARK: - Workflow World Protocol

/// Vercel-compatible "World" abstraction for workflow state persistence
/// This defines the interface for how workflows save and retrieve their execution state
protocol WorkflowWorld {
    /// Save a workflow run
    func createRun(_ run: WorkflowRunModel) async throws

    /// Save a workflow step
    func createStep(_ step: WorkflowStepModel) async throws

    /// Save a workflow event
    func saveEvent(_ event: WorkflowEventModel) async throws

    /// Get all events for a run (ordered by sequence)
    func getEvents(runId: UUID) async throws -> [WorkflowEventModel]

    /// Get all steps for a run (ordered by step number)
    func getSteps(runId: UUID) async throws -> [WorkflowStepModel]

    /// Get a specific run
    func getRun(id: UUID) async throws -> WorkflowRunModel?

    /// Replay a run from its events (time-travel debugging)
    func replayRun(id: UUID) async throws -> WorkflowRunModel
}

// MARK: - Local Storage Implementation

/// Local storage implementation of WorkflowWorld using LocalRepository
actor LocalWorkflowWorld: WorkflowWorld {
    private let repository: LocalRepository

    init(repository: LocalRepository = LocalRepository()) {
        self.repository = repository
    }

    func createRun(_ run: WorkflowRunModel) async throws {
        try await repository.saveWorkflowRun(run)
    }

    func createStep(_ step: WorkflowStepModel) async throws {
        try await repository.saveWorkflowStep(step)
    }

    func saveEvent(_ event: WorkflowEventModel) async throws {
        try await repository.saveWorkflowEvent(event)
    }

    func getEvents(runId: UUID) async throws -> [WorkflowEventModel] {
        try await repository.fetchWorkflowEvents(for: runId)
    }

    func getSteps(runId: UUID) async throws -> [WorkflowStepModel] {
        try await repository.fetchWorkflowSteps(for: runId)
    }

    func getRun(id: UUID) async throws -> WorkflowRunModel? {
        // Fetch from repository
        let memoWithRelationships = try await repository.fetchMemo(id: id)
        return memoWithRelationships?.workflowRuns.first { $0.id == id }
    }

    /// Replay a workflow run from its event log
    /// This reconstructs the run's state by replaying all events in sequence
    func replayRun(id: UUID) async throws -> WorkflowRunModel {
        // Get all events for this run
        let events = try await getEvents(runId: id)

        guard !events.isEmpty else {
            throw WorkflowWorldError.noEventsFound(runId: id)
        }

        // Get the original run as starting point
        guard let originalRun = try await getRun(id: id) else {
            throw WorkflowWorldError.runNotFound(runId: id)
        }

        // Reconstruct state by replaying events
        var reconstructedRun = originalRun

        for event in events {
            switch event.eventType {
            case .runCreated:
                // First event - set creation time
                reconstructedRun.createdAt = event.createdAt

            case .runStarted:
                // Run started - update status and start time
                reconstructedRun.status = .running
                reconstructedRun.startedAt = event.createdAt

            case .runCompleted:
                // Run completed - update status and completion time
                reconstructedRun.status = .completed
                reconstructedRun.completedAt = event.createdAt
                if let payload = event.parsedPayload,
                   let durationMs = payload["duration_ms"] as? Int {
                    reconstructedRun.durationMs = durationMs
                }

            case .runFailed:
                // Run failed - update status and error
                reconstructedRun.status = .failed
                reconstructedRun.completedAt = event.createdAt
                if let payload = event.parsedPayload {
                    reconstructedRun.errorMessage = payload["error_message"] as? String
                }

            case .runCancelled:
                // Run cancelled - update status
                reconstructedRun.status = .cancelled
                reconstructedRun.completedAt = event.createdAt

            case .stepCompleted:
                // Step completed - increment step count
                // (This could be enhanced to track individual step states)
                break

            default:
                // Other events don't affect run state
                break
            }
        }

        return reconstructedRun
    }
}

// MARK: - Errors

enum WorkflowWorldError: Error, LocalizedError {
    case runNotFound(runId: UUID)
    case noEventsFound(runId: UUID)
    case replayFailed(runId: UUID, reason: String)

    var errorDescription: String? {
        switch self {
        case .runNotFound(let runId):
            return "Workflow run not found: \(runId)"
        case .noEventsFound(let runId):
            return "No events found for run: \(runId)"
        case .replayFailed(let runId, let reason):
            return "Failed to replay run \(runId): \(reason)"
        }
    }
}

// MARK: - Sendable Conformance

extension LocalWorkflowWorld: Sendable {}
