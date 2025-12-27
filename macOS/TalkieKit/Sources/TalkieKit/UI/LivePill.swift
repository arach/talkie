//
//  LivePill.swift
//  TalkieKit
//
//  Shared live pill component - unified presentation for recording states
//  Used in StatusBar (embedded) and FloatingPill (floating overlay)
//
//  Two modes:
//  - Sliver (collapsed): minimal indicator bar
//  - Expanded: full pill with timer, audio level, status text
//
//  Hover to expand, or force expanded via parameter.
//

import SwiftUI
import AppKit

// MARK: - Visual State (Single Source of Truth)

/// Derived visual state that consolidates all display logic
private enum VisualState: Equatable {
    case warmingUp
    case success
    case offline
    case idle(hasPending: Bool)
    case listening(interstitialHint: Bool)
    case transcribing
    case routing

    var dotColor: Color {
        switch self {
        case .warmingUp: return SemanticColor.info
        case .success: return SemanticColor.success
        case .offline: return SemanticColor.warning
        case .idle: return TalkieTheme.textMuted
        case .listening: return .red
        case .transcribing: return SemanticColor.warning
        case .routing: return SemanticColor.success
        }
    }

    var sliverColor: Color {
        dotColor  // Same as dot color for consistency
    }

    var borderColor: Color {
        switch self {
        case .listening: return Color.red.opacity(0.3)
        case .success: return SemanticColor.success.opacity(0.3)
        default: return Color.white.opacity(0.1)
        }
    }

    var sliverWidth: CGFloat {
        switch self {
        case .idle: return 20
        case .success: return 28
        case .listening: return 28
        case .transcribing, .routing: return 24
        case .warmingUp, .offline: return 24
        }
    }

    var isPulsing: Bool {
        if case .listening = self { return true }
        return false
    }
}

// MARK: - Live Pill

/// Unified live pill showing: Ready → Recording → Processing → Success
/// Supports sliver (collapsed) and expanded modes with hover-to-expand.
public struct LivePill: View {
    let state: LiveState
    let isWarmingUp: Bool
    let showSuccess: Bool
    let recordingDuration: TimeInterval
    let processingDuration: TimeInterval
    let isEngineConnected: Bool
    let pendingQueueCount: Int
    let micDeviceName: String?
    let audioLevel: Float  // 0.0-1.0, passed from parent (no singleton dependency)

    // Control expansion
    var forceExpanded: Bool = false

    // Optional callbacks
    var onTap: (() -> Void)? = nil
    var onQueueTap: (() -> Void)? = nil  // Tapping the queue badge specifically

    // MARK: - State

    @State private var isHovered = false
    @State private var isShiftHeld = false
    @State private var isCommandHeld = false
    @State private var flagsMonitor: Any?

    // MARK: - Init

    public init(
        state: LiveState,
        isWarmingUp: Bool,
        showSuccess: Bool,
        recordingDuration: TimeInterval,
        processingDuration: TimeInterval,
        isEngineConnected: Bool,
        pendingQueueCount: Int,
        micDeviceName: String?,
        audioLevel: Float = 0,
        forceExpanded: Bool = false,
        onTap: (() -> Void)? = nil,
        onQueueTap: (() -> Void)? = nil
    ) {
        self.state = state
        self.isWarmingUp = isWarmingUp
        self.showSuccess = showSuccess
        self.recordingDuration = recordingDuration
        self.processingDuration = processingDuration
        self.isEngineConnected = isEngineConnected
        self.pendingQueueCount = pendingQueueCount
        self.micDeviceName = micDeviceName
        self.audioLevel = audioLevel
        self.forceExpanded = forceExpanded
        self.onTap = onTap
        self.onQueueTap = onQueueTap
    }

    // MARK: - Derived State

    private var isExpanded: Bool {
        forceExpanded || isHovered
    }

    // IMPROVEMENT #4: Single derived visual state
    private var visualState: VisualState {
        if isWarmingUp { return .warmingUp }
        if showSuccess { return .success }

        // Show warning if engine isn't connected OR mic isn't available
        let hasIssue = !isEngineConnected || micDeviceName == nil
        if hasIssue {
            return .offline
        }

        switch state {
        case .idle: return .idle(hasPending: pendingQueueCount > 0)
        case .listening: return .listening(interstitialHint: isHovered && isShiftHeld)
        case .transcribing: return .transcribing
        case .routing: return .routing
        }
    }

    // MARK: - Body

