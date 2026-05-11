//
//  QuickActionRunner.swift
//  TalkieAgent
//
//  Executes Quick Actions on Live utterances
//  Quick Actions are the primary promotion mechanism
//

import Foundation
import AppKit
import TalkieKit

private let log = Log(.system)

// MARK: - Quick Action Runner

@MainActor
final class QuickActionRunner {
    static let shared = QuickActionRunner()

    private init() {}

    /// Execute a quick action on a Live utterance
    func run(_ action: QuickActionKind, for live: LiveDictation) async {
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"
        log.info("[QuickAction] Running action: \(action.displayName) for Live \(idDesc)")
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
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"
        log.info("[QuickAction] Typed text again for Live \(idDesc)")
        AppLogger.shared.log(.ui, "Text typed", detail: "\(live.text.prefix(40))...")
    }

    private func copyToClipboard(_ live: LiveDictation) {
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"

        // Use safe pasteboard pattern (main thread + declareTypes instead of clearContents)
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)

        guard pasteboard.setString(live.text, forType: .string) else {
            log.error("[QuickAction] Failed to copy to clipboard for Live \(idDesc)")
            AppLogger.shared.log(.error, "Copy failed", detail: "Pasteboard error")
            return
        }

        log.info("[QuickAction] Copied to clipboard for Live \(idDesc)")
        AppLogger.shared.log(.ui, "Copied", detail: "\(live.wordCount ?? 0) words")
    }

    private func retryTranscription(_ live: LiveDictation) async {
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"

        guard live.hasAudio, let audioURL = live.audioURL else {
            log.error("[QuickAction] No audio file for Live \(idDesc)")
            AppLogger.shared.log(.error, "Retry failed", detail: "No audio file available")
            return
        }

        // TODO: Re-transcribe from the saved audio file
        // This will need access to the transcription service
        log.info("[QuickAction] Retry transcription requested for Live \(idDesc)")
        AppLogger.shared.log(.transcription, "Retry requested", detail: audioURL.lastPathComponent)
    }

    // MARK: - Promote-to-Memo Actions

    private func promoteToMemo(_ live: LiveDictation) async {
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"

        guard live.canPromote else {
            log.warning("[QuickAction] Live \(idDesc) already promoted")
            return
        }

        guard let recordingUUID = live.recordingUUID else {
            log.error("[QuickAction] Live has no recordingUUID, cannot promote to memo")
            return
        }

        // TODO: Create memo via TalkieBridge when available
        // For now, generate a placeholder memo ID
        let memoID = "memo_\(UUID().uuidString.prefix(8))"

        // Mark as promoted in database
        UnifiedDatabase.markAsMemo(id: recordingUUID, talkieMemoID: memoID)

        log.info("[QuickAction] Promoted Live \(idDesc) to memo: \(memoID)")
        AppLogger.shared.log(.database, "Promoted to memo", detail: memoID)
    }

    private func createResearchMemo(_ live: LiveDictation) async {
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"

        guard live.canPromote else {
            log.warning("[QuickAction] Live \(idDesc) already promoted")
            return
        }

        guard let recordingUUID = live.recordingUUID else {
            log.error("[QuickAction] Live has no recordingUUID, cannot create research memo")
            return
        }

        // TODO: Create research memo with additional context
        let memoID = "research_\(UUID().uuidString.prefix(8))"

        UnifiedDatabase.markAsMemo(id: recordingUUID, talkieMemoID: memoID)

        log.info("[QuickAction] Created research memo from Live \(idDesc): \(memoID)")
        AppLogger.shared.log(.database, "Research memo created", detail: memoID)
    }

    // MARK: - Promote-to-Command Actions

    private func sendToClaude(_ live: LiveDictation) async {
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"

        guard live.canPromote else {
            log.warning("[QuickAction] Live \(idDesc) already promoted")
            return
        }

        guard let recordingUUID = live.recordingUUID else {
            log.error("[QuickAction] Live has no recordingUUID, cannot send to Claude")
            return
        }

        // TODO: Create command via CommandLedger when available
        let commandID = "claude_\(UUID().uuidString.prefix(8))"

        UnifiedDatabase.markAsCommand(id: recordingUUID, commandID: commandID)

        log.info("[QuickAction] Sent Live \(idDesc) to Claude: \(commandID)")
        AppLogger.shared.log(.system, "Sent to Claude", detail: commandID)
    }

    private func runWorkflow(_ live: LiveDictation) async {
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"

        guard live.canPromote else {
            log.warning("[QuickAction] Live \(idDesc) already promoted")
            return
        }

        guard let recordingUUID = live.recordingUUID else {
            log.error("[QuickAction] Live has no recordingUUID, cannot run workflow")
            return
        }

        // TODO: Launch workflow picker or default workflow
        let commandID = "workflow_\(UUID().uuidString.prefix(8))"

        UnifiedDatabase.markAsCommand(id: recordingUUID, commandID: commandID)

        log.info("[QuickAction] Started workflow for Live \(idDesc): \(commandID)")
        AppLogger.shared.log(.system, "Workflow started", detail: commandID)
    }

    // MARK: - Meta Actions

    private func markIgnored(_ live: LiveDictation) {
        let idDesc = live.recordingUUID?.uuidString.prefix(8) ?? "no-uuid"

        guard let recordingUUID = live.recordingUUID else {
            log.error("[QuickAction] Live has no recordingUUID, cannot mark as ignored")
            return
        }

        UnifiedDatabase.markAsIgnored(id: recordingUUID)
        log.info("[QuickAction] Marked Live \(idDesc) as ignored")
        AppLogger.shared.log(.database, "Marked ignored", detail: "Live \(idDesc)")
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
