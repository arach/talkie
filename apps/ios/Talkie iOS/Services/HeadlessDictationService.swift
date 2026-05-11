//
//  HeadlessDictationService.swift
//  Talkie iOS
//
//  Headless dictation for keyboard extension - no UI, just background recording.
//  When keyboard triggers dictation, this service handles everything silently.
//

import Foundation
import AVFoundation
import AudioToolbox
import Speech
import TalkieMobileKit
import UIKit

/// Handles keyboard dictation entirely in the background without showing any UI
final class HeadlessDictationService: NSObject, ObservableObject {

    static let shared = HeadlessDictationService()

    @Published var isActive = false
    @Published var isRecording = false
    @Published var isInReadyMode = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var stopPollTimer: Timer?
    private var readyPollTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastRecordingFailure: Date?
    private let failureCooldown: TimeInterval = 8.0  // Wait after failure before retrying
    private var handledStartRequestAt: Date?  // Track when we last handled a start request
    private var permissionRequestInFlight = false
    private var pendingForegroundStart = false
    private var didReturnToSource = false
    private var readyRetryCount = 0
    private let maxReadyRetries = 3
    private var warmRecorder: AVAudioRecorder?
    private var transcriptionTask: Task<Void, Never>?
    private var warmRecordingURL: URL?
    private var warmRecordingStartTime: TimeInterval?
    private var warmSegmentStartTime: TimeInterval?
    private var warmSegmentEndTime: TimeInterval?
    private var explicitActivationInProgress = false  // Prevents handleAppDidBecomeActive from overriding
    private var deactivationGuardUntil: Date?

    private let sharedStore = DictationSharedStore.shared
    private let bridge = KeyboardBridge.shared
    private let configurationStore = TalkieAppConfigurationStore.shared

    private var currentSessionId: UUID?
    private var lastKeyboardDebugSequence = 0
    private var lastStopPollLogKey: String?
    private var lastStopPollLogAt: TimeInterval = 0
    private var lastStartPollLogKey: String?
    private var lastStartPollLogAt: TimeInterval = 0
    private var commandChangedToken: DictationNotificationCenter.Token?
    private var isActuallyRecording: Bool {
        if audioRecorder?.isRecording == true {
            return true
        }
        if warmRecorder?.isRecording == true, warmSegmentStartTime != nil {
            return true
        }
        return false
    }

    private func logSharedState(_ context: String, detail: String? = nil) {
        let state = sharedStore.snapshot()
        let now = Date().timeIntervalSince1970
        let appHeartbeatAge = state.appHeartbeat > 0 ? String(format: "%.1fs", now - state.appHeartbeat) : "nil"
        let keyboardHeartbeatAge = state.keyboardHeartbeat > 0 ? String(format: "%.1fs", now - state.keyboardHeartbeat) : "nil"
        let command = state.command
        let commandInfo = command == nil
            ? "none"
            : "\(command!.kind.rawValue) id=\(command!.id) session=\(command!.sessionId) age=\(String(format: "%.1fs", now - command!.requestedAt)) epoch=\(command!.epoch)"
        let ackInfo = state.commandAck == nil
            ? "none"
            : "\(state.commandAck!.id) phase=\(state.commandAck!.phase.rawValue)"
        let resultInfo = state.lastResult == nil ? "none" : "session=\(state.lastResult!.sessionId) chars=\(state.lastResult!.text.count)"
        let errorInfo = state.lastError == nil ? "none" : "session=\(state.lastError!.sessionId?.uuidString ?? "nil") msg=\(state.lastError!.message)"

        let extraLine = detail == nil ? "" : "\n   detail: \(detail!)"
        AppLogger.app.info("""
            HeadlessDictation: \(context)
               phase: \(state.phase.rawValue) age=\(String(format: "%.1fs", state.phaseAge))
               capability: \(state.capability.rawValue)
               activeSession: \(state.activeSessionId?.uuidString ?? "nil")
               command: \(commandInfo)
               ack: \(ackInfo)
               result: \(resultInfo)
               error: \(errorInfo)
               appHeartbeatAge: \(appHeartbeatAge) keyboardHeartbeatAge: \(keyboardHeartbeatAge)\(extraLine)
            """)
    }

    private func logKeyboardDebugIfNeeded(context: String) {
        guard let event = sharedStore.readKeyboardDebug() else { return }
        guard event.sequence != lastKeyboardDebugSequence else { return }
        lastKeyboardDebugSequence = event.sequence
        AppLogger.app.info("""
            HeadlessDictation: Keyboard debug (\(context))
               seq: \(event.sequence)
               message: \(event.message)
               timestamp: \(event.timestamp)
               snapshot:
            \(event.snapshot)
            """)
    }

