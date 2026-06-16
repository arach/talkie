//
//  MacRecordingView.swift
//  Talkie
//
//  Recording interface for creating memos from Mac
//  Simple, focused UI: record → transcribe → save as memo
//

import SwiftUI
import TalkieKit

// Recording red - matches iOS Color.recording (#FF3B30)
private let recordingRed = Color(red: 1.0, green: 0.231, blue: 0.188)
private let recordingGlow = Color(red: 1.0, green: 0.271, blue: 0.227)

struct MacRecordingView: View {
    var onDismiss: (() -> Void)?
    var onMemoCreated: ((UUID) async -> Void)?  // Async callback with new memo ID
    private let controller = MemoRecordingController.shared

    // Track last recorded memo for quick access link
    @State private var lastRecordedMemo: MemoModel?

    // Support both sheet and embedded modes
    @Environment(\.dismiss) private var environmentDismiss

    private func dismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            environmentDismiss()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: { handleClose() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("Recordings")
                            .font(Theme.current.fontSM)
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            // Page title
            HStack {
                PageHeader("Record")
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)

            // Main content - centered
            Spacer()

            VStack(spacing: Spacing.xl) {
                // Waveform visualization
                waveformView

                // Timer
                timerView
            }

            Spacer()

            // Action area
            VStack(spacing: Spacing.md) {
                mainActionButton

                // Hint text (only when idle)
                if case .idle = controller.state {
                    Text("Space to record · Space to stop")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.background)
        .onChange(of: controller.state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onKeyPress(.space) {
            handleSpaceKey()
            return .handled
        }
    }

    // MARK: - Waveform View

    // Expand waveform when recording or processing
    private var isExpanded: Bool {
        controller.state.isRecording || controller.state.isProcessing || controller.allStepsComplete
    }

    // Even more height for processing pipeline
    private var waveformHeight: CGFloat {
        if controller.state.isProcessing || controller.allStepsComplete {
            return 160  // Taller to fit pipeline steps
        }
        return isExpanded ? 120 : 80
    }

    private var waveformView: some View {
        // Glass pane container for the waveform - like a music device display
        ZStack {
            // Waveform content
            waveformContent
        }
        .frame(maxWidth: isExpanded ? .infinity : 400)
        .frame(height: waveformHeight)
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Theme.current.surface1.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, Spacing.lg)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
    }

    @ViewBuilder
    private var waveformContent: some View {
        if controller.state.isProcessing || controller.allStepsComplete {
            // Processing/Complete state: show pipeline steps
            processingPipelineView
        } else if case .error = controller.state {
            // Error state: warning
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.red)
        } else {
            // Idle / Preparing / Recording: live waveform bars - full width.
            // Recording is red; preparing borrows the accent for an
            // anticipatory "warming up" read; idle stays muted.
            LiveWaveformBars(
                audioLevel: controller.audioLevel,
                activity: controller.state.isRecording ? .recording
                    : controller.state.isPreparing ? .preparing : .idle,
                color: controller.state.isRecording ? recordingRed
                    : controller.state.isPreparing ? Theme.current.accent
                    : Theme.current.foregroundSecondary
            )
        }
    }

    /// Processing pipeline showing each step with status
    private var processingPipelineView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(controller.processingSteps) { step in
                HStack(spacing: Spacing.sm) {
                    // Status icon
                    stepStatusIcon(step.status)
                        .frame(width: 16, height: 16)

                    // Title
                    Text(step.title)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(stepTitleColor(step.status))

                    // Subtitle (path, word count, etc.)
                    if let subtitle = step.subtitle {
                        Text(subtitle)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
    }

    @ViewBuilder
    private func stepStatusIcon(_ status: ProcessingStep.StepStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .strokeBorder(Theme.current.foregroundMuted.opacity(0.3), lineWidth: 1.5)
        case .inProgress:
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.red)
        }
    }

