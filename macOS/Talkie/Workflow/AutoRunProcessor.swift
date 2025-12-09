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

private let logger = Logger(subsystem: "live.talkie.core", category: "AutoRunProcessor")

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
    /// Workflow execution order:
    /// 1. Transcription workflows (run even without existing transcript - they only need audio)
    /// 2. Post-transcription workflows (run after transcript exists)
    func processNewMemo(_ memo: VoiceMemo, context: NSManagedObjectContext) async {
        let memoTitle = memo.title ?? "Untitled"

        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] New memo synced", detail: "'\(memoTitle)'")

        // Check if auto-run workflows are globally enabled
        guard SettingsManager.shared.autoRunWorkflowsEnabled else {
            logger.info("AutoRunProcessor: Auto-run workflows disabled, skipping")
            await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] SKIPPED - globally disabled", detail: "Check Settings > Workflows > Auto-run")
            return
        }

        // Check if memo has already been processed
        if memo.autoProcessed {
            logger.info("AutoRunProcessor: Memo '\(memoTitle)' already processed, skipping")
            await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] SKIPPED - already processed", detail: "'\(memoTitle)' was processed previously")
            return
        }

        isProcessing = true
        defer {
            isProcessing = false
            processedCount += 1
        }

        logger.info("AutoRunProcessor: Processing memo '\(memoTitle)'")
        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] STARTING", detail: "Processing '\(memoTitle)'")

        // Get all enabled auto-run workflows, sorted by order
        var autoRunWorkflows = getAutoRunWorkflows()

        if autoRunWorkflows.isEmpty {
            logger.info("AutoRunProcessor: No auto-run workflows configured")
            await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] No workflows configured", detail: "Enable auto-run on workflows in Settings")
            markMemoAsProcessed(memo, context: context)
            return
        }

        // Log which workflows will be considered
        let workflowNames = autoRunWorkflows.map { $0.name }.joined(separator: ", ")
        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Found \(autoRunWorkflows.count) workflow(s)", detail: workflowNames)

        // Filter out workflows that have already run on this memo (deduplication)
        var existingRunIds = Set<UUID>()
        if let runs = memo.workflowRuns as? Set<WorkflowRun> {
            for run in runs {
                if let workflowId = run.workflowId {
                    existingRunIds.insert(workflowId)
                }
            }
        }
        let skippedCount = autoRunWorkflows.count
        autoRunWorkflows = autoRunWorkflows.filter { !existingRunIds.contains($0.id) }
        let deduplicatedCount = skippedCount - autoRunWorkflows.count

        if deduplicatedCount > 0 {
            await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Deduplication", detail: "\(deduplicatedCount) workflow(s) already ran on this memo")
        }

        if autoRunWorkflows.isEmpty {
            logger.info("AutoRunProcessor: All auto-run workflows already ran on this memo")
            await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] SKIPPED - all workflows already ran", detail: "No new workflows to execute")
            markMemoAsProcessed(memo, context: context)
            return
        }

        // Split workflows: transcription-first vs post-transcription
        let (transcriptionWorkflows, postTranscriptionWorkflows) = partitionWorkflows(autoRunWorkflows)

        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Workflow split", detail: "\(transcriptionWorkflows.count) transcription, \(postTranscriptionWorkflows.count) post-transcription")

        var successCount = 0
        var failureCount = 0

        // PHASE 1: Run transcription workflows first (only need audio data)
        if !transcriptionWorkflows.isEmpty && memo.audioData != nil {
            logger.info("AutoRunProcessor: Running \(transcriptionWorkflows.count) transcription workflow(s)")
            await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] PHASE 1: Transcription", detail: "Running \(transcriptionWorkflows.count) workflow(s)")

            for workflow in transcriptionWorkflows {
                do {
                    logger.info("AutoRunProcessor: Executing transcription workflow '\(workflow.name)'")
                    await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Executing: \(workflow.name)", detail: "Transcription workflow starting...")
                    _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo, context: context)
                    successCount += 1
                    logger.info("AutoRunProcessor: Workflow '\(workflow.name)' completed successfully")
                    await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Completed: \(workflow.name)", detail: "Success")

                    // Refresh memo to pick up new transcript
                    context.refresh(memo, mergeChanges: true)
                } catch {
                    failureCount += 1
                    logger.error("AutoRunProcessor: Workflow '\(workflow.name)' failed: \(error.localizedDescription)")
                    await SystemEventManager.shared.log(.error, "[AUTO-RUN] Failed: \(workflow.name)", detail: error.localizedDescription)
                }
            }
        }

        // PHASE 2: Run post-transcription workflows (need transcript to exist)
        let hasTranscript = memo.currentTranscript != nil && !memo.currentTranscript!.isEmpty

        if !postTranscriptionWorkflows.isEmpty {
            if hasTranscript {
                logger.info("AutoRunProcessor: Running \(postTranscriptionWorkflows.count) post-transcription workflow(s)")
                await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] PHASE 2: Post-transcription", detail: "Running \(postTranscriptionWorkflows.count) workflow(s)")

                for workflow in postTranscriptionWorkflows {
                    do {
                        logger.info("AutoRunProcessor: Executing workflow '\(workflow.name)'")
                        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Executing: \(workflow.name)", detail: "Post-transcription workflow starting...")
                        _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo, context: context)
                        successCount += 1
                        logger.info("AutoRunProcessor: Workflow '\(workflow.name)' completed successfully")
                        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Completed: \(workflow.name)", detail: "Success")
                    } catch is WorkflowExecutor.TriggerNotMatchedError {
                        logger.info("AutoRunProcessor: Workflow '\(workflow.name)' trigger not matched, skipping")
                        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Skipped: \(workflow.name)", detail: "Trigger condition not matched")
                    } catch {
                        failureCount += 1
                        logger.error("AutoRunProcessor: Workflow '\(workflow.name)' failed: \(error.localizedDescription)")
                        await SystemEventManager.shared.log(.error, "[AUTO-RUN] Failed: \(workflow.name)", detail: error.localizedDescription)
                    }
                }
            } else {
                logger.info("AutoRunProcessor: Skipping \(postTranscriptionWorkflows.count) post-transcription workflow(s) - no transcript available")
                await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] PHASE 2 SKIPPED", detail: "No transcript available for \(postTranscriptionWorkflows.count) workflow(s)")
            }
        }

        // Mark as processed if any workflow succeeded
        if successCount > 0 {
            markMemoAsProcessed(memo, context: context)
            lastProcessedMemoId = memo.id
        }

        let summary = "[AUTO-RUN] COMPLETE: \(successCount) succeeded, \(failureCount) failed"
        logger.info("AutoRunProcessor: \(summary)")
        await SystemEventManager.shared.log(.workflow, summary, detail: "Memo: '\(memoTitle)'")
    }

    /// Partition workflows into transcription-first and post-transcription categories
    /// Transcription workflows start with a Transcribe Audio step
    private func partitionWorkflows(_ workflows: [WorkflowDefinition]) -> (transcription: [WorkflowDefinition], postTranscription: [WorkflowDefinition]) {
        var transcription: [WorkflowDefinition] = []
        var postTranscription: [WorkflowDefinition] = []

        for workflow in workflows {
            if let firstStep = workflow.steps.first, firstStep.type == .transcribe {
                transcription.append(workflow)
            } else {
                postTranscription.append(workflow)
            }
        }

        return (transcription, postTranscription)
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
