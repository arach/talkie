//
//  ScreenRecordingController.swift
//  TalkieAgent
//
//  Orchestrator for screen video recording.
//  Flow: Hyper+R → chord HUD → select target → record → stop pill → tray.
//  Coordinates ScreenRecordingService and Agent-owned live tray storage.
//

import AppKit
import Foundation
import ScreenCaptureKit
import SwiftUI
import TalkieKit

private let log = Log(.system)

@MainActor
@Observable
final class ScreenRecordingController {
    static let shared = ScreenRecordingController()

    // MARK: - State

    enum State: Equatable {
        case idle
        case selecting       // User is picking region/window
        case recording       // Actively recording
    }

    enum ReusableRecordingResult: Equatable {
        case started
        case needsSelection
        case needsSelectionInMode(CaptureBarMode)
        case cancelled
    }

    private(set) var state: State = .idle
    private(set) var recordingStartTime: Date?

    @ObservationIgnored
    private var metadataSampleTask: Task<Void, Never>?
    @ObservationIgnored
    private var metadataEvents: [RecordingVisualContextEvent] = []
    @ObservationIgnored
    private var activeWindowEventIndex: Int?
    @ObservationIgnored
    private var activeOverlayController: ScreenRecordingActiveOverlayController?
    @ObservationIgnored
    private var cameraBubbleShownForRecording = false

    private init() {}

    // MARK: - Start Recording (from chord result)

    /// Start a screen recording with the given capture mode.
    /// Handles target selection, recording start, and pill display.
    func startRecording(mode: CaptureMode) async {
        guard state == .idle else {
            log.warning("Cannot start screen recording — state: \(String(describing: state))")
            return
        }

        state = .selecting

        let service = ScreenRecordingService.shared

        // Let user select what to record
        guard let target = await service.selectTarget(mode: mode) else {
            log.info("Screen recording target selection cancelled")
            state = .idle
            return
        }

        _ = await startResolvedRecording(target: target, mode: mode)
    }

    /// Start from the last successful target after a cancellable countdown.
    /// Return `.needsSelection` when the caller should show the regular HUD.
    func startReusableRecordingWithCountdown() async -> ReusableRecordingResult {
        guard state == .idle else {
            log.warning("Cannot quick-start screen recording — state: \(String(describing: state))")
            return .cancelled
        }

        let service = ScreenRecordingService.shared
        guard service.hasReusableTarget else {
            return .needsSelection
        }

        state = .selecting
        guard let target = await service.reusableTarget() else {
            state = .idle
            return .needsSelection
        }

        let countdown = ScreenRecordingCountdownController(target: target)
        switch await countdown.begin() {
        case .start(let confirmedTarget):
            let mode = Self.captureMode(for: confirmedTarget)
            let started = await startResolvedRecording(target: confirmedTarget, mode: mode)
            return started ? .started : .needsSelection

        case .selectMode(let mode):
            guard let selectedTarget = await service.selectTarget(mode: mode) else {
                state = .idle
                return .cancelled
            }
            let started = await startResolvedRecording(target: selectedTarget, mode: mode)
            return started ? .started : .needsSelection

        case .selectTarget:
            state = .idle
            return .needsSelection

        case .selectBarMode(let mode):
            state = .idle
            return .needsSelectionInMode(mode)

        case .cancel:
            state = .idle
            return .cancelled
        }
    }

    // MARK: - Stop Recording

    /// Stop the current screen recording and add the clip to the tray.
    func stopRecording() async {
        guard state == .recording else { return }

        // Capture start time before stop clears it
        let startTime = ScreenRecordingService.shared.recordingStartTime ?? recordingStartTime
        stopMetadataSampler()

        guard let result = await ScreenRecordingService.shared.stopRecording() else {
            log.error("Screen recording stop returned no result")
            recordingStartTime = nil
            state = .idle
            NotchOverlayController.shared.deactivateScreenRecording()
            hideActiveOverlay()
            hideCameraBubbleIfNeeded()
            resetMetadataSampler()
            return
        }

        // Calculate duration
        let durationMs: Int
        if let startTime {
            durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        } else {
            durationMs = 0
        }

        let captureMode = Self.captureModeString(for: result.target)
        let clipStartedAt = startTime ?? Date().addingTimeInterval(-Double(durationMs) / 1000.0)
        let metadataEvents = finalizedMetadataEvents(durationMs: durationMs)

        do {
            let stored = try await AgentLiveTrayAssetStore.shared.storeClip(
                tempURL: result.url,
                capturedAt: clipStartedAt,
                durationMs: durationMs,
                width: result.width,
                height: result.height,
                captureMode: captureMode,
                windowTitle: result.target.windowTitle,
                appName: result.target.appName,
                displayName: result.target.displayName,
                metadataEvents: metadataEvents
            )
            AgentCaptureLibraryWriter.persistClip(
                sourceURL: stored.fileURL,
                id: stored.id,
                capturedAt: clipStartedAt,
                durationMs: durationMs,
                captureMode: captureMode,
                width: result.width,
                height: result.height,
                windowTitle: result.target.windowTitle,
                appName: result.target.appName,
                displayName: result.target.displayName,
                metadataEvents: metadataEvents
            )
            log.info("Screen recording stopped, \(durationMs)ms → Agent tray (\(stored.filename))")
        } catch {
            log.error("Screen recording tray write failed: \(error.localizedDescription)")
        }

        recordingStartTime = nil
        state = .idle
        NotchOverlayController.shared.deactivateScreenRecording()
        hideActiveOverlay()
        hideCameraBubbleIfNeeded()
    }