    public var body: some View {
        Button(action: { onTap?() }) {
            ZStack {
                if isExpanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.06)),
                            removal: .opacity.animation(.easeIn(duration: 0.04))
                        ))
                } else {
                    sliverContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.06)),
                            removal: .opacity.animation(.easeIn(duration: 0.04))
                        ))
                }
            }
            .animation(.snappy(duration: 0.08), value: isExpanded)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                startModifierMonitor()
            } else {
                stopModifierMonitor()
            }
        }
        .onDisappear {
            stopModifierMonitor()
        }
        .onChange(of: isEngineConnected) { _, connected in
            if !connected {
                print("[LivePill] ⚠️ Engine disconnected - mic: \(micDeviceName ?? "nil")")
            } else {
                print("[LivePill] ✓ Engine connected")
            }
        }
        .onChange(of: micDeviceName) { oldMic, newMic in
            if oldMic != nil && newMic == nil {
                print("[LivePill] ⚠️ Microphone lost")
            } else if oldMic == nil && newMic != nil {
                print("[LivePill] ✓ Microphone available: \(newMic!)")
            }
        }
    }

    // MARK: - Sliver Content (Collapsed)

    private var sliverContent: some View {
        HStack(spacing: 4) {
            // Warning indicator for offline only
            if case .offline = visualState {
                Circle()
                    .fill(SemanticColor.warning)
                    .frame(width: 4, height: 4)
            }

            // Main sliver bar with optional pulse
            sliverBar
        }
        .frame(height: 18)
        .padding(.horizontal, 6)
    }

    // IMPROVEMENT #5: TimelineView for smooth, predictable pulse
    @ViewBuilder
    private var sliverBar: some View {
        if visualState.isPulsing {
            TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
                let phase = pulsePhase(for: timeline.date)
                let glow = glowIntensity(for: timeline.date)

                RoundedRectangle(cornerRadius: 2)
                    .fill(visualState.sliverColor.opacity(0.8 + phase * 0.2))
                    .frame(width: visualState.sliverWidth * (1.0 + phase * 0.25), height: 3)
                    .shadow(color: visualState.sliverColor.opacity(0.3 + glow * 0.4), radius: 2 + glow * 2)
            }
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(visualState.sliverColor.opacity(0.6))
                .frame(width: visualState.sliverWidth, height: 2)
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        HStack(spacing: 4) {
            stateDot
            stateContent
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(pillBackground)
        .contentShape(Rectangle())
    }

    // IMPROVEMENT #5: TimelineView for smooth dot pulse
    @ViewBuilder
    private var stateDot: some View {
        if visualState.isPulsing {
            TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
                let phase = pulsePhase(for: timeline.date)
                let glow = glowIntensity(for: timeline.date)

                Circle()
                    .fill(visualState.dotColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(1.0 + phase * 0.35)
                    .opacity(0.75 + phase * 0.25)
                    .shadow(color: visualState.dotColor.opacity(0.4 + glow * 0.4), radius: 2 + glow * 3)
            }
        } else {
            Circle()
                .fill(visualState.dotColor)
                .frame(width: 6, height: 6)
        }
    }

    /// Compute pulse phase from time (0.0 to 1.0, smooth breathing)
    private func pulsePhase(for date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        // Clean sine wave at ~0.7 Hz (comfortable breathing rhythm)
        // Using smoothstep-like easing: slower at peaks, faster through middle
        let raw = sin(t * 1.4 * .pi)
        let normalized = (raw + 1.0) / 2.0  // Map -1...1 to 0...1
        // Ease: spend more time at extremes (inhale pause, exhale pause)
        return CGFloat(normalized * normalized * (3.0 - 2.0 * normalized))
    }

    /// Glow intensity (slightly offset from main pulse)
    private func glowIntensity(for date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let raw = sin(t * 1.4 * .pi + 0.4)
        return CGFloat((raw + 1.0) / 2.0)
    }

    // MARK: - State Content

    @ViewBuilder
    private var stateContent: some View {
        switch visualState {
        case .warmingUp:
            Text("Warming up")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(SemanticColor.info)

        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                Text("Done")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SemanticColor.success)

        case .offline:
            // Show specific issue: mic or engine
            let message = micDeviceName == nil ? "No Mic" : "Offline"
            Text(message)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(SemanticColor.warning)

        case .idle(let hasPending):
            HStack(spacing: 4) {
                // Show mic name only when Command is held
                if isCommandHeld, let micName = micDeviceName {
                    HStack(spacing: 3) {
                        Image(systemName: "mic")
                            .font(.system(size: 8, weight: .medium))
                        Text(shortMicName(micName))
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(TalkieTheme.textTertiary)
                    .help(micName)
                } else {
                    Text("REC")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(TalkieTheme.textSecondary)
                }

                if hasPending {
                    Button(action: { onQueueTap?() }) {
                        Text("\(pendingQueueCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(SemanticColor.warning))
                    }
                    .buttonStyle(.plain)
                    .help("Click to retry failed transcriptions")
                }
            }

        case .listening(let interstitialHint):
            if interstitialHint {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("→ Edit")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.purple)
            } else {
                HStack(spacing: 4) {
                    // IMPROVEMENT #3: Fixed-width timer
                    Text(formatTime(recordingDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(minWidth: 28, alignment: .trailing)
                        .foregroundColor(TalkieTheme.textPrimary)
                    audioLevelIndicator
                }
            }

        case .transcribing:
            HStack(spacing: 4) {
                NanoWaveform(color: SemanticColor.warning)
                Text("Transcribing")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(SemanticColor.warning)
                if processingDuration > 0 {
                    Text("·")
                        .foregroundColor(TalkieTheme.textTertiary)
                    Text(formatTime(processingDuration))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

        case .routing:
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .medium))
                Text("Routing")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SemanticColor.success)
        }
    }

    // MARK: - Audio Level Indicator

    private var audioLevelIndicator: some View {
        // Use passed-in level (parent handles throttling)
        let sensitiveLevel = sqrt(CGFloat(audioLevel))  // Boost quiet sounds
        let maxHeight: CGFloat = 14
        let barHeight = max(2, maxHeight * sensitiveLevel)

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1)
                .fill(TalkieTheme.textTertiary.opacity(0.3))
                .frame(width: 3, height: maxHeight)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.red.opacity(0.6 + Double(sensitiveLevel) * 0.4))
                .frame(width: 3, height: barHeight)
                .animation(.easeOut(duration: 0.25), value: audioLevel)  // Smooth transition at 2Hz
        }
    }

    // MARK: - Background

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(visualState.borderColor, lineWidth: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.5
                    )
            )
    }

    // MARK: - Helpers

    // IMPROVEMENT #3: Fixed-width time formatting
    private func formatTime(_ interval: TimeInterval) -> String {
        let seconds = Int(floor(interval))
        if seconds < 60 {
            // Right-align single digits for consistent width
            return String(format: "%2ds", seconds)
        }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func shortMicName(_ fullName: String) -> String {
        let shortened = fullName
            .replacingOccurrences(of: " 2ch", with: "")
            .replacingOccurrences(of: " (USB)", with: "")
            .replacingOccurrences(of: " Microphone", with: "")

        if shortened.count > 12 {
            return String(shortened.prefix(12)) + "…"
        }
        return shortened
    }

    // MARK: - Modifier Key Monitoring
    // IMPROVEMENT #1: Event-based instead of timer polling

    private func startModifierMonitor() {
        stopModifierMonitor()  // Clean up any existing monitor

        // Event-based: only fires when modifiers actually change
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
            let newShift = event.modifierFlags.contains(.shift)
            let newCommand = event.modifierFlags.contains(.command)

            // Only update if changed (prevents unnecessary SwiftUI updates)
            if newShift != isShiftHeld { isShiftHeld = newShift }
            if newCommand != isCommandHeld { isCommandHeld = newCommand }

            return event
        }

        // Also check current state immediately
        let currentFlags = NSEvent.modifierFlags
        isShiftHeld = currentFlags.contains(.shift)
        isCommandHeld = currentFlags.contains(.command)
    }

    private func stopModifierMonitor() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        isShiftHeld = false
        isCommandHeld = false
    }
}

