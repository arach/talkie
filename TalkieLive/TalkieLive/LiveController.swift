import Foundation
import AppKit
import os.log
import TalkieCore
import TalkieServices

private let logger = Logger(subsystem: "jdi.talkie.live", category: "LiveController")

enum LiveState: String {
    case idle
    case listening
    case transcribing
    case routing
}

@MainActor
final class LiveController: ObservableObject {
    @Published private(set) var state: LiveState = .idle {
        didSet {
            logger.info("State: \(oldValue.rawValue) → \(self.state.rawValue)")
        }
    }

    private let audio: LiveAudioCapture
    private let transcription: any TranscriptionService
    private let router: LiveRouter

    // Metadata captured at recording start
    private var recordingStartTime: Date?
    private var capturedContext: UtteranceMetadata?
    private var createdInTalkieView: Bool = false  // Was Talkie Live frontmost when recording started?
    private var startApp: NSRunningApplication?  // App where recording started (for return-to-origin)

    init(
        audio: LiveAudioCapture,
        transcription: any TranscriptionService,
        router: LiveRouter
    ) {
        self.audio = audio
        self.transcription = transcription
        self.router = router
        logger.info("LiveController initialized")
    }

    func toggleListening() async {
        switch state {
        case .idle:
            await start()
        case .listening:
            stop()
        case .transcribing, .routing:
            // Don't interrupt processing
            break
        }
    }

    /// Cancel without processing (user pressed X)
    func cancelListening() {
        guard state == .listening else { return }
        audio.stopCapture()
        recordingStartTime = nil
        capturedContext = nil
        startApp = nil
        state = .idle
        logger.info("Recording cancelled")
    }

    /// Get the start app for return-to-origin feature
    func getStartApp() -> NSRunningApplication? {
        return startApp
    }

    private func start() async {
        // Check if Talkie Live is frontmost BEFORE capturing context
        // This determines if the Live goes into the implicit queue
        createdInTalkieView = ContextCapture.isTalkieLiveFrontmost()

        // Store the start app for potential return-to-origin after paste
        startApp = ContextCapture.getFrontmostApp()

        // Capture context BEFORE recording starts (user is in their target app)
        capturedContext = ContextCapture.captureCurrentContext()
        recordingStartTime = Date()

        // Log context capture
        let appName = capturedContext?.activeAppName ?? "Unknown"
        let windowTitle = capturedContext?.activeWindowTitle ?? ""
        let queueNote = createdInTalkieView ? " [will queue]" : ""
        SystemEventManager.shared.log(.system, "Context captured", detail: "\(appName) — \(windowTitle.prefix(30))\(queueNote)")

        // Play start sound
        SoundManager.shared.playStart()
        SystemEventManager.shared.log(.audio, "Recording started", detail: "Listening for audio input...")

        // Track milestone
        ProcessingMilestones.shared.markRecordingStarted()

        state = .listening
        audio.startCapture { [weak self] buffer in
            Task { [weak self] in
                await self?.process(buffer: buffer)
            }
        }
    }

    private func stop() {
        audio.stopCapture()
        // Don't set state to idle - let process() handle state transitions
    }

