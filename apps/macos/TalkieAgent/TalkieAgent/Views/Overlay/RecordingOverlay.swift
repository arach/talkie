//
//  RecordingOverlay.swift
//  TalkieAgent
//
//  Floating panel that shows during recording
//

import SwiftUI
import TalkieKit
import AppKit
import Combine

private let recordingOverlayProcessingBoxWidth: CGFloat = 34
private let recordingOverlayProcessingBoxHeight: CGFloat = 24
private let recordingOverlayProcessingIslandWidth: CGFloat = 176
private let recordingOverlayProcessingIslandHeight: CGFloat = 32
private let recordingOverlayStopTransitionDuration: Duration = .milliseconds(260)
/// Same window as `recordingOverlayStopTransitionDuration`, in seconds, for the
/// time-driven particle deceleration in the Canvas (TimelineView math wants a Double).
private let recordingOverlayStopTransitionSeconds: TimeInterval = 0.26
private let recordingOverlayFrameInterval: TimeInterval = 1.0 / 30.0
private let recordingOverlayParticleFrameInterval: TimeInterval = 1.0 / 60.0
private let recordingOverlayParticleLevelAttackDuration: TimeInterval = 0.08
private let recordingOverlayParticleLevelReleaseDuration: TimeInterval = 0.28
private let islandOverlayEdgeMargin: CGFloat = 6
private let islandOverlayTopEdgeMargin: CGFloat = 2

// Island surface tone: near-opaque black with a whisper of translucency (so it doesn't
// read as a dead rectangle) plus a soft white rim rather than a stark hairline.
private let islandSurfaceBackground = Color.black.opacity(0.94)
private let islandSurfaceBorder = Color.white.opacity(0.22)

@MainActor
private func recordingOverlayPlacementFrame(for screen: NSScreen) -> CGRect {
    guard LiveSettings.shared.effectiveOverlayStyle == .island else {
        return screen.overlayPlacementFrame()
    }

    let screenFrame = screen.frame
    let minX = screenFrame.minX + islandOverlayEdgeMargin
    let maxX = max(minX, screenFrame.maxX - islandOverlayEdgeMargin)
    let minY = screenFrame.minY + islandOverlayEdgeMargin
    let maxY = max(minY, screenFrame.maxY - islandOverlayTopEdgeMargin)

    return CGRect(
        x: minX,
        y: minY,
        width: max(0, maxX - minX),
        height: max(0, maxY - minY)
    )
}

struct RecordingIndicatorSurfaceModifier: ViewModifier {
    let backgroundFill: Color
    let borderColor: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundFill)
                    .overlay(
                        // Top-lit rim: brighter along the top edge, fading toward the base,
                        // so the pill reads as a lit surface instead of a flat outline.
                        // Stays invisible when borderColor is clear (idle state).
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [borderColor, borderColor.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )
            )
    }
}

extension View {
    func recordingIndicatorSurface(
        backgroundFill: Color,
        borderColor: Color,
        cornerRadius: CGFloat
    ) -> some View {
        modifier(
            RecordingIndicatorSurfaceModifier(
                backgroundFill: backgroundFill,
                borderColor: borderColor,
                cornerRadius: cornerRadius
            )
        )
    }
}

@MainActor
private func persistOverlayPlacement(from frame: CGRect, on screen: NSScreen?) {
    guard let screen else { return }

    let placementBounds = recordingOverlayPlacementFrame(for: screen)
    let minX = placementBounds.minX
    let maxX = max(minX, placementBounds.maxX - frame.width)
    let minY = placementBounds.minY
    let maxY = max(minY, placementBounds.maxY - frame.height)
    let normalizedX: CGFloat
    let normalizedY: CGFloat

    if maxX > minX {
        normalizedX = (frame.minX - minX) / (maxX - minX)
    } else {
        normalizedX = 0.5
    }

    if maxY > minY {
        normalizedY = (maxY - frame.minY) / (maxY - minY)
    } else {
        normalizedY = 0
    }

    let placement = NormalizedPlacement(x: normalizedX, y: normalizedY)
    let current = LiveSettings.shared.overlayPlacement
    guard abs(current.x - placement.x) > 0.002 || abs(current.y - placement.y) > 0.002 else { return }

    LiveSettings.shared.overlayPlacement = placement
}

// MARK: - Overlay Window Controller

