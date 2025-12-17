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
        case .transcribing: return TalkieTheme.textSecondary  // Neutral color during processing
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pillBackground)
        .contentShape(Rectangle())
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
        case .transcribing: return TalkieTheme.textSecondary  // Neutral color during processing
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