    private func process(buffer: Data) async {
        let settings = LiveSettings.shared

        // Capture end context IMMEDIATELY when recording stops
        // This captures where the user is NOW (may be different from start)
        if var context = capturedContext {
            ContextCapture.fillEndContext(in: &context)
            capturedContext = context

            // Log if context changed
            if context.contextChanged {
                let startApp = context.activeAppName ?? "?"
                let endApp = context.endAppName ?? "?"
                SystemEventManager.shared.log(.system, "Context changed", detail: "\(startApp) → \(endApp)")
            }
        }

        // Calculate recording duration
        let durationSeconds: Double?
        if let start = recordingStartTime {
            durationSeconds = Date().timeIntervalSince(start)
        } else {
            durationSeconds = nil
        }

        // Play finish sound (recording stopped, now processing)
        SoundManager.shared.playFinish()

        // Track milestone
        ProcessingMilestones.shared.markRecordingStopped()

        // Detailed audio info
        let audioSizeKB = Double(buffer.count) / 1024.0
        let durationStr = durationSeconds.map { String(format: "%.1fs", $0) } ?? "?"
        SystemEventManager.shared.log(.audio, "Recording finished", detail: "\(durationStr) • \(String(format: "%.1f", audioSizeKB)) KB")

        // CRITICAL: Save audio FIRST before anything else
        // This ensures the recording is sacrosanct even if transcription fails
        let audioFilename = AudioStorage.save(buffer)
        if let filename = audioFilename {
            let fileSizeStr = String(format: "%.1f KB", audioSizeKB)
            SystemEventManager.shared.log(.file, "Audio saved", detail: "\(filename) (\(fileSizeStr))")
            // Update milestone for status bar
            ProcessingMilestones.shared.markFileSaved(filename: filename)
        } else {
            SystemEventManager.shared.log(.error, "Audio save failed", detail: "Could not write audio file")
        }

        state = .transcribing
        let transcriptionStart = Date()

        // Log transcription start with model info
        let modelName = settings.whisperModel.rawValue
        SystemEventManager.shared.log(.transcription, "Transcribing...", detail: "Model: \(modelName)")

        // Track milestone
        ProcessingMilestones.shared.markTranscribing()

        do {
            let request = TranscriptionRequest(audioData: buffer, isLive: true)
            let result = try await transcription.transcribe(request)

            let transcriptionMs = Int(Date().timeIntervalSince(transcriptionStart) * 1000)
            let transcriptionSec = Double(transcriptionMs) / 1000.0
            let wordCount = result.text.split(separator: " ").count

            // Calculate real-time factor (RTF) - how many seconds to process 1 second of audio
            let rtfStr: String
            if let audioDuration = durationSeconds, audioDuration > 0 {
                let rtf = transcriptionSec / audioDuration
                rtfStr = String(format: "%.1fx", rtf)
            } else {
                rtfStr = "?"
            }

            // Log transcription result with detailed stats
            let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", transcriptionSec)
            SystemEventManager.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • RTF: \(rtfStr)")

            // Track milestone
            ProcessingMilestones.shared.markTranscriptionComplete(wordCount: wordCount)

            // Build complete metadata
            var metadata = capturedContext ?? UtteranceMetadata()
            metadata.whisperModel = settings.whisperModel.rawValue
            metadata.transcriptionDurationMs = transcriptionMs
            metadata.routingMode = settings.routingMode.rawValue
            metadata.audioFilename = audioFilename

            state = .routing

            // Track milestone
            ProcessingMilestones.shared.markRouting()

            // Decide: queue or paste immediately?
            if createdInTalkieView {
                // Created inside Talkie Live → queue it (don't paste)
                SystemEventManager.shared.log(.system, "Queueing transcript", detail: "Created in Talkie Live")

                // Play a different sound for queued (reuse pasted for now)
                SoundManager.shared.playPasted()
                SystemEventManager.shared.log(.ui, "Transcript queued", detail: "\(result.text.prefix(40))...")

                // Store in GRDB with createdInTalkieView = true, pasteTimestamp = nil
                let utterance = LiveUtterance(
                    text: result.text,
                    mode: "queued",
                    appBundleID: metadata.activeAppBundleID,
                    appName: metadata.activeAppName,
                    windowTitle: metadata.activeWindowTitle,
                    durationSeconds: durationSeconds,
                    whisperModel: metadata.whisperModel,
                    transcriptionMs: transcriptionMs,
                    audioFilename: audioFilename,
                    createdInTalkieView: true,
                    pasteTimestamp: nil  // Not pasted yet → queued
                )
                PastLivesDatabase.store(utterance)

            } else {
                // Normal flow: paste immediately
                let routingMode = settings.routingMode == .paste ? "Paste" : "Clipboard"
                SystemEventManager.shared.log(.system, "Routing transcript", detail: "\(routingMode) mode")

                await router.handle(transcript: result.text)
                metadata.wasRouted = true

                // Play pasted sound
                SoundManager.shared.playPasted()
                SystemEventManager.shared.log(.ui, "Text delivered", detail: "\(result.text.prefix(40))...")

                // Return to origin app if enabled and context changed
                if settings.returnToOriginAfterPaste,
                   let originApp = startApp,
                   metadata.contextChanged {
                    // Small delay to let paste complete
                    try? await Task.sleep(for: .milliseconds(100))
                    ContextCapture.activateApp(originApp)
                    SystemEventManager.shared.log(.system, "Returned to origin", detail: originApp.localizedName ?? "Unknown")
                }

                // Store in GRDB with pasteTimestamp = now (already pasted)
                let utterance = LiveUtterance(
                    text: result.text,
                    mode: settings.routingMode == .paste ? "paste" : "clipboard",
                    appBundleID: metadata.activeAppBundleID,
                    appName: metadata.activeAppName,
                    windowTitle: metadata.activeWindowTitle,
                    durationSeconds: durationSeconds,
                    whisperModel: metadata.whisperModel,
                    transcriptionMs: transcriptionMs,
                    audioFilename: audioFilename,
                    createdInTalkieView: false,
                    pasteTimestamp: Date()  // Already pasted
                )
                PastLivesDatabase.store(utterance)
            }

            let dbRecordCount = PastLivesDatabase.count()
            SystemEventManager.shared.log(.database, "Record stored", detail: "Total: \(dbRecordCount) utterances")

            // Track milestone
            ProcessingMilestones.shared.markDbRecordStored()

            // Also update legacy store for UI (until we migrate)
            UtteranceStore.shared.add(
                result.text,
                durationSeconds: durationSeconds,
                metadata: metadata
            )

            // Final success log
            SystemEventManager.shared.log(.system, "Pipeline complete", detail: "Ready for next recording")

            // Track final milestone
            ProcessingMilestones.shared.markSuccess()

        } catch {
            logger.error("Transcription error: \(error.localizedDescription)")
            SystemEventManager.shared.log(.error, "Transcription failed", detail: error.localizedDescription)

            // Even on failure, we saved the audio - log this for user awareness
            if let filename = audioFilename {
                SystemEventManager.shared.log(.file, "Audio preserved", detail: "\(filename) - retry transcription available")
            }
        }

        recordingStartTime = nil
        capturedContext = nil
        createdInTalkieView = false
        state = .idle
    }
}