    // MARK: - Toggle (for stop via hotkey)

    /// If recording, stop. Otherwise do nothing (chord handles start).
    func stopIfRecording() async {
        if state == .recording {
            await stopRecording()
        }
    }

    /// Mark a screenshot captured while this screen recording is active.
    /// The raw clip stays untouched; the marker lets visual-context processors
    /// overlay or summarize the user's intentional highlight later.
    func recordScreenshotHighlight(
        capturedAt: Date,
        filename: String,
        captureMode: String,
        width: Int?,
        height: Int?,
        windowTitle: String?,
        appName: String?,
        appBundleID: String?,
        displayName: String?
    ) {
        guard state == .recording,
              let startTime = recordingStartTime,
              capturedAt >= startTime else {
            return
        }

        let timestampMs = max(0, Int(capturedAt.timeIntervalSince(startTime) * 1000))
        metadataEvents.append(RecordingVisualContextEvent(
            startMs: timestampMs,
            endMs: timestampMs,
            type: .screenshot,
            appName: appName,
            appBundleID: appBundleID,
            windowTitle: windowTitle,
            displayName: displayName,
            captureMode: captureMode,
            assetKind: "screenshot",
            assetFilename: filename,
            width: width,
            height: height
        ))
        log.info("Screen recording screenshot marker added at \(timestampMs)ms: \(filename)")
    }

    private func startResolvedRecording(
        target: ScreenRecordingTarget,
        mode: CaptureMode
    ) async -> Bool {
        guard state == .idle || state == .selecting else {
            log.warning("Cannot start screen recording — state: \(String(describing: state))")
            return false
        }

        state = .selecting
        showCameraBubbleIfNeeded()
        let started = await ScreenRecordingService.shared.startRecording(target: target)
        guard started else {
            log.error("Screen recording failed to start")
            state = .idle
            NotchOverlayController.shared.deactivateScreenRecording()
            hideActiveOverlay()
            hideCameraBubbleIfNeeded()
            resetMetadataSampler()
            return false
        }

        let startTime = ScreenRecordingService.shared.recordingStartTime ?? Date()
        recordingStartTime = startTime
        state = .recording
        NotchOverlayController.shared.activateScreenRecording(startedAt: startTime)
        startMetadataSampler(for: target, captureMode: Self.captureModeString(for: target), startedAt: startTime)
        showActiveOverlay(for: target, startedAt: startTime)
        log.info("Screen recording in progress (mode: \(mode.rawValue))")
        return true
    }

    private func showCameraBubbleIfNeeded() {
        cameraBubbleShownForRecording = false
        guard TalkieSharedSettings.object(forKey: AgentSettingsKey.screenRecordingShowsCameraBubble) as? Bool == true else {
            return
        }
        cameraBubbleShownForRecording = AgentCameraBubbleController.shared.showForScreenRecording()
    }

    private func hideCameraBubbleIfNeeded() {
        guard cameraBubbleShownForRecording else { return }
        AgentCameraBubbleController.shared.hide()
        cameraBubbleShownForRecording = false
    }

    private func showActiveOverlay(for target: ScreenRecordingTarget, startedAt: Date) {
        hideActiveOverlay()
        let overlay = ScreenRecordingActiveOverlayController(target: target, startedAt: startedAt)
        overlay.show()
        activeOverlayController = overlay
    }

    private func hideActiveOverlay() {
        activeOverlayController?.dismiss()
        activeOverlayController = nil
    }

    // MARK: - Metadata Sampling

    private static func captureMode(for target: ScreenRecordingTarget) -> CaptureMode {
        switch target.kind {
        case .fullscreen: return .fullscreen
        case .region: return .region
        case .window: return .window
        }
    }

    private static func captureModeString(for target: ScreenRecordingTarget) -> String {
        switch target.kind {
        case .fullscreen: return "fullscreen"
        case .region: return "region"
        case .window: return "window"
        }
    }