    private override init() {
        super.init()

        sharedStore.bumpEpoch(reason: "HeadlessDictationService init")

        // Sync isActive from file-backed preference, fallback to bridge state
        if configurationStore.configuration.keyboard.modeEnabled {
            isActive = true
            bridge.setKeyboardModeEnabled(true)
            AppLogger.app.info("HeadlessDictation: Init - restoring keyboard mode enabled")
        } else if bridge.getKeyboardModeEnabled() {
            AppLogger.app.info("HeadlessDictation: Init - restoring keyboard mode enabled from bridge")
            isActive = true
            persistKeyboardModePreference(true)
        } else if bridge.isAppReady() {
            AppLogger.app.info("HeadlessDictation: Init - syncing isActive=true from bridge state")
            isActive = true
            persistKeyboardModePreference(true)
        }

        // Listen for app becoming active to re-enter ready mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        commandChangedToken = DictationNotificationCenter.shared.addObserver(.commandChanged) { [weak self] in
            self?.handleCommandSignal()
        }
    }

    deinit {
        if let token = commandChangedToken {
            DictationNotificationCenter.shared.removeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func persistKeyboardModePreference(_ enabled: Bool) {
        configurationStore.update { configuration in
            configuration.keyboard.modeEnabled = enabled
        }
        UserDefaults.standard.set(enabled, forKey: KeyboardBridgeKey.keyboardModeEnabled.rawValue)
        bridge.setKeyboardModeEnabled(enabled)
        Task { @MainActor in
            TalkieAppSettings.shared.reloadFromDisk()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        sharedStore.updateAppHeartbeat()
        logKeyboardDebugIfNeeded(context: "appDidBecomeActive")

        // Don't override explicit user activation (via deep link)
        // The explicit activation flow will set bridge state when ready
        if explicitActivationInProgress {
            AppLogger.app.info("HeadlessDictation: Skipping bridge sync - explicit activation in progress")
            return
        }

        // Check for pending deep link actions that will activate dictation
        // These are set by DeepLinkManager BEFORE this notification fires
        let pendingAction = DeepLinkManager.shared.pendingAction
        let hasPendingDictation = pendingAction == .dictate ||
                                   pendingAction == .keyboardActivate
        if hasPendingDictation {
            AppLogger.app.info("HeadlessDictation: Skipping bridge sync - pending deep link action: \(pendingAction)")
            return
        }

        // Sync isActive from bridge state on app foreground
        // This fixes the case where app was terminated but bridge still has ready=true
        let bridgeReady = bridge.isAppReady()
        if bridgeReady && !isActive {
            AppLogger.app.info("HeadlessDictation: Syncing isActive=true from bridge state")
            isActive = true
        } else if !bridgeReady && isActive {
            // Keep isActive as a user preference; only drop ready mode.
            AppLogger.app.info("HeadlessDictation: Bridge not ready - clearing ready mode")
            isInReadyMode = false
        }

        guard isActive else { return }

        // Check if shared store is in an active state (recording, stopping, transcribing)
        // Don't interfere if KeyboardPlayground or another component is handling dictation
        let activePhases: [DictationSharedState.Phase] = [.recording, .stopping, .transcribing]
        if activePhases.contains(sharedStore.phase) {
            AppLogger.app.info("HeadlessDictation: App became active but shared store is busy (\(sharedStore.phase)) - not entering ready mode")
            return
        }

        // If we're already in ready mode but warm recorder isn't running, start it now
        // This happens when we maintained ready state while backgrounded
        if isInReadyMode && warmRecorder?.isRecording != true && !isRecording {
            AppLogger.app.info("HeadlessDictation: App became active - starting warm recorder for ready mode")
            if configureAudioSession() {
                _ = startWarmRecorder()
            }
        }

        // If we're not recording and service is active, ensure we're in ready mode
        if !isRecording && !isInReadyMode {
            AppLogger.app.info("HeadlessDictation: App became active - entering ready mode")
            enterReadyMode()
        }

        if pendingForegroundStart {
            AppLogger.app.info("HeadlessDictation: Handling deferred start on foreground")
            pendingForegroundStart = false
            // Clear failure cooldown - this is triggered by user action (keyboard tap or deep link)
            lastRecordingFailure = nil
            if let command = acceptStartCommandIfPresent(context: "foreground") {
                startRecording(sessionId: command.sessionId)
            } else {
                let sessionId = currentSessionId ?? UUID()
                currentSessionId = sessionId
                sharedStore.appSetPhase(.arming, sessionId: sessionId)
                startRecording(sessionId: sessionId)
            }
        }
    }

    @objc private func handleAppWillResignActive() {
        guard isActive else { return }
        AppLogger.app.info("HeadlessDictation: App will resign active")
    }

    // MARK: - Public API

    /// Mark that dictation activation is about to start (called early in deep link handling)
    /// This prevents handleAppDidBecomeActive from resetting state before handleDictationRequest runs
    func prepareForDictation() {
        AppLogger.app.info("HeadlessDictation: Preparing for dictation")
        explicitActivationInProgress = true
    }

    /// Start the headless dictation service (called when keyboard mode is enabled)
    func activate() {
        if isActive {
            // Keep the shared preference and readiness aligned even on repeated toggles.
            persistKeyboardModePreference(true)
            if !isInReadyMode {
                enterReadyMode()
            }
            return
        }
        isActive = true
        persistKeyboardModePreference(true)

        AppLogger.app.info("HeadlessDictation: Activating")

        // Enter ready mode
        enterReadyMode()
    }

    /// Stop the headless dictation service
    func deactivate(explicit: Bool = false) {
        if !explicit,
           let guardUntil = deactivationGuardUntil,
           Date() < guardUntil {
            AppLogger.app.info("HeadlessDictation: Ignoring non-explicit deactivate during activation guard window")
            return
        }

        guard isActive else {
            persistKeyboardModePreference(false)
            return
        }

        AppLogger.app.info("HeadlessDictation: Deactivating")

        explicitActivationInProgress = false  // Clear any pending activation
        stopPolling()
        exitReadyMode()

        if isRecording {
            cancelRecording()
        }

        sharedStore.forceReset(reason: "Headless dictation deactivated", preserveCapability: false, updatedBy: "app")
        isActive = false
        persistKeyboardModePreference(false)
        deactivationGuardUntil = nil
    }

    /// Handle incoming dictation request (from URL scheme)
    func handleDictationRequest() {
        AppLogger.app.info("HeadlessDictation: Handling dictation request")
        let now = Date()
        if let guardUntil = deactivationGuardUntil, now < guardUntil {
            AppLogger.app.info("HeadlessDictation: Keeping existing deactivation guard window active")
        } else {
            deactivationGuardUntil = now.addingTimeInterval(8)
        }
        sharedStore.updateAppHeartbeat()
        logKeyboardDebugIfNeeded(context: "handleDictationRequest")
        logSharedState("handleDictationRequest")
        didReturnToSource = false

        // Proactively start loading/warming Parakeet model
        // By the time user finishes speaking, model should be ready
        Task { @MainActor in
            let state = ParakeetModelManager.shared.state
            AppLogger.app.info("HeadlessDictation: Preheating Parakeet (current state: \(state))")
            ParakeetModelManager.shared.preheatForKeyboard()
        }

        // Mark explicit activation in progress - prevents handleAppDidBecomeActive from overriding
        explicitActivationInProgress = true

        // Accept any pending start command (V2 flow)
        if let command = acceptStartCommandIfPresent(context: "deeplink") {
            currentSessionId = command.sessionId
        }

        let currentPhase = sharedStore.phase
        if isRecording && !isActuallyRecording {
            AppLogger.app.warning("HeadlessDictation: Stale recording flag detected - clearing")
            isRecording = false
            bridge.setRecordingInProgress(false)
        }
        if currentPhase == .recording && !isActuallyRecording {
            AppLogger.app.warning("HeadlessDictation: Stale recording phase detected - resetting before new request")
            bridge.setRecordingInProgress(false)
            sharedStore.appSetPhase(.idle, sessionId: sharedStore.activeSessionId ?? currentSessionId)
            sharedStore.appClearCommand()
        }

        // If recording is already in progress (started via bridge before deep link arrived),
        // just acknowledge it - don't try to start fresh
        if isActuallyRecording {
            AppLogger.app.info("HeadlessDictation: Recording already in progress - acknowledging")
            isActive = true
            isInReadyMode = true  // Show "ready" since we're actively handling dictation
            bridge.setAppReady(true)
            let sessionId = currentSessionId ?? sharedStore.activeSessionId ?? UUID()
            currentSessionId = sessionId
            _ = acknowledgeStartCommandIfPresent(sessionId: sessionId, phase: .recording, context: "handleDictationRequest")
            sharedStore.appSetPhase(.recording, sessionId: sessionId)
            finalizeStartCommandIfPresent(sessionId: sessionId, context: "handleDictationRequest")
            sharedStore.setCapability(.warm)
            startStopPolling()  // Make sure we're polling for stop requests
            returnToSourceAppIfPossible()
            explicitActivationInProgress = false
            return
        }

        // Clear failure cooldown - user explicitly requested via deep link
        // The cooldown is meant to prevent rapid automatic retries, not block explicit user requests
        if lastRecordingFailure != nil {
            AppLogger.app.info("HeadlessDictation: Clearing failure cooldown for explicit deep link request")
            lastRecordingFailure = nil
        }

        // For explicit deep link requests, use a shorter stale threshold (10s vs 60s)
        // User is actively trying to record, so clear any stuck state
        let explicitRequestStaleThreshold: TimeInterval = 10.0
        let phaseAge = sharedStore.phaseAge
        if phaseAge > explicitRequestStaleThreshold && currentPhase != .idle && currentPhase != .ready {
            AppLogger.app.warning("HeadlessDictation: Clearing stale \(currentPhase) phase for explicit request (age: \(Int(phaseAge))s)")
            bridge.forceReset()
            sharedStore.forceReset(reason: "Stale state cleared for explicit dictation request", preserveCapability: true, updatedBy: "app")
        }

        // Make sure we're active
        if !isActive {
            activate()
        }

        // Wait for app to become fully active before starting recording
        // The deep link opens the app but it takes a moment to reach .active state
        startRecordingWhenActive()
    }

    /// Wait for app to become active, then start recording
    private func startRecordingWhenActive(attempts: Int = 0) {
        let maxAttempts = 10  // Max 1 second of waiting
        let appState = UIApplication.shared.applicationState

        if appState == .active {
            AppLogger.app.info("HeadlessDictation: App is active, starting recording")
            explicitActivationInProgress = false  // Clear flag - activation complete
            let sessionId = currentSessionId ?? UUID()
            if currentSessionId == nil {
                currentSessionId = sessionId
                sharedStore.appSetPhase(.arming, sessionId: sessionId)
            }
            if warmRecorder?.isRecording == true {
                // Warm recorder already running - use it for continuous mode
                beginWarmSegment(sessionId: sessionId)
                startStopPolling()
            } else {
                // Try to start warm recorder for continuous mode
                // This establishes the session so subsequent recordings don't need app switch
                if startWarmRecorder() {
                    AppLogger.app.info("HeadlessDictation: Started warm recorder for continuous mode")
                    beginWarmSegment(sessionId: sessionId)
                    startStopPolling()
                } else {
                    // Fall back to regular recording if warm recorder fails
                    AppLogger.app.warning("HeadlessDictation: Warm recorder failed, using regular recording")
                    startRecording(sessionId: sessionId)
                }
            }
            return
        }

        if attempts >= maxAttempts {
            AppLogger.app.error("HeadlessDictation: Timeout waiting for app to become active")
            explicitActivationInProgress = false  // Clear flag - activation failed
            sharedStore.forceReset(reason: "Timeout waiting for foreground", preserveCapability: true, updatedBy: "app")
            return
        }

        // Wait and retry
        AppLogger.app.info("HeadlessDictation: Waiting for app to become active (attempt \(attempts + 1))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startRecordingWhenActive(attempts: attempts + 1)
        }
    }

    // MARK: - Ready Mode

    private func enterReadyMode() {
        sharedStore.updateAppHeartbeat()

        // Proactively warm up Parakeet while waiting for dictation
        Task { @MainActor in
            let state = ParakeetModelManager.shared.state
            AppLogger.app.info("HeadlessDictation: Preheating Parakeet in ready mode (current state: \(state))")
            ParakeetModelManager.shared.preheatForKeyboard()
        }

        // Clear any stale state - if phase has been stuck for over 60 seconds, it's definitely stale
        // This handles cases where app was killed mid-operation and state persisted in App Group
        let staleThreshold: TimeInterval = 60.0
        if sharedStore.phaseAge > staleThreshold && sharedStore.phase != .ready {
            AppLogger.app.warning("HeadlessDictation: Clearing stale \(sharedStore.phase) phase (age: \(Int(sharedStore.phaseAge))s)")
            bridge.forceReset()  // Also clear bridge state
            sharedStore.forceReset(reason: "Stale state cleared on ready mode entry", preserveCapability: true, updatedBy: "app")
        }

        let appState = UIApplication.shared.applicationState
        let isBackgrounded = appState != .active

        // Only proceed from safe states - don't interrupt active operations
        // IMPORTANT: Don't transition from DONE - keyboard needs to consume result first
        // The keyboard will set phase to IDLE after consuming, then we can transition to READY
        let currentPhase = sharedStore.phase
        if currentPhase == .done || currentPhase == .error {
            AppLogger.app.info("HeadlessDictation: State is DONE - waiting for keyboard to consume result before entering ready mode")
            // Keep polling so we can enter ready mode after keyboard consumes result
            if readyPollTimer == nil {
                startReadyPolling()
            }
            return
        }

        let safeToReset: [DictationSharedState.Phase] = [.idle, .ready]
        if safeToReset.contains(currentPhase) {
            // Only force reset from IDLE - READY is already there
            if currentPhase == .idle {
                sharedStore.forceReset(reason: "HeadlessDictation: Entering ready mode", preserveCapability: true, updatedBy: "app")
            }
            // Transition to ready
            if currentPhase != .ready {
                sharedStore.appSetPhase(.ready, sessionId: nil)
            }
        } else {
            AppLogger.app.warning("HeadlessDictation: Not entering ready mode - shared store is busy (\(sharedStore.phase), age: \(Int(sharedStore.phaseAge))s)")
            bridge.setAppReady(false)
            isInReadyMode = false
            let shared = sharedStore.snapshot()
            let pendingStart = shared.command?.kind == .start
            let shouldPollForStart: Bool = {
                guard pendingStart, let command = shared.command else { return shared.phase == .arming }
                if shared.isCommandAcked(command) { return false }
                if command.epoch != shared.epoch { return false }
                return sharedStore.isCommandFresh(command)
            }()
            if shouldPollForStart {
                startReadyPolling()
            }
            return
        }

        // When backgrounded, check if warm recorder is already running
        // If not, we can't provide instant start - keyboard will use deep link flow
        if isBackgrounded {
            if warmRecorder?.isRecording == true {
                // Warm recorder still running - can provide instant start
                AppLogger.app.info("HeadlessDictation: App is backgrounded but warm recorder active - maintaining ready state")
                isInReadyMode = true
                bridge.setAppReady(true)
                sharedStore.setCapability(.warm)
                startReadyPolling()
                readyRetryCount = 0
            } else {
                // No warm recorder, can't start one from background
                // Don't signal ready - keyboard will use deep link to bring app to foreground
                AppLogger.app.info("HeadlessDictation: App is backgrounded without warm recorder - not signaling ready")
                isInReadyMode = false
                bridge.setAppReady(false)
                sharedStore.setCapability(.foregroundOnly)
                // Stop polling since we're not ready
                readyPollTimer?.invalidate()
                readyPollTimer = nil
            }
            return
        }

        guard configureAudioSession() else {
            AppLogger.app.warning("HeadlessDictation: Ready mode not enabled - audio session unavailable")
            bridge.setAppReady(false)
            isInReadyMode = false
            sharedStore.setCapability(.foregroundOnly)
            scheduleReadyRetry()
            return
        }

        if startWarmRecorder() {
            isInReadyMode = true
            bridge.setAppReady(true)
            sharedStore.setCapability(.warm)
            AppLogger.app.info("HeadlessDictation: Ready mode enabled with warm recorder")

            // Start polling for keyboard requests
            startReadyPolling()
            readyRetryCount = 0
        } else {
            // Warm recorder failed but we can still maintain ready state
            // Next recording will use regular recorder when app is foregrounded
            isInReadyMode = true
            bridge.setAppReady(true)
            sharedStore.setCapability(.foregroundOnly)
            AppLogger.app.info("HeadlessDictation: Ready mode enabled (no warm recorder)")
            startReadyPolling()
            readyRetryCount = 0
        }
    }

    private func exitReadyMode() {
        readyPollTimer?.invalidate()
        readyPollTimer = nil
        isInReadyMode = false
        bridge.setAppReady(false)
        sharedStore.appSetPhase(.idle, sessionId: nil)
        stopWarmRecorder(setCapability: DictationSharedState.Capability.none)
    }

    private func startReadyPolling() {
        readyPollTimer?.invalidate()

        // Poll for keyboard start requests
        readyPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForStartRequest()
        }
        RunLoop.current.add(readyPollTimer!, forMode: .common)
    }

    private func checkForStartRequest() {
        sharedStore.updateAppHeartbeat()
        logKeyboardDebugIfNeeded(context: "start-poll")
        let sharedForLog = sharedStore.snapshot()
        if sharedForLog.phase == .stopping || sharedForLog.phase == .transcribing {
            return
        }
        let logKey = "\(sharedForLog.phase.rawValue)|\(sharedForLog.command?.id.uuidString ?? "nil")|\(sharedForLog.commandAck?.id.uuidString ?? "nil")|\(sharedForLog.lastResult?.sessionId.uuidString ?? "nil")|\(sharedForLog.lastError?.sessionId?.uuidString ?? "nil")|\(isRecording)"
        let now = Date().timeIntervalSince1970
        if logKey != lastStartPollLogKey || (now - lastStartPollLogAt) > 2.0 {
            lastStartPollLogKey = logKey
            lastStartPollLogAt = now
            logSharedState("checkForStartRequest")
        }

        let heartbeatState = sharedStore.snapshot()
        let heartbeatNow = Date().timeIntervalSince1970
        if heartbeatState.keyboardHeartbeat > 0,
           (heartbeatNow - heartbeatState.keyboardHeartbeat) > 12.0,
           !isRecording {
            AppLogger.app.info("HeadlessDictation: Keyboard heartbeat stale - dropping warm readiness")
            isInReadyMode = false
            bridge.setAppReady(false)
            stopWarmRecorder(setCapability: .foregroundOnly)
            readyPollTimer?.invalidate()
            readyPollTimer = nil
            return
        }

        // Refresh ready timestamp
        bridge.refreshAppReady()

        // Check if keyboard consumed result (phase transitioned to IDLE)
        // If so, we can now enter READY state
        let currentPhase = sharedStore.phase
        if currentPhase == .idle && !isRecording && !isInReadyMode {
            AppLogger.app.info("HeadlessDictation: Phase is IDLE - entering ready mode")
            sharedStore.appSetPhase(.ready, sessionId: nil)
            isInReadyMode = true
            bridge.setAppReady(true)
        }

        // Check cooldown after failure
        if let lastFailure = lastRecordingFailure {
            if Date().timeIntervalSince(lastFailure) < failureCooldown {
                bridge.clearStartRequest()
                return  // Still in cooldown, skip this poll
            }
        }

        // Prevent rapid re-handling of same request (debounce)
        if let lastHandled = handledStartRequestAt {
            if Date().timeIntervalSince(lastHandled) < 0.5 {
                return  // Already handled recently
            }
        }

        // Check if keyboard requested to start via shared state
        if let command = acceptStartCommandIfPresent(context: "ready-poll"), !isRecording {
            handledStartRequestAt = Date()
            logSharedState("startCommandAccepted", detail: "source=ready-poll session=\(command.sessionId)")
            if warmRecorder?.isRecording == true {
                beginWarmSegment(sessionId: command.sessionId)
                startStopPolling()
            } else {
                startRecording(sessionId: command.sessionId)
            }
            return
        }
    }

    private func handleCommandSignal() {
        let state = sharedStore.snapshot()

        if state.command?.kind == .cancel {
            handleCancelCommand()
            return
        }

        if state.command?.kind == .stop || state.phase == .stopping {
            readyPollTimer?.invalidate()
            readyPollTimer = nil
            if stopPollTimer == nil {
                startStopPolling()
            }
            checkForStopRequest()
            return
        }

        if state.command?.kind == .start {
            if readyPollTimer == nil {
                startReadyPolling()
            }
            checkForStartRequest()
        }
    }

    private func handleCancelCommand() {
        let state = sharedStore.snapshot()
        guard let command = state.command, command.kind == .cancel else { return }

        // Only cancel if epoch matches and command is fresh
        guard command.epoch == state.epoch, sharedStore.isCommandFresh(command) else {
            sharedStore.appClearCommand()
            return
        }

        AppLogger.app.info("HeadlessDictation: Cancel command received — aborting transcription")
        logSharedState("handleCancelCommand", detail: "session=\(command.sessionId)")

        // Cancel the in-flight transcription task
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Stop any active recording
        if isRecording {
            audioRecorder?.stop()
            warmRecorder?.stop()
            warmRecorder = nil
            warmRecordingURL = nil
            warmRecordingStartTime = nil
            warmSegmentStartTime = nil
            warmSegmentEndTime = nil
            isRecording = false
            bridge.setRecordingInProgress(false)
        }

        // Stop polling
        stopPollTimer?.invalidate()
        stopPollTimer = nil

        // Clean up audio file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        // Reset state
        sharedStore.appAcknowledgeCommand(command, phase: .idle)
        sharedStore.appClearCommand()
        currentSessionId = nil

        endBackgroundTask()

        // Re-enter ready mode for next recording
        reenterReadyMode()
    }

    private func acceptStartCommandIfPresent(context: String) -> DictationSharedState.Command? {
        let state = sharedStore.snapshot()
        guard let command = state.command, command.kind == .start else { return nil }

        // Don't accept starts while a result/error is pending or app is busy
        let busyPhases: [DictationSharedState.Phase] = [.recording, .stopping, .transcribing, .done, .error]
        if busyPhases.contains(state.phase) || state.lastResult != nil || state.lastError != nil || isRecording {
            logSharedState("startCommandIgnored", detail: "context=\(context) reason=busy phase=\(state.phase.rawValue)")
            return nil
        }

        // Ignore already-acked commands
        if state.isCommandAcked(command) {
            logSharedState("startCommandIgnored", detail: "context=\(context) reason=already_acked")
            return nil
        }

        // Ignore stale or wrong-epoch commands
        if command.epoch != state.epoch || !sharedStore.isCommandFresh(command) {
            sharedStore.appClearCommand()
            logSharedState("startCommandIgnored", detail: "context=\(context) reason=stale epoch=\(command.epoch) stateEpoch=\(state.epoch)")
            return nil
        }

        // Respect cooldown
        if state.isCoolingDown() {
            logSharedState("startCommandIgnored", detail: "context=\(context) reason=cooldown")
            return nil
        }

        AppLogger.app.info("HeadlessDictation: Start command accepted (\(context))")
        currentSessionId = command.sessionId
        sharedStore.appAcknowledgeCommand(command, phase: .arming)
        return command
    }

    @discardableResult
    private func acknowledgeStartCommandIfPresent(
        sessionId: UUID,
        phase: DictationSharedState.Phase,
        context: String
    ) -> Bool {
        let state = sharedStore.snapshot()
        guard let command = state.command, command.kind == .start else { return false }
        guard command.sessionId == sessionId else { return false }
        if state.isCommandAcked(command), state.commandAck?.phase == phase {
            return true
        }
        if command.epoch != state.epoch || !sharedStore.isCommandFresh(command) {
            sharedStore.appClearCommand()
            return false
        }
        sharedStore.appAcknowledgeCommand(command, phase: phase)
        logSharedState("startCommandAcked", detail: "context=\(context) session=\(sessionId)")
        return true
    }

    private func finalizeStartCommandIfPresent(sessionId: UUID, context: String) {
        let state = sharedStore.snapshot()
        guard let command = state.command, command.kind == .start, command.sessionId == sessionId else { return }
        sharedStore.appClearCommand()
        logSharedState("startCommandCleared", detail: "context=\(context) session=\(sessionId)")
    }

    // MARK: - Recording

    @discardableResult
    private func configureAudioSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true)
            AppLogger.app.info("HeadlessDictation: Audio session configured")
            return true
        } catch {
            AppLogger.app.error("HeadlessDictation: Failed to configure audio session: \(error)")
            return false
        }
    }

    private func startRecording(sessionId: UUID) {
        guard !isRecording else {
            AppLogger.app.warning("HeadlessDictation: Already recording")
            return
        }

        currentSessionId = sessionId
        sharedStore.appSetPhase(.arming, sessionId: sessionId)
        logSharedState("startRecording", detail: "session=\(sessionId)")

        ensurePermissions { [weak self] granted in
            guard let self = self else { return }
            if !granted {
                self.bridge.setDictationError("Permissions required")
                self.sharedStore.appSetError(
                    message: "Permissions required",
                    sessionId: sessionId,
                    code: "permissions",
                    recoverable: true,
                    retryAfter: self.failureCooldown
                )
                self.reenterReadyMode()
                return
            }

            self.startRecordingWithPermissions(sessionId: sessionId)
        }
    }

    private func startRecordingWithPermissions(sessionId: UUID) {
        // Ensure Parakeet is warming up in parallel with recording
        Task { @MainActor in
            let state = ParakeetModelManager.shared.state
            AppLogger.app.info("HeadlessDictation: Preheating Parakeet before recording (current state: \(state))")
            ParakeetModelManager.shared.preheatForKeyboard()
        }

        // Check if app is in foreground - can't start recording from background
        if let lastFailure = lastRecordingFailure,
           Date().timeIntervalSince(lastFailure) < failureCooldown {
            AppLogger.app.warning("HeadlessDictation: In failure cooldown - not starting")
            logSharedState("startRecordingBlocked", detail: "session=\(sessionId) reason=cooldown")
            bridge.clearStartRequest()
            return
        }

        let appState = UIApplication.shared.applicationState
        if appState != .active && !isInReadyMode {
            AppLogger.app.warning("HeadlessDictation: App is in background (\(appState.rawValue)) - deferring start")

            pendingForegroundStart = true

            // Clear stop request; keep start request so we can honor it on foreground
            bridge.clearStopRequest()
            bridge.setRecordingInProgress(false)

            // Signal that instant start isn't available while backgrounded
            // Don't re-enter ready mode - wait for app to become active
            bridge.setAppReady(false)
            isInReadyMode = false
            sharedStore.setCapability(.foregroundOnly)
            lastRecordingFailure = Date()

            // Stop polling while backgrounded to avoid retry loop
            readyPollTimer?.invalidate()
            readyPollTimer = nil

            // Ready mode will be restored when app becomes active (via notification)
            return
        }

        AppLogger.app.info("HeadlessDictation: Starting recording (app in foreground)")
        logSharedState("startRecordingForeground", detail: "session=\(sessionId)")

        // Start background task
        startBackgroundTask()

        // Configure and activate audio session (must reconfigure, not just activate)
        let session = AVAudioSession.sharedInstance()
        do {
            // Full configuration - required for recording to work
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true)
            AppLogger.app.info("HeadlessDictation: Audio session ready")
        } catch {
            AppLogger.app.error("HeadlessDictation: Failed to configure audio session: \(error)")
            lastRecordingFailure = Date()
            sharedStore.appSetError(
                message: "Microphone unavailable",
                sessionId: sessionId,
                code: "audio_session",
                recoverable: true,
                retryAfter: failureCooldown
            )
            bridge.clearStartRequest()
            bridge.setAppReady(false)
            isInReadyMode = false
            attemptForegroundRecovery(reason: "Audio session unavailable")
            scheduleReadyModeAfterCooldown()
            endBackgroundTask()
            return
        }

        // Create recording file
        let filename = UUID().uuidString + ".m4a"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        recordingURL = url

        // Recording settings - simpler format for reliability
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self

            // Prepare before recording (allocates resources)
            guard audioRecorder?.prepareToRecord() == true else {
                AppLogger.app.error("HeadlessDictation: prepareToRecord() failed")
                lastRecordingFailure = Date()
                sharedStore.appSetError(
                    message: "Recording failed",
                    sessionId: sessionId,
                    code: "prepare_failed",
                    recoverable: true,
                    retryAfter: failureCooldown
                )
                reenterReadyMode()
                endBackgroundTask()
                return
            }

            // Now start recording
            if audioRecorder?.record() == true {
                isRecording = true
                isInReadyMode = true  // Service is actively handling keyboard dictation
                lastRecordingFailure = nil  // Clear any previous failure
                if !acknowledgeStartCommandIfPresent(sessionId: sessionId, phase: .recording, context: "startRecording") {
                    sharedStore.appSetPhase(.recording, sessionId: sessionId)
                }
                finalizeStartCommandIfPresent(sessionId: sessionId, context: "startRecording")
                bridge.setAppReady(true)  // App is ready for keyboard commands (stop)
                bridge.setRecordingInProgress(true)

                AppLogger.app.info("HeadlessDictation: Recording started successfully")

                returnToSourceAppIfPossible()

                // Start polling for stop request
                startStopPolling()
            } else {
                AppLogger.app.error("HeadlessDictation: record() returned false - check mic permissions")
                lastRecordingFailure = Date()
                sharedStore.appSetError(
                    message: "Recording failed",
                    sessionId: sessionId,
                    code: "recording_failed",
                    recoverable: true,
                    retryAfter: failureCooldown
                )
                bridge.clearStartRequest()
                bridge.setAppReady(false)
                scheduleReadyModeAfterCooldown()
                attemptForegroundRecovery(reason: "Record returned false")
                endBackgroundTask()
            }
        } catch {
            AppLogger.app.error("HeadlessDictation: Failed to create recorder: \(error)")
            lastRecordingFailure = Date()
            sharedStore.appSetError(
                message: "Recording failed",
                sessionId: sessionId,
                code: "recorder_init",
                recoverable: true,
                retryAfter: failureCooldown
            )
            bridge.clearStartRequest()
            bridge.setAppReady(false)
            scheduleReadyModeAfterCooldown()
            attemptForegroundRecovery(reason: "Recorder init failed")
            endBackgroundTask()
        }
    }

    private func startStopPolling() {
        stopPollTimer?.invalidate()

        stopPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForStopRequest()
        }
        RunLoop.current.add(stopPollTimer!, forMode: .common)
    }

    private func stopStopPolling() {
        stopPollTimer?.invalidate()
        stopPollTimer = nil
    }

    private func stopPolling() {
        stopStopPolling()
        readyPollTimer?.invalidate()
        readyPollTimer = nil
    }

    private func checkForStopRequest() {
        sharedStore.updateAppHeartbeat()
        logKeyboardDebugIfNeeded(context: "stop-poll")
        let shared = sharedStore.snapshot()
        let logKey = "\(shared.phase.rawValue)|\(shared.command?.id.uuidString ?? "nil")|\(shared.commandAck?.id.uuidString ?? "nil")|\(shared.lastResult?.sessionId.uuidString ?? "nil")|\(shared.lastError?.sessionId?.uuidString ?? "nil")|\(isRecording)"
        let now = Date().timeIntervalSince1970
        if logKey != lastStopPollLogKey || (now - lastStopPollLogAt) > 2.0 {
            lastStopPollLogKey = logKey
            lastStopPollLogAt = now
            logSharedState("checkForStopRequest")
        }

        if isRecording, let command = shared.command, command.kind == .start {
            if currentSessionId == nil || currentSessionId != command.sessionId {
                currentSessionId = command.sessionId
            }
            if (!shared.isCommandAcked(command) || shared.commandAck?.phase != .recording),
               command.epoch == shared.epoch,
               sharedStore.isCommandFresh(command) {
                sharedStore.appAcknowledgeCommand(command, phase: .recording)
                logSharedState("startCommandAutoAck", detail: "context=stop-poll session=\(command.sessionId)")
            } else if shared.phase == .arming {
                sharedStore.appSetPhase(.recording, sessionId: shared.activeSessionId ?? currentSessionId)
            }
        }
        if let command = shared.command, command.kind == .start, !sharedStore.isCommandFresh(command), !isRecording {
            AppLogger.app.warning("HeadlessDictation: Clearing stale start command")
            sharedStore.appClearCommand()
            sharedStore.appSetPhase(.idle, sessionId: shared.activeSessionId)
        }

        // Check if keyboard requested stop via shared state
        if let command = acceptStopCommandIfPresent() {
            logSharedState("stopCommandAccepted", detail: "session=\(command.sessionId)")
            if !isRecording {
                AppLogger.app.info("HeadlessDictation: Stop command received but not recording")
                bridge.setRecordingInProgress(false)
                sharedStore.appClearCommand()
                sharedStore.appSetPhase(.idle, sessionId: command.sessionId)
                return
            }
            stopAndTranscribe()
            return
        }

        // Fallback path: consume stop requests written via KeyboardBridge.
        // This keeps the old stop mechanism working when a shared-store stop command
        // was not created (for example when session ID is temporarily unavailable in UI).
        if bridge.isStopRequested() {
            if isRecording {
                AppLogger.app.info("HeadlessDictation: Stop requested via bridge")
                if shared.phase != .stopping {
                    sharedStore.appSetPhase(.stopping, sessionId: shared.activeSessionId ?? currentSessionId)
                }
                stopAndTranscribe()
            } else {
                AppLogger.app.info("HeadlessDictation: Bridge stop request received while not recording")
                bridge.clearStopRequest()
                bridge.setRecordingInProgress(false)
                if shared.phase == .stopping {
                    sharedStore.appSetPhase(.idle, sessionId: shared.activeSessionId ?? currentSessionId)
                }
            }
            return
        }

        if !isRecording && shared.phase != .stopping {
            stopStopPolling()
            return
        }
    }

    private func acceptStopCommandIfPresent() -> DictationSharedState.Command? {
        let state = sharedStore.snapshot()
        guard let command = state.command, command.kind == .stop else { return nil }

        if state.isCommandAcked(command) {
            return nil
        }

        if command.epoch != state.epoch || !sharedStore.isCommandFresh(command) {
            sharedStore.appClearCommand()
            return nil
        }

        if isRecording, let currentSessionId, command.sessionId != currentSessionId {
            if state.activeSessionId == command.sessionId {
                self.currentSessionId = command.sessionId
            } else {
                return nil
            }
        }

        sharedStore.appAcknowledgeCommand(command, phase: .stopping)
        return command
    }

    private func stopAndTranscribe() {
        guard isRecording else { return }
        logSharedState("stopAndTranscribe", detail: "session=\(currentSessionId?.uuidString ?? "nil")")

        if warmRecorder?.isRecording == true, warmSegmentStartTime != nil {
            endWarmSegmentAndTranscribe()
            return
        }

        AppLogger.app.info("HeadlessDictation: Stopping recording")

        stopPollTimer?.invalidate()
        stopPollTimer = nil

        audioRecorder?.stop()
        isRecording = false
        bridge.setRecordingInProgress(false)

        if let sessionId = currentSessionId {
            sharedStore.appSetPhase(.transcribing, sessionId: sessionId)
        }

        // Transcribe
        guard let url = recordingURL else {
            AppLogger.app.error("HeadlessDictation: No recording URL")
            sharedStore.appSetError(
                message: "No recording",
                sessionId: currentSessionId,
                code: "missing_audio",
                recoverable: true,
                retryAfter: failureCooldown
            )
            reenterReadyMode()
            return
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLogger.app.error("HeadlessDictation: Recording file doesn't exist")
            sharedStore.appSetError(
                message: "Recording failed",
                sessionId: currentSessionId,
                code: "file_missing",
                recoverable: true,
                retryAfter: failureCooldown
            )
            reenterReadyMode()
            return
        }

        let sessionId = currentSessionId

        // Before transcribing, give Parakeet a moment to finish loading if it's in progress
        // This prevents falling back to Apple Speech on first cold run
        transcriptionTask = Task { @MainActor in
            let parakeetManager = ParakeetModelManager.shared
            let state = parakeetManager.state
            let isWarmed = parakeetManager.isWarmedUp

            // If Parakeet is loading or warming up, wait for it (but not too long)
            if state == .loading || (state == .ready && !isWarmed) {
                AppLogger.app.info("HeadlessDictation: Parakeet is loading/warming (state=\(state), warmed=\(isWarmed)), waiting...")
                let ready = await parakeetManager.waitForReady(timeout: 8.0)
                if ready {
                    AppLogger.app.info("HeadlessDictation: Parakeet became ready")
                } else {
                    AppLogger.app.info("HeadlessDictation: Parakeet wait timed out, will fall back to Apple Speech")
                }
            }

            // Check for cancellation before starting transcription
            guard !Task.isCancelled else {
                AppLogger.app.info("HeadlessDictation: Transcription cancelled before start")
                try? FileManager.default.removeItem(at: url)
                return
            }

            // Now transcribe - TranscriptionService will use Parakeet if ready, else Apple Speech
            TranscriptionService.shared.transcribe(audioURL: url, useCase: .keyboard) { [weak self] result in
                DispatchQueue.main.async {
                    // If cancelled while transcription was in flight, discard result
                    guard !(self?.transcriptionTask?.isCancelled ?? true) else {
                        AppLogger.app.info("HeadlessDictation: Transcription result discarded — cancelled")
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    self?.transcriptionTask = nil
                    self?.handleTranscriptionResult(result, audioURL: url, sessionId: sessionId)
                }
            }
        }
    }

    private func handleTranscriptionResult(_ result: Result<String, Error>, audioURL: URL, sessionId: UUID?) {
        switch result {
        case .success(let text):
            AppLogger.app.info("HeadlessDictation: Transcription success - \(text.count) chars")
            logSharedState("transcriptionSuccess", detail: "session=\(sessionId?.uuidString ?? "nil") chars=\(text.count)")

            // Check if we should delay result delivery to give keyboard time to regain focus
            // When we return from the Talkie app, the keyboard needs a moment to be ready
            let shouldDelay: Bool = {
                // If this was a warm segment recording, keyboard never left - no delay needed
                if warmSegmentStartTime != nil || warmSegmentEndTime != nil {
                    AppLogger.app.info("HeadlessDictation: Warm segment (continuous mode) - keyboard already focused, no delay")
                    return false
                }
                
                // Regular recording means we switched to the app and back
                // Keyboard needs time to regain focus on the text field
                AppLogger.app.info("HeadlessDictation: Regular recording (switched apps) - adding 150ms delay for keyboard focus")
                return true
            }()
            
            let deliverResult = { [weak self] in
                guard let self = self else { return }
                
                // Store result for keyboard (via App Group)
                if let sessionId {
                    self.sharedStore.appSetResult(text: text, sessionId: sessionId, durationSeconds: nil)
                }
                self.sharedStore.appClearCommand()
                let dictationResult = DictationResult(text: text)
                self.bridge.setDictationResult(dictationResult)
                self.bridge.setLastDictationCompletedAt()

                // Save to dictation history
                KeyboardDictationStore.shared.add(text: text, durationSeconds: nil, appContext: "Keyboard")

                // Try to copy to clipboard as backup (may fail when backgrounded)
                if UIApplication.shared.applicationState == .active {
                    UIPasteboard.general.string = text
                }

                // Mark as returned - we can't actually return to arbitrary host apps
                // The keyboard extension will read the result via App Group
                self.didReturnToSource = true
                // Only clear session if no new recording has started
                if !self.isRecording {
                    self.currentSessionId = nil
                }
            }
            
            if shouldDelay {
                // Give keyboard 150ms to regain focus on text field after app switch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    deliverResult()
                }
            } else {
                // Immediate delivery for continuous mode
                deliverResult()
            }

        case .failure(let error):
            AppLogger.app.error("HeadlessDictation: Transcription failed: \(error)")
            logSharedState("transcriptionFailure", detail: "session=\(sessionId?.uuidString ?? "nil") error=\(error.localizedDescription)")

            let message: String
            if error.localizedDescription.lowercased().contains("no speech") {
                message = "No speech detected"
            } else {
                message = "Transcription failed"
            }
            sharedStore.appSetError(
                message: message,
                sessionId: sessionId,
                code: "transcription_failed",
                recoverable: true,
                retryAfter: nil
            )
            sharedStore.appClearCommand()
            bridge.setRecordingInProgress(false)
            bridge.clearStopRequest()
            // Only clear session if no new recording has started
            if !isRecording {
                currentSessionId = nil
            }

            // Try to return via error callback
            DeepLinkManager.shared.callErrorCallback(message: message)
            didReturnToSource = true
        }

        // Clean up audio file
        try? FileManager.default.removeItem(at: audioURL)

        // Only reset recording state if no new recording has started in the meantime.
        // A warm-segment transcription can complete while the next segment is already recording.
        let newRecordingInProgress = isRecording
        if !newRecordingInProgress {
            recordingURL = nil

            // Re-enter ready mode for next recording
            // NOTE: Do NOT deactivate audio session here - keep it alive for continuous dictation
            // iOS won't let us reactivate from background, so we need to keep the session hot
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.reenterReadyMode()
            }
        }

        endBackgroundTask()
    }

    private func cancelRecording() {
        stopPollTimer?.invalidate()
        stopPollTimer = nil

        audioRecorder?.stop()
        isRecording = false
        bridge.setRecordingInProgress(false)
        if let sessionId = currentSessionId {
            sharedStore.appSetPhase(.idle, sessionId: sessionId)
        }
        sharedStore.appClearCommand()

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        currentSessionId = nil

        endBackgroundTask()
    }

    private func reenterReadyMode() {
        AppLogger.app.info("HeadlessDictation: Re-entering ready mode")
        enterReadyMode()
    }

    private func scheduleReadyModeAfterCooldown() {
        let delay = failureCooldown
        AppLogger.app.info("HeadlessDictation: Cooling down for \(Int(delay))s before ready mode")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reenterReadyMode()
        }
    }

    private func scheduleReadyRetry() {
        guard readyRetryCount < maxReadyRetries else { return }
        readyRetryCount += 1
        let delay: TimeInterval = 0.6
        AppLogger.app.info("HeadlessDictation: Retrying ready mode (\(readyRetryCount)/\(maxReadyRetries))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.enterReadyMode()
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            AppLogger.app.info("HeadlessDictation: Audio session deactivated")
        } catch {
            AppLogger.app.error("HeadlessDictation: Failed to deactivate audio session: \(error)")
        }
    }

    private func attemptForegroundRecovery(reason: String) {
        let appState = UIApplication.shared.applicationState
        guard appState != .active else { return }
        AppLogger.app.warning("HeadlessDictation: Foreground recovery requested (\(reason))")
        pendingForegroundStart = true
        DispatchQueue.main.async {
            UIApplication.shared.open(URL(string: "talkie://dictate")!)
        }
    }

    // MARK: - Warm Recorder (Mic Reserved)

    /// Start a warm recorder for instant dictation
    /// - Parameter reuseExistingSession: If true, don't reconfigure audio session (use when session is already active)
    private func startWarmRecorder(reuseExistingSession: Bool = false) -> Bool {
        guard warmRecorder == nil else { return true }

        // Ensure audio session is active (skip if reusing existing session from background)
        if !reuseExistingSession {
            guard configureAudioSession() else { return false }
        }

        let filename = "warm-\(UUID().uuidString).m4a"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        warmRecordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            guard recorder.prepareToRecord() else { return false }
            guard recorder.record() else { return false }

            warmRecorder = recorder
            warmRecordingStartTime = recorder.currentTime
            warmSegmentStartTime = nil
            warmSegmentEndTime = nil
            sharedStore.setCapability(.warm)
            AppLogger.app.info("HeadlessDictation: Warm recorder started")
            return true
        } catch {
            AppLogger.app.error("HeadlessDictation: Failed to start warm recorder: \(error)")
            warmRecorder = nil
            warmRecordingURL = nil
            return false
        }
    }

    private func stopWarmRecorder(setCapability: DictationSharedState.Capability? = nil) {
        warmRecorder?.stop()
        warmRecorder = nil
        warmRecordingStartTime = nil
        warmSegmentStartTime = nil
        warmSegmentEndTime = nil
        if let url = warmRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        warmRecordingURL = nil
        deactivateAudioSession()
        if let setCapability {
            sharedStore.setCapability(setCapability)
        }
        AppLogger.app.info("HeadlessDictation: Warm recorder stopped")
    }

    private func beginWarmSegment(sessionId: UUID) {
        guard !isRecording else { return }
        guard let recorder = warmRecorder else { return }
        // Warm up Parakeet in parallel with recording
        Task { @MainActor in
            let state = ParakeetModelManager.shared.state
            AppLogger.app.info("HeadlessDictation: Preheating Parakeet for warm segment (current state: \(state))")
            ParakeetModelManager.shared.preheatForKeyboard()
        }
        warmSegmentStartTime = recorder.currentTime
        isRecording = true
        isInReadyMode = true  // Service is actively handling keyboard dictation
        lastRecordingFailure = nil
        currentSessionId = sessionId
        if !acknowledgeStartCommandIfPresent(sessionId: sessionId, phase: .recording, context: "beginWarmSegment") {
            sharedStore.appSetPhase(.recording, sessionId: sessionId)
        }
        finalizeStartCommandIfPresent(sessionId: sessionId, context: "beginWarmSegment")
        // NOTE: Don't set appReady=false during warm segment recording
        // The warm recorder is still running, so keep LED green for continuous mode
        // The keyboard knows we're recording via shared store (RECORDING phase)
        bridge.setRecordingInProgress(true)
        bridge.setAppReady(true)  // Signal app is ready for keyboard commands
        returnToSourceAppIfPossible()
        AppLogger.app.info("HeadlessDictation: Warm segment started at \(recorder.currentTime)")
    }

    private func endWarmSegmentAndTranscribe() {
        guard let recorder = warmRecorder,
              let startTime = warmSegmentStartTime,
              let url = warmRecordingURL else {
            sharedStore.appSetError(
                message: "Recording failed",
                sessionId: currentSessionId,
                code: "warm_missing",
                recoverable: true,
                retryAfter: failureCooldown
            )
            reenterReadyMode()
            return
        }

        warmSegmentEndTime = recorder.currentTime
        let endTime = warmSegmentEndTime ?? recorder.currentTime

        stopPollTimer?.invalidate()
        stopPollTimer = nil

        // Save the URL before stopping - we'll need it for export
        let recordedURL = url

        recorder.stop()
        warmRecorder = nil
        warmRecordingURL = nil  // Clear so startWarmRecorder creates a new file

        isRecording = false
        bridge.setRecordingInProgress(false)
        if let sessionId = currentSessionId {
            sharedStore.appSetPhase(.transcribing, sessionId: sessionId)
        }

        // CRITICAL: Start a new warm recorder IMMEDIATELY - reuse existing audio session
        // The audio session is already active from the previous recording, so don't reconfigure
        // (reconfiguring from background will fail with '!int' error)
        // This enables continuous dictation without app switching
        if startWarmRecorder(reuseExistingSession: true) {
            AppLogger.app.info("HeadlessDictation: New warm recorder started for continuous dictation")
            isInReadyMode = true
            bridge.setAppReady(true)
            startReadyPolling()
        } else {
            AppLogger.app.warning("HeadlessDictation: Failed to start new warm recorder - will require app switch for next recording")
        }

        guard endTime > startTime else {
            AppLogger.app.error("HeadlessDictation: Invalid segment time range")
            sharedStore.appSetError(
                message: "Recording failed",
                sessionId: currentSessionId,
                code: "segment_range",
                recoverable: true,
                retryAfter: failureCooldown
            )
            reenterReadyMode()
            return
        }

        let asset = AVURLAsset(url: recordedURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            sharedStore.appSetError(
                message: "Recording failed",
                sessionId: currentSessionId,
                code: "export_session",
                recoverable: true,
                retryAfter: failureCooldown
            )
            reenterReadyMode()
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("segment-\(UUID().uuidString).m4a")
        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let duration = CMTime(seconds: endTime - startTime, preferredTimescale: 600)
        exporter.timeRange = CMTimeRange(start: start, duration: duration)

        // Capture session ID NOW — a new recording may start before transcription completes
        let sessionId = currentSessionId

        // Export on background thread (original threading model), then hop to MainActor
        // for Parakeet wait + transcription. The inner Task is stored for cancellation.
        Task {
            do {
                try await exporter.export(to: outputURL, as: .m4a)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    // Store inner task so handleCancelCommand can cancel it
                    self.transcriptionTask = Task { @MainActor [weak self] in
                        guard let self else { return }

                        let parakeetManager = ParakeetModelManager.shared
                        let state = parakeetManager.state
                        let isWarmed = parakeetManager.isWarmedUp

                        // If Parakeet is loading or warming up, wait for it (but not too long)
                        if state == .loading || (state == .ready && !isWarmed) {
                            AppLogger.app.info("HeadlessDictation: Parakeet is loading/warming (state=\(state), warmed=\(isWarmed)), waiting...")
                            let ready = await parakeetManager.waitForReady(timeout: 8.0)
                            if ready {
                                AppLogger.app.info("HeadlessDictation: Parakeet became ready")
                            } else {
                                AppLogger.app.info("HeadlessDictation: Parakeet wait timed out, will fall back to Apple Speech")
                            }
                        }

                        // Check for cancellation before starting transcription
                        guard !Task.isCancelled else {
                            AppLogger.app.info("HeadlessDictation: Warm segment transcription cancelled")
                            try? FileManager.default.removeItem(at: outputURL)
                            return
                        }

                        // Now transcribe - TranscriptionService will use Parakeet if ready, else Apple Speech
                        TranscriptionService.shared.transcribe(audioURL: outputURL, useCase: .keyboard) { [weak self] result in
                            DispatchQueue.main.async {
                                // If cancelled while transcription was in flight, discard result
                                guard let self, !(self.transcriptionTask?.isCancelled ?? true) else {
                                    AppLogger.app.info("HeadlessDictation: Warm segment result discarded — cancelled")
                                    try? FileManager.default.removeItem(at: outputURL)
                                    return
                                }
                                self.transcriptionTask = nil
                                self.handleTranscriptionResult(result, audioURL: outputURL, sessionId: sessionId)
                            }
                        }
                    }
                    // Clean up the old recording file (not the new warm recorder's file)
                    try? FileManager.default.removeItem(at: recordedURL)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    AppLogger.app.error("HeadlessDictation: Export failed: \(error.localizedDescription)")
                    self.sharedStore.appSetError(
                        message: "Recording failed",
                        sessionId: sessionId,
                        code: "export_failed",
                        recoverable: true,
                        retryAfter: self.failureCooldown
                    )
                    // NOTE: Do NOT deactivate audio session - keep it alive for continuous dictation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.reenterReadyMode()
                    }
                    // Clean up the old recording file
                    try? FileManager.default.removeItem(at: recordedURL)
                }
            }
        }
    }

    // MARK: - Permissions

    private func ensurePermissions(completion: @escaping (Bool) -> Void) {
        if permissionRequestInFlight {
            completion(false)
            return
        }

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioApplication.shared.recordPermission

        if speechStatus == .authorized && micStatus == .granted {
            completion(true)
            return
        }

        permissionRequestInFlight = true

        if speechStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
                DispatchQueue.main.async {
                    if authStatus == .authorized {
                        self?.checkMicPermission(completion: completion)
                    } else {
                        self?.permissionRequestInFlight = false
                        completion(false)
                    }
                }
            }
            return
        }

        if speechStatus == .authorized {
            checkMicPermission(completion: completion)
            return
        }

        permissionRequestInFlight = false
        completion(false)
    }

    private func checkMicPermission(completion: @escaping (Bool) -> Void) {
        let micStatus = AVAudioApplication.shared.recordPermission
        if micStatus == .granted {
            permissionRequestInFlight = false
            completion(true)
        } else if micStatus == .undetermined {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionRequestInFlight = false
                    completion(granted)
                }
            }
        } else {
            permissionRequestInFlight = false
            completion(false)
        }
    }

    // MARK: - Background Task

    private func startBackgroundTask() {
        guard backgroundTask == .invalid else { return }

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "HeadlessDictation") { [weak self] in
            AppLogger.app.warning("HeadlessDictation: Background task expiring")
            self?.playExpirationWarning()
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Play audio + haptic warning when background task is about to expire
    private func playExpirationWarning() {
        // Play alert sound (also triggers vibration on devices that support it)
        AudioServicesPlayAlertSound(SystemSoundID(1521)) // Tri-tone alert

        // Also play a secondary beep after short delay for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AudioServicesPlayAlertSound(SystemSoundID(1521))
        }

        // Post notification for any UI that wants to show visual feedback
        NotificationCenter.default.post(
            name: .backgroundTaskExpiring,
            object: nil,
            userInfo: ["service": "HeadlessDictation"]
        )

        AppLogger.app.warning("HeadlessDictation: Audio warning played for background task expiration")
    }

    // MARK: - Return to Source App

    /// Try to return to the source app once recording is live
    private func returnToSourceAppIfPossible() {
        guard !didReturnToSource else { return }
        if DeepLinkManager.shared.returnToSourceBestEffort() {
            didReturnToSource = true
            AppLogger.app.info("HeadlessDictation: Returned to source app after recording start")
        } else {
            didReturnToSource = true
            AppLogger.app.info("HeadlessDictation: No callback URL - user should tap Back in status bar")
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension HeadlessDictationService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            AppLogger.app.error("HeadlessDictation: Recording finished unsuccessfully")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            AppLogger.app.error("HeadlessDictation: Encode error: \(error)")
        }
    }
}