    private func stepTitleColor(_ status: ProcessingStep.StepStatus) -> Color {
        switch status {
        case .pending: return Theme.current.foregroundMuted
        case .inProgress: return Theme.current.foreground
        case .completed: return Theme.current.foreground
        case .failed: return .red
        }
    }

    // MARK: - Timer View

    private var timerView: some View {
        VStack(spacing: Spacing.xs) {
            Text(formatTime(controller.elapsedTime))
                .font(.system(size: 48, weight: .ultraLight, design: .monospaced))
                .foregroundColor(Theme.current.foreground)
                .monospacedDigit()

            if let message = controller.captureStatusMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Main Action Button

    @ViewBuilder
    private var mainActionButton: some View {
        switch controller.state {
        case .idle:
            VStack(spacing: Spacing.lg) {
                // Record button - matches iOS ActionDock style
                Button(action: { controller.startRecording() }) {
                    ZStack {
                        // Main button - Apple red
                        Circle()
                            .fill(recordingRed)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .strokeBorder(recordingGlow.opacity(0.4), lineWidth: 1)
                            )

                        // Mic icon
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                // Show link to last recorded memo
                if let memo = lastRecordedMemo {
                    Button(action: { navigateToMemo(memo) }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("View last recording")
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .font(Theme.current.fontXS)
                    }
                    .buttonStyle(.plain)
                }
            }

        case .preparing:
            VStack(spacing: Spacing.sm) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(recordingRed)
                Text("Preparing…")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

        case .recording:
            HStack(spacing: Spacing.lg) {
                // Cancel
                Button(action: { controller.cancelRecording() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 44, height: 44)
                        .background(Theme.current.surface1)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Stop button - matches iOS RecordingView style
                Button(action: { controller.stopRecording() }) {
                    ZStack {
                        // Subtle glow while recording
                        Circle()
                            .fill(recordingRed)
                            .frame(width: 76, height: 76)
                            .blur(radius: 20)
                            .opacity(0.5)

                        // Outer ring
                        Circle()
                            .strokeBorder(recordingRed, lineWidth: 3)
                            .frame(width: 70, height: 70)

                        // Stop icon - rounded square
                        RoundedRectangle(cornerRadius: 4)
                            .fill(recordingRed)
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)

                // Spacer to balance
                Color.clear.frame(width: 44, height: 44)
            }

        case .processing:
            // Show status while processing
            if controller.allStepsComplete {
                // All done - show action buttons
                completeActionButtons
            } else {
                // Still processing - show current step
                VStack(spacing: Spacing.xs) {
                    if let currentStep = controller.processingSteps.first(where: {
                        if case .inProgress = $0.status { return true }
                        return false
                    }) {
                        Text(currentStep.title)
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
            }

        case .complete(let memo):
            // Complete state - show action buttons
            completeActionButtons

        case .error:
            Button(action: { controller.reset() }) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(Theme.current.fontSMMedium)
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Color.red.opacity(0.8))
                .cornerRadius(CornerRadius.md)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Complete Action Buttons

    private var completeActionButtons: some View {
        HStack(spacing: Spacing.md) {
            // Continue recording
            Button(action: { controller.reset() }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                    Text("Record Another")
                }
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.md)
            }
            .buttonStyle(.plain)

            // View recording
            Button(action: { viewCompletedMemo() }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                    Text("View Recording")
                }
                .font(Theme.current.fontSMMedium)
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Color.green)
                .cornerRadius(CornerRadius.md)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func viewCompletedMemo() {
        if case .complete(let memo) = controller.state {
            lastRecordedMemo = memo
            dismiss()
            controller.reset()
            NavigationState.shared.navigateToMemo(memo.id)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    private func handleSpaceKey() {
        switch controller.state {
        case .idle:
            controller.startRecording()
        case .recording:
            controller.stopRecording()
        default:
            break
        }
    }

    private func handleClose() {
        if controller.state.isRecording {
            controller.cancelRecording()
        }
        controller.reset()
        dismiss()
    }

    private func handleStateChange(from oldState: MemoRecordingController.RecordingState, to newState: MemoRecordingController.RecordingState) {
        if case .complete(let memo) = newState {
            // Store reference to last recorded memo
            lastRecordedMemo = memo
            // No auto-dismiss - user chooses to view or record another
        }
    }

    private func navigateToMemo(_ memo: MemoModel) {
        dismiss()
        controller.reset()
        NavigationState.shared.navigateToMemo(memo.id)
    }
}

// MARK: - Sheet Presentation Helper

struct MacRecordingSheet: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                MacRecordingView()
                    .frame(width: 400, height: 450)
            }
    }
}

extension View {
    func macRecordingSheet(isPresented: Binding<Bool>) -> some View {
        modifier(MacRecordingSheet(isPresented: isPresented))
    }
}

// MARK: - Live Waveform Bars

/// Real-time audio level visualization - fills available width.
///
/// Three activities drive the look:
///   - `.idle`      — dormant: a calm low drift so the strip looks alive at rest.
///   - `.preparing` — spinning up: an anticipatory pulse sweeps across while the
///                    recorder warms up. Honest "getting ready" motion with no
///                    claim of real audio — never reads as active recording.
///   - `.recording` — live: audio history scrolls in from the right; a faint
///                    ambient ripple keeps quiet moments from flatlining.
///
/// Motion is deterministic and timer-free: the traveling ripple is derived
/// from the TimelineView clock, and the whole strip renders in a single
/// `Canvas`, so there is no per-bar view churn.
struct LiveWaveformBars: View {
    enum Activity: Equatable {
        case idle
        case preparing
        case recording

        var isRecording: Bool { self == .recording }
    }

    let audioLevel: Float
    let activity: Activity
    let color: Color

    /// Convenience for the common two-state callers.
    init(audioLevel: Float, isRecording: Bool, color: Color) {
        self.audioLevel = audioLevel
        self.activity = isRecording ? .recording : .idle
        self.color = color
    }

    init(audioLevel: Float, activity: Activity, color: Color) {
        self.audioLevel = audioLevel
        self.activity = activity
        self.color = color
    }

    // Dynamic bar count based on available width
    private let barWidth: CGFloat = 3
    private let gap: CGFloat = 4
    @State private var barLevels: [CGFloat] = Array(repeating: 0.12, count: 80)
    /// Smoothed level used to drive a gentle scale pulse on the whole
    /// waveform — gives the strip an "alive" / breathing quality
    /// without per-bar randomness that reads as noise.
    @State private var envelope: CGFloat = 0.12

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let barCount = max(20, Int(availableWidth / (barWidth + gap)))

            TimelineView(.animation(minimumInterval: 0.033)) { timeline in
                // Phase comes straight from the animation clock so the
                // traveling ripple is deterministic — no stored timer, no
                // randomness — and resolves identically on every frame.
                let phase = timeline.date.timeIntervalSinceReferenceDate

                Canvas { context, size in
                    let totalWidth = CGFloat(barCount) * (barWidth + gap) - gap
                    let startX = (size.width - totalWidth) / 2
                    // Taller bars overall — was 0.85, the old cap left
                    // dead space top + bottom even on loud signals.
                    let maxHeight = size.height * 0.96
                    let centerY = size.height / 2
                    let lastIndex = Double(max(1, barCount - 1))

                    for i in 0..<barCount {
                        let x = startX + CGFloat(i) * (barWidth + gap)

                        // Center-weighted spatial envelope: the strip reads as
                        // a single intentional shape — fuller in the middle,
                        // tapering toward the ends — instead of a flat block.
                        let position = Double(i) / lastIndex
                        let shape = CGFloat(0.40 + 0.60 * sin(position * .pi))

                        // Deterministic traveling ripple. Two sines at
                        // different speeds + wavelengths beat against each
                        // other so the shimmer reads organic, never a single
                        // obvious pulse. Travels leftward, matching the audio
                        // history scroll direction.
                        let wave = sin(phase * 2.3 + Double(i) * 0.55) * 0.6
                                 + sin(phase * 0.9 + Double(i) * 0.23) * 0.4
                        let ripple = CGFloat(wave * 0.5 + 0.5)   // 0...1

                        // Audio history — newest level scrolls in from the right.
                        let audioBar = barLevels[i % barLevels.count]

                        let level: CGFloat
                        let opacity: Double
                        switch activity {
                        case .recording:
                            // Real audio leads; a faint ambient ripple fills the
                            // quiet so the strip never collapses to a dead line.
                            let ambient = (0.045 + envelope * 0.05) * ripple
                            level = max(audioBar, ambient) * shape
                            opacity = 0.45 + Double(min(1, level)) * 0.55
                        case .preparing:
                            // Anticipatory sweep — squaring the ripple sharpens
                            // it into a soft crest that travels across the strip.
                            let sweep = ripple * ripple
                            level = (0.16 + 0.34 * sweep) * shape
                            opacity = 0.32 + 0.46 * Double(sweep)
                        case .idle:
                            // Dormant: a low calm drift — alive but at rest.
                            level = (0.10 + 0.07 * ripple) * shape
                            opacity = 0.20 + 0.10 * Double(ripple)
                        }

                        // Bar height
                        let minHeight: CGFloat = 3
                        let barHeight = max(minHeight, level * maxHeight)

                        // Draw bar centered vertically
                        let barRect = CGRect(
                            x: x,
                            y: centerY - barHeight / 2,
                            width: barWidth,
                            height: barHeight
                        )

                        context.fill(
                            RoundedRectangle(cornerRadius: barWidth / 2).path(in: barRect),
                            with: .color(color.opacity(opacity))
                        )
                    }
                }
                .onChange(of: timeline.date) { _, _ in
                    updateBars(count: barCount)
                }
            }
        }
        // Subtle whole-wave breathing — vertical scale ranges roughly
        // 0.94 → 1.10 with the smoothed envelope. The strip expands
        // with louder voice and settles when you go quiet.
        .scaleEffect(x: 1.0, y: 0.94 + envelope * 0.16, anchor: .center)
        .animation(.easeOut(duration: 0.12), value: envelope)
        .onAppear {
            // Initialize with idle state
            barLevels = Array(repeating: 0.12, count: 80)
            envelope = 0.12
        }
    }

    private func updateBars(count: Int) {
        // Only real recording feeds the history buffer; idle/preparing hold a
        // quiet baseline so the buffer is clean when capture actually begins.
        // Lighter compression than before (was pow(x, 0.5)) so the bars swing
        // with voice volume instead of squashing toward a single mid-level.
        let rawLevel = CGFloat(audioLevel)
        let baseline: CGFloat = 0.10
        let targetLevel: CGFloat = activity.isRecording
            ? max(0.10, pow(rawLevel, 0.7))
            : baseline

        // Shift bars and add new value
        var newLevels = barLevels
        let effectiveCount = min(count, barLevels.count)
        for i in 0..<(effectiveCount - 1) {
            newLevels[i] = newLevels[i + 1]
        }
        if effectiveCount > 0 {
            newLevels[effectiveCount - 1] = targetLevel
        }

        barLevels = newLevels

        // Envelope follower for the whole-wave pulse. Asymmetric
        // attack / release: rises fast on louder input, decays slow
        // so the strip "breathes" rather than chattering.
        let target = activity.isRecording ? targetLevel : baseline
        if target > envelope {
            envelope += (target - envelope) * 0.35
        } else {
            envelope += (target - envelope) * 0.12
        }
    }
}

// MARK: - Preview

#Preview("Full Screen") {
    MacRecordingView(onDismiss: {})
        .frame(width: 600, height: 500)
}

#Preview("Sheet") {
    MacRecordingView()
        .frame(width: 400, height: 450)
}