    private func startMetadataSampler(
        for target: ScreenRecordingTarget,
        captureMode: String,
        startedAt: Date
    ) {
        resetMetadataSampler()
        metadataEvents.append(captureTargetEvent(for: target, captureMode: captureMode))
        sampleActiveWindow(startedAt: startedAt)

        metadataSampleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.sampleActiveWindow(startedAt: startedAt)
            }
        }
    }

    private func stopMetadataSampler() {
        metadataSampleTask?.cancel()
        metadataSampleTask = nil
    }

    private func resetMetadataSampler() {
        stopMetadataSampler()
        metadataEvents = []
        activeWindowEventIndex = nil
    }

    private func finalizedMetadataEvents(durationMs: Int) -> [RecordingVisualContextEvent] {
        let finalDuration = max(0, durationMs)
        if let index = activeWindowEventIndex, metadataEvents.indices.contains(index) {
            metadataEvents[index].endMs = metadataEvents[index].endMs ?? finalDuration
        }

        for index in metadataEvents.indices where metadataEvents[index].endMs == nil {
            metadataEvents[index].endMs = finalDuration
        }

        let events = metadataEvents
        resetMetadataSampler()
        return events
    }

    private func sampleActiveWindow(startedAt: Date) {
        let metadata = ContextCaptureService.shared.captureBaseline()
        guard metadata.activeAppBundleID != nil
            || metadata.activeAppName != nil
            || metadata.activeWindowTitle != nil else {
            return
        }

        let timestampMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        if let index = activeWindowEventIndex,
           metadataEvents.indices.contains(index),
           sameActiveWindow(metadataEvents[index], metadata) {
            return
        }

        if let index = activeWindowEventIndex, metadataEvents.indices.contains(index) {
            metadataEvents[index].endMs = timestampMs
        }

        metadataEvents.append(RecordingVisualContextEvent(
            startMs: timestampMs,
            type: .activeWindow,
            appName: metadata.activeAppName,
            appBundleID: metadata.activeAppBundleID,
            windowTitle: metadata.activeWindowTitle
        ))
        activeWindowEventIndex = metadataEvents.indices.last
    }

    private func sameActiveWindow(
        _ event: RecordingVisualContextEvent,
        _ metadata: DictationMetadata
    ) -> Bool {
        event.type == .activeWindow
            && event.appBundleID == metadata.activeAppBundleID
            && event.appName == metadata.activeAppName
            && event.windowTitle == metadata.activeWindowTitle
    }

    private func captureTargetEvent(
        for target: ScreenRecordingTarget,
        captureMode: String
    ) -> RecordingVisualContextEvent {
        switch target.kind {
        case .fullscreen(let display):
            return RecordingVisualContextEvent(
                startMs: 0,
                type: .captureTarget,
                displayName: target.displayName,
                displayID: display.displayID,
                captureMode: captureMode,
                bounds: RecordingVisualContextRect(display.frame)
            )

        case .region(let display, let rect):
            return RecordingVisualContextEvent(
                startMs: 0,
                type: .captureTarget,
                displayName: target.displayName,
                displayID: display.displayID,
                captureMode: captureMode,
                bounds: RecordingVisualContextRect(rect)
            )

        case .window(let window):
            return RecordingVisualContextEvent(
                startMs: 0,
                type: .captureTarget,
                appName: target.appName,
                windowTitle: target.windowTitle,
                displayName: target.displayName,
                captureMode: captureMode,
                bounds: RecordingVisualContextRect(window.frame)
            )
        }
    }
}

// MARK: - Reusable Target Confirmation

@MainActor
private final class ScreenRecordingCountdownController {
    enum Result {
        case start(ScreenRecordingTarget)
        case selectMode(CaptureMode)
        case selectBarMode(CaptureBarMode)
        case selectTarget
        case cancel
    }

    private let target: ScreenRecordingTarget
    private var panel: ScreenRecordingConfirmationPanel?
    private let hudPanel = CaptureHUDPanel()
    private var overlayView: ScreenRecordingCountdownView?
    private var countdownTask: Task<Void, Never>?
    private var targetResolutionTask: Task<Void, Never>?
    private var paletteTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<Result, Never>?
    private var didFinish = false

    init(target: ScreenRecordingTarget) {
        self.target = target
    }

