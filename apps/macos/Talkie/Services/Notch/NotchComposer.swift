//
//  NotchComposer.swift
//  Talkie
//
//  Coordinator that owns the notch area exclusively.
//  Manages a priority queue of display intents — highest-priority active intent wins.
//  Observes Agent state, tray counts, camera state, and screen recording state.
//

import Foundation
import AppKit
import TalkieKit

private let log = Log(.ui)

@MainActor
@Observable
final class NotchComposer {
    static let shared = NotchComposer()

    // MARK: - State

    /// Currently active intents and their payloads
    private(set) var activeIntents: [NotchDisplayIntent: NotchIntentPayload] = [:]

    /// The resolved intent (highest-priority active intent)
    private(set) var resolvedIntent: NotchDisplayIntent = .idle

    /// The payload for the resolved intent
    private(set) var resolvedPayload: NotchIntentPayload = .idle

    /// High-frequency audio level (0...1), refreshed every poll during recording.
    /// Deliberately kept OUT of `resolvedPayload`: the level changes ~60×/sec, and if
    /// the view read it off the payload, every sample would re-evaluate the whole notch
    /// geometry (custom Shape paths, masks, two `.drawingGroup()` offscreen passes).
    /// Isolating it here means a level tick only invalidates the particle subview.
    private(set) var liveAudioLevel: Float = 0

    /// Whether the composer has been initialized (notch detected)
    private(set) var isActive = false

    /// Whether the tray badge is being hovered (suppresses notch hover expansion)
    var trayBadgeHoverActive = false

    /// Latest rendered content size for the overlay. The hosting panel is larger
    /// than the shell so tray expansions have room, but hit testing should only
    /// use the actual rendered content bounds.
    @ObservationIgnored
    private(set) var interactiveContentSize: CGSize = .zero

    /// Whether the surface is at rest (wings retracted, not hovered).
    /// Used by NotchPanel to decide whether to use hover zone settings.
    @ObservationIgnored
    private(set) var isAtRest: Bool = true

    /// Whether the mouse is inside the interactive hit zone (set by NotchPanel).
    /// The SwiftUI view observes this to drive hover state instead of `.onHover`.
    var mouseInHitZone: Bool = false

    /// Debug: interactive hit rect in panel coordinates (AppKit y-up).
    /// Published so SwiftUI can draw a dotted outline.
    @ObservationIgnored
    private(set) var debugInteractiveRect: CGRect = .zero
    @ObservationIgnored
    private(set) var debugPanelSize: CGSize = .zero

    // MARK: - Panel

    @ObservationIgnored
    private var panel: NotchPanel?

    @ObservationIgnored
    private var notchInfo: NotchInfo?

    // Hot state: memory-mapped file for zero-latency agent state
    @ObservationIgnored
    private var hotStateReader: NotchHotStateReader?

    @ObservationIgnored
    private var hotStatePollTimer: Timer?

    @ObservationIgnored
    private var lastHotStateSequence: UInt32 = 0

    /// Last lifecycle state pushed into `resolvedPayload`. Used so the 60Hz poll only
    /// refreshes the structural payload on real transitions, not on every audio sample.
    @ObservationIgnored
    private var lastPushedLiveState: LiveState?

    @ObservationIgnored
    private var hotStateRetryCount: Int = 0

    @ObservationIgnored
    private var distributedObservers: [NSObjectProtocol] = []

    @ObservationIgnored
    private var lastScreenID: CGDirectDisplayID?

    /// The display ID of the screen the notch is currently on.
    var currentDisplayID: CGDirectDisplayID { notchInfo?.displayID ?? 0 }

    private init() {}

    private var communicationDemoEnabled: Bool { NotchSettings.shared.communicationDemoEnabled }
    private var notchCapabilityEnabled: Bool { NotchSettings.shared.enabled }
    private var notchTrayBarEnabled: Bool { NotchSettings.shared.trayStripEnabled }

    // MARK: - Setup

