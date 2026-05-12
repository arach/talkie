//
//  QuickActionRunner.swift
//  TalkieAgent
//
//  Executes Quick Actions on Live utterances
//  Quick Actions are the primary promotion mechanism
//

import Foundation
import AppKit
import CoreData
import os.log
import TalkieKit

private let logger = Logger(subsystem: "to.talkie.app.agent", category: "QuickAction")

// MARK: - Quick Action Runner

@MainActor
final class QuickActionRunner {
    static let shared = QuickActionRunner()

    private init() {}

    /// Execute a quick action on a Live utterance
    func run(_ action: QuickActionKind, for live: LiveDictation) async {
        logger.info("Running action: \(action.displayName) for Live #\(live.recordingID ?? "unknown")")
        AppLogger.shared.log(.system, "Quick Action", detail: action.displayName)

        switch action {
        // Execute-only actions (no promotion)
        case .typeAgain:
            await typeAgain(live)

        case .copyToClipboard:
            copyToClipboard(live)

        case .retryTranscription:
            await retryTranscription(live)

        // Promote-to-memo actions
        case .promoteToMemo:
            await promoteToMemo(live)

        case .createResearchMemo:
            await createResearchMemo(live)

        // Promote-to-command actions
        case .sendToClaude:
            await sendToClaude(live)

        case .runWorkflow:
            await runWorkflow(live)

        // Meta actions
        case .markIgnored:
            markIgnored(live)
        }
    }

    // MARK: - Execute-Only Actions

    private func typeAgain(_ live: LiveDictation) async {
        // Use the existing TranscriptRouter to type the text
        let router = TranscriptRouter(mode: .paste)
        await router.handle(transcript: live.text)
        logger.info("Typed text again for Live #\(live.recordingID ?? "unknown")")
        AppLogger.shared.log(.ui, "Text typed", detail: "\(live.text.prefix(40))...")
    }

    private func copyToClipboard(_ live: LiveDictation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(live.text, forType: .string)
        logger.info("Copied to clipboard for Live #\(live.recordingID ?? "unknown")")
        AppLogger.shared.log(.ui, "Copied", detail: "\(live.wordCount ?? 0) words")
    }

    private func retryTranscription(_ live: LiveDictation) async {
        guard live.hasAudio, let audioURL = live.audioURL else {
            logger.error("No audio file for Live #\(live.recordingID ?? "unknown")")
            AppLogger.shared.log(.error, "Retry failed", detail: "No audio file available")
            return
        }

        // TODO: Re-transcribe from the saved audio file
        // This will need access to the transcription service
        logger.info("Retry transcription requested for Live #\(live.recordingID ?? "unknown")")
        AppLogger.shared.log(.transcription, "Retry requested", detail: audioURL.lastPathComponent)
    }

    // MARK: - Promote-to-Memo Actions

    private func promoteToMemo(_ live: LiveDictation) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.recordingID ?? "unknown") already promoted")
            return
        }

        // Get the recording UUID - required for in-place promotion
        guard let recordingIdString = live.recordingID,
              let recordingId = UUID(uuidString: recordingIdString) else {
            logger.error("Cannot promote: missing or invalid recordingID")
            AppLogger.shared.log(.error, "Promote failed", detail: "Missing recording ID")
            return
        }

        // In-place promotion: changes type from dictation → memo, preserves metadataJSON
        do {
            let repo = TalkieObjectRepository()
            guard let promoted = try await repo.promoteToMemo(id: recordingId) else {
                logger.error("Promote failed: recording not found")
                AppLogger.shared.log(.error, "Promote failed", detail: "Recording not found")
                return
            }

            logger.info("Promoted recording \(recordingId.uuidString.prefix(8)) to memo (in-place)")
            AppLogger.shared.log(.database, "Promoted to memo", detail: String(live.text.prefix(40)))

            NSSound.beep()
        } catch {
            logger.error("Failed to promote: \(error.localizedDescription)")
            AppLogger.shared.log(.error, "Promote failed", detail: error.localizedDescription)
        }
    }

    private func createResearchMemo(_ live: LiveDictation) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.recordingID ?? "unknown") already promoted")
            return
        }

        // TODO: Create research memo with additional context
        let memoID = "research_\(UUID().uuidString.prefix(8))"

        // TODO: Route through TalkieAgent XPC - Talkie is read-only
        logger.warning("markAsMemo not implemented - should route through TalkieAgent XPC")

        logger.info("Created research memo from Live #\(live.recordingID ?? "unknown"): \(memoID)")
        AppLogger.shared.log(.database, "Research memo created", detail: memoID)
    }

    // MARK: - Promote-to-Command Actions

    private func sendToClaude(_ live: LiveDictation) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.recordingID ?? "unknown") already promoted")
            return
        }

        // TODO: Create command via CommandLedger when available
        let commandID = "claude_\(UUID().uuidString.prefix(8))"

        // TODO: Route through TalkieAgent XPC - Talkie is read-only
        logger.warning("markAsCommand not implemented - should route through TalkieAgent XPC")

        logger.info("Sent Live #\(live.recordingID ?? "unknown") to Claude: \(commandID)")
        AppLogger.shared.log(.system, "Sent to Claude", detail: commandID)
    }

    private func runWorkflow(_ live: LiveDictation) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.recordingID ?? "unknown") already promoted")
            return
        }

        // TODO: Launch workflow picker or default workflow
        let commandID = "workflow_\(UUID().uuidString.prefix(8))"

        // TODO: Route through TalkieAgent XPC - Talkie is read-only
        logger.warning("markAsCommand not implemented - should route through TalkieAgent XPC")

        logger.info("Started workflow for Live #\(live.recordingID ?? "unknown"): \(commandID)")
        AppLogger.shared.log(.system, "Workflow started", detail: commandID)
    }

    // MARK: - Meta Actions

    private func markIgnored(_ live: LiveDictation) {
        // TODO: Route through TalkieAgent XPC - Talkie is read-only
        logger.warning("markAsIgnored not implemented - should route through TalkieAgent XPC")
        logger.info("Marked Live #\(live.recordingID ?? "unknown") as ignored")
        AppLogger.shared.log(.database, "Marked ignored", detail: "Live #\(live.recordingID ?? "unknown")")
    }
}

// MARK: - Quick Action Extensions

extension QuickActionKind {
    /// Actions available for a given Live (context-aware)
    static func availableActions(for live: LiveDictation) -> [QuickActionKind] {
        var actions: [QuickActionKind] = []

        // Always available execute-only actions
        actions.append(.copyToClipboard)
        actions.append(.typeAgain)

        // Retry transcription only if audio exists
        if live.hasAudio {
            actions.append(.retryTranscription)
        }

        // Promotion actions only if not already promoted
        if live.canPromote {
            actions.append(.promoteToMemo)
            actions.append(.createResearchMemo)
            actions.append(.sendToClaude)
            actions.append(.runWorkflow)
            actions.append(.markIgnored)
        }

        return actions
    }

    /// Primary actions shown prominently
    static var primaryActions: [QuickActionKind] {
        [.copyToClipboard, .promoteToMemo, .sendToClaude]
    }

    /// Secondary actions shown in overflow menu
    static var secondaryActions: [QuickActionKind] {
        [.typeAgain, .createResearchMemo, .runWorkflow, .markIgnored]
    }
}