// MARK: - Nano Waveform

/// Waveform animation style
public enum NanoWaveformStyle: String, CaseIterable, Identifiable {
    case wave      // Smooth sine wave
    case bounce    // Bouncy energy
    case pulse     // Center-out pulse
    case cascade   // Waterfall effect
    case heartbeat // Quick double-beat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wave: return "Wave"
        case .bounce: return "Bounce"
        case .pulse: return "Pulse"
        case .cascade: return "Cascade"
        case .heartbeat: return "Heartbeat"
        }
    }
}

/// Tiny 5-bar waveform animation - fast and delightful
public struct NanoWaveform: View {
    let color: Color
    var style: NanoWaveformStyle = .wave

    public init(color: Color, style: NanoWaveformStyle = .wave) {
        self.color = color
        self.style = style
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    let height = barHeight(index: i, time: t)

                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(color)
                        .frame(width: 1.5, height: CGFloat(height))
                }
            }
            .frame(height: 8, alignment: .center)
        }
    }

    private func barHeight(index: Int, time: Double) -> Double {
        switch style {
        case .wave:
            // Smooth traveling sine wave
            let phase = time * 8.0 + Double(index) * 0.6
            return 2.0 + sin(phase) * 4.0

        case .bounce:
            // Bouncy with abs() for energy
            let phase = time * 10.0 + Double(index) * 0.5
            return 2.0 + abs(sin(phase)) * 5.0

        case .pulse:
            // Center-out ripple
            let center = 2.0
            let dist = abs(Double(index) - center)
            let phase = time * 6.0 - dist * 0.8
            return 2.0 + max(0, sin(phase)) * 5.0

        case .cascade:
            // Waterfall from left to right
            let phase = time * 7.0 - Double(index) * 0.4
            let wave = (sin(phase) + 1.0) / 2.0  // 0-1
            return 2.0 + wave * 5.0

        case .heartbeat:
            // Quick double-beat pattern
            let cycle = time.truncatingRemainder(dividingBy: 0.8)
            let beat1 = cycle < 0.1 ? (1.0 - cycle / 0.1) : 0
            let beat2 = (cycle > 0.15 && cycle < 0.25) ? (1.0 - (cycle - 0.15) / 0.1) : 0
            let intensity = max(beat1, beat2)
            let centerDist = abs(Double(index) - 2.0) / 2.0
            return 2.0 + intensity * (1.0 - centerDist * 0.5) * 5.0
        }
    }
}
