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

private let logger = Logger(subsystem: "live.talkie.core", category: "WorkflowExecutor")

// MARK: - Workflow Execution Context

struct WorkflowContext {
    var transcript: String
    var title: String
    var date: Date
    var outputs: [String: String] = [:]

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
        result = result.replacingOccurrences(of: "{{TRANSCRIPT}}", with: transcript)
        result = result.replacingOccurrences(of: "{{TITLE}}", with: sanitizeForFilename(title))
        result = result.replacingOccurrences(of: "{{DATE}}", with: Self.dateFormatter.string(from: date))
        result = result.replacingOccurrences(of: "{{DATETIME}}", with: Self.datetimeFormatter.string(from: date))

        // Replace output keys
        for (key, value) in outputs {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        // Handle PREVIOUS_OUTPUT - use the last output if available
        if let lastOutput = Array(outputs.values).last {
            result = result.replacingOccurrences(of: "{{PREVIOUS_OUTPUT}}", with: lastOutput)
        }

        // Handle OUTPUT - same as PREVIOUS_OUTPUT for backward compatibility
        if let lastOutput = Array(outputs.values).last {
            result = result.replacingOccurrences(of: "{{OUTPUT}}", with: lastOutput)
        }

        return result
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
class WorkflowExecutor: ObservableObject {
    static let shared = WorkflowExecutor()

    private let registry = LLMProviderRegistry.shared
    private let settings = SettingsManager.shared

    private init() {}

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

            print("✅ \(action.rawValue) completed successfully")

        } catch {
            // Clear processing state on error
            setProcessingState(for: action, memo: memo, isProcessing: false)
            try? context.save()
            throw error
        }
    }