@MainActor
final class RecordingOverlayController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = RecordingOverlayController()

    private var window: NSWindow?
    private var settingsCancellables = Set<AnyCancellable>()
    private var moveCommitTask: Task<Void, Never>?

    @Published var state: LiveState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var transcript: String = ""
    @Published var captureIntent: String = "Paste"  // Shows current intent during recording
    @Published var isShowingStopTransition: Bool = false
    @Published var stopTransitionAudioLevel: Float = 0.18
    /// Reference-date timestamp marking the start of the stop transition. The
    /// particle Canvas reads this to coast the motion to a halt over the window.
    @Published var stopTransitionStartReference: TimeInterval? = nil

    private var timer: Timer?
    private var startTime: Date?
    private var keyMonitor: Any?  // Event monitor for mid-recording modifiers
    private var isHiding = false  // Track if we're in the middle of a hide animation
    private var stopTransitionTask: Task<Void, Never>?

    private override init() {
        super.init()

        LiveSettings.shared.$overlayPlacement
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.window != nil else { return }
                    self.updateWindowPosition(for: self.state)
                }
            }
            .store(in: &settingsCancellables)

        LiveSettings.shared.$overlayStyle
            .dropFirst()
            .sink { [weak self] style in
                Task { @MainActor in
                    guard let self else { return }
                    let effectiveStyle = OverlayIndicatorOverridesStore.shared.resolvedOverlayStyle(fallback: style)

                    if effectiveStyle.showsTopOverlay {
                        if self.state == .listening, self.window == nil {
                            self.show()
                        } else if self.window != nil {
                            self.updateWindowPosition(for: self.state)
                        }
                    } else if self.window != nil {
                        self.hide()
                    }
                }
            }
            .store(in: &settingsCancellables)

        LiveSettings.shared.$islandOverlayWidth
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.window != nil, LiveSettings.shared.effectiveOverlayStyle == .island else { return }
                    self.updateWindowPosition(for: self.state)
                }
            }
            .store(in: &settingsCancellables)

        LiveSettings.shared.$islandOverlayHeight
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.window != nil, LiveSettings.shared.effectiveOverlayStyle == .island else { return }
                    self.updateWindowPosition(for: self.state)
                }
            }
            .store(in: &settingsCancellables)
    }

    func show() {
        // Don't show top overlay if "Pill Only" mode is selected
        guard LiveSettings.shared.effectiveOverlayStyle.showsTopOverlay else { return }

        // Cancel any pending hide animation - rapid succession fix
        if isHiding, let panel = window {
            isHiding = false
            // Stop the hide animation and restore the window
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                panel.animator().alphaValue = 1
            }
            panel.orderFront(nil)
            return
        }

        guard window == nil else {
            window?.orderFront(nil)
            return
        }

        let overlayView = RecordingOverlayView()
        let hostingView = NSHostingView(rootView: overlayView.environmentObject(self))
        let overlaySize = listeningOverlaySize()
        hostingView.frame = NSRect(x: 0, y: 0, width: overlaySize.width, height: overlaySize.height)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.hasShadow = false  // Chromeless - no visible border/shadow
        panel.acceptsMouseMovedEvents = true  // Required for hover detection

        if let screen = NSScreen.main {
            let finalFrame = targetFrame(
                for: .listening,
                on: screen,
                size: hostingView.frame.size
            )
            let startFrame = finalFrame.offsetBy(dx: 0, dy: 12)

            panel.setFrame(startFrame, display: false)
            panel.alphaValue = 0
            panel.orderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalFrame, display: true)
                panel.animator().alphaValue = 1
            }
        }

        self.window = panel

        // Start timer (2Hz is plenty for displaying seconds)
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        moveCommitTask?.cancel()
        moveCommitTask = nil
        stopTransitionTask?.cancel()
        stopTransitionTask = nil
        isShowingStopTransition = false
        stopTransitionStartReference = nil
        startTime = nil
        elapsedTime = 0
        transcript = ""

        guard let panel = window else {
            window?.orderOut(nil)
            window = nil
            return
        }
        let exitFrame = panel.frame.offsetBy(dx: 0, dy: 12)

        isHiding = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(exitFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Only clean up if we weren't interrupted by a new show()
                if self.isHiding {
                    self.isHiding = false
                    self.window?.orderOut(nil)
                    self.window = nil
                }
            }
        })
    }

    func updateState(_ state: LiveState, previousState: LiveState? = nil) {
        let oldState = previousState ?? self.state

        if oldState == .listening && state == .transcribing {
            beginStopTransition()
        } else if state != .transcribing {
            finishStopTransition()
        }

        self.state = state

        if state == .listening {
            show()
            startKeyMonitoring()  // Monitor for mid-recording modifier shortcuts
        } else {
            stopKeyMonitoring()
            if state == .idle {
                // Delay hide to show success checkmark clearly
                Task {
                    try? await Task.sleep(for: .milliseconds(900))  // Longer to show checkmark
                    if self.state == .idle {
                        hide()
                    }
                }
            }
        }

        // Re-center the window when state changes (different sizes for each state)
        updateWindowPosition(for: state)
    }

    private func beginStopTransition() {
        stopTransitionTask?.cancel()
        stopTransitionAudioLevel = max(0.12, AudioLevelMonitor.shared.level)
        stopTransitionStartReference = Date().timeIntervalSinceReferenceDate
        isShowingStopTransition = true

        stopTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: recordingOverlayStopTransitionDuration)
            guard let self, !Task.isCancelled, self.state == .transcribing else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                self.isShowingStopTransition = false
            }
            self.stopTransitionStartReference = nil
            self.updateWindowPosition(for: .transcribing)
            self.stopTransitionTask = nil
        }
    }

    private func finishStopTransition() {
        stopTransitionTask?.cancel()
        stopTransitionTask = nil
        isShowingStopTransition = false
        stopTransitionStartReference = nil
    }

    /// Update window position and size based on current state
    private func updateWindowPosition(for state: LiveState) {
        guard let panel = window else { return }

        let screen = panel.screen ?? NSScreen.main

        // Calculate size based on state (matches processingWidth/processingHeight in view)
        let width: CGFloat
        let height: CGFloat
        switch state {
        case .listening, .idle:
            let overlaySize = listeningOverlaySize()
            width = overlaySize.width
            height = overlaySize.height
        case .transcribing:
            if isShowingStopTransition {
                let overlaySize = listeningOverlaySize()
                width = overlaySize.width
                height = overlaySize.height
            } else {
                let overlaySize = processingOverlaySize()
                width = overlaySize.width
                height = overlaySize.height
            }
        case .routing, .refining:
            let overlaySize = processingOverlaySize()
            width = overlaySize.width
            height = overlaySize.height
        }
        guard let screen else { return }
        let targetFrame = targetFrame(
            for: state,
            on: screen,
            size: CGSize(width: width, height: height)
        )

        // Animate the window size and position change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func targetFrame(for state: LiveState, on screen: NSScreen, size: CGSize) -> CGRect {
        let placementBounds = recordingOverlayPlacementFrame(for: screen)
        let origin = LiveSettings.shared.overlayPlacement.origin(in: placementBounds, itemSize: size)
        return CGRect(origin: origin, size: size)
    }

    private func listeningOverlaySize() -> CGSize {
        let settings = LiveSettings.shared
        if settings.effectiveOverlayStyle == .island {
            return CGSize(width: CGFloat(settings.islandOverlayWidth), height: CGFloat(settings.islandOverlayHeight))
        }

        let tuning = OverlayTuning.shared
        return CGSize(
            width: OverlayIndicatorOverridesStore.shared.topBarWidth(fallback: tuning.overlayWidth),
            height: OverlayIndicatorOverridesStore.shared.topBarHeight(fallback: tuning.overlayHeight)
        )
    }

    private func processingOverlaySize() -> CGSize {
        let listeningSize = listeningOverlaySize()
        return CGSize(
            width: min(listeningSize.width, recordingOverlayProcessingIslandWidth),
            height: min(listeningSize.height, recordingOverlayProcessingIslandHeight)
        )
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard let panel = notification.object as? NSWindow,
                  panel === self.window,
                  self.state == .listening else { return }

            self.schedulePlacementCommit(for: panel)
        }
    }

    private func schedulePlacementCommit(for panel: NSWindow) {
        moveCommitTask?.cancel()
        moveCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, panel === self.window, self.state == .listening else { return }
            persistOverlayPlacement(from: panel.frame, on: panel.screen ?? NSScreen.main)
        }
    }

    func updateTranscript(_ text: String) {
        self.transcript = text
    }

    // Control callbacks - set by AppDelegate
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var agentController: AgentController?  // Reference to controller for intent updates

    func requestStop() {
        onStop?()
    }

    func requestCancel() {
        onCancel?()
        hide()
    }

    // MARK: - Key Monitoring for Mid-Recording Modifiers

    private func startKeyMonitoring() {
        stopKeyMonitoring()  // Clear any existing monitor

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let controller = self.agentController else { return event }

            let isShiftHeld = event.modifierFlags.contains(.shift)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // Detect Shift+A → Save as Memo
            if isShiftHeld && key == "a" {
                controller.setSaveAsMemoIntent()
                self.captureIntent = controller.captureIntent
                return nil  // Consume event
            }

            // Detect Shift+F → Queue live feedback
            if isShiftHeld && key == "f" {
                controller.requestFeedbackSidecar()
                return nil  // Consume event
            }

            // Detect Shift+R → Queue live research
            if isShiftHeld && key == "r" {
                controller.requestResearchSidecar()
                return nil  // Consume event
            }

            // Detect Shift or Shift+S → Toggle Scratchpad
            if isShiftHeld && (key == "s" || key == "") {
                if controller.captureIntent == "Paste" {
                    controller.setInterstitialIntent()
                } else {
                    controller.clearIntent()
                }
                self.captureIntent = controller.captureIntent
                return nil  // Consume event
            }

            return event
        }
    }

    private func stopKeyMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        captureIntent = "Paste"  // Reset to default
    }
}

