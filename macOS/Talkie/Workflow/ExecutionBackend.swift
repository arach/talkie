//
//  ExecutionBackend.swift
//  Talkie macOS
//
//  Core protocol for WFKit execution abstraction
//  Enables "define once, execute anywhere" workflows
//

import Foundation

// MARK: - Execution Backend Protocol

/// Core protocol that all workflow execution backends must implement.
/// This abstraction enables workflows to run on different infrastructure
/// (local Swift, Vercel cloud, Temporal durable execution, etc.)
@MainActor
protocol ExecutionBackend {
    /// Execute a complete workflow from start to finish
    /// - Parameters:
    ///   - workflow: The workflow definition to execute
    ///   - context: Execution context with memo, transcript, outputs
    /// - Returns: Dictionary of output keys to their values
    func execute(
        workflow: WorkflowDefinition,
        context: WorkflowContext
    ) async throws -> [String: String]

    /// Execute a single workflow step (optional, for granular control)
    /// Default implementation delegates to execute() for full workflow
    /// - Parameters:
    ///   - step: The step to execute
    ///   - context: Mutable context that accumulates outputs
    /// - Returns: Result of the step execution
    func executeStep(
        _ step: WorkflowStep,
        context: inout WorkflowContext
    ) async throws -> StepResult

    /// Backend capabilities (what step types are supported, etc.)
    var capabilities: BackendCapabilities { get }

    /// Backend metadata (name, version, description)
    var metadata: BackendMetadata { get }
}

// MARK: - Default Implementation

extension ExecutionBackend {
    /// Default step execution - backends can override for granular control
    func executeStep(
        _ step: WorkflowStep,
        context: inout WorkflowContext
    ) async throws -> StepResult {
        // Default: not implemented, backends should provide full workflow execution
        throw ExecutionBackendError.stepExecutionNotSupported
    }
}

// MARK: - Step Result

/// Result of executing a single workflow step
struct StepResult {
    /// The output text/data from the step
    let output: String

    /// Optional metadata about execution (tokens used, model, etc.)
    let metadata: [String: Any]?

    /// How long the step took to execute
    let duration: TimeInterval

    /// Error if step failed (nil if successful)
    let error: Error?

    /// Convenience initializer for successful results
    init(output: String, duration: TimeInterval = 0, metadata: [String: Any]? = nil) {
        self.output = output
        self.duration = duration
        self.metadata = metadata
        self.error = nil
    }

    /// Initializer for failed results
    init(error: Error, duration: TimeInterval = 0) {
        self.output = ""
        self.duration = duration
        self.metadata = nil
        self.error = error
    }
}

// MARK: - Backend Capabilities

/// Describes what a backend can and cannot do
struct BackendCapabilities {
    /// Which step types this backend can execute
    let supportedStepTypes: Set<WorkflowStep.StepType>

    /// Whether the backend supports streaming results
    let supportsStreaming: Bool

    /// Whether execution survives crashes/restarts (Temporal-style)
    let supportsDurableExecution: Bool

    /// Whether steps can run in parallel
    let supportsParallelSteps: Bool

    /// Whether the backend requires network connectivity
    let requiresNetwork: Bool

    /// Check if a step type is supported
    func supports(_ stepType: WorkflowStep.StepType) -> Bool {
        supportedStepTypes.contains(stepType)
    }

    /// All local step types (no network required)
    static let localStepTypes: Set<WorkflowStep.StepType> = [
        .transcribe, .shell, .clipboard, .saveFile, .transform,
        .conditional, .appleNotes, .appleReminders, .appleCalendar,
        .speak, .trigger, .intentExtract, .executeWorkflows
    ]

    /// Step types that typically require network
    static let networkStepTypes: Set<WorkflowStep.StepType> = [
        .llm, .webhook, .email, .notification, .iOSPush
    ]
}

// MARK: - Backend Metadata

/// Metadata about the backend (for UI display, logging, etc.)
struct BackendMetadata {
    /// Unique identifier (e.g., "local-swift", "vercel", "temporal")
    let id: String

    /// Human-readable name (e.g., "Local Swift", "Vercel Cloud")
    let displayName: String

    /// Description of what this backend does
    let description: String

    /// Version string (e.g., "1.0.0")
    let version: String

    /// Icon name (SF Symbol or custom)
    let icon: String?

    init(
        id: String,
        displayName: String,
        description: String,
        version: String = "1.0.0",
        icon: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.version = version
        self.icon = icon
    }
}

// MARK: - Execution Backend Error

enum ExecutionBackendError: LocalizedError {
    case stepExecutionNotSupported
    case stepTypeNotSupported(WorkflowStep.StepType)
    case backendNotAvailable(String)
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .stepExecutionNotSupported:
            return "This backend does not support individual step execution"
        case .stepTypeNotSupported(let type):
            return "Step type '\(type.rawValue)' is not supported by this backend"
        case .backendNotAvailable(let reason):
            return "Backend unavailable: \(reason)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}

// MARK: - Workflow Context Extension

extension WorkflowContext {
    /// Convert context to JSON for passing to remote backends
    func toJSON() -> [String: Any] {
        let json: [String: Any] = [
            "transcript": transcript,
            "title": title,
            "date": ISO8601DateFormatter().string(from: date),
            "outputs": outputs
        ]
        return json
    }

    /// Create context from JSON (for remote execution results)
    static func fromJSON(_ json: [String: Any], memo: MemoModel, date: Date) -> WorkflowContext {
        let transcript = json["transcript"] as? String ?? ""
        let title = json["title"] as? String ?? "Untitled"
        let outputs = json["outputs"] as? [String: String] ?? [:]

        var context = WorkflowContext(
            transcript: transcript,
            title: title,
            date: date,
            memo: memo
        )
        context.outputs = outputs
        return context
    }
}
