//
//  AudioCaptureService.swift
//  TalkieAgent
//
//  Simplified audio capture following v1.9.0 philosophy:
//  "Live and die with AVAudioEngine" - no complex wrappers, no format
//  conversion, just capture what AVAudioEngine gives us.
//
//  Guiding principles:
//  1. Trust AVAudioEngine - use nil format (auto-negotiate)
//  2. Keep everything simple and synchronous where possible
//  3. Accept small startup delay - don't over-optimize
//  4. Never lose audio - reliability over features
//

import AVFoundation
import CoreAudio
import TalkieKit
import QuartzCore
import Accelerate

private let log = Log(.audio)

/// State of the audio capture service
enum AudioCaptureState: String {
    case cold           // Not initialized
    case warming        // Pre-warming (minimal - no engine)
    case warm           // Ready for recording
    case recording      // Actively capturing
    case finalizing     // Closing file, validating
    case error          // Needs recovery
}

/// Audio capture with simplified architecture.
/// Owns AVAudioEngine directly, uses nil format tap for auto-negotiation.
final class AudioCaptureService: AgentAudioCapture {

    // MARK: - Debug

    #if DEBUG
    /// Simulate HAL failure for testing recovery logic
    /// Toggle via Debug Settings in TalkieAgent
    static var simulateHALFailure = false

    /// Simulate no audio buffers (device appears to work but produces nothing)
    /// This tests the firstBufferTimeout and retry logic
    static var simulateNoBuffers = false

    // MARK: - Audio Diagnostics (DEBUG only)
    // These help diagnose HAL contention and retry loop issues

    /// Track how many times doStartCapture is called (resets on successful capture)
    private static var captureAttemptCount = 0
    /// Track total HAL initialization time across attempts
    private static var totalHALInitMs: Int = 0
    /// Track when we last started a capture attempt
    private static var lastCaptureAttemptTime: Date?
    /// Track rapid-fire attempts (< 1 second apart)
    private static var rapidAttemptCount = 0

    private func logCaptureAttemptDiagnostics(isRetry: Bool) {
        Self.captureAttemptCount += 1

        let now = Date()
        if let lastTime = Self.lastCaptureAttemptTime {
            let interval = now.timeIntervalSince(lastTime)
            if interval < 1.0 {
                Self.rapidAttemptCount += 1
                log.warning("⚠️ RAPID CAPTURE ATTEMPT #\(Self.rapidAttemptCount)",
                           detail: "interval=\(String(format: "%.2f", interval))s, total_attempts=\(Self.captureAttemptCount)")
            } else if interval < 5.0 {
                log.info("📊 Capture attempt #\(Self.captureAttemptCount)",
                        detail: "interval=\(String(format: "%.1f", interval))s, isRetry=\(isRetry)")
            }
        }
        Self.lastCaptureAttemptTime = now
    }

    private func logHALInitTiming(_ durationMs: Int) {
        Self.totalHALInitMs += durationMs
        if durationMs > 100 {
            log.warning("🐢 SLOW HAL INIT: \(durationMs)ms",
                       detail: "total_hal_time=\(Self.totalHALInitMs)ms across \(Self.captureAttemptCount) attempts")
        }
    }

    static func resetCaptureAttemptDiagnostics() {
        captureAttemptCount = 0
        totalHALInitMs = 0
        rapidAttemptCount = 0
        lastCaptureAttemptTime = nil
        log.debug("📊 Capture diagnostics reset")
    }

    static func printCaptureDiagnosticsSummary() {
        guard captureAttemptCount > 0 else { return }
        let avgHAL = totalHALInitMs / max(1, captureAttemptCount)
        log.info("📊 CAPTURE DIAGNOSTICS SUMMARY",
                detail: "attempts=\(captureAttemptCount), rapid=\(rapidAttemptCount), avg_hal=\(avgHAL)ms, total_hal=\(totalHALInitMs)ms")
    }
    #endif

    // MARK: - State

    private(set) var state: AudioCaptureState = .cold

    /// Whether an audio input device is available on the system
    /// Returns false on Mac Mini without microphone, for example
    var hasAudioInput: Bool {
        getDefaultInputDeviceID() != 0
    }

    private static var voiceForegroundingFlagEnabled: Bool {
        if let override = ProcessInfo.processInfo.environment["TALKIE_VOICE_FOREGROUNDING"]?.lowercased() {
            return ["1", "true", "yes", "on"].contains(override)
        }

        return TalkieSharedSettings.object(forKey: AgentSettingsKey.featureVoiceForegroundingEnabled) as? Bool ?? false
    }

    // MARK: - AVAudioEngine (owned directly)

    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var isRecordingActive = false
    private var currentDeviceUID: String?

    /// Engines that have been stopped but may still have an active IO thread.
    /// CoreAudio's IOWorkLoop runs on its own thread and can outlive engine.stop().
    /// We hold strong references here to prevent deallocation until the next recording
    /// starts, by which point the IO thread is guaranteed to have exited.
    private var retiredEngines: [AVAudioEngine] = []

    // MARK: - Components (kept)

    private let fileWriter = AudioFileWriter()
    private let archiver = AudioArchiver()
    private let voiceForegroundProcessor = VoiceForegroundProcessor()
    private var voiceForegroundingEnabledForSession = false

    /// Dedicated queue for audio engine setup to avoid blocking MainActor during HAL initialization
    /// This queue is recreated on reboot() to recover from stuck HAL operations
    private var audioSetupQueue = DispatchQueue(label: "to.talkie.app.audio.setup", qos: .userInitiated)

    // MARK: - Recording State

    private var currentRecordingURL: URL?
    private var onChunk: (([String]) -> Void)?
    var onSegmentCompleted: ((AudioWriterSegment) -> Void)? {
        get { onSegmentCompletedCallback }
        set { onSegmentCompletedCallback = newValue }
    }
    private var onCaptureErrorCallback: ((String) -> Void)?
    private var onSegmentCompletedCallback: ((AudioWriterSegment) -> Void)?
    private var captureToken = UUID()
    private var retryCount = 0
    private var bufferCount = 0
    private var fileCreated = false
    private var fallbackCaptureSession: FallbackCaptureSession?

    /// Performance trace for the current capture session
    /// Set by AgentController to enable "time to first audio" tracking
    weak var currentTrace: LiveTranscriptionTrace?

    /// When true, triggers a reboot after the current recording completes.
    /// Used for fallback-device recovery and pathological slow-start recovery.
    private var rebootAfterRecording = false
    private var rebootAfterRecordingReason: String?

    // MARK: - Silence Detection (inlined)

    private let silenceThreshold: Float = 0.05  // After 12x amplification, catches raw RMS < 0.004
    private let silenceWarningMs: Int = 400
    private let silenceConfirmedMs: Int = 2000
    private var silentBufferCount = 0
    private var buffersPerSecond: Double = 11.7  // Updated based on actual format
    private var silenceAlerted = false

    // MARK: - Timing

    private let baseFirstBufferTimeout: TimeInterval = 1.0  // Normal timeout for healthy HAL
    private let degradedFirstBufferTimeout: TimeInterval = 3.0  // Extended timeout when HAL is slow
    private var firstBufferReceived = false
    private var recordingStartTime: CFTimeInterval = 0
    private var lastSuccessfulRecordingTime: CFTimeInterval = 0
    private var halSetupEnteredQueue = false
    private let deviceReconfigurationSettleDelay: TimeInterval = 0.65

    /// Dynamic timeout based on HAL health
    private var firstBufferTimeout: TimeInterval {
        isHALDegraded ? degradedFirstBufferTimeout : baseFirstBufferTimeout
    }

    // MARK: - Failure Tracking

