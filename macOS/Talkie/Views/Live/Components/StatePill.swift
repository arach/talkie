//
//  StatePill.swift
//  TalkieLive
//
//  Shared state pill component - unified presentation for recording states
//  Used in StatusBar (embedded) and FloatingPill (floating overlay)
//
//  Two modes:
//  - Sliver (collapsed): minimal indicator bar
//  - Expanded: full pill with timer, audio level, status text
//
//  Hover to expand, or force expanded via parameter.
//

import SwiftUI
import TalkieKit

// MARK: - State Pill

/// Unified state pill showing: Ready → Recording → Processing → Success
/// Supports sliver (collapsed) and expanded modes with hover-to-expand.
struct StatePill: View {
    let state: LiveState
    let isWarmingUp: Bool
    let showSuccess: Bool
    let recordingDuration: TimeInterval
    let processingDuration: TimeInterval
    let isEngineConnected: Bool
    let pendingQueueCount: Int

    // Control expansion
    var forceExpanded: Bool = false

    // Optional environment and device info
    var talkieEnvironment: TalkieEnvironment? = nil  // Main app environment
    var liveEnvironment: TalkieEnvironment? = nil    // Only if differs from Talkie
    var engineEnvironment: TalkieEnvironment? = nil  // Only if differs from Talkie
    var micDeviceName: String? = nil

    // Optional callbacks
    var onTap: (() -> Void)? = nil
    var onQueueTap: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var pulsePhase: CGFloat = 0
    @State private var isShiftHeld = false
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared

    private var isExpanded: Bool {
        forceExpanded || isHovered
    }

    /// Show interstitial hint when recording + hovering + Shift held
    private var showInterstitialHint: Bool {
        state == .listening && isHovered && isShiftHeld
    }

