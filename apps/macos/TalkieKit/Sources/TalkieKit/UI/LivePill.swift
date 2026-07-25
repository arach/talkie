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
    case idle
    case listening(interstitialHint: Bool)
    case transcribing
    case routing
    case refining

    var dotColor: Color {
        switch self {
        case .warmingUp: return SemanticColor.info
        case .success: return SemanticColor.success
        case .offline: return SemanticColor.warning
        case .idle: return TalkieTheme.textMuted
        case .listening: return .red
        case .transcribing: return SemanticColor.warning
        case .routing: return SemanticColor.success
        case .refining: return .purple
        }
    }

    var sliverColor: Color {
        dotColor  // Same as dot color for consistency
    }

    var borderColor: Color {
        switch self {
        case .listening: return Color.red.opacity(0.3)
        case .success: return SemanticColor.success.opacity(0.3)
        case .refining: return Color.purple.opacity(0.3)
        default: return Color.white.opacity(0.1)
        }
    }

    var sliverWidth: CGFloat {
        switch self {
        case .idle: return 20
        case .success: return 28
        case .listening: return 28
        case .transcribing, .routing, .refining: return 24
        case .warmingUp, .offline: return 24
        }
    }

    var isPulsing: Bool {
        if case .listening = self { return true }
        return false
    }
}

// MARK: - Shared Surface

/// Stable, semantic chrome for overlays that must remain legible regardless of
/// the app or wallpaper beneath them. TalkieAgent chooses the tone from a
/// small screen sample; other LivePill hosts can continue using system glass.
public enum LiveGlassTone: Equatable, Sendable {
    case pearl
    case graphite

    public var colorScheme: ColorScheme {
        switch self {
        case .pearl: .light
        case .graphite: .dark
        }
    }

    public var surface: Color {
        switch self {
        case .pearl: Color(red: 0.965, green: 0.973, blue: 0.976)
        case .graphite: Color(red: 0.071, green: 0.086, blue: 0.094)
        }
    }

    public var surfaceOpacity: Double {
        switch self {
        case .pearl: 0.72
        case .graphite: 0.62
        }
    }

    public var raisedSurface: Color {
        switch self {
        case .pearl: Color(red: 0.992, green: 0.988, blue: 0.976)
        case .graphite: Color(red: 0.105, green: 0.125, blue: 0.133)
        }
    }

    public var primaryText: Color {
        switch self {
        case .pearl: Color(red: 0.12, green: 0.14, blue: 0.15)
        case .graphite: Color(red: 0.93, green: 0.95, blue: 0.94)
        }
    }

    public var secondaryText: Color {
        switch self {
        case .pearl: Color(red: 0.34, green: 0.37, blue: 0.39)
        case .graphite: Color(red: 0.59, green: 0.66, blue: 0.64)
        }
    }

    public var edge: Color {
        switch self {
        case .pearl: Color.black.opacity(0.14)
        case .graphite: Color.white.opacity(0.13)
        }
    }

    public var highlight: Color {
        switch self {
        case .pearl: Color.white.opacity(0.82)
        case .graphite: Color.white.opacity(0.10)
        }
    }

    public var sheen: Color {
        switch self {
        case .pearl: Color.white.opacity(0.55)
        case .graphite: Color.white.opacity(0.10)
        }
    }

    public var outerEdge: Color {
        switch self {
        case .pearl: Color.black.opacity(0.12)
        case .graphite: Color.black.opacity(0.35)
        }
    }

    public var shadow: Color {
        switch self {
        case .pearl: Color.black.opacity(0.20)
        case .graphite: Color.black.opacity(0.42)
        }
    }

    public var contactShadow: Color {
        switch self {
        case .pearl: Color.black.opacity(0.12)
        case .graphite: Color.black.opacity(0.22)
        }
    }

    public var lockAccent: Color {
        switch self {
        case .pearl: Color(red: 0.08, green: 0.57, blue: 0.48)
        case .graphite: Color(red: 0.31, green: 0.83, blue: 0.69)
        }
    }

    public var recordingAccent: Color {
        switch self {
        case .pearl: Color(red: 0.88, green: 0.23, blue: 0.18)
        case .graphite: Color(red: 1.0, green: 0.35, blue: 0.29)
        }
    }
}

public struct LiveGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let borderColor: Color
    let tone: LiveGlassTone?

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tone {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(tone.surface.opacity(tone.surfaceOpacity))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tone?.sheen ?? Color.white.opacity(0.12),
                                        tone?.sheen.opacity(0.18) ?? Color.white.opacity(0.02),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(tone == nil ? borderColor : borderColor.opacity(0.72), lineWidth: 0.6)
                    )
                    .overlay {
                        if let tone {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(tone.outerEdge, lineWidth: 0.5)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        tone?.highlight ?? Color.white.opacity(0.4),
                                        tone?.highlight.opacity(0.28) ?? Color.white.opacity(0.15),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: tone == nil ? 1 : 0.7
                            )
                    )
                    .shadow(color: tone?.shadow ?? Color.black.opacity(0.2), radius: tone == nil ? 8 : 10, x: 0, y: tone == nil ? 4 : 5)
                    .shadow(color: tone?.contactShadow ?? Color.white.opacity(0.05), radius: tone == nil ? 1 : 2, x: 0, y: 1)
            )
    }
}