    /// Initialize the composer. Only activates if feature flag is on and display has a notch.
    /// Safe to call multiple times — skips if already active, or re-attempts if settings changed.
    func setup() {
        guard FeatureFlags.shared.enableNotchComposer else {
            log.info("NotchComposer: feature flag off, staying inactive")
            return
        }

        // Already active — nothing to do
        guard !isActive else { return }

        guard let screen = preferredScreen(startingWith: NSScreen.main) else {
            log.info("NotchComposer: no eligible display for notch overlay")
            return
        }

        let info = NotchInfo.effective(for: screen)
        if info.isVirtual {
            log.info("NotchComposer: no physical notch — using virtual notch")
        }

        notchInfo = info
        isActive = true
        panel = NotchPanel(notchInfo: info, composer: self, startHidden: info.isVirtual)
        log.info("NotchComposer: active (\(info.isVirtual ? "virtual" : "physical") notch \(Int(info.notchWidth))×\(Int(info.notchHeight)))")

        lastScreenID = screenID(for: info.screenFrame)

        observeAgentState()
        observeScreenRecording()
        observeScreenChanges()
        updatePanel()

#if DEBUG
        NotchAnimationInspectorController.shared.showIfEnabled()
#endif
    }

    // MARK: - Intent API

    func activate(_ intent: NotchDisplayIntent, payload: NotchIntentPayload) {
        activeIntents[intent] = payload
        resolve()
    }

    func deactivate(_ intent: NotchDisplayIntent) {
        activeIntents.removeValue(forKey: intent)
        resolve()
    }

    func updatePayload(_ intent: NotchDisplayIntent, payload: NotchIntentPayload) {
        guard activeIntents[intent] != nil else { return }
        activeIntents[intent] = payload
        // Update resolved payload if this is the current winner
        if intent == resolvedIntent {
            resolvedPayload = payload
        }
    }

    // MARK: - Resolution

    private func resolve() {
        // Find highest-priority (lowest rawValue) active intent
        let winner = activeIntents.keys.min() ?? .idle
        let payload = activeIntents[winner] ?? .idle

        let changed = winner != resolvedIntent
        resolvedIntent = winner
        resolvedPayload = payload

        if changed {
            log.debug("NotchComposer: resolved → \(String(describing: winner))")
            updatePanel()
        }
    }

    func captureOverlaySnapshot(metadataLines: [String] = []) {
        panel?.captureOverlaySnapshot(metadataLines: metadataLines)
    }

    func updateInteractiveContentSize(_ size: CGSize) {
        interactiveContentSize = size
    }

    func updateRestState(_ atRest: Bool) {
        isAtRest = atRest
        // Hide the panel when at rest with no active intent to eliminate
        // GPU compositing cost. The global mouse monitor keeps running and
        // NotchPanel will re-show the panel when mouse enters the hover zone.
        if atRest && resolvedIntent == .idle && notchCapabilityEnabled && !NotchSettings.shared.alwaysVisible {
            panel?.hideIfNeeded()
        }
    }

    func updateDebugInteractiveRect(_ rect: CGRect, panelSize: CGSize) {
        debugInteractiveRect = rect
        debugPanelSize = panelSize
    }

    func refreshVisibilityFromSettings() {
        // If the composer never activated (e.g. externalEnabled was off at launch),
        // try setup now — settings may have changed to allow it.
        if !isActive {
            setup()
            return
        }
        updatePanel()
    }

    private func updatePanel() {
        guard notchCapabilityEnabled else {
            panel?.hideIfNeeded()
            return
        }

        if resolvedIntent != .idle {
            moveToActiveScreenIfNeeded()
            // Active intent — panel must be visible.
            panel?.showIfNeeded()
        } else if !isAtRest || NotchSettings.shared.alwaysVisible {
            // Not at rest (hovering/expanding), or user wants permanent visibility.
            panel?.showIfNeeded()
        } else {
            // At rest with no intent — hide the panel to save GPU compositing.
            // The global mouse monitor will re-show it when hover zone is entered.
            panel?.hideIfNeeded()
        }
    }

    // MARK: - Observation: Agent Recording State (Notification + Polling)
    //
    // Idle: DistributedNotification listeners + 4Hz mmap safety net
    // Recording: Notification triggers swap to 60Hz mmap polling for audio levels
    // End: Race — notification OR mmap→idle, whichever arrives first