// MARK: - Overlay Settings Preview

@MainActor
final class OverlaySettingsPreviewController: NSObject, NSWindowDelegate {
    static let shared = OverlaySettingsPreviewController()

    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var moveCommitTask: Task<Void, Never>?
    private var isActive = false
    private var isHiding = false
    private var isDismissedForCurrentActivation = false

    private override init() {
        super.init()

        let settings = LiveSettings.shared

        settings.$overlayStyle
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)

        settings.$overlayPlacement
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshFrame(animated: true) }
            }
            .store(in: &cancellables)

        settings.$islandOverlayWidth
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshFrame(animated: true) }
            }
            .store(in: &cancellables)

        settings.$islandOverlayHeight
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshFrame(animated: true) }
            }
            .store(in: &cancellables)

        RecordingOverlayController.shared.$state
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)
    }

    func activate() {
        isActive = true
        isDismissedForCurrentActivation = false
        refresh()
    }

    func deactivate() {
        isActive = false
        moveCommitTask?.cancel()
        moveCommitTask = nil
        hide()
    }

    func dismissForCurrentActivation() {
        isDismissedForCurrentActivation = true
        moveCommitTask?.cancel()
        moveCommitTask = nil
        hide()
    }

    private func refresh() {
        guard isActive else {
            hide()
            return
        }

        guard !isDismissedForCurrentActivation else {
            hide()
            return
        }

        guard RecordingOverlayController.shared.state == .idle,
              LiveSettings.shared.effectiveOverlayStyle.showsTopOverlay else {
            hide()
            return
        }

        showOrUpdate()
    }

    private func showOrUpdate() {
        if isHiding, let panel = window {
            isHiding = false
            panel.orderFront(nil)
            panel.animator().alphaValue = 1
            refreshFrame(animated: true)
            return
        }

        guard window == nil else {
            refreshFrame(animated: true)
            window?.orderFront(nil)
            return
        }

        let frame = previewFrame()
        let hostingView = NSHostingView(rootView: OverlaySettingsFloatingPreviewView())
        hostingView.frame = NSRect(origin: .zero, size: frame.size)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.alphaValue = 0

        window = panel
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func refreshFrame(animated: Bool) {
        guard let panel = window else { return }
        let frame = previewFrame()
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func hide() {
        guard let panel = window else { return }
        moveCommitTask?.cancel()
        moveCommitTask = nil
        isHiding = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.isHiding else { return }
                self.isHiding = false
                self.window?.orderOut(nil)
                self.window = nil
            }
        })
    }

    private func previewFrame() -> CGRect {
        let size = Self.currentPreviewSize()
        let screen = NSScreen.main
        let placementFrame = screen.map { recordingOverlayPlacementFrame(for: $0) } ?? .zero
        let origin = LiveSettings.shared.overlayPlacement.origin(in: placementFrame, itemSize: size)
        return CGRect(origin: origin, size: size)
    }

    static func currentPreviewSize() -> CGSize {
        let settings = LiveSettings.shared
        if settings.effectiveOverlayStyle == .island {
            return CGSize(width: CGFloat(settings.islandOverlayWidth), height: CGFloat(settings.islandOverlayHeight))
        }

        let tuning = OverlayTuning.shared
        return CGSize(
            width: OverlayIndicatorOverridesStore.shared.topBarWidth(fallback: tuning.overlayWidth),
            height: OverlayIndicatorOverridesStore.shared.topBarHeight(fallback: tuning.overlayHeight)
        )
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard let panel = notification.object as? NSWindow,
                  panel === self.window,
                  self.isActive,
                  !self.isDismissedForCurrentActivation else { return }

            self.schedulePlacementCommit(for: panel)
        }
    }

    private func schedulePlacementCommit(for panel: NSWindow) {
        moveCommitTask?.cancel()
        moveCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled,
                  panel === self.window,
                  self.isActive,
                  !self.isDismissedForCurrentActivation else { return }

            persistOverlayPlacement(from: panel.frame, on: panel.screen ?? NSScreen.main)
        }
    }
}

private struct OverlaySettingsFloatingPreviewView: View {
    @ObservedObject private var settings = LiveSettings.shared
    @ObservedObject private var overlayTuning = OverlayTuning.shared
    private let overlayOverrides = OverlayIndicatorOverridesStore.shared

