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
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: 0.25)
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

    let placementBounds = screen.overlayPlacementFrame()
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

    private var timer: Timer?
    private var startTime: Date?
    private var keyMonitor: Any?  // Event monitor for mid-recording modifiers
    private var isHiding = false  // Track if we're in the middle of a hide animation

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

    func updateState(_ state: LiveState) {
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
            width = recordingOverlayProcessingBoxWidth
            height = recordingOverlayProcessingBoxHeight
        case .routing, .refining:
            width = recordingOverlayProcessingBoxWidth
            height = recordingOverlayProcessingBoxHeight
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
        let placementBounds = screen.overlayPlacementFrame()
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
        let placementFrame = screen?.overlayPlacementFrame() ?? .zero
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
            return Color.black.opacity(0.92)
        }

        let opacity = overlayOverrides.topBarBackgroundOpacity(fallback: overlayTuning.backgroundOpacity)
        return Color(white: 0, opacity: opacity * 0.7)
    }

    private var borderColor: Color {
        if settings.effectiveOverlayStyle == .island {
            return Color.white.opacity(0.12)
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
                cornerRadius: cornerRadiusForState,
                backgroundFill: backgroundFill,
                borderColor: borderColor,
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

        case .transcribing, .routing, .refining, .idle:
            ZStack {
                if controller.state == .transcribing {
                    ProcessingSpinnerView(
                        tint: whisperService.isWarmingUp ? warmupCyan : processingOrange
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }

                if controller.state == .routing || showCheckmark {
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
        case .transcribing: return recordingOverlayProcessingBoxWidth
        case .routing: return recordingOverlayProcessingBoxWidth
        case .refining: return recordingOverlayProcessingBoxWidth
        case .idle: return baseWidth
        }
    }

    private var processingHeight: CGFloat {
        let baseHeight = listeningOverlaySize.height
        switch controller.state {
        case .listening: return baseHeight
        case .transcribing: return recordingOverlayProcessingBoxHeight
        case .routing: return recordingOverlayProcessingBoxHeight
        case .refining: return recordingOverlayProcessingBoxHeight
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

    private var cornerRadiusForState: CGFloat {
        switch controller.state {
        case .listening:
            if settings.effectiveOverlayStyle == .island {
                return processingHeight / 2
            }
            return overlayOverrides.topBarCornerRadius(fallback: overlayTuning.cornerRadius)
        case .transcribing:
            return 12
        case .routing, .refining:
            return 12
        case .idle:
            if settings.effectiveOverlayStyle == .island {
                return processingHeight / 2
            }
            return overlayOverrides.topBarCornerRadius(fallback: overlayTuning.cornerRadius)
        }
    }

    private var backgroundFill: Color {
        switch controller.state {
        case .listening:
            if settings.effectiveOverlayStyle == .island {
                return Color.black.opacity(0.92)
            }
            let opacity = overlayOverrides.topBarBackgroundOpacity(fallback: overlayTuning.backgroundOpacity)
            return Color(white: 0, opacity: opacity * 0.7)
        case .transcribing:
            return (whisperService.isWarmingUp ? warmupCyan : processingOrange).opacity(0.06)
        case .routing:
            return processingOrange.opacity(0.06)
        case .refining:
            return Color.purple.opacity(0.06)
        case .idle:
            return Color.clear
        }
    }

    private var borderColor: Color {
        switch controller.state {
        case .listening:
            if settings.effectiveOverlayStyle == .island {
                return Color.white.opacity(0.12)
            }
            return TalkieTheme.textSecondary.opacity(0.1)
        case .transcribing:
            return (whisperService.isWarmingUp ? warmupCyan : processingOrange).opacity(0.18)
        case .routing:
            return processingOrange.opacity(0.18)
        case .refining:
            return Color.purple.opacity(0.18)
        case .idle:
            return Color.clear
        }
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
                    .fill(tint.opacity(dotOpacity(for: index)))
                    .frame(width: 3, height: 3)
                    .scaleEffect(dotScale(for: index))
                    .shadow(color: tint.opacity(animationPhase == indexPhase(for: index) ? 0.28 : 0), radius: 3)
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

    private func dotOpacity(for index: Int) -> Double {
        if animationPhase == 0 {
            return 0.26
        }

        return animationPhase == indexPhase(for: index) ? 0.95 : 0.3
    }

    private func dotScale(for index: Int) -> CGFloat {
        animationPhase == indexPhase(for: index) ? 1.15 : 0.92
    }

    private func indexPhase(for index: Int) -> Int {
        index + 1
    }
}

private struct ProcessingSpinnerView: View {
    let tint: Color

    var body: some View {
        BrailleSpinner(size: 10, speed: 0.11)
            .foregroundStyle(tint.opacity(0.85))
            .frame(width: recordingOverlayProcessingBoxWidth, height: recordingOverlayProcessingBoxHeight)
    }
}

// MARK: - Completion Dot (collapsed from three processing dots)

struct CompletionDotView: View {
    private let processingOrange = SemanticColor.warning

    var body: some View {
        // Single dot - the three processing dots collapse into one
        Circle()
            .fill(processingOrange.opacity(0.9))
            .frame(width: 4, height: 4)
    }
}

// MARK: - Infinity Particles (processing state - figure 8 loop with breathing feel)

struct InfinityParticlesView: View {
    let tint: Color  // Kept for API compatibility but we use white to match main particles

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 0.016)) { timeline in
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
                    let breathingCycle = sin(time * 0.8) * 0.12 + 1.0  // Slow, subtle breathing
                    let loopWidth = baseLoopWidth * CGFloat(breathingCycle)
                    let loopHeight = baseLoopHeight * CGFloat(breathingCycle)

                    let particleCount = 24  // Smooth flow

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
                        let sizeBreath = 0.85 + sin(time * 1.5 + Double(i) * 0.3) * 0.25
                        let particleSize: CGFloat = 2.0 * CGFloat(sizeBreath)

                        // Opacity variation creates depth - particles fade in and out gently
                        // Use same opacity range as WavyParticlesView for consistency
                        let baseOpacity = 0.56
                        let breathOpacity = sin(time * 1.2 + Double(i) * 0.5) * 0.18
                        let flowOpacity = sin(phase * 1.5) * 0.12
                        let opacity = baseOpacity + breathOpacity + flowOpacity

                        let rect = CGRect(
                            x: x - particleSize / 2,
                            y: y - particleSize / 2,
                            width: particleSize,
                            height: particleSize
                        )
                        // Use explicit white for overlay context
                        context.fill(Circle().path(in: rect), with: .color(Color.white.opacity(max(0.34, min(0.90, opacity)))))
                    }

                    // Add a subtle glow trail effect - a few larger, more transparent particles
                    for i in 0..<6 {
                        let trailPhase = Double(i) / 6.0 * 2.0 * .pi
                        let phase = trailPhase + time * 1.0 - 0.25  // Slightly behind the main particles

                        let t = phase
                        let denom = 1.0 + sin(t) * sin(t)
                        let x = centerX + CGFloat(cos(t) / denom) * loopWidth
                        let y = centerY + CGFloat(sin(t) * cos(t) / denom) * loopHeight

                        let glowSize: CGFloat = 4.5 * CGFloat(breathingCycle)
                        let glowOpacity = 0.10 + sin(time * 0.8) * 0.025

                        let rect = CGRect(
                            x: x - glowSize / 2,
                            y: y - glowSize / 2,
                            width: glowSize,
                            height: glowSize
                        )
                        // Use explicit white for overlay context
                        context.fill(Circle().path(in: rect), with: .color(Color.white.opacity(glowOpacity)))
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
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerX = size.width / 2
                let centerY = size.height / 2

                // Converging particles that form a checkmark feeling
                let particleCount = 12

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618
                    let angle = Double(i) / Double(particleCount) * 2 * .pi

                    // Particles pulse inward
                    let pulse = sin(time * 4 + seed) * 0.3 + 0.7
                    let radius = min(size.width, size.height) * 0.3 * pulse

                    let x = centerX + CGFloat(cos(angle) * radius)
                    let y = centerY + CGFloat(sin(angle) * radius)

                    let particleSize: CGFloat = 2.0
                    let opacity = 0.7

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(successGreen.opacity(opacity)))
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
                .foregroundColor(Color.white.opacity(isHovered ? 0.96 : 0.50))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.22 : 0.035))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isHovered ? 0.28 : 0.07), lineWidth: 0.8)
                )
                .shadow(color: Color.white.opacity(isHovered ? 0.18 : 0), radius: 5)
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

