//
//  WorkflowExecutor.swift
//  talkie
//
//  Executes workflow actions and saves results to Core Data
//

import Foundation
import CoreData
import AppKit
import UserNotifications
import os
import Observation
import CryptoKit
import TalkieKit

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "WorkflowExecutor")
private let workflowUILog = Log(.ui)
// MARK: - Workflow Execution Context

struct WorkflowContext {
    var transcript: String
    var title: String
    var date: Date
    var outputs: [String: String] = [:]

    /// Tracks output keys in insertion order (Dictionary doesn't guarantee order)
    var outputOrder: [String] = []

    /// The memo being processed
    let memo: MemoModel

    /// Filename-safe date formatter (2025-11-26)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Filename-safe datetime formatter (2025-11-26_15-30)
    private static let datetimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter
    }()

    func resolve(_ template: String) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{{TRANSCRIPT_JSON}}", with: jsonStringLiteral(transcript))
        result = result.replacingOccurrences(of: "{{TITLE_JSON}}", with: jsonStringLiteral(sanitizeForFilename(title)))
        result = result.replacingOccurrences(of: "{{TRANSCRIPT}}", with: transcript)
        result = result.replacingOccurrences(of: "{{TITLE}}", with: sanitizeForFilename(title))
        result = result.replacingOccurrences(of: "{{DATE}}", with: Self.dateFormatter.string(from: date))
        result = result.replacingOccurrences(of: "{{DATETIME}}", with: Self.datetimeFormatter.string(from: date))

        // Replace output keys
        for (key, value) in outputs {
            result = result.replacingOccurrences(of: "{{\(key)_JSON}}", with: jsonStringLiteral(value))
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        // Handle PREVIOUS_OUTPUT - use the last output based on insertion order
        if let lastKey = outputOrder.last, let lastOutput = outputs[lastKey] {
            result = result.replacingOccurrences(of: "{{PREVIOUS_OUTPUT_JSON}}", with: jsonStringLiteral(lastOutput))
            result = result.replacingOccurrences(of: "{{PREVIOUS_OUTPUT}}", with: lastOutput)
        }

        // Handle OUTPUT - same as PREVIOUS_OUTPUT for backward compatibility
        if let lastKey = outputOrder.last, let lastOutput = outputs[lastKey] {
            result = result.replacingOccurrences(of: "{{OUTPUT_JSON}}", with: jsonStringLiteral(lastOutput))
            result = result.replacingOccurrences(of: "{{OUTPUT}}", with: lastOutput)
        }

        return result
    }

    /// Encode a string as a JSON string literal for webhook body templates.
    private func jsonStringLiteral(_ input: String) -> String {
        guard let data = try? JSONEncoder().encode(input),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    /// Sanitize a string to be safe for use in filenames
    private func sanitizeForFilename(_ input: String) -> String {
        var result = input
        let invalidChars: [(String, String)] = [
            (":", "-"),
            ("/", "-"),
            ("\\", "-"),
            ("*", ""),
            ("?", ""),
            ("\"", "'"),
            ("<", ""),
            (">", ""),
            ("|", "-"),
            ("\n", " "),
            ("\r", ""),
        ]
        for (char, replacement) in invalidChars {
            result = result.replacingOccurrences(of: char, with: replacement)
        }
        return result
    }
}

// MARK: - Workflow Executor

@MainActor
@Observable
class WorkflowExecutor {
    static let shared = WorkflowExecutor()
    private nonisolated static let homeHistoryLimit = 3

    private let registry = LLMProviderRegistry.shared
    private let settings = SettingsManager.shared

    private(set) var homeRecentSuccessfulRuns: [WorkflowRunModel] = []
    private(set) var homeSuccessfulRunsTodayCount = 0

    private init() {}

    func refreshHomeHistory(limit: Int = WorkflowExecutor.homeHistoryLimit) async {
        do {
            let runs = try await LocalRepository().allWorkflowRuns()
            let successfulRuns = runs.filter { $0.status == .completed }
            let calendar = Calendar.current

            homeRecentSuccessfulRuns = Array(successfulRuns.prefix(limit))
            homeSuccessfulRunsTodayCount = successfulRuns.filter {
                calendar.isDateInToday($0.runDate)
            }.count
        } catch is CancellationError {
        } catch {
            workflowUILog.warning("Failed to refresh home workflow history", detail: error.localizedDescription)
            homeRecentSuccessfulRuns = []
            homeSuccessfulRunsTodayCount = 0
        }
    }

    private func applyHomeWorkflowRun(_ run: WorkflowRunModel, limit: Int = WorkflowExecutor.homeHistoryLimit) {
        guard run.status == .completed else { return }

        let calendar = Calendar.current
        let wasAlreadyCountedToday = homeRecentSuccessfulRuns.contains {
            $0.id == run.id && calendar.isDateInToday($0.runDate)
        }
        var updatedRuns = homeRecentSuccessfulRuns.filter { $0.id != run.id }
        updatedRuns.append(run)
        updatedRuns.sort { $0.runDate > $1.runDate }
        homeRecentSuccessfulRuns = Array(updatedRuns.prefix(limit))

        if calendar.isDateInToday(run.runDate), !wasAlreadyCountedToday {
            homeSuccessfulRunsTodayCount += 1
        }
    }

    private struct SidecarWorkflowContextPayload: Codable {
        let transcript: String
        let title: String
        let date: Date
        let outputs: [String: String]
        let outputOrder: [String]
    }

    private struct SidecarWorkflowRunOptions: Codable {
        let continueOnUnsupported: Bool
    }

    private struct SidecarWorkflowRunRequest: Codable {
        let memoId: UUID
        let workflow: WorkflowDefinition
        let context: SidecarWorkflowContextPayload
        let options: SidecarWorkflowRunOptions
    }

    private struct SidecarWorkflowRunEnvelope: Codable {
        let ok: Bool
        let result: SidecarWorkflowRunResult?
        let error: String?
        let details: SidecarWorkflowErrorDetails?
    }

    private struct SidecarWorkflowErrorDetails: Codable {
        let stepId: String?
        let stepType: String?
        let cause: SidecarWorkflowErrorCause?
        let status: Int?
    }

    private struct SidecarWorkflowErrorCause: Codable {
        let code: String?
        let path: String?
        let errno: Int?
    }

    private struct SidecarWorkflowRunResult: Codable {
        let outputs: [String: String]
        let outputOrder: [String]
        let trace: [SidecarWorkflowTrace]
        let halted: Bool
        let haltReason: String?
    }

    private struct SidecarWorkflowTrace: Codable {
        let stepId: String
        let type: String
        let outputKey: String
        let runner: String
        let status: String
        let durationMs: Double
        let reason: String?
        let output: String?
        let input: String?
    }

    // MARK: - Execute Legacy Action (for backward compatibility)
    func execute(
        action: WorkflowActionType,
        for memo: VoiceMemo,
        providerName: String? = nil,
        modelId: String? = nil,
        context: NSManagedObjectContext
    ) async throws {
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else {
            throw WorkflowError.noTranscript
        }

        // Get provider and model
        let provider: LLMProvider
        let model: String

        if let providerName = providerName,
           let selectedProvider = registry.provider(for: providerName),
           let modelId = modelId {
            provider = selectedProvider
            model = modelId
        } else if let resolved = await registry.resolveProviderAndModel() {
            // Use selected or first available provider with its default model
            provider = resolved.provider
            model = resolved.modelId
        } else {
            throw LLMError.providerNotAvailable("No LLM providers available. Please configure an API key in Settings.")
        }

        // Mark as processing
        setProcessingState(for: action, memo: memo, isProcessing: true)
        try? context.save()

        do {
            let prompt = action.systemPrompt.replacingOccurrences(of: "{{TRANSCRIPT}}", with: transcript)

            // Generate using provider
            let options = GenerationOptions(
                temperature: 0.7,
                topP: 0.9,
                maxTokens: 1024
            )

            let output = try await provider.generate(
                prompt: prompt,
                model: model,
                options: options
            )

            let result = WorkflowResult(
                actionType: action,
                output: output,
                model: .geminiFlash // Legacy field, keep for compatibility
            )

            // Save result to Core Data
            saveResult(result, to: memo, context: context)
            setProcessingState(for: action, memo: memo, isProcessing: false)
            try? context.save()

            logger.debug("✅ \(action.rawValue) completed successfully")
        } catch {
            // Clear processing state on error
            setProcessingState(for: action, memo: memo, isProcessing: false)
            try? context.save()
            throw error
        }
    }

    // MARK: - Execute Workflow Definition

    /// Execute workflow from Recording - converts to MemoModel for execution
    func executeWorkflow(
        _ workflow: WorkflowDefinition,
        for recording: TalkieObject
    ) async throws -> [String: String] {
        // Convert Recording to MemoModel for workflow execution
        let memo = recording.toMemoModel()
        return try await executeWorkflow(workflow, for: memo)
    }

    func retryWorkflowRun(_ run: WorkflowRunModel) async throws -> [String: String] {
        try await retryWorkflow(
            workflowId: run.workflowId,
            memoId: run.memoId,
            fallbackWorkflowName: run.workflowName
        )
    }

    func retryWorkflow(
        workflowId: UUID,
        memoId: UUID,
        fallbackWorkflowName: String? = nil
    ) async throws -> [String: String] {
        guard let workflow = WorkflowService.shared.workflow(byID: workflowId)?.definition else {
            throw WorkflowError.executionFailed("Workflow '\(fallbackWorkflowName ?? workflowId.uuidString)' is no longer available.")
        }

        let repository = LocalRepository()
        guard let memo = try await repository.fetchMemo(id: memoId)?.memo else {
            throw WorkflowError.executionFailed("The memo for workflow '\(workflow.name)' is no longer available.")
        }

        await SystemEventManager.shared.log(
            .workflow,
            "Retrying: \(workflow.name)",
            detail: "Memo: \(memo.title ?? "Untitled")"
        )

        return try await executeWorkflow(workflow, for: memo)
    }

