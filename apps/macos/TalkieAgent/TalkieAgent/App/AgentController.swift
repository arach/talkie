import Foundation
import AppKit
import AVFoundation
import TalkieKit

private let log = Log(.system)

// MARK: - Capture Intent

/// Intent for how to route a recording after transcription
enum CaptureIntent: Equatable {
    case paste                          // Normal: paste directly
    case interstitial                   // Open in scratchpad editor
    case saveMemo                       // Auto-promote to memo

    var displayName: String {
        switch self {
        case .paste: return "Paste"
        case .interstitial: return "Scratchpad"
        case .saveMemo: return "Save as Memo"
        }
    }

    var isInterstitial: Bool {
        if case .interstitial = self { return true }
        return false
    }
}

private final class LiveSidecarSegmentTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var requestedSegmentsBySession: [UUID: Set<Int>] = [:]

    func markRequested(sessionId: UUID, segmentIndex: Int) {
        _ = lock.withLock {
            requestedSegmentsBySession[sessionId, default: []].insert(segmentIndex)
        }
    }

    func consumeIfRequested(sessionId: UUID, segmentIndex: Int) -> Bool {
        lock.withLock {
            guard var segments = requestedSegmentsBySession[sessionId],
                  segments.contains(segmentIndex) else {
                return false
            }

            segments.remove(segmentIndex)
            if segments.isEmpty {
                requestedSegmentsBySession.removeValue(forKey: sessionId)
            } else {
                requestedSegmentsBySession[sessionId] = segments
            }
            return true
        }
    }

    func clear(sessionId: UUID) {
        _ = lock.withLock {
            requestedSegmentsBySession.removeValue(forKey: sessionId)
        }
    }
}

@MainActor
final class AgentController: ObservableObject {
    // State machine - centralized state management with validation
    private let stateMachine = LiveStateMachine()

    // Published computed property for external observation
    @Published private(set) var state: LiveState = .idle

    private var audio: AgentAudioCapture
    private let transcription: any TranscriptionService
    private let router: AgentRouter

    // Metadata captured at recording start
    private var recordingStartTime: Date?
    private var capturedContext: DictationMetadata?  // Baseline only - enrichment happens after paste
    private var createdInTalkieView: Bool = false  // Was Talkie Agent frontmost when recording started?
    private var intent: CaptureIntent = .paste  // Routing intent for current recording
    private var originalSelectedText: String?  // Text that was selected when recording started
    private var startApp: NSRunningApplication?  // App where recording started (for return-to-origin)
    private var traceID: String?

    /// Performance trace for the current dictation flow (hotkey → paste)
    private var trace: LiveTranscriptionTrace?

    // Transcription task - stored so we can cancel it
    private var transcriptionTask: Task<Void, Never>?
    private var pendingAudioFilename: String?  // For saving on cancel

    // Screenshots captured during this recording
    private var capturedScreenshots: [RecordingScreenshot] = []
    private var recordingId: UUID?
    private let liveSidecarSegmentTracker = LiveSidecarSegmentTracker()

    // One-shot guard to prevent process() being called multiple times per recording
    private var processDidFire = false

    // Consecutive capture failure tracking - reboot audio after 2 failures
    private var consecutiveFailures = 0
    private let failuresBeforeReboot = 2
    // Post-reboot failure tracking - detect when reboot doesn't help (device routing issue)
    private var justRebooted = false
    private var postRebootFailures = 0
    private var hasShownDeviceRoutingAlert = false  // Only show once per session

    // Timer for updating elapsed time in database during recording
    private var elapsedTimeTimer: Timer?

    // Watchdog for stuck state detection
    private var watchdogTimer: Timer?
    private var stateEntryTime: Date?

    // Timeout thresholds
    private let transcribingTimeout: TimeInterval = 120.0  // 2 minutes max for transcription
    private let routingTimeout: TimeInterval = 30.0        // 30 seconds max for routing

    // Idle sweep - full state reset after extended inactivity
    private var idleSweepTimer: Timer?
    private let idleSweepTimeout: TimeInterval = 300.0  // 5 minutes of inactivity

    // Audio input route changes can leave CoreAudio briefly unsettled. Track the
    // recovery window so the next hotkey shows intent instead of burning retries.
    private var audioInputChangeObserver: NSObjectProtocol?
    private var audioInputRecoveryTask: Task<Void, Never>?
    private var audioInputSettlingUntil: Date?
    private let audioInputSettleDuration: TimeInterval = 1.5

    deinit {
        // Cancel outstanding tasks to prevent orphaned work
        transcriptionTask?.cancel()
        audioInputRecoveryTask?.cancel()
        elapsedTimeTimer?.invalidate()
        watchdogTimer?.invalidate()
        idleSweepTimer?.invalidate()
        if let audioInputChangeObserver {
            NotificationCenter.default.removeObserver(audioInputChangeObserver)
        }
    }

    // MARK: - Black Channel Tests

    #if DEBUG
    func runBlackChannelTests() async -> [[String: Any]] {
        guard let audioService = audio as? AudioCaptureService else {
            return [["error": "AudioCaptureService not available"]]
        }

        let results = await BlackChannelTest.runAll(
            audioService: audioService,
            transcription: transcription
        )

        return results.map { result in
            [
                "label": result.label,
                "passed": result.passed,
                "similarity": String(format: "%.0f%%", result.similarity * 100),
                "segments": result.segments,
                "durationMs": result.durationMs,
                "audioDuration": String(format: "%.1fs", result.audioDuration),
                "control": result.controlText,
                "segmented": result.segmentedText
            ] as [String: Any]
        }
    }
    #endif

    init(
        audio: AgentAudioCapture,
        transcription: any TranscriptionService,
        router: AgentRouter
    ) {
        self.audio = audio
        self.transcription = transcription
        self.router = router

        // Configure state machine callbacks
        stateMachine.onStateChange = { [weak self] oldState, newState in
            guard let self = self else { return }

            // Log state transition
            log.info("State: \(oldState.rawValue) → \(newState.rawValue)")

            // Sync published state
            self.state = newState

            // Track state entry time for watchdog
            self.stateEntryTime = Date()

            // Manage watchdog timer based on state
            switch newState {
            case .transcribing, .routing, .refining:
                // Start watchdog for processing states
                self.startWatchdog()
            case .idle, .listening:
                // Stop watchdog when not in processing states
                self.stopWatchdog()
            }

            // Broadcast state change via XPC service for real-time IPC
            let elapsed = self.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            TalkieAgentXPCService.shared.updateState(newState.rawValue, elapsedTime: elapsed)

            // Update floating pill state (desktop overlay)
            FloatingPillController.shared.state = newState
            FloatingPillController.shared.elapsedTime = elapsed

            // Update recording overlay state (top overlay)
            RecordingOverlayController.shared.state = newState
            RecordingOverlayController.shared.elapsedTime = elapsed

            // Stop elapsed time timer when no longer actively recording
            if newState != .listening {
                self.stopElapsedTimeTimer()
            }

            if newState == .idle {
                FloatingPillController.shared.captureIntent = "Paste"
                self.startIdleSweepTimer()
            } else {
                self.stopIdleSweepTimer()
            }
        }

        stateMachine.onInvalidTransition = { currentState, event in
            let eventStr = String(describing: event)
            log.warning("Invalid transition: \(currentState.rawValue) + \(eventStr)")
            log.error("Invalid state transition", detail: "\(currentState.rawValue) + \(eventStr)")
        }

        // Wire up capture error handler
        self.audio.onCaptureError = { [weak self] errorMsg in
            Task { @MainActor [weak self] in
                self?.handleCaptureError(errorMsg)
            }
        }

        observeAudioInputChanges()

        log.info("AgentController initialized")
    }

    // MARK: - State Cleanup

    /// Centralized cleanup of all recording-related state
    /// Call this when returning to idle from any path (success, error, cancel)
    /// Concatenate multiple WAV files into a single output file
    private static func concatenateWAVFiles(_ inputs: [URL], to output: URL) throws {
        guard let first = inputs.first else { return }

        let firstFile = try AVAudioFile(forReading: first)
        let format = firstFile.processingFormat

        let outputFile = try AVAudioFile(forWriting: output, settings: format.settings)

        let chunkSize: AVAudioFrameCount = 16384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw NSError(domain: "AgentController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        for inputURL in inputs {
            let inputFile = try AVAudioFile(forReading: inputURL)
            while inputFile.framePosition < inputFile.length {
                try inputFile.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try outputFile.write(from: buffer)
            }
        }
    }

    private func clearRecordingState(invalidateTrace: Bool = true) {
        recordingStartTime = nil
        capturedContext = nil
        startApp = nil
        pendingAudioFilename = nil
        traceID = nil
        if invalidateTrace {
            trace?.invalidate()
            trace = nil
        }
        isCancelled = false
        intent = .paste
        originalSelectedText = nil
        createdInTalkieView = false
        capturedScreenshots = []
        recordingId = nil
    }

    private func discardLiveSidecarSessionIfNeeded() {
        guard let captureSessionId = recordingId else { return }
        liveSidecarSegmentTracker.clear(sessionId: captureSessionId)

        Task {
            await LiveSidecarSessionStore.shared.clear(captureSessionId: captureSessionId)
        }
    }

    private func discardLiveSidecarSession(captureSessionId: UUID?) async {
        guard let captureSessionId else { return }
        liveSidecarSegmentTracker.clear(sessionId: captureSessionId)
        await LiveSidecarSessionStore.shared.clear(captureSessionId: captureSessionId)
    }

    private nonisolated static func currentLiveSidecarProvenance(
        for captureSessionId: UUID?
    ) async -> [ProvenanceSegment]? {
        guard let captureSessionId else { return nil }
        let provenance = await LiveSidecarSessionStore.shared.completedProvenance(for: captureSessionId)
        return provenance.isEmpty ? nil : provenance
    }

    private nonisolated static func applyRecordingAssets(
        to recording: inout LiveRecording,
        segmentsJSON: String? = nil,
        screenshotsJSON: String? = nil,
        captureSessionId: UUID?
    ) async -> Set<UUID> {
        let textProvenance = await currentLiveSidecarProvenance(for: captureSessionId)
        recording.setAssets(
            segmentsJSON: segmentsJSON,
            screenshotsJSON: screenshotsJSON,
            textProvenance: textProvenance
        )
        return Set(textProvenance?.map(\.id) ?? [])
    }

    @discardableResult
    private nonisolated static func storeRecording(
        _ recording: LiveRecording,
        captureSessionId: UUID?,
        includedProvenanceIDs: Set<UUID> = []
    ) async -> UUID? {
        guard let id = UnifiedDatabase.store(recording) else { return nil }

        if let captureSessionId {
            await LiveSidecarSessionStore.shared.setPersistedRecordingId(id, for: captureSessionId)

            let currentProvenance = await LiveSidecarSessionStore.shared.completedProvenance(for: captureSessionId)
            let lateProvenance = currentProvenance.filter { !includedProvenanceIDs.contains($0.id) }
            if !lateProvenance.isEmpty {
                UnifiedDatabase.appendTextProvenance(id: id, segments: lateProvenance)
            }
            await LiveSidecarSessionStore.shared.clearIfPersistedAndIdle(captureSessionId: captureSessionId)
        }

        return id
    }

