//
//  RecordingOverlay.swift
//  TalkieLive
//
//  Floating panel that shows during recording
//

import SwiftUI
import TalkieKit
import AppKit

// MARK: - Overlay Window Controller

@MainActor
final class RecordingOverlayController: ObservableObject {
    static let shared = RecordingOverlayController()

    private var window: NSWindow?

    @Published var state: LiveState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var transcript: String = ""
    @Published var captureIntent: String = "Paste"  // Shows current intent during recording

    private var timer: Timer?
    private var startTime: Date?
    private var keyMonitor: Any?  // Event monitor for mid-recording modifiers

    private init() {}

    func show() {
        // Don't show top overlay if "Pill Only" mode is selected
        guard LiveSettings.shared.overlayStyle.showsTopOverlay else { return }

        guard window == nil else {
            window?.orderFront(nil)
            return
        }

        let tuning = OverlayTuning.shared
        let overlayView = RecordingOverlayView()
        let hostingView = NSHostingView(rootView: overlayView.environmentObject(self))
        hostingView.frame = NSRect(x: 0, y: 0, width: tuning.overlayWidth, height: tuning.overlayHeight)

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
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true  // Required for hover detection

        // Position based on settings - tight to edges
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth = hostingView.frame.width
            let panelHeight = hostingView.frame.height
            let margin: CGFloat = 4  // Minimal gap from menu bar

            // Calculate final position
            let finalX: CGFloat
            let position = LiveSettings.shared.overlayPosition
            switch position {
            case .topCenter:
                finalX = screenFrame.midX - panelWidth / 2
            case .topLeft:
                finalX = screenFrame.minX + margin
            case .topRight:
                finalX = screenFrame.maxX - panelWidth - margin
            }
            let finalY = screenFrame.maxY - panelHeight - margin

            // Start position: slide from logical direction based on position
            // topCenter: from top, topLeft: from top-left, topRight: from top-right
            let startX: CGFloat
            let startY: CGFloat
            switch position {
            case .topCenter:
                // Slide from top (above screen)
                startX = finalX
                startY = screenFrame.maxY + 10
            case .topLeft:
                // Slide from top-left (diagonal)
                startX = screenFrame.minX - panelWidth - 10
                startY = screenFrame.maxY + 10
            case .topRight:
                // Slide from top-right (diagonal)
                startX = screenFrame.maxX + 10
                startY = screenFrame.maxY + 10
            }

            panel.setFrameOrigin(NSPoint(x: startX, y: startY))
            panel.alphaValue = 0
            panel.orderFront(nil)

            // Animate sliding to final position from logical edge
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(NSPoint(x: finalX, y: finalY))
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
        startTime = nil
        elapsedTime = 0
        transcript = ""

        guard let panel = window, let screen = NSScreen.main else {
            window?.orderOut(nil)
            window = nil
            return
        }

        let screenFrame = screen.visibleFrame
        let currentFrame = panel.frame
        let position = LiveSettings.shared.overlayPosition

        // Animate sliding back to the edge it came from (reverse of show animation)
        let exitX: CGFloat
        let exitY: CGFloat
        switch position {
        case .topCenter:
            // Slide back up to top
            exitX = currentFrame.origin.x
            exitY = screenFrame.maxY + 10
        case .topLeft:
            // Slide back to top-left
            exitX = screenFrame.minX - currentFrame.width - 10
            exitY = screenFrame.maxY + 10
        case .topRight:
            // Slide back to top-right
            exitX = screenFrame.maxX + 10
            exitY = screenFrame.maxY + 10
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(NSPoint(x: exitX, y: exitY))
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        })
    }

    func updateState(_ state: LiveState) {
        self.state = state

        if state == .listening {
            show()
            startKeyMonitoring()  // Monitor for Shift+A during recording
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
        guard let panel = window, let screen = NSScreen.main else { return }

        let tuning = OverlayTuning.shared
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 4

        // Calculate size based on state (matches processingWidth/processingHeight in view)
        let width: CGFloat
        let height: CGFloat
        switch state {
        case .listening, .idle:
            width = CGFloat(tuning.overlayWidth)
            height = CGFloat(tuning.overlayHeight)
        case .transcribing, .routing:
            // Same size - dots collapse but window stays put
            width = 56
            height = 24
        }

        // Calculate new position (always center horizontally)
        let y = screenFrame.maxY - height - margin
        let x: CGFloat
        switch LiveSettings.shared.overlayPosition {
        case .topCenter:
            x = screenFrame.midX - width / 2
        case .topLeft:
            x = screenFrame.minX + margin
        case .topRight:
            x = screenFrame.maxX - width - margin
        }

        // Animate the window size and position change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }

    func updateTranscript(_ text: String) {
        self.transcript = text
    }

    // Control callbacks - set by AppDelegate
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var liveController: LiveController?  // Reference to controller for intent updates

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
            guard let self = self, let controller = self.liveController else { return event }

            let isShiftHeld = event.modifierFlags.contains(.shift)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // Detect Shift+A → Save as Memo
            if isShiftHeld && key == "a" {
                controller.setSaveAsMemoIntent()
                self.captureIntent = controller.captureIntent
                return nil  // Consume event
            }

            // Detect Shift or Shift+S → Toggle Scratchpad
            // If auto-scratchpad is active (from selection), Shift cancels it
            // Otherwise, Shift enables scratchpad mode
            if isShiftHeld && (key == "s" || key == "") {
                if controller.isAutoScratchpad {
                    // Auto-scratchpad is on → Shift cancels it
                    controller.clearIntent()
                } else if controller.captureIntent == "Paste" {
                    // Normal paste mode → Shift enables scratchpad
                    controller.setInterstitialIntent()
                } else {
                    // Already in scratchpad mode (manually set) → Shift cancels
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

// MARK: - Overlay View

struct RecordingOverlayView: View {
    @EnvironmentObject var controller: RecordingOverlayController
    @ObservedObject private var settings = LiveSettings.shared
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared

    // Direct access without observation - prevents cycles
    private let overlayTuning = OverlayTuning.shared
    private let whisperService = WhisperService.shared

    @State private var isOverlayHovered: Bool = false  // Track hover state for controls
    @State private var showCheckmark: Bool = false  // For transcribing → success transition

    // Colors matching status bar / floating pill
    private let processingOrange = SemanticColor.warning
    private let successGreen = SemanticColor.success
    private let warmupCyan = Color.cyan

    var body: some View {
        ZStack {
            // Recording state - visualization based on style
            if controller.state == .listening {
                ZStack {
                    Group {
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
                            EmptyView()  // No top overlay content for pill-only mode
                        }
                    }

                    // Silent mic warning overlay
                    if audioMonitor.isSilent {
                        silentMicWarning
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .transition(.opacity)  // Fade only, no horizontal slide

                // Controls - only visible on hover
                if isOverlayHovered {
                    HStack {
                        // Cancel hint (left edge)
                        OverlayButton(action: { controller.requestCancel() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.leading, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))

                        Spacer()

                        // Stop hint (right edge)
                        OverlayButton(action: { controller.requestStop() }) {
                            RoundedRectangle(cornerRadius: 2)
                                .frame(width: 10, height: 10)
                        }
                        .padding(.trailing, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
            }

            // Processing state - simple ellipsis animation with orange tint
            // Shows warmup message if model is still warming up
            if controller.state == .transcribing {
                VStack(spacing: 8) {
                    ProcessingDotsView(tint: whisperService.isWarmingUp ? warmupCyan : processingOrange)

                    // Contextual warmup message
                    if whisperService.isWarmingUp {
                        Text(warmupStatusMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(warmupCyan.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)  // Center in container
                .transition(.opacity)  // Fade only, no horizontal slide
            }

            // Success state - single dot (collapsed from three dots)
            if controller.state == .routing || showCheckmark {
                CompletionDotView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)  // Fade only, no horizontal slide
            }
        }
        .frame(width: processingWidth, height: processingHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadiusForState)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadiusForState)
                        .stroke(borderColor, lineWidth: 0.5)
                )
        )
        .animation(.easeOut(duration: 0.3), value: controller.state)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isOverlayHovered = hovering
            }
        }
        .onChange(of: controller.state) { _, newState in
            // Reset hover when state changes
            isOverlayHovered = false

            // Show checkmark briefly when transitioning to routing
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

    // MARK: - Warmup Status Message

    /// Contextual message based on how long warmup has been running
    private var warmupStatusMessage: String {
        guard let startTime = whisperService.warmupStartTime else {
            return "Model warming up..."
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Heuristics based on elapsed time
        if elapsed < 15 {
            return "Warming up model... ~1-2 min"
        } else if elapsed < 45 {
            return "Still warming up... almost there"
        } else if elapsed < 90 {
            return "Should be ready soon..."
        } else {
            return "Almost ready, hang tight"
        }
    }

    // Silent mic warning - polite, non-alarming, with fix action
    private var silentMicWarning: some View {
        Button(action: {
            AudioTroubleshooterController.shared.show()
        }) {
            HStack(spacing: 6) {
                // Softer mic icon - more friendly and less alarming
                Image(systemName: "mic.badge.questionmark")
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
        let baseWidth = CGFloat(overlayTuning.overlayWidth)
        switch controller.state {
        case .listening: return baseWidth
        case .transcribing:
            // Wider if showing warmup message
            return whisperService.isWarmingUp ? 160 : 56
        case .routing: return 56  // Same as transcribing - dots collapse, no size change
        case .idle: return baseWidth
        }
    }

    private var processingHeight: CGFloat {
        let baseHeight = CGFloat(overlayTuning.overlayHeight)
        switch controller.state {
        case .listening: return baseHeight
        case .transcribing:
            // Taller if showing warmup message
            return whisperService.isWarmingUp ? 48 : 24
        case .routing: return 24  // Same height
        case .idle: return baseHeight
        }
    }

    private var cornerRadiusForState: CGFloat {
        switch controller.state {
        case .listening: return CGFloat(overlayTuning.cornerRadius)
        case .transcribing, .routing: return 12  // Pill shape
        case .idle: return CGFloat(overlayTuning.cornerRadius)
        }
    }

    private var backgroundFill: Color {
        switch controller.state {
        case .listening:
            return Color(white: 0, opacity: overlayTuning.backgroundOpacity * 0.7)
        case .transcribing:
            // Cyan tint during warmup, orange otherwise
            if whisperService.isWarmingUp {
                return warmupCyan.opacity(0.1)
            }
            return processingOrange.opacity(0.08)
        case .routing:
            // Same as transcribing - neutral exit, no color change
            return processingOrange.opacity(0.08)
        case .idle:
            return Color.clear
        }
    }

    private var borderColor: Color {
        switch controller.state {
        case .listening:
            return TalkieTheme.textSecondary.opacity(0.1)
        case .transcribing:
            return processingOrange.opacity(0.25)
        case .routing:
            // Same as transcribing - neutral exit
            return processingOrange.opacity(0.25)
        case .idle:
            return Color.clear
        }
    }
}

// MARK: - Processing Dots (simple ellipsis animation)

struct ProcessingDotsView: View {
    let tint: Color
    @State private var animationPhase: Int = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(tint.opacity(dotOpacity(for: i)))
                    .frame(width: 3, height: 3)
            }
        }
        .onAppear {
            // Cycle through dots with smooth animation
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
        // animationPhase 0: all dim, 1: first bright, 2: second bright, 3: third bright
        if animationPhase == 0 {
            return 0.4
        }
        return index == (animationPhase - 1) ? 1.0 : 0.4
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
                        let baseOpacity = 0.45
                        let breathOpacity = sin(time * 1.2 + Double(i) * 0.5) * 0.15
                        let flowOpacity = sin(phase * 1.5) * 0.1
                        let opacity = baseOpacity + breathOpacity + flowOpacity

                        let rect = CGRect(
                            x: x - particleSize / 2,
                            y: y - particleSize / 2,
                            width: particleSize,
                            height: particleSize
                        )
                        // Use white to match main particle color
                        context.fill(Circle().path(in: rect), with: .color(TalkieTheme.textSecondary.opacity(max(0.25, min(0.75, opacity)))))
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
                        let glowOpacity = 0.06 + sin(time * 0.8) * 0.02

                        let rect = CGRect(
                            x: x - glowSize / 2,
                            y: y - glowSize / 2,
                            width: glowSize,
                            height: glowSize
                        )
                        context.fill(Circle().path(in: rect), with: .color(TalkieTheme.textSecondary.opacity(glowOpacity)))
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
                .foregroundColor(TalkieTheme.textSecondary.opacity(isHovered ? 0.9 : 0.4))
                .padding(6)
                .background(
                    Circle()
                        .fill(TalkieTheme.textSecondary.opacity(isHovered ? 0.15 : 0))
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
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
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared
    @ObservedObject private var tuning = ParticleTuning.shared
    @State private var smoothedLevel: CGFloat = 0.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2

                // Apply input sensitivity to the raw audio level
                let rawLevel = CGFloat(audioMonitor.level) * CGFloat(tuning.inputSensitivity)
                let targetLevel = min(1.0, rawLevel)  // Clamp to prevent crazy values

                // Use tuning values, with calm mode applying a reduction factor
                let calmFactor = calm ? 0.7 : 1.0
                let smoothingFactor = tuning.smoothingFactor * calmFactor
                let level = max(0.2, smoothedLevel)

                // Particle count from tuning
                let particleCount = calm ? Int(Double(tuning.particleCount) * 0.9) : tuning.particleCount

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749

                    // X position: constant speed flow from tuning
                    let baseSpeed = tuning.baseSpeed * calmFactor
                    let speedVar = (seed.truncatingRemainder(dividingBy: 1.0)) * tuning.speedVariation
                    let speed = baseSpeed + speedVar
                    let xProgress = (time * speed + seed).truncatingRemainder(dividingBy: 1.0)
                    let x = CGFloat(xProgress) * size.width

                    // Y position: sine-wave motion with tuned parameters
                    let baseAmp = tuning.baseAmplitude * calmFactor
                    let audioAmp = tuning.audioAmplitude * calmFactor
                    let waveAmplitude = baseAmp + Double(level) * audioAmp

                    let waveSpd = tuning.waveSpeed * calmFactor
                    let primaryWave = sin(time * waveSpd + seed * 4) * waveAmplitude
                    let secondaryWave = sin(time * (waveSpd * 0.6) + seed * 6) * waveAmplitude * 0.3

                    // Small vertical offset per particle
                    let laneOffset = (Double(i % 10) / 10.0 - 0.5) * 0.3
                    let y = centerY + CGFloat((primaryWave + secondaryWave + laneOffset) * Double(centerY) * 0.7)

                    // Size from tuning - particles grow with audio level
                    let baseSize = CGFloat(tuning.baseSize)
                    let levelBonus = level * 4.0  // Stronger size response to audio
                    let sizeVariation = CGFloat(0.5 + sin(seed * 5) * 0.5)  // 0.0-1.0 range
                    let particleSize = baseSize + levelBonus * sizeVariation

                    // Opacity from tuning
                    let opacity = tuning.baseOpacity + Double(level) * 0.35 * (0.6 + sin(seed * 3) * 0.4)

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(TalkieTheme.textSecondary.opacity(opacity)))
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
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared
    @ObservedObject private var tuning = WaveformTuning.shared
    @State private var barLevels: [CGFloat] = Array(repeating: 0.1, count: 48)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let barCount = tuning.barCount
                let gap = CGFloat(tuning.barGap)
                let barWidth: CGFloat = (size.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount)
                let maxBarHeight = size.height * CGFloat(tuning.maxHeightRatio)
                let centerY = size.height / 2

                // Apply input sensitivity to the raw audio level
                let rawLevel = min(1.0, CGFloat(audioMonitor.level) * CGFloat(tuning.inputSensitivity))

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
                    let minHeight: CGFloat = sensitive ? CGFloat(tuning.minBarHeight) * 2 : CGFloat(tuning.minBarHeight)
                    let barHeight = max(minHeight, barLevel * maxBarHeight)

                    // Draw bar centered vertically
                    let barRect = CGRect(
                        x: x,
                        y: centerY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )

                    // Color/opacity
                    let baseOpacity = sensitive ? tuning.baseOpacity * 1.25 : tuning.baseOpacity
                    let opacity = baseOpacity + Double(barLevel) * tuning.levelOpacityBoost
                    context.fill(
                        RoundedRectangle(cornerRadius: CGFloat(tuning.cornerRadius)).path(in: barRect),
                        with: .color(TalkieTheme.textSecondary.opacity(opacity))
                    )
                }

                // Update bar levels with audio - shift left and add new value
                // Note: DispatchQueue.main.async is needed here for smooth 60fps updates
                DispatchQueue.main.async {
                    // Resize array if needed
                    var newLevels = currentLevels.count == barCount ? currentLevels : Array(repeating: 0.1, count: barCount)
                    // Shift bars left
                    for i in 0..<(barCount - 1) {
                        newLevels[i] = newLevels[i + 1]
                    }
                    // Add new level on right with some smoothing
                    let smoothFactor: CGFloat = sensitive ? CGFloat(tuning.smoothingFactor) * 1.2 : CGFloat(tuning.smoothingFactor)
                    let lastLevel = barCount > 0 ? newLevels[barCount - 1] : 0.1
                    let smoothed = lastLevel * (1 - smoothFactor) + targetLevel * smoothFactor
                    if barCount > 0 {
                        newLevels[barCount - 1] = smoothed
                    }
                    barLevels = newLevels
                }
            }
        }
    }
}

#Preview {
    RecordingOverlayView()
        .environmentObject(RecordingOverlayController.shared)
        .frame(width: 400, height: 56)
        .padding()
}