    private var isActive: Bool {
        isWarmingUp || state != .idle || showSuccess
    }

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    sliverContent
                        .transition(.opacity.combined(with: .scale(scale: 1.1)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isExpanded)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                // Start monitoring modifier keys
                startModifierMonitor()
            } else {
                stopModifierMonitor()
                isShiftHeld = false
            }
        }
        .onAppear {
            if state == .listening {
                startPulseAnimation()
            }
        }
        .onChange(of: state) { _, newState in
            pulsePhase = 0
            if newState == .listening {
                startPulseAnimation()
            }
        }
    }

    // MARK: - Sliver Content (Collapsed)

    private var sliverContent: some View {
        HStack(spacing: 4) {
            // Warning indicator for offline/queue (don't show during active processing)
            if !isEngineConnected || (pendingQueueCount > 0 && state == .idle && !showSuccess) {
                Circle()
                    .fill(SemanticColor.warning)
                    .frame(width: 4, height: 4)
            }

            // Main sliver bar
            RoundedRectangle(cornerRadius: 2)
                .fill(sliverColor.opacity(sliverOpacity))
                .frame(width: sliverWidth, height: state == .listening ? 3 : 2)
                .scaleEffect(x: state == .listening ? 1.0 + pulsePhase * 0.3 : 1.0, y: 1.0)
                .shadow(color: state == .listening ? sliverColor.opacity(0.4) : .clear, radius: 3)

            // Queue badge
            if pendingQueueCount > 0 && state == .idle && !showSuccess {
                Text("\(pendingQueueCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(SemanticColor.warning))
            }
        }
        .frame(height: 18)
        .padding(.horizontal, 6)
    }

    private var sliverColor: Color {
        if isWarmingUp { return SemanticColor.info }
        if showSuccess { return SemanticColor.success }
        if !isEngineConnected { return SemanticColor.warning }
        switch state {
        case .idle: return TalkieTheme.textMuted
        case .listening: return .red
        case .transcribing: return .white.opacity(0.6)  // Neutral processing - no semantic color
        case .routing: return SemanticColor.success
        }
    }

    private var sliverOpacity: Double {
        state == .listening ? 0.9 : 0.6
    }

    private var sliverWidth: CGFloat {
        switch state {
        case .idle: return showSuccess ? 28 : 20
        case .listening: return 28
        case .transcribing: return 24
        case .routing: return 24
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        HStack(spacing: 6) {
            // State indicator dot
            stateDot

            // Content varies by state
            stateContent

            // Environment and mic info on the right
            if talkieEnvironment != nil || liveEnvironment != nil || engineEnvironment != nil || micDeviceName != nil {
                Divider()
                    .frame(height: 12)
                    .opacity(0.3)

                metadataContent
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pillBackground)
        .contentShape(Rectangle())
    }

    // MARK: - Metadata Content (Environment + Mic)

    @ViewBuilder
    private var metadataContent: some View {
        HStack(spacing: 4) {
            // Mic device (only show in idle state)
            if let micName = micDeviceName, state == .idle {
                HStack(spacing: 3) {
                    Image(systemName: "mic")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                    Text(shortMicName(micName))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
                .help(micName)
            }

            // Talkie environment badge (main app)
            if let env = talkieEnvironment, env != .production {
                environmentBadge(env, icon: "house.fill", label: "Talkie")
            }

            // Live environment badge (only if differs from Talkie)
            if let env = liveEnvironment, env != .production {
                environmentBadge(env, icon: "waveform.circle", label: "Live")
            }

            // Engine environment badge (only if differs from Talkie)
            if let env = engineEnvironment, env != .production {
                environmentBadge(env, icon: "engine.combustion", label: "Engine")
            }
        }
    }

    private func environmentBadge(_ env: TalkieEnvironment, icon: String, label: String) -> some View {
        let badgeColor: Color = {
            switch env {
            case .staging: return .orange
            case .dev: return .red
            case .production: return .blue
            }
        }()

        let badgeText = {
            switch env {
            case .staging: return "S"
            case .dev: return "D"
            case .production: return "P"
            }
        }()

        let helpText = {
            if label == "Talkie" {
                return "\(label): \(env.displayName)"
            } else {
                return "Connected to \(label) (\(env.displayName))"
            }
        }()

        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(badgeColor.opacity(0.7))

            Text(badgeText)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(badgeColor.opacity(0.2))
        .cornerRadius(2)
        .help(helpText)
    }

    private func shortMicName(_ name: String) -> String {
        // Shorten common mic names
        let shortened = name
            .replacingOccurrences(of: "Built-in Microphone", with: "Built-in")
            .replacingOccurrences(of: "MacBook Pro Microphone", with: "MacBook")
            .replacingOccurrences(of: "AirPods Pro", with: "AirPods")

        // Truncate if still too long
        if shortened.count > 12 {
            return String(shortened.prefix(12)) + "…"
        }
        return shortened
    }

    // MARK: - State Dot

    @ViewBuilder
    private var stateDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 6, height: 6)
            .scaleEffect(state == .listening ? 1.0 + pulsePhase * 0.5 : 1.0)
            .opacity(state == .listening ? 0.7 + pulsePhase * 0.3 : 1.0)
            .shadow(color: state == .listening ? dotColor.opacity(0.5) : .clear, radius: 3)
    }

    private var dotColor: Color {
        if isWarmingUp { return SemanticColor.info }
        if showSuccess { return SemanticColor.success }
        if !isEngineConnected { return SemanticColor.warning }
        switch state {
        case .idle: return TalkieTheme.textMuted
        case .listening: return .red  // Always red when recording
        case .transcribing: return .white.opacity(0.7)  // Neutral processing - no semantic color
        case .routing: return SemanticColor.success
        }
    }

    // MARK: - State Content

    @ViewBuilder
    private var stateContent: some View {
        if isWarmingUp {
            Text("Warming up")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(SemanticColor.info)
        } else if showSuccess {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                Text("Done")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SemanticColor.success)
        } else if !isEngineConnected {
            Text("Offline")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(SemanticColor.warning)
        } else {
            switch state {
            case .idle:
                if pendingQueueCount > 0 {
                    Button(action: { onQueueTap?() }) {
                        HStack(spacing: 4) {
                            Text("Ready")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(TalkieTheme.textSecondary)
                            Text("\(pendingQueueCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(SemanticColor.warning))
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Ready")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TalkieTheme.textSecondary)
                }
            case .listening:
                if showInterstitialHint {
                    // Shift held during hover - show interstitial mode hint
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text("→ Edit")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.purple)
                } else {
                    HStack(spacing: 4) {
                        Text(formatTime(recordingDuration))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(TalkieTheme.textPrimary)
                        audioLevelIndicator
                    }
                }
            case .transcribing:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text(formatTime(processingDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textSecondary)
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
    }

    // MARK: - Audio Level Indicator

    private var audioLevelIndicator: some View {
        let level = CGFloat(audioMonitor.level)
        let barHeight = max(2, 10 * level)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1)
                .fill(TalkieTheme.textTertiary.opacity(0.3))
                .frame(width: 3, height: 10)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.red.opacity(0.6 + Double(level) * 0.4))
                .frame(width: 3, height: barHeight)
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    // MARK: - Background

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 0.5)
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

    private var borderColor: Color {
        if state == .listening { return Color.red.opacity(0.3) }
        if showSuccess { return SemanticColor.success.opacity(0.3) }
        return Color.white.opacity(0.1)
    }

    // MARK: - Helpers

    private func formatTime(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulsePhase = 1.0
        }
    }

    // MARK: - Modifier Key Monitoring

    @State private var modifierTimer: Timer?

    private func startModifierMonitor() {
        // Poll modifier flags at 20Hz while hovering
        modifierTimer?.invalidate()
        modifierTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let shift = NSEvent.modifierFlags.contains(.shift)
            if shift != isShiftHeld {
                isShiftHeld = shift
            }
        }
    }

    private func stopModifierMonitor() {
        modifierTimer?.invalidate()
        modifierTimer = nil
    }
}

// MARK: - Preview

#Preview("States") {
    VStack(spacing: 20) {
        Text("Sliver (default)").font(.caption).foregroundColor(.gray)
        HStack(spacing: 20) {
            StatePill(state: .idle, isWarmingUp: false, showSuccess: false, recordingDuration: 0, processingDuration: 0, isEngineConnected: true, pendingQueueCount: 0)
            StatePill(state: .listening, isWarmingUp: false, showSuccess: false, recordingDuration: 12.5, processingDuration: 0, isEngineConnected: true, pendingQueueCount: 0)
            StatePill(state: .transcribing, isWarmingUp: false, showSuccess: false, recordingDuration: 0, processingDuration: 1.2, isEngineConnected: true, pendingQueueCount: 0)
        }

        Text("Expanded (hover)").font(.caption).foregroundColor(.gray)
        VStack(spacing: 10) {
            StatePill(state: .idle, isWarmingUp: false, showSuccess: false, recordingDuration: 0, processingDuration: 0, isEngineConnected: true, pendingQueueCount: 0, forceExpanded: true)
            StatePill(state: .listening, isWarmingUp: false, showSuccess: false, recordingDuration: 12.5, processingDuration: 0, isEngineConnected: true, pendingQueueCount: 0, forceExpanded: true)
            StatePill(state: .transcribing, isWarmingUp: false, showSuccess: false, recordingDuration: 0, processingDuration: 1.2, isEngineConnected: true, pendingQueueCount: 0, forceExpanded: true)
            StatePill(state: .idle, isWarmingUp: false, showSuccess: true, recordingDuration: 0, processingDuration: 0, isEngineConnected: true, pendingQueueCount: 0, forceExpanded: true)
            StatePill(state: .idle, isWarmingUp: false, showSuccess: false, recordingDuration: 0, processingDuration: 0, isEngineConnected: false, pendingQueueCount: 3, forceExpanded: true)
        }
    }
    .padding()
    .background(Color.black)
}