    /// Execute workflow from MemoModel - pure LocalRepository, no Core Data
    func executeWorkflow(
        _ workflow: WorkflowDefinition,
        for memo: MemoModel
    ) async throws -> [String: String] {
        let startsWithTranscribe = workflow.steps.first?.type == .transcribe

        let transcript = memo.transcription ?? ""
        if !startsWithTranscribe && transcript.isEmpty {
            throw WorkflowError.noTranscript
        }

        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Executing workflow: \(workflow.name)"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }

        let workflowStartTime = Date()
        let runId = UUID()

        var workflowContext = WorkflowContext(
            transcript: transcript,
            title: memo.title ?? "Untitled",
            date: memo.createdAt,
            memo: memo
        )

        workflowContext.outputs["WORKFLOW_NAME"] = workflow.name
        workflowContext.outputOrder.append("WORKFLOW_NAME")

        await SystemEventManager.shared.log(.workflow, "Starting: \(workflow.name)", detail: "Memo: \(memo.displayTitle)")
        let pendingActionId = PendingActionsManager.shared.startAction(
            workflowId: workflow.id,
            workflowName: workflow.name,
            workflowIcon: workflow.icon,
            memoId: memo.id,
            memoTitle: memo.displayTitle,
            totalSteps: workflow.steps.filter { $0.isEnabled }.count
        )

        PendingActionsManager.shared.updateAction(
            id: pendingActionId,
            currentStep: "TalkieServer runtime",
            stepIndex: 0
        )

        let firstLLMConfig = workflow.steps.compactMap { step -> LLMStepConfig? in
            if case .llm(let config) = step.config {
                return config
            }
            return nil
        }.first
        let usedProvider = firstLLMConfig?.provider?.displayName ?? (firstLLMConfig != nil ? "auto-route" : nil)
        let usedModel = firstLLMConfig?.modelId ?? (firstLLMConfig != nil ? "auto" : nil)

        do {
            let result = try await executeWorkflowViaSidecar(
                workflow: workflow,
                memo: memo,
                context: workflowContext
            )

            let stepExecutions = makeStepExecutions(from: result.trace, startedAt: workflowStartTime)
            let finalOutput = result.outputOrder
                .compactMap { key in result.outputs[key] }
                .joined(separator: "\n\n---\n\n")

            if result.halted {
                await SystemEventManager.shared.log(
                    .workflow,
                    "Stopped: \(workflow.name)",
                    detail: result.haltReason ?? "Execution halted"
                )
            } else {
                await SystemEventManager.shared.log(.workflow, "Completed: \(workflow.name)", detail: "\(stepExecutions.count) steps")
            }

            PendingActionsManager.shared.completeAction(id: pendingActionId)

            let workflowCompletedTime = Date()
            saveWorkflowRun(
                runId: runId,
                workflow: workflow,
                output: finalOutput,
                stepExecutions: stepExecutions,
                providerName: usedProvider,
                modelId: usedModel,
                memo: memo,
                startedAt: workflowStartTime,
                completedAt: workflowCompletedTime,
                backendId: "talkie-sidecar"
            )

            return result.outputs
        } catch {
            PendingActionsManager.shared.failAction(id: pendingActionId, error: error.localizedDescription)

            await SystemEventManager.shared.log(
                .error,
                "Workflow failed: \(workflow.name)",
                detail: error.localizedDescription
            )

            let failedAt = Date()
            saveWorkflowRun(
                runId: runId,
                workflow: workflow,
                output: "",
                stepExecutions: [],
                providerName: usedProvider,
                modelId: usedModel,
                memo: memo,
                startedAt: workflowStartTime,
                completedAt: failedAt,
                status: .failed,
                error: error,
                backendId: "talkie-sidecar"
            )

            throw error
        }
    }

