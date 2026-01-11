//
//  SidecarOverlay.swift
//  TalkieLive
//
//  Touch-friendly control panel for iPad Sidecar displays.
//  Shows during recording with Cancel/Done buttons, or idle with Start Recording.
//

import SwiftUI
import TalkieKit
import AppKit
import os

private let log = Logger(subsystem: "jdi.talkie.live", category: "SidecarOverlay")

// MARK: - Touch-Enabled Panel

/// Custom panel that can become key window to receive Sidecar touch events
private class TouchEnabledPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Multi-Touch Container View

/// Container view that detects multi-touch gestures from Sidecar
/// Two-finger tap triggers the primary action (start/stop recording)
private class MultiTouchContainerView: NSView {
    var onMultiTouchTap: (() -> Void)?

    private var activeTouches: Set<NSTouch> = []
    private var twoFingerTapDetected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTouchTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTouchTracking()
    }

    private func setupTouchTracking() {
        allowedTouchTypes = [.indirect, .direct]  // Both trackpad and direct touches
        wantsRestingTouches = true
    }

    // MARK: - Touch Events

    override func touchesBegan(with event: NSEvent) {
        activeTouches = event.touches(matching: .touching, in: self)
        log.debug("[Touch] BEGAN - count: \(self.activeTouches.count)")

        if activeTouches.count >= 2 {
            twoFingerTapDetected = true
            log.info("[Touch] Multi-touch detected: \(self.activeTouches.count) fingers")
        }
    }

    override func touchesMoved(with event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        log.debug("[Touch] MOVED - count: \(touches.count)")
    }

    override func touchesEnded(with event: NSEvent) {
        let endedTouches = event.touches(matching: .ended, in: self)
        activeTouches = event.touches(matching: .touching, in: self)
        log.debug("[Touch] ENDED - ended: \(endedTouches.count), remaining: \(self.activeTouches.count)")

        if twoFingerTapDetected && endedTouches.count >= 2 && activeTouches.isEmpty {
            log.info("[Touch] Two-finger tap completed - triggering action")
            twoFingerTapDetected = false
            onMultiTouchTap?()
        }
    }

    override func touchesCancelled(with event: NSEvent) {
        log.debug("[Touch] CANCELLED")
        activeTouches.removeAll()
        twoFingerTapDetected = false
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        log.debug("[Mouse] DOWN - clicks: \(event.clickCount), pressure: \(event.pressure)")
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        log.debug("[Mouse] UP - clicks: \(event.clickCount)")
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        log.debug("[Mouse] RIGHT DOWN")
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        log.debug("[Mouse] OTHER DOWN - button: \(event.buttonNumber)")
        super.otherMouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // Too noisy, skip logging
        super.mouseMoved(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        log.debug("[Mouse] DRAGGED")
        super.mouseDragged(with: event)
    }

    private var scrollAccumulator: CGFloat = 0
    private var lastScrollTime: Date?

    override func scrollWheel(with event: NSEvent) {
        let deltaY = event.scrollingDeltaY
        log.debug("[Scroll] deltaY: \(deltaY), phase: \(event.phase.rawValue)")

        // Accumulate scroll and trigger on significant movement
        // Reset accumulator if it's been a while since last scroll
        let now = Date()
        if let lastTime = lastScrollTime, now.timeIntervalSince(lastTime) > 0.3 {
            scrollAccumulator = 0
        }
        lastScrollTime = now

        scrollAccumulator += deltaY

        // Trigger on scroll gesture end with significant accumulated scroll
        if event.phase == .ended || event.momentumPhase == .ended {
            if abs(scrollAccumulator) > 20 {
                log.info("[Scroll] Scroll gesture completed (delta: \(self.scrollAccumulator)) - triggering action")
                onMultiTouchTap?()
            }
            scrollAccumulator = 0
        }

        super.scrollWheel(with: event)
    }

    // MARK: - Gesture Events

    override func magnify(with event: NSEvent) {
        log.debug("[Gesture] MAGNIFY - magnitude: \(event.magnification), phase: \(event.phase.rawValue)")

        // Trigger on pinch gesture completion
        // magnitude < 0 = pinch in (zoom out), magnitude > 0 = pinch out (zoom in)
        if event.phase == .ended {
            log.info("[Gesture] Pinch completed (magnitude: \(event.magnification)) - triggering action")
            onMultiTouchTap?()
        }
        super.magnify(with: event)
    }

    override func rotate(with event: NSEvent) {
        log.debug("[Gesture] ROTATE - rotation: \(event.rotation), phase: \(event.phase.rawValue)")
        super.rotate(with: event)
    }

    override func swipe(with event: NSEvent) {
        log.debug("[Gesture] SWIPE - deltaX: \(event.deltaX), deltaY: \(event.deltaY)")
        super.swipe(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        log.debug("[Gesture] SMART MAGNIFY (double-tap)")
        super.smartMagnify(with: event)
    }

    // MARK: - Pressure Events (Force Touch)

    override func pressureChange(with event: NSEvent) {
        log.debug("[Pressure] stage: \(event.stage), pressure: \(event.pressure)")
        super.pressureChange(with: event)
    }

    // MARK: - Tablet Events (Apple Pencil via Sidecar)

    override func tabletPoint(with event: NSEvent) {
        log.debug("[Tablet] POINT - pressure: \(event.pressure), tilt: (\(event.tilt.x), \(event.tilt.y))")
        super.tabletPoint(with: event)
    }

    override func tabletProximity(with event: NSEvent) {
        log.debug("[Tablet] PROXIMITY - entering: \(event.isEnteringProximity)")
        super.tabletProximity(with: event)
    }

    // MARK: - Accept First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        log.debug("[Responder] Became first responder")
        return true
    }
}