    var body: some View {
        AgentOverlay(
            animationStyle: animationStyle,
            animationDirection: .inbound,
            width: previewSize.width,
            height: previewSize.height,
            cornerRadius: cornerRadius,
            backgroundFill: backgroundFill,
            borderColor: borderColor,
            audioLevel: 0.42,
            controlVisibility: .always,
            content: nil,
            leadingControl: AnyView(
                OverlayButton(action: {
                    OverlaySettingsPreviewController.shared.dismissForCurrentActivation()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                }
                .help("Hide preview")
            ),
            trailingControl: AnyView(
                OverlayButton(action: {}) {
                    RoundedRectangle(cornerRadius: 2)
                        .frame(width: 10, height: 10)
                }
            )
        )
    }

    private var previewSize: CGSize {
        OverlaySettingsPreviewController.currentPreviewSize()
    }

    private var cornerRadius: CGFloat {
        if settings.effectiveOverlayStyle == .island {
            return previewSize.height / 2
        }

        return overlayOverrides.topBarCornerRadius(fallback: overlayTuning.cornerRadius)
    }

    private var backgroundFill: Color {
        if settings.effectiveOverlayStyle == .island {
            return islandSurfaceBackground
        }

        let opacity = overlayOverrides.topBarBackgroundOpacity(fallback: overlayTuning.backgroundOpacity)
        return Color(white: 0, opacity: opacity * 0.7)
    }

    private var borderColor: Color {
        if settings.effectiveOverlayStyle == .island {
            return islandSurfaceBorder
        }

        return TalkieTheme.textSecondary.opacity(0.1)
    }

    private var animationStyle: AgentOverlay.AnimationStyle {
        switch settings.effectiveOverlayStyle {
        case .particles:
            return .particles(calm: false, speedMultiplier: 1.0)
        case .particlesCalm:
            return .particles(calm: true, speedMultiplier: 1.0)
        case .waveform:
            return .waveform(sensitive: false)
        case .waveformSensitive:
            return .waveform(sensitive: true)
        case .island:
            return .island
        case .pillOnly:
            return .none
        }
    }
}

// MARK: - Overlay View

struct RecordingOverlayView: View {
    @EnvironmentObject var controller: RecordingOverlayController
    @ObservedObject private var settings = LiveSettings.shared
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared

    // Direct access without observation - prevents cycles
    private let overlayTuning = OverlayTuning.shared
    private let overlayOverrides = OverlayIndicatorOverridesStore.shared
    private let whisperService = WhisperService.shared

    @State private var showCheckmark: Bool = false  // For transcribing → success transition

    // Colors matching status bar / floating pill
    private let processingOrange = SemanticColor.warning
    private let warmupCyan = Color.cyan