    private func executeWorkflowViaSidecar(
        workflow: WorkflowDefinition,
        memo: MemoModel,
        context: WorkflowContext
    ) async throws -> SidecarWorkflowRunResult {
        let bridgeManager = BridgeManager.shared
        if bridgeManager.bridgeStatus != .running {
            await bridgeManager.checkStatusNow()
        }
        if bridgeManager.bridgeStatus != .running {
            await bridgeManager.startBridge()
            await bridgeManager.checkStatusNow()
        }

        guard bridgeManager.bridgeStatus == .running else {
            throw WorkflowError.executionFailed("TalkieServer workflow runtime is unavailable.")
        }

        try await ensureLocalWorkflowHostRunning()

        let requestBody = SidecarWorkflowRunRequest(
            memoId: memo.id,
            workflow: workflow,
            context: SidecarWorkflowContextPayload(
                transcript: context.transcript,
                title: context.title,
                date: context.date,
                outputs: context.outputs,
                outputOrder: context.outputOrder
            ),
            options: SidecarWorkflowRunOptions(continueOnUnsupported: false)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(requestBody)

        let (data, response, url) = try await bridgeManager.performBridgeRequest(
            path: "/workflows/run",
            method: "POST",
            body: body,
            contentType: "application/json"
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkflowError.executionFailed("Workflow runtime returned an invalid response.")
        }

        let decoder = JSONDecoder()
        let envelope = try decoder.decode(SidecarWorkflowRunEnvelope.self, from: data)

        guard (200...299).contains(httpResponse.statusCode), envelope.ok, let result = envelope.result else {
            let message = workflowRuntimeErrorMessage(
                from: envelope,
                workflow: workflow,
                statusCode: httpResponse.statusCode,
                url: url
            )
            throw WorkflowError.executionFailed(message)
        }

        return result
    }

    private func ensureLocalWorkflowHostRunning() async throws {
        if TalkieServer.shared.isRunning {
            return
        }

        TalkieServer.shared.start()

        for _ in 0..<20 {
            if TalkieServer.shared.isRunning {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw WorkflowError.executionFailed("Local workflow host failed to start.")
    }

    private func workflowRuntimeErrorMessage(
        from envelope: SidecarWorkflowRunEnvelope,
        workflow: WorkflowDefinition,
        statusCode: Int,
        url: URL
    ) -> String {
        if envelope.details?.cause?.code == "ConnectionRefused",
           envelope.details?.cause?.path?.contains("127.0.0.1:8766") == true {
            let stepLabel = workflowStepLabel(for: envelope.details?.stepId, in: workflow)
            return "Local workflow host was unreachable while running \(stepLabel). Try rerunning the workflow or restarting Talkie."
        }

        if let stepId = envelope.details?.stepId {
            let stepLabel = workflowStepLabel(for: stepId, in: workflow)
            if let error = envelope.error, !error.isEmpty {
                return error.replacingOccurrences(of: "Step '\(stepId)'", with: stepLabel)
            }
        }

        if let error = envelope.error, !error.isEmpty {
            return error
        }

        return "Workflow runtime request failed (\(statusCode)) at \(url.absoluteString)"
    }

    private func workflowStepLabel(for stepId: String?, in workflow: WorkflowDefinition) -> String {
        guard let stepId,
              let uuid = UUID(uuidString: stepId),
              let step = workflow.steps.first(where: { $0.id == uuid }) else {
            return stepId.map { "step '\($0)'" } ?? "the workflow step"
        }

        if step.outputKey.isEmpty {
            return "the \(step.type.displayName) step"
        }

        return "the \(step.type.displayName) step '\(step.outputKey)'"
    }

    private func makeStepExecutions(
        from trace: [SidecarWorkflowTrace],
        startedAt workflowStartedAt: Date
    ) -> [StepExecution] {
        var cursor = workflowStartedAt
        var executions: [StepExecution] = []

        for (index, item) in trace.enumerated() where item.status == "completed" {
            let startedAt = cursor
            let completedAt = startedAt.addingTimeInterval(item.durationMs / 1000)
            cursor = completedAt

            let stepType = WorkflowStep.StepType(rawValue: item.type)
            executions.append(
                StepExecution(
                    stepNumber: index + 1,
                    stepType: item.type,
                    stepIcon: stepType?.icon ?? "gear",
                    input: item.input ?? "",
                    output: item.output ?? "",
                    outputKey: item.outputKey,
                    startedAt: startedAt,
                    completedAt: completedAt
                )
            )
        }

        return executions
    }

    // MARK: - Step Execution Record
    struct StepExecution: Codable {
        let stepNumber: Int
        let stepType: String
        let stepIcon: String
        let input: String
        let output: String
        let outputKey: String
        let startedAt: Date
        let completedAt: Date
        var durationMs: Int {
            Int(completedAt.timeIntervalSince(startedAt) * 1000)
        }
    }

    // MARK: - Save Workflow Run
    private func saveWorkflowRun(
        runId: UUID,
        workflow: WorkflowDefinition,
        output: String,
        stepExecutions: [StepExecution],
        providerName: String?,
        modelId: String?,
        memo: MemoModel,
        startedAt: Date,
        completedAt: Date,
        status: WorkflowRunModel.Status = .completed,
        error: Error? = nil,
        backendId: String = "local-swift"
    ) {
        let runDate = completedAt

        // Encode step executions as JSON
        var stepOutputsJSON: String? = nil
        if let jsonData = try? JSONEncoder().encode(stepExecutions),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            stepOutputsJSON = jsonString
        }

        // Save to LocalRepository (source of truth)
        logger.info("💾 Saving workflow run to LocalRepository: \(workflow.name)")
        Task {
            do {
                let repository = LocalRepository()

                // Calculate duration
                let durationMs = Int(completedAt.timeIntervalSince(startedAt) * 1000)

                // Encode outputs as JSON
                let finalOutputsJSON: String?
                if let jsonData = try? JSONEncoder().encode(["final": output]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    finalOutputsJSON = jsonString
                } else {
                    finalOutputsJSON = nil
                }

                // 1. Create workflow run
                let workflowRun = WorkflowRunModel(
                    id: runId,
                    memoId: memo.id,
                    workflowId: workflow.id,
                    workflowName: workflow.name,
                    workflowIcon: workflow.icon,
                    status: status,
                    createdAt: startedAt,
                    updatedAt: completedAt,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    runDate: runDate,
                    inputTranscript: memo.transcription,
                    inputTitle: memo.title,
                    inputDate: memo.createdAt,
                    output: output,
                    finalOutputs: finalOutputsJSON,
                    errorMessage: error?.localizedDescription,
                    errorStack: error.map { String(describing: $0) },
                    durationMs: durationMs,
                    stepCount: stepExecutions.count,
                    triggerSource: .manual,
                    modelId: modelId,
                    providerName: providerName,
                    stepOutputsJSON: stepOutputsJSON,
                    backendId: backendId,
                    workflowVersion: 1
                )
                try await repository.saveWorkflowRun(workflowRun)
                logger.info("✅ [Event Sourcing] Saved workflow run")
                applyHomeWorkflowRun(workflowRun)

                // 2. Create workflow steps
                var eventSequence = 0
                for stepExecution in stepExecutions {
                    let stepModel = WorkflowStepModel(
                        id: UUID(),
                        runId: runId,
                        stepNumber: stepExecution.stepNumber,
                        stepType: stepExecution.stepType,
                        stepConfig: "{}",
                        outputKey: stepExecution.outputKey,
                        status: .completed,
                        createdAt: stepExecution.startedAt,
                        startedAt: stepExecution.startedAt,
                        completedAt: stepExecution.completedAt,
                        inputSnapshot: String(stepExecution.input.prefix(1000)),
                        outputValue: String(stepExecution.output.prefix(1000)),
                        durationMs: stepExecution.durationMs,
                        retryCount: 0,
                        backendId: backendId
                    )
                    try await repository.saveWorkflowStep(stepModel)
                }
                logger.info("✅ [Event Sourcing] Saved \(stepExecutions.count) workflow steps")

                // 3. Create workflow events
                // Run created event
                let runCreatedEvent = WorkflowEventModel.runCreated(
                    runId: runId,
                    workflowName: workflow.name,
                    triggerSource: "manual"
                )
                try await repository.saveWorkflowEvent(runCreatedEvent)
                eventSequence += 1

                // Run started event
                var runStartedEvent = WorkflowEventModel.runStarted(runId: runId)
                runStartedEvent.createdAt = startedAt
                try await repository.saveWorkflowEvent(runStartedEvent)
                eventSequence += 1

                // Step completed events
                for stepExecution in stepExecutions {
                    let stepCompletedEvent = WorkflowEventModel.stepCompleted(
                        runId: runId,
                        stepId: UUID(),
                        stepNumber: stepExecution.stepNumber,
                        stepType: stepExecution.stepType,
                        outputKey: stepExecution.outputKey,
                        outputLength: stepExecution.output.count,
                        duration: stepExecution.completedAt.timeIntervalSince(stepExecution.startedAt)
                    )
                    try await repository.saveWorkflowEvent(stepCompletedEvent)
                    eventSequence += 1
                }

                // Run completed or failed event
                if status == .completed {
                    let runCompletedEvent = WorkflowEventModel.runCompleted(
                        runId: runId,
                        outputCount: stepExecutions.count,
                        duration: completedAt.timeIntervalSince(startedAt)
                    )
                    try await repository.saveWorkflowEvent(runCompletedEvent)
                } else if status == .failed, let error = error {
                    let runFailedEvent = WorkflowEventModel.runFailed(
                        runId: runId,
                        error: error,
                        failedStepNumber: stepExecutions.last?.stepNumber
                    )
                    try await repository.saveWorkflowEvent(runFailedEvent)
                }

                logger.info("✅ Saved \(eventSequence + 1) workflow events")
                logger.info("💾 Complete workflow run saved to LocalRepository")

                // Sync to Core Data for CloudKit
                await MainActor.run {
                    syncWorkflowRunToCoreData(
                        runId: runId,
                        workflow: workflow,
                        output: output,
                        providerName: providerName,
                        modelId: modelId,
                        memoId: memo.id,
                        runDate: runDate,
                        stepOutputsJSON: stepOutputsJSON,
                        backendId: backendId
                    )
                }
            } catch {
                logger.error("❌ Failed to save to LocalRepository: \(error.localizedDescription)")
            }
        }
    }

    /// Sync workflow run to Core Data for CloudKit sync
    @MainActor
    private func syncWorkflowRunToCoreData(
        runId: UUID,
        workflow: WorkflowDefinition,
        output: String,
        providerName: String?,
        modelId: String?,
        memoId: UUID,
        runDate: Date,
        stepOutputsJSON: String?,
        backendId: String
    ) {
        // NOTE: Core Data sync removed - workflow runs now stored in GRDB only
        // Future: Could sync workflow runs via API instead of CloudKit
        logger.info("📝 Saving workflow run locally (CloudKit sync disabled): \(workflow.name)")

        // Save to GRDB via LocalRepository
        Task {
            do {
                let repo = LocalRepository()
                let runModel = WorkflowRunModel(
                    id: runId,
                    memoId: memoId,
                    workflowId: workflow.id,
                    workflowName: workflow.name,
                    workflowIcon: workflow.icon,
                    status: .completed,
                    runDate: runDate,
                    output: output,
                    modelId: modelId,
                    providerName: providerName,
                    stepOutputsJSON: stepOutputsJSON
                )
                try await repo.saveWorkflowRun(runModel)
                logger.info("✅ Saved workflow run to GRDB: \(workflow.name)")
            } catch {
                logger.error("❌ Failed to save workflow run: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Execute Single Step
    func executeHostedStep(
        _ step: WorkflowStep,
        context: inout WorkflowContext
    ) async throws -> String {
        try await executeStep(step, context: &context)
    }

    private func executeStep(
        _ step: WorkflowStep,
        context: inout WorkflowContext
    ) async throws -> String {
        switch step.config {
        case .llm(let config):
            return try await executeLLMStep(config, context: context)

        case .shell(let config):
            return try await executeShellStep(config, context: context)

        case .webhook(let config):
            return try await executeWebhookStep(config, context: context)

        case .email(let config):
            return try await executeEmailStep(config, context: context)

        case .notification(let config):
            return try await executeNotificationStep(config, context: context)

        case .iOSPush(let config):
            return try await executeiOSPushStep(config, context: context)

        case .appleNotes(let config):
            return try await executeAppleNotesStep(config, context: context)

        case .appleReminders(let config):
            return try await executeAppleRemindersStep(config, context: context)

        case .appleCalendar(let config):
            return try await executeAppleCalendarStep(config, context: context)

        case .clipboard(let config):
            return executeClipboardStep(config, context: context)

        case .saveFile(let config):
            return try executeSaveFileStep(config, context: context)

        case .conditional(let config):
            return evaluateCondition(context.resolve(config.condition)) ? "true" : "false"

        case .transform(let config):
            return try executeTransformStep(config, context: context)

        case .transcribe(let config):
            return try await executeTranscribeStep(config, context: context)

        case .speak(let config):
            return try await executeSpeakStep(config, context: context)

        case .trigger(let config):
            return try executeTriggerStep(config, context: context)

        case .intentExtract(let config):
            return try await executeIntentExtractStep(config, context: context)

        case .executeWorkflows(let config):
            return try await executeWorkflowsStep(config, context: context)

        case .cloudUpload(let config):
            return try await executeCloudUploadStep(config, context: context)
        }
    }

    // MARK: - LLM Step Execution
    private func executeLLMStep(_ config: LLMStepConfig, context: WorkflowContext) async throws -> String {
        // Build set of available WorkflowLLMProviders from registry
        let availableProviders = await buildAvailableProviders()

        // Resolve provider and model using auto-routing or explicit config
        guard let resolved = config.resolveProviderAndModel(
            availableProviders: availableProviders,
            globalTier: settings.llmCostTier
        ) else {
            throw WorkflowError.executionFailed("No LLM provider available. Please configure API keys in Settings.")
        }

        // Get the actual LLMProvider instance
        guard let provider = registry.provider(for: resolved.provider.registryId) else {
            throw WorkflowError.executionFailed("Provider '\(resolved.provider.displayName)' not found in registry")
        }

        logger.info("🤖 LLM Step: Using \(resolved.provider.displayName) / \(resolved.modelId) (tier: \(config.costTier?.rawValue ?? self.settings.llmCostTier.rawValue))")
        await SystemEventManager.shared.log(.workflow, "LLM generating", detail: "\(resolved.provider.displayName) / \(resolved.modelId)")
        let resolvedPrompt = context.resolve(config.prompt)
        let systemPrompt = config.systemPrompt.map { context.resolve($0) }

        // Pass system prompt properly via GenerationOptions (providers handle API-specific formatting)
        let options = GenerationOptions(
            temperature: config.temperature,
            topP: config.topP,
            maxTokens: config.maxTokens,
            systemPrompt: systemPrompt
        )

        logger.info("🤖 LLM: Starting generation (prompt: \(resolvedPrompt.prefix(100))..., hasSystemPrompt: \(systemPrompt != nil))")
        do {
            let result = try await provider.generate(
                prompt: resolvedPrompt,
                model: resolved.modelId,
                options: options
            )

            logger.info("🤖 LLM: Generation complete (\(result.count) chars)")
            await SystemEventManager.shared.log(.workflow, "LLM complete", detail: "\(result.count) chars")
            return result

        } catch {
            logger.error("🤖 LLM: Generation failed:")
            logger.error("   Provider: \(resolved.provider.displayName)")
            logger.error("   Model: \(resolved.modelId)")
            logger.error("   Error type: \(type(of: error))")
            logger.error("   Description: \(error.localizedDescription)")
            logger.error("   Full error: \(String(describing: error))")

            await SystemEventManager.shared.log(
                .error,
                "LLM failed: \(resolved.provider.displayName)/\(resolved.modelId)",
                detail: "[\(type(of: error))] \(error.localizedDescription)\n\nFull: \(String(describing: error))"
            )
            throw error
        }
    }

    /// Build set of WorkflowLLMProviders that have API keys configured
    private func buildAvailableProviders() async -> Set<WorkflowLLMProvider> {
        var available = Set<WorkflowLLMProvider>()

        for provider in registry.providers {
            if await provider.isAvailable {
                // Map registry provider ID to WorkflowLLMProvider enum
                if let workflowProvider = WorkflowLLMProvider(rawValue: provider.id) {
                    available.insert(workflowProvider)
                }
            }
        }

        return available
    }

    // MARK: - Shell Step Execution
    private func executeShellStep(_ config: ShellStepConfig, context: WorkflowContext) async throws -> String {
        // Validate config (executable allowlist, etc.)
        let validation = config.validate()
        if !validation.valid {
            let errorMessage = validation.errors.joined(separator: "; ")
            logger.debug("🚫 Shell step blocked: \(errorMessage)")
            throw WorkflowError.executionFailed("Security validation failed: \(errorMessage)")
        }

        // Verify executable exists
        guard FileManager.default.fileExists(atPath: config.executable) else {
            throw WorkflowError.executionFailed("Executable not found: \(config.executable)")
        }

        logger.debug("🖥️ Executing shell command: \(config.executable)")
        // Resolve template variables and sanitize dynamic content
        var resolvedArgs = config.arguments.map { arg in
            let resolved = context.resolve(arg)
            let sanitized = ShellStepConfig.sanitizeContent(resolved)

            // Check for injection attempts (log but don't block)
            let warnings = ShellStepConfig.detectInjectionAttempts(sanitized)
            for warning in warnings {
                logger.debug("⚠️ Injection warning in argument: \(warning)")
            }

            return sanitized
        }

        // If promptTemplate is provided, resolve it and add as -p argument
        if let promptTemplate = config.promptTemplate, !promptTemplate.isEmpty {
            let resolvedPrompt = context.resolve(promptTemplate)
            let sanitizedPrompt = ShellStepConfig.sanitizeContent(resolvedPrompt)

            // Check for injection attempts
            let warnings = ShellStepConfig.detectInjectionAttempts(sanitizedPrompt)
            for warning in warnings {
                logger.debug("⚠️ Injection warning in prompt template: \(warning)")
            }

            // Add -p flag and the prompt as arguments
            resolvedArgs.append("-p")
            resolvedArgs.append(sanitizedPrompt)
            logger.debug("Prompt template resolved (\(sanitizedPrompt.count) chars)")
        }

        // Resolve stdin if provided
        let resolvedStdin: String? = config.stdin.map { stdinTemplate in
            let resolved = context.resolve(stdinTemplate)
            let sanitized = ShellStepConfig.sanitizeContent(resolved)

            // Check for injection attempts
            let warnings = ShellStepConfig.detectInjectionAttempts(sanitized)
            for warning in warnings {
                logger.debug("⚠️ Injection warning in stdin: \(warning)")
            }

            return sanitized
        }

        // Build the command string for display/logging
        let commandDisplay = ([config.executable] + resolvedArgs)
            .map { arg in
                // Quote arguments with spaces for display
                arg.contains(" ") ? "\"\(arg)\"" : arg
            }
            .joined(separator: " ")
        logger.debug("Command: \(commandDisplay)")
        if let stdin = resolvedStdin {
            logger.debug("Stdin length: \(stdin.count) chars")
        }

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.executable)
        process.arguments = resolvedArgs

        // Set working directory if specified
        if let workDir = config.workingDirectory {
            let resolvedWorkDir = context.resolve(workDir)
            process.currentDirectoryURL = URL(fileURLWithPath: resolvedWorkDir)
        }

        // Set environment variables
        var env = ProcessInfo.processInfo.environment
        for (key, value) in config.environment {
            env[key] = context.resolve(value)
        }

        // Enrich PATH so child processes (claude, node, bun) are discoverable
        env["PATH"] = ExecutableResolver.enrichedPATH(from: env["PATH"])

        // Remove potentially dangerous environment variables
        env.removeValue(forKey: "LD_PRELOAD")
        env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
        process.environment = env

        // Set up pipes for stdout/stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set up stdin if needed
        if let stdinData = resolvedStdin?.data(using: .utf8) {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe

            // Write to stdin in background to avoid blocking
            Task.detached {
                try? stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
                try? stdinPipe.fileHandleForWriting.close()
            }
        }

        // Execute with timeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            // Timeout task
            group.addTask {
                try await Task.sleep(for: .seconds(config.timeout))
                throw WorkflowError.executionFailed("Command timed out after \(config.timeout) seconds")
            }

            // Execution task
            group.addTask {
                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    // Check exit status
                    if process.terminationStatus != 0 {
                        logger.debug("⚠️ Command exited with status: \(process.terminationStatus)")
                        if !stderr.isEmpty {
                            logger.debug("Stderr: \(stderr.prefix(500))")
                        }
                        // Still return output but note the error
                        if config.captureStderr && !stderr.isEmpty {
                            return "Exit code: \(process.terminationStatus)\n\nStdout:\n\(stdout)\n\nStderr:\n\(stderr)"
                        }
                    }

                    // Combine output based on config
                    if config.captureStderr && !stderr.isEmpty {
                        return stdout + "\n" + stderr
                    }

                    return stdout.trimmingCharacters(in: .whitespacesAndNewlines)

                } catch {
                    throw WorkflowError.executionFailed("Failed to execute command: \(error.localizedDescription)")
                }
            }

            // Return first result (either completion or timeout)
            if let result = try await group.next() {
                group.cancelAll()
                process.terminate() // Kill process if still running
                return result
            }

            throw WorkflowError.executionFailed("Unexpected shell execution error")
        }
    }

    // MARK: - Webhook Step Execution
    private func executeWebhookStep(_ config: WebhookStepConfig, context: WorkflowContext) async throws -> String {
        // Resolve URL (may contain credential placeholders)
        var resolvedUrl = try resolveUserDefaultsPlaceholders(in: context.resolve(config.url))

        // Handle credential placeholder in URL (e.g., for Telegram bot token)
        if let credentialMatch = resolvedUrl.range(of: #"\{\{CREDENTIAL:([A-F0-9-]+)\}\}"#, options: .regularExpression) {
            let placeholder = String(resolvedUrl[credentialMatch])
            if let uuidString = placeholder.components(separatedBy: ":").last?.dropLast(2),
               let credentialId = UUID(uuidString: String(uuidString)) {
                let secret = try await CredentialStore.shared.getSecret(id: credentialId) ?? ""
                resolvedUrl = resolvedUrl.replacingOccurrences(of: placeholder, with: secret)
            }
        }

        guard let url = URL(string: resolvedUrl) else {
            throw WorkflowError.executionFailed("Invalid webhook URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = config.method.rawValue

        // Add headers
        for (key, value) in config.headers {
            request.setValue(try resolveUserDefaultsPlaceholders(in: context.resolve(value)), forHTTPHeaderField: key)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication if configured
        if let auth = config.auth {
            try await applyWebhookAuth(auth, to: &request)
        }

        // Build body
        var body: [String: Any] = [:]

        if config.includeTranscript {
            body["transcript"] = context.transcript
        }

        if config.includeMetadata {
            body["title"] = context.title
            body["date"] = context.date.iso8601
        }

        // Add previous outputs
        body["outputs"] = context.outputs

        // Custom body template if provided
        if let template = config.bodyTemplate {
            let resolved = try resolveUserDefaultsPlaceholders(in: context.resolve(template))
            if let data = resolved.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                body.merge(json) { _, new in new }
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WorkflowError.executionFailed("Webhook request failed with status \(statusCode)")
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Resolve `{{USERDEFAULTS:KeyName}}` placeholders in skill-backed webhook configs.
    /// This keeps starter `.skill.md` files bundle-safe while allowing Phase 1 secrets
    /// to live in local defaults, e.g. `SkillsSlackWebhookURL`.
    private func resolveUserDefaultsPlaceholders(in value: String) throws -> String {
        let pattern = #"\{\{USERDEFAULTS:([A-Za-z0-9_.-]+)\}\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsValue = value as NSString
        let matches = regex.matches(
            in: value,
            range: NSRange(location: 0, length: nsValue.length)
        )

        guard !matches.isEmpty else { return value }

        var resolved = value
        for match in matches.reversed() {
            let placeholder = nsValue.substring(with: match.range(at: 0))
            let key = nsValue.substring(with: match.range(at: 1))
            let configuredValue = UserDefaults.standard
                .string(forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let configuredValue, !configuredValue.isEmpty else {
                throw WorkflowError.executionFailed(
                    "Missing webhook URL. Set UserDefaults key '\(key)' before running this skill."
                )
            }

            resolved = resolved.replacingOccurrences(of: placeholder, with: configuredValue)
        }

        return resolved
    }

    /// Apply authentication to a webhook request
    private func applyWebhookAuth(_ auth: WebhookAuth, to request: inout URLRequest) async throws {
        let secret = try await CredentialStore.shared.getSecret(id: auth.credentialId, for: request)

        switch auth {
        case .bearer:
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        case .apiKey(let header, _):
            request.setValue(secret, forHTTPHeaderField: header)
        }
    }

    // MARK: - Cloud Upload Step Execution

    private func executeCloudUploadStep(_ config: CloudUploadStepConfig, context: WorkflowContext) async throws -> String {
        // Get the audio file path from the memo
        guard let audioFilePath = context.memo.audioFilePath else {
            throw WorkflowError.executionFailed("No audio file for memo")
        }

        let audioUrl = AudioStorage.url(for: audioFilePath)
        let audioData = try Data(contentsOf: audioUrl)

        // Resolve path template
        let resolvedPath = context.resolve(config.pathTemplate)

        // Build the upload URL
        let uploadUrl: URL
        switch config.provider {
        case .r2:
            guard let endpoint = config.endpoint else {
                throw WorkflowError.executionFailed("R2 requires an endpoint")
            }
            uploadUrl = URL(string: "\(endpoint)/\(config.bucket)/\(resolvedPath)")!
        case .s3:
            let endpoint = config.endpoint ?? "https://s3.\(config.region ?? "us-east-1").amazonaws.com"
            uploadUrl = URL(string: "\(endpoint)/\(config.bucket)/\(resolvedPath)")!
        }

        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "PUT"
        request.httpBody = audioData
        request.setValue(config.contentType, forHTTPHeaderField: "Content-Type")

        // Sign request if we have credentials
        if let credentialId = config.credentialId {
            request = try await signS3Request(request, credentialId: credentialId, region: config.region ?? "auto")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WorkflowError.executionFailed("Cloud upload failed with status \(statusCode)")
        }

        return uploadUrl.absoluteString
    }

    /// Sign an S3-compatible request using AWS Signature V4
    private func signS3Request(_ request: URLRequest, credentialId: UUID, region: String) async throws -> URLRequest {
        // Get credential
        guard let credential = await CredentialStore.shared.getCredential(id: credentialId),
              case .awsSigningKey(let accessKeyId) = credential.type,
              let secretKey = await CredentialStore.shared.getSecret(id: credentialId) else {
            throw WorkflowError.executionFailed("Cloud storage credentials not found")
        }

        var signedRequest = request

        // AWS Signature V4 signing
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: date)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)

        signedRequest.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        signedRequest.setValue(request.url?.host ?? "", forHTTPHeaderField: "Host")

        // Calculate content hash
        let payloadHash = sha256Hash(request.httpBody ?? Data())
        signedRequest.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        // Create canonical request
        let method = request.httpMethod ?? "PUT"
        let canonicalUri = request.url?.path ?? "/"
        let canonicalQueryString = request.url?.query ?? ""

        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "host:\(request.url?.host ?? "")",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)"
        ].joined(separator: "\n") + "\n"

        let canonicalRequest = [
            method,
            canonicalUri,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        // Create string to sign
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            sha256Hash(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        // Calculate signature
        let kDate = hmacSHA256(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data("s3".utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()

        // Create authorization header
        let authorization = "\(algorithm) Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        signedRequest.setValue(authorization, forHTTPHeaderField: "Authorization")

        return signedRequest
    }

    private func sha256Hash(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(signature)
    }

    // MARK: - Email Step Execution
    private func executeEmailStep(_ config: EmailStepConfig, context: WorkflowContext) async throws -> String {
        let to = context.resolve(config.to)
        let subject = context.resolve(config.subject)
        let body = context.resolve(config.body)

        // Use mailto: URL scheme to open default mail app
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        if let cc = config.cc {
            components.queryItems?.append(URLQueryItem(name: "cc", value: context.resolve(cc)))
        }

        if let bcc = config.bcc {
            components.queryItems?.append(URLQueryItem(name: "bcc", value: context.resolve(bcc)))
        }

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }

        return "Email draft opened"
    }

    // MARK: - Notification Step Execution
    private func executeNotificationStep(_ config: NotificationStepConfig, context: WorkflowContext) async throws -> String {
        let title = context.resolve(config.title)
        let body = context.resolve(config.body)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if config.sound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        try await UNUserNotificationCenter.current().add(request)

        return "Notification sent"
    }

    // MARK: - iOS Push Notification Step Execution
    /// Sends a push notification to the iOS app via CloudKit
    /// Creates a PushNotification record that iOS subscribes to via CKQuerySubscription
    private func executeiOSPushStep(
        _ config: iOSPushStepConfig,
        context: WorkflowContext
    ) async throws -> String {
        let memo = context.memo

        // Resolve template variables, including workflow name
        var resolvedTitle = context.resolve(config.title)
        var resolvedBody = context.resolve(config.body)

        // Handle {{WORKFLOW_NAME}} separately since it's not in the standard context
        // The workflow name will be set by the parent execution if available
        if let workflowName = context.outputs["WORKFLOW_NAME"] {
            resolvedTitle = resolvedTitle.replacingOccurrences(of: "{{WORKFLOW_NAME}}", with: workflowName)
            resolvedBody = resolvedBody.replacingOccurrences(of: "{{WORKFLOW_NAME}}", with: workflowName)
        }

        logger.debug("📱 [iOS Push] Creating push notification record...")
        logger.debug("📱 [iOS Push]   Title: \(resolvedTitle)")
        logger.debug("📱 [iOS Push]   Body: \(resolvedBody)")
        logger.debug("📱 [iOS Push]   Memo: \(memo.displayTitle) (ID: \(memo.id.uuidString.prefix(8))...)")
        logger.debug("📱 [iOS Push]   Sound: \(config.sound ? "enabled" : "disabled")")

        // NOTE: Core Data removed from main app - iOS push notifications disabled
        // Future: Send via TalkieGateway API or through TalkieSync XPC
        logger.warning("📱 [iOS Push] ⚠️ Push notifications temporarily disabled - Core Data moved to TalkieSync")
        logger.info("📱 [iOS Push]   Would send: '\(resolvedTitle)' - '\(resolvedBody.prefix(50))...'")

        // TODO: Implement push via TalkieGateway API
        return "Push notification logged (API integration pending)"
    }

    // MARK: - Apple Notes Step Execution
    private func executeAppleNotesStep(_ config: AppleNotesStepConfig, context: WorkflowContext) async throws -> String {
        _ = config
        _ = context
        throw WorkflowError.executionFailed(
            "Apple Notes actions have been removed from Workflow Runner. Remove this step or replace it with another supported action."
        )
    }

    // MARK: - Apple Reminders Step Execution
    private func executeAppleRemindersStep(_ config: AppleRemindersStepConfig, context: WorkflowContext) async throws -> String {
        let title = context.resolve(config.title)
        let notes = config.notes.map { context.resolve($0) }

        // Helper for AppleScript escaping
        func escapeForAppleScript(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }

        // Build AppleScript
        let escapedTitle = escapeForAppleScript(title)
        var properties = ["name:\"\(escapedTitle)\""]

        if let notes = notes {
            properties.append("body:\"\(escapeForAppleScript(notes))\"")
        }

        let listClause = config.listName.map { "of list \"\(escapeForAppleScript($0))\"" } ?? ""

        let script = """
        tell application "Reminders"
            make new reminder \(listClause) with properties {\(properties.joined(separator: ", "))}
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                throw WorkflowError.executionFailed("AppleScript error: \(error)")
            }
        }

        return "Reminder created: \(title)"
    }

    // MARK: - Apple Calendar Step Execution
    private func executeAppleCalendarStep(_ config: AppleCalendarStepConfig, context: WorkflowContext) async throws -> String {
        _ = config
        _ = context
        throw WorkflowError.executionFailed(
            "Calendar actions have been removed from Workflow Runner. Remove this step or replace it with another supported action."
        )
    }

    // MARK: - Clipboard Step Execution
    private func executeClipboardStep(_ config: ClipboardStepConfig, context: WorkflowContext) -> String {
        let content = context.resolve(config.content)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        return "Copied to clipboard"
    }

    // MARK: - Save File Step Execution
    private func executeSaveFileStep(_ config: SaveFileStepConfig, context: WorkflowContext) throws -> String {
        var resolvedFilename = context.resolve(config.filename)
        let content = context.resolve(config.content)

        logger.debug("📁 Save File Step:")
        logger.debug("Config directory: \(config.directory ?? "nil")")
        logger.debug("Config filename: \(config.filename)")
        logger.debug("Resolved filename: \(resolvedFilename)")
        var directory: URL

        // Check if filename contains an @alias (e.g., "@Obsidian/notes.md")
        if resolvedFilename.hasPrefix("@") {
            // Extract alias and path components
            let aliasResolved = SaveFileStepConfig.resolvePathAlias(resolvedFilename)
            logger.debug("Filename contains @alias, resolved to: \(aliasResolved)")
            // Split into directory and filename
            let url = URL(fileURLWithPath: aliasResolved)
            directory = url.deletingLastPathComponent()
            resolvedFilename = url.lastPathComponent
            logger.debug("Split into dir: \(directory.path), file: \(resolvedFilename)")
        } else if let customDir = config.directory, !customDir.isEmpty {
            // Resolve template variables first, then resolve @aliases
            let resolvedDir = context.resolve(customDir)
            let aliasResolved = SaveFileStepConfig.resolvePathAlias(resolvedDir)
            logger.debug("Resolved dir: \(resolvedDir)")
            logger.debug("After alias resolution: \(aliasResolved)")
            directory = URL(fileURLWithPath: aliasResolved)
        } else {
            // Use the default output directory from settings
            logger.debug("Using default directory: \(SaveFileStepConfig.defaultOutputDirectory)")
            directory = URL(fileURLWithPath: SaveFileStepConfig.defaultOutputDirectory)
        }

        logger.debug("Known aliases: \(SaveFileStepConfig.pathAliases)")
        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.debug("Created directory: \(directory.path)")
        }

        let fileURL = directory.appendingPathComponent(resolvedFilename)

        if config.appendIfExists && FileManager.default.fileExists(atPath: fileURL.path) {
            let existingContent = try String(contentsOf: fileURL, encoding: .utf8)
            try (existingContent + "\n" + content).write(to: fileURL, atomically: true, encoding: .utf8)
            logger.debug("📁 Appended to file: \(fileURL.path)")
        } else {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.debug("📁 Saved file: \(fileURL.path)")
        }

        return "Saved to: \(fileURL.path)"
    }

    // MARK: - Transform Step Execution
    private func executeTransformStep(_ config: TransformStepConfig, context: WorkflowContext) throws -> String {
        let input = Array(context.outputs.values).last ?? context.transcript

        switch config.operation {
        case .extractJSON:
            // Try to extract JSON from the input
            if let range = input.range(of: "\\[.*\\]", options: String.CompareOptions.regularExpression),
               let data = String(input[range]).data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return String(input[range])
            }
            if let range = input.range(of: "\\{.*\\}", options: String.CompareOptions.regularExpression),
               let data = String(input[range]).data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return String(input[range])
            }
            return input

        case .extractList:
            // Convert text to bullet list
            let lines = input.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                .filter { !$0.isEmpty }
            return lines.map { "• \($0)" }.joined(separator: "\n")
        case .formatMarkdown:
            // Basic markdown formatting (already in markdown usually)
            return input

        case .summarize:
            // Truncate to specified length
            let maxLength = Int(config.parameters["maxLength"] ?? "500") ?? 500
            if input.count > maxLength {
                return String(input.prefix(maxLength)) + "..."
            }
            return input

        case .regex:
            guard let pattern = config.parameters["pattern"] else {
                return input
            }
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               let range = Range(match.range, in: input) {
                return String(input[range])
            }
            return input

        case .template:
            guard let template = config.parameters["template"] else {
                return input
            }
            return context.resolve(template)
        }
    }

    // MARK: - Transcribe Step Execution
    private func executeTranscribeStep(_ config: TranscribeStepConfig, context: WorkflowContext) async throws -> String {
        let memo = context.memo
        logger.info("Executing transcribe step: tier=\(config.qualityTier.rawValue), primary=\(config.primaryModel), fallback=\(config.effectiveFallbackModel ?? "none")")

        // Check if memo already has a transcript and we're not overwriting
        if let existingTranscript = memo.transcription, !existingTranscript.isEmpty, !config.overwriteExisting {
            logger.info("Memo already has transcript, skipping transcription (overwriteExisting=false)")
            return existingTranscript
        }

        // Load audio data from local file path
        guard let audioFilePath = memo.audioFilePath else {
            throw WorkflowError.executionFailed("No audio file path available for transcription")
        }

        let audioURL = AudioStorage.url(for: audioFilePath)
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw WorkflowError.executionFailed("Could not load audio from: \(audioFilePath)")
        }

        logger.info("Transcribing audio (\(audioData.count) bytes) from \(audioFilePath) with \(config.qualityTier.displayName) quality")

        // Try primary model first
        do {
            return try await transcribeWithModel(
                modelId: config.primaryModel,
                audioData: audioData,
                memoId: memo.id,
                config: config,
                isPrimary: true
            )
        } catch {
            logger.warning("Primary transcription failed: \(error.localizedDescription)")

            // Check fallback strategy
            guard config.fallbackStrategy != .none,
                  let fallbackModel = config.effectiveFallbackModel else {
                logger.error("No fallback configured, propagating error")
                throw error
            }

            // For onTimeout strategy, only fallback if it was a timeout error
            if config.fallbackStrategy == .onTimeout {
                let isTimeout = error.localizedDescription.lowercased().contains("timeout") ||
                               error.localizedDescription.lowercased().contains("timed out")
                guard isTimeout else {
                    logger.info("Error was not a timeout, not using fallback (strategy=onTimeout)")
                    throw error
                }
            }

            logger.info("Using fallback model: \(fallbackModel)")
            await SystemEventManager.shared.log(.workflow, "Falling back", detail: "Using \(fallbackModel)")

            // Try fallback model
            return try await transcribeWithModel(
                modelId: fallbackModel,
                audioData: audioData,
                memoId: memo.id,
                config: config,
                isPrimary: false
            )
        }
    }

    /// Transcribe using a specific model ID
    private func transcribeWithModel(modelId: String, audioData: Data, memoId: UUID, config: TranscribeStepConfig, isPrimary: Bool) async throws -> String {
        if modelId == "apple_speech" {
            return try await transcribeWithAppleSpeech(audioData: audioData, memoId: memoId, config: config)
        } else {
            return try await transcribeWithWhisper(modelId: modelId, audioData: audioData, memoId: memoId, config: config)
        }
    }

    /// Save transcript to LocalRepository with proper versioning
    /// Handles version incrementing, memo updates, and error logging
    private func saveTranscriptToRepository(
        transcript: String,
        memoId: UUID,
        engine: String,
        repository: LocalRepository
    ) async {
        do {
            // Fetch existing versions to determine next version number
            let memoData = try await repository.fetchMemo(id: memoId)
            let existingVersions = memoData?.transcriptVersions ?? []
            let nextVersion = (existingVersions.map { $0.version }.max() ?? 0) + 1

            // Save new transcript version
            let transcriptVersion = TranscriptVersionModel(
                id: UUID(),
                memoId: memoId,
                version: nextVersion,
                content: transcript,
                sourceType: "system_macos",
                engine: engine,
                createdAt: Date(),
                transcriptionDurationMs: 0
            )
            try await repository.saveTranscriptVersion(transcriptVersion)
            logger.info("Saved transcript version \(nextVersion) to LocalRepository")

            // Update memo's transcription field
            if var memoToUpdate = memoData?.memo {
                memoToUpdate.transcription = transcript
                memoToUpdate.lastModified = Date()
                try await repository.saveMemo(memoToUpdate)
                logger.info("Updated memo transcription field")
            }
        } catch {
            // Log error instead of silently ignoring
            logger.error("Failed to save transcript to LocalRepository: \(error.localizedDescription)")
        }
    }

    /// Transcribe using Apple Speech (no download required)
    private func transcribeWithAppleSpeech(audioData: Data, memoId: UUID, config: TranscribeStepConfig) async throws -> String {
        await SystemEventManager.shared.log(.workflow, "Transcribing with Apple Speech", detail: "On-device, instant")
        do {
            let transcript = try await AppleSpeechService.shared.transcribe(audioData: audioData)

            // Save transcript to LocalRepository
            if config.saveAsVersion {
                await saveTranscriptToRepository(
                    transcript: transcript,
                    memoId: memoId,
                    engine: TranscriptEngines.appleSpeech,
                    repository: LocalRepository()
                )
            }

            logger.info("Apple Speech transcription complete: \(transcript.prefix(100))...")
            await SystemEventManager.shared.log(.workflow, "Transcription complete", detail: "\(transcript.count) characters")
            return transcript
        } catch {
            logger.error("Apple Speech transcription failed: \(error.localizedDescription)")
            throw WorkflowError.executionFailed("Apple Speech transcription failed: \(error.localizedDescription)")
        }
    }

    /// Transcribe using Whisper via TalkieEngine (requires model download)
    private func transcribeWithWhisper(modelId: String, audioData: Data, memoId: UUID, config: TranscribeStepConfig) async throws -> String {
        let modelName = TranscribeStepConfig.availableModels.first { $0.id == modelId }?.name ?? modelId
        await SystemEventManager.shared.log(.workflow, "Transcribing with Whisper", detail: modelName)

        // Convert model string to WhisperModel enum
        let whisperModel: WhisperModel
        switch modelId {
        case "openai_whisper-tiny":
            whisperModel = .tiny
        case "openai_whisper-base":
            whisperModel = .base
        case "openai_whisper-small":
            whisperModel = .small
        case "distil-whisper_distil-large-v3":
            whisperModel = .distilLargeV3
        default:
            whisperModel = .small
        }

        do {
            let transcript = try await WhisperService.shared.transcribe(audioData: audioData, model: whisperModel)

            // Save transcript to LocalRepository
            if config.saveAsVersion {
                await saveTranscriptToRepository(
                    transcript: transcript,
                    memoId: memoId,
                    engine: TranscriptEngines.mlxWhisper,
                    repository: LocalRepository()
                )
            }

            logger.info("Whisper transcription complete: \(transcript.prefix(100))...")
            await SystemEventManager.shared.log(.workflow, "Transcription complete", detail: "\(transcript.count) characters")
            return transcript
        } catch {
            logger.error("Whisper transcription failed: \(error.localizedDescription)")
            throw WorkflowError.executionFailed("Whisper transcription failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Speak Step Execution (Walkie-Talkie Mode!)

    private func executeSpeakStep(_ config: SpeakStepConfig, context: WorkflowContext) async throws -> String {
        logger.info("Executing speak step (Walkie-Talkie mode) with provider: \(config.provider.rawValue)")
        // Resolve text with variables
        let textToSpeak = context.resolve(config.text)

        guard !textToSpeak.isEmpty else {
            logger.warning("Speak step: no text to speak after variable resolution")
            return ""
        }

        await SystemEventManager.shared.log(.workflow, "Speaking response", detail: "\(textToSpeak.prefix(50))...")
        // Generate audio file path
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw WorkflowError.executionFailed("Cannot access documents directory")
        }
        let audioDir = documentsURL.appendingPathComponent("TalkieAudio")
        try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let timestamp = Date().iso8601
        let filename = "walkie-\(timestamp).mp3"
        let fileURL = audioDir.appendingPathComponent(filename)

        var audioFileURL: URL?

        // Use appropriate TTS provider
        switch config.provider {
        case .system:
            // Use built-in macOS AVSpeechSynthesizer
            audioFileURL = try await generateWithSystemTTS(
                text: textToSpeak,
                voiceId: resolvedSystemVoiceId(for: config),
                config: config,
                outputURL: fileURL
            )

        case .speakeasy, .openai:
            // Direct OpenAI TTS API
            let voice = config.voice ?? "echo"
            audioFileURL = try await TTSService.synthesizeOpenAI(text: textToSpeak, voice: voice, apiKey: SettingsManager.shared.openaiApiKey)

        case .elevenlabs:
            // Direct ElevenLabs TTS API
            let voiceId = config.voice ?? "Rachel"
            audioFileURL = try await TTSService.synthesizeElevenLabs(text: textToSpeak, voiceId: voiceId, apiKey: SettingsManager.shared.fetchElevenLabsKey())

        case .local:
            throw WorkflowError.executionFailed("Local TTS was removed. Switch this step to OpenAI or ElevenLabs.")
        }

        // Play audio file immediately (non-blocking)
        if config.playImmediately, let url = audioFileURL {
            // Fire-and-forget playback using NSSound - doesn't block workflow
            if let sound = NSSound(contentsOf: url, byReference: true) {
                sound.play()
                logger.info("🔊 Started audio playback (non-blocking)")
            } else {
                logger.warning("🔊 Failed to create NSSound from \(url.path)")
            }
        } else if config.provider == .system && config.playImmediately {
            // System TTS fallback (blocking for now, but system TTS is rarely used)
            let speechService = SpeechSynthesisService.shared
            if let voiceId = resolvedSystemVoiceId(for: config) {
                await MainActor.run { speechService.selectedVoiceIdentifier = voiceId }
            }
            await MainActor.run {
                speechService.speechRate = config.rate
                speechService.speechPitch = config.pitch
            }
            logger.info("🔊 Starting system speech...")
            await speechService.speakAsync(textToSpeak)
            logger.info("🔊 System speech playback complete")
        }

        // Log if saving
        if config.saveToFile, let url = audioFileURL {
            await SystemEventManager.shared.log(.workflow, "Audio saved", detail: url.lastPathComponent)
        }

        logger.info("🔊 Speak step complete")
        await SystemEventManager.shared.log(.workflow, "Speak complete")
        return textToSpeak
    }

    /// Generate audio using built-in macOS TTS
    private func generateWithSystemTTS(text: String, voiceId: String?, config: SpeakStepConfig, outputURL: URL) async throws -> URL? {
        let speechService = SpeechSynthesisService.shared

        if let voiceId {
            await MainActor.run { speechService.selectedVoiceIdentifier = voiceId }
        }
        await MainActor.run {
            speechService.speechRate = config.rate
            speechService.speechPitch = config.pitch
        }

        // Generate to file with .caf extension for system TTS
        let cafURL = outputURL.deletingPathExtension().appendingPathExtension("caf")
        try await speechService.generateAudioFile(from: text, to: cafURL)
        logger.info("Generated system TTS audio: \(cafURL.lastPathComponent)")
        return cafURL
    }

    private func resolvedSystemVoiceId(for config: SpeakStepConfig) -> String? {
        if let voiceId = config.voice, !voiceId.isEmpty {
            return voiceId
        }

        let selectedVoiceId = settings.selectedTTSVoiceId
        return selectedVoiceId.hasPrefix("com.apple.voice") ? selectedVoiceId : nil
    }

    /// Generate audio using SpeakEasy CLI
    // generateWithSpeakEasy removed — cloud TTS now uses direct API calls
    // via TTSService.

    // MARK: - Condition Evaluation
    private func evaluateCondition(_ condition: String) -> Bool {
        // Simple condition evaluation
        // Supports: contains, equals, startsWith, endsWith, isEmpty, isNotEmpty

        let trimmed = condition.trimmingCharacters(in: .whitespaces)

        if trimmed.contains(" contains ") {
            let parts = trimmed.components(separatedBy: " contains ")
            guard parts.count == 2 else { return false }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return parts[0].contains(value)
        }

        if trimmed.contains(" equals ") {
            let parts = trimmed.components(separatedBy: " equals ")
            guard parts.count == 2 else { return false }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return parts[0] == value
        }

        if trimmed.contains(" startsWith ") {
            let parts = trimmed.components(separatedBy: " startsWith ")
            guard parts.count == 2 else { return false }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return parts[0].hasPrefix(value)
        }

        if trimmed.contains(" endsWith ") {
            let parts = trimmed.components(separatedBy: " endsWith ")
            guard parts.count == 2 else { return false }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return parts[0].hasSuffix(value)
        }

        if trimmed.hasSuffix(" isEmpty") {
            let value = trimmed.replacingOccurrences(of: " isEmpty", with: "")
            return value.trimmingCharacters(in: .whitespaces).isEmpty
        }

        if trimmed.hasSuffix(" isNotEmpty") {
            let value = trimmed.replacingOccurrences(of: " isNotEmpty", with: "")
            return !value.trimmingCharacters(in: .whitespaces).isEmpty
        }

        // Default: non-empty string is truthy
        return !trimmed.isEmpty
    }

    // MARK: - Trigger Step Execution

    /// Thrown when trigger step doesn't match and stopIfNoMatch is true
    struct TriggerNotMatchedError: Error {}

    private func executeTriggerStep(_ config: TriggerStepConfig, context: WorkflowContext) throws -> String {
        let transcript = context.transcript

        // Determine search text based on case sensitivity
        let searchText = config.caseSensitive ? transcript : transcript.lowercased()
        let searchPhrases = config.caseSensitive ? config.phrases : config.phrases.map { $0.lowercased() }

        // Find the first matching phrase
        var matchedPhrase: String? = nil
        var matchRange: Range<String.Index>? = nil

        for phrase in searchPhrases {
            let options: String.CompareOptions
            switch config.searchLocation {
            case .end:
                options = .backwards
            case .start:
                options = []
            case .anywhere:
                options = []
            }

            if let range = searchText.range(of: phrase, options: options) {
                matchedPhrase = phrase
                matchRange = range
                break
            }
        }

        guard let phrase = matchedPhrase, let range = matchRange else {
            // No match found
            if config.stopIfNoMatch {
                throw TriggerNotMatchedError()
            }
            return """
            {"matched": false}
            """
        }

        // Extract context window around the match
        let position = searchText.distance(from: searchText.startIndex, to: range.lowerBound)
        let contextWindow = extractContextWindow(from: transcript, triggerPosition: position, windowSize: config.contextWindowSize)

        // Return JSON with match info
        let result: [String: Any] = [
            "matched": true,
            "phrase": phrase,
            "position": position,
            "context": contextWindow
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: result),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return """
        {"matched": true, "phrase": "\(phrase)", "context": "\(contextWindow.prefix(200))..."}
        """
    }

    /// Extract context window around the trigger position
    private func extractContextWindow(from transcript: String, triggerPosition: Int, windowSize: Int) -> String {
        let words = transcript.split(separator: " ", omittingEmptySubsequences: true)

        // Find which word index contains the trigger position
        var charCount = 0
        var triggerWordIndex = 0

        for (index, word) in words.enumerated() {
            charCount += word.count + 1 // +1 for space
            if charCount > triggerPosition {
                triggerWordIndex = index
                break
            }
        }

        // Get words before and after (bias toward after for commands)
        let startIndex = max(0, triggerWordIndex - 50)
        let endIndex = min(words.count, triggerWordIndex + windowSize)

        let windowWords = words[startIndex..<endIndex]
        return windowWords.joined(separator: " ")
    }

    // MARK: - Intent Extract Step Execution

    private func executeIntentExtractStep(_ config: IntentExtractStepConfig, context: WorkflowContext) async throws -> String {
        // Get input from previous step or specified key
        let input = context.resolve(config.inputKey)

        // Parse context if it's JSON from trigger step
        var textToAnalyze = input
        if let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let contextText = json["context"] as? String {
            textToAnalyze = contextText
        }

        var extractedIntents: [ExtractedIntent] = []

        switch config.extractionMethod {
        case .keywords:
            extractedIntents = extractIntentsWithKeywords(from: textToAnalyze, recognizedIntents: config.recognizedIntents)

        case .llm:
            extractedIntents = await extractIntentsWithLLM(from: textToAnalyze, config: config)

        case .hybrid:
            // Try LLM first, fall back to keywords
            extractedIntents = await extractIntentsWithLLM(from: textToAnalyze, config: config)
            if extractedIntents.isEmpty {
                extractedIntents = extractIntentsWithKeywords(from: textToAnalyze, recognizedIntents: config.recognizedIntents)
            }
        }

        // Filter by confidence threshold
        let threshold = config.confidenceThreshold
        extractedIntents = extractedIntents.filter { ($0.confidence ?? 1.0) >= threshold }

        // Encode as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let jsonData = try? encoder.encode(extractedIntents),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "[]"
    }

    /// Extract intents using keyword matching
    private func extractIntentsWithKeywords(from text: String, recognizedIntents: [IntentDefinition]) -> [ExtractedIntent] {
        let lowercased = text.lowercased()
        var results: [ExtractedIntent] = []

        for intent in recognizedIntents where intent.isEnabled {
            // Check main name and synonyms
            let allKeywords = [intent.name] + intent.synonyms
            for keyword in allKeywords {
                if lowercased.contains(keyword.lowercased()) {
                    // Avoid duplicates
                    if !results.contains(where: { $0.action == intent.name }) {
                        let parameter = extractParameterForIntent(intent.name, from: lowercased)
                        results.append(ExtractedIntent(
                            action: intent.name,
                            parameter: parameter,
                            confidence: 0.7,
                            workflowId: intent.targetWorkflowId
                        ))
                    }
                    break
                }
            }
        }

        return results
    }

    /// Extract time/parameter for certain intent types
    private func extractParameterForIntent(_ intent: String, from text: String) -> String? {
        guard intent == "remind" || intent == "calendar" else { return nil }

        // Simple time extraction patterns
        let patterns = [
            "tomorrow", "next week", "next monday", "next tuesday", "next wednesday",
            "next thursday", "next friday", "next saturday", "next sunday",
            "in an hour", "in two hours", "in a day", "in two days", "in three days",
            "in a week", "this afternoon", "this evening", "tonight"
        ]

        for pattern in patterns {
            if text.contains(pattern) {
                return pattern
            }
        }

        // Regex for "in X days/hours/minutes"
        if let regex = try? NSRegularExpression(pattern: "in (\\d+) (day|hour|minute|week)s?", options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            return String(text[range])
        }

        return nil
    }

    /// Extract intents using LLM with configurable prompt template
    private func extractIntentsWithLLM(from text: String, config: IntentExtractStepConfig) async -> [ExtractedIntent] {
        let recognizedIntents = config.recognizedIntents
        // Build prompt from template
        let intentNames = recognizedIntents.filter { $0.isEnabled }.map { $0.name }.joined(separator: ", ")
        let prompt = config.llmPromptTemplate
            .replacingOccurrences(of: "{{INPUT}}", with: text)
            .replacingOccurrences(of: "{{TRANSCRIPT}}", with: text)
            .replacingOccurrences(of: "{{INTENT_NAMES}}", with: intentNames)

        // Use the registry to resolve provider and model (reads from config)
        guard let resolved = await registry.resolveProviderAndModel() else {
            logger.warning("No LLM provider available for intent extraction. Configure an API key in Settings.")
            return []
        }

        let provider = resolved.provider
        let modelId = resolved.modelId
        logger.info("Intent extraction using \(provider.name) with model \(modelId)")
        do {
            let response = try await provider.generate(
                prompt: prompt,
                model: modelId,
                options: GenerationOptions(temperature: 0.3, maxTokens: 512)
            )

            return parseIntentLLMResponse(response, recognizedIntents: recognizedIntents)
        } catch {
            logger.warning("LLM intent extraction failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Parse LLM response into ExtractedIntent array
    private func parseIntentLLMResponse(_ response: String, recognizedIntents: [IntentDefinition]) -> [ExtractedIntent] {
        var results: [ExtractedIntent] = []

        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("action:") else { continue }

            let parts = trimmed.components(separatedBy: "|")
            if let actionPart = parts.first {
                let action = actionPart
                    .replacingOccurrences(of: "ACTION:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()

                var param: String? = nil
                var confidence: Double = 0.85 // default confidence for LLM

                // Parse PARAM if present
                for part in parts.dropFirst() {
                    let trimmedPart = part.trimmingCharacters(in: .whitespaces)
                    if trimmedPart.lowercased().hasPrefix("param:") {
                        let value = trimmedPart
                            .replacingOccurrences(of: "PARAM:", with: "", options: .caseInsensitive)
                            .trimmingCharacters(in: .whitespaces)
                        if !value.isEmpty {
                            param = value
                        }
                    } else if trimmedPart.lowercased().hasPrefix("confidence:") {
                        let value = trimmedPart
                            .replacingOccurrences(of: "CONFIDENCE:", with: "", options: .caseInsensitive)
                            .trimmingCharacters(in: .whitespaces)
                        if let parsed = Double(value) {
                            confidence = parsed
                        }
                    }
                }

                // Find matching intent definition for workflowId
                let matchingIntent = recognizedIntents.first { $0.name == action }

                if !action.isEmpty {
                    results.append(ExtractedIntent(
                        action: action,
                        parameter: param,
                        confidence: confidence,
                        workflowId: matchingIntent?.targetWorkflowId
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Execute Workflows Step

    private func executeWorkflowsStep(
        _ config: ExecuteWorkflowsStepConfig,
        context: WorkflowContext
    ) async throws -> String {
        let memo = context.memo
        logger.info("📋 executeWorkflowsStep started")
        // Get intents from previous step
        let intentsJson = context.resolve(config.intentsKey)
        logger.info("📋 Resolved intents JSON length: \(intentsJson.count) chars")
        guard let data = intentsJson.data(using: .utf8),
              let intents = try? JSONDecoder().decode([ExtractedIntent].self, from: data) else {
            logger.warning("📋 Failed to decode intents JSON: \(intentsJson.prefix(200))")
            return "No intents to execute"
        }

        logger.info("📋 Decoded \(intents.count) intents")
        var results: [String] = []
        var errors: [String] = []

        for intent in intents {
            logger.info("📋 Processing intent: \(intent.action)")
            // Check if this intent is configured for "detect only" (no execution)
            if intent.workflowId == IntentDefinition.doNothingId {
                logger.info("📋 Intent '\(intent.action)' detected (detect only mode)")
                results.append("\(intent.action): detected (no action)")
                continue
            }

            // Find workflow by ID first, then fallback to name matching
            var workflow: WorkflowDefinition?

            if let workflowId = intent.workflowId {
                workflow = WorkflowService.shared.workflow(byID: workflowId)?.definition
            }

            // Fallback: match intent action to workflow by name
            if workflow == nil {
                let intentLower = intent.action.lowercased()
                workflow = WorkflowService.shared.workflows.first { wf in
                    let nameLower = wf.name.lowercased()
                    // Match if workflow name contains intent action or vice versa
                    return nameLower.contains(intentLower) ||
                           intentLower.contains(nameLower.components(separatedBy: " ").first ?? "") ||
                           (intentLower == "summarize" && nameLower.contains("summary")) ||
                           (intentLower == "todo" && (nameLower.contains("task") || nameLower.contains("todo"))) ||
                           (intentLower == "remind" && nameLower.contains("remind")) ||
                           (intentLower == "note" && nameLower.contains("note"))
                }?.definition
                if let wf = workflow {
                    logger.info("📋 Matched intent '\(intent.action)' to workflow '\(wf.name)' by name")
                }
            }

            guard let workflow = workflow else {
                logger.info("📋 Intent '\(intent.action)' has no workflow mapped and no match found")
                results.append("\(intent.action): No workflow mapped")
                continue
            }

            do {
                _ = try await executeWorkflow(workflow, for: memo)
                results.append("\(intent.action): Completed - \(workflow.name)")
                logger.info("Executed workflow '\(workflow.name)' for intent '\(intent.action)'")
            } catch {
                let errorMsg = "\(intent.action): Failed - \(error.localizedDescription)"
                errors.append(errorMsg)
                if config.stopOnError {
                    throw WorkflowError.executionFailed(errorMsg)
                }
            }
        }

        // Build summary
        let summary = """
        Executed \(results.count) workflow(s)
        \(results.joined(separator: "\n"))
        \(errors.isEmpty ? "" : "\nErrors:\n\(errors.joined(separator: "\n"))")
        """

        logger.info("📋 executeWorkflowsStep finished")
        return summary
    }

    // MARK: - Execute Action Chain (legacy)
    func executeChain(
        actions: [WorkflowActionType],
        for memo: VoiceMemo,
        providerName: String? = nil,
        modelId: String? = nil,
        context: NSManagedObjectContext
    ) async throws {
        for action in actions {
            try await execute(
                action: action,
                for: memo,
                providerName: providerName,
                modelId: modelId,
                context: context
            )
        }
    }

    // MARK: - Helper Methods
    private func setProcessingState(
        for action: WorkflowActionType,
        memo: VoiceMemo,
        isProcessing: Bool
    ) {
        switch action {
        case .summarize:
            memo.isProcessingSummary = isProcessing
        case .extractTasks:
            memo.isProcessingTasks = isProcessing
        case .reminders:
            memo.isProcessingReminders = isProcessing
        case .keyInsights, .share:
            break
        }
    }

    private func saveResult(
        _ result: WorkflowResult,
        to memo: VoiceMemo,
        context: NSManagedObjectContext
    ) {
        switch result.actionType {
        case .summarize:
            memo.summary = result.output

        case .extractTasks:
            // Parse JSON array of tasks
            if let data = result.output.data(using: .utf8),
               let tasks = try? JSONDecoder().decode([TaskItem].self, from: data) {
                memo.tasks = result.output // Store raw JSON
                logger.debug("📋 Extracted \(tasks.count) tasks")
            } else {
                // Fallback: store as plain text if JSON parsing fails
                memo.tasks = result.output
                logger.debug("⚠️ Could not parse tasks as JSON, storing as text")
            }

        case .reminders:
            // Parse JSON array of reminders
            if let data = result.output.data(using: .utf8),
               let reminders = try? JSONDecoder().decode([ReminderItem].self, from: data) {
                memo.reminders = result.output // Store raw JSON
                logger.debug("🔔 Extracted \(reminders.count) reminders")
            } else {
                // Fallback: store as plain text if JSON parsing fails
                memo.reminders = result.output
                logger.debug("⚠️ Could not parse reminders as JSON, storing as text")
            }

        case .keyInsights:
            // Parse JSON array of insights
            if let data = result.output.data(using: .utf8),
               let insights = try? JSONDecoder().decode([String].self, from: data) {
                memo.summary = insights.joined(separator: "\n\n") // Store in summary field
                logger.debug("💡 Extracted \(insights.count) insights")
            } else {
                memo.summary = result.output
            }

        case .share:
            break
        }
    }
}

// MARK: - Errors
enum WorkflowError: LocalizedError {
    case noTranscript
    case executionFailed(String)
    case stepFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .noTranscript:
            return "Voice memo must be transcribed before running workflows."
        case .executionFailed(let message):
            return "Workflow execution failed: \(message)"
        case .stepFailed(let step, let error):
            return "Step '\(step)' failed: \(error.localizedDescription)"
        }
    }
}