// MARK: - Sidecar Overlay Controller

@MainActor
final class SidecarOverlayController: ObservableObject {
    static let shared = SidecarOverlayController()

    private var window: NSWindow?
    private var currentScreen: NSScreen?

    @Published var state: LiveState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var isVisible: Bool = false

    // Control callbacks - set by AppDelegate
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onScratchpad: (() -> Void)?
    var liveController: LiveController?

    private var timer: Timer?
    private var startTime: Date?

    private init() {
        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenChange()
            }
        }
    }

    // MARK: - Public API

    /// Show overlay if a Sidecar (iPad) display is connected
    func showIfSidecarConnected() {
        guard let sidecarScreen = NSScreen.screens.first(where: { $0.isSidecar && $0.isValid }) else {
            log.debug("No Sidecar display detected")
            return
        }

        if currentScreen !== sidecarScreen || window == nil {
            show(on: sidecarScreen)
        }
    }

    func show(on screen: NSScreen) {
        hide()

        currentScreen = screen
        log.info("Showing Sidecar overlay on: \(screen.safeDisplayName)")

        let overlayView = SidecarOverlayView()
        let hostingView = NSHostingView(rootView: overlayView.environmentObject(self))
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 340)

        // Wrap in multi-touch container for Sidecar gesture detection
        let touchContainer = MultiTouchContainerView(frame: hostingView.frame)
        touchContainer.addSubview(hostingView)
        hostingView.autoresizingMask = [.width, .height]

        // Two-finger tap triggers primary action based on state
        touchContainer.onMultiTouchTap = { [weak self] in
            guard let self = self else { return }
            switch self.state {
            case .idle:
                log.info("Multi-touch: Starting recording")
                self.requestStart()
            case .listening:
                log.info("Multi-touch: Stopping recording")
                self.requestStop()
            case .transcribing, .routing:
                log.debug("Multi-touch: Ignored during processing")
            }
        }

        let panel = TouchEnabledPanel(
            contentRect: touchContainer.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = touchContainer
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false  // Must handle touches

        // Position centered on Sidecar screen, slightly above center
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.midY - panelSize.height / 2 + 50  // Slightly above center

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)

        window = panel
        isVisible = true
    }

    func hide() {
        stopTimer()
        window?.orderOut(nil)
        window = nil
        currentScreen = nil
        isVisible = false
    }

    // MARK: - State Management

    func updateState(_ newState: LiveState) {
        let oldState = state
        state = newState

        switch newState {
        case .listening:
            startTimer()
            showIfSidecarConnected()
        case .transcribing, .routing:
            stopTimer()
            // Keep overlay visible during processing
        case .idle:
            stopTimer()
            elapsedTime = 0
            // In idle state, check if Sidecar connected and show Start Recording
            showIfSidecarConnected()
        }

        log.debug("Sidecar state: \(oldState.rawValue) → \(newState.rawValue)")
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        startTime = nil
    }

    // MARK: - Screen Changes

    private func handleScreenChange() {
        // Check if Sidecar was connected or disconnected
        if let sidecarScreen = NSScreen.screens.first(where: { $0.isSidecar && $0.isValid }) {
            // Sidecar connected (or still connected)
            if window == nil || currentScreen !== sidecarScreen {
                show(on: sidecarScreen)
            }
        } else {
            // Sidecar disconnected
            if isVisible {
                log.info("Sidecar disconnected, hiding overlay")
                hide()
            }
        }
    }

    // MARK: - Actions

    func requestStart() {
        log.info("Sidecar: Start recording requested")
        onStart?()
    }

    func requestStop() {
        log.info("Sidecar: Stop requested")
        onStop?()
    }

    func requestCancel() {
        log.info("Sidecar: Cancel requested")
        onCancel?()
    }

    func requestScratchpad() {
        log.info("Sidecar: Scratchpad toggle requested")
        onScratchpad?()
    }
}