    func begin(seconds: Int = 3) async -> Result {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(seconds: seconds)
        }
    }

    private func show(seconds: Int) {
        let targetRect = Self.screenRect(for: target)
        guard let screen = Self.screen(for: targetRect) ?? NSScreen.main ?? NSScreen.screens.first else {
            finish(.selectTarget)
            return
        }

        let view = ScreenRecordingCountdownView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screenFrame: screen.frame,
            targetRect: targetRect,
            isFullscreen: Self.isFullscreen(target),
            isRegion: Self.isRegion(target),
            captureMode: Self.captureModeLabel(for: target),
            countdown: seconds
        )
        view.onConfirm = { [weak self] rect, adjusted in
            self?.confirm(screenRect: rect, adjusted: adjusted, seconds: seconds)
        }
        view.onModeSelected = { [weak self] mode in
            self?.handleModeSelection(mode)
        }
        view.onBarModeSelected = { [weak self] mode in
            self?.handleBarModeSelection(mode)
        }
        view.onCancel = { [weak self] in
            self?.finish(.cancel)
        }

        let panel = ScreenRecordingConfirmationPanel(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.setFrameOrigin(screen.frame.origin)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(view)

        self.panel = panel
        self.overlayView = view

        showHUD(for: target)
    }

    private func showHUD(for target: ScreenRecordingTarget) {
        let expectedFrame = CaptureHUDPanel.expectedFrame(
            for: NSEvent.mouseLocation,
            position: Self.captureHUDPosition
        )

        hudPanel.show(
            mode: .video,
            showCameraOption: false,
            showTrayOption: false,
            showSelectionOption: false,
            trayCount: 0,
            palette: WallpaperLuminanceSampler.fallbackPalette()
        )
        hudPanel.state.selectedCaptureMode = Self.captureMode(for: target)
        hudPanel.state.onAction = { [weak self] result in
            guard let self else { return }
            guard let result else {
                handleBarModeSelection(hudPanel.state.mode)
                return
            }
            switch result {
            case .screenRecord(let mode):
                handleModeSelection(mode)
            default:
                break
            }
        }

        paletteTask = Task { @MainActor [weak self] in
            let palette = await WallpaperLuminanceSampler.samplePalette(for: expectedFrame)
            guard !Task.isCancelled else { return }
            self?.hudPanel.updatePalette(palette)
        }
    }


    private static var captureHUDPosition: CaptureHUDPosition {
        guard let raw = UserDefaults.standard.string(forKey: "captureHUDPosition"),
              let position = CaptureHUDPosition(rawValue: raw) else {
            return .fixed
        }
        return position
    }

    private func handleBarModeSelection(_ mode: CaptureBarMode) {
        guard !didFinish else { return }
        hudPanel.state.mode = mode
        guard mode != .video else {
            overlayView?.focusSelection()
            return
        }
        finish(.selectBarMode(mode))
    }

    private static func captureMode(for target: ScreenRecordingTarget) -> CaptureMode {
        switch target.kind {
        case .fullscreen: return .fullscreen
        case .region: return .region
        case .window: return .window
        }
    }

    private func handleModeSelection(_ mode: CaptureMode) {
        guard !didFinish else { return }
        hudPanel.state.selectedCaptureMode = mode
        switch mode {
        case .region:
            finish(.selectMode(mode))
        case .fullscreen, .window:
            finish(.selectMode(mode))
        }
    }

    private func confirm(screenRect: CGRect, adjusted: Bool, seconds: Int) {
        guard !didFinish else { return }
        overlayView?.beginCountdown(seconds: seconds)

        targetResolutionTask?.cancel()
        targetResolutionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let resolvedTarget: ScreenRecordingTarget?
            if adjusted, !Self.isFullscreen(target) {
                resolvedTarget = await ScreenRecordingService.shared.regionTarget(
                    for: screenRect,
                    preferredTarget: target
                )
            } else {
                resolvedTarget = target
            }

            guard let resolvedTarget else {
                finish(.selectTarget)
                return
            }

            var remaining = seconds
            while remaining > 0 {
                overlayView?.countdown = remaining
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
            }
            finish(.start(resolvedTarget))
        }
    }

    private func finish(_ result: Result) {
        guard !didFinish else { return }
        didFinish = true

        countdownTask?.cancel()
        countdownTask = nil
        targetResolutionTask?.cancel()
        targetResolutionTask = nil
        paletteTask?.cancel()
        paletteTask = nil
        hudPanel.dismiss()

        panel?.orderOut(nil)
        panel = nil
        overlayView = nil

        continuation?.resume(returning: result)
        continuation = nil
    }

    private static func screenRect(for target: ScreenRecordingTarget) -> CGRect {
        switch target.kind {
        case .fullscreen(let display):
            return display.frame
        case .region(_, let rect):
            return rect
        case .window(let window):
            return window.frame
        }
    }

    private static func isFullscreen(_ target: ScreenRecordingTarget) -> Bool {
        if case .fullscreen = target.kind {
            return true
        }
        return false
    }

    private static func isRegion(_ target: ScreenRecordingTarget) -> Bool {
        if case .region = target.kind {
            return true
        }
        return false
    }

    private static func screen(for targetRect: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, targetRect) < intersectionArea(rhs.frame, targetRect)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func captureModeLabel(for target: ScreenRecordingTarget) -> String {
        switch target.kind {
        case .fullscreen:
            return target.displayName.map { "Screen · \($0)" } ?? "Screen"
        case .region:
            return "Region"
        case .window:
            return [target.appName, target.windowTitle]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
                .nilIfEmpty ?? "Window"
        }
    }
}

private final class ScreenRecordingConfirmationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScreenRecordingActiveOverlayController {
    private let target: ScreenRecordingTarget
    private let startedAt: Date
    private var panel: NSPanel?
    private var stopPanel: NSPanel?
    private var timer: Timer?

    init(target: ScreenRecordingTarget, startedAt: Date) {
        self.target = target
        self.startedAt = startedAt
    }