public extension View {
    func liveGlassSurface(
        borderColor: Color = Color.white.opacity(0.1),
        cornerRadius: CGFloat = 8,
        tone: LiveGlassTone? = nil
    ) -> some View {
        modifier(
            LiveGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                borderColor: borderColor,
                tone: tone
            )
        )
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
    var pendingQueueCount: Int = 0
    let micDeviceName: String?
    let audioLevel: Float  // 0.0-1.0, passed from parent (no singleton dependency)

    // Control expansion
    var forceExpanded: Bool = false

    // Optional identifier for logging (e.g., "statusbar", "floating")
    var identifier: String? = nil

    // Capture intent for display (e.g., "Paste", "Scratchpad")
    // When not "Paste", shows an indicator during recording
    var captureIntent: String = "Paste"

    // Screen-aware chrome for the floating overlay. Nil preserves the system
    // material used by embedded/status-bar instances.
    var glassTone: LiveGlassTone? = nil

    // Optional callbacks
    var onTap: (() -> Void)? = nil
    var onQueueTap: (() -> Void)? = nil  // Tapping the queue badge specifically
    var onShiftToggle: (() -> Void)? = nil  // Shift pressed while hovering during recording

    // MARK: - State

    @Environment(\.colorScheme) private var colorScheme
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
        identifier: String? = nil,
        captureIntent: String = "Paste",
        glassTone: LiveGlassTone? = nil,
        onTap: (() -> Void)? = nil,
        onQueueTap: (() -> Void)? = nil,
        onShiftToggle: (() -> Void)? = nil
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
        self.identifier = identifier
        self.captureIntent = captureIntent
        self.glassTone = glassTone
        self.onTap = onTap
        self.onQueueTap = onQueueTap
        self.onShiftToggle = onShiftToggle
    }

    // MARK: - Derived State

    private var isExpanded: Bool {
        forceExpanded || isHovered
    }

    // IMPROVEMENT #4: Single derived visual state
    // Be optimistic - only show warnings for ACTIVE problems, not stale state
    private var visualState: VisualState {
        if isWarmingUp { return .warmingUp }
        if showSuccess { return .success }

        switch state {
        case .idle:
            // Idle: Don't show offline for passive connection issues
            // Only show mic warning if there's truly no mic (user should know)
            // But don't be aggressive about stale engine connection state
            return .idle

        case .listening:
            // Actively recording: Only warn if mic is unavailable (active problem)
            if micDeviceName == nil {
                return .offline
            }
            // Show scratchpad hint if: 1) captureIntent is scratchpad-related, or 2) hover+shift
            let showScratchpadHint = captureIntent != "Paste" || (isHovered && isShiftHeld)
            return .listening(interstitialHint: showScratchpadHint)

        case .transcribing:
            // Actively transcribing: Only warn if engine is disconnected (active problem)
            if !isEngineConnected {
                return .offline
            }
            return .transcribing

        case .routing:
            return .routing

        case .refining:
            return .refining
        }
    }

    private var stateAccent: Color {
        if case .listening = visualState, let glassTone {
            return glassTone.recordingAccent
        }
        return visualState.dotColor
    }

    private var primaryLabelColor: Color {
        glassTone?.primaryText ?? TalkieTheme.textPrimary
    }

    private var secondaryLabelColor: Color {
        glassTone?.secondaryText ?? TalkieTheme.textSecondary
    }

    private var tertiaryLabelColor: Color {
        glassTone?.secondaryText.opacity(0.72) ?? TalkieTheme.textTertiary
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
            let tag = identifier.map { "[\($0)] " } ?? ""
            if !connected {
                TalkieLogger.info(.system, "[LivePill] \(tag)⚠️ Engine disconnected - mic: \(micDeviceName ?? "nil")")
            } else {
                TalkieLogger.info(.system, "[LivePill] \(tag)✓ Engine connected")
            }
        }
        .onChange(of: micDeviceName) { oldMic, newMic in
            let tag = identifier.map { "[\($0)] " } ?? ""
            if oldMic != nil && newMic == nil {
                TalkieLogger.info(.system, "[LivePill] \(tag)⚠️ Microphone lost")
            } else if oldMic == nil && newMic != nil {
                TalkieLogger.info(.system, "[LivePill] \(tag)✓ Microphone available: \(newMic!)")
            }
        }
        .environment(\.colorScheme, glassTone?.colorScheme ?? colorScheme)
    }

    // MARK: - Sliver Content (Collapsed)

    private var sliverContent: some View {
        VStack(spacing: 2) {
            // Subtle scratchpad indicator when active (even without hover)
            if case .listening = visualState, captureIntent != "Paste" {
                Image(systemName: captureIntent.contains("selection") ? "text.cursor" : "sparkles")
                    .font(.system(size: 6, weight: .medium))
                    .foregroundColor(captureIntent.contains("selection") ? .cyan.opacity(0.7) : .purple.opacity(0.7))
            }

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
        }
        .frame(height: 14)
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
                    .fill(stateAccent.opacity(0.8 + phase * 0.2))
                    .frame(width: visualState.sliverWidth * (1.0 + phase * 0.25), height: 3)
                    .shadow(color: stateAccent.opacity(0.3 + glow * 0.4), radius: 2 + glow * 2)
            }
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(stateAccent.opacity(0.6))
                .frame(width: visualState.sliverWidth, height: 2)
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        HStack(spacing: 5) {
            stateDot
            stateContent
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 2)
        .liveGlassSurface(
            borderColor: glassTone.map { tone in
                if case .listening = visualState {
                    return tone.recordingAccent.opacity(0.46)
                }
                return tone.edge
            } ?? visualState.borderColor,
            tone: glassTone
        )
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
                    .fill(stateAccent)
                    .frame(width: 4, height: 4)
                    .scaleEffect(1.0 + phase * 0.35)
                    .opacity(0.75 + phase * 0.25)
                    .shadow(color: stateAccent.opacity(0.4 + glow * 0.4), radius: 2 + glow * 3)
            }
        } else {
            Circle()
                .fill(stateAccent)
                .frame(width: 4, height: 4)
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
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(SemanticColor.info)

        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .semibold))
                Text("Done")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(SemanticColor.success)

        case .offline:
            // Show specific issue: mic or engine
            let message = micDeviceName == nil ? "No Mic" : "Offline"
            Text(message)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(SemanticColor.warning)

        case .idle:
            // Show mic name only when Command is held
            if isCommandHeld, let micName = micDeviceName {
                HStack(spacing: 3) {
                    Image(systemName: "mic")
                        .font(.system(size: 7, weight: .medium))
                    Text(shortMicName(micName))
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundColor(tertiaryLabelColor)
                .help(micName)
            } else {
                Text("REC")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(secondaryLabelColor)
            }

        case .listening(let interstitialHint):
            if interstitialHint {
                HStack(spacing: 5) {
                    // Show appropriate icon based on intent
                    if captureIntent.contains("selection") {
                        Image(systemName: "text.cursor")
                            .font(.system(size: 8))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                    }
                    // Show "→ Edit" for selection-based, "→ Scratchpad" for shift-triggered
                    Text(captureIntent.contains("selection") ? "→ Edit" : "→ Scratchpad")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundColor(captureIntent.contains("selection") ? .cyan : .purple)
            } else {
                HStack(spacing: 5) {
                    // IMPROVEMENT #3: Fixed-width timer
                    Text(formatTime(recordingDuration))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .frame(minWidth: 24, alignment: .trailing)
                        .foregroundColor(primaryLabelColor)
                    audioLevelIndicator
                }
            }

        case .transcribing:
            HStack(spacing: 5) {
                NanoWaveform(color: SemanticColor.warning)
                Text("Transcribing")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(SemanticColor.warning)
                if processingDuration > 0 {
                    Text("·")
                        .foregroundColor(tertiaryLabelColor)
                    Text(formatTime(processingDuration))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(tertiaryLabelColor)
                }
            }

        case .routing:
            HStack(spacing: 5) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .medium))
                Text("Routing")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(SemanticColor.success)

        case .refining:
            HStack(spacing: 5) {
                NanoWaveform(color: .purple, style: .pulse)
                Text("Refining")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.purple)
            }
        }
    }

    // MARK: - Audio Level Indicator

    private var audioLevelIndicator: some View {
        // Use passed-in level (parent handles throttling)
        let sensitiveLevel = sqrt(CGFloat(audioLevel))  // Boost quiet sounds
        let maxHeight: CGFloat = 10
        let barHeight = max(2, maxHeight * sensitiveLevel)

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1)
                .fill(tertiaryLabelColor.opacity(0.3))
                .frame(width: 2, height: maxHeight)
            RoundedRectangle(cornerRadius: 1)
                .fill((glassTone?.recordingAccent ?? Color.red).opacity(0.6 + Double(sensitiveLevel) * 0.4))
                .frame(width: 2, height: barHeight)
                .animation(.easeOut(duration: 0.25), value: audioLevel)  // Smooth transition at 2Hz
        }
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
            if newShift != isShiftHeld {
                isShiftHeld = newShift
                // Fire callback when Shift is pressed (not released)
                // - In idle: opens interstitial directly (quick scratchpad)
                // - In listening: toggles capture intent
                if newShift && isHovered && (state == .idle || state == .listening) {
                    onShiftToggle?()
                }
            }
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