    var body: some View {
        overlayBody
        .animation(.easeOut(duration: 0.18), value: controller.state)
        .onChange(of: controller.state) { _, newState in
            if newState == .routing {
                withAnimation(.easeOut(duration: 0.25)) {
                    showCheckmark = true
                }
            } else if newState == .idle {
                // Keep checkmark visible longer so user can see it, then fade smoothly
                Task {
                    try? await Task.sleep(for: .milliseconds(700))  // Longer visibility
                    withAnimation(.easeOut(duration: 0.4)) {
                        showCheckmark = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var overlayBody: some View {
        switch controller.state {
        case .listening:
            AgentOverlay(
                animationStyle: recordingAnimationStyle,
                animationDirection: .inbound,
                width: processingWidth,
                height: processingHeight,
                cornerRadius: listeningCornerRadius,
                backgroundFill: listeningBackgroundFill,
                borderColor: listeningBorderColor,
                audioLevel: nil,
                controlVisibility: .always,
                content: audioMonitor.isSilent ? AnyView(
                    silentMicWarning
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                ) : nil,
                leadingControl: AnyView(
                    OverlayButton(action: { controller.requestCancel() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                    }
                ),
                trailingControl: AnyView(
                    OverlayButton(action: { controller.requestStop() }) {
                        RoundedRectangle(cornerRadius: 2)
                            .frame(width: 8.5, height: 8.5)
                    }
                )
            )
            .transition(.opacity)

        case .transcribing where controller.isShowingStopTransition:
            AgentOverlay(
                animationStyle: recordingAnimationStyle,
                animationDirection: .outbound,
                width: listeningOverlaySize.width,
                height: listeningOverlaySize.height,
                cornerRadius: listeningCornerRadius,
                backgroundFill: listeningBackgroundFill,
                borderColor: listeningBorderColor,
                audioLevel: controller.stopTransitionAudioLevel,
                controlVisibility: .hidden,
                content: nil,
                leadingControl: nil,
                trailingControl: nil,
                settleStartReference: controller.stopTransitionStartReference
            )
            .transition(.opacity)

        case .transcribing, .routing, .refining:
            ProcessingLifecycleIslandView(
                title: processingTitle,
                tint: processingTint,
                systemImage: processingSystemImage,
                showsSpinner: false
            )
            .frame(width: processingWidth, height: processingHeight)
            .recordingIndicatorSurface(
                backgroundFill: backgroundFill,
                borderColor: borderColor,
                cornerRadius: cornerRadiusForState
            )

        case .idle:
            ZStack {
                if showCheckmark {
                    CompletionDotView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .frame(width: processingWidth, height: processingHeight)
            .recordingIndicatorSurface(
                backgroundFill: backgroundFill,
                borderColor: borderColor,
                cornerRadius: cornerRadiusForState
            )
        }
    }

    // Silent mic warning - polite, non-alarming, with fix action
    private var silentMicWarning: some View {
        Button(action: {
            AudioTroubleshooterController.shared.show()
        }) {
            HStack(spacing: 6) {
                // Softer mic icon - more friendly and less alarming
                Image(systemName: "mic.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.cyan.opacity(0.9))  // Softer color, less aggressive

                Text("Check mic")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.cyan.opacity(0.8))

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.cyan.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // Dynamic sizing - shrinks progressively for processing states (droplet effect)
    private var processingWidth: CGFloat {
        let baseWidth = listeningOverlaySize.width
        switch controller.state {
        case .listening: return baseWidth
        case .transcribing: return processingOverlaySize.width
        case .routing: return processingOverlaySize.width
        case .refining: return processingOverlaySize.width
        case .idle: return baseWidth
        }
    }

    private var processingHeight: CGFloat {
        let baseHeight = listeningOverlaySize.height
        switch controller.state {
        case .listening: return baseHeight
        case .transcribing: return processingOverlaySize.height
        case .routing: return processingOverlaySize.height
        case .refining: return processingOverlaySize.height
        case .idle: return baseHeight
        }
    }

    private var listeningOverlaySize: CGSize {
        if settings.effectiveOverlayStyle == .island {
            return CGSize(width: CGFloat(settings.islandOverlayWidth), height: CGFloat(settings.islandOverlayHeight))
        }

        return CGSize(
            width: overlayOverrides.topBarWidth(fallback: overlayTuning.overlayWidth),
            height: overlayOverrides.topBarHeight(fallback: overlayTuning.overlayHeight)
        )
    }

    private var processingOverlaySize: CGSize {
        CGSize(
            width: min(listeningOverlaySize.width, recordingOverlayProcessingIslandWidth),
            height: min(listeningOverlaySize.height, recordingOverlayProcessingIslandHeight)
        )
    }

    private var cornerRadiusForState: CGFloat {
        switch controller.state {
        case .listening:
            return listeningCornerRadius
        case .transcribing:
            return processingHeight / 2
        case .routing, .refining:
            return processingHeight / 2
        case .idle:
            return listeningCornerRadius
        }
    }

    private var backgroundFill: Color {
        switch controller.state {
        case .listening:
            return listeningBackgroundFill
        case .transcribing:
            return islandSurfaceBackground
        case .routing:
            return islandSurfaceBackground
        case .refining:
            return islandSurfaceBackground
        case .idle:
            return Color.clear
        }
    }

    private var borderColor: Color {
        switch controller.state {
        case .listening:
            return listeningBorderColor
        case .transcribing:
            return processingTint.opacity(0.5)
        case .routing:
            return processingTint.opacity(0.5)
        case .refining:
            return processingTint.opacity(0.5)
        case .idle:
            return Color.clear
        }
    }

    private var processingTitle: String {
        switch controller.state {
        case .transcribing:
            return whisperService.isWarmingUp ? "Warming up" : "Transcribing"
        case .routing:
            return "Transcribed"
        case .refining:
            return "Refining"
        case .listening, .idle:
            return ""
        }
    }

    private var processingTint: Color {
        switch controller.state {
        case .transcribing:
            return whisperService.isWarmingUp ? warmupCyan : processingOrange
        case .routing:
            return SemanticColor.success
        case .refining:
            return Color.purple
        case .listening, .idle:
            return processingOrange
        }
    }

    private var processingSystemImage: String {
        switch controller.state {
        case .routing:
            return "checkmark"
        case .refining:
            return "sparkles"
        case .transcribing:
            return "waveform"
        case .listening, .idle:
            return "circle.fill"
        }
    }

    private var listeningCornerRadius: CGFloat {
        if settings.effectiveOverlayStyle == .island {
            return listeningOverlaySize.height / 2
        }
        return overlayOverrides.topBarCornerRadius(fallback: overlayTuning.cornerRadius)
    }

    private var listeningBackgroundFill: Color {
        if settings.effectiveOverlayStyle == .island {
            return islandSurfaceBackground
        }

        let opacity = overlayOverrides.topBarBackgroundOpacity(fallback: overlayTuning.backgroundOpacity)
        return Color(white: 0, opacity: opacity * 0.7)
    }

    private var listeningBorderColor: Color {
        if settings.effectiveOverlayStyle == .island {
            return islandSurfaceBorder
        }
        return TalkieTheme.textSecondary.opacity(0.1)
    }

    private var recordingAnimationStyle: AgentOverlay.AnimationStyle {
        switch settings.effectiveOverlayStyle {
        case .particles:
            return .particles(calm: false, speedMultiplier: 1.0)
        case .particlesCalm:
            return .particles(calm: true, speedMultiplier: 1.0)
        case .waveform:
            return .waveform(sensitive: false)
        case .waveformSensitive:
            return .waveform(sensitive: true)
        case .island:
            return .island
        case .pillOnly:
            return .none
        }
    }
}

// MARK: - Processing Dots (horizontal ellipsis animation)

struct ProcessingDotsView: View {
    let tint: Color
    @State private var animationPhase: Int = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotFill(for: index))
                    .frame(width: 3, height: 3)
                    .scaleEffect(dotScale(for: index))
            }
        }
        .frame(width: 18, height: 6)
        .onAppear {
            animationPhase = 1
            timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    animationPhase = (animationPhase + 1) % 4
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func dotFill(for index: Int) -> Color {
        animationPhase == indexPhase(for: index) ? tint : Color.white
    }

    private func dotScale(for index: Int) -> CGFloat {
        animationPhase == indexPhase(for: index) ? 1.15 : 0.92
    }

    private func indexPhase(for index: Int) -> Int {
        index + 1
    }
}

private struct ProcessingLifecycleIslandView: View {
    let title: String
    let tint: Color
    let systemImage: String
    let showsSpinner: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(tint, lineWidth: 1)
                    .frame(width: 18, height: 18)

                if showsSpinner {
                    BrailleSpinner(size: 9, speed: 0.10)
                        .foregroundStyle(tint)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tint)
                }
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsSpinner {
                ProcessingDotsView(tint: tint)
                    .frame(width: 18, height: 8)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 10)
    }
}

private struct ProcessingSpinnerView: View {
    let tint: Color

    var body: some View {
        BrailleSpinner(size: 10, speed: 0.11)
            .foregroundStyle(tint)
            .frame(width: recordingOverlayProcessingBoxWidth, height: recordingOverlayProcessingBoxHeight)
    }
}

// MARK: - Completion Dot (collapsed from three processing dots)

struct CompletionDotView: View {
    private let processingOrange = SemanticColor.warning

    var body: some View {
        // Single dot - the three processing dots collapse into one
        Circle()
            .fill(processingOrange)
            .frame(width: 4, height: 4)
    }
}

// MARK: - Infinity Particles (processing state - figure 8 loop with breathing feel)

struct InfinityParticlesView: View {
    let tint: Color  // Kept for API compatibility but we use white to match main particles

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: recordingOverlayFrameInterval)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate

                    // Center horizontally in the full screen width
                    let screenCenter = geometry.frame(in: .global).midX
                    let canvasCenter = size.width / 2
                    let centerX = canvasCenter + (screenCenter - canvasCenter) * 0  // Keep at canvas center
                    let centerY = size.height / 2

                    // Properly proportioned infinity loop - not squished
                    // The lemniscate naturally has a 2:1 aspect ratio, so we honor that
                    let baseLoopWidth: CGFloat = 32
                    let baseLoopHeight: CGFloat = 12  // Better proportions for true ∞ shape

                    // Breathing effect - gentle pulsing of the loop size
                    let breathingCycle = sin(time * 0.8) * 0.08 + 1.0  // Slow, subtle breathing
                    let loopWidth = baseLoopWidth * CGFloat(breathingCycle)
                    let loopHeight = baseLoopHeight * CGFloat(breathingCycle)

                    let particleCount = 12

                    for i in 0..<particleCount {
                        // Each particle has a phase offset around the infinity loop
                        let basePhase = Double(i) / Double(particleCount) * 2.0 * .pi
                        // Slower, more meditative rotation speed
                        let phase = basePhase + time * 1.0

                        // Parametric equation for infinity/lemniscate curve
                        // Using the proper Bernoulli lemniscate formula
                        let t = phase
                        let denom = 1.0 + sin(t) * sin(t)
                        let x = centerX + CGFloat(cos(t) / denom) * loopWidth
                        let y = centerY + CGFloat(sin(t) * cos(t) / denom) * loopHeight

                        // Particle size with subtle breathing - particles "breathe" too
                        let sizeBreath = 0.9 + sin(time * 1.5 + Double(i) * 0.3) * 0.18
                        let particleSize: CGFloat = 2.0 * CGFloat(sizeBreath)

                        let rect = CGRect(
                            x: x - particleSize / 2,
                            y: y - particleSize / 2,
                            width: particleSize,
                            height: particleSize
                        )
                        // Use explicit white for overlay context
                        context.fill(Circle().path(in: rect), with: .color(.white))
                    }
                }
            }
        }
    }
}

// MARK: - Success Particles (routing state - brief celebration)

struct SuccessParticlesView: View {
    @State private var phase: CGFloat = 0

    // Matches FloatingPill routing color
    private let successGreen = Color(red: 0.4, green: 1.0, blue: 0.5)

    var body: some View {
        TimelineView(.animation(minimumInterval: recordingOverlayFrameInterval)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerX = size.width / 2
                let centerY = size.height / 2

                // Converging particles that form a checkmark feeling
                let particleCount = 8

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618
                    let angle = Double(i) / Double(particleCount) * 2 * .pi

                    // Particles pulse inward
                    let pulse = sin(time * 4 + seed) * 0.3 + 0.7
                    let radius = min(size.width, size.height) * 0.3 * pulse

                    let x = centerX + CGFloat(cos(angle) * radius)
                    let y = centerY + CGFloat(sin(angle) * radius)

                    let particleSize: CGFloat = 2.0
                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(successGreen))
                }
            }
        }
    }
}