    func show() {
        let targetRect = Self.screenRect(for: target)
        guard let screen = Self.screen(for: targetRect) ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let view = ScreenRecordingActiveOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screenFrame: screen.frame,
            targetRect: targetRect,
            isFullscreen: Self.isFullscreen(target),
            startedAt: startedAt
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.setFrameOrigin(screen.frame.origin)
        panel.orderFrontRegardless()

        showStopPanel(near: targetRect, on: screen)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak view] _ in
            Task { @MainActor in
                view?.needsDisplay = true
            }
        }
        self.panel = panel
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        stopPanel?.orderOut(nil)
        stopPanel = nil
    }

    private func showStopPanel(near targetRect: CGRect, on screen: NSScreen) {
        let panelSize = CGSize(width: 132, height: 38)
        let visible = screen.visibleFrame
        let x = min(
            max(targetRect.midX - panelSize.width / 2, visible.minX + 12),
            visible.maxX - panelSize.width - 12
        )
        let preferredAboveY = targetRect.maxY + 10
        let y = preferredAboveY + panelSize.height <= visible.maxY
            ? preferredAboveY
            : max(visible.minY + 12, targetRect.minY - panelSize.height - 10)

        let view = ScreenRecordingStopPillView(startedAt: startedAt) {
            Task { @MainActor in
                await ScreenRecordingController.shared.stopRecording()
            }
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.level = .screenSaver + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        panel.orderFrontRegardless()
        stopPanel = panel
    }

    private static func screenRect(for target: ScreenRecordingTarget) -> CGRect {
        switch target.kind {
        case .fullscreen(let display):
            return display.frame
        case .region(_, let rect):
            return rect
        case .window(let window):
            return window.frame
        }
    }

    private static func isFullscreen(_ target: ScreenRecordingTarget) -> Bool {
        if case .fullscreen = target.kind {
            return true
        }
        return false
    }

    private static func screen(for targetRect: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, targetRect) < intersectionArea(rhs.frame, targetRect)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

private struct ScreenRecordingStopPillView: View {
    let startedAt: Date
    let onStop: () -> Void

    @State private var elapsedSeconds = 0

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text(formatTime(elapsedSeconds))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 36, alignment: .leading)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.red.opacity(0.95)))
            }
            .buttonStyle(.plain)
            .help("Stop screen recording")
            .accessibilityLabel("Stop screen recording")
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .task {
            updateElapsed()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                updateElapsed()
            }
        }
    }

    private func updateElapsed() {
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}

private final class ScreenRecordingActiveOverlayView: NSView {
    private let screenFrame: CGRect
    private let targetRect: CGRect
    private let isFullscreen: Bool
    private let startedAt: Date

    init(
        frame: NSRect,
        screenFrame: CGRect,
        targetRect: CGRect,
        isFullscreen: Bool,
        startedAt: Date
    ) {
        self.screenFrame = screenFrame
        self.targetRect = targetRect
        self.isFullscreen = isFullscreen
        self.startedAt = startedAt
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = drawingRect()
        guard rect.width > 1, rect.height > 1 else { return }
        drawTargetFrame(rect)
        drawRecordingBadge(near: rect)
    }

    private func drawingRect() -> CGRect {
        let rawRect = CGRect(
            x: targetRect.origin.x - screenFrame.origin.x,
            y: targetRect.origin.y - screenFrame.origin.y,
            width: targetRect.width,
            height: targetRect.height
        ).intersection(bounds)
        guard !rawRect.isNull else { return .null }

        let edgeInset: CGFloat = isFullscreen ? 0 : 2
        return rawRect
            .intersection(bounds.insetBy(dx: edgeInset, dy: edgeInset))
            .standardized
    }

    private var accent: NSColor {
        NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.34, alpha: 1)
    }

    private func drawTargetFrame(_ rect: CGRect) {
        let hairline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        hairline.lineWidth = 0.75
        accent.withAlphaComponent(0.34).setStroke()
        hairline.stroke()

        drawCornerBrackets(in: rect)
    }

    private func drawCornerBrackets(in rect: CGRect) {
        let bracketWidth: CGFloat = 1.8
        let bracketRect = rect.insetBy(dx: bracketWidth / 2 + 0.5, dy: bracketWidth / 2 + 0.5)
        let minDimension = max(1, min(bracketRect.width, bracketRect.height))
        let length = min(max(20, minDimension * 0.12), 52)
        let topLeft = NSPoint(x: bracketRect.minX, y: bracketRect.maxY)
        let topRight = NSPoint(x: bracketRect.maxX, y: bracketRect.maxY)
        let bottomLeft = NSPoint(x: bracketRect.minX, y: bracketRect.minY)
        let bottomRight = NSPoint(x: bracketRect.maxX, y: bracketRect.minY)
        let bracketColor = accent.withAlphaComponent(0.86)

        strokeCorner(
            from: NSPoint(x: topLeft.x + length, y: topLeft.y),
            through: topLeft,
            to: NSPoint(x: topLeft.x, y: topLeft.y - length),
            width: bracketWidth,
            color: bracketColor
        )
        strokeCorner(
            from: NSPoint(x: topRight.x - length, y: topRight.y),
            through: topRight,
            to: NSPoint(x: topRight.x, y: topRight.y - length),
            width: bracketWidth,
            color: bracketColor
        )
        strokeCorner(
            from: NSPoint(x: bottomLeft.x + length, y: bottomLeft.y),
            through: bottomLeft,
            to: NSPoint(x: bottomLeft.x, y: bottomLeft.y + length),
            width: bracketWidth,
            color: bracketColor
        )
        strokeCorner(
            from: NSPoint(x: bottomRight.x - length, y: bottomRight.y),
            through: bottomRight,
            to: NSPoint(x: bottomRight.x, y: bottomRight.y + length),
            width: bracketWidth,
            color: bracketColor
        )
    }

    private func drawRecordingBadge(near rect: CGRect) {
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        let text = "REC \(elapsed / 60):\(elapsed % 60 < 10 ? "0" : "")\(elapsed % 60)"
        let badgeSize = CGSize(width: 72, height: 24)
        let x = min(max(rect.minX, bounds.minX + 10), bounds.maxX - badgeSize.width - 10)
        let y = rect.maxY + badgeSize.height + 8 < bounds.maxY
            ? rect.maxY + 8
            : rect.minY - badgeSize.height - 8
        let badgeRect = CGRect(
            x: x,
            y: min(max(y, bounds.minY + 10), bounds.maxY - badgeSize.height - 10),
            width: badgeSize.width,
            height: badgeSize.height
        )
        let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 9, yRadius: 9)
        NSColor(white: 0.04, alpha: 0.70).setFill()
        badge.fill()
        accent.withAlphaComponent(0.46).setStroke()
        badge.lineWidth = 0.8
        badge.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.draw(
            with: CGRect(x: badgeRect.minX + 6, y: badgeRect.minY + 5, width: badgeRect.width - 12, height: 14),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                .paragraphStyle: paragraph
            ]
        )
    }

    private func strokeCorner(from start: NSPoint, through corner: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        path.line(to: corner)
        path.line(to: end)
        color.setStroke()
        path.stroke()
    }
}