    /// Consecutive recording sessions that failed to produce audio
    /// Reset to 0 on successful recording, incremented on failure
    private var consecutiveSessionFailures = 0
    private let maxSessionFailuresBeforeReboot = 2  // Reboot after 2 failed sessions

    // MARK: - HAL Health Tracking

    /// Recent audio engine startup times in milliseconds
    /// Used to detect HAL degradation (slow startups indicate system audio issues)
    private var recentStartupTimes: [Int] = []
    private let maxStartupTimeSamples = 5
    private let halDegradedThresholdMs = 500  // Startup > 500ms indicates degradation

    /// Whether HAL appears degraded based on recent startup times
    var isHALDegraded: Bool {
        guard !recentStartupTimes.isEmpty else { return false }
        let average = recentStartupTimes.reduce(0, +) / recentStartupTimes.count
        return average > halDegradedThresholdMs
    }

    /// Last recorded startup time for external monitoring
    private(set) var lastStartupTimeMs: Int = 0
    private let slowStartupRecoveryThresholdMs = 1200
    private let rebootCooldownAfterSlowStart: CFTimeInterval = 90
    private var lastPostRecordingRebootTime: CFTimeInterval = 0
    private var rebootTask: Task<AudioRebootResult, Never>?

    /// Track a new startup time and update HAL health status
    private func recordStartupTime(_ ms: Int) {
        lastStartupTimeMs = ms
        recentStartupTimes.append(ms)
        if recentStartupTimes.count > maxStartupTimeSamples {
            recentStartupTimes.removeFirst()
        }

        // Log HAL health transition
        let wasHealthy = recentStartupTimes.count > 1 &&
            (recentStartupTimes.dropLast().reduce(0, +) / (recentStartupTimes.count - 1)) <= halDegradedThresholdMs
        let isNowDegraded = isHALDegraded

        if wasHealthy && isNowDegraded {
            log.warning("HAL entered degraded mode", detail: "avg startup: \(recentStartupTimes.reduce(0, +) / recentStartupTimes.count)ms, timeout extended to \(Int(degradedFirstBufferTimeout * 1000))ms")
        } else if !wasHealthy && !isNowDegraded && recentStartupTimes.count > 1 {
            log.info("HAL recovered to healthy state", detail: "avg startup: \(recentStartupTimes.reduce(0, +) / recentStartupTimes.count)ms")
        }
    }

    private func schedulePostRecordingReboot(reason: String) {
        let now = CACurrentMediaTime()
        let secondsSinceLastRecovery = now - lastPostRecordingRebootTime

        guard secondsSinceLastRecovery >= rebootCooldownAfterSlowStart else {
            log.debug(
                "Skipping post-recording reboot",
                detail: "cooldown \(Int(rebootCooldownAfterSlowStart - secondsSinceLastRecovery))s remaining"
            )
            return
        }

        guard !rebootAfterRecording else { return }

        rebootAfterRecording = true
        rebootAfterRecordingReason = reason
        log.warning("Queued audio reboot after recording", detail: reason)
    }

    /// Reset HAL health tracking (call after successful app restart recovery)
    func resetHALHealth() {
        recentStartupTimes.removeAll()
        lastStartupTimeMs = 0
        log.info("HAL health tracking reset")
    }

    // MARK: - Callbacks

    /// Callback for capture failure - called on main thread
    var onCaptureError: ((String) -> Void)? {
        get { onCaptureErrorCallback }
        set { onCaptureErrorCallback = newValue }
    }

    // MARK: - Initialization

    var currentSegmentIndex: Int {
        fileWriter.currentSegmentIndex
    }

    init() {
        fileWriter.onSegmentCompleted = { [weak self] segment in
            self?.onSegmentCompletedCallback?(segment)
        }
    }

    deinit {
        tearDown()
    }

    // MARK: - Public API (AgentAudioCapture Protocol)

    /// Start capturing audio
    /// - Parameter onChunk: Callback with file path when recording completes
    func startCapture(onChunk: @escaping ([String]) -> Void) {
        self.onChunk = onChunk
        fileWriter.segmentDuration = MainActor.assumeIsolated { LiveSettings.shared.segmentDuration }

        // Can start from warm, cold, or error state
        if state == .error {
            log.info("Recovering from error state")
            state = .cold
        }

        guard state == .warm || state == .cold else {
            log.warning("Cannot start capture in state: \(state.rawValue)")
            return
        }

        fallbackCaptureSession = nil

        if state == .cold {
            // Cold start: need async warmUp, then start capture
            Task { @MainActor [weak self] in
                guard let self else { return }
                let warmed = await self.warmUp()
                guard warmed else {
                    self.onCaptureErrorCallback?("Failed to initialize audio capture")
                    return
                }
                self.startCaptureWithStability()
            }
        } else {
            // Warm: start immediately — no Task hop needed
            startCaptureWithStability()
        }
    }

    // MARK: - Black Channel (file playback simulation)