// MARK: - Overlay Button (with hover effect)

struct OverlayButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
                .foregroundStyle(isHovered ? Color.black : Color.white.opacity(0.62))
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .fill(isHovered ? Color.white : Color.white.opacity(0.04))
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(isHovered ? 1.0 : 0.22), lineWidth: 1)
                }
                .shadow(color: Color.white.opacity(isHovered ? 0.22 : 0), radius: 5)
                .scaleEffect(isHovered ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Particles (iOS Talkie style - direct port)

private struct WavyParticleConst {
    let seed: Double
    let speedSeed: Double
    let primaryPhase: Double
    let secondaryPhase: Double
    let laneOffset: Double
    let sizeVariation: CGFloat
}

private func buildWavyParticleConstants(_ count: Int) -> [WavyParticleConst] {
    (0..<count).map { i in
        let seed = Double(i) * 1.618033988749
        return WavyParticleConst(
            seed: seed,
            speedSeed: seed.truncatingRemainder(dividingBy: 1.0),
            primaryPhase: seed * 4,
            secondaryPhase: seed * 6,
            laneOffset: (Double(i % 10) / 10.0 - 0.5) * 0.3,
            sizeVariation: CGFloat(0.5 + sin(seed * 5) * 0.5)
        )
    }
}

struct WavyParticlesView: View {
    let calm: Bool
    let direction: AgentOverlay.AnimationDirection
    let levelOverride: Float?
    let speedMultiplier: Double
    let settleStartReference: TimeInterval?
    @ObservedObject private var tuning = ParticleTuning.shared
    @State private var smoothedInputLevel: CGFloat = 0
    @State private var particleConstants: [WavyParticleConst] = []
    @State private var lastParticleCount: Int = 0

    init(
        calm: Bool,
        direction: AgentOverlay.AnimationDirection = .inbound,
        levelOverride: Float? = nil,
        speedMultiplier: Double = 1.0,
        settleStartReference: TimeInterval? = nil
    ) {
        self.calm = calm
        self.direction = direction
        self.levelOverride = levelOverride
        self.speedMultiplier = speedMultiplier
        self.settleStartReference = settleStartReference
    }

    var body: some View {
        WavyParticlesCanvas(
            calm: calm,
            direction: direction,
            levelOverride: levelOverride,
            speedMultiplier: speedMultiplier,
            settleStartReference: settleStartReference,
            inputLevel: levelOverride.map(CGFloat.init) ?? smoothedInputLevel,
            particleCount: resolvedParticleCount,
            particleConstants: particleConstants,
            baseSpeed: tuning.baseSpeed,
            speedVariation: tuning.speedVariation,
            waveSpeed: tuning.waveSpeed,
            baseAmplitude: tuning.baseAmplitude,
            audioAmplitude: tuning.audioAmplitude,
            baseSize: tuning.baseSize,
            inputSensitivity: tuning.inputSensitivity
        )
        .onAppear {
            rebuildParticleConstantsIfNeeded()
            updateSmoothedInputLevel(from: currentInputLevel, immediate: true)
        }
        .onReceive(AudioLevelMonitor.shared.$level.throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)) { level in
            guard levelOverride == nil else { return }
            updateSmoothedInputLevel(from: level)
        }
        .onChange(of: levelOverride) { _, newValue in
            guard let newValue else { return }
            updateSmoothedInputLevel(from: newValue, immediate: true)
        }
        .onChange(of: tuning.particleCount) { _, _ in
            rebuildParticleConstantsIfNeeded()
        }
        .onChange(of: calm) { _, _ in
            rebuildParticleConstantsIfNeeded()
        }
    }

    private var resolvedParticleCount: Int {
        let tunedParticleCount = calm
            ? Int(Double(tuning.particleCount) * 0.45)
            : Int(Double(tuning.particleCount) * 0.55)
        return max(12, min(36, tunedParticleCount))
    }

    private var currentInputLevel: Float {
        levelOverride ?? AudioLevelMonitor.shared.level
    }

    private func rebuildParticleConstantsIfNeeded() {
        let count = resolvedParticleCount
        guard count != lastParticleCount else { return }
        lastParticleCount = count
        particleConstants = buildWavyParticleConstants(count)
    }

    private func updateSmoothedInputLevel(from inputLevel: Float, immediate: Bool = false) {
        let targetLevel = min(1, max(0, CGFloat(inputLevel)))
        guard !immediate else {
            smoothedInputLevel = targetLevel
            return
        }

        guard abs(targetLevel - smoothedInputLevel) > 0.001 else { return }

        let baseDuration = targetLevel > smoothedInputLevel
            ? recordingOverlayParticleLevelAttackDuration
            : recordingOverlayParticleLevelReleaseDuration
        let speedFactor = min(1.6, max(0.6, tuning.smoothingFactor / 0.55))
        let duration = baseDuration / speedFactor

        withAnimation(.easeOut(duration: duration)) {
            smoothedInputLevel = targetLevel
        }
    }
}

