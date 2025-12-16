import Foundation
import AppKit
import os.log

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
    private var capturedContext: UtteranceMetadata?  // Baseline only - enrichment happens after paste
    private var createdInTalkieView: Bool = false  // Was Talkie Live frontmost when recording started?
    private var routeToInterstitial: Bool = false  // Shift-click: route to Talkie Core interstitial instead of paste
    private var startApp: NSRunningApplication?  // App where recording started (for return-to-origin)
    private var traceID: String?

    // Transcription task - stored so we can cancel it
    private var transcriptionTask: Task<Void, Never>?
    private var pendingAudioFilename: String?  // For saving on cancel

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

    /// Toggle mode: press to start, press to stop
    /// - Parameter interstitial: If true (Shift-click), route to Talkie Core interstitial instead of paste
    func toggleListening(interstitial: Bool = false) async {
        switch state {
        case .idle:
            await start()
        case .listening:
            stop(interstitial: interstitial)
        case .transcribing, .routing:
            // Don't interrupt processing
            break
        }
    }

    // MARK: - Push-to-Talk Mode

    /// PTT start: called when PTT hotkey is pressed down
    func pttStart() async {
        guard state == .idle else {
            logger.info("PTT start ignored - not idle (state=\(self.state.rawValue))")
            return
        }
        logger.info("PTT recording started (key down)")
        await start()
    }

    /// PTT stop: called when PTT hotkey is released
    func pttStop() {
        guard state == .listening else {
            logger.info("PTT stop ignored - not listening (state=\(self.state.rawValue))")
            return
        }
        logger.info("PTT recording stopped (key up)")
        stop()
    }

    /// Cancel without processing (user pressed X)
    /// Works in any active state - sets cancelled flag to prevent paste
    @Published private(set) var isCancelled = false

    /// Cancel recording during listening phase (before transcription starts)
    func cancelListening() {
        guard state == .listening else { return }
        isCancelled = true
        audio.stopCapture()
        recordingStartTime = nil
        capturedContext = nil
        startApp = nil
        pendingAudioFilename = nil
        traceID = nil
        state = .idle
        logger.info("Recording cancelled during listening")
    }

    /// Push current transcription to queue for later retry
    /// Use this when stuck in transcribing state and want to move on
    func pushToQueue() {
        guard state == .transcribing || state == .routing else { return }
        let previousState = state
        isCancelled = true

        // Cancel any in-flight transcription task
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Save the audio file for retry
        if let audioFilename = pendingAudioFilename {
            let utterance = LiveUtterance(
                text: "[Queued for retry]",
                mode: "queued",
                appBundleID: capturedContext?.activeAppBundleID,
                appName: capturedContext?.activeAppName,
                windowTitle: capturedContext?.activeWindowTitle,
                durationSeconds: recordingStartTime.map { Date().timeIntervalSince($0) },
                whisperModel: LiveSettings.shared.selectedModelId,
                metadata: capturedContext.flatMap { buildMetadataDict(from: $0) },
                audioFilename: audioFilename,
                transcriptionStatus: .pending,
                createdInTalkieView: createdInTalkieView,
                pasteTimestamp: nil
            )
            LiveDatabase.store(utterance)
            SystemEventManager.shared.log(.database, "Pushed to queue", detail: "Audio saved for retry")
            SoundManager.shared.playPasted()  // Confirmation sound
        }

        recordingStartTime = nil
        capturedContext = nil
        startApp = nil
        pendingAudioFilename = nil
        traceID = nil
        state = .idle
        logger.info("Pushed to queue (was \(previousState.rawValue))")

        // Refresh the queue count
        UtteranceStore.shared.refresh()
    }

    /// Reset cancelled flag when starting a new recording
    private func resetCancelled() {
        isCancelled = false
    }

    /// Get the start app for return-to-origin feature
    func getStartApp() -> NSRunningApplication? {
        return startApp
    }

    private func start() async {
        // Reset cancelled flag for new recording
        resetCancelled()
        traceID = nil

        // Check if Talkie Live is frontmost BEFORE capturing context
        // This determines if the Live goes into the implicit queue
        createdInTalkieView = ContextCapture.isTalkieLiveFrontmost()

        // Store the start app for potential return-to-origin after paste
        startApp = ContextCapture.getFrontmostApp()

        // Capture baseline context BEFORE recording starts (user is in their target app)
        // This is instant (~1ms) - enrichment happens after paste
        capturedContext = ContextCaptureService.shared.captureBaseline()
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

        // Notify for onboarding celebration (immediate feedback when user presses hotkey)
        NotificationCenter.default.post(name: .recordingDidStart, object: nil)

        state = .listening
        audio.startCapture { [weak self] audioPath in
            Task { [weak self] in
                await self?.process(tempAudioPath: audioPath)
            }
        }
    }

    private func stop(interstitial: Bool = false) {
        NSLog("[LiveController] stop() called with interstitial=\(interstitial)")
        logger.info("stop() called with interstitial=\(interstitial)")
        routeToInterstitial = interstitial
        if interstitial {
            NSLog("[LiveController] Stopping with interstitial routing (Shift-click)")
            logger.info("Stopping with interstitial routing (Shift-click)")
        }
        audio.stopCapture()
        // Don't set state to idle - let process() handle state transitions
    }

    private func process(tempAudioPath: String) async {
        let pipelineStart = Date()  // Track end-to-end timing
        let settings = LiveSettings.shared

        // Helper to log timing milestones
        func logTiming(_ step: String) {
            let ms = Int(Date().timeIntervalSince(pipelineStart) * 1000)
            SystemEventManager.shared.log(.transcription, "⏱ \(step)", detail: "+\(ms)ms")
        }

        logTiming("Pipeline start")

        // CRITICAL: Copy temp audio to permanent storage FIRST before anything else
        // This ensures the recording is sacrosanct even if transcription fails
        // Once copied, the permanent file is NEVER moved or modified - only read or copied
        let tempURL = URL(fileURLWithPath: tempAudioPath)
        guard let audioFilename = AudioStorage.copyToStorage(tempURL) else {
            SystemEventManager.shared.log(.error, "Audio save failed", detail: "Could not copy temp file to storage")
            state = .idle
            return
        }
        logTiming("Audio copied to storage")

        traceID = makeTraceID(from: audioFilename)

        // Store for push-to-queue in case user wants to bail during transcription
        pendingAudioFilename = audioFilename

        // Clean up temp file now that permanent copy is safe
        try? FileManager.default.removeItem(atPath: tempAudioPath)
        logTiming("Temp file cleaned")

        let fileSaveMs = Int(Date().timeIntervalSince(pipelineStart) * 1000)

        // Get size from the permanent file
        let permanentURL = AudioStorage.url(for: audioFilename)
        let audioSizeBytes = (try? permanentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let audioSizeKB = Double(audioSizeBytes) / 1024.0
        let fileSizeStr = String(format: "%.1f KB", audioSizeKB)
        #if DEBUG
        let traceSuffix = traceID.map { " • trace=\($0)" } ?? ""
        #else
        let traceSuffix = ""
        #endif
        SystemEventManager.shared.log(.file, "Audio saved", detail: "\(audioFilename) (\(fileSizeStr)) • \(fileSaveMs)ms\(traceSuffix)")

        // Get permanent path for transcription
        let permanentAudioPath = AudioStorage.url(for: audioFilename).path

        // Update milestone for status bar
        ProcessingMilestones.shared.markFileSaved(filename: audioFilename)
        logTiming("Milestone: file saved")

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
        logTiming("End context captured")

        // Calculate recording duration
        let recordStart = recordingStartTime ?? pipelineStart
        let durationSeconds = Date().timeIntervalSince(recordStart)

        // Play finish sound (recording stopped, now processing)
        SoundManager.shared.playFinish()
        logTiming("Finish sound triggered")

        // Track milestone
        ProcessingMilestones.shared.markRecordingStopped()

        // Detailed audio info
        let durationStr = String(format: "%.1fs", durationSeconds)
        SystemEventManager.shared.log(.audio, "Recording finished", detail: "\(durationStr) • \(fileSizeStr)")

        state = .transcribing
        logTiming("State → transcribing")
        let engineStart = Date()

        // Log transcription start with model info and overhead
        let modelName = settings.selectedModelId
        let preMs = Int(engineStart.timeIntervalSince(pipelineStart) * 1000)  // Time from stop-recording to engine-submit
        SystemEventManager.shared.log(.transcription, "Transcribing...", detail: "Model: \(modelName) • pre: \(preMs)ms\(traceSuffix)")

        // Track milestone
        ProcessingMilestones.shared.markTranscribing()

        do {
            // Pass the permanent audio path - engine reads directly, never modifies
            logTiming("Sending to engine")
            let request = TranscriptionRequest(audioPath: permanentAudioPath, isLive: true)
            let result = try await transcription.transcribe(request)
            logTiming("Engine returned")
            let engineEnd = Date()

            let transcriptionMs = Int(engineEnd.timeIntervalSince(engineStart) * 1000)
            let transcriptionSec = Double(transcriptionMs) / 1000.0
            let wordCount = result.text.split(separator: " ").count
            // preMs already calculated above (time from stop-recording to engine-submit)

            // Track milestone
            ProcessingMilestones.shared.markTranscriptionComplete(wordCount: wordCount)
            logTiming("Milestone: transcription complete")

            // Notify for onboarding (dismiss after first transcription)
            NotificationCenter.default.post(name: .transcriptionDidComplete, object: nil)
            logTiming("NotificationCenter posted")

            // Use baseline metadata immediately - don't block on enrichment
            // Enrichment runs async and can update the record later if needed
            var metadata = capturedContext ?? UtteranceMetadata()
            logTiming("Using baseline metadata (no enrichment wait)")
            metadata.whisperModel = settings.selectedModelId
            metadata.perfEngineMs = transcriptionMs
            metadata.perfPreMs = preMs
            metadata.routingMode = settings.routingMode.rawValue
            metadata.audioFilename = audioFilename
            logTiming("Metadata built")

            // Check if user cancelled during transcription
            if isCancelled {
                logger.info("Recording was cancelled - skipping paste")
                state = .idle
                return
            }

            state = .routing
            logTiming("State → routing")

            // Track milestone
            ProcessingMilestones.shared.markRouting()

            // Interstitial mode: Shift-click to route to Talkie Core for editing
            NSLog("[LiveController] Checking routeToInterstitial flag: \(self.routeToInterstitial)")
            logger.info("Checking routeToInterstitial flag: \(self.routeToInterstitial)")
            if routeToInterstitial {
                NSLog("[LiveController] === INTERSTITIAL MODE ACTIVATED ===")
                logger.info("=== INTERSTITIAL MODE ACTIVATED ===")
                SystemEventManager.shared.log(.system, "Routing to interstitial", detail: "Shift-click mode")

                let routeEnd = Date()
                let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)
                let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                let appMs = max(0, totalMs - transcriptionMs)

                metadata.perfEndToEndMs = totalMs
                metadata.perfInAppMs = appMs
                metadata.perfPreMs = preMs
                metadata.perfPostMs = postMs

                let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", transcriptionSec)
                SystemEventManager.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")

                // Store in GRDB with mode "interstitial", pasteTimestamp = nil
                logTiming("Creating LiveUtterance for interstitial")
                let utterance = LiveUtterance(
                    text: result.text,
                    mode: "interstitial",
                    appBundleID: metadata.activeAppBundleID,
                    appName: metadata.activeAppName,
                    windowTitle: metadata.activeWindowTitle,
                    durationSeconds: durationSeconds,
                    whisperModel: metadata.whisperModel,
                    perfEngineMs: transcriptionMs,
                    perfEndToEndMs: metadata.perfEndToEndMs,
                    perfInAppMs: metadata.perfInAppMs,
                    metadata: buildMetadataDict(from: metadata),
                    audioFilename: audioFilename,
                    createdInTalkieView: createdInTalkieView,
                    pasteTimestamp: nil  // Not pasted yet → interstitial will handle
                )

                if let id = LiveDatabase.store(utterance) {
                    logTiming("Database stored")

                    // Schedule enrichment
                    if let baseline = capturedContext {
                        ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline)
                    }

                    // Launch Talkie Core with interstitial URL
                    launchInterstitialEditor(utteranceId: id)
                    logTiming("Interstitial URL launched")
                }

                // Play sound to confirm
                SoundManager.shared.playPasted()
                logTiming("Sound triggered")

                // Reset flag and finish
                routeToInterstitial = false
                state = .idle
                recordingStartTime = nil
                capturedContext = nil
                startApp = nil
                pendingAudioFilename = nil
                traceID = nil

                // Refresh stores
                UtteranceStore.shared.refresh()
                logTiming("Pipeline complete (interstitial)")
                return
            }

            // Decide: queue or paste immediately?
            if createdInTalkieView {
                // Created inside Talkie Live → queue it (don't paste)
                SystemEventManager.shared.log(.system, "Queueing transcript", detail: "Created in Talkie Live")

                // Play a different sound for queued (reuse pasted for now)
                SoundManager.shared.playPasted()
                logTiming("Pasted sound triggered")
                SystemEventManager.shared.log(.ui, "Transcript queued", detail: "\(result.text.prefix(40))...\(traceSuffix)")

                let routeEnd = Date()
                let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)  // End-to-end: stop-recording → delivery
                let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                let appMs = max(0, totalMs - transcriptionMs)  // App time = total - engine

                metadata.perfEndToEndMs = totalMs
                metadata.perfInAppMs = appMs
                metadata.perfPreMs = preMs
                metadata.perfPostMs = postMs

                let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", transcriptionSec)
                SystemEventManager.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")
                #if DEBUG
                SystemEventManager.shared.log(.transcription, "Latency breakdown", detail: "e2e: \(totalMs)ms • engine: \(transcriptionMs)ms • app: \(appMs)ms (pre: \(preMs)ms, post: \(postMs)ms)\(traceSuffix)")
                #endif

                // Store in GRDB with createdInTalkieView = true, pasteTimestamp = nil
                logTiming("Creating LiveUtterance")
                let utterance = LiveUtterance(
                    text: result.text,
                    mode: "queued",
                    appBundleID: metadata.activeAppBundleID,
                    appName: metadata.activeAppName,
                    windowTitle: metadata.activeWindowTitle,
                    durationSeconds: durationSeconds,
                    whisperModel: metadata.whisperModel,
                    perfEngineMs: transcriptionMs,
                    perfEndToEndMs: metadata.perfEndToEndMs,
                    perfInAppMs: metadata.perfInAppMs,
                    metadata: buildMetadataDict(from: metadata),
                    audioFilename: audioFilename,
                    createdInTalkieView: true,
                    pasteTimestamp: nil  // Not pasted yet → queued
                )
                if let id = LiveDatabase.store(utterance), let baseline = capturedContext {
                    ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline)
                }
                logTiming("Database stored")

            } else {
                // Normal flow: paste immediately
                let routingMode = settings.routingMode == .paste ? "Paste" : "Clipboard"
                SystemEventManager.shared.log(.system, "Routing transcript", detail: "\(routingMode) mode")

                logTiming("Calling router.handle")
                await router.handle(transcript: result.text)
                logTiming("Router finished")
                metadata.wasRouted = true

                // Play pasted sound
                SoundManager.shared.playPasted()
                logTiming("Pasted sound triggered")
                SystemEventManager.shared.log(.ui, "Text delivered", detail: "\(result.text.prefix(40))...\(traceSuffix)")

                let routeEnd = Date()
                let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)  // End-to-end: stop-recording → delivery
                let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                let appMs = max(0, totalMs - transcriptionMs)  // App time = total - engine

                metadata.perfEndToEndMs = totalMs
                metadata.perfInAppMs = appMs
                metadata.perfPreMs = preMs
                metadata.perfPostMs = postMs

                let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", transcriptionSec)
                SystemEventManager.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")
                #if DEBUG
                SystemEventManager.shared.log(.transcription, "Latency breakdown", detail: "e2e: \(totalMs)ms • engine: \(transcriptionMs)ms • app: \(appMs)ms (pre: \(preMs)ms, post: \(postMs)ms)\(traceSuffix)")
                #endif

                // Return to origin app if enabled and context changed
                if settings.returnToOriginAfterPaste,
                   let originApp = startApp,
                   metadata.contextChanged {
                    logTiming("Waiting for paste delay")
                    // Small delay to let paste complete
                    try? await Task.sleep(for: .milliseconds(100))
                    ContextCapture.activateApp(originApp)
                    logTiming("Returned to origin app")
                    SystemEventManager.shared.log(.system, "Returned to origin", detail: originApp.localizedName ?? "Unknown")
                }

                // Store in GRDB with pasteTimestamp = now (already pasted)
                logTiming("Creating LiveUtterance")
                let utterance = LiveUtterance(
                    text: result.text,
                    mode: settings.routingMode == .paste ? "paste" : "clipboard",
                    appBundleID: metadata.activeAppBundleID,
                    appName: metadata.activeAppName,
                    windowTitle: metadata.activeWindowTitle,
                    durationSeconds: durationSeconds,
                    whisperModel: metadata.whisperModel,
                    perfEngineMs: transcriptionMs,
                    perfEndToEndMs: metadata.perfEndToEndMs,
                    perfInAppMs: metadata.perfInAppMs,
                    metadata: buildMetadataDict(from: metadata),
                    audioFilename: audioFilename,
                    createdInTalkieView: false,
                    pasteTimestamp: Date()  // Already pasted
                )
                if let id = LiveDatabase.store(utterance), let baseline = capturedContext {
                    ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline)
                }
                logTiming("Database stored")
            }

            logTiming("Counting DB records")
            let dbRecordCount = LiveDatabase.count()
            SystemEventManager.shared.log(.database, "Record stored", detail: "Total: \(dbRecordCount) utterances\(traceSuffix)")

            // Track milestone
            ProcessingMilestones.shared.markDbRecordStored()
            logTiming("Milestone: DB stored")

            // Refresh UtteranceStore to pick up the new record from DB
            logTiming("Refreshing UtteranceStore")
            UtteranceStore.shared.refresh()
            logTiming("UtteranceStore refreshed")

            // Final success log
            SystemEventManager.shared.log(.system, "Pipeline complete", detail: "Ready for next recording")

            // Track final milestone
            ProcessingMilestones.shared.markSuccess()
            logTiming("Pipeline complete")

        } catch {
            logger.error("Transcription error: \(error.localizedDescription)")
            SystemEventManager.shared.log(.error, "Transcription failed", detail: "\(error.localizedDescription)\(traceSuffix)")

            // Even on failure, we saved the audio - store a record for retry
            // audioFilename is guaranteed valid (we guard at the start of process())
            SystemEventManager.shared.log(.file, "Audio preserved", detail: "\(audioFilename) - queued for retry")

            // Store a record with failed status so we can retry later
            let utterance = LiveUtterance(
                text: "[Transcription failed - retry pending]",
                mode: "failed",
                appBundleID: capturedContext?.activeAppBundleID,
                appName: capturedContext?.activeAppName,
                windowTitle: capturedContext?.activeWindowTitle,
                durationSeconds: durationSeconds,
                whisperModel: settings.selectedModelId,
                perfEndToEndMs: nil,
                perfInAppMs: nil,
                metadata: capturedContext.flatMap { buildMetadataDict(from: $0) },
                audioFilename: audioFilename,
                transcriptionStatus: .failed,
                transcriptionError: error.localizedDescription,
                createdInTalkieView: createdInTalkieView,
                pasteTimestamp: nil
            )
            LiveDatabase.store(utterance)

            SystemEventManager.shared.log(.database, "Failed record stored", detail: "Will retry when engine available")
        }

        recordingStartTime = nil
        capturedContext = nil
        createdInTalkieView = false
        pendingAudioFilename = nil
        traceID = nil
        state = .idle
    }

    // MARK: - Metadata Helpers

    /// Build metadata dictionary with rich context for database storage
    private func buildMetadataDict(from metadata: UtteranceMetadata) -> [String: String]? {
        var dict: [String: String] = [:]
        if let url = metadata.documentURL { dict["documentURL"] = url }
        if let url = metadata.browserURL { dict["browserURL"] = url }
        if let role = metadata.focusedElementRole { dict["focusedElementRole"] = role }
        if let value = metadata.focusedElementValue { dict["focusedElementValue"] = value }
        if let dir = metadata.terminalWorkingDir { dict["terminalWorkingDir"] = dir }
        if let total = metadata.perfEndToEndMs { dict["perfEndToEndMs"] = String(total) }
        if let inApp = metadata.perfInAppMs { dict["perfInAppMs"] = String(inApp) }
        return dict.isEmpty ? nil : dict
    }

    /// Create a short trace ID from the audio filename for correlating logs (debug-only)
    private func makeTraceID(from filename: String) -> String {
        let base = filename.components(separatedBy: ".").first ?? filename
        let trimmed = base.replacingOccurrences(of: "-", with: "")
        return String(trimmed.suffix(8))
    }

    // MARK: - Interstitial Editor

    /// Launch Talkie Core's interstitial editor with the given utterance ID
    private func launchInterstitialEditor(utteranceId: Int64) {
        let urlString = "talkie://interstitial/\(utteranceId)"
        guard let url = URL(string: urlString) else {
            NSLog("[LiveController] ERROR: Failed to create interstitial URL for utterance \(utteranceId)")
            logger.error("Failed to create interstitial URL for utterance \(utteranceId)")
            return
        }

        NSLog("[LiveController] Launching interstitial editor: \(urlString)")
        logger.info("Launching interstitial editor for utterance \(utteranceId)")
        NSWorkspace.shared.open(url)
        NSLog("[LiveController] NSWorkspace.shared.open() called")
    }
}