    private nonisolated static func copyLiveSidecarSegment(
        sourceURL: URL,
        captureSessionId: UUID,
        segmentIndex: Int
    ) -> URL? {
        let fm = FileManager.default
        let ext = sourceURL.pathExtension.isEmpty ? "wav" : sourceURL.pathExtension
        let destinationURL = fm.temporaryDirectory
            .appendingPathComponent("talkie-live-sidecar-\(captureSessionId.uuidString)-\(segmentIndex)-\(UUID().uuidString)")
            .appendingPathExtension(ext)

        do {
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            log.error("Failed to copy live sidecar segment", detail: sourceURL.lastPathComponent, error: error)
            return nil
        }
    }

    /// Handle audio capture startup failure
    private func handleCaptureError(_ errorMsg: String) {
        guard state == .listening || (state == .transcribing && pendingAudioFilename == nil) else { return }

        // "Recording too short" or "setup incomplete" are not errors - just nothing to transcribe
        // Handle gracefully without alarming the user
        let isShortRecording = errorMsg.contains("too short")
        let isCancelledSetup = errorMsg.contains("setup incomplete")

        // Check if "setup incomplete" was likely a HAL failure (user waited >1s but no audio)
        // If user cancelled within 1s, it's probably intentional. After 1s, audio should have started.
        let waitedForAudio: Bool
        if let startTime = recordingStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            waitedForAudio = elapsed > 1.0
        } else {
            waitedForAudio = false
        }

        let isLikelyHALFailure = isCancelledSetup && waitedForAudio
        let isGracefulCancel = (isShortRecording || isCancelledSetup) && !isLikelyHALFailure

        if isLikelyHALFailure {
            log.warning("⚠️ Audio setup failed after waiting - likely HAL corruption")
            AppLogger.shared.log(.audio, "Audio setup failed", detail: "HAL likely corrupted")
            FloatingPillController.shared.showError("Mic unavailable — another app may be using it")
        } else if isGracefulCancel {
            let reason = isShortRecording ? "Too short to transcribe" : "Stopped before audio started"
            log.info("Recording discarded: \(reason)")
            AppLogger.shared.log(.audio, "Recording discarded", detail: reason)
            // Subtle feedback (dev builds only, configurable)
            SoundManager.shared.playCancelled()
        } else {
            log.error("Audio capture failed: \(errorMsg)")
            AppLogger.shared.log(.error, "Mic capture failed", detail: errorMsg)
            // User-facing error message via pill toast
            let userMessage = Self.userFacingAudioError(errorMsg)
            FloatingPillController.shared.showError(userMessage)
        }

        // Reset state
        discardLiveSidecarSessionIfNeeded()
        clearRecordingState()