struct WavyParticlesView: View {
    let calm: Bool
    let direction: AgentOverlay.AnimationDirection
    let levelOverride: Float?
    let speedMultiplier: Double
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared
    @ObservedObject private var tuning = ParticleTuning.shared
    @State private var smoothedLevel: CGFloat = 0.2

    init(
        calm: Bool,
        direction: AgentOverlay.AnimationDirection = .inbound,
        levelOverride: Float? = nil,
        speedMultiplier: Double = 1.0
    ) {
        self.calm = calm
        self.direction = direction
        self.levelOverride = levelOverride
        self.speedMultiplier = speedMultiplier
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2

                // Apply input sensitivity to the raw audio level
                let inputLevel = levelOverride ?? audioMonitor.level
                let rawLevel = CGFloat(inputLevel) * CGFloat(tuning.inputSensitivity)
                let targetLevel = min(1.0, rawLevel)  // Clamp to prevent crazy values

                // Use tuning values, with calm mode applying a reduction factor
                let calmFactor = calm ? 0.42 : 1.0
                let smoothingFactor = tuning.smoothingFactor * calmFactor
                let levelFloor: CGFloat = levelOverride == nil ? 0.08 : 0.01
                let level = max(levelFloor, smoothedLevel)

                // Particle count from tuning
                let particleCount = calm ? Int(Double(tuning.particleCount) * 0.9) : tuning.particleCount

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749

                    // X position: constant speed flow from tuning
                    let baseSpeed = tuning.baseSpeed * calmFactor * speedMultiplier
                    let speedVar = (seed.truncatingRemainder(dividingBy: 1.0)) * tuning.speedVariation
                    let speed = baseSpeed + speedVar
                    let xProgress = (time * speed + seed).truncatingRemainder(dividingBy: 1.0)
                    let x = direction == .inbound
                        ? CGFloat(xProgress) * size.width
                        : size.width - (CGFloat(xProgress) * size.width)

                    // Y position: sine-wave motion with tuned parameters
                    let baseAmp = tuning.baseAmplitude * calmFactor
                    let audioAmp = tuning.audioAmplitude * calmFactor
                    let waveAmplitude = baseAmp + Double(level) * audioAmp

                    let waveSpd = tuning.waveSpeed * calmFactor * speedMultiplier
                    let primaryWave = sin(time * waveSpd + seed * 4) * waveAmplitude
                    let secondaryWave = sin(time * (waveSpd * 0.6) + seed * 6) * waveAmplitude * 0.3

                    // Small vertical offset per particle
                    let laneOffset = (Double(i % 10) / 10.0 - 0.5) * 0.3
                    let y = centerY + CGFloat((primaryWave + secondaryWave + laneOffset) * Double(centerY) * 0.7)

                    // Size from tuning - particles grow with audio level
                    let baseSize = CGFloat(tuning.baseSize)
                    let levelBonus = level * 6.0  // More responsive size change with voice
                    let sizeVariation = CGFloat(0.5 + sin(seed * 5) * 0.5)  // 0.0-1.0 range
                    let particleSize = baseSize + levelBonus * sizeVariation

                    // Opacity from tuning - more responsive to voice
                    let visibilityBoost = levelOverride == nil ? 1.18 : max(0.12, Double(level) * 1.65)
                    let opacity = min(
                        0.96,
                        max(
                            0.24,
                            (tuning.baseOpacity + Double(level) * 0.56 * (0.6 + sin(seed * 3) * 0.4)) * visibilityBoost
                        )
                    )

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    // Use explicit white for overlay context (TalkieTheme colors can resolve incorrectly in overlays)
                    context.fill(Circle().path(in: rect), with: .color(Color.white.opacity(opacity)))
                }

