//
//  QuickActionRunner.swift
//  TalkieLive
//
//  Executes Quick Actions on Live utterances
//  Quick Actions are the primary promotion mechanism
//

import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "QuickAction")

// MARK: - Quick Action Runner

@MainActor
final class QuickActionRunner {
    static let shared = QuickActionRunner()

    private init() {}

    /// Execute a quick action on a Live utterance
    func run(_ action: QuickActionKind, for live: LiveUtterance) async {
        logger.info("Running action: \(action.displayName) for Live #\(live.id ?? 0)")
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

    private func typeAgain(_ live: LiveUtterance) async {
        // Use the existing TranscriptRouter to type the text
        let router = TranscriptRouter(mode: .paste)
        await router.handle(transcript: live.text)
        logger.info("Typed text again for Live #\(live.id ?? 0)")
        AppLogger.shared.log(.ui, "Text typed", detail: "\(live.text.prefix(40))...")
    }

    private func copyToClipboard(_ live: LiveUtterance) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(live.text, forType: .string)
        logger.info("Copied to clipboard for Live #\(live.id ?? 0)")
        AppLogger.shared.log(.ui, "Copied", detail: "\(live.wordCount ?? 0) words")
    }

    private func retryTranscription(_ live: LiveUtterance) async {
        guard live.hasAudio, let audioURL = live.audioURL else {
            logger.error("No audio file for Live #\(live.id ?? 0)")
            AppLogger.shared.log(.error, "Retry failed", detail: "No audio file available")
            return
        }

        // TODO: Re-transcribe from the saved audio file
        // This will need access to the transcription service
        logger.info("Retry transcription requested for Live #\(live.id ?? 0)")
        AppLogger.shared.log(.transcription, "Retry requested", detail: audioURL.lastPathComponent)
    }

    // MARK: - Promote-to-Memo Actions

    private func promoteToMemo(_ live: LiveUtterance) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.id ?? 0) already promoted")
            return
        }

        // TODO: Create memo via TalkieBridge when available
        // For now, generate a placeholder memo ID
        let memoID = "memo_\(UUID().uuidString.prefix(8))"

        // Mark as promoted in database
        LiveDatabase.markAsMemo(id: live.id, talkieMemoID: memoID)

        logger.info("Promoted Live #\(live.id ?? 0) to memo: \(memoID)")
        AppLogger.shared.log(.database, "Promoted to memo", detail: memoID)
    }

    private func createResearchMemo(_ live: LiveUtterance) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.id ?? 0) already promoted")
            return
        }

        // TODO: Create research memo with additional context
        let memoID = "research_\(UUID().uuidString.prefix(8))"

        LiveDatabase.markAsMemo(id: live.id, talkieMemoID: memoID)

        logger.info("Created research memo from Live #\(live.id ?? 0): \(memoID)")
        AppLogger.shared.log(.database, "Research memo created", detail: memoID)
    }

    // MARK: - Promote-to-Command Actions

    private func sendToClaude(_ live: LiveUtterance) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.id ?? 0) already promoted")
            return
        }

        // TODO: Create command via CommandLedger when available
        let commandID = "claude_\(UUID().uuidString.prefix(8))"

        LiveDatabase.markAsCommand(id: live.id, commandID: commandID)

        logger.info("Sent Live #\(live.id ?? 0) to Claude: \(commandID)")
        AppLogger.shared.log(.system, "Sent to Claude", detail: commandID)
    }

    private func runWorkflow(_ live: LiveUtterance) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.id ?? 0) already promoted")
            return
        }

        // TODO: Launch workflow picker or default workflow
        let commandID = "workflow_\(UUID().uuidString.prefix(8))"

        LiveDatabase.markAsCommand(id: live.id, commandID: commandID)

        logger.info("Started workflow for Live #\(live.id ?? 0): \(commandID)")
        AppLogger.shared.log(.system, "Workflow started", detail: commandID)
    }

    // MARK: - Meta Actions

    private func markIgnored(_ live: LiveUtterance) {
        LiveDatabase.markAsIgnored(id: live.id)
        logger.info("Marked Live #\(live.id ?? 0) as ignored")
        AppLogger.shared.log(.database, "Marked ignored", detail: "Live #\(live.id ?? 0)")
    }
}

// MARK: - Quick Action Extensions

extension QuickActionKind {
    /// Actions available for a given Live (context-aware)
    static func availableActions(for live: LiveUtterance) -> [QuickActionKind] {
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
