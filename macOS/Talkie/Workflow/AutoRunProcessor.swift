//
//  AutoRunProcessor.swift
//  Talkie macOS
//
//  Processes auto-run workflows for synced memos.
//  Replaces the hardcoded TriggerPipeline with a workflow-native approach.
//
//  Flow: Sync → AutoRunProcessor → Execute autoRun workflows → Trigger steps handle gating
//

import Foundation
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie-os-mac", category: "AutoRunProcessor")

// MARK: - Auto-Run Processor

@MainActor
class AutoRunProcessor: ObservableObject {
    static let shared = AutoRunProcessor()

    @Published var isProcessing = false
    @Published var lastProcessedMemoId: UUID?
    @Published var processedCount = 0

    private init() {}

    // MARK: - Main Entry Point

    /// Process a newly synced memo through all enabled auto-run workflows
    func processNewMemo(_ memo: VoiceMemo, context: NSManagedObjectContext) async {
        // Check if auto-run workflows are globally enabled
        guard SettingsManager.shared.autoRunWorkflowsEnabled else {
            logger.info("AutoRunProcessor: Auto-run workflows disabled, skipping")
            return
        }

        // Check if memo has already been processed
        if memo.autoProcessed {
            logger.info("AutoRunProcessor: Memo '\(memo.title ?? "Untitled")' already processed, skipping")
            return
        }

        // Check if memo has a transcript to process
        guard let transcript = memo.currentTranscript, !transcript.isEmpty else {
            logger.info("AutoRunProcessor: No transcript for memo '\(memo.title ?? "Untitled")', skipping")
            return
        }

        isProcessing = true
        defer {
            isProcessing = false
            processedCount += 1
        }

        logger.info("AutoRunProcessor: Processing memo '\(memo.title ?? "Untitled")'")
        await SystemEventManager.shared.log(.workflow, "Auto-run processing started", detail: memo.title)

        // Get all enabled auto-run workflows, sorted by order
        let autoRunWorkflows = getAutoRunWorkflows()

        if autoRunWorkflows.isEmpty {
            logger.info("AutoRunProcessor: No auto-run workflows configured")
            // Still mark as processed to avoid re-processing
            markMemoAsProcessed(memo, context: context)
            return
        }

        logger.info("AutoRunProcessor: Found \(autoRunWorkflows.count) auto-run workflow(s)")

        // Execute each auto-run workflow
        var successCount = 0
        var failureCount = 0

        for workflow in autoRunWorkflows {
            do {
                logger.info("AutoRunProcessor: Executing workflow '\(workflow.name)'")
                _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo, context: context)
                successCount += 1
                logger.info("AutoRunProcessor: Workflow '\(workflow.name)' completed successfully")
            } catch is WorkflowExecutor.TriggerNotMatchedError {
                // This is expected for trigger-based workflows - not a failure
                logger.info("AutoRunProcessor: Workflow '\(workflow.name)' trigger not matched, skipping")
            } catch {
                failureCount += 1
                logger.error("AutoRunProcessor: Workflow '\(workflow.name)' failed: \(error.localizedDescription)")
                await SystemEventManager.shared.log(
                    .error,
                    "Auto-run workflow failed",
                    detail: "\(workflow.name): \(error.localizedDescription)"
                )
            }
        }

        // Mark memo as processed
        markMemoAsProcessed(memo, context: context)
        lastProcessedMemoId = memo.id

        // Log summary
        let summary = "Auto-run complete: \(successCount) succeeded, \(failureCount) failed"
        logger.info("AutoRunProcessor: \(summary)")
        await SystemEventManager.shared.log(.workflow, summary, detail: memo.title)
    }

    // MARK: - Helpers

    /// Get all enabled auto-run workflows, sorted by execution order
    private func getAutoRunWorkflows() -> [WorkflowDefinition] {
        var workflows = WorkflowManager.shared.workflows
            .filter { $0.autoRun && $0.isEnabled }
            .sorted { $0.autoRunOrder < $1.autoRunOrder }

        // If no user-configured auto-run workflows, check if default Hey Talkie should be used
        if workflows.isEmpty {
            // Check if user has explicitly disabled the default workflow
            let hasHeyTalkie = WorkflowManager.shared.workflows.contains {
                $0.id == WorkflowDefinition.heyTalkieWorkflowId
            }

            // If Hey Talkie isn't in the list at all, add the default
            if !hasHeyTalkie {
                workflows = [WorkflowDefinition.heyTalkie]
                logger.info("AutoRunProcessor: Using default Hey Talkie workflow")
            }
        }

        return workflows
    }

    /// Mark a memo as having been processed by auto-run workflows
    private func markMemoAsProcessed(_ memo: VoiceMemo, context: NSManagedObjectContext) {
        memo.autoProcessed = true
        do {
            try context.save()
            logger.info("AutoRunProcessor: Marked memo as processed")
        } catch {
            logger.error("AutoRunProcessor: Failed to save processed status: \(error.localizedDescription)")
        }
    }

    // MARK: - Manual Trigger

    /// Manually re-process a memo (ignores autoProcessed flag)
    func reprocessMemo(_ memo: VoiceMemo, context: NSManagedObjectContext) async {
        // Temporarily clear the processed flag
        let wasProcessed = memo.autoProcessed
        memo.autoProcessed = false

        await processNewMemo(memo, context: context)

        // If it wasn't processed before but failed now, restore the flag
        if !wasProcessed && !memo.autoProcessed {
            memo.autoProcessed = false
        }
    }

    /// Run a specific workflow on a memo (for testing/manual execution)
    func runWorkflow(_ workflow: WorkflowDefinition, on memo: VoiceMemo, context: NSManagedObjectContext) async throws {
        logger.info("AutoRunProcessor: Manual run of '\(workflow.name)' on '\(memo.title ?? "Untitled")'")
        _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo, context: context)
    }
}
