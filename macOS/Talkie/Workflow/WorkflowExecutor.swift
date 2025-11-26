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

// MARK: - Workflow Execution Context

struct WorkflowContext {
    var transcript: String
    var title: String
    var date: Date
    var outputs: [String: String] = [:]

    func resolve(_ template: String) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{{TRANSCRIPT}}", with: transcript)
        result = result.replacingOccurrences(of: "{{TITLE}}", with: title)
        result = result.replacingOccurrences(of: "{{DATE}}", with: ISO8601DateFormatter().string(from: date))

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
        guard let transcript = memo.transcription, !transcript.isEmpty else {
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
        } else if let geminiProvider = registry.provider(for: "gemini") {
            // Default to Gemini Flash if available
            provider = geminiProvider
            model = "gemini-1.5-flash-latest"
        } else if let firstProvider = registry.providers.first {
            // Fallback to first available provider
            provider = firstProvider
            model = "gemini-1.5-flash-latest"
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
        guard let transcript = memo.transcription, !transcript.isEmpty else {
            throw WorkflowError.noTranscript
        }

        var workflowContext = WorkflowContext(
            transcript: transcript,
            title: memo.title ?? "Untitled",
            date: memo.createdAt ?? Date()
        )

        // Track provider/model used for the run
        var usedProvider: String?
        var usedModel: String?

        // Track step-by-step execution for detailed view
        var stepExecutions: [StepExecution] = []

        print("🚀 Starting workflow: \(workflow.name)")

        for (index, step) in workflow.steps.enumerated() {
            guard step.isEnabled else {
                print("⏭️ Skipping disabled step \(index + 1)")
                continue
            }

            // Check condition if present
            if let condition = step.condition {
                let resolvedCondition = workflowContext.resolve(condition.expression)
                if !evaluateCondition(resolvedCondition) {
                    if condition.skipOnFail {
                        print("⏭️ Condition not met, skipping step \(index + 1)")
                        continue
                    }
                }
            }

            print("▶️ Executing step \(index + 1): \(step.type.rawValue)")

            // Capture input for this step
            let stepInput: String
            if case .llm(let config) = step.config {
                usedProvider = config.provider.displayName
                usedModel = config.modelId
                stepInput = workflowContext.resolve(config.prompt)
            } else {
                stepInput = workflowContext.transcript
            }

            let output = try await executeStep(step, context: &workflowContext, memo: memo, coreDataContext: context)
            workflowContext.outputs[step.outputKey] = output

            // Record step execution
            stepExecutions.append(StepExecution(
                stepNumber: index + 1,
                stepType: step.type.rawValue,
                stepIcon: step.type.icon,
                input: stepInput,
                output: output,
                outputKey: step.outputKey
            ))

            print("✅ Step \(index + 1) completed")
        }

        print("🎉 Workflow completed: \(workflow.name)")

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

        case .webhook(let config):
            return try await executeWebhookStep(config, context: context, memo: memo)

        case .email(let config):
            return try await executeEmailStep(config, context: context)

        case .notification(let config):
            return try await executeNotificationStep(config, context: context)

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
        }
    }

    // MARK: - LLM Step Execution
    private func executeLLMStep(_ config: LLMStepConfig, context: WorkflowContext) async throws -> String {
        guard let provider = registry.provider(for: config.provider.registryId) else {
            throw WorkflowError.executionFailed("Provider '\(config.provider.displayName)' not found")
        }

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

        return try await provider.generate(
            prompt: fullPrompt,
            model: config.modelId,
            options: options
        )
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
                set theAccount to first account
                set theFolder to folder "\(escapedFolder)" of theAccount
                make new note at theFolder with properties {name:"\(escapedTitle)", body:"<html><body>\(escapedHtmlBody)</body></html>"}
            end tell
            """
        } else {
            script = """
            tell application "Notes"
                activate
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
        let filename = context.resolve(config.filename)
        let content = context.resolve(config.content)

        let directory: URL
        if let customDir = config.directory {
            directory = URL(fileURLWithPath: context.resolve(customDir))
        } else {
            directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }

        let fileURL = directory.appendingPathComponent(filename)

        if config.appendIfExists && FileManager.default.fileExists(atPath: fileURL.path) {
            let existingContent = try String(contentsOf: fileURL, encoding: .utf8)
            try (existingContent + "\n" + content).write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
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