    #if DEBUG
    /// Simulate mic capture by feeding audio from file(s) through the buffer pipeline.
    /// Runs the full path: handleBuffer → segmentation → compression → transcription.
    /// No real mic is used. Runs faster than real-time.
    func simulateCapture(filePaths: [String], segmentDuration: TimeInterval? = nil, onChunk: @escaping ([String]) -> Void) {
        self.onChunk = onChunk

        // Override segment duration if requested
        if let segmentDuration {
            fileWriter.segmentDuration = segmentDuration
        }

        // Set up file writer state (same as real capture)
        let tempDir = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let fileURL = tempDir.appendingPathComponent(filename).appendingPathExtension("wav")
        currentRecordingURL = fileURL
        fileCreated = false
        bufferCount = 0
        firstBufferReceived = false
        silentBufferCount = 0
        silenceAlerted = false
        recordingStartTime = CACurrentMediaTime()
        isRecordingActive = true
        state = .recording

        log.info("[BlackChannel] Starting simulation with \(filePaths.count) file(s)")

        Task.detached { [weak self] in
            guard let self else { return }

            let chunkSize: AVAudioFrameCount = 4096

            for (fileIdx, path) in filePaths.enumerated() {
                do {
                    let sourceFile = try AVAudioFile(forReading: URL(fileURLWithPath: path))
                    let format = sourceFile.processingFormat
                    let totalFrames = sourceFile.length

                    guard let readBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
                        log.error("[BlackChannel] Failed to create read buffer for file \(fileIdx)")
                        continue
                    }

                    log.info("[BlackChannel] Playing file \(fileIdx + 1)/\(filePaths.count)", detail: "\(format.sampleRate)Hz \(format.channelCount)ch \(totalFrames) frames")

                    while sourceFile.framePosition < totalFrames {
                        try sourceFile.read(into: readBuffer)
                        if readBuffer.frameLength == 0 { break }
                        self.handleBuffer(readBuffer)
                    }
                } catch {
                    log.error("[BlackChannel] Failed to read file \(fileIdx): \(path)", error: error)
                }
            }

            log.info("[BlackChannel] Simulation complete, finalizing")

            // Finalize on main thread (same as real stopCapture)
            await MainActor.run {
                self.isRecordingActive = false
                self.state = .finalizing

                if let result = self.fileWriter.finalize() {
                    self.state = .warm

                    if result.fileSize > 0 {
                        let segmentPaths = result.segments.map(\.url.path)
                        let paths = segmentPaths.isEmpty ? [result.url.path] : segmentPaths
                        log.info("[BlackChannel] Done: \(result.segments.count) segments, \(result.fileSize) bytes, \(String(format: "%.1f", result.duration))s")
                        self.onChunk?(paths)
                    }
                }

                self.currentRecordingURL = nil
                self.onChunk = nil
                self.bufferCount = 0
                self.fileCreated = false
                self.firstBufferReceived = false
            }
        }
    }

    #endif

    /// Stop capturing and finalize the recording
    func stopCapture() {
        // Cancel any pending setup by invalidating the token
        // This handles the case where stop is called during background audio setup
        let wasStarting = (state == .warm || state == .warming)
        captureToken = UUID()

        guard state == .recording else {
            if wasStarting {
                log.info("Cancelled pending audio setup")
                finishFallbackCaptureSession()
                // Signal immediately so AgentController doesn't wait for timeout
                onCaptureErrorCallback?("Recording cancelled (setup incomplete)")
            } else {
                log.warning("Cannot stop capture in state: \(state.rawValue)")
            }
            return
        }

        let stopStart = CACurrentMediaTime()
        var completedRecording = false

        func logTiming(_ step: String) {
            let ms = Int((CACurrentMediaTime() - stopStart) * 1000)
            log.debug("Stop: \(step)", detail: "+\(ms)ms")
        }

        state = .finalizing
        isRecordingActive = false

        // Stop the engine and retire it.
        // CoreAudio's IO thread may still be mid-callback after stop() returns,
        // so we hold the engine in retiredEngines to prevent premature deallocation.
        // The retired list is drained at the start of the next recording.
        retireEngine()
        logTiming("engine stopped")

        // Remove config observer
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }

        // Finalize the file
        if let result = fileWriter.finalize() {
            logTiming("file finalized")
            state = .warm

            // Validate file
            if result.fileSize > 1000 && result.bufferCount >= 4 {
                let totalMs = Int((CACurrentMediaTime() - stopStart) * 1000)
                lastSuccessfulRecordingTime = CACurrentMediaTime()

                let segmentPaths = result.segments.map(\.url.path)
                let segmentInfo = result.segments.count > 1
                    ? "\(result.segments.count) segments, "
                    : ""
                log.info("Recording complete",
                         detail: "\(segmentInfo)\(result.bufferCount) buffers, \(result.fileSize) bytes in \(totalMs)ms")

                completedRecording = true
                if segmentPaths.isEmpty {
                    onChunk?([result.url.path])
                } else {
                    onChunk?(segmentPaths)
                }

                // Archive: process() copies segments to AudioStorage first,
                // so archiving the temp files is no longer needed here.
                // AudioStorage files are archived separately after transcription.
            } else {
                log.warning("Recording too short or empty",
                           detail: "\(result.bufferCount) buffers, \(result.fileSize) bytes")
                try? FileManager.default.removeItem(at: result.url)
                for segment in result.segments {
                    try? FileManager.default.removeItem(at: segment.url)
                }

                // Signal error so AgentController can reset immediately instead of waiting for timeout
                onCaptureErrorCallback?("Recording too short")
            }
        } else {
            log.error("Failed to finalize recording")
            state = .warm
        }

        // Reset UI
        Task { @MainActor in
            AudioLevelMonitor.shared.level = 0
            AudioLevelMonitor.shared.resetSilenceTracking()
        }

        // Clean up state
        currentRecordingURL = nil
        onChunk = nil
        captureToken = UUID()
        bufferCount = 0
        fileCreated = false
        silentBufferCount = 0
        silenceAlerted = false
        firstBufferReceived = false
        voiceForegroundingEnabledForSession = false
        voiceForegroundProcessor.reset()
        logTiming("cleanup done")

        finishFallbackCaptureSession(schedulePostRecordingReboot: completedRecording)

        // If HAL was degraded or fallback recovery was needed, reboot now that
        // the recording is finished. Device defaults are restored separately.
        if rebootAfterRecording {
            rebootAfterRecording = false
            let rebootReason = rebootAfterRecordingReason ?? "Audio recovery"
            rebootAfterRecordingReason = nil
            lastPostRecordingRebootTime = CACurrentMediaTime()
            log.info("🔄 Rebooting audio system after recording", detail: rebootReason)
            Task {
                await self.reboot()
            }
        }
    }

    func requestCheckpoint() {
        guard state == .recording, firstBufferReceived else { return }
        fileWriter.requestCheckpoint()
        log.info("Checkpoint requested for segment \(fileWriter.currentSegmentIndex)")
    }

    // MARK: - Pre-warming

    /// Prepare for recording
    /// With simplified architecture, this just starts device observation.
    @discardableResult
    func warmUp() async -> Bool {
        guard state == .cold || state == .error else {
            return state == .warm
        }

        state = .warming
        log.info("Preparing audio capture service")

        // Check for available audio input devices
        let defaultDevice = getDefaultInputDeviceID()
        if defaultDevice == 0 {
            log.warning("⚠️ No audio input device detected - recording will not work")
            // Still mark as warm so the error is shown when user tries to record
            // This allows the UI to show a helpful message rather than silently failing
        }

        // Mark as ready - engine created fresh for each recording
        state = .warm
        log.info("Audio capture service ready")
        return true
    }

    /// Shut down the service
    func tearDown() {
        // Invalidate any pending background setup
        captureToken = UUID()

        if state == .recording {
            stopCapture()
        }
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }

        isRecordingActive = false
        retireEngine()
        finishFallbackCaptureSession()
        // On full teardown, clear retired engines too (service is shutting down)
        retiredEngines.removeAll()
        rebootAfterRecording = false
        rebootAfterRecordingReason = nil
        voiceForegroundingEnabledForSession = false
        voiceForegroundProcessor.reset()
        state = .cold
    }

    /// Reboot the audio system - full teardown and re-warmup
    /// Call this when capture fails to recover without app restart
    /// - Returns: Result indicating success and HAL health status
    @discardableResult
    func reboot() async -> AudioRebootResult {
        if let rebootTask {
            log.debug("Audio reboot already in progress")
            return await rebootTask.value
        }

        let task = Task { [weak self] in
            guard let self else { return AudioRebootResult.failed }
            return await self.performReboot()
        }
        rebootTask = task
        let result = await task.value
        rebootTask = nil
        return result
    }

    private func performReboot() async -> AudioRebootResult {
        let wasAlreadyDegraded = isHALDegraded
        log.info("════════════════════════════════════════════════════════════")
        log.info("🔄 Rebooting audio system", detail: "HAL was \(wasAlreadyDegraded ? "degraded" : "healthy")")
        log.info("════════════════════════════════════════════════════════════")

        // Full teardown
        tearDown()

        // Recreate the audioSetupQueue to recover from stuck HAL operations
        // If a HAL initialization hung on the old queue, the serial queue is stuck forever.
        // Creating a new queue abandons the old one and any stuck operations.
        audioSetupQueue = DispatchQueue(label: "to.talkie.app.audio.setup", qos: .userInitiated)
        log.debug("Recreated audio setup queue")

        // Adaptive delay based on HAL health - give degraded HAL more time to recover
        let delayMs = wasAlreadyDegraded ? 1000 : 250
        log.debug("Waiting \(delayMs)ms for CoreAudio to release resources")
        try? await Task.sleep(for: .milliseconds(delayMs))

        // Re-warm
        let success = await warmUp()

        if success {
            if isHALDegraded {
                log.warning("Audio system rebooted but HAL still degraded", detail: "avg startup: \(recentStartupTimes.reduce(0, +) / max(1, recentStartupTimes.count))ms")
                return .successDegraded
            } else {
                log.info("Audio system rebooted successfully", detail: "HAL healthy")
                return .success
            }
        } else {
            log.error("Audio system reboot failed")
            return .failed
        }
    }

    // MARK: - Private Implementation

    private func startCaptureWithStability(
        isRetry: Bool = false,
        overrideDeviceSelection: DeviceSelection? = nil
    ) {
        let token = UUID()
        captureToken = token
        if !isRetry {
            retryCount = 0
        }

        // Call directly — callers are already on MainActor
        doStartCapture(isRetry: isRetry, token: token, overrideDeviceSelection: overrideDeviceSelection)
    }

    private func doStartCapture(
        isRetry: Bool,
        token: UUID,
        overrideDeviceSelection: DeviceSelection? = nil
    ) {
        // Safe to release engines from previous recordings — their IO threads
        // have had ample time to exit (at minimum the full device stability wait).
        drainRetiredEngines()

        let captureStart = CACurrentMediaTime()
        recordingStartTime = captureStart

        func logTiming(_ step: String) {
            let ms = Int((CACurrentMediaTime() - captureStart) * 1000)
            log.debug("Start: \(step)", detail: "+\(ms)ms")
        }

        if isRetry {
            if let fallbackCaptureSession {
                log.info("Retrying audio capture with fallback microphone",
                         detail: fallbackCaptureSession.selection.name)
            } else {
                log.info("Retrying audio capture after no-buffer start")
            }
        }

        #if DEBUG
        logCaptureAttemptDiagnostics(isRetry: isRetry)
        #endif

        // Reset tracking state
        bufferCount = 0
        silentBufferCount = 0
        silenceAlerted = false
        firstBufferReceived = false
        voiceForegroundProcessor.reset()
        voiceForegroundingEnabledForSession = Self.voiceForegroundingFlagEnabled

        if voiceForegroundingEnabledForSession {
            log.info("Experimental voice foregrounding enabled")
        }

        Task { @MainActor in
            AudioLevelMonitor.shared.resetSilenceTracking()
            AudioLevelMonitor.shared.refreshMicName()
        }

        // Resolve device selection (lightweight - just reads settings)
        let deviceSelection: DeviceSelection
        if let overrideDeviceSelection {
            deviceSelection = overrideDeviceSelection
            log.warning("Using fallback microphone for this recording", detail: "\(deviceSelection.name) (uid: \(deviceSelection.uid))")
        } else {
            switch resolveDevice() {
            case .selection(let selection):
                deviceSelection = selection
            case .missingFixed(let uid, let name):
                let deviceLabel = name ?? uid ?? "Unknown device"
                if let fallback = selectFallbackInputDevice(excludingUID: uid, excludingDeviceID: nil) {
                    beginFallbackCaptureSession(
                        selection: fallback,
                        failedDeviceName: deviceLabel,
                        reason: "configured microphone unavailable",
                        rebootAfterRecording: false
                    )
                    deviceSelection = fallback
                } else {
                    log.error("Selected microphone unavailable", detail: deviceLabel)
                    handleError("Selected microphone unavailable. Open Audio Settings to choose a device.")
                    return
                }
            }
        }

        currentDeviceUID = deviceSelection.uid
        logTiming("device resolved: \(deviceSelection.name)")

        // Validate device is responding before expensive HAL operations
        guard isDeviceResponding(deviceSelection.deviceID) else {
            if deviceSelection.deviceID == 0 {
                log.error("No audio input device available")
                handleError("No audio input device found. Connect a microphone or headset to record.")
            } else {
                log.error("Device not responding, aborting recording start")
                handleError("Audio device not responding")
            }
            return
        }
        logTiming("device health checked")

        // CRITICAL FIX: For fixed devices, set system default BEFORE creating AVAudioEngine.
        // AudioUnitSetProperty device switching doesn't work reliably when the audio graph
        // is confused (e.g., AirPods connected as default but we want USB mic).
        // Setting system default first ensures AVAudioEngine initializes with correct device.
        var changedSystemDefaultInput = false
        if deviceSelection.isFixedDevice {
            let currentDefault = getDefaultInputDeviceID()
            if currentDefault != deviceSelection.deviceID {
                let currentDefaultName = getDeviceName(currentDefault) ?? "unknown"
                log.info("🔄 Switching system default input",
                         detail: "from '\(currentDefaultName)' to '\(deviceSelection.name)'")

                if setDefaultInputDevice(deviceSelection.deviceID) {
                    changedSystemDefaultInput = true
                    log.info("✅ System default input changed to: \(deviceSelection.name)")
                    logTiming("system default switched")
                } else {
                    log.warning("⚠️ Failed to set system default input - will try AudioUnit fallback")
                }
            } else {
                log.debug("Fixed device already is system default", detail: deviceSelection.name)
            }
        }

        // Set up HAL timeout watchdog - fires if HAL init takes too long (queue might be stuck)
        // This runs on MainActor and will catch hung HAL operations
        let halTimeoutSec: Double = 12.0
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(halTimeoutSec))
            guard let self else { return }
            // If we're still in warm/warming state with the same token, HAL init is stuck
            guard self.captureToken == token else { return }
            guard self.state == .warm || self.state == .warming else { return }

            let idleSec = self.lastSuccessfulRecordingTime > 0
                ? Int(CACurrentMediaTime() - self.lastSuccessfulRecordingTime)
                : -1
            let retiredCount = self.retiredEngines.count
            let queueEntered = self.halSetupEnteredQueue

            log.error("HAL initialization timeout after \(Int(halTimeoutSec))s",
                      detail: "queueEntered=\(queueEntered) retiredEngines=\(retiredCount) idleSec=\(idleSec) device=\(self.currentDeviceUID ?? "default")")
            AppLogger.shared.log(.error, "HAL timeout",
                                 detail: "Audio setup stuck • queueEntered=\(queueEntered) retired=\(retiredCount) idle=\(idleSec)s")

            if self.recoverWithFallbackMicrophone(
                failedSelection: deviceSelection,
                token: token,
                reason: "Audio initialization timeout"
            ) {
                return
            }

            // Trigger recovery
            self.handleError("Audio initialization timeout")

            // Schedule reboot to recover the stuck queue
            Task {
                await self.reboot()
            }
        }

        halSetupEnteredQueue = false

        // Do expensive AVAudioEngine setup on dedicated queue to avoid blocking MainActor
        // Accessing engine.inputNode triggers synchronous CoreAudio HAL initialization
        // that can take 1-3 seconds via IPC to coreaudiod
        audioSetupQueue.async { [weak self] in
            guard let self else { return }
            self.halSetupEnteredQueue = true
            guard self.captureToken == token else {
                log.debug("Audio setup cancelled - token mismatch")
                return
            }
            guard self.state == .warm || self.state == .warming else {
                log.debug("Audio setup cancelled - state changed to \(self.state.rawValue)")
                return
            }

            let setupStart = CACurrentMediaTime()
            func logSetupTiming(_ step: String) {
                let ms = Int((CACurrentMediaTime() - setupStart) * 1000)
                log.debug("Setup: \(step)", detail: "+\(ms)ms")
            }

            if changedSystemDefaultInput {
                log.debug("Waiting for system input change to settle", detail: "\(Int(self.deviceReconfigurationSettleDelay * 1000))ms")
                Thread.sleep(forTimeInterval: self.deviceReconfigurationSettleDelay)
                guard self.captureToken == token else {
                    log.debug("Audio setup cancelled after system input settle - token mismatch")
                    return
                }
            }

            // Create fresh audio engine
            let newEngine = AVAudioEngine()
            logSetupTiming("engine created")

            // Pre-warm inputNode - this is the expensive HAL initialization
            // Doing it here on the setup queue keeps MainActor responsive
            #if DEBUG
            let halStart = CACurrentMediaTime()
            #endif

            let inputNode = newEngine.inputNode

            #if DEBUG
            let halDurationMs = Int((CACurrentMediaTime() - halStart) * 1000)
            self.logHALInitTiming(halDurationMs)
            #endif

            logSetupTiming("inputNode initialized (HAL warmup)")

            // Bind the selected device on the audio unit itself. Changing the
            // system default is not enough on setups where AVAudioEngine opens
            // a synthetic default aggregate device.
            let bindingResult = self.bindSelectedInputDeviceIfNeeded(
                inputNode: inputNode,
                selection: deviceSelection
            )

            switch bindingResult {
            case .ready:
                break
            case .changed(let requiresSettle):
                if requiresSettle {
                    log.debug("Waiting for input device binding to settle", detail: "\(Int(self.deviceReconfigurationSettleDelay * 1000))ms")
                    Thread.sleep(forTimeInterval: self.deviceReconfigurationSettleDelay)
                    guard self.captureToken == token else {
                        log.debug("Audio setup cancelled after device binding settle - token mismatch")
                        newEngine.stop()
                        return
                    }
                }
            case .failed:
                DispatchQueue.main.async { [weak self] in
                    newEngine.stop()
                    guard let self, self.captureToken == token else { return }
                    if self.recoverWithFallbackMicrophone(
                        failedSelection: deviceSelection,
                        token: token,
                        reason: "Failed to select microphone"
                    ) {
                        return
                    }
                    self.handleError("Failed to select microphone: \(deviceSelection.name)")
                }
                return
            }

            logSetupTiming("device bound")

            // CRITICAL: Prepare engine after setting device
            // This forces the audio graph to reinitialize with the correct device format.
            // Without this, switching from AirPods (24kHz/1ch) to USB mic (48kHz/2ch)
            // causes -10868 errors because the graph is stuck in the old format.
            // Note: reset() does NOT work - only prepare() properly reinitializes the graph.
            newEngine.prepare()
            logSetupTiming("engine prepared")

            // Get hardware format
            let hwFormat = inputNode.inputFormat(forBus: 0)
            logSetupTiming("got format: \(Int(hwFormat.sampleRate))Hz, \(hwFormat.channelCount)ch")

            // Continue on main queue for state updates and tap installation
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.captureToken == token else {
                    log.debug("Audio setup cancelled during handoff - token mismatch")
                    newEngine.stop()
                    return
                }

                self.finishStartCapture(
                    engine: newEngine,
                    inputNode: inputNode,
                    hwFormat: hwFormat,
                    deviceSelection: deviceSelection,
                    deviceName: deviceSelection.name,
                    captureStart: captureStart,
                    token: token
                )
            }
        }
    }

    private func finishStartCapture(
        engine newEngine: AVAudioEngine,
        inputNode: AVAudioInputNode,
        hwFormat: AVAudioFormat,
        deviceSelection: DeviceSelection,
        deviceName: String,
        captureStart: CFTimeInterval,
        token: UUID
    ) {
        func logTiming(_ step: String) {
            let ms = Int((CACurrentMediaTime() - captureStart) * 1000)
            log.debug("Start: \(step)", detail: "+\(ms)ms")
        }

        // Final validation: check token and state before committing
        // This catches: stop called during setup, errors during background phase, etc.
        guard captureToken == token else {
            log.debug("finishStartCapture cancelled - token mismatch")
            newEngine.stop()
            return
        }

        guard state == .warm || state == .warming else {
            log.warning("finishStartCapture cancelled - unexpected state: \(state.rawValue)")
            newEngine.stop()
            return
        }

        // Store engine reference
        self.engine = newEngine
        logTiming("engine stored")

        // Set up configuration change observer
        setupConfigObserver(for: newEngine)

        // Validate minimum sample rate for Whisper
        guard hwFormat.sampleRate >= 16000 else {
            log.error("Sample rate too low", detail: "\(Int(hwFormat.sampleRate))Hz - need at least 16kHz")
            cleanupEngine()
            handleError("Audio device sample rate too low for transcription")
            return
        }

        // Create temp file path for PCM recording (file created lazily on first buffer)
        let tempDir = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let fileURL = tempDir.appendingPathComponent(filename).appendingPathExtension("wav")
        currentRecordingURL = fileURL
        fileCreated = false

        // Calculate buffers per second for silence detection
        let bufferSize = Double(AudioCaptureConfiguration.bufferSize)
        buffersPerSecond = hwFormat.sampleRate / bufferSize

        // Install tap with nil format - let AVAudioEngine auto-negotiate
        inputNode.installTap(onBus: 0, bufferSize: AudioCaptureConfiguration.bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self, self.isRecordingActive else { return }
            self.handleBuffer(buffer)
        }
        logTiming("tap installed")

        // Start engine off the main actor. CoreAudio can block inside kAUStartIO
        // for several seconds when HAL is degraded, and the watchdog/recovery
        // timers need the main actor free to run.
        state = .warming
        audioSetupQueue.async { [weak self] in
            do {
                try newEngine.start()
                let totalMs = Int((CACurrentMediaTime() - captureStart) * 1000)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.captureToken == token, self.engine === newEngine else {
                        newEngine.stop()
                        return
                    }
                    guard self.state == .warm || self.state == .warming else {
                        newEngine.stop()
                        return
                    }

                    logTiming("engine started")
                    self.isRecordingActive = true
                    self.state = .recording
                    self.scheduleFirstBufferCheck(token: token)

                    // Track startup time for HAL health monitoring
                    self.recordStartupTime(totalMs)

                    if totalMs >= self.slowStartupRecoveryThresholdMs {
                        self.schedulePostRecordingReboot(
                            reason: "Slow startup \(totalMs)ms (HAL degraded: \(self.isHALDegraded ? "yes" : "no"))"
                        )
                    }

                    // Warn if engine start was suspiciously slow (HAL issues often cause >500ms startup)
                    if totalMs > self.halDegradedThresholdMs {
                        log.warning("⚠️ Slow audio startup: \(totalMs)ms (HAL may be degraded)", detail: "timeout extended to \(Int(self.firstBufferTimeout * 1000))ms")
                    }
                    log.info("Recording started", detail: "\(Int(hwFormat.sampleRate))Hz, \(hwFormat.channelCount)ch in \(totalMs)ms")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.captureToken == token else {
                        newEngine.stop()
                        return
                    }

                    log.error("Failed to start engine", error: error)
                    if self.engine === newEngine {
                        self.cleanupEngine()
                    } else {
                        newEngine.stop()
                    }
                    if self.recoverWithFallbackMicrophone(
                        failedSelection: deviceSelection,
                        token: token,
                        reason: "Failed to start recording: \(error.localizedDescription)"
                    ) {
                        return
                    }
                    self.handleError("Failed to start recording: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        #if DEBUG
        // Simulate no buffers for testing recovery
        if AudioCaptureService.simulateNoBuffers {
            // Silently drop buffers - triggers firstBufferTimeout
            return
        }
        #endif

        bufferCount += 1

        if !firstBufferReceived {
            firstBufferReceived = true
            consecutiveSessionFailures = 0  // Reset failure counter on successful audio
            let latencyMs = Int((CACurrentMediaTime() - recordingStartTime) * 1000)
            log.debug("First buffer received", detail: "+\(latencyMs)ms from capture start, format: \(buffer.format.sampleRate)Hz, \(buffer.format.channelCount)ch")

            // Mark time to first audio in performance trace
            currentTrace?.mark("first_audio", metadata: "\(latencyMs)ms")

            #if DEBUG
            // Reset diagnostics on successful capture start - next session starts fresh
            Self.resetCaptureAttemptDiagnostics()
            #endif
        }

        let bufferForWriting = voiceForegroundingEnabledForSession
            ? (voiceForegroundProcessor.process(buffer) ?? buffer)
            : buffer

        // Create file lazily on first buffer - ensures format matches exactly
        if !fileCreated, let fileURL = currentRecordingURL {
            if fileWriter.createFile(at: fileURL, format: bufferForWriting.format) {
                fileCreated = true
                log.debug("Created audio file", detail: "\(bufferForWriting.format.sampleRate)Hz, \(bufferForWriting.format.channelCount)ch")
            } else {
                log.error("Failed to create audio file on first buffer")
                return
            }
        }

        // Write to file
        fileWriter.write(bufferForWriting)

        // Calculate RMS level (inlined)
        let level = calculateRMSLevel(bufferForWriting)

        // Silence detection (inlined)
        if level < silenceThreshold {
            silentBufferCount += 1
            let silentMs = Int(Double(silentBufferCount) / buffersPerSecond * 1000)

            if silentMs >= silenceConfirmedMs && !silenceAlerted {
                silenceAlerted = true
                log.warning("Confirmed silence", detail: "\(silentMs)ms")
                Task { @MainActor in
                    AudioLevelMonitor.shared.isSilent = true
                    // Visual feedback in overlay is enough - no beep needed
                }
            }
        } else {
            // Got audio - reset silence counter
            if silentBufferCount > 0 {
                silentBufferCount = 0
                silenceAlerted = false
                Task { @MainActor in
                    AudioLevelMonitor.shared.isSilent = false
                }
            }
        }

        // Update UI level
        Task { @MainActor in
            AudioLevelMonitor.shared.updateLevel(level, isRecording: true)
        }
    }

    /// Calculate RMS level from buffer using vDSP for realtime performance
    private func calculateRMSLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelDataValue = channelData.pointee
        let frameLength = vDSP_Length(buffer.frameLength)

        guard frameLength > 0 else { return 0 }

        var rms: Float = 0
        vDSP_rmsqv(channelDataValue, 1, &rms, frameLength)

        // Amplify for better visual response to quiet sounds
        return min(1.0, rms * 12.0)
    }

    private func scheduleFirstBufferCheck(token: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let timeoutMs = Int(self.firstBufferTimeout * 1000)
            try? await Task.sleep(for: .milliseconds(timeoutMs))
            guard self.state == .recording, self.captureToken == token else { return }
            guard !self.firstBufferReceived else { return }
            self.handleNoBufferStart()
        }
    }

    private func handleNoBufferStart() {
        // Calculate how long user has been waiting
        let waitTimeMs = Int((CACurrentMediaTime() - recordingStartTime) * 1000)
        let waitTimeSec = String(format: "%.1f", Double(waitTimeMs) / 1000.0)

        retryCount += 1

        // Progressive retry strategy:
        // Retry 1+: Try the same device again (transient HAL issue)
        // Max retries: Give up - but return to warm state so user can try again
        let maxRetries = 3

        if retryCount >= maxRetries {
            consecutiveSessionFailures += 1
            log.error("════════════════════════════════════════════════════════════")
            log.error("🔴 AUDIO SYSTEM FAILED - Session \(consecutiveSessionFailures) of \(maxSessionFailuresBeforeReboot)")
            log.error("   No audio after \(retryCount) attempts (\(waitTimeSec)s)")
            log.error("   Device: \(currentDeviceUID ?? "unknown")")
            log.error("════════════════════════════════════════════════════════════")

            #if DEBUG
            Self.printCaptureDiagnosticsSummary()
            #endif

            cleanupEngine()
            cleanupFailedRecording()
            finishFallbackCaptureSession()

            // Auto-reboot if we've failed multiple sessions in a row
            if consecutiveSessionFailures >= maxSessionFailuresBeforeReboot {
                log.error("🔄 AUTO-REBOOTING AUDIO SYSTEM after \(consecutiveSessionFailures) consecutive failures")
                Task { @MainActor [weak self] in
                    await self?.reboot()
                }
                return
            }

            // Return to warm state so user can immediately try again
            state = .warm
            onCaptureErrorCallback?("Microphone not responding - tap to try again")
            return
        }

        log.warning("No audio buffers (attempt \(retryCount)/\(maxRetries)) - retrying same device",
                    detail: "device=\(currentDeviceUID ?? "unknown")")

        cleanupEngine()
        cleanupFailedRecording()
        state = .warm
        startCaptureWithStability(
            isRetry: true,
            overrideDeviceSelection: fallbackCaptureSession?.selection
        )
    }

    private func cleanupFailedRecording() {
        if let result = fileWriter.finalizeLegacy() {
            try? FileManager.default.removeItem(at: result.url)
        }
        currentRecordingURL = nil
        fileCreated = false
        Task { @MainActor in
            AudioLevelMonitor.shared.level = 0
            AudioLevelMonitor.shared.resetSilenceTracking()
        }
    }

    private func cleanupEngine() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }

        isRecordingActive = false
        retireEngine()
    }

    /// Stop the current engine and move it to the retired list.
    /// The retired engine stays alive briefly to let CoreAudio's IO thread exit,
    /// then is drained automatically after a delay.
    private func retireEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        retiredEngines.append(engine)
        self.engine = nil
        scheduleDeferredDrain()
    }

    /// Release engines from previous recordings.
    /// Called at the start of a new recording or after the deferred drain timer fires.
    private func drainRetiredEngines() {
        if !retiredEngines.isEmpty {
            log.debug("Draining \(retiredEngines.count) retired engine(s)")
            retiredEngines.removeAll()
        }
    }

    /// Schedule a deferred drain so retired engines don't hold IO threads alive indefinitely.
    /// 5s is enough for CoreAudio's IOWorkLoop to fully exit after engine.stop().
    private func scheduleDeferredDrain() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.drainRetiredEngines()
        }
    }

    private func handleError(_ error: String) {
        log.error("Capture error", detail: error)
        finishFallbackCaptureSession()
        state = .error
        onCaptureErrorCallback?(error)
    }

    @discardableResult
    private func recoverWithFallbackMicrophone(
        failedSelection: DeviceSelection,
        token: UUID,
        reason: String
    ) -> Bool {
        guard captureToken == token else { return true }
        guard fallbackCaptureSession == nil else {
            log.error("Fallback microphone recovery already attempted", detail: reason)
            return false
        }

        guard let fallback = selectFallbackInputDevice(
            excludingUID: failedSelection.uid,
            excludingDeviceID: failedSelection.deviceID
        ) else {
            log.error("No fallback microphone available", detail: reason)
            return false
        }

        beginFallbackCaptureSession(
            selection: fallback,
            failedDeviceName: failedSelection.name,
            reason: reason,
            rebootAfterRecording: true
        )

        captureToken = UUID()
        cleanupEngine()
        cleanupFailedRecording()
        state = .warm
        retryCount = 0
        halSetupEnteredQueue = false
        audioSetupQueue = DispatchQueue(label: "to.talkie.app.audio.setup", qos: .userInitiated)

        startCaptureWithStability(isRetry: true, overrideDeviceSelection: fallback)
        return true
    }

    private func beginFallbackCaptureSession(
        selection: DeviceSelection,
        failedDeviceName: String,
        reason: String,
        rebootAfterRecording shouldRebootAfterRecording: Bool
    ) {
        let currentDefaultDeviceID = getDefaultInputDeviceID()
        let restoreDefaultDeviceID = currentDefaultDeviceID != 0 && currentDefaultDeviceID != selection.deviceID
            ? currentDefaultDeviceID
            : nil
        let restoreDefaultDeviceName = restoreDefaultDeviceID.flatMap { getDeviceName($0) }

        fallbackCaptureSession = FallbackCaptureSession(
            selection: selection,
            restoreDefaultDeviceID: restoreDefaultDeviceID,
            restoreDefaultDeviceName: restoreDefaultDeviceName,
            reason: reason,
            postRecordingRebootReason: shouldRebootAfterRecording
                ? "Fallback microphone used after \(failedDeviceName) failed: \(reason)"
                : nil
        )

        log.warning(
            "Using fallback microphone for this recording",
            detail: "\(failedDeviceName) -> \(selection.name) (\(reason))"
        )
    }

    private func finishFallbackCaptureSession(schedulePostRecordingReboot: Bool = false) {
        guard let session = fallbackCaptureSession else { return }
        fallbackCaptureSession = nil

        if schedulePostRecordingReboot, let reason = session.postRecordingRebootReason {
            self.schedulePostRecordingReboot(reason: reason)
        }

        guard let restoreDefaultDeviceID = session.restoreDefaultDeviceID else { return }
        guard getDefaultInputDeviceID() != restoreDefaultDeviceID else { return }

        let restoreName = session.restoreDefaultDeviceName
            ?? getDeviceName(restoreDefaultDeviceID)
            ?? "previous input"

        if setDefaultInputDevice(restoreDefaultDeviceID) {
            log.info(
                "Restored system default input",
                detail: "\(restoreName) after fallback microphone \(session.selection.name)"
            )
        } else {
            log.warning(
                "Failed to restore system default input after fallback",
                detail: "\(restoreName) after \(session.selection.name) (\(session.reason))"
            )
        }
    }

    private func archiveRecording(_ pcmURL: URL) {
        archiver.archiveToAAC(pcmPath: pcmURL, deleteOriginal: true) { result in
            switch result {
            case .success(let aacURL, _, let compressedSize):
                log.debug("Archived to AAC", detail: "\(aacURL.lastPathComponent) (\(compressedSize) bytes)")
            case .failed(let reason):
                // File may have been moved to AudioStorage before archiving started - not critical
                log.debug("Archive skipped", detail: reason)
            case .skipped(let reason):
                log.debug("Archive skipped", detail: reason)
            }
        }
    }

    private func setupConfigObserver(for engine: AVAudioEngine) {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            // Only log - don't fail. The tap usually keeps working.
            if self.state == .recording {
                if self.bufferCount == 0 {
                    log.debug("Audio engine config changed at start")
                } else {
                    log.debug("Audio engine config changed mid-recording", detail: "\(self.bufferCount) buffers")
                }
            }
        }
    }

    // MARK: - Device Selection (inlined from DeviceSelector)

    private struct DeviceSelection {
        let deviceID: AudioDeviceID
        let uid: String
        let name: String
        let isFixedDevice: Bool
    }

    private struct FallbackCaptureSession {
        let selection: DeviceSelection
        let restoreDefaultDeviceID: AudioDeviceID?
        let restoreDefaultDeviceName: String?
        let reason: String
        let postRecordingRebootReason: String?
    }

    private enum DeviceResolution {
        case selection(DeviceSelection)
        case missingFixed(uid: String?, name: String?)
    }

    private enum InputDeviceBindingResult {
        case ready
        case changed(requiresSettle: Bool)
        case failed
    }

    private func bindSelectedInputDeviceIfNeeded(
        inputNode: AVAudioInputNode,
        selection: DeviceSelection
    ) -> InputDeviceBindingResult {
        guard let audioUnit = inputNode.audioUnit else {
            log.warning("Could not inspect audio input device", detail: "No audio unit")
            return selection.isFixedDevice ? .failed : .ready
        }

        guard let currentDeviceID = currentInputDeviceID(for: audioUnit) else {
            log.warning("Could not inspect audio input device", detail: "Current device unavailable")
            return selection.isFixedDevice ? .failed : .ready
        }

        let currentName = getDeviceName(currentDeviceID) ?? "unknown"
        if currentDeviceID == selection.deviceID {
            log.info("🎤 Engine using device: \(currentName) (ID: \(currentDeviceID))",
                     detail: "✅ matches selection")
            return .ready
        }

        guard selection.isFixedDevice else {
            log.info("🎤 Engine using device: \(currentName) (ID: \(currentDeviceID))",
                     detail: "system default")
            return .ready
        }

        let bindingDefaultAggregate = isDefaultInputAggregate(currentDeviceID, name: currentName)
            && defaultInputMatches(selection)

        if bindingDefaultAggregate {
            log.info(
                "🎤 Engine using device: \(currentName) (ID: \(currentDeviceID))",
                detail: "default aggregate routes to \(selection.name); binding concrete device"
            )
        } else {
            log.warning(
                "Engine input mismatch; binding selected microphone",
                detail: "current=\(currentName) (ID: \(currentDeviceID)), selected=\(selection.name) (ID: \(selection.deviceID))"
            )
        }

        var mutableDeviceID = selection.deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            log.error("Failed to bind selected microphone", detail: "status=\(status), device=\(selection.name)")
            return .failed
        }

        guard let verifiedDeviceID = currentInputDeviceID(for: audioUnit) else {
            log.warning("Selected microphone bound but could not verify", detail: selection.name)
            return .changed(requiresSettle: true)
        }

        let verifiedName = getDeviceName(verifiedDeviceID) ?? "unknown"
        let matches = verifiedDeviceID == selection.deviceID
        log.info(
            "🎤 Engine using device: \(verifiedName) (ID: \(verifiedDeviceID))",
            detail: matches ? "✅ bound selected microphone" : "⚠️ still mismatch with \(selection.name)"
        )
        return matches ? .changed(requiresSettle: !bindingDefaultAggregate) : .failed
    }

    private func isDefaultInputAggregate(_ deviceID: AudioDeviceID, name: String) -> Bool {
        if name.localizedCaseInsensitiveContains("DefaultDeviceAggregate") {
            return true
        }

        guard let uid = getDeviceUID(deviceID) else { return false }
        return uid.localizedCaseInsensitiveContains("DefaultDeviceAggregate")
    }

    private func defaultInputMatches(_ selection: DeviceSelection) -> Bool {
        let defaultDeviceID = getDefaultInputDeviceID()
        guard defaultDeviceID != 0 else { return false }
        if defaultDeviceID == selection.deviceID {
            return true
        }

        return getDeviceUID(defaultDeviceID) == selection.uid
    }

    private func currentInputDeviceID(for audioUnit: AudioUnit) -> AudioDeviceID? {
        var currentDeviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &currentDeviceID,
            &size
        )
        return status == noErr ? currentDeviceID : nil
    }

    private func resolveDevice() -> DeviceResolution {
        let store = TalkieSharedSettings
        let modeRaw = store.string(forKey: AgentSettingsKey.selectedMicrophoneMode)
            ?? MicrophoneSelectionMode.systemDefault.rawValue
        let mode = MicrophoneSelectionMode(rawValue: modeRaw) ?? .systemDefault

        switch mode {
        case .systemDefault:
            return .selection(selectSystemDefault())

        case .fixedUID:
            return selectConfiguredDevice()
        }
    }

    private func selectSystemDefault() -> DeviceSelection {
        let deviceID = getDefaultInputDeviceID()

        // Handle no input device (e.g., Mac Mini without mic)
        guard deviceID != 0 else {
            log.warning("No audio input device found on system")
            // Return a placeholder that will fail the isDeviceResponding check
            return DeviceSelection(deviceID: 0, uid: "none", name: "No Input Device", isFixedDevice: false)
        }

        let uid = getDeviceUID(deviceID) ?? "system_default"
        let name = getDeviceName(deviceID) ?? "System Default"

        log.info("Using system default microphone", detail: name)

        return DeviceSelection(deviceID: deviceID, uid: uid, name: name, isFixedDevice: false)
    }

    private func selectConfiguredDevice() -> DeviceResolution {
        let store = TalkieSharedSettings
        let requestedUID = store.string(forKey: AgentSettingsKey.selectedMicrophoneUID)
        let requestedName = store.string(forKey: AgentSettingsKey.selectedMicrophoneName)

        guard let uid = requestedUID else {
            log.warning("Fixed UID mode but no UID saved")
            return .missingFixed(uid: nil, name: requestedName)
        }

        // Try to find the configured device
        if let deviceID = findDeviceByUID(uid),
           let name = getDeviceName(deviceID) {
            log.info("Using configured microphone", detail: "\(name) (uid: \(uid))")
            return .selection(DeviceSelection(deviceID: deviceID, uid: uid, name: name, isFixedDevice: true))
        }

        // Device not found - surface so the user can choose a new device
        log.warning("Configured microphone unavailable",
                    detail: "'\(requestedName ?? uid)' not found")
        return .missingFixed(uid: uid, name: requestedName)
    }

    private struct FallbackInputCandidate {
        let selection: DeviceSelection
        let isDefault: Bool
        let score: Int
    }

    private func selectFallbackInputDevice(
        excludingUID: String?,
        excludingDeviceID: AudioDeviceID?
    ) -> DeviceSelection? {
        let defaultDeviceID = getDefaultInputDeviceID()
        let candidates = getAllDeviceIDs().compactMap { deviceID -> FallbackInputCandidate? in
            if let excludingDeviceID, deviceID == excludingDeviceID { return nil }
            guard hasInputStreams(deviceID) else { return nil }
            guard let uid = getDeviceUID(deviceID),
                  let name = getDeviceName(deviceID) else { return nil }
            if let excludingUID, uid == excludingUID { return nil }
            guard !isVirtualOrAggregateInput(name: name, uid: uid) else { return nil }
            guard isDeviceResponding(deviceID) else { return nil }

            let isDefault = deviceID == defaultDeviceID
            let lowerName = name.lowercased()
            var score = isDefault ? 100 : 0
            if lowerName.localizedStandardContains("webcam") { score += 40 }
            if lowerName.localizedStandardContains("built-in") { score += 35 }
            if lowerName.localizedStandardContains("microphone") { score += 25 }
            if lowerName.localizedStandardContains("iphone") { score -= 20 }
            if lowerName.localizedStandardContains("airpods") { score -= 15 }

            return FallbackInputCandidate(
                selection: DeviceSelection(
                    deviceID: deviceID,
                    uid: uid,
                    name: name,
                    isFixedDevice: true
                ),
                isDefault: isDefault,
                score: score
            )
        }

        let sorted = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.selection.name.localizedStandardCompare($1.selection.name) == .orderedAscending
        }

        guard let selected = sorted.first else { return nil }
        let candidateList = sorted
            .map { "\($0.selection.name)\($0.isDefault ? " default" : "")" }
            .joined(separator: ", ")
        log.info("Fallback microphone selected", detail: "\(selected.selection.name); candidates: \(candidateList)")
        return selected.selection
    }

    private func isVirtualOrAggregateInput(name: String, uid: String) -> Bool {
        let descriptor = "\(name) \(uid)".lowercased()
        let virtualMarkers = [
            "defaultdeviceaggregate",
            "aggregate",
            "blackhole",
            "teams audio",
            "speaker audio recorder",
            "loopback",
            "soundflower",
            "background music",
            "zoomaudio",
            "obs"
        ]
        return virtualMarkers.contains { descriptor.localizedStandardContains($0) }
    }

    /// Check if a device is responding (CoreAudio IPC is healthy)
    private func isDeviceResponding(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != 0 else {
            return getDefaultInputDeviceID() != 0
        }

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        if status == noErr, let cfName = name?.takeRetainedValue() {
            let _ = cfName as String
            return true
        }

        log.warning("Device not responding", detail: "deviceID=\(deviceID), status=\(status)")
        return false
    }

    // MARK: - CoreAudio Helpers (inlined from DeviceSelector)

    private func getDefaultInputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : 0
    }

    /// Set the system default input device.
    /// This is the reliable way to switch devices - AVAudioEngine picks up the new default on creation.
    /// Returns true on success, false on failure.
    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )

        return status == noErr
    }

    private func findDeviceByUID(_ uid: String) -> AudioDeviceID? {
        let deviceIDs = getAllDeviceIDs()

        for deviceID in deviceIDs {
            if let deviceUID = getDeviceUID(deviceID), deviceUID == uid {
                if hasInputStreams(deviceID) {
                    return deviceID
                }
            }
        }

        return nil
    }

    private func getAllDeviceIDs() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        return status == noErr ? deviceIDs : []
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        guard status == noErr, let cfUID = uid?.takeRetainedValue() else {
            return nil
        }

        return cfUID as String
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr, let cfName = name?.takeRetainedValue() else {
            return nil
        }

        return cfName as String
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }
}