        // Transition to idle - use forceReset for graceful cancels (cleaner), error for real failures
        if isGracefulCancel {
            stateMachine.transition(.forceReset)
        } else {
            stateMachine.transition(.error(errorMsg))

            // Check if this is a device routing error (-10868)
            // This happens when macOS switches audio devices (e.g., AirPods connected)
            // and the configured input device becomes unavailable
            let isDeviceRoutingError = errorMsg.contains("-10868")

            // Track post-reboot failures to detect when reboot doesn't help
            if justRebooted {
                justRebooted = false
                postRebootFailures += 1
                log.warning("Post-reboot failure #\(postRebootFailures) - reboot may not resolve this issue")

                // If we're still failing after reboot with a device routing error,
                // show helpful guidance to the user immediately (once per session)
                if isDeviceRoutingError && !hasShownDeviceRoutingAlert {
                    hasShownDeviceRoutingAlert = true
                    showDeviceRoutingHelp()
                }
            }

            // Track consecutive failures and auto-reboot audio system if needed
            consecutiveFailures += 1
            log.warning("Consecutive audio failures: \(consecutiveFailures)/\(failuresBeforeReboot)")
            if consecutiveFailures >= failuresBeforeReboot {
                log.error("════════════════════════════════════════════════════════════")
                log.error("🔄 AUTO-REBOOTING AUDIO SYSTEM after \(consecutiveFailures) consecutive failures")
                log.error("════════════════════════════════════════════════════════════")
                AppLogger.shared.log(.audio, "Rebooting audio system", detail: "\(consecutiveFailures) consecutive failures")
                consecutiveFailures = 0
                justRebooted = true  // Track that we're about to reboot
                Task {
                    await audio.reboot()
                }
            }
        }
    }

    /// Translate raw audio error strings into concise, user-facing messages
    private static func userFacingAudioError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("not responding") || lower.contains("microphone not") {
            return "Mic not responding — try again"
        }
        if lower.contains("-10868") || lower.contains("device") {
            return "Audio device changed — check Sound settings"
        }
        if lower.contains("initialize") || lower.contains("hal") {
            return "Mic unavailable — another app may be using it"
        }
        if lower.contains("busy") || lower.contains("in use") {
            return "Mic in use by another app"
        }
        // Generic fallback — keep it short
        return "Mic error — tap to retry"
    }

    private func observeAudioInputChanges() {
        audioInputChangeObserver = NotificationCenter.default.addObserver(
            forName: .audioInputDeviceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioInputDeviceChanged(notification)
            }
        }
    }

    private func handleAudioInputDeviceChanged(_ notification: Notification) {
        let deviceName = notification.userInfo?["deviceName"] as? String
        let deviceLabel = if let deviceName, !deviceName.isEmpty {
            deviceName
        } else {
            "system input"
        }

        audioInputSettlingUntil = Date().addingTimeInterval(audioInputSettleDuration)
        FloatingPillController.shared.showNotice("Input changed - updating mic")
        AppLogger.shared.log(.audio, "Audio input changed", detail: deviceLabel)

        audioInputRecoveryTask?.cancel()
        audioInputRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            guard self.state == .idle else { return }

            let result = await self.audio.reboot()
            guard !Task.isCancelled else { return }

            self.audioInputSettlingUntil = nil
            switch result {
            case .success:
                log.info("Audio input recovery completed", detail: deviceLabel)
            case .successDegraded:
                log.warning("Audio input recovery completed with degraded HAL", detail: deviceLabel)
            case .failed:
                FloatingPillController.shared.showError("Mic update failed - tap to retry")
                AppLogger.shared.log(.error, "Audio input recovery failed", detail: deviceLabel)
            }
        }
    }

    private func waitForAudioInputRecoveryIfNeeded(allowDelay: Bool) async -> Bool {
        if let deadline = audioInputSettlingUntil {
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                FloatingPillController.shared.showNotice("Input changed - updating mic")
                guard allowDelay else { return false }
                try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
            }
        }

        if let recoveryTask = audioInputRecoveryTask {
            guard allowDelay else { return false }
            await recoveryTask.value
            audioInputRecoveryTask = nil
        }

        guard audioInputSettlingUntil != nil else { return true }

        let result = await audio.reboot()
        audioInputSettlingUntil = nil
        if case .failed = result {
            FloatingPillController.shared.showError("Mic update failed - tap to retry")
            return false
        }
        return true
    }

    /// Show helpful guidance when device routing issues are detected
    private func showDeviceRoutingHelp() {
        log.info("📢 Showing device routing help to user")
        AppLogger.shared.log(.audio, "Showing device routing help", detail: "Persistent -10868 errors after reboot")

        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Audio Input Issue Detected"
            alert.informativeText = """
            Your configured microphone isn't responding. This often happens when macOS switches to a newly connected audio device (like AirPods).

            To fix:
            1. Open System Settings → Sound → Input
            2. Select your preferred microphone (e.g., USB mic)
            3. Try recording again
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Sound Settings")
            alert.addButton(withTitle: "Learn More")
            alert.addButton(withTitle: "Dismiss")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open Sound Settings directly to Sound pane
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } else if response == .alertSecondButtonReturn {
                // Open Apple's support article about changing sound input settings
                if let url = URL(string: "https://support.apple.com/guide/mac-help/change-sound-input-settings-mchlp2567/mac") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Reboot the audio system - use when HAL gets corrupted
    /// Exposed for menu item access
    /// - Returns: Result indicating success and HAL health status
    @discardableResult
    func rebootAudio() async -> AudioRebootResult {
        await audio.reboot()
    }

    /// Toggle mode: press to start, press to stop
    /// - Parameters:
    ///   - interstitial: If true (Shift-click), route to Talkie Core interstitial instead of paste
    ///   - hotkeyTimestamp: Precise timestamp from Carbon callback for performance measurement
    func toggleListening(interstitial: Bool = false, hotkeyTimestamp: HotKeyTimestamp? = nil) async {
        NSLog("[AgentController] toggleListening: state=%@, interstitial=%d", self.state.rawValue, interstitial ? 1 : 0)
        log.info("[AgentController] toggleListening: state=\(self.state.rawValue), interstitial=\(interstitial)")

        switch state {
        case .idle:
            log.info("[AgentController] Calling start()...")
            await start(hotkeyTimestamp: hotkeyTimestamp)
            log.info("[AgentController] start() completed")
        case .listening:
            log.info("[AgentController] Calling stop()...")
            stop(interstitial: interstitial)
            log.info("[AgentController] stop() completed")
        case .transcribing, .routing, .refining:
            // Don't interrupt processing
            log.info("[AgentController] Ignoring toggle - currently processing")
            break
        }
    }

    // MARK: - Push-to-Talk Mode

    /// PTT start: called when PTT hotkey is pressed down
    /// - Parameter hotkeyTimestamp: Precise timestamp from Carbon callback for performance measurement
    func pttStart(hotkeyTimestamp: HotKeyTimestamp? = nil) async {
        guard state == .idle else {
            log.info("PTT start ignored - not idle (state=\(self.state.rawValue))")
            return
        }
        log.info("PTT recording started (key down)")
        await start(hotkeyTimestamp: hotkeyTimestamp, allowDelayedStart: false)
    }

    /// PTT stop: called when PTT hotkey is released
    func pttStop() {
        guard state == .listening else {
            log.info("PTT stop ignored - not listening (state=\(self.state.rawValue))")
            return
        }
        log.info("PTT recording stopped (key up)")
        stop()
    }

    /// Cancel without processing (user pressed X)
    /// Works in any active state - sets cancelled flag to prevent paste
    @Published private(set) var isCancelled = false

    /// Cancel recording during listening phase (before transcription starts)
    /// Audio is still preserved in the queue for later access
    func cancelListening() {
        guard state == .listening else {
            log.info("cancelListening() ignored - not in listening state (current: \(self.state.rawValue))")
            return
        }
        isCancelled = true

        // Transition to transcribing state to prevent double-cancel
        // This makes the UI show "processing" and blocks further clicks
        stateMachine.transition(.cancel)

        // stopCapture() will trigger process() which will see isCancelled
        // and skip transcription (audio is still preserved)
        audio.stopCapture()
        log.info("Recording cancelled during listening - audio will be preserved")

        // Safety timeout: if process() doesn't get called (e.g., PTT too short, no audio file),
        // force reset to idle after 2 seconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if self.state == .transcribing && self.isCancelled {
                log.warning("Cancel timeout - forcing reset to idle (audio file may not have been created)")
                self.clearRecordingState()
                self.stateMachine.transition(.forceReset)
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
            let captureSessionId = recordingId
            let appBundleID = capturedContext?.activeAppBundleID
            let appName = capturedContext?.activeAppName
            let windowTitle = capturedContext?.activeWindowTitle
            let durationSeconds = recordingStartTime.map { Date().timeIntervalSince($0) }
            let metadata = capturedContext.flatMap { buildMetadataDict(from: $0) }
            let selectedModelId = LiveSettings.shared.selectedModelId
            let screenshotsJSON = RecordingScreenshot.toJSON(capturedScreenshots)
            let createdInTalkieView = createdInTalkieView

            Task {
                let utterance = LiveDictation(
                    text: "[Queued for retry]",
                    mode: "queued",
                    appBundleID: appBundleID,
                    appName: appName,
                    windowTitle: windowTitle,
                    durationSeconds: durationSeconds,
                    transcriptionModel: selectedModelId,
                    metadata: metadata,
                    audioFilename: audioFilename,
                    transcriptionStatus: .pending,
                    createdInTalkieView: createdInTalkieView,
                    pasteTimestamp: nil
                )
                var recording = LiveRecording(from: utterance)
                let includedProvenanceIDs = await Self.applyRecordingAssets(
                    to: &recording,
                    screenshotsJSON: screenshotsJSON,
                    captureSessionId: captureSessionId
                )
                if await Self.storeRecording(
                    recording,
                    captureSessionId: captureSessionId,
                    includedProvenanceIDs: includedProvenanceIDs
                ) != nil {
                    TalkieAgentXPCService.shared.notifyDictationAdded()
                    AppLogger.shared.log(.database, "Pushed to queue", detail: "Audio saved for retry")
                }
            }
            SoundManager.shared.playPasted()  // Confirmation sound
        }

        clearRecordingState()

        // Cancel back to idle
        stateMachine.transition(.cancel)
        log.info("Pushed to queue (was \(previousState.rawValue))")

        // Refresh the queue count
        DictationStore.shared.refresh()
    }

    /// Reset cancelled flag when starting a new recording
    private func resetCancelled() {
        isCancelled = false
    }

    /// Force reset to idle state - use when stuck or as emergency exit
    /// This will cancel any in-flight transcription and reset all state
    func forceReset() {
        log.warning("Force reset requested from state: \(self.state.rawValue)")
        AppLogger.shared.log(.system, "Force reset", detail: "Was in \(state.rawValue)")

        // Cancel any pending transcription
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Stop any active capture
        if state == .listening {
            audio.stopCapture()
        }

        // Clear all state
        clearRecordingState()

        // Force reset to idle (emergency exit - works from any state)
        stateMachine.transition(.forceReset)
        log.info("Force reset complete - now idle")
    }

    /// Get the start app for return-to-origin feature
    func getStartApp() -> NSRunningApplication? {
        return startApp
    }

    // MARK: - Capture Intent (Mid-Recording Modifiers)

    /// Set intent to route to interstitial editor (Shift or Shift+S during recording)
    func setInterstitialIntent() {
        guard state == .listening else { return }
        intent = .interstitial
        log.info("Intent set: Interstitial editor")
        updatePillIntent()
    }

    /// Set intent to save as memo (Shift+A during recording)
    func setSaveAsMemoIntent() {
        guard state == .listening else { return }
        intent = .saveMemo
        log.info("Intent set: Save as memo")
        updatePillIntent()
    }

    func requestFeedbackSidecar() {
        Task { @MainActor [weak self] in
            await self?.queueLiveSidecar(kind: .feedback)
        }
    }

    func requestResearchSidecar() {
        Task { @MainActor [weak self] in
            await self?.queueLiveSidecar(kind: .research)
        }
    }

    /// Clear capture intent (return to normal paste behavior)
    func clearIntent() {
        guard state == .listening else { return }
        intent = .paste
        log.info("Intent cleared: Normal paste")
        updatePillIntent()
    }

    /// Update FloatingPill with current intent
    private func updatePillIntent() {
        FloatingPillController.shared.captureIntent = intent.displayName
    }

    /// Get current capture intent for UI display
    var captureIntent: String {
        intent.displayName
    }

    private func queueLiveSidecar(kind: LiveSidecarKind) async {
        guard state == .listening else { return }
        guard let captureSessionId = recordingId,
              let recordingStartTime else {
            log.warning("Live sidecar request ignored - no active recording session")
            return
        }

        let targetSegmentIndex = audio.currentSegmentIndex
        let requestedAtMs = Int(Date().timeIntervalSince(recordingStartTime) * 1000)
        let request = LiveSidecarRequest(
            captureSessionId: captureSessionId,
            kind: kind,
            targetSegmentIndex: targetSegmentIndex,
            requestedAtMs: requestedAtMs,
            appName: capturedContext?.activeAppName,
            windowTitle: capturedContext?.activeWindowTitle
        )

        liveSidecarSegmentTracker.markRequested(sessionId: captureSessionId, segmentIndex: targetSegmentIndex)
        await LiveSidecarSessionStore.shared.queue(request)
        audio.requestCheckpoint()

        log.info(
            "Queued live sidecar request",
            detail: "\(kind.rawValue) segment=\(targetSegmentIndex)"
        )
        ToastOverlayController.shared.show(
            ToastMessage(
                icon: kind.iconName,
                text: kind.queuedToastText,
                detail: "It will attach to this recording.",
                actionLabel: nil,
                action: nil
            ),
            duration: 1.2
        )
    }

    private func processPendingLiveSidecarSegments(
        captureSessionId: UUID?,
        audioFilenames: [String]
    ) async {
        guard let captureSessionId else { return }

        for (segmentIndex, audioFilename) in audioFilenames.enumerated() {
            await handleCompletedSidecarSegment(
                captureSessionId: captureSessionId,
                segmentIndex: segmentIndex,
                segmentURL: AudioStorage.url(for: audioFilename),
                deleteWhenDone: false
            )
        }

        liveSidecarSegmentTracker.clear(sessionId: captureSessionId)
    }

    private func handleCompletedSidecarSegment(
        captureSessionId: UUID,
        segmentIndex: Int,
        segmentURL: URL,
        deleteWhenDone: Bool
    ) async {
        let requests = await LiveSidecarSessionStore.shared.takeRequests(
            captureSessionId: captureSessionId,
            segmentIndex: segmentIndex
        )

        guard !requests.isEmpty else {
            if deleteWhenDone {
                try? FileManager.default.removeItem(at: segmentURL)
            }
            return
        }

        let transcription = self.transcription
        Task.detached { [transcription] in
            await Self.processLiveSidecarRequests(
                requests,
                segmentURL: segmentURL,
                transcription: transcription,
                deleteWhenDone: deleteWhenDone
            )
        }
    }

    private nonisolated static func processLiveSidecarRequests(
        _ requests: [LiveSidecarRequest],
        segmentURL: URL,
        transcription: any TranscriptionService,
        deleteWhenDone: Bool
    ) async {
        defer {
            if deleteWhenDone {
                try? FileManager.default.removeItem(at: segmentURL)
            }
        }

        do {
            let transcript = try await transcription.transcribe(
                TranscriptionRequest(
                    audioPath: segmentURL.path,
                    isLive: true,
                    postProcess: .dictionary
                )
            )
            let trimmedTranscript = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedTranscript.isEmpty else {
                for request in requests {
                    _ = await LiveSidecarSessionStore.shared.complete(request, provenance: nil)
                }

                await MainActor.run {
                    ToastOverlayController.shared.show(
                        ToastMessage(
                            icon: "waveform.slash",
                            text: "No speech captured",
                            detail: "Nothing to analyze from that moment.",
                            actionLabel: nil,
                            action: nil
                        ),
                        duration: 1.2
                    )
                }
                return
            }

            for request in requests {
                do {
                    let result = try await LiveSidecarTaskService.shared.run(
                        request: request,
                        transcript: trimmedTranscript
                    )

                    let provenance = ProvenanceSegment(
                        source: .workflow,
                        originalText: result.response,
                        sourceAssetId: "live-sidecar-segment-\(request.targetSegmentIndex)",
                        sourceDetail: LiveSidecarPromptBuilder.provenanceDetail(
                            kind: request.kind,
                            providerName: result.providerName,
                            modelId: result.modelId
                        )
                    )

                    let persistedRecordingId = await LiveSidecarSessionStore.shared.complete(
                        request,
                        provenance: provenance
                    )

                    if let persistedRecordingId {
                        UnifiedDatabase.appendTextProvenance(
                            id: persistedRecordingId,
                            segments: [provenance]
                        )
                    }

                    await MainActor.run {
                        if persistedRecordingId != nil {
                            DictationStore.shared.refresh()
                        }

                        ToastOverlayController.shared.show(
                            ToastMessage(
                                icon: request.kind.iconName,
                                text: request.kind.readyToastText,
                                detail: persistedRecordingId == nil
                                    ? "It will attach when you stop recording."
                                    : nil,
                                actionLabel: nil,
                                action: nil
                            ),
                            duration: 1.5
                        )
                    }
                } catch {
                    log.error(
                        "Live sidecar task failed",
                        detail: "\(request.kind.rawValue) segment=\(request.targetSegmentIndex)",
                        error: error
                    )
                    _ = await LiveSidecarSessionStore.shared.complete(request, provenance: nil)

                    await MainActor.run {
                        ToastOverlayController.shared.show(
                            ToastMessage(
                                icon: "exclamationmark.triangle",
                                text: "\(request.kind.displayName) failed",
                                detail: nil,
                                actionLabel: nil,
                                action: nil
                            ),
                            duration: 1.4
                        )
                    }
                }
            }
        } catch {
            log.error("Live sidecar transcription failed", detail: segmentURL.lastPathComponent, error: error)

            for request in requests {
                _ = await LiveSidecarSessionStore.shared.complete(request, provenance: nil)
            }

            await MainActor.run {
                ToastOverlayController.shared.show(
                    ToastMessage(
                        icon: "exclamationmark.triangle",
                        text: "Live sidecar failed",
                        detail: nil,
                        actionLabel: nil,
                        action: nil
                    ),
                    duration: 1.4
                )
            }
        }
    }

    // MARK: - Screenshot Capture

    /// Capture a fullscreen screenshot during recording
    /// Called via Hyper+S hotkey — only acts while recording
    func captureScreenshot() {
        guard state == .listening else {
            log.debug("Screenshot ignored — not recording (state=\(state.rawValue))")
            return
        }
        guard let startTime = recordingStartTime, let recId = recordingId else {
            log.warning("Screenshot ignored — missing recording state")
            return
        }

        let timestampMs = Int(Date().timeIntervalSince(startTime) * 1000)
        log.info("Capturing screenshot at \(timestampMs)ms")

        Task {
            guard let image = await ScreenshotService.shared.captureMainDisplay() else {
                log.warning("Screenshot capture failed")
                ToastOverlayController.shared.show(
                    ToastMessage(icon: "camera", text: "Screenshot failed", detail: nil, actionLabel: nil, action: nil),
                    duration: 1.5
                )
                return
            }

            guard let pngData = await ScreenshotService.shared.encodeAsPNG(image) else {
                log.warning("Screenshot PNG encoding failed")
                return
            }

            let width = Int(image.size.width)
            let height = Int(image.size.height)
            guard let savedURL = ScreenshotStorage.save(
                pngData,
                recordingId: recId,
                timestampMs: timestampMs,
                captureMode: "fullscreen",
                width: width,
                height: height
            ) else {
                log.error("Screenshot save failed")
                return
            }

            let screenshot = RecordingScreenshot(
                filename: savedURL.lastPathComponent,
                timestampMs: timestampMs,
                captureMode: "fullscreen",
                width: width,
                height: height
            )
            capturedScreenshots.append(screenshot)

            let count = capturedScreenshots.count
            log.info("Screenshot \(count) captured: \(savedURL.lastPathComponent) (\(width)x\(height))")
            AppLogger.shared.log(.system, "Screenshot captured", detail: "#\(count) at \(timestampMs)ms")

            // Brief toast feedback
            ToastOverlayController.shared.show(
                ToastMessage(icon: "camera.fill", text: "Screenshot \(count)", detail: nil, actionLabel: nil, action: nil),
                duration: 1.0
            )
        }
    }

    private func start(hotkeyTimestamp: HotKeyTimestamp? = nil, allowDelayedStart: Bool = true) async {
        guard await waitForAudioInputRecoveryIfNeeded(allowDelay: allowDelayedStart) else { return }
        guard state == .idle else { return }

        // Reset cancelled flag for new recording
        resetCancelled()
        processDidFire = false  // Reset one-shot guard
        traceID = nil
        intent = .paste
        originalSelectedText = nil
        capturedScreenshots = []
        recordingId = UUID()
        let captureSessionId = recordingId
        let liveSidecarSegmentTracker = self.liveSidecarSegmentTracker

        if let captureSessionId {
            liveSidecarSegmentTracker.clear(sessionId: captureSessionId)
        }

        audio.onSegmentCompleted = { [weak self, liveSidecarSegmentTracker] segment in
            guard let captureSessionId else { return }
            guard liveSidecarSegmentTracker.consumeIfRequested(
                sessionId: captureSessionId,
                segmentIndex: segment.index
            ) else {
                return
            }
            guard let copiedURL = Self.copyLiveSidecarSegment(
                sourceURL: segment.url,
                captureSessionId: captureSessionId,
                segmentIndex: segment.index
            ) else {
                return
            }

            Task { @MainActor [weak self] in
                await self?.handleCompletedSidecarSegment(
                    captureSessionId: captureSessionId,
                    segmentIndex: segment.index,
                    segmentURL: copiedURL,
                    deleteWhenDone: true
                )
            }
        }

        // Start performance trace for this dictation flow
        // If we have a precise hotkey timestamp, use it as the trace start time
        // This gives us accurate measurement from the actual Carbon callback
        trace = LiveTranscriptionTrace(hotkeyTimestamp: hotkeyTimestamp)

        // Mark how long it took from hotkey to reach this point
        if let ts = hotkeyTimestamp {
            let dispatchMs = ts.elapsedMs()
            trace?.mark("hotkey_received", metadata: "dispatch: \(dispatchMs)ms")
        } else {
            trace?.mark("hotkey_pressed")
        }

        // Capture frontmost app IMMEDIATELY (sync, ~0ms) before any focus changes
        // This is the only thing we MUST capture before starting recording
        let targetApp = NSWorkspace.shared.frontmostApplication
        log.info("Target app at hotkey: \(targetApp?.localizedName ?? "none") (\(targetApp?.bundleIdentifier ?? "?"))")

        // Store for return-to-origin (captured before recording starts)
        startApp = targetApp
        recordingStartTime = Date()

        // START RECORDING IMMEDIATELY - don't block on context capture
        trace?.begin("recording")
        SoundManager.shared.playStart()
        AppLogger.shared.log(.audio, "Recording started", detail: "Listening for audio input...")
        ProcessingMilestones.shared.markRecordingStarted()
        NotificationCenter.default.post(name: .recordingDidStart, object: nil)
        stateMachine.transition(.startRecording)
        startElapsedTimeTimer()

        // Pass trace to audio capture service for "time to first audio" tracking
        if let audioService = audio as? AudioCaptureService {
            audioService.currentTrace = trace
        }

        audio.startCapture { [weak self] audioPaths in
            // Use @MainActor to ensure processDidFire check-then-set is atomic
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // One-shot guard: prevent duplicate process() calls
                guard !self.processDidFire else {
                    log.warning("process() already fired for this recording, ignoring duplicate callback")
                    return
                }
                self.processDidFire = true
                await self.process(segmentPaths: audioPaths)
            }
        }

        // PARALLEL: Capture context while recording (doesn't block user)
        // This runs during recording time, which is always >> 100ms
        // Note: Don't use trace?.begin() here - it would auto-end the "recording" step
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Capture baseline context
            self.capturedContext = ContextCaptureService.shared.captureBaseline()

            if let selectedText = ContextCaptureService.shared.getSelectedText(in: targetApp) {
                self.originalSelectedText = selectedText
                log.info("Captured \(selectedText.count) chars of selected text for in-place replacement")
            }

            // Check if recording started inside TalkieAgent window (for queue mode)
            // Small delay to let focus settle after menu bar click
            try? await Task.sleep(for: .milliseconds(50))
            let agentIsNowFrontmost = ContextCapture.isTalkieAgentFrontmost()
            let targetBundleID = self.capturedContext?.activeAppBundleID
            self.createdInTalkieView = agentIsNowFrontmost && (targetBundleID == "jdi.talkie.agent")

            // Log completion (context captured in background, doesn't add to latency)
            let appName = self.capturedContext?.activeAppName ?? "Unknown"
            let windowTitle = self.capturedContext?.activeWindowTitle ?? ""
            let queueNote = self.createdInTalkieView ? " [will queue]" : ""
            AppLogger.shared.log(.system, "Context captured", detail: "\(appName) — \(windowTitle.prefix(30))\(queueNote)")
        }
    }

    /// Start timer to broadcast elapsed time updates via XPC service
    private func startElapsedTimeTimer() {
        elapsedTimeTimer?.invalidate()
        elapsedTimeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime)

                // Broadcast elapsed time update via XPC
                TalkieAgentXPCService.shared.updateState(self.state.rawValue, elapsedTime: elapsed)

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

    // MARK: - Watchdog Timer (Stuck State Detection)

    /// Start watchdog timer to detect stuck states
    private func startWatchdog() {
        stopWatchdog()  // Clear any existing timer

        // Check every 5 seconds for stuck states
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForStuckState()
            }
        }
        log.info("Watchdog started")
    }

    /// Stop watchdog timer
    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// Check if current state has exceeded timeout threshold
    private func checkForStuckState() {
        guard let entryTime = stateEntryTime else { return }

        let elapsed = Date().timeIntervalSince(entryTime)
        let threshold: TimeInterval

        switch self.state {
        case .transcribing:
            threshold = transcribingTimeout
        case .routing, .refining:
            threshold = routingTimeout
        default:
            // Not a monitored state
            return
        }

        // Check if we've exceeded the timeout
        if elapsed > threshold {
            let timeoutStr = String(format: "%.0fs", elapsed)
            log.error("⏱ STUCK STATE DETECTED: \(self.state.rawValue) exceeded \(threshold)s (actual: \(timeoutStr))")
            AppLogger.shared.log(.error, "Stuck state timeout", detail: "\(self.state.rawValue) • \(timeoutStr)")

            // Recover from stuck state
            recoverFromStuckState(reason: "Timeout after \(timeoutStr)")
        }
    }

    /// Recover from stuck state by pushing to queue and resetting
    private func recoverFromStuckState(reason: String) {
        log.warning("🔧 Recovering from stuck state: \(reason)")
        AppLogger.shared.log(.system, "Auto-recovery triggered", detail: reason)

        // Cancel any in-flight transcription task
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // If we have audio, save it to queue for retry
        if let audioFilename = pendingAudioFilename {
            let captureSessionId = recordingId
            let appBundleID = capturedContext?.activeAppBundleID
            let appName = capturedContext?.activeAppName
            let windowTitle = capturedContext?.activeWindowTitle
            let durationSeconds = recordingStartTime.map { Date().timeIntervalSince($0) }
            let metadata = capturedContext.flatMap { buildMetadataDict(from: $0) }
            let selectedModelId = LiveSettings.shared.selectedModelId
            let screenshotsJSON = RecordingScreenshot.toJSON(capturedScreenshots)
            let createdInTalkieView = createdInTalkieView

            Task {
                let utterance = LiveDictation(
                    text: "[Auto-recovered - timeout]",
                    mode: "queued",
                    appBundleID: appBundleID,
                    appName: appName,
                    windowTitle: windowTitle,
                    durationSeconds: durationSeconds,
                    transcriptionModel: selectedModelId,
                    metadata: metadata,
                    audioFilename: audioFilename,
                    transcriptionStatus: .pending,
                    transcriptionError: reason,
                    createdInTalkieView: createdInTalkieView,
                    pasteTimestamp: nil
                )
                var recording = LiveRecording(from: utterance)
                let includedProvenanceIDs = await Self.applyRecordingAssets(
                    to: &recording,
                    screenshotsJSON: screenshotsJSON,
                    captureSessionId: captureSessionId
                )
                if await Self.storeRecording(
                    recording,
                    captureSessionId: captureSessionId,
                    includedProvenanceIDs: includedProvenanceIDs
                ) != nil {
                    TalkieAgentXPCService.shared.notifyDictationAdded()
                    AppLogger.shared.log(.database, "Auto-recovery: queued", detail: "Audio saved for retry")
                }
            }
        }

        // Play error sound to alert user
        NSSound.beep()

        // Clear state
        clearRecordingState()

        // Force reset to idle
        stateMachine.transition(.forceReset)
        log.info("Auto-recovery complete - reset to idle")

        // Refresh stores to show queued item
        DictationStore.shared.refresh()
    }

    // MARK: - Idle Sweep (Cleanup After Extended Inactivity)

    /// Start idle sweep timer - fires after 5 minutes of inactivity
    private func startIdleSweepTimer() {
        stopIdleSweepTimer()  // Clear any existing timer

        idleSweepTimer = Timer.scheduledTimer(withTimeInterval: idleSweepTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performIdleSweep()
            }
        }
        log.debug("Idle sweep timer started (\(Int(idleSweepTimeout))s)")
    }

    /// Stop idle sweep timer
    private func stopIdleSweepTimer() {
        idleSweepTimer?.invalidate()
        idleSweepTimer = nil
    }

    /// Perform full state reset after extended idle period
    /// Clears transcription state, buffers, and resets audio system
    private func performIdleSweep() {
        guard state == .idle else {
            log.debug("Idle sweep skipped - not idle (state=\(state.rawValue))")
            return
        }

        log.info("🧹 Idle sweep: cleaning up after \(Int(idleSweepTimeout / 60)) minutes of inactivity")
        AppLogger.shared.log(.system, "Idle sweep", detail: "Resetting state after \(Int(idleSweepTimeout / 60))m idle")

        // Clear any residual recording state
        clearRecordingState()

        // Reset consecutive failure counter
        consecutiveFailures = 0

        // Reboot audio system to ensure clean state
        // This clears any lingering HAL state, device routing issues, etc.
        Task {
            await audio.reboot()
            log.info("🧹 Idle sweep complete - audio system rebooted")
        }

        // Refresh stores in case there's stale data
        DictationStore.shared.refresh()
    }

    private func stop(interstitial: Bool = false) {
        NSLog("[AgentController] stop() called with interstitial=\(interstitial)")
        log.info("stop() called with interstitial=\(interstitial)")

        // Only override intent if explicitly requesting interstitial mode
        // This preserves any intent set earlier during recording.
        if interstitial && !intent.isInterstitial {
            intent = .interstitial
            NSLog("[AgentController] Stopping with interstitial routing (Shift-click)")
            log.info("Stopping with interstitial routing (Shift-click)")
        }
        log.info("intent after stop(): \(intent)")

        // Transition to transcribing state immediately (before audio callback fires)
        stateMachine.transition(.stopRecording)

        audio.stopCapture()

        // Safety timeout: if no audio file is produced, reset to idle with error
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            guard self.state == .transcribing, self.pendingAudioFilename == nil, !self.isCancelled else { return }
            self.handleCaptureError("No audio captured")
        }
    }

    private func process(segmentPaths: [String]) async {
        // Reset failure counters on successful capture
        consecutiveFailures = 0
        postRebootFailures = 0
        justRebooted = false
        hasShownDeviceRoutingAlert = false  // Allow showing again if issue recurs later
        let captureSessionId = recordingId

        let pipelineStart = Date()  // Track end-to-end timing
        let settings = LiveSettings.shared

        // Calculate recording duration for display (not counted as latency)
        let recordingDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let recordingDurationStr = String(format: "%.1fs", recordingDuration)

        // End recording phase with duration metadata
        trace?.end(recordingDurationStr)
        trace?.begin("file_save")

        // Helper to log timing milestones
        func logTiming(_ step: String) {
            let ms = Int(Date().timeIntervalSince(pipelineStart) * 1000)
            AppLogger.shared.log(.transcription, "⏱ \(step)", detail: "+\(ms)ms")
        }

        logTiming("Pipeline start (\(segmentPaths.count) segment\(segmentPaths.count == 1 ? "" : "s"))")

        // CRITICAL: Save audio to permanent storage FIRST before anything else.
        // For multi-segment recordings, concatenate into a single file.
        let audioFilename: String
        let allAudioFilenames: [String]

        if segmentPaths.count == 1 {
            // Single segment — just copy/move
            let tempURL = URL(fileURLWithPath: segmentPaths[0])
            guard let filename = AudioStorage.copyToStorage(tempURL) else {
                AppLogger.shared.log(.error, "Audio save failed", detail: "Could not copy temp file to storage")
                trace?.end("failed")
                trace = nil
                await discardLiveSidecarSession(captureSessionId: captureSessionId)
                stateMachine.transition(.error("Audio save failed"))
                return
            }
            audioFilename = filename
            allAudioFilenames = [filename]
            logTiming("Audio copied to storage")
        } else {
            // Multi-segment — concatenate into one WAV, keep individual segments for per-segment transcription
            let concatFilename = UUID().uuidString + ".wav"
            let concatURL = AudioStorage.url(for: concatFilename)

            // Save individual segments first (for transcription)
            var segFilenames: [String] = []
            for path in segmentPaths {
                let segURL = URL(fileURLWithPath: path)
                if let fn = AudioStorage.copyToStorage(segURL) {
                    segFilenames.append(fn)
                }
            }

            // Concatenate segments into one file
            do {
                try Self.concatenateWAVFiles(segFilenames.map { AudioStorage.url(for: $0) }, to: concatURL)
                audioFilename = concatFilename
                allAudioFilenames = segFilenames
                logTiming("\(segFilenames.count) segments concatenated → \(concatFilename)")
            } catch {
                // Fallback: use first segment as primary
                log.warning("Concatenation failed, using first segment", detail: error.localizedDescription)
                audioFilename = segFilenames.first ?? ""
                allAudioFilenames = segFilenames
            }
        }

        traceID = makeTraceID(from: audioFilename)

        // Store for push-to-queue in case user wants to bail during transcription
        pendingAudioFilename = audioFilename

        // Clean up temp files
        for path in segmentPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        logTiming("Temp file cleanup attempted")

        let fileSaveMs = Int(Date().timeIntervalSince(pipelineStart) * 1000)

        // Get total size from all permanent files
        var totalAudioSizeBytes = 0
        for fn in allAudioFilenames {
            let url = AudioStorage.url(for: fn)
            totalAudioSizeBytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        let audioSizeBytes = totalAudioSizeBytes
        let audioSizeKB = Double(audioSizeBytes) / 1024.0
        let fileSizeStr = String(format: "%.1f KB", audioSizeKB)
        #if DEBUG
        let traceSuffix = traceID.map { " • trace=\($0)" } ?? ""
        #else
        let traceSuffix = ""
        #endif
        AppLogger.shared.log(.file, "Audio saved", detail: "\(audioFilename) (\(fileSizeStr)) • \(fileSaveMs)ms\(traceSuffix)")

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

        // We're already in transcribing state (stop() transitioned us)
        let engineStart = Date()

        // Log transcription start with model info and overhead
        let modelName = settings.selectedModelId
        let preMs = Int(engineStart.timeIntervalSince(pipelineStart) * 1000)  // Time from stop-recording to engine-submit
        AppLogger.shared.log(.transcription, "Transcribing...", detail: "Model: \(modelName) • pre: \(preMs)ms\(traceSuffix)")

        // Track milestone
        ProcessingMilestones.shared.markTranscribing()

        // Use trace's ID for Engine correlation (so E2E view can link them)
        let externalRefId = trace?.traceId ?? String(UUID().uuidString.prefix(8)).lowercased()

        // End file save step before deciding whether to transcribe
        trace?.end(fileSizeStr)
        trace?.externalRefId = externalRefId  // Already the same, but kept for reference

        // If user cancelled during listening, skip transcription entirely
        if isCancelled {
            let audioPath = AudioStorage.url(for: audioFilename).path
            log.info("Recording cancelled - skipping transcription", detail: "Audio saved: \(audioPath)")
            AppLogger.shared.log(.system, "Recording cancelled", detail: "Audio saved: \(audioFilename)")
            await discardLiveSidecarSession(captureSessionId: captureSessionId)
            clearRecordingState()
            stateMachine.transition(.complete)
            return
        }

        await processPendingLiveSidecarSegments(
            captureSessionId: captureSessionId,
            audioFilenames: allAudioFilenames
        )

        // Begin engine transcription
        trace?.begin("engine")

        // Determine post-processing before transcription — context rule drives Engine behavior
        let matchedContextRule: ContextRule? = if !createdInTalkieView {
            ContextRuleStore.shared.matchingRule(for: capturedContext?.activeAppBundleID)
        } else {
            nil
        }
        let postProcess: PostProcessOption = if matchedContextRule?.behavior == .protocolProcessor {
            .proceduralProcessor
        } else {
            .dictionary
        }

        do {
            // Transcribe each segment, offset timestamps, concatenate
            logTiming("Sending to engine (\(allAudioFilenames.count) segment\(allAudioFilenames.count == 1 ? "" : "s"))")

            var allText = ""
            var allWords: [WordSegment] = []
            var cumulativeOffset: Double = 0

            for (segIdx, segFilename) in allAudioFilenames.enumerated() {
                let segPath = AudioStorage.url(for: segFilename).path
                let request = TranscriptionRequest(audioPath: segPath, isLive: true, externalRefId: externalRefId, postProcess: postProcess)
                let segResult = try await transcription.transcribe(request)

                let segText = segResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !segText.isEmpty {
                    if !allText.isEmpty { allText += " " }
                    allText += segText
                }

                // Offset word timestamps by cumulative duration of prior segments
                if let timed = segResult.timedTranscription {
                    let offsetWords = timed.words.map { word in
                        WordSegment(
                            word: word.word,
                            start: word.start + cumulativeOffset,
                            end: word.end + cumulativeOffset,
                            confidence: word.confidence
                        )
                    }
                    allWords.append(contentsOf: offsetWords)

                    // Use the last word's end time (or segment duration) as offset for next segment
                    if let lastEnd = timed.words.last?.end {
                        cumulativeOffset += lastEnd
                    }
                }

                if allAudioFilenames.count > 1 {
                    logTiming("Segment \(segIdx + 1)/\(allAudioFilenames.count) transcribed")
                }
            }
            logTiming("Engine returned")

            // Build merged result that the rest of the pipeline can use unchanged
            let result = Transcript(
                text: allText,
                confidence: nil,
                timedTranscription: allWords.isEmpty ? nil : TimedTranscription(text: allText, words: allWords)
            )
            let timedTranscription = result.timedTranscription
            let segmentsJSON = timedTranscription?.toJSON()

            // Handle empty transcription (silence) gracefully - this is valid, not an error
            let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                log.info("Transcription returned silence - nothing to paste")
                AppLogger.shared.log(.transcription, "Silence detected", detail: "No text to paste\(traceSuffix)")

                // Reset state and complete - no error, no retry
                await discardLiveSidecarSession(captureSessionId: captureSessionId)
                clearRecordingState()
                stateMachine.transition(.complete)
                return
            }

            let engineEnd = Date()

            // End engine step
            let transcriptionMs = Int(engineEnd.timeIntervalSince(engineStart) * 1000)
            trace?.end("\(transcriptionMs)ms")
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
            var metadata = capturedContext ?? DictationMetadata()
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
                log.info("Recording cancelled - audio preserved at: \(audioPath)")
                AppLogger.shared.log(.system, "Recording cancelled", detail: "Audio saved: \(audioFilename)")

                // Reset state
                clearRecordingState()

                // Complete the flow (user cancelled)
                stateMachine.transition(.complete)
                return
            }

            // Transition to routing state
            stateMachine.transition(.beginRouting)
            logTiming("State → routing")

            // Track milestone
            ProcessingMilestones.shared.markRouting()

            // Interleave screenshots with transcript if both are available
            let notesMarkdown: String? = if !capturedScreenshots.isEmpty, let timed = timedTranscription {
                ScreenshotInserter.interleave(
                    timedTranscription: timed,
                    screenshots: capturedScreenshots,
                    screenshotDirectory: ScreenshotStorage.screenshotsDirectory
                ).markdown
            } else {
                nil
            }

            // Use interleaved text (with screenshot refs) for pasting when available
            let textToPaste = notesMarkdown ?? result.text

            // Save as Memo mode: Shift+A to auto-promote to permanent memo
            if case .saveMemo = intent {
                NSLog("[AgentController] === SAVE AS MEMO MODE ACTIVATED ===")
                log.info("=== SAVE AS MEMO MODE ACTIVATED ===")
                AppLogger.shared.log(.system, "Saving as memo", detail: "Shift+A mode")

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

                // Store in GRDB first
                logTiming("Creating LiveDictation for memo")
                let dictation = LiveDictation(
                    text: result.text,
                    mode: "memo",  // Mark as memo mode
                    appBundleID: metadata.activeAppBundleID,
                    appName: metadata.activeAppName,
                    windowTitle: metadata.activeWindowTitle,
                    durationSeconds: durationSeconds,
                    transcriptionModel: metadata.transcriptionModel,
                    perfEngineMs: transcriptionMs,
                    perfEndToEndMs: metadata.perfEndToEndMs,
                    perfInAppMs: metadata.perfInAppMs,
                    sessionID: externalRefId,
                    metadata: buildMetadataDict(from: metadata),
                    audioFilename: audioFilename,
                    createdInTalkieView: createdInTalkieView,
                    pasteTimestamp: Date()  // Mark as delivered
                )

                var recording = LiveRecording(from: dictation)
                let includedProvenanceIDs = await Self.applyRecordingAssets(
                    to: &recording,
                    segmentsJSON: segmentsJSON,
                    screenshotsJSON: RecordingScreenshot.toJSON(capturedScreenshots),
                    captureSessionId: captureSessionId
                )
                recording.notes = notesMarkdown
                if let id = await Self.storeRecording(
                    recording,
                    captureSessionId: captureSessionId,
                    includedProvenanceIDs: includedProvenanceIDs
                ) {
                    logTiming("UnifiedDatabase stored")

                    // Notify Talkie via XPC
                    TalkieAgentXPCService.shared.notifyDictationAdded()

                    // Refresh pending count to clear queue indicator on successful recording
                    TranscriptionRetryManager.shared.refreshPendingCount()

                    // Schedule enrichment (includes bridge context mapping)
                    // Copy performance metrics to baseline so they're preserved during enrichment
                    if var baseline = capturedContext {
                        baseline.perfEngineMs = metadata.perfEngineMs
                        baseline.perfEndToEndMs = metadata.perfEndToEndMs
                        baseline.perfInAppMs = metadata.perfInAppMs
                        baseline.sessionID = metadata.sessionID
                        ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline, dictationText: result.text)
                    }

                    // Auto-promote to memo (uses existing QuickActionRunner)
                    logTiming("Auto-promoting to memo")
                    Task {
                        await QuickActionRunner.shared.run(.promoteToMemo, for: dictation)
                    }
                    AppLogger.shared.log(.system, "Auto-promoted to memo", detail: "ID: \(id.uuidString.prefix(8))")
                }

                // Play success sound
                SoundManager.shared.playPasted()
                logTiming("Sound triggered")

                // Reset state and finish
                clearRecordingState()

                // Complete the flow
                stateMachine.transition(.complete)

                // Refresh stores
                DictationStore.shared.refresh()
                logTiming("Pipeline complete (saved as memo)")
                return
            }

            // Interstitial mode: Shift or Shift+S to route to Talkie Core for editing
            NSLog("[AgentController] Checking intent for interstitial: \(self.intent)")
            log.info("Checking intent for interstitial: \(self.intent)")
            if intent.isInterstitial {
                NSLog("[AgentController] === INTERSTITIAL MODE ACTIVATED ===")
                log.info("=== INTERSTITIAL MODE ACTIVATED ===")
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
                // Include original selection context for Command+Enter replacement
                logTiming("Creating LiveDictation for interstitial")
                var interstitialMetadata = buildMetadataDict(from: metadata) ?? [:]
                if let originalText = originalSelectedText {
                    interstitialMetadata["originalSelectedText"] = originalText
                }
                if let sourceAppBundleID = startApp?.bundleIdentifier {
                    interstitialMetadata["sourceAppBundleID"] = sourceAppBundleID
                }
                let utterance = LiveDictation(
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
                    metadata: interstitialMetadata.isEmpty ? nil : interstitialMetadata,
                    audioFilename: audioFilename,
                    createdInTalkieView: createdInTalkieView,
                    pasteTimestamp: nil  // Not pasted yet → interstitial will handle
                )

                var recording = LiveRecording(from: utterance)
                let includedProvenanceIDs = await Self.applyRecordingAssets(
                    to: &recording,
                    segmentsJSON: segmentsJSON,
                    screenshotsJSON: RecordingScreenshot.toJSON(capturedScreenshots),
                    captureSessionId: captureSessionId
                )
                recording.notes = notesMarkdown
                if let id = await Self.storeRecording(
                    recording,
                    captureSessionId: captureSessionId,
                    includedProvenanceIDs: includedProvenanceIDs
                ) {
                    logTiming("UnifiedDatabase stored")

                    // Notify Talkie via XPC (non-blocking)
                    TalkieAgentXPCService.shared.notifyDictationAdded()

                    // Refresh pending count to clear queue indicator on successful recording
                    TranscriptionRetryManager.shared.refreshPendingCount()

                    // Schedule enrichment (includes bridge context mapping)
                    // Copy performance metrics to baseline so they're preserved during enrichment
                    if var baseline = capturedContext {
                        baseline.perfEngineMs = metadata.perfEngineMs
                        baseline.perfEndToEndMs = metadata.perfEndToEndMs
                        baseline.perfInAppMs = metadata.perfInAppMs
                        baseline.sessionID = metadata.sessionID
                        ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline, dictationText: result.text)
                    }

                    // Show interstitial editor directly (TalkieAgent owns this panel)
                    launchInterstitialEditor(utteranceId: id)
                    logTiming("Interstitial shown")
                }

                // Play sound to confirm
                SoundManager.shared.playPasted()
                logTiming("Sound triggered")

                // Reset state and finish
                clearRecordingState()

                // Complete the flow (interstitial routing done)
                stateMachine.transition(.complete)

                // Refresh stores
                DictationStore.shared.refresh()
                logTiming("Pipeline complete (interstitial)")
                return
            }

            // Context rule check: app-aware post-transcription routing
            // matchedContextRule was resolved before transcription (drives Engine postProcess)
            Self.debugLog("Context rule check: createdInTalkieView=\(createdInTalkieView), bundleID=\(capturedContext?.activeAppBundleID ?? "nil")")
            if let contextRule = matchedContextRule {
                Self.debugLog("Context rule MATCHED: \(contextRule.name) (\(contextRule.behavior.rawValue)) provider=\(contextRule.llmProviderId ?? "nil") model=\(contextRule.llmModelId ?? "nil")")
                log.info("Context rule matched: \(contextRule.name) (\(contextRule.behavior.rawValue))")
                AppLogger.shared.log(.system, "Context rule matched", detail: "\(contextRule.name) → \(contextRule.behavior.rawValue)")

                switch contextRule.behavior {
                case .autoRefine:
                    // Auto-refine: call LLM, paste refined text
                    stateMachine.transition(.beginRefining)
                    let refineStart = Date()
                    let refinedText = await autoRefine(
                        text: textToPaste,
                        rule: contextRule,
                        pipelineStart: pipelineStart
                    )
                    let refineMs = Int(Date().timeIntervalSince(refineStart) * 1000)

                    let routingMode = settings.routingMode == .paste ? "Paste" : "Clipboard"
                    trace?.begin("paste")
                    await router.handle(transcript: refinedText ?? textToPaste)
                    let pasteMs = trace?.end(routingMode) ?? 0
                    logTiming("Router finished (\(pasteMs)ms)")
                    metadata.wasRouted = true

                    let routeEnd = Date()
                    let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)
                    let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                    let appMs = max(0, totalMs - transcriptionMs)

                    metadata.perfEndToEndMs = totalMs
                    metadata.perfInAppMs = appMs
                    metadata.perfPreMs = preMs
                    metadata.perfPostMs = postMs

                    // Build metadata with refinement info
                    var metadataDict = buildMetadataDict(from: metadata) ?? [:]
                    if let refined = refinedText {
                        metadataDict["refinement.rawText"] = result.text
                        metadataDict["refinement.refined"] = refined
                        metadataDict["refinement.prompt"] = contextRule.prompt
                        metadataDict["refinement.ruleName"] = contextRule.name
                        metadataDict["refinement.latencyMs"] = "\(refineMs)"
                        // Record which LLM was used for refinement
                        if let providerId = contextRule.llmProviderId, let modelId = contextRule.llmModelId {
                            metadataDict["refinement.model"] = "\(providerId)/\(modelId)"
                        } else if let fallback = await LLMProviderRegistry.shared.resolveProviderAndModel() {
                            metadataDict["refinement.model"] = "\(fallback.provider.name)/\(fallback.modelId)"
                        }
                    }

                    Self.debugLog("metadataDict keys: \(metadataDict.keys.sorted().joined(separator: ", "))")
                    if let rawText = metadataDict["refinement.rawText"] {
                        Self.debugLog("refinement.rawText: \(rawText.prefix(60))")
                    } else {
                        Self.debugLog("NO refinement keys in metadataDict")
                    }

                    let capturedMetadata = metadata
                    let capturedContext = self.capturedContext
                    let capturedStartApp = self.startApp
                    let finalText = refinedText ?? result.text
                    let currentTrace = trace
                    let returnToOrigin = settings.returnToOriginAfterPaste
                    let routingModeStr = settings.routingMode == .paste ? "paste" : "clipboard"
                    let screenshotsJSON = RecordingScreenshot.toJSON(self.capturedScreenshots)
                    let notesForPaste = notesMarkdown
                    let capturedRecordingId = self.recordingId

                    Task.detached { [transcriptionMs, wordCount, externalRefId, audioFilename, durationSeconds, traceSuffix, totalMs, appMs, segmentsJSON, screenshotsJSON, notesForPaste, capturedRecordingId, metadataDict] in
                        await MainActor.run { SoundManager.shared.playPasted() }

                        if returnToOrigin,
                           let originApp = capturedStartApp,
                           capturedMetadata.contextChanged {
                            await MainActor.run { ContextCapture.activateApp(originApp) }
                        }

                        var mergedScreenshotsJSON = screenshotsJSON
                        if let recId = capturedRecordingId {
                            if let trayJSON = await TalkieAgentXPCService.shared.fetchTrayScreenshots(recordingId: recId) {
                                if let base = screenshotsJSON,
                                   let baseData = base.data(using: .utf8),
                                   let trayData = trayJSON.data(using: .utf8),
                                   var baseArray = try? JSONSerialization.jsonObject(with: baseData) as? [[String: Any]],
                                   let trayArray = try? JSONSerialization.jsonObject(with: trayData) as? [[String: Any]] {
                                    baseArray.append(contentsOf: trayArray)
                                    if let merged = try? JSONSerialization.data(withJSONObject: baseArray),
                                       let mergedStr = String(data: merged, encoding: .utf8) {
                                        mergedScreenshotsJSON = mergedStr
                                    }
                                } else {
                                    mergedScreenshotsJSON = trayJSON
                                }
                            }
                        }

                        let utterance = LiveDictation(
                            text: finalText,
                            mode: routingModeStr,
                            appBundleID: capturedMetadata.activeAppBundleID,
                            appName: capturedMetadata.activeAppName,
                            windowTitle: capturedMetadata.activeWindowTitle,
                            durationSeconds: durationSeconds,
                            transcriptionModel: capturedMetadata.transcriptionModel,
                            perfEngineMs: transcriptionMs,
                            perfEndToEndMs: capturedMetadata.perfEndToEndMs,
                            perfInAppMs: capturedMetadata.perfInAppMs,
                            sessionID: externalRefId,
                            metadata: metadataDict.isEmpty ? nil : metadataDict,
                            audioFilename: audioFilename,
                            createdInTalkieView: false,
                            pasteTimestamp: Date()
                        )

                        var recording = LiveRecording(from: utterance)
                        let includedProvenanceIDs = await Self.applyRecordingAssets(
                            to: &recording,
                            segmentsJSON: segmentsJSON,
                            screenshotsJSON: mergedScreenshotsJSON,
                            captureSessionId: capturedRecordingId
                        )
                        recording.notes = notesForPaste
                        if let id = await Self.storeRecording(
                            recording,
                            captureSessionId: capturedRecordingId,
                            includedProvenanceIDs: includedProvenanceIDs
                        ), var baseline = capturedContext {
                            if let recId = capturedRecordingId {
                                await TalkieAgentXPCService.shared.notifyDictationPasted(recordingId: recId)
                            }
                            await TalkieAgentXPCService.shared.notifyDictationAdded()
                            await TranscriptionRetryManager.shared.refreshPendingCount()
                            baseline.perfEngineMs = capturedMetadata.perfEngineMs
                            baseline.perfEndToEndMs = capturedMetadata.perfEndToEndMs
                            baseline.perfInAppMs = capturedMetadata.perfInAppMs
                            baseline.sessionID = capturedMetadata.sessionID
                            await ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline, dictationText: finalText)
                        }

                        await MainActor.run { DictationStore.shared.refresh() }

                        let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", Double(transcriptionMs) / 1000)
                        await AppLogger.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")

                        await MainActor.run {
                            currentTrace?.end()
                            if let trace = currentTrace {
                                let metric = LiveTraceMetric(
                                    from: trace,
                                    wordCount: wordCount,
                                    audioFilename: audioFilename,
                                    audioDurationSeconds: durationSeconds,
                                    transcriptPreview: String(finalText.prefix(50))
                                )
                                LivePerformanceStore.shared.add(metric)
                                AppLogger.shared.log(.performance, "Trace complete", detail: trace.summary)
                            }
                            currentTrace?.invalidate()
                            ProcessingMilestones.shared.markSuccess()
                        }
                    }

                    clearRecordingState(invalidateTrace: false)
                    stateMachine.transition(.complete)
                    DictationStore.shared.refresh()
                    logTiming("Pipeline complete (context rule: auto-refine)")
                    return

                case .autoInterstitial:
                    // Auto-interstitial: route to interstitial with context prompt pre-applied
                    let routeEnd = Date()
                    let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)
                    let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                    let appMs = max(0, totalMs - transcriptionMs)

                    metadata.perfEndToEndMs = totalMs
                    metadata.perfInAppMs = appMs
                    metadata.perfPreMs = preMs
                    metadata.perfPostMs = postMs

                    var interstitialMetadata = buildMetadataDict(from: metadata) ?? [:]
                    interstitialMetadata["contextPrompt"] = contextRule.prompt
                    interstitialMetadata["contextRuleName"] = contextRule.name

                    let utterance = LiveDictation(
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
                        sessionID: externalRefId,
                        metadata: interstitialMetadata.isEmpty ? nil : interstitialMetadata,
                        audioFilename: audioFilename,
                        createdInTalkieView: createdInTalkieView,
                        pasteTimestamp: nil
                    )

                    var recording = LiveRecording(from: utterance)
                    let includedProvenanceIDs = await Self.applyRecordingAssets(
                        to: &recording,
                        segmentsJSON: segmentsJSON,
                        screenshotsJSON: RecordingScreenshot.toJSON(capturedScreenshots),
                        captureSessionId: captureSessionId
                    )
                    recording.notes = notesMarkdown
                    if let id = await Self.storeRecording(
                        recording,
                        captureSessionId: captureSessionId,
                        includedProvenanceIDs: includedProvenanceIDs
                    ) {
                        TalkieAgentXPCService.shared.notifyDictationAdded()
                        TranscriptionRetryManager.shared.refreshPendingCount()

                        if var baseline = capturedContext {
                            baseline.perfEngineMs = metadata.perfEngineMs
                            baseline.perfEndToEndMs = metadata.perfEndToEndMs
                            baseline.perfInAppMs = metadata.perfInAppMs
                            baseline.sessionID = metadata.sessionID
                            ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline, dictationText: result.text)
                        }

                        launchInterstitialEditor(
                            utteranceId: id,
                            contextPrompt: contextRule.prompt,
                            contextRuleName: contextRule.name
                        )
                        logTiming("Interstitial shown (context rule)")
                    }

                    SoundManager.shared.playPasted()
                    clearRecordingState()
                    stateMachine.transition(.complete)
                    DictationStore.shared.refresh()
                    logTiming("Pipeline complete (context rule: auto-interstitial)")
                    return

                case .protocolProcessor:
                    // Engine already ran ProceduralProcessor — result.text is the processed output
                    let processedText = result.text
                    log.info("Protocol processor (engine): \(processedText.prefix(60))")
                    AppLogger.shared.log(.system, "Protocol processor applied (engine)", detail: "\(processedText.prefix(60))")

                    let routingMode = settings.routingMode == .paste ? "Paste" : "Clipboard"
                    trace?.begin("paste")
                    await router.handle(transcript: processedText)
                    let pasteMs = trace?.end(routingMode) ?? 0
                    logTiming("Router finished (\(pasteMs)ms)")
                    metadata.wasRouted = true

                    let routeEnd = Date()
                    let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)
                    let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                    let appMs = max(0, totalMs - transcriptionMs)

                    metadata.perfEndToEndMs = totalMs
                    metadata.perfInAppMs = appMs
                    metadata.perfPreMs = preMs
                    metadata.perfPostMs = postMs

                    var metadataDict = buildMetadataDict(from: metadata) ?? [:]
                    metadataDict["processor.processedText"] = processedText
                    metadataDict["processor.ruleName"] = contextRule.name

                    let capturedMetadata = metadata
                    let capturedContext = self.capturedContext
                    let capturedStartApp = self.startApp
                    let currentTrace = trace
                    let returnToOrigin = settings.returnToOriginAfterPaste
                    let screenshotsJSON = RecordingScreenshot.toJSON(self.capturedScreenshots)
                    let notesForPaste = notesMarkdown
                    let capturedRecordingId = self.recordingId

                    Task.detached { [transcriptionMs, wordCount, externalRefId, audioFilename, durationSeconds, traceSuffix, totalMs, appMs, segmentsJSON, screenshotsJSON, notesForPaste, capturedRecordingId, metadataDict] in
                        await MainActor.run { SoundManager.shared.playPasted() }

                        if returnToOrigin,
                           let originApp = capturedStartApp,
                           capturedMetadata.contextChanged {
                            await MainActor.run { ContextCapture.activateApp(originApp) }
                        }

                        let utterance = LiveDictation(
                            text: processedText,
                            mode: "pasted",
                            appBundleID: capturedMetadata.activeAppBundleID,
                            appName: capturedMetadata.activeAppName,
                            windowTitle: capturedMetadata.activeWindowTitle,
                            durationSeconds: durationSeconds,
                            transcriptionModel: capturedMetadata.transcriptionModel,
                            perfEngineMs: transcriptionMs,
                            perfEndToEndMs: capturedMetadata.perfEndToEndMs,
                            perfInAppMs: capturedMetadata.perfInAppMs,
                            sessionID: externalRefId,
                            metadata: metadataDict.isEmpty ? nil : metadataDict,
                            audioFilename: audioFilename,
                            createdInTalkieView: false,
                            pasteTimestamp: Date()
                        )

                        var recording = LiveRecording(from: utterance)
                        let includedProvenanceIDs = await Self.applyRecordingAssets(
                            to: &recording,
                            segmentsJSON: segmentsJSON,
                            screenshotsJSON: screenshotsJSON,
                            captureSessionId: capturedRecordingId
                        )
                        recording.notes = notesForPaste
                        if let id = await Self.storeRecording(
                            recording,
                            captureSessionId: capturedRecordingId,
                            includedProvenanceIDs: includedProvenanceIDs
                        ), var baseline = capturedContext {
                            if let recId = capturedRecordingId {
                                await TalkieAgentXPCService.shared.notifyDictationPasted(recordingId: recId)
                            }
                            await TalkieAgentXPCService.shared.notifyDictationAdded()
                            await TranscriptionRetryManager.shared.refreshPendingCount()
                            baseline.perfEngineMs = capturedMetadata.perfEngineMs
                            baseline.perfEndToEndMs = capturedMetadata.perfEndToEndMs
                            baseline.perfInAppMs = capturedMetadata.perfInAppMs
                            baseline.sessionID = capturedMetadata.sessionID
                            await ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline, dictationText: processedText)
                        }

                        await MainActor.run { DictationStore.shared.refresh() }

                        let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", Double(transcriptionMs) / 1000)
                        await AppLogger.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")

                        await MainActor.run {
                            currentTrace?.end()
                            if let trace = currentTrace {
                                let metric = LiveTraceMetric(
                                    from: trace,
                                    wordCount: wordCount,
                                    audioFilename: audioFilename,
                                    audioDurationSeconds: durationSeconds,
                                    transcriptPreview: String(processedText.prefix(50))
                                )
                                LivePerformanceStore.shared.add(metric)
                            }
                            currentTrace?.invalidate()
                            ProcessingMilestones.shared.markSuccess()
                        }
                    }

                    clearRecordingState(invalidateTrace: false)
                    stateMachine.transition(.complete)
                    DictationStore.shared.refresh()
                    logTiming("Pipeline complete (context rule: protocol-processor)")
                    return
                }
            }

            // Decide: queue or paste immediately?
            if createdInTalkieView {
                // Created inside Talkie Agent → queue it (don't paste)
                AppLogger.shared.log(.system, "Queueing transcript", detail: "Created in Talkie Agent")

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
                logTiming("Creating LiveDictation")
                let utterance = LiveDictation(
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
                var recording = LiveRecording(from: utterance)
                let includedProvenanceIDs = await Self.applyRecordingAssets(
                    to: &recording,
                    segmentsJSON: segmentsJSON,
                    screenshotsJSON: RecordingScreenshot.toJSON(capturedScreenshots),
                    captureSessionId: captureSessionId
                )
                recording.notes = notesMarkdown
                if let id = await Self.storeRecording(
                    recording,
                    captureSessionId: captureSessionId,
                    includedProvenanceIDs: includedProvenanceIDs
                ), var baseline = capturedContext {
                    TalkieAgentXPCService.shared.notifyDictationAdded()
                    TranscriptionRetryManager.shared.refreshPendingCount()
                    // Copy performance metrics to baseline so they're preserved during enrichment
                    baseline.perfEngineMs = metadata.perfEngineMs
                    baseline.perfEndToEndMs = metadata.perfEndToEndMs
                    baseline.perfInAppMs = metadata.perfInAppMs
                    baseline.sessionID = metadata.sessionID
                    ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline, dictationText: result.text)
                }
                logTiming("Database stored")

            } else {
                // Normal flow: paste immediately
                let routingMode = settings.routingMode == .paste ? "Paste" : "Clipboard"
                AppLogger.shared.log(.system, "Routing transcript", detail: "\(routingMode) mode")

                // Trace ONLY the actual paste operation
                trace?.begin("paste")
                await router.handle(transcript: textToPaste)
                let pasteMs = trace?.end(routingMode) ?? 0
                logTiming("Router finished (\(pasteMs)ms)")
                metadata.wasRouted = true

                // Calculate timing metrics immediately after paste
                let routeEnd = Date()
                let totalMs = Int(routeEnd.timeIntervalSince(pipelineStart) * 1000)
                let postMs = Int(routeEnd.timeIntervalSince(engineEnd) * 1000)
                let appMs = max(0, totalMs - transcriptionMs)

                metadata.perfEndToEndMs = totalMs
                metadata.perfInAppMs = appMs
                metadata.perfPreMs = preMs
                metadata.perfPostMs = postMs

                // CRITICAL PATH ENDS HERE - text is pasted, user can continue
                // Everything below runs in background, doesn't block user

                // Capture ALL values needed for background work (must capture before Task)
                let capturedMetadata = metadata
                let capturedContext = self.capturedContext
                let capturedStartApp = self.startApp
                let resultText = result.text
                let metadataDict = buildMetadataDict(from: metadata)
                let currentTrace = trace
                let returnToOrigin = settings.returnToOriginAfterPaste
                let routingModeStr = settings.routingMode == .paste ? "paste" : "clipboard"
                let screenshotsJSON = RecordingScreenshot.toJSON(self.capturedScreenshots)
                let notesForPaste = notesMarkdown
                let capturedRecordingId = self.recordingId

                // Fire-and-forget: ALL post-paste work runs in background
                Task.detached { [transcriptionMs, wordCount, externalRefId, audioFilename, durationSeconds, traceSuffix, totalMs, appMs, segmentsJSON, screenshotsJSON, notesForPaste, capturedRecordingId] in
                    // Play sound
                    await MainActor.run { SoundManager.shared.playPasted() }

                    // Return to origin app if enabled (do this early for better UX)
                    if returnToOrigin,
                       let originApp = capturedStartApp,
                       capturedMetadata.contextChanged {
                        await MainActor.run { ContextCapture.activateApp(originApp) }
                    }

                    // Pull tray screenshots from Talkie (all unpinned items)
                    // This is included in the initial DB write — no merge needed later
                    var mergedScreenshotsJSON = screenshotsJSON
                    if let recId = capturedRecordingId {
                        if let trayJSON = await TalkieAgentXPCService.shared.fetchTrayScreenshots(recordingId: recId) {
                            // Merge during-recording screenshots with tray screenshots
                            if let base = screenshotsJSON,
                               let baseData = base.data(using: .utf8),
                               let trayData = trayJSON.data(using: .utf8),
                               var baseArray = try? JSONSerialization.jsonObject(with: baseData) as? [[String: Any]],
                               let trayArray = try? JSONSerialization.jsonObject(with: trayData) as? [[String: Any]] {
                                baseArray.append(contentsOf: trayArray)
                                if let merged = try? JSONSerialization.data(withJSONObject: baseArray),
                                   let mergedStr = String(data: merged, encoding: .utf8) {
                                    mergedScreenshotsJSON = mergedStr
                                }
                            } else {
                                // No during-recording screenshots — tray screenshots are the only ones
                                mergedScreenshotsJSON = trayJSON
                            }
                        }
                    }

                    // Database store
                    let utterance = LiveDictation(
                        text: resultText,
                        mode: routingModeStr,
                        appBundleID: capturedMetadata.activeAppBundleID,
                        appName: capturedMetadata.activeAppName,
                        windowTitle: capturedMetadata.activeWindowTitle,
                        durationSeconds: durationSeconds,
                        transcriptionModel: capturedMetadata.transcriptionModel,
                        perfEngineMs: transcriptionMs,
                        perfEndToEndMs: capturedMetadata.perfEndToEndMs,
                        perfInAppMs: capturedMetadata.perfInAppMs,
                        sessionID: externalRefId,
                        metadata: metadataDict,
                        audioFilename: audioFilename,
                        createdInTalkieView: false,
                        pasteTimestamp: Date()
                    )

                    var recording = LiveRecording(from: utterance)
                    let includedProvenanceIDs = await Self.applyRecordingAssets(
                        to: &recording,
                        segmentsJSON: segmentsJSON,
                        screenshotsJSON: mergedScreenshotsJSON,
                        captureSessionId: capturedRecordingId
                    )
                    recording.notes = notesForPaste
                    if let id = await Self.storeRecording(
                        recording,
                        captureSessionId: capturedRecordingId,
                        includedProvenanceIDs: includedProvenanceIDs
                    ), var baseline = capturedContext {
                        // DB store complete — notify Talkie to clear unpinned tray items
                        if let recId = capturedRecordingId {
                            await TalkieAgentXPCService.shared.notifyDictationPasted(recordingId: recId)
                        }
                        await TalkieAgentXPCService.shared.notifyDictationAdded()
                        await TranscriptionRetryManager.shared.refreshPendingCount()
                        // Copy performance metrics to baseline so they're preserved during enrichment
                        baseline.perfEngineMs = capturedMetadata.perfEngineMs
                        baseline.perfEndToEndMs = capturedMetadata.perfEndToEndMs
                        baseline.perfInAppMs = capturedMetadata.perfInAppMs
                        baseline.sessionID = capturedMetadata.sessionID
                        await ContextCaptureService.shared.scheduleEnrichment(utteranceId: id, baseline: baseline, dictationText: resultText)
                    }

                    // Refresh store
                    await MainActor.run { DictationStore.shared.refresh() }

                    // Logging (low priority)
                    let transcriptionTimeStr = transcriptionMs < 1000 ? "\(transcriptionMs)ms" : String(format: "%.1fs", Double(transcriptionMs) / 1000)
                    await AppLogger.shared.log(.transcription, "Transcription complete", detail: "\(wordCount) words • \(transcriptionTimeStr) • app: \(appMs)ms • e2e: \(totalMs)ms\(traceSuffix)")

                    // Finalize trace
                    await MainActor.run {
                        currentTrace?.end()
                        if let trace = currentTrace {
                            let metric = LiveTraceMetric(
                                from: trace,
                                wordCount: wordCount,
                                audioFilename: audioFilename,
                                audioDurationSeconds: durationSeconds,
                                transcriptPreview: String(resultText.prefix(50))
                            )
                            LivePerformanceStore.shared.add(metric)
                            // Log for E2ETraceView correlation (matches Engine format)
                            AppLogger.shared.log(.performance, "Trace complete", detail: trace.summary)
                        }
                        // Clean up trace after we're done with it
                        currentTrace?.invalidate()
                        ProcessingMilestones.shared.markSuccess()
                    }
                }
            }

        } catch {
            log.error("Transcription error: \(error.localizedDescription)")
            AppLogger.shared.log(.error, "Transcription failed", detail: "\(error.localizedDescription)\(traceSuffix)")

            // Even on failure, we saved the audio - store a record for retry
            // audioFilename is guaranteed valid (we guard at the start of process())
            AppLogger.shared.log(.file, "Audio preserved", detail: "\(audioFilename) - queued for retry")

            // Store a record with failed status so we can retry later
            let utterance = LiveDictation(
                text: "",
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
            var recording = LiveRecording(from: utterance)
            let includedProvenanceIDs = await Self.applyRecordingAssets(
                to: &recording,
                screenshotsJSON: RecordingScreenshot.toJSON(capturedScreenshots),
                captureSessionId: captureSessionId
            )
            if await Self.storeRecording(
                recording,
                captureSessionId: captureSessionId,
                includedProvenanceIDs: includedProvenanceIDs
            ) != nil {
                TalkieAgentXPCService.shared.notifyDictationAdded()
            }

            AppLogger.shared.log(.database, "Failed record stored", detail: "Will retry when engine available")

            // Transition to idle with error
            clearRecordingState()
            stateMachine.transition(.error(error.localizedDescription))
            return
        }

        // Success path - complete the flow
        // Note: Don't invalidate trace here - the Task.detached above handles trace.end()
        // and trace finalization. Invalidating here would race with the detached task.
        clearRecordingState(invalidateTrace: false)
        stateMachine.transition(.complete)
    }

    // MARK: - Metadata Helpers

    /// Build metadata dictionary with rich context for database storage
    private func buildMetadataDict(from metadata: DictationMetadata) -> [String: String]? {
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

    /// Launch the interstitial editor directly (no URL scheme needed)
    /// TalkieAgent owns the interstitial panel - voice dictation works immediately
    private func launchInterstitialEditor(utteranceId: UUID, contextPrompt: String? = nil, contextRuleName: String? = nil) {
        log.info("Launching interstitial editor for utterance \(utteranceId.uuidString.prefix(8))")
        InterstitialPanelController.shared.show(
            dictationId: utteranceId,
            contextPrompt: contextPrompt,
            contextRuleName: contextRuleName
        )
    }

    // MARK: - Context Rule Auto-Refine

    /// Call LLM to refine transcribed text using a context rule's prompt.
    /// Returns refined text on success, nil on timeout/error (caller falls back to raw text).
    private func autoRefine(text: String, rule: ContextRule, pipelineStart: Date) async -> String? {
        let providerId = rule.llmProviderId ?? ""
        let modelId = rule.llmModelId ?? ""

        // Cloud provider — resolve from registry
        let registry = LLMProviderRegistry.shared
        let resolved: (provider: any LLMProvider, modelId: String)
        if let provider = registry.provider(for: providerId), !modelId.isEmpty {
            resolved = (provider, modelId)
        } else if let fallback = await registry.resolveProviderAndModel() {
            resolved = fallback
        } else {
            log.warning("Auto-refine: no LLM provider available, using raw text")
            return nil
        }

        let prompt = """
        You are helping refine transcribed speech. Apply the instruction to transform the text.
        Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.

        Instruction: \(rule.prompt)

        Text:
        \(text)
        """

        let options = LLMGenerationOptions(
            temperature: 0.3,
            maxTokens: 2048
        )

        log.info("Auto-refine: calling \(resolved.provider.name)/\(resolved.modelId)")
        AppLogger.shared.log(.system, "Auto-refining", detail: "\(resolved.provider.name)/\(resolved.modelId)")

        // 5-second timeout
        do {
            let refined = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await resolved.provider.generate(
                        prompt: prompt,
                        model: resolved.modelId,
                        options: options
                    )
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw CancellationError()
                }

                guard let result = try await group.next() else {
                    throw LLMError.generationFailed("No result")
                }
                group.cancelAll()
                return result
            }

            let trimmed = refined.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                log.warning("Auto-refine: LLM returned empty, using raw text")
                return nil
            }

            let refineMs = Int(Date().timeIntervalSince(pipelineStart) * 1000)
            log.info("Auto-refine complete: \(trimmed.count) chars in \(refineMs)ms")
            AppLogger.shared.log(.system, "Auto-refine complete", detail: "\(trimmed.count) chars • \(refineMs)ms")
            return trimmed

        } catch is CancellationError {
            log.warning("Auto-refine: timed out after 5s, using raw text")
            AppLogger.shared.log(.system, "Auto-refine timeout", detail: "Falling back to raw text")
            return nil
        } catch {
            log.warning("Auto-refine failed: \(error.localizedDescription), using raw text")
            AppLogger.shared.log(.system, "Auto-refine failed", detail: error.localizedDescription)
            return nil
        }
    }

    // MARK: - Debug File Logging

    static let debugLogPath = "/tmp/talkie-agent-debug.log"

    static func debugLog(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLogPath) {
                if let fh = FileHandle(forWritingAtPath: debugLogPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: debugLogPath, contents: data)
            }
        }
    }
}