// MARK: - Sidecar Overlay View

struct SidecarOverlayView: View {
    @EnvironmentObject var controller: SidecarOverlayController
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            switch controller.state {
            case .listening:
                recordingView
            case .transcribing:
                processingView
            case .routing:
                routingView
            case .idle:
                idleView
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 16) {
            // Visualization area - respects user's overlay style preference
            visualizationView
                .frame(height: 80)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            // Timer
            Text(formatTime(controller.elapsedTime))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            // Action buttons - minimal style
            HStack(spacing: 32) {
                SidecarActionButton(icon: "xmark", label: "Cancel") {
                    controller.requestCancel()
                }

                SidecarActionButton(icon: "checkmark", label: "Done") {
                    controller.requestStop()
                }
            }
            .padding(.top, 8)

            // Gesture hint
            gestureHint(text: "Swipe to stop")
                .padding(.bottom, 20)
        }
        .frame(width: 320)
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 32)

            Text("Ready")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            gestureHint(text: "Swipe to start")
                .padding(.bottom, 24)
        }
        .frame(width: 280)
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 16) {
            ProcessingDotsView(tint: .orange)
                .frame(height: 60)

            Text("Processing")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.orange.opacity(0.8))
        }
        .frame(width: 280, height: 160)
    }

    // MARK: - Routing View

    private var routingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Done")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.green.opacity(0.8))
        }
        .frame(width: 280, height: 160)
    }

    // MARK: - Visualization

    @ViewBuilder
    private var visualizationView: some View {
        switch settings.overlayStyle {
        case .particles:
            WavyParticlesView(calm: false)
        case .particlesCalm:
            WavyParticlesView(calm: true)
        case .waveform:
            WaveformBarsView(sensitive: false)
        case .waveformSensitive:
            WaveformBarsView(sensitive: true)
        case .pillOnly:
            // Fallback to calm particles for pill-only users
            WavyParticlesView(calm: true)
        }
    }

    // MARK: - Gesture Hint

    private func gestureHint(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.35))
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Minimal Action Button

private struct SidecarActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(isPressed ? 0.5 : 0.8))
            .frame(width: 100, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(isPressed ? 0.15 : 0.08))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