    // MARK: - Execute Workflow Definition (new step-based system)
    func executeWorkflow(
        _ workflow: WorkflowDefinition,
        for memo: VoiceMemo,
        context: NSManagedObjectContext
    ) async throws -> [String: String] {
        // Check if workflow starts with transcription - if so, we don't need a transcript yet
        let startsWithTranscribe = workflow.steps.first?.type == .transcribe

        // Require transcript for non-transcription workflows
        let transcript = memo.currentTranscript ?? ""
        if !startsWithTranscribe && transcript.isEmpty {
            throw WorkflowError.noTranscript
        }

        // Prevent system from throttling during workflow execution
        // This is lightweight - just tells macOS "we're doing something important"
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Executing workflow: \(workflow.name)"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }

        var workflowContext = WorkflowContext(
            transcript: transcript,  // May be empty for transcription-first workflows
            title: memo.title ?? "Untitled",
            date: memo.createdAt ?? Date()
        )

        // Add workflow name to context for use in templates
        workflowContext.outputs["WORKFLOW_NAME"] = workflow.name

        // Track provider/model used for the run
        var usedProvider: String?
        var usedModel: String?

        // Track step-by-step execution for detailed view
        var stepExecutions: [StepExecution] = []

        // Log workflow start to console
        await SystemEventManager.shared.log(.workflow, "Starting: \(workflow.name)", detail: "Memo: \(memo.title ?? "Untitled")")

        // Register with pending actions manager
        let pendingActionId = PendingActionsManager.shared.startAction(
            workflowId: workflow.id,
            workflowName: workflow.name,
            workflowIcon: workflow.icon,
            memoId: memo.id,
            memoTitle: memo.title ?? "Untitled",
            totalSteps: workflow.steps.filter { $0.isEnabled }.count
        )

        logger.info("🔄 Starting workflow loop with \(workflow.steps.count) steps")

        for (index, step) in workflow.steps.enumerated() {
            logger.info("🔄 Processing step \(index + 1)/\(workflow.steps.count): \(step.type.rawValue)")

            guard step.isEnabled else {
                await SystemEventManager.shared.log(.workflow, "Skipping step \(index + 1) (disabled)", detail: workflow.name)
                logger.info("⏭️ Step \(index + 1) is disabled, skipping")
                continue
            }

            // Check condition if present
            if let condition = step.condition {
                let resolvedCondition = workflowContext.resolve(condition.expression)
                if !evaluateCondition(resolvedCondition) {
                    if condition.skipOnFail {
                        await SystemEventManager.shared.log(.workflow, "Skipping step \(index + 1) (condition)", detail: workflow.name)
                        logger.info("⏭️ Step \(index + 1) condition not met, skipping")
                        continue
                    }
                }
            }

            await SystemEventManager.shared.log(.workflow, "Step \(index + 1): \(step.type.rawValue)", detail: workflow.name)

            // Update pending action progress
            PendingActionsManager.shared.updateAction(
                id: pendingActionId,
                currentStep: step.type.rawValue,
                stepIndex: index
            )

            // Capture input for this step
            let stepInput: String
            if case .llm(let config) = step.config {
                usedProvider = config.provider?.displayName ?? "auto-route"
                usedModel = config.modelId ?? "auto"
                stepInput = workflowContext.resolve(config.prompt)
            } else if case .shell(let config) = step.config {
                // For shell steps, show the command that will be executed
                let resolvedArgs = config.arguments.map { workflowContext.resolve($0) }
                let commandDisplay = ([config.executable] + resolvedArgs)
                    .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
                    .joined(separator: " ")
                if let stdin = config.stdin {
                    let resolvedStdin = workflowContext.resolve(stdin)
                    let preview = String(resolvedStdin.prefix(200))
                    stepInput = "$ \(commandDisplay)\n\n[stdin: \(preview)\(resolvedStdin.count > 200 ? "..." : "")]"
                } else {
                    stepInput = "$ \(commandDisplay)"
                }
            } else {
                stepInput = workflowContext.transcript
            }

            logger.info("🔄 Executing step \(index + 1)...")
            let output: String
            do {
                output = try await executeStep(step, context: &workflowContext, memo: memo, coreDataContext: context)
                logger.info("✅ Step \(index + 1) completed, output length: \(output.count) chars")
            } catch is TriggerNotMatchedError {
                // Trigger step didn't match - stop workflow gracefully (not an error)
                logger.info("🛑 Trigger not matched at step \(index + 1), stopping workflow '\(workflow.name)' gracefully")
                await SystemEventManager.shared.log(.workflow, "Trigger not matched, stopping", detail: workflow.name)
                // Complete the pending action (graceful stop is success)
                PendingActionsManager.shared.completeAction(id: pendingActionId)
                break
            } catch {
                logger.error("❌ Step \(index + 1) failed with error: \(error.localizedDescription)")
                // Mark pending action as failed
                PendingActionsManager.shared.failAction(id: pendingActionId, error: error.localizedDescription)
                throw error
            }
            workflowContext.outputs[step.outputKey] = output
            logger.info("💾 Saved output to key '\(step.outputKey)'")

            // Record step execution
            stepExecutions.append(StepExecution(
                stepNumber: index + 1,
                stepType: step.type.rawValue,
                stepIcon: step.type.icon,
                input: stepInput,
                output: output,
                outputKey: step.outputKey
            ))

            await SystemEventManager.shared.log(.workflow, "Step \(index + 1) completed", detail: workflow.name)
            logger.info("➡️ Moving to next step...")
        }

        logger.info("🏁 Workflow loop finished, executed \(stepExecutions.count) steps")

        // Mark pending action as completed
        PendingActionsManager.shared.completeAction(id: pendingActionId)

        await SystemEventManager.shared.log(.workflow, "Completed: \(workflow.name)", detail: "\(workflow.steps.count) steps")

        // Save workflow run to Core Data
        let finalOutput = workflowContext.outputs.values.joined(separator: "\n\n---\n\n")
        saveWorkflowRun(
            workflow: workflow,
            output: finalOutput,
            stepExecutions: stepExecutions,
            providerName: usedProvider,
            modelId: usedModel,
            memo: memo,
            context: context
        )

        return workflowContext.outputs
    }

    // MARK: - Step Execution Record
    struct StepExecution: Codable {
        let stepNumber: Int
        let stepType: String
        let stepIcon: String
        let input: String
        let output: String
        let outputKey: String
    }

