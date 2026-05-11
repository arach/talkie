//
//  VoiceCommandOverlay.swift
//  Talkie
//
//  Overlay for voice command capture and intent recognition.
//  Features particle-based visualization that responds to audio and state.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Voice Command State

enum VoiceCommandState: Equatable {
    case idle
    case recording
    case processing
    case result(IntentResult)
    case navigating(VoiceIntent)
    case error(String)
    case dismissed
}

// MARK: - Particle

struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var velocity: CGPoint
    var hue: Double
}

// MARK: - Particle System View

struct ParticleSystemView: View {
    let state: VoiceCommandState
    let audioLevel: Float

    @State private var particles: [Particle] = []

    private let particleCount = 40
    private let centerX: CGFloat = 150
    private let centerY: CGFloat = 80

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.x - particle.size / 2,
                        y: particle.y - particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )

                    let color = Color(
                        hue: particle.hue,
                        saturation: 0.7,
                        brightness: 0.9,
                        opacity: particle.opacity
                    )

                    context.fill(
                        Circle().path(in: rect),
                        with: .color(color)
                    )
                }
            }
            .onChange(of: timeline.date) { _, _ in
                updateParticles()
            }
        }
        .frame(width: 300, height: 160)
        .onAppear {
            initializeParticles()
        }
        .onChange(of: state) { _, newState in
            handleStateChange(newState)
        }
    }

    private func initializeParticles() {
        particles = (0..<particleCount).map { _ in
            let angle = Double.random(in: 0...(2 * .pi))
            let radius = CGFloat.random(in: 20...60)
            return Particle(
                x: centerX + cos(angle) * radius,
                y: centerY + sin(angle) * radius,
                size: CGFloat.random(in: 3...8),
                opacity: Double.random(in: 0.4...0.8),
                velocity: CGPoint(
                    x: CGFloat.random(in: -0.5...0.5),
                    y: CGFloat.random(in: -0.5...0.5)
                ),
                hue: 0.6 // Blue
            )
        }
    }

    private func updateParticles() {
        let level = CGFloat(audioLevel)

        for i in particles.indices {
            var p = particles[i]

            switch state {
            case .recording:
                // Gentle floating, responsive to audio
                let audioInfluence = level * 2
                let angle = atan2(p.y - centerY, p.x - centerX)
                let distance = hypot(p.x - centerX, p.y - centerY)

                // Breathe in/out with audio
                let targetRadius: CGFloat = 40 + audioInfluence * 30
                let radiusDiff = targetRadius - distance

                p.x += cos(angle) * radiusDiff * 0.05 + p.velocity.x
                p.y += sin(angle) * radiusDiff * 0.05 + p.velocity.y

                // Gentle orbit
                let orbitSpeed: CGFloat = 0.01
                let newAngle = angle + orbitSpeed
                p.x = centerX + cos(newAngle) * distance + p.velocity.x
                p.y = centerY + sin(newAngle) * distance + p.velocity.y

                p.size = CGFloat.random(in: 3...6) + level * 4
                p.opacity = 0.5 + Double(level) * 0.4
                p.hue = 0.55 + Double(level) * 0.1 // Blue to cyan

            case .processing:
                // Stormy acceleration - particles swirl inward
                let angle = atan2(p.y - centerY, p.x - centerX)
                let distance = hypot(p.x - centerX, p.y - centerY)

                // Fast orbit
                let orbitSpeed: CGFloat = 0.08 + CGFloat.random(in: -0.02...0.02)
                let newAngle = angle + orbitSpeed

                // Pull toward center
                let pullStrength: CGFloat = 0.03
                let newDistance = max(10, distance - pullStrength * distance)

                p.x = centerX + cos(newAngle) * newDistance
                p.y = centerY + sin(newAngle) * newDistance

                // Add chaos
                p.x += CGFloat.random(in: -2...2)
                p.y += CGFloat.random(in: -2...2)

                p.size = CGFloat.random(in: 2...5)
                p.opacity = Double.random(in: 0.6...1.0)
                p.hue = Double.random(in: 0.05...0.15) // Orange/amber

            case .result(let result):
                // Calm settling, color based on success
                let angle = atan2(p.y - centerY, p.x - centerX)
                let distance = hypot(p.x - centerX, p.y - centerY)

                let targetRadius: CGFloat = result.isActionable ? 50 : 30
                let radiusDiff = targetRadius - distance

                p.x += cos(angle) * radiusDiff * 0.1
                p.y += sin(angle) * radiusDiff * 0.1

                // Slow orbit
                let orbitSpeed: CGFloat = 0.005
                let newAngle = angle + orbitSpeed
                p.x = centerX + cos(newAngle) * distance
                p.y = centerY + sin(newAngle) * distance

                p.size = CGFloat.random(in: 4...7)
                p.opacity = 0.8
                p.hue = result.isActionable ? 0.35 : 0.08 // Green or orange

            case .navigating:
                // Particles stream toward edge (like going somewhere)
                p.x += 3 + CGFloat.random(in: 0...2)
                p.velocity.x += 0.1
                p.opacity = max(0, p.opacity - 0.02)
                p.hue = 0.55 // Blue

                // Respawn particles that exit
                if p.x > 300 || p.opacity <= 0 {
                    p.x = CGFloat.random(in: 0...100)
                    p.y = centerY + CGFloat.random(in: -30...30)
                    p.opacity = 0.8
                }

            case .error:
                // Settle inward, red hue
                let angle = atan2(p.y - centerY, p.x - centerX)
                let distance = hypot(p.x - centerX, p.y - centerY)
                let targetRadius: CGFloat = 25
                let radiusDiff = targetRadius - distance
                p.x += cos(angle) * radiusDiff * 0.05
                p.y += sin(angle) * radiusDiff * 0.05
                p.size = CGFloat.random(in: 3...5)
                p.opacity = max(0.3, p.opacity - 0.01)
                p.hue = 0.0 // Red

            case .idle, .dismissed:
                // Fade out
                p.opacity = max(0, p.opacity - 0.02)
            }

            particles[i] = p
        }
    }

    private func handleStateChange(_ newState: VoiceCommandState) {
        // Reset particles for dramatic state changes
        if case .processing = newState {
            // Burst outward then swirl in
            for i in particles.indices {
                let angle = Double.random(in: 0...(2 * .pi))
                particles[i].velocity = CGPoint(
                    x: cos(angle) * 3,
                    y: sin(angle) * 3
                )
            }
        }
    }
}