private final class ScreenRecordingCountdownView: NSView {
    private enum Phase {
        case confirming
        case countingDown
    }

    private enum DragOperation {
        case drawNew
        case move
        case resizeTopLeft
        case resizeBottomRight
    }

    private let screenFrame: CGRect
    private let targetRect: CGRect
    private let isFullscreen: Bool
    private let isRegion: Bool
    private let captureMode: String
    private let minSelectionSize = CGSize(width: 96, height: 72)
    private let edgeInset: CGFloat

    var onConfirm: ((CGRect, Bool) -> Void)?
    var onModeSelected: ((CaptureMode) -> Void)?
    var onBarModeSelected: ((CaptureBarMode) -> Void)?
    var onCancel: (() -> Void)?

    private var phase: Phase = .confirming
    private var selectionRect: CGRect
    private var dragOperation: DragOperation?
    private var dragStartPoint: NSPoint = .zero
    private var dragStartRect: CGRect = .zero
    private var didAdjust = false

    var countdown: Int {
        didSet { needsDisplay = true }
    }

    init(
        frame: NSRect,
        screenFrame: CGRect,
        targetRect: CGRect,
        isFullscreen: Bool,
        isRegion: Bool,
        captureMode: String,
        countdown: Int
    ) {
        self.screenFrame = screenFrame
        self.targetRect = targetRect
        self.isFullscreen = isFullscreen
        self.isRegion = isRegion
        self.captureMode = captureMode
        self.countdown = countdown
        self.edgeInset = isFullscreen ? 0 : 2
        self.selectionRect = Self.initialSelectionRect(
            targetRect: targetRect,
            screenFrame: screenFrame,
            bounds: CGRect(origin: .zero, size: frame.size),
            edgeInset: isFullscreen ? 0 : 2
        )
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = selectionRect.standardized

        guard rect.width > 1, rect.height > 1 else { return }

        drawBackdropHole(around: rect)
        drawTargetFrame(rect)
        switch phase {
        case .confirming:
            drawConfirmation(in: rect)
        case .countingDown:
            drawCountdown(in: rect)
        }
    }

    func beginCountdown(seconds: Int) {
        phase = .countingDown
        countdown = seconds
        needsDisplay = true
    }

    func focusSelection() {
        phase = .confirming
        needsDisplay = true
    }

    private static func initialSelectionRect(
        targetRect: CGRect,
        screenFrame: CGRect,
        bounds: CGRect,
        edgeInset: CGFloat
    ) -> CGRect {
        let rawRect = CGRect(
            x: targetRect.origin.x - screenFrame.origin.x,
            y: targetRect.origin.y - screenFrame.origin.y,
            width: targetRect.width,
            height: targetRect.height
        ).intersection(bounds)
        guard !rawRect.isNull else { return .null }

        return rawRect
            .intersection(bounds.insetBy(dx: edgeInset, dy: edgeInset))
            .standardized
    }

    private func localRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x - screenFrame.origin.x,
            y: rect.origin.y - screenFrame.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    private func screenRect(for localRect: CGRect) -> CGRect {
        CGRect(
            x: localRect.origin.x + screenFrame.origin.x,
            y: localRect.origin.y + screenFrame.origin.y,
            width: localRect.width,
            height: localRect.height
        ).standardized
    }

    private func drawBackdropHole(around rect: CGRect) {
        let backdrop = NSBezierPath(rect: bounds)
        backdrop.append(NSBezierPath(rect: rect))
        backdrop.windingRule = .evenOdd
        let alpha: CGFloat = isFullscreen ? 0.06 : (phase == .confirming ? 0.18 : 0.14)
        NSColor(white: 0, alpha: alpha).setFill()
        backdrop.fill()
    }