    private func observeAgentState() {
        let center = DistributedNotificationCenter.default()
        let prefix = "to.talkie.app.agent"

        func observe(_ suffix: String, handler: @escaping () -> Void) {
            let token = center.addObserver(
                forName: .init("\(prefix).\(suffix)"),
                object: nil, queue: .main
            ) { _ in handler() }
            distributedObservers.append(token)
        }

        observe("recording.started") { [weak self] in
            self?.handleRecordingStarted()
        }
        observe("recording.stopped") { [weak self] in
            self?.handleRecordingStopped()
        }
        observe("recording.cancelled") { [weak self] in
            self?.handleRecordingStopped()
        }
        observe("transcribing") { [weak self] in
            self?.handleTranscribing()
        }
        observe("routing") { [weak self] in
            self?.handleRouting()
        }

        // Prepare hot state reader for polling
        let reader = NotchHotStateReader()
        hotStateReader = reader
        if reader.isActive {
            log.info("NotchComposer: hot state ready, starting idle poll")
            startIdlePolling()
        } else {
            log.info("NotchComposer: hot state not ready, retrying in background")
            startHotStateRetry()
        }
    }

    // MARK: - Notification Handlers

    private func handleRecordingStarted() {
        lastPushedLiveState = .listening
        activate(.recording, payload: .recording(state: .listening, audioLevel: 0, elapsedTime: 0))
        swapToRecordingPolling()
    }

    private func handleRecordingStopped() {
        liveAudioLevel = 0
        lastPushedLiveState = nil
        deactivate(.recording)
        swapToIdlePolling()
    }

    private func handleTranscribing() {
        lastPushedLiveState = .transcribing
        activate(.recording, payload: .recording(state: .transcribing, audioLevel: 0, elapsedTime: 0))
        // Keep polling — still want audio visualization during transcription
    }

    private func handleRouting() {
        lastPushedLiveState = .routing
        activate(.recording, payload: .recording(state: .routing, audioLevel: 0, elapsedTime: 0))
    }

    // MARK: - Hot State Polling (4Hz idle / 60Hz recording)

    /// Start 4Hz idle polling — safety net for missed notifications.
    private func startIdlePolling() {
        stopPolling()
        guard let reader = hotStateReader, reader.isActive else { return }

        let timer = Timer(timeInterval: 1.0 / 4.0, repeats: true) { [weak self] _ in
            self?.pollHotState()
        }
        RunLoop.main.add(timer, forMode: .common)
        hotStatePollTimer = timer
    }