// MARK: - Voice Command Overlay

struct VoiceCommandOverlay: View {
    @State private var state: VoiceCommandState = .idle
    @State private var audioLevel: Float = 0
    @State private var result: IntentResult?
    @State private var levelTimer: Timer?
    @State private var overlayOffset: CGFloat = 0
    @State private var overlayScale: CGFloat = 1
    @State private var overlayOpacity: Double = 1
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Dimmed background (theme-aware)
            SettingsManager.shared.modalBackdrop.opacity(backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    cancel()
                }
                .animation(.easeOut(duration: 0.3), value: state)

            // Main content
            VStack(spacing: 0) {
                if isToastMode {
                    Spacer()
                    toastView
                        .padding(.top, 60)
                    Spacer()
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                        .frame(height: 80)
                    modalView
                    Spacer()
                }
            }
            .scaleEffect(overlayScale)
            .opacity(overlayOpacity)
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.return) {
            handleReturn()
            return .handled
        }
        .onKeyPress(.escape) {
            cancel()
            return .handled
        }
        .onAppear {
            startRecording()
            isFocused = true
        }
        .onDisappear {
            cleanup()
        }
    }

    // MARK: - Modal View (Recording/Processing/Result)

    private var modalView: some View {
        VStack(spacing: 20) {
            // Particle visualization
            ParticleSystemView(state: state, audioLevel: audioLevel)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            // Status text
            Text(statusText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)

            // Result display
            if let result = result {
                resultView(result)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Error display
            if case .error(let message) = state {
                VStack(spacing: 4) {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Action hint
            Text(actionHint)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(24)
        .frame(width: 350)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: borderColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Toast View (Navigating)

    private var toastView: some View {
        HStack(spacing: 12) {
            Image(systemName: destinationIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text(destinationText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.accentColor)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Result View

    private func resultView(_ result: IntentResult) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: result.isActionable ? "checkmark.circle.fill" : "questionmark.circle.fill")
                    .foregroundColor(result.isActionable ? .green : .orange)
                    .font(.system(size: 20))

                Text(result.intent.displayName)
                    .font(.system(size: 18, weight: .semibold))
            }

            Text("\"\(result.rawText)\"")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Computed Properties

    private var isToastMode: Bool {
        if case .navigating = state { return true }
        return false
    }

    private var backgroundOpacity: Double {
        switch state {
        case .navigating: return 0.2
        case .dismissed: return 0
        default: return 0.5
        }
    }

    private var borderColors: [Color] {
        switch state {
        case .recording:
            return [.blue.opacity(0.5), .cyan.opacity(0.3)]
        case .processing:
            return [.orange.opacity(0.6), .yellow.opacity(0.4)]
        case .result(let r):
            return r.isActionable
                ? [.green.opacity(0.5), .mint.opacity(0.3)]
                : [.orange.opacity(0.5), .yellow.opacity(0.3)]
        case .error:
            return [.red.opacity(0.5), .orange.opacity(0.3)]
        default:
            return [.white.opacity(0.2), .white.opacity(0.1)]
        }
    }

    private var statusText: String {
        switch state {
        case .idle: return "Initializing..."
        case .recording: return "Listening..."
        case .processing: return "Understanding..."
        case .result(let r): return r.isActionable ? "Got it!" : "Didn't catch that"
        case .navigating(let intent): return "Going to \(intent.displayName)"
        case .error: return "Something went wrong"
        case .dismissed: return ""
        }
    }

    private var actionHint: String {
        switch state {
        case .recording: return "Press Return when done, Escape to cancel"
        case .result(let r) where r.isActionable: return "Press Return to go, Escape to cancel"
        case .result: return "Press Escape to dismiss"
        case .error: return "Press Escape to dismiss"
        default: return ""
        }
    }

    private var destinationIcon: String {
        if case .navigating(let intent) = state {
            switch intent {
            // Main Navigation
            case .navigateHome: return "house.fill"
            case .navigateRecordings: return "doc.text.fill"
            case .navigateDictations: return "waveform"
            case .navigateSettings: return "gear"
            case .navigateWorkflows: return "arrow.triangle.branch"
            case .navigateModels: return "cube.fill"
            case .navigateDrafts: return "doc.text.fill"
            case .navigateStats: return "chart.bar.fill"
            case .navigateActivityLog: return "list.bullet.rectangle"
            case .navigateSystemConsole: return "terminal"
            case .navigatePendingActions: return "clock.arrow.circlepath"
            case .navigateAIResults: return "bolt.fill"

            // Settings Subsections
            case .settingsAppearance: return "paintbrush.fill"
            case .settingsHelpers: return "gearshape.2.fill"
            case .settingsVoiceIO: return "mic.fill"
            case .settingsDictionary: return "text.book.closed.fill"
            case .settingsAIProviders: return "key.fill"
            case .settingsModels: return "cpu.fill"
            case .settingsStorage: return "internaldrive.fill"
            case .settingsSync: return "arrow.triangle.2.circlepath"
            case .settingsActions: return "bolt.fill"
            case .settingsAutomations: return "gearshape.arrow.triangle.2.circlepath"
            case .settingsExtensions: return "puzzlepiece.extension.fill"
            case .settingsPermissions: return "lock.shield.fill"
            case .settingsDebug: return "ant.fill"

            // Actions
            case .openSearch: return "magnifyingglass"
            case .openCommandPalette: return "command"
            case .goBack: return "arrow.left"
            case .startDictation: return "mic.fill"
            case .stopDictation: return "stop.fill"
            case .syncNow: return "arrow.triangle.2.circlepath"
            case .unknown: return "questionmark"
            }
        }
        return "arrow.right"
    }

    private var destinationText: String {
        if case .navigating(let intent) = state {
            return intent.displayName
        }
        return "Navigating..."
    }

    // MARK: - Actions

    private func startRecording() {
        log.info("[VoiceCmd] Step 1: startRecording() called")
        // Small delay to ensure any previous audio session is fully released
        Task {
            try? await Task.sleep(for: .milliseconds(50))

            await MainActor.run {
                do {
                    log.info("[VoiceCmd] Step 2: Calling VoiceCommandService.startCapture()")
                    try VoiceCommandService.shared.startCapture()
                    log.info("[VoiceCmd] Step 3: startCapture() succeeded, state → recording")
                    withAnimation(.easeOut(duration: 0.3)) {
                        state = .recording
                    }

                    // Poll audio level
                    levelTimer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in
                        Task { @MainActor in
                            audioLevel = VoiceCommandService.shared.audioLevel
                        }
                    }
                } catch {
                    log.error("[VoiceCmd] Step 2 FAILED: startCapture() error: \(error.localizedDescription)")
                    let message = userFacingMessage(for: error)
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.state = .error(message)
                    }
                }
            }
        }
    }

    private func stopRecording() {
        log.info("[VoiceCmd] Step 4: stopRecording() called")
        levelTimer?.invalidate()
        levelTimer = nil

        withAnimation(.easeOut(duration: 0.2)) {
            state = .processing
        }

        Task {
            do {
                log.info("[VoiceCmd] Step 5: Calling stopAndRecognize()")
                let intentResult = try await withThrowingTaskGroup(of: IntentResult.self) { group in
                    group.addTask {
                        try await VoiceCommandService.shared.stopAndRecognize()
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(10))
                        throw VoiceCommandError.recognitionFailed("Timed out — the embedded engine may not be responding")
                    }
                    guard let result = try await group.next() else {
                        throw VoiceCommandError.recognitionFailed("Recognition task returned no result")
                    }
                    group.cancelAll()
                    return result
                }
                log.info("[VoiceCmd] Step 6: Got result - intent=\(intentResult.intent.rawValue) confidence=\(String(format: "%.2f", intentResult.confidence)) actionable=\(intentResult.isActionable)")
                await MainActor.run {
                    self.result = intentResult
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        self.state = .result(intentResult)
                    }
                }

                // Auto-execute if high confidence (threshold is configurable)
                let threshold = Float(SettingsManager.shared.voiceCommandConfidenceThreshold)
                let shouldAutoExecute = intentResult.isActionable && intentResult.confidence >= threshold
                log.info("[VoiceCmd] Step 7: Auto-execute check: \(shouldAutoExecute) (threshold: \(threshold))")
                if shouldAutoExecute {
                    try? await Task.sleep(for: .milliseconds(600))
                    await MainActor.run {
                        executeNavigation(intentResult)
                    }
                }
            } catch {
                log.error("[VoiceCmd] Step 5 FAILED: stopAndRecognize() error: \(error.localizedDescription)")
                await MainActor.run {
                    let message = userFacingMessage(for: error)
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.state = .error(message)
                    }
                }
                // Auto-dismiss after a few seconds
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }

    private func handleReturn() {
        switch state {
        case .recording:
            stopRecording()
        case .result(let r) where r.isActionable:
            executeNavigation(r)
        default:
            break
        }
    }

    private func executeNavigation(_ result: IntentResult) {
        log.info("[VoiceCmd] Step 8: executeNavigation() called for intent=\(result.intent.rawValue)")
        let intent = result.intent

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            state = .navigating(intent)
        }

        // Navigate after brief delay for animation
        Task {
            try? await Task.sleep(for: .milliseconds(300))

            await MainActor.run {
                log.info("[VoiceCmd] Step 9: Calling NavigationState.handleVoiceNavigation()")
                NavigationState.shared.handleVoiceNavigation(
                    intent: intent.rawValue,
                    rawText: result.rawText
                )
                log.info("[VoiceCmd] Step 10: Navigation complete, dismissing in 1.2s")
            }

            // Dismiss after navigation
            try? await Task.sleep(for: .milliseconds(1200))
            await MainActor.run {
                log.info("[VoiceCmd] Step 11: Dismissing overlay")
                dismiss()
            }
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        let desc = error.localizedDescription
        if desc.contains("helper application") || desc.contains("XPC") {
            return "TalkieAgent isn't running, so the embedded engine is unavailable"
        }
        if desc.contains("audioTooShort") || desc.contains("too short") {
            return "Recording was too short — try holding longer"
        }
        return "Voice command failed — try again"
    }

    private func cancel() {
        VoiceCommandService.shared.cancel()
        dismiss()
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            state = .dismissed
            overlayOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            SettingsManager.shared.isVoiceCommandPresented = false
        }
    }

    private func cleanup() {
        levelTimer?.invalidate()
        levelTimer = nil
        if case .recording = state {
            VoiceCommandService.shared.cancel()
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        VoiceCommandOverlay()
    }
}
