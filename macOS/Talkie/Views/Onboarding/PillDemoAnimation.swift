//
//  PillDemoAnimation.swift
//  Talkie macOS
//
//  Pill demo animation ported from TalkieLive onboarding
//  Shows the full recording workflow: cursor → click → record → process → complete
//

import SwiftUI

// MARK: - Pill Demo Animation

struct PillDemoAnimation: View {
    let colors: OnboardingColors
    @Binding var phase: Int
    @State private var recordingTime: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var dotsCount: Int = 0
    @State private var waveformLevels: [CGFloat] = Array(repeating: 0.2, count: 16)
    @State private var showKeys: Bool = false
    @State private var clickRippleScale: CGFloat = 0.3
    @State private var clickRippleOpacity: Double = 0

    // Phase 0: Idle sliver, cursor approaching
    // Phase 1: Cursor at pill, expanded "REC"
    // Phase 2: Click - recording starts, cursor still at pill briefly
    // Phase 3: Cursor moved away, red sliver pulsing, waveform visible
    // Phase 4: Keys appear (⌥⌘L), processing dots - cursor stays away
    // Phase 5: Success (checkmark) - cursor still away
    // Phase 6: Keys fade, cursor leaves, back to idle sliver

    private var isRecordingExpanded: Bool { phase == 2 }
    private var isRecordingSliver: Bool { phase == 3 }
    private var isProcessing: Bool { phase == 4 }
    private var isSuccess: Bool { phase == 5 }
    private var showExpandedPill: Bool { phase == 1 || phase == 2 || phase == 4 || phase == 5 }
    private var showWaveform: Bool { phase == 2 || phase == 3 }

    // Cursor position - stays away after recording
    private var cursorOffsetX: CGFloat {
        switch phase {
        case 0: return 40    // Approaching from right
        case 1, 2: return 12 // At the pill
        case 3, 4, 5: return -35  // Moved away, stays there
        case 6: return -50   // Leaves from current position
        default: return 12
        }
    }

    private var cursorOffsetY: CGFloat {
        switch phase {
        case 0: return 20    // Approaching
        case 1, 2: return 32 // At pill (bottom)
        case 3, 4, 5: return 5  // Away (middle area)
        case 6: return -10   // Leaves upward
        default: return 32
        }
    }

    private var cursorOpacity: Double {
        switch phase {
        case 0: return 0.5
        case 1, 2: return 1.0
        case 3, 4, 5: return 0.5  // Dimmer when away
        case 6: return 0.1
        default: return 0
        }
    }

    var body: some View {
        ZStack {
            // Screen mockup background - uses adaptive colors
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [colors.surfaceCard, colors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colors.border, lineWidth: 1)
                )
                .clipped()  // Clip content to viewport

            // Waveform overlay at top during recording (clipped to viewport)
            if showWaveform {
                VStack {
                    WaveformDemoView(levels: waveformLevels, colors: colors)
                        .padding(.top, 10)  // More room from top edge
                    Spacer()
                }
                .transition(.opacity)  // Just fade, no movement
            }

            // Keyboard shortcut display (right side)
            if showKeys {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        KeyboardShortcutView(colors: colors)
                            .padding(.trailing, 8)
                            .padding(.bottom, 25)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // The pill (bottom center)
            VStack {
                Spacer()
                ZStack {
                    if showExpandedPill {
                        HStack(spacing: 4) {
                            if isRecordingExpanded {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(pulseScale)
                                Text(formatTime(recordingTime))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(colors.textPrimary.opacity(0.9))
                            } else if isProcessing {
                                HStack(spacing: 2) {
                                    ForEach(0..<3) { i in
                                        Circle()
                                            .fill(colors.textPrimary.opacity(i < dotsCount ? 0.8 : 0.2))
                                            .frame(width: 3, height: 3)
                                    }
                                }
                                .frame(width: 40)  // Fixed width to match timer
                            } else if isSuccess {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(colors.accent)
                                    .frame(width: 40)  // Fixed width to match timer
                            } else {
                                Circle()
                                    .fill(colors.textPrimary)
                                    .frame(width: 6, height: 6)
                                Text("REC")
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(1)
                                    .foregroundColor(colors.textTertiary)
                            }
                        }
                        .frame(height: 18)  // Fixed height to prevent jumping
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(isRecordingExpanded ? Color.red.opacity(0.2) : colors.border.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                        .stroke(isRecordingExpanded ? Color.red.opacity(0.3) : colors.border, lineWidth: 0.5)
                                )
                        )
                        .transition(.scale.combined(with: .opacity))
                    } else if isRecordingSliver {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 24 * (1.0 + pulseScale * 0.15), height: 2)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(colors.textTertiary)
                            .frame(width: 24, height: 2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.bottom, 6)
            }

            // Cursor with click ripple effect
            ZStack {
                // Click ripple effect (expanding circle that fades)
                Circle()
                    .stroke(colors.textPrimary, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .scaleEffect(clickRippleScale)
                    .opacity(clickRippleOpacity)

                Image(systemName: "cursorarrow")
                    .font(.system(size: 16))
                    .foregroundColor(colors.textPrimary)
                    .shadow(color: colors.background.opacity(0.8), radius: 2, x: 1, y: 1)
            }
            .opacity(cursorOpacity)
            .offset(x: cursorOffsetX, y: cursorOffsetY)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))  // Clip everything to viewport
        .onChange(of: phase) { _, newPhase in
            if newPhase == 2 {
                // Click ripple effect - starts small and opaque, expands and fades
                clickRippleScale = 0.3
                clickRippleOpacity = 0.8
                withAnimation(.easeOut(duration: 0.4)) {
                    clickRippleScale = 2.5
                    clickRippleOpacity = 0
                }
                recordingTime = 0
                startRecordingAnimation()
                startWaveformAnimation()
            } else if newPhase == 4 {
                // Show keys when stopping recording
                withAnimation(.easeOut(duration: 0.15)) {
                    showKeys = true
                }
                startDotsAnimation()
                // Hide keys after 1.2s (longer to enjoy)
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    await MainActor.run {
                        withAnimation(.easeIn(duration: 0.3)) {
                            showKeys = false
                        }
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                pulseScale = 1.4
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        let seconds = Int(time) % 60
        let tenths = Int((time * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "0:%02d.%d", seconds, tenths)
    }

    private func startRecordingAnimation() {
        Task {
            while phase == 2 || phase == 3 {
                try? await Task.sleep(for: .milliseconds(100))
                await MainActor.run {
                    recordingTime += 0.1
                }
            }
        }
    }

    private func startWaveformAnimation() {
        Task {
            while phase == 2 || phase == 3 {
                try? await Task.sleep(for: .milliseconds(50))
                await MainActor.run {
                    var newLevels = waveformLevels
                    for i in 0..<(newLevels.count - 1) {
                        newLevels[i] = newLevels[i + 1]
                    }
                    let newLevel = CGFloat.random(in: 0.15...0.85)
                    newLevels[newLevels.count - 1] = newLevel
                    waveformLevels = newLevels
                }
            }
        }
    }

    private func startDotsAnimation() {
        dotsCount = 1
        Task {
            while phase == 4 {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    dotsCount = (dotsCount % 3) + 1
                }
            }
        }
    }
}