    /// Swap to 60Hz polling during recording for smooth audio levels.
    private func swapToRecordingPolling() {
        stopPolling()
        guard let reader = hotStateReader, reader.isActive else { return }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.pollHotState()
        }
        RunLoop.main.add(timer, forMode: .common)
        hotStatePollTimer = timer
    }

    /// Swap back to 4Hz idle polling.
    private func swapToIdlePolling() {
        startIdlePolling()
    }

    private func stopPolling() {
        hotStatePollTimer?.invalidate()
        hotStatePollTimer = nil
        lastHotStateSequence = 0
    }

    private func pollHotState() {
        guard let reader = hotStateReader, reader.isActive else { return }
        let state = reader.read()

        // Skip if nothing changed
        guard state.sequence != lastHotStateSequence else { return }
        lastHotStateSequence = state.sequence

        let liveState = state.liveState
        let isRecordingActive = activeIntents[.recording] != nil

        switch liveState {
        case .listening, .transcribing, .routing, .refining:
            // Audio level is the only thing that changes every frame — update the
            // isolated observable so the particle view animates without dragging the
            // whole notch geometry through a re-render.
            liveAudioLevel = state.audioLevel

            if isRecordingActive {
                // Already recording — refresh the structural payload only on a real
                // lifecycle transition (listening → transcribing → routing …).
                if liveState != lastPushedLiveState {
                    lastPushedLiveState = liveState
                    updatePayload(.recording, payload: .recording(
                        state: liveState,
                        audioLevel: state.audioLevel,
                        elapsedTime: TimeInterval(state.elapsedTime)
                    ))
                }
            } else {
                // Idle poll caught recording start before notification — activate + swap to 60Hz
                lastPushedLiveState = liveState
                activate(.recording, payload: .recording(
                    state: liveState,
                    audioLevel: state.audioLevel,
                    elapsedTime: TimeInterval(state.elapsedTime)
                ))
                swapToRecordingPolling()
            }
        case .idle:
            if isRecordingActive {
                // Mmap says idle before notification — deactivate + swap to 4Hz
                liveAudioLevel = 0
                lastPushedLiveState = nil
                deactivate(.recording)
                swapToIdlePolling()
            }
        }
    }

    /// Retry opening hot state file every 0.5s (Agent may not have started yet)
    private func startHotStateRetry() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.hotStateRetryCount += 1

            if self.hotStateReader?.tryOpen() == true {
                log.info("NotchComposer: hot state available (retry \(self.hotStateRetryCount))")
                timer.invalidate()
                self.startIdlePolling()
            } else if self.hotStateRetryCount > 60 {
                // Give up after ~30s
                log.info("NotchComposer: hot state never appeared, notifications still active")
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Observation: Screen Recording

    private func observeScreenRecording() {
        withObservationTracking {
            let _ = ScreenRecordingController.shared.state
        } onChange: {
            Task { @MainActor in
                self.handleScreenRecordingChange()
                self.observeScreenRecording()
            }
        }
    }

    private func handleScreenRecordingChange() {
        let state = ScreenRecordingController.shared.state

        switch state {
        case .recording:
            let startTime = ScreenRecordingController.shared.recordingStartTime ?? Date()
            activate(.screenRecording, payload: .screenRecording(startTime: startTime))
        case .idle, .selecting:
            deactivate(.screenRecording)
        }
    }

    // MARK: - Screen Change Observation

    /// Reposition the panel when display configuration changes (sleep/wake,
    /// external monitor plugged/unplugged, display arrangement changed).
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenParametersChanged()
            }
        }
    }

    private func handleScreenParametersChanged() {
        guard isActive, let currentInfo = notchInfo else { return }

        // Re-detect for the screen the panel is currently on
        let currentScreen = NSScreen.screens.first(where: {
            screenID(for: $0.frame) == lastScreenID
        })
        let screen = preferredScreen(startingWith: currentScreen) ?? currentScreen ?? NSScreen.main

        guard let screen else { return }

        let info = NotchInfo.effective(for: screen)

        // Only reposition if coordinates actually changed
        guard info.screenFrame != currentInfo.screenFrame
           || info.screenCenter != currentInfo.screenCenter else { return }

        notchInfo = info
        lastScreenID = screenID(for: screen.frame)
        panel?.moveToScreen(info)
        log.info("NotchComposer: repositioned after screen change (\(info.isVirtual ? "virtual" : "physical") notch)")
    }

    // MARK: - Active Screen Tracking

    /// Check if the cursor is on a different screen and move the notch there.
    /// Called continuously from the panel's global mouse monitor.
    @discardableResult
    func moveToActiveScreenIfNeeded() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        let hoveredScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
        guard let screen = preferredScreen(startingWith: hoveredScreen) else { return false }

        let currentID = screenID(for: screen.frame)
        guard currentID != lastScreenID else { return false }
        lastScreenID = currentID

        // Detect notch for the new screen
        let info = NotchInfo.effective(for: screen)

        notchInfo = info
        panel?.moveToScreen(info)
        log.info("NotchComposer: moved to screen \(Int(screen.frame.origin.x)),\(Int(screen.frame.origin.y)) (\(info.isVirtual ? "virtual" : "physical") notch)")
        return true
    }

    /// Move the notch overlay to a specific screen (e.g. the screen showing settings).
    func moveToScreen(_ screen: NSScreen) {
        guard let resolvedScreen = preferredScreen(startingWith: screen) else { return }
        let newID = screenID(for: resolvedScreen.frame)
        guard newID != lastScreenID else { return }
        lastScreenID = newID
        let info = NotchInfo.effective(for: resolvedScreen)
        notchInfo = info
        panel?.moveToScreen(info)
        log.info("NotchComposer: moved to requested screen (\(info.isVirtual ? "virtual" : "physical") notch)")
    }

    private func preferredScreen(startingWith candidate: NSScreen?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let candidate, supportsNotchOverlay(on: candidate) {
            return candidate
        }

        if let builtInNotchScreen = screens.first(where: { NotchInfo.detect(for: $0).hasNotch }) {
            return builtInNotchScreen
        }

        if let builtInScreen = screens.first(where: { isBuiltinDisplay($0) }) {
            return builtInScreen
        }

        if NotchSettings.shared.externalEnabled {
            return candidate ?? NSScreen.main ?? screens.first
        }

        // In clamshell / external-only setups there may be no built-in display
        // to anchor against. Fall back to a virtual surface instead of silently
        // disabling the composer.
        return candidate ?? NSScreen.main ?? screens.first
    }

    private func supportsNotchOverlay(on screen: NSScreen) -> Bool {
        let detected = NotchInfo.detect(for: screen)
        return detected.hasNotch || isBuiltinDisplay(screen) || NotchSettings.shared.externalEnabled
    }

    private func isBuiltinDisplay(_ screen: NSScreen) -> Bool {
        let detected = NotchInfo.detect(for: screen)
        return CGDisplayIsBuiltin(detected.displayID) != 0
    }

    func debugStatusLines() -> [String] {
        let settings = NotchSettings.shared
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main
        let preferred = preferredScreen(startingWith: mainScreen)
        let hotState = hotStateReader?.read()
        let envPath = NotchHotState.filePath()

        var lines: [String] = [
            "environment=\(TalkieEnvironment.current.rawValue)",
            "feature.enableNotchComposer=\(FeatureFlags.shared.enableNotchComposer)",
            "settings.enabled=\(settings.enabled) externalEnabled=\(settings.externalEnabled) alwaysVisible=\(settings.alwaysVisible)",
            "composer.isActive=\(isActive) resolvedIntent=\(resolvedIntent) currentDisplayID=\(currentDisplayID) lastScreenID=\(lastScreenID ?? 0)",
            "hotState.path=\(envPath) readerActive=\(hotStateReader?.isActive == true)"
        ]

        if let hotState {
            lines.append(
                "hotState.phase=\(hotState.phase) liveState=\(hotState.liveState.rawValue) " +
                "audioLevel=\(hotState.audioLevel.formatted(.number.precision(.fractionLength(3)))) " +
                "elapsed=\(hotState.elapsedTime.formatted(.number.precision(.fractionLength(3)))) " +
                "sequence=\(hotState.sequence)"
            )
        } else {
            lines.append("hotState=<unavailable>")
        }

        if let info = notchInfo {
            lines.append(
                "composer.notchInfo displayID=\(info.displayID) hasNotch=\(info.hasNotch) " +
                "isVirtual=\(info.isVirtual) width=\(Int(info.notchWidth)) height=\(Int(info.notchHeight)) " +
                "screenFrame=\(NSStringFromRect(info.screenFrame))"
            )
        } else {
            lines.append("composer.notchInfo=<nil>")
        }

        if let mainScreen {
            lines.append("mainScreen=\(debugDescription(for: mainScreen))")
        } else {
            lines.append("mainScreen=<nil>")
        }

        if let preferred {
            lines.append("preferredScreen=\(debugDescription(for: preferred))")
        } else {
            lines.append("preferredScreen=<nil>")
        }

        lines.append("screenCount=\(screens.count)")
        for (index, screen) in screens.enumerated() {
            lines.append("screen[\(index)]=\(debugDescription(for: screen))")
        }

        return lines
    }

    /// Derive a stable screen identifier from the display at a point.
    private func screenID(for frame: CGRect) -> CGDirectDisplayID {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: frame.midX, y: frame.midY), 16, &displayIDs, &displayCount)
        return displayCount > 0 ? displayIDs[0] : 0
    }

    private func debugDescription(for screen: NSScreen) -> String {
        let detected = NotchInfo.detect(for: screen)
        let effective = NotchInfo.effective(for: screen)
        let isMain = screen == NSScreen.main
        let supportsOverlay = supportsNotchOverlay(on: screen)
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY

        return
            "displayID=\(detected.displayID) main=\(isMain) " +
            "frame=\(NSStringFromRect(screen.frame)) visible=\(NSStringFromRect(screen.visibleFrame)) " +
            "menuBarHeight=\(Int(menuBarHeight)) detected.hasNotch=\(detected.hasNotch) " +
            "detected.width=\(Int(detected.notchWidth)) effective.isVirtual=\(effective.isVirtual) " +
            "effective.width=\(Int(effective.notchWidth)) supportsOverlay=\(supportsOverlay)"
    }
}
