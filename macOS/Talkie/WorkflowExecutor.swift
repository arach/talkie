//
//  WorkflowExecutor.swift
//  talkie
//
//  Executes workflow actions and saves results to Core Data
//

import Foundation
import CoreData

class WorkflowExecutor {
    static let shared = WorkflowExecutor()

    private let geminiService = GeminiService.shared

    private init() {}

    // MARK: - Execute Single Action
    func execute(
        action: WorkflowActionType,
        for memo: VoiceMemo,
        model: AIModel = .geminiFlash,
        context: NSManagedObjectContext
    ) async throws {
        guard let transcript = memo.transcription, !transcript.isEmpty else {
            throw WorkflowError.noTranscript
        }

        // Mark as processing
        await MainActor.run {
            setProcessingState(for: action, memo: memo, isProcessing: true)
            try? context.save()
        }

        do {
            let config = WorkflowConfig(actionType: action, model: model)
            let result = try await geminiService.executeWorkflow(config: config, transcript: transcript)

            // Save result to Core Data
            await MainActor.run {
                saveResult(result, to: memo, context: context)
                setProcessingState(for: action, memo: memo, isProcessing: false)
                try? context.save()
            }

            print("✅ \(action.rawValue) completed successfully")

        } catch {
            // Clear processing state on error
            await MainActor.run {
                setProcessingState(for: action, memo: memo, isProcessing: false)
                try? context.save()
            }
            throw error
        }
    }

    // MARK: - Execute Action Chain
    func executeChain(
        actions: [WorkflowActionType],
        for memo: VoiceMemo,
        model: AIModel = .geminiFlash,
        context: NSManagedObjectContext
    ) async throws {
        for action in actions {
            try await execute(action: action, for: memo, model: model, context: context)
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

    var errorDescription: String? {
        switch self {
        case .noTranscript:
            return "Voice memo must be transcribed before running workflows."
        case .executionFailed(let message):
            return "Workflow execution failed: \(message)"
        }
    }
}