    private func drawTargetFrame(_ rect: CGRect) {
        let accent = resolvedAccentColor
        let hairlineRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let hairline = NSBezierPath(rect: hairlineRect)
        hairline.lineWidth = 0.75
        accent.withAlphaComponent(0.38).setStroke()
        hairline.stroke()

        drawCornerBrackets(in: rect, accent: accent)
    }

    private var resolvedAccentColor: NSColor {
        NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.34, alpha: 1)
    }

    private func drawCornerBrackets(in rect: CGRect, accent: NSColor) {
        let bracketWidth: CGFloat = 1.8
        let bracketRect = rect.insetBy(dx: bracketWidth / 2 + 0.5, dy: bracketWidth / 2 + 0.5)
        let minDimension = max(1, min(bracketRect.width, bracketRect.height))
        let length = min(max(20, minDimension * 0.12), 52)

        let topLeft = NSPoint(x: bracketRect.minX, y: bracketRect.maxY)
        let topRight = NSPoint(x: bracketRect.maxX, y: bracketRect.maxY)
        let bottomLeft = NSPoint(x: bracketRect.minX, y: bracketRect.minY)
        let bottomRight = NSPoint(x: bracketRect.maxX, y: bracketRect.minY)
        let bracketColor = accent.withAlphaComponent(0.88)

        strokeCorner(
            from: NSPoint(x: topLeft.x + length, y: topLeft.y),
            through: topLeft,
            to: NSPoint(x: topLeft.x, y: topLeft.y - length),
            width: bracketWidth,
            color: bracketColor
        )
        strokeCorner(
            from: NSPoint(x: topRight.x - length, y: topRight.y),
            through: topRight,
            to: NSPoint(x: topRight.x, y: topRight.y - length),
            width: bracketWidth,
            color: bracketColor
        )
        strokeCorner(
            from: NSPoint(x: bottomLeft.x + length, y: bottomLeft.y),
            through: bottomLeft,
            to: NSPoint(x: bottomLeft.x, y: bottomLeft.y + length),
            width: bracketWidth,
            color: bracketColor
        )
        strokeCorner(
            from: NSPoint(x: bottomRight.x - length, y: bottomRight.y),
            through: bottomRight,
            to: NSPoint(x: bottomRight.x, y: bottomRight.y + length),
            width: bracketWidth,
            color: bracketColor
        )
    }

    private func strokeCorner(from start: NSPoint, through corner: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        path.line(to: corner)
        path.line(to: end)
        color.setStroke()
        path.stroke()
    }

    private func drawConfirmation(in target: CGRect) {
        let label = "\(Int(target.width.rounded())) x \(Int(target.height.rounded()))"
        let badgeSize = CGSize(width: max(104, CGFloat(label.count) * 8 + 44), height: 28)
        let badgeX = min(
            max(target.midX - badgeSize.width / 2, bounds.minX + 10),
            bounds.maxX - badgeSize.width - 10
        )
        let preferAboveY = target.maxY + 10
        let badgeY = preferAboveY + badgeSize.height < bounds.maxY
            ? preferAboveY
            : max(bounds.minY + 10, target.minY - badgeSize.height - 10)
        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeSize.width, height: badgeSize.height)

        let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 10, yRadius: 10)
        NSColor(white: 0.05, alpha: 0.78).setFill()
        badge.fill()
        resolvedAccentColor.withAlphaComponent(0.42).setStroke()
        badge.lineWidth = 0.8
        badge.stroke()

        drawCentered(
            label,
            in: CGRect(x: badgeRect.minX + 10, y: badgeRect.minY + 6, width: badgeRect.width - 34, height: 16),
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            color: .white
        )
        drawCentered(
            "↵",
            in: CGRect(x: badgeRect.maxX - 28, y: badgeRect.minY + 6, width: 18, height: 16),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: resolvedAccentColor.withAlphaComponent(0.92)
        )
    }

    private func drawCountdown(in target: CGRect) {
        let center = NSPoint(x: target.midX, y: target.midY)
        let bubbleSize = CGSize(width: 132, height: 110)
        let bubbleRect = CGRect(
            x: center.x - bubbleSize.width / 2,
            y: center.y - bubbleSize.height / 2,
            width: bubbleSize.width,
            height: bubbleSize.height
        )

        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 20, yRadius: 20)
        NSColor(white: 0.05, alpha: 0.82).setFill()
        bubble.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        bubble.lineWidth = 1
        bubble.stroke()

        drawCentered(
            "\(countdown)",
            in: CGRect(x: bubbleRect.minX, y: bubbleRect.minY + 34, width: bubbleRect.width, height: 52),
            font: .monospacedDigitSystemFont(ofSize: 46, weight: .bold),
            color: .white
        )
        drawCentered(
            captureMode,
            in: CGRect(x: bubbleRect.minX + 8, y: bubbleRect.minY + 18, width: bubbleRect.width - 16, height: 16),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.78)
        )
    }

    private func drawCentered(_ string: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        guard phase == .confirming, !isFullscreen else { return }
        let point = convert(event.locationInWindow, from: nil)
        let operation = dragOperation(at: point) ?? (isRegion ? .drawNew : nil)
        guard let operation else { return }
        dragOperation = operation
        dragStartPoint = point
        dragStartRect = selectionRect
        if case .drawNew = operation {
            setSelection(CGRect(origin: point, size: .zero))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard phase == .confirming, let dragOperation else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: point.x - dragStartPoint.x, height: point.y - dragStartPoint.y)
        updateSelection(operation: dragOperation, delta: delta)
    }

    override func mouseUp(with event: NSEvent) {
        dragOperation = nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard phase == .confirming, !isFullscreen else {
            NSCursor.arrow.set()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        switch dragOperation(at: point) {
        case .drawNew:
            NSCursor.crosshair.set()
        case .move:
            NSCursor.openHand.set()
        case .resizeTopLeft, .resizeBottomRight:
            NSCursor.crosshair.set()
        case nil:
            (isRegion ? NSCursor.crosshair : NSCursor.arrow).set()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        if event.isCaptureModeSwitchArrow {
            onBarModeSelected?(event.keyCode == 123 ? .screenshot : .video)
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 || event.isOpeningCaptureChordKey(initialMode: .video) {
            guard phase == .confirming else { return }
            onConfirm?(screenRect(for: selectionRect), didAdjust)
            return
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            onModeSelected?(.region)
            return
        case "s":
            onModeSelected?(.fullscreen)
            return
        case "d":
            onModeSelected?(.window)
            return
        default:
            break
        }

        guard phase == .confirming, !isFullscreen else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let resizes = event.modifierFlags.contains(.option)

        switch event.keyCode {
        case 123: // left
            resizes ? resizeBy(width: -step, height: 0) : moveBy(dx: -step, dy: 0)
        case 124: // right
            resizes ? resizeBy(width: step, height: 0) : moveBy(dx: step, dy: 0)
        case 125: // down
            resizes ? resizeBy(width: 0, height: -step) : moveBy(dx: 0, dy: -step)
        case 126: // up
            resizes ? resizeBy(width: 0, height: step) : moveBy(dx: 0, dy: step)
        default:
            super.keyDown(with: event)
        }
    }

    private func dragOperation(at point: NSPoint) -> DragOperation? {
        let rect = selectionRect.standardized
        guard rect.insetBy(dx: -12, dy: -12).contains(point) else { return nil }

        let topLeftHandle = CGRect(x: rect.minX - 14, y: rect.maxY - 20, width: 28, height: 34)
        let bottomRightHandle = CGRect(x: rect.maxX - 14, y: rect.minY - 14, width: 28, height: 34)
        if topLeftHandle.contains(point) { return .resizeTopLeft }
        if bottomRightHandle.contains(point) { return .resizeBottomRight }
        if rect.contains(point) { return .move }
        return nil
    }

    private func updateSelection(operation: DragOperation, delta: CGSize) {
        var rect = dragStartRect
        switch operation {
        case .drawNew:
            let end = NSPoint(
                x: dragStartPoint.x + delta.width,
                y: dragStartPoint.y + delta.height
            )
            rect = CGRect(
                x: min(dragStartPoint.x, end.x),
                y: min(dragStartPoint.y, end.y),
                width: abs(delta.width),
                height: abs(delta.height)
            )
        case .move:
            rect.origin.x += delta.width
            rect.origin.y += delta.height
        case .resizeTopLeft:
            rect.origin.x += delta.width
            rect.size.width -= delta.width
            rect.size.height += delta.height
        case .resizeBottomRight:
            rect.origin.y += delta.height
            rect.size.width += delta.width
            rect.size.height -= delta.height
        }
        setSelection(rect)
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        setSelection(selectionRect.offsetBy(dx: dx, dy: dy))
    }

    private func resizeBy(width: CGFloat, height: CGFloat) {
        var rect = selectionRect
        rect.size.width += width
        rect.size.height += height
        setSelection(rect)
    }

    private func setSelection(_ proposedRect: CGRect) {
        let constrained = constrainedSelectionRect(proposedRect)
        guard !constrained.isNull else { return }
        selectionRect = constrained
        didAdjust = true
        needsDisplay = true
    }

    private func constrainedSelectionRect(_ proposedRect: CGRect) -> CGRect {
        var rect = proposedRect.standardized
        let allowed = bounds.insetBy(dx: edgeInset, dy: edgeInset)
        rect.size.width = min(max(rect.width, minSelectionSize.width), allowed.width)
        rect.size.height = min(max(rect.height, minSelectionSize.height), allowed.height)

        if rect.minX < allowed.minX { rect.origin.x = allowed.minX }
        if rect.maxX > allowed.maxX { rect.origin.x = allowed.maxX - rect.width }
        if rect.minY < allowed.minY { rect.origin.y = allowed.minY }
        if rect.maxY > allowed.maxY { rect.origin.y = allowed.maxY - rect.height }
        return rect.standardized
    }
}

private extension NSEvent {
    var isCaptureModeSwitchArrow: Bool {
        guard keyCode == 123 || keyCode == 124 else { return false }
        let synthesizedArrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]
        let activeModifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(synthesizedArrowFlags)
        let hyperModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return activeModifiers.isEmpty || activeModifiers.isSuperset(of: hyperModifiers)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
