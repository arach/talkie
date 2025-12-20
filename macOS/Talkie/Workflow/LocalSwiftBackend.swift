//
//  LocalSwiftBackend.swift
//  Talkie macOS
//
//  Local Swift execution backend - wraps existing WorkflowExecutor
//  Provides in-process, no-network execution of all step types
//

import Foundation
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LocalSwiftBackend")

// MARK: - Local Swift Backend

/// Executes workflows in-process using Swift/macOS APIs
/// This is the default backend and wraps the existing WorkflowExecutor
/// to maintain backward compatibility while providing the new abstraction.
@MainActor
final class LocalSwiftBackend: ExecutionBackend {

    // MARK: - Properties

    private let executor: WorkflowExecutor
    private let coreDataContext: NSManagedObjectContext

    // MARK: - Initialization

    init(
        executor: WorkflowExecutor = .shared,
        coreDataContext: NSManagedObjectContext
    ) {
        self.executor = executor
        self.coreDataContext = coreDataContext
    }

    // MARK: - ExecutionBackend Protocol

    func execute(
        workflow: WorkflowDefinition,
        context: WorkflowContext
    ) async throws -> [String: String] {
        logger.info("🏃 LocalSwiftBackend executing workflow: \(workflow.name)")

        // Delegate to existing WorkflowExecutor
        // This keeps all your existing step implementations working!
        let outputs = try await executor.executeWorkflow(
            workflow,
            for: context.memo,
            context: context.coreDataContext
        )

        logger.info("✅ LocalSwiftBackend completed: \(outputs.count) outputs")
        return outputs
    }

    func executeStep(
        _ step: WorkflowStep,
        context: inout WorkflowContext
    ) async throws -> StepResult {
        logger.info("🔧 LocalSwiftBackend executing step: \(step.type.rawValue)")

        let startTime = Date()

        // Temporary: Execute just this step by creating a mini-workflow
        // In Phase 2, we can refactor WorkflowExecutor to expose executeStep directly
        let miniWorkflow = WorkflowDefinition(
            name: "Step Execution",
            description: "Single step execution",
            steps: [step]
        )

        let outputs = try await executor.executeWorkflow(
            miniWorkflow,
            for: context.memo,
            context: context.coreDataContext
        )

        let duration = Date().timeIntervalSince(startTime)
        let output = outputs[step.outputKey] ?? ""

        return StepResult(
            output: output,
            duration: duration,
            metadata: [
                "backend": "local-swift",
                "stepType": step.type.rawValue
            ]
        )
    }

    var capabilities: BackendCapabilities {
        BackendCapabilities(
            supportedStepTypes: Set(WorkflowStep.StepType.allCases), // All types!
            supportsStreaming: false,
            supportsDurableExecution: false,
            supportsParallelSteps: false,
            requiresNetwork: false // Pure local execution
        )
    }

    var metadata: BackendMetadata {
        BackendMetadata(
            id: "local-swift",
            displayName: "Local Swift",
            description: "In-process execution using native Swift and macOS APIs. Fast, private, and works offline.",
            version: "1.0.0",
            icon: "bolt.fill"
        )
    }

}