    // MARK: - Save Workflow Run
    private func saveWorkflowRun(
        workflow: WorkflowDefinition,
        output: String,
        stepExecutions: [StepExecution],
        providerName: String?,
        modelId: String?,
        memo: VoiceMemo,
        context: NSManagedObjectContext
    ) {
        context.perform {
            let run = WorkflowRun(context: context)
            run.id = UUID()
            run.workflowId = workflow.id
            run.workflowName = workflow.name
            run.workflowIcon = workflow.icon
            run.output = output
            run.providerName = providerName
            run.modelId = modelId
            run.runDate = Date()
            run.status = "completed"
            run.memo = memo
            run.memoId = memo.id  // Denormalized for CloudKit querying

            // Encode step executions as JSON
            if let jsonData = try? JSONEncoder().encode(stepExecutions),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                run.stepOutputsJSON = jsonString
            }

            do {
                try context.save()
                print("💾 Saved workflow run: \(workflow.name)")
            } catch {
                print("❌ Failed to save workflow run: \(error)")
            }
        }
    }

    // MARK: - Execute Single Step
    private func executeStep(
        _ step: WorkflowStep,
        context: inout WorkflowContext,
        memo: VoiceMemo,
        coreDataContext: NSManagedObjectContext
    ) async throws -> String {
        switch step.config {
        case .llm(let config):
            return try await executeLLMStep(config, context: context)

        case .shell(let config):
            return try await executeShellStep(config, context: context)

        case .webhook(let config):
            return try await executeWebhookStep(config, context: context, memo: memo)

        case .email(let config):
            return try await executeEmailStep(config, context: context)

        case .notification(let config):
            return try await executeNotificationStep(config, context: context)

        case .iOSPush(let config):
            return try await executeiOSPushStep(config, context: context, memo: memo, coreDataContext: coreDataContext)

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
            return try await executeTranscribeStep(config, memo: memo, context: context)

        case .speak(let config):
            return try await executeSpeakStep(config, memo: memo, context: context)

        case .trigger(let config):
            return try executeTriggerStep(config, context: context)

        case .intentExtract(let config):
            return try await executeIntentExtractStep(config, context: context)

        case .executeWorkflows(let config):
            return try await executeWorkflowsStep(config, context: context, memo: memo, coreDataContext: coreDataContext)
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

        let options = GenerationOptions(
            temperature: config.temperature,
            topP: config.topP,
            maxTokens: config.maxTokens
        )

        // If system prompt exists, prepend it
        let fullPrompt: String
        if let system = systemPrompt {
            fullPrompt = "System: \(system)\n\nUser: \(resolvedPrompt)"
        } else {
            fullPrompt = resolvedPrompt
        }

        logger.info("🤖 LLM: Starting generation (prompt: \(fullPrompt.prefix(100))...)")

        do {
            let result = try await provider.generate(
                prompt: fullPrompt,
                model: resolved.modelId,
                options: options
            )

            logger.info("🤖 LLM: Generation complete (\(result.count) chars)")
            await SystemEventManager.shared.log(.workflow, "LLM complete", detail: "\(result.count) chars")
            return result

        } catch {
            logger.error("🤖 LLM: Generation failed - \(error.localizedDescription)")
            await SystemEventManager.shared.log(.error, "LLM failed", detail: error.localizedDescription)
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
            print("🚫 Shell step blocked: \(errorMessage)")
            throw WorkflowError.executionFailed("Security validation failed: \(errorMessage)")
        }

        // Verify executable exists
        guard FileManager.default.fileExists(atPath: config.executable) else {
            throw WorkflowError.executionFailed("Executable not found: \(config.executable)")
        }

        print("🖥️ Executing shell command: \(config.executable)")

        // Resolve template variables and sanitize dynamic content
        var resolvedArgs = config.arguments.map { arg in
            let resolved = context.resolve(arg)
            let sanitized = ShellStepConfig.sanitizeContent(resolved)

            // Check for injection attempts (log but don't block)
            let warnings = ShellStepConfig.detectInjectionAttempts(sanitized)
            for warning in warnings {
                print("⚠️ Injection warning in argument: \(warning)")
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
                print("⚠️ Injection warning in prompt template: \(warning)")
            }

            // Add -p flag and the prompt as arguments
            resolvedArgs.append("-p")
            resolvedArgs.append(sanitizedPrompt)
            print("   Prompt template resolved (\(sanitizedPrompt.count) chars)")
        }

        // Resolve stdin if provided
        let resolvedStdin: String? = config.stdin.map { stdinTemplate in
            let resolved = context.resolve(stdinTemplate)
            let sanitized = ShellStepConfig.sanitizeContent(resolved)

            // Check for injection attempts
            let warnings = ShellStepConfig.detectInjectionAttempts(sanitized)
            for warning in warnings {
                print("⚠️ Injection warning in stdin: \(warning)")
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

        print("   Command: \(commandDisplay)")
        if let stdin = resolvedStdin {
            print("   Stdin length: \(stdin.count) chars")
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

        // Ensure PATH includes common tool locations
        // This is needed for tools like claude that shell out to node
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Users/arach/.bun/bin",
            "/Users/arach/.nvm/versions/node/v20.11.0/bin", // Common nvm path
            "/Users/arach/.local/bin",
        ]
        if let existingPath = env["PATH"] {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
        } else {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":/usr/bin:/bin"
        }

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
                try await Task.sleep(nanoseconds: UInt64(config.timeout) * 1_000_000_000)
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
                        print("⚠️ Command exited with status: \(process.terminationStatus)")
                        if !stderr.isEmpty {
                            print("   Stderr: \(stderr.prefix(500))")
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
    private func executeWebhookStep(_ config: WebhookStepConfig, context: WorkflowContext, memo: VoiceMemo) async throws -> String {
        guard let url = URL(string: config.url) else {
            throw WorkflowError.executionFailed("Invalid webhook URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = config.method.rawValue

        // Add headers
        for (key, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build body
        var body: [String: Any] = [:]

        if config.includeTranscript {
            body["transcript"] = context.transcript
        }

        if config.includeMetadata {
            body["title"] = context.title
            body["date"] = ISO8601DateFormatter().string(from: context.date)
        }

        // Add previous outputs
        body["outputs"] = context.outputs

        // Custom body template if provided
        if let template = config.bodyTemplate {
            let resolved = context.resolve(template)
            if let data = resolved.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                body.merge(json) { _, new in new }
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WorkflowError.executionFailed("Webhook request failed")
        }

        return String(data: data, encoding: .utf8) ?? ""
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
        context: WorkflowContext,
        memo: VoiceMemo,
        coreDataContext: NSManagedObjectContext
    ) async throws -> String {
        // Resolve template variables, including workflow name
        var resolvedTitle = context.resolve(config.title)
        var resolvedBody = context.resolve(config.body)

        // Handle {{WORKFLOW_NAME}} separately since it's not in the standard context
        // The workflow name will be set by the parent execution if available
        if let workflowName = context.outputs["WORKFLOW_NAME"] {
            resolvedTitle = resolvedTitle.replacingOccurrences(of: "{{WORKFLOW_NAME}}", with: workflowName)
            resolvedBody = resolvedBody.replacingOccurrences(of: "{{WORKFLOW_NAME}}", with: workflowName)
        }

        print("📱 [iOS Push] Creating push notification record...")
        print("📱 [iOS Push]   Title: \(resolvedTitle)")
        print("📱 [iOS Push]   Body: \(resolvedBody)")
        print("📱 [iOS Push]   Memo: \(memo.title ?? "Untitled") (ID: \(memo.id?.uuidString.prefix(8) ?? "nil")...)")
        print("📱 [iOS Push]   Sound: \(config.sound ? "enabled" : "disabled")")

        // Create PushNotification record in Core Data
        // This will sync to CloudKit and trigger the iOS CKQuerySubscription
        return try await coreDataContext.perform {
            let notificationId = UUID()
            let pushNotification = PushNotification(context: coreDataContext)
            pushNotification.id = notificationId
            pushNotification.title = resolvedTitle
            pushNotification.body = resolvedBody
            pushNotification.createdAt = Date()
            pushNotification.memoId = memo.id
            pushNotification.memoTitle = memo.title
            pushNotification.soundEnabled = config.sound
            pushNotification.isRead = false

            // Include workflow name for iOS display
            if let workflowName = context.outputs["WORKFLOW_NAME"] {
                pushNotification.workflowName = workflowName
            }

            try coreDataContext.save()
            print("📱 [iOS Push] ✅ Record saved to Core Data (ID: \(notificationId.uuidString.prefix(8))...)")
            print("📱 [iOS Push]   → Will sync to CloudKit → APNs → iOS device")

            return "Push notification queued for iOS"
        }
    }

    // MARK: - Apple Notes Step Execution
    private func executeAppleNotesStep(_ config: AppleNotesStepConfig, context: WorkflowContext) async throws -> String {
        let title = context.resolve(config.title)
        var body = context.resolve(config.body)

        if config.attachTranscript {
            body += "\n\n---\n\nTranscript:\n\(context.transcript)"
        }

        print("📝 Creating Apple Note:")
        print("   Title: \(title)")
        print("   Body length: \(body.count) chars")
        print("   Body preview: \(String(body.prefix(100)))...")

        // Convert body to HTML for better formatting in Notes
        let htmlBody = body
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        // Build the AppleScript with proper escaping
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedHtmlBody = htmlBody.replacingOccurrences(of: "\"", with: "&quot;")

        let script: String
        if let folder = config.folderName {
            let escapedFolder = folder.replacingOccurrences(of: "\"", with: "\\\"")
            script = """
            tell application "Notes"
                activate
                delay 0.5
                set theAccount to first account
                set theFolder to folder "\(escapedFolder)" of theAccount
                make new note at theFolder with properties {name:"\(escapedTitle)", body:"<html><body>\(escapedHtmlBody)</body></html>"}
            end tell
            """
        } else {
            script = """
            tell application "Notes"
                activate
                delay 0.5
                set theAccount to first account
                make new note at theAccount with properties {name:"\(escapedTitle)", body:"<html><body>\(escapedHtmlBody)</body></html>"}
            end tell
            """
        }

        print("📝 AppleScript:\n\(script)")

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                print("❌ AppleScript error (\(errorNumber)): \(errorMessage)")
                print("❌ Full error: \(error)")

                if errorNumber == -1743 {
                    throw WorkflowError.executionFailed("Permission denied. Go to System Settings > Privacy & Security > Automation and enable Notes for Talkie")
                }
                if errorNumber == -600 {
                    throw WorkflowError.executionFailed("Notes app couldn't be launched. Try opening Notes manually first, or check System Settings > Privacy & Security > Automation")
                }
                throw WorkflowError.executionFailed("Apple Notes error: \(errorMessage)")
            }
            print("✅ AppleScript result: \(result.stringValue ?? "nil")")
            print("✅ Note should be created in Notes app")
        } else {
            print("❌ Failed to compile AppleScript")
            throw WorkflowError.executionFailed("Failed to create AppleScript")
        }

        return "Note created: \(title)"
    }

    // MARK: - Apple Reminders Step Execution
    private func executeAppleRemindersStep(_ config: AppleRemindersStepConfig, context: WorkflowContext) async throws -> String {
        let title = context.resolve(config.title)
        let notes = config.notes.map { context.resolve($0) }

        // Build AppleScript
        var properties = ["name:\"\(title)\""]

        if let notes = notes {
            properties.append("body:\"\(notes.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }

        let listClause = config.listName.map { "of list \"\($0)\"" } ?? ""

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
        let title = context.resolve(config.title)

        // Default to now + 1 hour if no start date specified
        let startDate = Date().addingTimeInterval(3600)
        let endDate = startDate.addingTimeInterval(TimeInterval(config.duration))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"

        let startStr = dateFormatter.string(from: startDate)
        let endStr = dateFormatter.string(from: endDate)

        var properties = [
            "summary:\"\(title)\"",
            "start date:date \"\(startStr)\"",
            "end date:date \"\(endStr)\""
        ]

        if let location = config.location {
            properties.append("location:\"\(context.resolve(location))\"")
        }

        if config.isAllDay {
            properties.append("allday event:true")
        }

        let calendarClause = config.calendarName.map { "of calendar \"\($0)\"" } ?? ""

        let script = """
        tell application "Calendar"
            tell (first calendar where its name is "Calendar") \(calendarClause)
                make new event with properties {\(properties.joined(separator: ", "))}
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                throw WorkflowError.executionFailed("AppleScript error: \(error)")
            }
        }

        return "Calendar event created: \(title)"
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

        print("📁 Save File Step:")
        print("   Config directory: \(config.directory ?? "nil")")
        print("   Config filename: \(config.filename)")
        print("   Resolved filename: \(resolvedFilename)")

        var directory: URL

        // Check if filename contains an @alias (e.g., "@Obsidian/notes.md")
        if resolvedFilename.hasPrefix("@") {
            // Extract alias and path components
            let aliasResolved = SaveFileStepConfig.resolvePathAlias(resolvedFilename)
            print("   Filename contains @alias, resolved to: \(aliasResolved)")

            // Split into directory and filename
            let url = URL(fileURLWithPath: aliasResolved)
            directory = url.deletingLastPathComponent()
            resolvedFilename = url.lastPathComponent
            print("   Split into dir: \(directory.path), file: \(resolvedFilename)")
        } else if let customDir = config.directory, !customDir.isEmpty {
            // Resolve template variables first, then resolve @aliases
            let resolvedDir = context.resolve(customDir)
            let aliasResolved = SaveFileStepConfig.resolvePathAlias(resolvedDir)
            print("   Resolved dir: \(resolvedDir)")
            print("   After alias resolution: \(aliasResolved)")
            directory = URL(fileURLWithPath: aliasResolved)
        } else {
            // Use the default output directory from settings
            print("   Using default directory: \(SaveFileStepConfig.defaultOutputDirectory)")
            directory = URL(fileURLWithPath: SaveFileStepConfig.defaultOutputDirectory)
        }

        print("   Known aliases: \(SaveFileStepConfig.pathAliases)")

        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            print("   Created directory: \(directory.path)")
        }

        let fileURL = directory.appendingPathComponent(resolvedFilename)

        if config.appendIfExists && FileManager.default.fileExists(atPath: fileURL.path) {
            let existingContent = try String(contentsOf: fileURL, encoding: .utf8)
            try (existingContent + "\n" + content).write(to: fileURL, atomically: true, encoding: .utf8)
            print("📁 Appended to file: \(fileURL.path)")
        } else {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("📁 Saved file: \(fileURL.path)")
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
    private func executeTranscribeStep(_ config: TranscribeStepConfig, memo: VoiceMemo, context: WorkflowContext) async throws -> String {
        logger.info("Executing transcribe step with model: \(config.model)")

        // Check if memo already has a transcript and we're not overwriting
        if let existingTranscript = memo.currentTranscript, !existingTranscript.isEmpty, !config.overwriteExisting {
            logger.info("Memo already has transcript, skipping transcription (overwriteExisting=false)")
            return existingTranscript
        }

        // Get audio data from memo
        guard let audioData = memo.audioData else {
            throw WorkflowError.executionFailed("No audio data available for transcription")
        }

        logger.info("Transcribing audio (\(audioData.count) bytes)")

        // Use Apple Speech for "apple_speech" model, Whisper for others
        if config.model == "apple_speech" {
            return try await transcribeWithAppleSpeech(audioData: audioData, memo: memo, config: config)
        } else {
            return try await transcribeWithWhisper(audioData: audioData, memo: memo, config: config)
        }
    }

    /// Transcribe using Apple Speech (no download required)
    private func transcribeWithAppleSpeech(audioData: Data, memo: VoiceMemo, config: TranscribeStepConfig) async throws -> String {
        await SystemEventManager.shared.log(.workflow, "Transcribing with Apple Speech", detail: "On-device, no download")

        do {
            let transcript = try await AppleSpeechService.shared.transcribe(audioData: audioData)

            // Save transcript to memo if configured
            if config.saveAsVersion, let context = memo.managedObjectContext {
                await MainActor.run {
                    memo.addSystemTranscript(
                        content: transcript,
                        fromMacOS: true,
                        engine: TranscriptEngines.appleSpeech
                    )
                    try? context.save()
                }
                logger.info("Saved Apple Speech transcript as new version")
            }

            logger.info("Apple Speech transcription complete: \(transcript.prefix(100))...")
            await SystemEventManager.shared.log(.workflow, "Transcription complete", detail: "\(transcript.count) characters")

            return transcript
        } catch {
            logger.error("Apple Speech transcription failed: \(error.localizedDescription)")
            throw WorkflowError.executionFailed("Apple Speech transcription failed: \(error.localizedDescription)")
        }
    }

    /// Transcribe using Whisper (requires model download)
    private func transcribeWithWhisper(audioData: Data, memo: VoiceMemo, config: TranscribeStepConfig) async throws -> String {
        await SystemEventManager.shared.log(.workflow, "Transcribing with Whisper", detail: "Model: \(config.model)")

        // Convert model string to WhisperModel enum
        let whisperModel: WhisperModel
        switch config.model {
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

            // Save transcript to memo if configured
            if config.saveAsVersion, let context = memo.managedObjectContext {
                await MainActor.run {
                    memo.addSystemTranscript(
                        content: transcript,
                        fromMacOS: true,
                        engine: TranscriptEngines.mlxWhisper
                    )
                    try? context.save()
                }
                logger.info("Saved Whisper transcript as new version")
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

    private func executeSpeakStep(_ config: SpeakStepConfig, memo: VoiceMemo, context: WorkflowContext) async throws -> String {
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
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioDir = documentsURL.appendingPathComponent("TalkieAudio")
        try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "walkie-\(timestamp).mp3"
        let fileURL = audioDir.appendingPathComponent(filename)

        var audioFileURL: URL?

        // Use appropriate TTS provider
        switch config.provider {
        case .system:
            // Use built-in macOS AVSpeechSynthesizer
            audioFileURL = try await generateWithSystemTTS(text: textToSpeak, config: config, outputURL: fileURL)

        case .speakeasy, .openai, .elevenlabs:
            // Use SpeakEasy CLI
            audioFileURL = try await generateWithSpeakEasy(
                text: textToSpeak,
                provider: config.provider,
                voice: config.voice,
                useCache: config.useCache,
                playImmediately: config.playImmediately,
                outputURL: fileURL
            )
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
            let speechService = await SpeechSynthesisService.shared
            if let voiceId = config.voice {
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

        // Upload to CloudKit as Walkie (send audio to iOS!)
        if config.uploadToWalkie, let fileURL = audioFileURL {
            let memoId = memo.id?.uuidString ?? UUID().uuidString
            logger.info("📤 Uploading Walkie for memo: \(memoId)")

            do {
                let walkieId = try await WalkieService.shared.uploadWalkie(
                    audioURL: fileURL,
                    memoId: memoId,
                    transcript: textToSpeak
                )
                logger.info("📤 Walkie uploaded: \(walkieId)")
                await SystemEventManager.shared.log(.workflow, "Walkie sent to iOS", detail: "ID: \(walkieId.prefix(8))...")
            } catch {
                logger.error("📤 Walkie upload failed: \(error.localizedDescription)")
                await SystemEventManager.shared.log(.workflow, "Walkie upload failed", detail: error.localizedDescription)
            }
        }

        logger.info("🔊 Speak step complete")
        await SystemEventManager.shared.log(.workflow, "Speak complete", detail: "Walkie-Talkie reply delivered")

        return textToSpeak
    }

    /// Generate audio using built-in macOS TTS
    private func generateWithSystemTTS(text: String, config: SpeakStepConfig, outputURL: URL) async throws -> URL? {
        let speechService = await SpeechSynthesisService.shared

        if let voiceId = config.voice {
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

    /// Generate audio using SpeakEasy CLI
    private func generateWithSpeakEasy(
        text: String,
        provider: TTSProvider,
        voice: String?,
        useCache: Bool,
        playImmediately: Bool,
        outputURL: URL
    ) async throws -> URL? {
        logger.info("🗣️ Generating audio with SpeakEasy (provider: \(provider.rawValue))")

        // Build SpeakEasy command
        var args: [String] = []

        // Add text
        args.append("--text")
        args.append(text)

        // Provider mapping
        let speakeasyProvider: String
        switch provider {
        case .speakeasy:
            speakeasyProvider = "openai"  // Default SpeakEasy uses OpenAI
        case .openai:
            speakeasyProvider = "openai"
        case .elevenlabs:
            speakeasyProvider = "elevenlabs"
        case .system:
            speakeasyProvider = "system"
        }
        args.append("--provider")
        args.append(speakeasyProvider)

        // Voice - use a nice default if not specified
        let voiceToUse = voice ?? (speakeasyProvider == "openai" ? "echo" : nil)
        if let voiceToUse = voiceToUse {
            args.append("--voice")
            args.append(voiceToUse)
        }

        // Speech rate - default to 200 WPM for snappy responses
        if speakeasyProvider == "openai" {
            args.append("--rate")
            args.append("200")
        }

        // Silent mode - don't play audio, just generate the file
        // We'll handle playback ourselves for better UI control
        args.append("--silent")

        // Caching
        if useCache {
            args.append("--cache")
        }

        // Output file (--out saves to file in addition to playing)
        args.append("--out")
        args.append(outputURL.path)

        // Use node (bun crashes on better-sqlite3 native module)
        let nodePath = "/opt/homebrew/bin/node"
        let speakeasyScript = "/Users/arach/dev/speakeasy/dist/bin/speakeasy-cli.js"

        logger.info("🗣️ Node path: \(nodePath)")
        logger.info("🗣️ SpeakEasy script: \(speakeasyScript)")
        logger.info("🗣️ Output URL: \(outputURL.path)")

        // Verify files exist
        guard FileManager.default.fileExists(atPath: nodePath) else {
            logger.error("🗣️ Node not found at: \(nodePath)")
            throw NSError(domain: "SpeakEasy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Node not found at \(nodePath)"])
        }
        guard FileManager.default.fileExists(atPath: speakeasyScript) else {
            logger.error("🗣️ SpeakEasy script not found at: \(speakeasyScript)")
            throw NSError(domain: "SpeakEasy", code: 1, userInfo: [NSLocalizedDescriptionKey: "SpeakEasy script not found at \(speakeasyScript)"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [speakeasyScript] + args

        // Set environment for node
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["NODE_PATH"] = "/Users/arach/dev/speakeasy/node_modules"
        env["HOME"] = NSHomeDirectory()
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let commandPreview = "node speakeasy-cli.js " + args.map { $0.contains(" ") ? "\"\($0.prefix(50))...\"" : $0 }.joined(separator: " ")
        logger.info("🗣️ Running: \(commandPreview)")

        do {
            try process.run()
            process.waitUntilExit()  // Fast with --silent (no playback)

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            logger.info("🗣️ Exit code: \(process.terminationStatus)")
            if !stdout.isEmpty { logger.info("🗣️ stdout: \(stdout.prefix(500))") }
            if !stderr.isEmpty { logger.warning("🗣️ stderr: \(stderr.prefix(500))") }

            if process.terminationStatus == 0 {
                logger.info("🗣️ SpeakEasy completed successfully")
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    return outputURL
                } else {
                    // Check if file was created with different extension
                    let mp3URL = outputURL.deletingPathExtension().appendingPathExtension("mp3")
                    if FileManager.default.fileExists(atPath: mp3URL.path) {
                        logger.info("🗣️ Found output at \(mp3URL.path)")
                        return mp3URL
                    }
                    logger.warning("🗣️ SpeakEasy succeeded but output file not found")
                    return nil
                }
            } else {
                let errorMsg = stderr.isEmpty ? stdout : stderr
                logger.error("🗣️ SpeakEasy failed (exit \(process.terminationStatus)): \(errorMsg)")
                throw NSError(domain: "SpeakEasy", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        } catch {
            logger.error("🗣️ Failed to launch SpeakEasy: \(error.localizedDescription)")
            throw error
        }
    }

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
        context: WorkflowContext,
        memo: VoiceMemo,
        coreDataContext: NSManagedObjectContext
    ) async throws -> String {
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
                workflow = WorkflowManager.shared.workflows.first(where: { $0.id == workflowId })
            }

            // Fallback: match intent action to workflow by name
            if workflow == nil {
                let intentLower = intent.action.lowercased()
                workflow = WorkflowManager.shared.workflows.first { wf in
                    let nameLower = wf.name.lowercased()
                    // Match if workflow name contains intent action or vice versa
                    return nameLower.contains(intentLower) ||
                           intentLower.contains(nameLower.components(separatedBy: " ").first ?? "") ||
                           (intentLower == "summarize" && nameLower.contains("summary")) ||
                           (intentLower == "todo" && (nameLower.contains("task") || nameLower.contains("todo"))) ||
                           (intentLower == "remind" && nameLower.contains("remind")) ||
                           (intentLower == "note" && nameLower.contains("note"))
                }
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
                _ = try await executeWorkflow(workflow, for: memo, context: coreDataContext)
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
                print("📋 Extracted \(tasks.count) tasks")
            } else {
                // Fallback: store as plain text if JSON parsing fails
                memo.tasks = result.output
                print("⚠️ Could not parse tasks as JSON, storing as text")
            }

        case .reminders:
            // Parse JSON array of reminders
            if let data = result.output.data(using: .utf8),
               let reminders = try? JSONDecoder().decode([ReminderItem].self, from: data) {
                memo.reminders = result.output // Store raw JSON
                print("🔔 Extracted \(reminders.count) reminders")
            } else {
                // Fallback: store as plain text if JSON parsing fails
                memo.reminders = result.output
                print("⚠️ Could not parse reminders as JSON, storing as text")
            }

        case .keyInsights:
            // Parse JSON array of insights
            if let data = result.output.data(using: .utf8),
               let insights = try? JSONDecoder().decode([String].self, from: data) {
                memo.summary = insights.joined(separator: "\n\n") // Store in summary field
                print("💡 Extracted \(insights.count) insights")
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