private struct WavyParticlesCanvas: View, Animatable {
    let calm: Bool
    let direction: AgentOverlay.AnimationDirection
    let levelOverride: Float?
    let speedMultiplier: Double
    let settleStartReference: TimeInterval?
    var inputLevel: CGFloat
    let particleCount: Int
    let particleConstants: [WavyParticleConst]
    let baseSpeed: Double
    let speedVariation: Double
    let waveSpeed: Double
    let baseAmplitude: Double
    let audioAmplitude: Double
    let baseSize: Double
    let inputSensitivity: Double

    var animatableData: CGFloat {
        get { inputLevel }
        set { inputLevel = newValue }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: recordingOverlayParticleFrameInterval)) { timeline in
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2
                let constants = particleConstants.isEmpty
                    ? buildWavyParticleConstants(particleCount)
                    : particleConstants

                // Coast-to-a-halt: while a stop transition is in progress, ease the
                // "virtual time" that drives flow + wave so the motion decelerates
                // smoothly to zero (constant deceleration: velocity 1 → 0 ⇒
                // distance = d·(u − u²/2)). Once the window elapses the value is
                // frozen, so the particles are fully at rest before the dots appear.
                // Pure per-frame math, no per-particle state.
                let motionTime: Double = {
                    guard let ref = settleStartReference else { return time }
                    let elapsed = time - ref
                    guard elapsed > 0 else { return time }
                    let d = recordingOverlayStopTransitionSeconds
                    let u = min(1.0, elapsed / d)
                    return ref + d * (u - u * u / 2)
                }()

                let rawLevel = inputLevel * CGFloat(inputSensitivity)
                let targetLevel = 1 - exp(-rawLevel)

                // Use tuning values, with calm mode applying a reduction factor
                let calmFactor = calm ? 0.42 : 1.0
                let levelFloor: CGFloat = levelOverride == nil ? 0.08 : 0.01
                let level = max(levelFloor, targetLevel)

                let resolvedBaseSpeed = baseSpeed * calmFactor * speedMultiplier
                let resolvedBaseAmp = baseAmplitude * calmFactor
                let resolvedAudioAmp = audioAmplitude * calmFactor
                let waveAmplitude = resolvedBaseAmp + Double(level) * resolvedAudioAmp
                let resolvedWaveSpeed = waveSpeed * calmFactor * speedMultiplier
                let resolvedBaseSize = CGFloat(baseSize)
                let levelBonus = level * 6.0  // More responsive size change with voice
                let flowRight = direction == .inbound

                for particle in constants {
                    // X position: constant speed flow from tuning
                    let speedVar = particle.speedSeed * speedVariation
                    let speed = resolvedBaseSpeed + speedVar
                    let xProgress = (motionTime * speed + particle.seed).truncatingRemainder(dividingBy: 1.0)
                    let x = flowRight
                        ? CGFloat(xProgress) * size.width
                        : size.width - (CGFloat(xProgress) * size.width)

                    // Y position: sine-wave motion with tuned parameters
                    let primaryWave = sin(motionTime * resolvedWaveSpeed + particle.primaryPhase) * waveAmplitude
                    let secondaryWave = sin(motionTime * (resolvedWaveSpeed * 0.6) + particle.secondaryPhase) * waveAmplitude * 0.3

                    // Small vertical offset per particle
                    let y = centerY + CGFloat((primaryWave + secondaryWave + particle.laneOffset) * Double(centerY) * 0.7)

                    // Size from tuning - particles grow with audio level
                    let edgeScale = flowRight
                        ? min(xProgress * 3.0, 1.0) * min((1.0 - xProgress) * 2.0, 1.0)
                        : min((1.0 - xProgress) * 3.0, 1.0) * min(xProgress * 2.0, 1.0)
                    let particleSize = (resolvedBaseSize + levelBonus * particle.sizeVariation) * max(0.35, CGFloat(edgeScale))

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    // Use explicit white for overlay context (TalkieTheme colors can resolve incorrectly in overlays)
                    context.fill(Circle().path(in: rect), with: .color(.white))
                }
            }
        }
    }
}

// MARK: - Waveform Bars (audio visualizer style)

struct WaveformBarsView: View {
    let sensitive: Bool
    let direction: AgentOverlay.AnimationDirection
    let levelOverride: Float?
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared
    @ObservedObject private var tuning = WaveformTuning.shared

    init(
        sensitive: Bool,
        direction: AgentOverlay.AnimationDirection = .inbound,
        levelOverride: Float? = nil
    ) {
        self.sensitive = sensitive
        self.direction = direction
        self.levelOverride = levelOverride
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: recordingOverlayFrameInterval)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let barCount = max(8, min(32, tuning.barCount))
                let gap = CGFloat(tuning.barGap)
                let barWidth: CGFloat = (size.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount)
                let maxBarHeight = size.height * CGFloat(tuning.maxHeightRatio)
                let centerY = size.height / 2

                // Apply input sensitivity to the raw audio level
                let inputLevel = levelOverride ?? audioMonitor.level
                let rawLevel = min(1.0, CGFloat(inputLevel) * CGFloat(tuning.inputSensitivity))

                // Sensitive mode: boost low levels, compress high levels
                // Normal mode: linear response
                let targetLevel: CGFloat
                if sensitive {
                    // Apply curve that boosts quiet sounds
                    let boosted = pow(rawLevel, 0.5)  // Square root gives more low-end response
                    let minimum: CGFloat = 0.15  // Always show some movement
                    targetLevel = max(minimum, boosted)
                } else {
                    targetLevel = rawLevel
                }