                // Smooth level update - needed inside Canvas for 60fps responsiveness
                DispatchQueue.main.async {
                    smoothedLevel = smoothedLevel * (1.0 - CGFloat(smoothingFactor)) + targetLevel * CGFloat(smoothingFactor)
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
    @State private var barLevels: [CGFloat] = Array(repeating: 0.1, count: 48)

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
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let barCount = tuning.barCount
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

                // Ensure barLevels array is the right size
                let currentLevels = barLevels.count == barCount ? barLevels : Array(repeating: 0.1, count: barCount)

                for i in 0..<barCount {
                    let x = CGFloat(i) * (barWidth + gap)

                    // Each bar has slightly different response for natural look
                    let seed = Double(i) * 1.618
                    let variationBase: CGFloat = sensitive ? 0.8 : (1.0 - CGFloat(tuning.variationAmount))
                    let variationRange = CGFloat(tuning.variationAmount) * (sensitive ? 0.67 : 1.0)
                    let variation: CGFloat = variationBase + CGFloat(sin(seed * 3)) * variationRange
                    let barLevel = currentLevels[i] * variation

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

                    // Color/opacity - use explicit white for overlay context
                    let baseOpacity = levelOverride == nil
                        ? (sensitive ? tuning.baseOpacity * 1.25 : tuning.baseOpacity)
                        : 0.02
                    let visibilityBoost = levelOverride == nil ? 1.0 : max(0.08, Double(barLevel) * 1.6)
                    let opacity = (baseOpacity + Double(barLevel) * tuning.levelOpacityBoost) * visibilityBoost
                    context.fill(
                        RoundedRectangle(cornerRadius: CGFloat(tuning.cornerRadius)).path(in: barRect),
                        with: .color(Color.white.opacity(opacity))
                    )
                }

                // Update bar levels with audio, respecting the requested flow direction
                // Note: DispatchQueue.main.async is needed here for smooth 60fps updates
                DispatchQueue.main.async {
                    var newLevels = currentLevels.count == barCount ? currentLevels : Array(repeating: 0.1, count: barCount)
                    let smoothFactor: CGFloat = sensitive ? CGFloat(tuning.smoothingFactor) * 1.2 : CGFloat(tuning.smoothingFactor)
                    let edgeIndex = direction == .inbound ? barCount - 1 : 0
                    let lastLevel = barCount > 0 ? newLevels[edgeIndex] : 0.1
                    let smoothed = lastLevel * (1 - smoothFactor) + targetLevel * smoothFactor

                    if direction == .inbound {
                        for i in 0..<(barCount - 1) {
                            newLevels[i] = newLevels[i + 1]
                        }
                        if barCount > 0 {
                            newLevels[barCount - 1] = smoothed
                        }
                    } else {
                        for i in stride(from: barCount - 1, through: 1, by: -1) {
                            newLevels[i] = newLevels[i - 1]
                        }
                        if barCount > 0 {
                            newLevels[0] = smoothed
                        }
                    }
                    barLevels = newLevels
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
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let islandSettings = settings.islandVisualizationSettings
                let speed = CGFloat(islandSettings.motion)
                let reactivity = CGFloat(islandSettings.reactivity)
                let density = CGFloat(islandSettings.shape)
                let level = max(0.10, smoothedLevel)
                let speedAmount = max(0.12, speed)
                let particleCount = Int(18 + density * 22)
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
                    let shimmer = 0.72 + sin(time * 2.2 + seed * 3.0) * 0.18
                    let opacityScale = 0.58 + sin(seed * 3.0) * 0.34
                    let opacity = min(
                        0.92,
                        max(
                            0.18,
                            (0.28 + Double(level) * (0.40 + Double(reactivity) * 0.22)) * edgeFade * shimmer * opacityScale
                        )
                    )

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(Color.white.opacity(opacity)))
                }

                if speed > 0.05 {
                    let glintWidth = max(18, size.width * (0.10 + level * 0.08))
                    let glintXProgress = CGFloat((time * (0.18 + Double(speedAmount) * 0.34)).truncatingRemainder(dividingBy: 1))
                    let glintX = flowRight
                        ? glintXProgress * (size.width + glintWidth) - glintWidth
                        : (1 - glintXProgress) * (size.width + glintWidth) - glintWidth
                    let glintRect = CGRect(x: glintX, y: 2.2, width: glintWidth, height: 0.8)
                    context.fill(
                        RoundedRectangle(cornerRadius: 0.5).path(in: glintRect),
                        with: .color(Color.white.opacity(0.055 + level * 0.10))
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
