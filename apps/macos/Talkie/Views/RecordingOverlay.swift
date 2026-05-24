//
//  RecordingOverlay.swift
//  Talkie
//
//  Overlay component for recording and post-recording recap.
//  Sits on top of the recordings list, doesn't replace it.
//

import SwiftUI
import TalkieKit

// Recording red - matches iOS
private let recordingRed = Color(red: 1.0, green: 0.231, blue: 0.188)
private let recordingGlow = Color(red: 1.0, green: 0.271, blue: 0.227)

// MARK: - Recording Overlay

struct RecordingOverlay: View {
    let controller: MemoRecordingController
    var onDismiss: () -> Void
    var onMemoCreated: ((UUID) async -> Void)?
    var onNewRecording: () -> Void

    // Track if we've already called onMemoCreated for current recording
    @State private var didNotifyMemoCreated = false
    // Hover state for the card — drives the reveal of secondary
    // controls (cancel / stop) during recording so the surface is
    // quiet by default and acts only when the user moves the pointer
    // toward it.
    @State private var isHoveringCard = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Main content card
            VStack(spacing: Spacing.lg) {
                if controller.allStepsComplete, case .complete(let memo) = controller.state {
                    // Recap mode
                    recapContent(memo: memo)
                } else if controller.state.isProcessing {
                    // Processing mode
                    processingContent
                } else {
                    // Recording mode (idle or recording)
                    recordingContent
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 500)
            // Glass card: ultra-thin material below, theme tint on top
            // at low opacity. Surface1 alone reads as a solid panel;
            // the material layer carries the desktop blur so the card
            // sits on whatever is behind it instead of obscuring it.
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xl)
                            .fill(Theme.current.surface1.opacity(0.55))
                    )
                    .shadow(color: .black.opacity(0.32), radius: 40, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .onHover { isHoveringCard = $0 }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SettingsManager.shared.modalBackdropStandard
                .contentShape(Rectangle())
                .onTapGesture {
                    // Only dismiss on background tap if not actively recording
                    if !controller.state.isRecording && !controller.state.isProcessing {
                        controller.reset()
                        onDismiss()
                    }
                }
        )
        .onKeyPress(.space) {
            handleSpaceKey()
            return .handled
        }
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
        .onChange(of: controller.state) { _, newState in
            if case .complete(let memo) = newState, !didNotifyMemoCreated {
                didNotifyMemoCreated = true
                Task {
                    await onMemoCreated?(memo.id)
                }
            }
            // Reset flag when going back to idle
            if case .idle = newState {
                didNotifyMemoCreated = false
            }
        }
    }

    // MARK: - Recording Content

    private var recordingContent: some View {
        VStack(spacing: Spacing.xl) {
            // Waveform
            waveformView

            // Timer
            Text(formatTime(controller.elapsedTime))
                .font(.system(size: 48, weight: .ultraLight, design: .monospaced))
                .foregroundColor(Theme.current.foreground)
                .monospacedDigit()

            // Action buttons
            recordingButtons
        }
    }

    private var waveformView: some View {
        ZStack {
            LiveWaveformBars(
                audioLevel: controller.audioLevel,
                isRecording: controller.state.isRecording,
                color: controller.state.isRecording ? recordingRed : Theme.current.foregroundSecondary
            )
        }
        .frame(height: 80)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Theme.current.background.opacity(0.5))
        )
    }

    @ViewBuilder
    private var recordingButtons: some View {
        if case .idle = controller.state {
            VStack(spacing: Spacing.md) {
                // Record button
                Button(action: { controller.startRecording() }) {
                    ZStack {
                        Circle()
                            .fill(recordingRed)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .strokeBorder(recordingGlow.opacity(0.4), lineWidth: 1)
                            )
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                Text("Space to record · Space to stop · Esc to cancel")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        } else if case .recording = controller.state {
            // Two-row pattern: a tiny LIVE indicator always sits in
            // the row so the user knows recording is active even with
            // controls hidden; the cancel + stop buttons fade in on
            // card hover so the surface stays quiet between glances.
            HStack(spacing: Spacing.lg) {
                // Cancel
                Button(action: {
                    controller.cancelRecording()
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 44, height: 44)
                        .background(Theme.current.surface2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Stop button
                Button(action: { controller.stopRecording() }) {
                    ZStack {
                        Circle()
                            .fill(recordingRed)
                            .frame(width: 76, height: 76)
                            .blur(radius: 20)
                            .opacity(0.5)
                        Circle()
                            .strokeBorder(recordingRed, lineWidth: 3)
                            .frame(width: 70, height: 70)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(recordingRed)
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)

                Color.clear.frame(width: 44, height: 44)
            }
            // Hidden by default during recording — only the wave and
            // timer carry the active state. Hover the card to reveal
            // cancel + stop. Keyboard (space / esc) still works either
            // way so this is purely visual quietude.
            .opacity(isHoveringCard ? 1.0 : 0.0)
            .scaleEffect(isHoveringCard ? 1.0 : 0.96)
            .allowsHitTesting(isHoveringCard)
            .animation(.easeOut(duration: 0.18), value: isHoveringCard)
        }
    }

    // MARK: - Processing Content

    private var processingContent: some View {
        VStack(spacing: Spacing.lg) {
            // Pipeline steps
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(controller.processingSteps) { step in
                    HStack(spacing: Spacing.sm) {
                        stepStatusIcon(step.status)
                            .frame(width: 16, height: 16)
                        Text(step.title)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(stepTitleColor(step.status))
                        if let subtitle = step.subtitle {
                            Text(subtitle)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Theme.current.background.opacity(0.5))
            )

            // Status text
            if let currentStep = controller.processingSteps.first(where: {
                if case .inProgress = $0.status { return true }
                return false
            }) {
                Text(currentStep.title + "...")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
    }

    // MARK: - Recap Content

    private func recapContent(memo: MemoModel) -> some View {
        VStack(spacing: Spacing.lg) {
            // Success indicator with view CTA
            VStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                HStack(spacing: Spacing.sm) {
                    Text("Memo Saved")
                        .font(Theme.current.fontTitleMedium)
                        .foregroundColor(Theme.current.foreground)

                    Button(action: {
                        controller.reset()
                        onDismiss()
                        NavigationState.shared.navigateToMemo(memo.id)
                    }) {
                        HStack(spacing: 2) {
                            Text("View")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                        }
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }

            // Recap stats
            HStack(spacing: Spacing.lg) {
                recapStat(
                    icon: "waveform",
                    value: formatDuration(memo.duration),
                    label: "Duration"
                )

                if let transcription = memo.transcription, !transcription.isEmpty {
                    recapStat(
                        icon: "text.word.spacing",
                        value: "\(transcription.split(separator: " ").count)",
                        label: "Words"
                    )
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Theme.current.background.opacity(0.5))
            )

            // Action buttons
            HStack(spacing: Spacing.md) {
                // New recording
                Button(action: {
                    controller.reset()
                    onNewRecording()
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                        Text("New Memo")
                    }
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(Theme.current.surface2)
                    .cornerRadius(CornerRadius.md)
                }
                .buttonStyle(.plain)

                // Done - dismiss overlay
                Button(action: {
                    controller.reset()
                    onDismiss()
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12))
                        Text("Done")
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
    }

    private func recapStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foregroundMuted)
                Text(value)
                    .font(Theme.current.fontBodyMedium.monospacedDigit())
                    .foregroundColor(Theme.current.foreground)
            }
            Text(label)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepStatusIcon(_ status: ProcessingStep.StepStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .strokeBorder(Theme.current.foregroundMuted.opacity(0.3), lineWidth: 1.5)
        case .inProgress:
            BrailleSpinner(size: 10)
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
        case .inProgress, .completed: return Theme.current.foreground
        case .failed: return .red
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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

    private func handleEscape() {
        if controller.state.isRecording {
            controller.cancelRecording()
        }
        if case .idle = controller.state {
            onDismiss()
        }
    }
}

// LiveWaveformBars is defined in MacRecordingView.swift