                for i in 0..<barCount {
                    let x = CGFloat(i) * (barWidth + gap)

                    // Each bar has slightly different response for natural look
                    let seed = Double(i) * 1.618
                    let variationBase: CGFloat = sensitive ? 0.8 : (1.0 - CGFloat(tuning.variationAmount))
                    let variationRange = CGFloat(tuning.variationAmount) * (sensitive ? 0.67 : 1.0)
                    let variation: CGFloat = variationBase + CGFloat(sin(seed * 3)) * variationRange
                    let flowIndex = direction == .inbound ? i : barCount - 1 - i
                    let flowPhase = Double(flowIndex) / Double(max(barCount - 1, 1))
                    let movement = 0.70 + 0.30 * CGFloat(sin(time * 4.2 - flowPhase * 6.0 + seed))
                    let barLevel = max(0.08, targetLevel * variation * movement)

                    // Bar height based on level
                    let minHeight: CGFloat
                    if levelOverride == nil {
                        minHeight = sensitive ? CGFloat(tuning.minBarHeight) * 2 : CGFloat(tuning.minBarHeight)
                    } else {
                        minHeight = 1
                    }
                    let barHeight = max(minHeight, barLevel * maxBarHeight)

                    // Draw bar centered vertically
                    let barRect = CGRect(
                        x: x,
                        y: centerY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )

                    context.fill(
                        RoundedRectangle(cornerRadius: CGFloat(tuning.cornerRadius)).path(in: barRect),
                        with: .color(.white)
                    )
                }
            }
        }
    }
}

// MARK: - Island Pill Shapes

struct IslandPillShapesView: View {
    let direction: AgentOverlay.AnimationDirection
    let levelOverride: Float?

    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared
    @ObservedObject private var settings = LiveSettings.shared
    @State private var smoothedLevel: CGFloat = 0.18

    init(
        direction: AgentOverlay.AnimationDirection = .inbound,
        levelOverride: Float? = nil
    ) {
        self.direction = direction
        self.levelOverride = levelOverride
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: recordingOverlayFrameInterval)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let islandSettings = settings.islandVisualizationSettings
                let speed = CGFloat(islandSettings.motion)
                let reactivity = CGFloat(islandSettings.reactivity)
                let density = CGFloat(islandSettings.shape)
                let level = max(0.10, smoothedLevel)
                let speedAmount = max(0.12, speed)
                let particleCount = Int(16 + density * 16)
                let flowSpeed = 0.18 + Double(speedAmount) * 0.52
                let waveSpeed = 1.25 + Double(speedAmount) * 1.15
                let flowRight = direction == .inbound
                let centerY = size.height * 0.48
                let waveAmplitude = (0.08 + Double(level) * (0.42 + Double(reactivity) * 0.22)) * Double(size.height) * 0.5
                let baseSize = 1.45 + density * 1.15
                let levelBonus = level * (1.2 + reactivity * 1.6)

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749
                    let speedVariation = seed.truncatingRemainder(dividingBy: 1.0) * 0.06
                    let xProgress = (time * (flowSpeed + speedVariation) + seed).truncatingRemainder(dividingBy: 1.0)
                    let x = flowRight
                        ? CGFloat(xProgress) * size.width
                        : size.width - CGFloat(xProgress) * size.width
                    let laneOffset = (Double(i % 9) / 8.0 - 0.5) * 0.38
                    let primaryWave = sin(time * waveSpeed + seed * 4.0)
                    let secondaryWave = sin(time * (waveSpeed * 0.48) + seed * 6.0) * 0.28
                    let y = centerY + CGFloat((primaryWave + secondaryWave + laneOffset) * waveAmplitude)
                    let sizeScale = CGFloat(0.68 + sin(seed * 5.0) * 0.32)
                    let particleSize = max(1.1, baseSize + levelBonus * sizeScale)
                    let edgeFade = flowRight
                        ? min(xProgress * 3.0, 1.0) * min((1.0 - xProgress) * 2.0, 1.0)
                        : min((1.0 - xProgress) * 3.0, 1.0) * min(xProgress * 2.0, 1.0)
                    let visibleSize = particleSize * max(0.34, CGFloat(edgeFade))

                    // Luminous opacity: horizontal edge fade + per-particle depth + a gentle
                    // shimmer. This is pure per-frame math (no main-thread dispatch), so it
                    // restores the soft glow without touching the performance work.
                    let shimmer = 0.74 + sin(time * 2.1 + seed * 3.0) * 0.16
                    let depth = 0.58 + sin(seed * 3.0) * 0.42
                    let rawOpacity = (0.30 + Double(level) * (0.34 + Double(reactivity) * 0.18))
                        * Double(edgeFade) * shimmer * depth
                    let opacity = min(0.96, max(0.30, rawOpacity * 1.9))

                    let rect = CGRect(
                        x: x - visibleSize / 2,
                        y: y - visibleSize / 2,
                        width: visibleSize,
                        height: visibleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(Color.white.opacity(opacity)))
                }

                // Single soft glint sweep — one fill per frame, negligible cost, adds a
                // "lit glass" highlight gliding across the pill.
                if speedAmount > 0.05 {
                    let glintWidth = max(18, size.width * (0.10 + level * 0.08))
                    let glintXProgress = CGFloat((time * (0.18 + Double(speedAmount) * 0.34)).truncatingRemainder(dividingBy: 1))
                    let glintX = flowRight
                        ? glintXProgress * (size.width + glintWidth) - glintWidth
                        : (1 - glintXProgress) * (size.width + glintWidth) - glintWidth
                    let glintRect = CGRect(x: glintX, y: 2.2, width: glintWidth, height: 0.8)
                    context.fill(
                        RoundedRectangle(cornerRadius: 0.5).path(in: glintRect),
                        with: .color(Color.white.opacity(0.10 + level * 0.14))
                    )
                }
            }
        }
        .onAppear {
            updateSmoothedLevel(from: currentInputLevel)
        }
        .onReceive(audioMonitor.$level) { level in
            guard levelOverride == nil else { return }
            updateSmoothedLevel(from: level)
        }
        .onChange(of: levelOverride) { _, newValue in
            guard let newValue else { return }
            updateSmoothedLevel(from: newValue)
        }
        .onChange(of: settings.islandOverlayReactivity) { _, _ in
            updateSmoothedLevel(from: currentInputLevel)
        }
    }

    private var currentInputLevel: Float {
        levelOverride ?? audioMonitor.level
    }

    private func updateSmoothedLevel(from inputLevel: Float) {
        let islandSettings = settings.islandVisualizationSettings
        let sensitivity = 0.9 + islandSettings.reactivity * 2.0
        let targetLevel = min(1, max(0.04, CGFloat(inputLevel) * CGFloat(sensitivity)))
        let blend = CGFloat(0.12 + islandSettings.motion * 0.14)
        smoothedLevel = smoothedLevel * (1 - blend) + targetLevel * blend
    }
}

#Preview {
    RecordingOverlayView()
        .environmentObject(RecordingOverlayController.shared)
        .frame(width: 400, height: 56)
        .padding()
}