private final class VoiceForegroundProcessor {
    private struct ChannelState {
        var previousInput: Float = 0
        var previousOutput: Float = 0
        var noiseFloor: Float = 0.012
    }

    private let cutoffFrequency: Double = 120
    private let speechFloor: Float = 0.012
    private let targetRMS: Float = 0.16
    private let maxSpeechGain: Float = 5
    private let backgroundAttenuation: Float = 0.65
    private let limiterKnee: Float = 0.85
    private let limiterCeiling: Float = 0.98

    private var channelStates: [ChannelState] = []

    func reset() {
        channelStates.removeAll(keepingCapacity: true)
    }

    func process(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard input.frameLength > 0,
              let sourceChannels = input.floatChannelData,
              let output = input.audioCaptureDeepCopy(),
              let outputChannels = output.floatChannelData else {
            return nil
        }

        let channelCount = Int(input.format.channelCount)
        let frameCount = Int(input.frameLength)
        ensureStateCount(channelCount)

        let highPassAlpha = highPassAlpha(sampleRate: input.format.sampleRate)

        for channelIndex in 0..<channelCount {
            let source = sourceChannels[channelIndex]
            let destination = outputChannels[channelIndex]
            var state = channelStates[channelIndex]
            var sumSquares: Float = 0

            for frameIndex in 0..<frameCount {
                let sample = source[frameIndex]
                let filtered = highPassAlpha * (state.previousOutput + sample - state.previousInput)
                state.previousInput = sample
                state.previousOutput = filtered
                destination[frameIndex] = filtered
                sumSquares += filtered * filtered
            }

            let rms = (sumSquares / Float(frameCount)).squareRoot()
            let speechThreshold = max(speechFloor, state.noiseFloor * 1.45)
            let speechLikely = rms >= speechThreshold

            if speechLikely {
                state.noiseFloor = max(speechFloor, min(state.noiseFloor * 1.005, state.noiseFloor + 0.0005))
            } else {
                let smoothing: Float = rms > state.noiseFloor ? 0.02 : 0.08
                state.noiseFloor = (state.noiseFloor * (1 - smoothing)) + (max(rms, 0.0005) * smoothing)
            }

            let gain: Float
            if speechLikely {
                gain = min(maxSpeechGain, max(1, targetRMS / max(rms, 0.001)))
            } else {
                gain = backgroundAttenuation
            }

            for frameIndex in 0..<frameCount {
                destination[frameIndex] = limit(destination[frameIndex] * gain)
            }

            channelStates[channelIndex] = state
        }

        return output
    }

    private func ensureStateCount(_ channelCount: Int) {
        guard channelStates.count != channelCount else { return }
        channelStates = Array(repeating: ChannelState(), count: channelCount)
    }

    private func highPassAlpha(sampleRate: Double) -> Float {
        guard sampleRate > 0 else { return 0.95 }
        let dt = 1 / sampleRate
        let rc = 1 / (2 * Double.pi * cutoffFrequency)
        return Float(rc / (rc + dt))
    }

    private func limit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > limiterKnee else { return sample }

        let sign: Float = sample < 0 ? -1 : 1
        let excess = magnitude - limiterKnee
        let compressed = limiterKnee + (excess / (1 + (excess / max(0.001, limiterCeiling - limiterKnee))))

        return sign * min(limiterCeiling, compressed)
    }
}

private extension AVAudioPCMBuffer {
    func audioCaptureDeepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }

        copy.frameLength = frameLength

        let sourcePointer = UnsafeMutablePointer<AudioBufferList>(mutating: audioBufferList)
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(sourcePointer)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        for index in 0..<Int(sourceBuffers.count) {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData else {
                continue
            }

            memcpy(destinationData, sourceData, Int(sourceBuffers[index].mDataByteSize))
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }

        return copy
    }
}
