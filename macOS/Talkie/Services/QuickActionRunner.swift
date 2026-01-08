//
//  QuickActionRunner.swift
//  TalkieLive
//
//  Executes Quick Actions on Live utterances
//  Quick Actions are the primary promotion mechanism
//

import Foundation
import AppKit
import CoreData
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "QuickAction")

// MARK: - Quick Action Runner

@MainActor
final class QuickActionRunner {
    static let shared = QuickActionRunner()

    private init() {}

    /// Execute a quick action on a Live utterance
    func run(_ action: QuickActionKind, for live: LiveDictation) async {
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

    private func typeAgain(_ live: LiveDictation) async {
        // Use the existing TranscriptRouter to type the text
        let router = TranscriptRouter(mode: .paste)
        await router.handle(transcript: live.text)
        logger.info("Typed text again for Live #\(live.id ?? 0)")
        AppLogger.shared.log(.ui, "Text typed", detail: "\(live.text.prefix(40))...")
    }

    private func copyToClipboard(_ live: LiveDictation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(live.text, forType: .string)
        logger.info("Copied to clipboard for Live #\(live.id ?? 0)")
        AppLogger.shared.log(.ui, "Copied", detail: "\(live.wordCount ?? 0) words")
    }

    private func retryTranscription(_ live: LiveDictation) async {
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

    private func promoteToMemo(_ live: LiveDictation) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.id ?? 0) already promoted")
            return
        }

        // TODO: Ideally this should create memo in GRDB first (source of truth),
        // then let the sync layer propagate to Core Data/CloudKit.
        guard let context = await CoreDataSyncGateway.shared.context else {
            logger.warning("Cannot promote - Core Data not ready")
            return
        }

        // Create new VoiceMemo in CoreData
        let memo = VoiceMemo(context: context)
        memo.id = UUID()

        // Basic content
        memo.title = String(live.text.prefix(100)) // Use first 100 chars as title
        memo.transcription = live.text
        memo.createdAt = live.createdAt
        memo.lastModified = Date()
        memo.duration = live.durationSeconds ?? 0
        memo.sortOrder = Int32(-live.createdAt.timeIntervalSince1970)

        // Origin tracking
        memo.originDeviceId = "live" // Mark as coming from Live dictation

        // Context metadata - store in notes field
        var contextNotes: [String] = []
        if let appName = live.appName {
            contextNotes.append("📱 App: \(appName)")
        }
        if let windowTitle = live.windowTitle {
            contextNotes.append("🪟 Window: \(windowTitle)")
        }
        if let metadata = live.metadata {
            if let browserURL = metadata["browserURL"] {
                contextNotes.append("🌐 URL: \(browserURL)")
            } else if let documentURL = metadata["documentURL"] {
                contextNotes.append("📄 Document: \(documentURL)")
            }
            if let terminalDir = metadata["terminalWorkingDir"] {
                contextNotes.append("💻 Working Dir: \(terminalDir)")
            }
        }

        // Performance metrics
        if let totalMs = live.perfEndToEndMs {
            contextNotes.append("⏱ Latency: \(totalMs)ms")
        }

        // Transcription metadata
        if let model = live.transcriptionModel {
            contextNotes.append("🤖 Model: \(model)")
        }

        if !contextNotes.isEmpty {
            memo.notes = """
            Promoted from Live Dictation

            \(contextNotes.joined(separator: "\n"))

            ---
            Original timestamp: \(live.createdAt.formatted())
            """
        }

        // Copy audio file if it exists
        if let audioFilename = live.audioFilename,
           let sourceURL = live.audioURL,
           FileManager.default.fileExists(atPath: sourceURL.path) {

            // Create destination path in Talkie's storage
            let destDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Talkie/Audio", isDirectory: true)

            // Create directory if needed
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            let destURL = destDir.appendingPathComponent(audioFilename)

            // Copy audio file
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                memo.fileURL = destURL.path
                logger.info("Copied audio file to Talkie storage")
            } catch {
                logger.error("Failed to copy audio: \(error.localizedDescription)")
                // Continue without audio
            }
        }

        // Save to CoreData
        do {
            try context.save()
            let memoID = memo.id?.uuidString ?? "unknown"

            // TODO: Route through TalkieLive XPC - Talkie is read-only
            logger.warning("markAsMemo not implemented - should route through TalkieLive XPC")

            logger.info("Promoted Live #\(live.id ?? 0) to memo: \(memoID)")
            AppLogger.shared.log(.database, "Promoted to memo", detail: String(live.text.prefix(40)))

            // Play success sound
            NSSound.beep()
        } catch {
            logger.error("Failed to save memo: \(error.localizedDescription)")
            AppLogger.shared.log(.error, "Promote failed", detail: error.localizedDescription)
        }
    }

    private func createResearchMemo(_ live: LiveDictation) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.id ?? 0) already promoted")
            return
        }

        // TODO: Create research memo with additional context
        let memoID = "research_\(UUID().uuidString.prefix(8))"

        // TODO: Route through TalkieLive XPC - Talkie is read-only
        logger.warning("markAsMemo not implemented - should route through TalkieLive XPC")

        logger.info("Created research memo from Live #\(live.id ?? 0): \(memoID)")
        AppLogger.shared.log(.database, "Research memo created", detail: memoID)
    }

    // MARK: - Promote-to-Command Actions

    private func sendToClaude(_ live: LiveDictation) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.id ?? 0) already promoted")
            return
        }

        // TODO: Create command via CommandLedger when available
        let commandID = "claude_\(UUID().uuidString.prefix(8))"

        // TODO: Route through TalkieLive XPC - Talkie is read-only
        logger.warning("markAsCommand not implemented - should route through TalkieLive XPC")

        logger.info("Sent Live #\(live.id ?? 0) to Claude: \(commandID)")
        AppLogger.shared.log(.system, "Sent to Claude", detail: commandID)
    }

    private func runWorkflow(_ live: LiveDictation) async {
        guard live.canPromote else {
            logger.warning("Live #\(live.id ?? 0) already promoted")
            return
        }

        // TODO: Launch workflow picker or default workflow
        let commandID = "workflow_\(UUID().uuidString.prefix(8))"

        // TODO: Route through TalkieLive XPC - Talkie is read-only
        logger.warning("markAsCommand not implemented - should route through TalkieLive XPC")

        logger.info("Started workflow for Live #\(live.id ?? 0): \(commandID)")
        AppLogger.shared.log(.system, "Workflow started", detail: commandID)
    }

    // MARK: - Meta Actions

    private func markIgnored(_ live: LiveDictation) {
        // TODO: Route through TalkieLive XPC - Talkie is read-only
        logger.warning("markAsIgnored not implemented - should route through TalkieLive XPC")
        logger.info("Marked Live #\(live.id ?? 0) as ignored")
        AppLogger.shared.log(.database, "Marked ignored", detail: "Live #\(live.id ?? 0)")
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
