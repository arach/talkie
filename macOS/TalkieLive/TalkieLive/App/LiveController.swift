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

            // Broadcast state change via XPC service for real-time IPC
            let elapsed = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            TalkieLiveXPCService.shared.updateState(state.rawValue, elapsedTime: elapsed)

            // Update floating pill state (desktop overlay)
            FloatingPillController.shared.state = state
            FloatingPillController.shared.elapsedTime = elapsed

            // Update recording overlay state (top overlay)
            RecordingOverlayController.shared.state = state
            RecordingOverlayController.shared.elapsedTime = elapsed

            // Stop elapsed time timer when returning to idle
            if state == .idle {
                stopElapsedTimeTimer()
            }
        }
    }

    private var audio: LiveAudioCapture
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

    // Timer for updating elapsed time in database during recording
    private var elapsedTimeTimer: Timer?

    init(
        audio: LiveAudioCapture,
        transcription: any TranscriptionService,
        router: LiveRouter
    ) {
        self.audio = audio
        self.transcription = transcription
        self.router = router

        // Wire up capture error handler
        self.audio.onCaptureError = { [weak self] errorMsg in
            Task { @MainActor [weak self] in
                self?.handleCaptureError(errorMsg)
            }
        }

        logger.info("LiveController initialized")
    }

    /// Handle audio capture startup failure
    private func handleCaptureError(_ errorMsg: String) {
        guard state == .listening else { return }

        logger.error("Audio capture failed: \(errorMsg)")
        AppLogger.shared.log(.error, "Mic capture failed", detail: errorMsg)

        // Play error sound
        NSSound.beep()

        // Reset state
        recordingStartTime = nil
        capturedContext = nil
        startApp = nil
        pendingAudioFilename = nil
        traceID = nil
        state = .idle
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
    /// Audio is still preserved in the queue for later access
    func cancelListening() {
        guard state == .listening else {
            logger.info("cancelListening() ignored - not in listening state (current: \(self.state.rawValue))")
            return
        }
        isCancelled = true
        // Immediately transition to transcribing state to prevent double-cancel
        // This makes the UI show "processing" and blocks further clicks
        state = .transcribing
        // stopCapture() will trigger process() which will see isCancelled
        // and save the audio with mode="cancelled"
        audio.stopCapture()
        logger.info("Recording cancelled during listening - audio will be preserved")

        // Safety timeout: if process() doesn't get called (e.g., PTT too short, no audio file),
        // force reset to idle after 2 seconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if self.state == .transcribing && self.isCancelled {
                logger.warning("Cancel timeout - forcing reset to idle (audio file may not have been created)")
                self.recordingStartTime = nil
                self.capturedContext = nil
                self.startApp = nil
                self.pendingAudioFilename = nil
                self.traceID = nil
                self.isCancelled = false
                self.state = .idle
            }
        }
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
                transcriptionModel: LiveSettings.shared.selectedModelId,
                metadata: capturedContext.flatMap { buildMetadataDict(from: $0) },
                audioFilename: audioFilename,
                transcriptionStatus: .pending,
                createdInTalkieView: createdInTalkieView,
                pasteTimestamp: nil
            )
            LiveDatabase.store(utterance)
            TalkieLiveXPCService.shared.notifyUtteranceAdded()
            AppLogger.shared.log(.database, "Pushed to queue", detail: "Audio saved for retry")
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

    /// Force reset to idle state - use when stuck or as emergency exit
    /// This will cancel any in-flight transcription and reset all state
    func forceReset() {
        logger.warning("Force reset requested from state: \(self.state.rawValue)")
        AppLogger.shared.log(.system, "Force reset", detail: "Was in \(state.rawValue)")

        // Cancel any pending transcription
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Stop any active capture
        if state == .listening {
            audio.stopCapture()
        }

        // Clear all state
        isCancelled = false
        recordingStartTime = nil
        capturedContext = nil
        startApp = nil
        pendingAudioFilename = nil
        traceID = nil
        routeToInterstitial = false
        createdInTalkieView = false

        // Reset to idle
        state = .idle
        logger.info("Force reset complete - now idle")
    }

    /// Get the start app for return-to-origin feature
    func getStartApp() -> NSRunningApplication? {
        return startApp
    }

    private func start() async {
        // Reset cancelled flag for new recording
        resetCancelled()
        traceID = nil

        // Capture baseline context FIRST to get the REAL target app
        // before any potential TalkieLive activation
        capturedContext = ContextCaptureService.shared.captureBaseline()

        // Check if Talkie Live is frontmost AFTER a tiny delay
        // This avoids false positives from menu bar clicks
        // We want to detect if user INTENTIONALLY opened TalkieLive window to queue,
        // not just clicked the menu bar icon to record
        try? await Task.sleep(for: .milliseconds(50))

        // Check frontmost app - if it's the target app from baseline, don't queue
        let currentFrontmost = ContextCapture.getFrontmostApp()
        let targetApp = capturedContext?.activeAppBundleID
        let talkieLiveIsNowFrontmost = ContextCapture.isTalkieLiveFrontmost()

        // Only queue if TalkieLive is frontmost AND it was the target app
        // (user intentionally recording inside Talkie Live window)
        createdInTalkieView = talkieLiveIsNowFrontmost && (targetApp == "jdi.talkie.live")

        // Store the start app for potential return-to-origin after paste
        startApp = currentFrontmost

        recordingStartTime = Date()

        // Log context capture
        let appName = capturedContext?.activeAppName ?? "Unknown"
        let windowTitle = capturedContext?.activeWindowTitle ?? ""
        let queueNote = createdInTalkieView ? " [will queue]" : ""
        AppLogger.shared.log(.system, "Context captured", detail: "\(appName) — \(windowTitle.prefix(30))\(queueNote)")

        // Play start sound
        SoundManager.shared.playStart()
        AppLogger.shared.log(.audio, "Recording started", detail: "Listening for audio input...")

        // Track milestone
        ProcessingMilestones.shared.markRecordingStarted()

        // Notify for onboarding celebration (immediate feedback when user presses hotkey)
        NotificationCenter.default.post(name: .recordingDidStart, object: nil)

        state = .listening

        // Start timer to update elapsed time in database every 250ms
        startElapsedTimeTimer()

        audio.startCapture { [weak self] audioPath in
            Task { [weak self] in
                await self?.process(tempAudioPath: audioPath)
            }
        }
    }

    /// Start timer to broadcast elapsed time updates via XPC service
    private func startElapsedTimeTimer() {
        elapsedTimeTimer?.invalidate()
        elapsedTimeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime)

                // Broadcast elapsed time update via XPC
                TalkieLiveXPCService.shared.updateState(self.state.rawValue, elapsedTime: elapsed)

                // Update local overlays
                FloatingPillController.shared.elapsedTime = elapsed
                RecordingOverlayController.shared.elapsedTime = elapsed
            }
        }
    }

    /// Stop elapsed time timer
    private func stopElapsedTimeTimer() {
        elapsedTimeTimer?.invalidate()
        elapsedTimeTimer = nil
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
            AppLogger.shared.log(.transcription, "⏱ \(step)", detail: "+\(ms)ms")
        }

        logTiming("Pipeline start")

        // CRITICAL: Copy temp audio to permanent storage FIRST before anything else
        // This ensures the recording is sacrosanct even if transcription fails
        // Once copied, the permanent file is NEVER moved or modified - only read or copied
        let tempURL = URL(fileURLWithPath: tempAudioPath)
        guard let audioFilename = AudioStorage.copyToStorage(tempURL) else {
            AppLogger.shared.log(.error, "Audio save failed", detail: "Could not copy temp file to storage")
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
        AppLogger.shared.log(.file, "Audio saved", detail: "\(audioFilename) (\(fileSizeStr)) • \(fileSaveMs)ms\(traceSuffix)")

        // Get path for transcription
        let audioPath = AudioStorage.url(for: audioFilename).path

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
                AppLogger.shared.log(.system, "Context changed", detail: "\(startApp) → \(endApp)")
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
        AppLogger.shared.log(.audio, "Recording finished", detail: "\(durationStr) • \(fileSizeStr)")

        state = .transcribing
        logTiming("State → transcribing")
        let engineStart = Date()

        // Log transcription start with model info and overhead
        let modelName = settings.selectedModelId
        let preMs = Int(engineStart.timeIntervalSince(pipelineStart) * 1000)  // Time from stop-recording to engine-submit
        AppLogger.shared.log(.transcription, "Transcribing...", detail: "Model: \(modelName) • pre: \(preMs)ms\(traceSuffix)")

        // Track milestone
        ProcessingMilestones.shared.markTranscribing()

        // Generate external reference ID for Engine trace correlation (short 8-char hex)
        let externalRefId = String(UUID().uuidString.prefix(8)).lowercased()

        do {
            // Pass the permanent audio path - engine reads directly, never modifies
            logTiming("Sending to engine")
            let request = TranscriptionRequest(audioPath: audioPath, isLive: true, externalRefId: externalRefId)
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
            metadata.transcriptionModel = settings.selectedModelId
            metadata.perfEngineMs = transcriptionMs
            metadata.perfPreMs = preMs
            metadata.routingMode = settings.routingMode.rawValue
            metadata.audioFilename = audioFilename
            logTiming("Metadata built")

            // Check if user cancelled during transcription
            if isCancelled {
                // Don't save to database - user explicitly cancelled
                // Audio file is already preserved in AudioStorage, user can drop it back in if they change their mind
                let audioPath = AudioStorage.url(for: audioFilename).path
                logger.info("Recording cancelled - audio preserved at: \(audioPath)")
                AppLogger.shared.log(.system, "Recording cancelled", detail: "Audio saved: \(audioFilename)")

                // Reset state
                recordingStartTime = nil
                capturedContext = nil
                startApp = nil
                pendingAudioFilename = nil
                traceID = nil
                isCancelled = false
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
                AppLogger.shared.log(.system, "Routing to interstitial", detail: "Shift-click mode")

                let routeEnd = Date()
                let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)
                let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                let appMs = max(0, totalMs - transcriptionMs)

                metadata.perfEndToEndMs = totalMs
                metadata.perfInAppMs = appMs
                metadata.perfPreMs = preMs
                metadata.perfPostMs = postMs

                let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", transcriptionSec)
                AppLogger.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")

                // Store in GRDB with mode "interstitial", pasteTimestamp = nil
                logTiming("Creating LiveUtterance for interstitial")
                let utterance = LiveUtterance(
                    text: result.text,
                    mode: "interstitial",
                    appBundleID: metadata.activeAppBundleID,
                    appName: metadata.activeAppName,
                    windowTitle: metadata.activeWindowTitle,
                    durationSeconds: durationSeconds,
                    transcriptionModel: metadata.transcriptionModel,
                    perfEngineMs: transcriptionMs,
                    perfEndToEndMs: metadata.perfEndToEndMs,
                    perfInAppMs: metadata.perfInAppMs,
                    sessionID: externalRefId,  // For Engine trace deep link
                    metadata: buildMetadataDict(from: metadata),
                    audioFilename: audioFilename,
                    createdInTalkieView: createdInTalkieView,
                    pasteTimestamp: nil  // Not pasted yet → interstitial will handle
                )

                if let id = LiveDatabase.store(utterance) {
                    logTiming("Database stored")

                    // Notify Talkie via XPC (non-blocking)
                    TalkieLiveXPCService.shared.notifyUtteranceAdded()

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
                AppLogger.shared.log(.system, "Queueing transcript", detail: "Created in Talkie Live")

                // Play a different sound for queued (reuse pasted for now)
                SoundManager.shared.playPasted()
                logTiming("Pasted sound triggered")
                AppLogger.shared.log(.ui, "Transcript queued", detail: "\(result.text.prefix(40))...\(traceSuffix)")

                let routeEnd = Date()
                let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)  // End-to-end: stop-recording → delivery
                let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                let appMs = max(0, totalMs - transcriptionMs)  // App time = total - engine

                metadata.perfEndToEndMs = totalMs
                metadata.perfInAppMs = appMs
                metadata.perfPreMs = preMs
                metadata.perfPostMs = postMs

                let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", transcriptionSec)
                AppLogger.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")
                #if DEBUG
                AppLogger.shared.log(.transcription, "Latency breakdown", detail: "e2e: \(totalMs)ms • engine: \(transcriptionMs)ms • app: \(appMs)ms (pre: \(preMs)ms, post: \(postMs)ms)\(traceSuffix)")
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
                    transcriptionModel: metadata.transcriptionModel,
                    perfEngineMs: transcriptionMs,
                    perfEndToEndMs: metadata.perfEndToEndMs,
                    perfInAppMs: metadata.perfInAppMs,
                    sessionID: externalRefId,  // For Engine trace deep link
                    metadata: buildMetadataDict(from: metadata),
                    audioFilename: audioFilename,
                    createdInTalkieView: true,
                    pasteTimestamp: nil  // Not pasted yet → queued
                )
                if let id = LiveDatabase.store(utterance), let baseline = capturedContext {
                    TalkieLiveXPCService.shared.notifyUtteranceAdded()
                    ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline)
                }
                logTiming("Database stored")

            } else {
                // Normal flow: paste immediately
                let routingMode = settings.routingMode == .paste ? "Paste" : "Clipboard"
                AppLogger.shared.log(.system, "Routing transcript", detail: "\(routingMode) mode")

                logTiming("Calling router.handle")
                await router.handle(transcript: result.text)
                logTiming("Router finished")
                metadata.wasRouted = true

                // Play pasted sound
                SoundManager.shared.playPasted()
                logTiming("Pasted sound triggered")
                AppLogger.shared.log(.ui, "Text delivered", detail: "\(result.text.prefix(40))...\(traceSuffix)")

                let routeEnd = Date()
                let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)  // End-to-end: stop-recording → delivery
                let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                let appMs = max(0, totalMs - transcriptionMs)  // App time = total - engine

                metadata.perfEndToEndMs = totalMs
                metadata.perfInAppMs = appMs
                metadata.perfPreMs = preMs
                metadata.perfPostMs = postMs

                let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", transcriptionSec)
                AppLogger.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")
                #if DEBUG
                AppLogger.shared.log(.transcription, "Latency breakdown", detail: "e2e: \(totalMs)ms • engine: \(transcriptionMs)ms • app: \(appMs)ms (pre: \(preMs)ms, post: \(postMs)ms)\(traceSuffix)")
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
                    AppLogger.shared.log(.system, "Returned to origin", detail: originApp.localizedName ?? "Unknown")
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
                    transcriptionModel: metadata.transcriptionModel,
                    perfEngineMs: transcriptionMs,
                    perfEndToEndMs: metadata.perfEndToEndMs,
                    perfInAppMs: metadata.perfInAppMs,
                    sessionID: externalRefId,  // For Engine trace deep link
                    metadata: buildMetadataDict(from: metadata),
                    audioFilename: audioFilename,
                    createdInTalkieView: false,
                    pasteTimestamp: Date()  // Already pasted
                )
                if let id = LiveDatabase.store(utterance), let baseline = capturedContext {
                    TalkieLiveXPCService.shared.notifyUtteranceAdded()
                    ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline)
                }
                logTiming("Database stored")
            }

            logTiming("Counting DB records")
            let dbRecordCount = LiveDatabase.count()
            AppLogger.shared.log(.database, "Record stored", detail: "Total: \(dbRecordCount) utterances\(traceSuffix)")

            // Track milestone
            ProcessingMilestones.shared.markDbRecordStored()
            logTiming("Milestone: DB stored")

            // Refresh UtteranceStore to pick up the new record from DB
            logTiming("Refreshing UtteranceStore")
            UtteranceStore.shared.refresh()
            logTiming("UtteranceStore refreshed")

            // Final success log
            AppLogger.shared.log(.system, "Pipeline complete", detail: "Ready for next recording")

            // Track final milestone
            ProcessingMilestones.shared.markSuccess()
            logTiming("Pipeline complete")

        } catch {
            logger.error("Transcription error: \(error.localizedDescription)")
            AppLogger.shared.log(.error, "Transcription failed", detail: "\(error.localizedDescription)\(traceSuffix)")

            // Even on failure, we saved the audio - store a record for retry
            // audioFilename is guaranteed valid (we guard at the start of process())
            AppLogger.shared.log(.file, "Audio preserved", detail: "\(audioFilename) - queued for retry")

            // Store a record with failed status so we can retry later
            let utterance = LiveUtterance(
                text: "[Transcription failed - retry pending]",
                mode: "failed",
                appBundleID: capturedContext?.activeAppBundleID,
                appName: capturedContext?.activeAppName,
                windowTitle: capturedContext?.activeWindowTitle,
                durationSeconds: durationSeconds,
                transcriptionModel: settings.selectedModelId,
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
            TalkieLiveXPCService.shared.notifyUtteranceAdded()

            AppLogger.shared.log(.database, "Failed record stored", detail: "Will retry when engine available")
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
