//
//  AutoRunProcessor.swift
//  Talkie macOS
//
//  Processes auto-run workflows for synced memos.
//  MIGRATED: Now uses GRDB via LocalRepository instead of Core Data.
//
//  Flow: Sync → AutoRunProcessor → Execute autoRun workflows → Trigger steps handle gating
//

import Foundation
import os
import Observation
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "AutoRunProcessor")

// MARK: - Auto-Run Processor

@MainActor
@Observable
class AutoRunProcessor {
    static let shared = AutoRunProcessor()

    var isProcessing = false
    var lastProcessedMemoId: UUID?
    var processedCount = 0

    private let repository = LocalRepository()

    private init() {}

    // MARK: - Main Entry Point

    /// Process a newly synced memo through all enabled auto-run workflows
    /// Workflow execution order:
    /// 1. Transcription workflows (run even without existing transcript - they only need audio)
    /// 2. Post-transcription workflows (run after transcript exists)
    func processNewMemo(_ memo: MemoModel) async {
        let memoTitle = memo.displayTitle

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
            await markMemoAsProcessed(memo)
            return
        }

        // Log which workflows will be considered
        let workflowNames = autoRunWorkflows.map { $0.name }.joined(separator: ", ")
        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Found \(autoRunWorkflows.count) workflow(s)", detail: workflowNames)

        // TODO: Filter out workflows that have already run on this memo (deduplication)
        // This would need workflow run tracking in GRDB

        let hasAudio = memo.audioFilePath != nil
        let hasTranscript = memo.transcription != nil && !memo.transcription!.isEmpty

        // Split workflows: transcription-first vs post-transcription
        let (transcriptionWorkflows, postTranscriptionWorkflows) = partitionWorkflows(autoRunWorkflows)

        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Workflow split", detail: "\(transcriptionWorkflows.count) transcription, \(postTranscriptionWorkflows.count) post-transcription")

        var successCount = 0
        var failureCount = 0

        // PHASE 1: Run transcription workflows first (only need audio data)
        if !transcriptionWorkflows.isEmpty && hasAudio {
            logger.info("AutoRunProcessor: Running \(transcriptionWorkflows.count) transcription workflow(s)")
            await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] PHASE 1: Transcription", detail: "Running \(transcriptionWorkflows.count) workflow(s)")

            for workflow in transcriptionWorkflows {
                do {
                    logger.info("AutoRunProcessor: Executing transcription workflow '\(workflow.name)'")
                    await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Executing: \(workflow.name)", detail: "Transcription workflow starting...")
                    _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo)
                    successCount += 1
                    logger.info("AutoRunProcessor: Workflow '\(workflow.name)' completed successfully")
                    await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Completed: \(workflow.name)", detail: "Success")
                } catch {
                    failureCount += 1
                    logger.error("AutoRunProcessor: Workflow '\(workflow.name)' failed: \(error.localizedDescription)")
                    await SystemEventManager.shared.log(.error, "[AUTO-RUN] Failed: \(workflow.name)", detail: error.localizedDescription)
                }
            }
        }

        // PHASE 2: Run post-transcription workflows (need transcript to exist)
        if !postTranscriptionWorkflows.isEmpty {
            // Refresh memo to pick up any new transcript
            let refreshedMemo = (try? await repository.fetchMemo(id: memo.id)?.memo) ?? memo
            let currentHasTranscript = refreshedMemo.transcription != nil && !refreshedMemo.transcription!.isEmpty

            if currentHasTranscript {
                logger.info("AutoRunProcessor: Running \(postTranscriptionWorkflows.count) post-transcription workflow(s)")
                await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] PHASE 2: Post-transcription", detail: "Running \(postTranscriptionWorkflows.count) workflow(s)")

                for workflow in postTranscriptionWorkflows {
                    do {
                        logger.info("AutoRunProcessor: Executing workflow '\(workflow.name)'")
                        await SystemEventManager.shared.log(.workflow, "[AUTO-RUN] Executing: \(workflow.name)", detail: "Post-transcription workflow starting...")
                        _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: refreshedMemo)
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
            await markMemoAsProcessed(memo)
            lastProcessedMemoId = memo.id
        }

        let summary = "[AUTO-RUN] COMPLETE: \(successCount) succeeded, \(failureCount) failed"
        logger.info("AutoRunProcessor: \(summary)")
        await SystemEventManager.shared.log(.workflow, summary, detail: "Memo: '\(memoTitle)'")
    }

    /// Legacy method for Core Data VoiceMemo - converts to MemoModel
    @available(*, deprecated, message: "Use processNewMemo(_ memo: MemoModel) instead")
    func processNewMemo(_ memo: Any, context: Any) async {
        // Try to convert if it's a VoiceMemo-like object with an ID
        if let idProvider = memo as? (any Identifiable) {
            if let uuid = idProvider.id as? UUID {
                // Fetch from GRDB
                if let memoWithFiles = try? await repository.fetchMemo(id: uuid) {
                    await processNewMemo(memoWithFiles.memo)
                    return
                }
            }
        }
        logger.warning("processNewMemo(VoiceMemo) called but could not convert - workflows skipped")
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
        // Use WorkflowService's autoRunWorkflows (already sorted by autoRunOrder)
        var workflows = WorkflowService.shared.autoRunWorkflows.map { $0.definition }

        // If no user-configured auto-run workflows, check if default Hey Talkie should be used
        if workflows.isEmpty {
            // Check if user has explicitly disabled the default workflow
            let hasHeyTalkie = WorkflowService.shared.workflow(byID: WorkflowDefinition.heyTalkieWorkflowId) != nil

            // If Hey Talkie isn't in the list at all, add the default
            if !hasHeyTalkie {
                workflows = [WorkflowDefinition.heyTalkie]
                logger.info("AutoRunProcessor: Using default Hey Talkie workflow")
            }
        }

        return workflows
    }

    /// Mark a memo as having been processed by auto-run workflows
    private func markMemoAsProcessed(_ memo: MemoModel) async {
        var updatedMemo = memo
        updatedMemo.autoProcessed = true
        do {
            try await repository.saveMemo(updatedMemo)
            logger.info("AutoRunProcessor: Marked memo as processed")
        } catch {
            logger.error("AutoRunProcessor: Failed to save processed status: \(error.localizedDescription)")
        }
    }

    // MARK: - Manual Trigger

    /// Manually re-process a memo (ignores autoProcessed flag)
    func reprocessMemo(_ memo: MemoModel) async {
        // Temporarily clear the processed flag
        var mutableMemo = memo
        mutableMemo.autoProcessed = false

        await processNewMemo(mutableMemo)
    }

    /// Run a specific workflow on a MemoModel
    func runWorkflow(_ workflow: WorkflowDefinition, on memo: MemoModel) async throws {
        logger.info("AutoRunProcessor: Manual run of '\(workflow.name)' on '\(memo.displayTitle)'")
        _ = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo)
    }
}
