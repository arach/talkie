//
//  DictationPill.swift
//  Talkie
//
//  Floating pill for ephemeral dictation - mirrors TalkieLive's LivePill design language
//  Sliver (collapsed) → Expanded (on hover) with same transitions
//

import SwiftUI

enum DictationPillState {
    case idle
    case recording
    case transcribing
    case success
}

/// Dictation pill matching TalkieLive's iconic sliver/expand pattern (LivePill)
struct DictationPill: View {
    @Binding var state: DictationPillState
    @Binding var duration: TimeInterval
    let onTap: () -> Void

    @Environment(SettingsManager.self) private var settings
    @State private var isHovered = false
    @State private var pulsePhase: CGFloat = 0

    private var isDark: Bool { settings.isDarkMode }

    private var isExpanded: Bool {
        isHovered || state != .idle
    }

    var body: some View {
        Button(action: onTap) {
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
        }
        .onChange(of: state) { _, newState in
            pulsePhase = 0
            if newState == .recording {
                startPulseAnimation()
            }
        }
    }

    // MARK: - Sliver Content (Collapsed)

    private var sliverContent: some View {
        HStack(spacing: 4) {
            // Mic hint
            Image(systemName: "mic.fill")
                .font(.system(size: 8))
                .foregroundColor(sliverColor.opacity(0.6))

            // Main sliver bar
            RoundedRectangle(cornerRadius: 2)
                .fill(sliverColor.opacity(0.5))
                .frame(width: 20, height: 2)
        }
        .frame(height: 18)
        .padding(.horizontal, 6)
    }

    private var sliverColor: Color {
        isDark ? Color(white: 0.5) : Color(white: 0.4)
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
            .scaleEffect(state == .recording ? 1.0 + pulsePhase * 0.5 : 1.0)
            .opacity(state == .recording ? 0.7 + pulsePhase * 0.3 : 1.0)
            .shadow(color: state == .recording ? dotColor.opacity(0.5) : .clear, radius: 3)
    }

    private var dotColor: Color {
        switch state {
        case .idle: return isDark ? Color(white: 0.5) : Color(white: 0.4)
        case .recording: return .red
        case .transcribing: return SemanticColor.warning
        case .success: return SemanticColor.success
        }
    }

    // MARK: - State Content

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle:
            Text("Dictate")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(textSecondary)

        case .recording:
            HStack(spacing: 4) {
                Text(formatTime(duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(textPrimary)
                // Audio level bar (simplified)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red.opacity(0.6))
                    .frame(width: 3, height: 6 + pulsePhase * 4)
            }

        case .transcribing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(textSecondary)
            }

        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                Text("Done")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(SemanticColor.success)
        }
    }

    private var textPrimary: Color {
        isDark ? .white : Color(white: 0.1)
    }

    private var textSecondary: Color {
        isDark ? Color(white: 0.7) : Color(white: 0.4)
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
        if state == .recording { return Color.red.opacity(0.3) }
        if state == .success { return SemanticColor.success.opacity(0.3) }
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
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        Text("Sliver (collapsed)").font(.caption).foregroundColor(.gray)
        HStack(spacing: 20) {
            DictationPill(state: .constant(.idle), duration: .constant(0), onTap: {})
        }

        Text("Expanded (hover/active)").font(.caption).foregroundColor(.gray)
        VStack(spacing: 10) {
            DictationPill(state: .constant(.idle), duration: .constant(0), onTap: {})
                .onAppear {} // Force expanded via preview
            DictationPill(state: .constant(.recording), duration: .constant(5), onTap: {})
            DictationPill(state: .constant(.transcribing), duration: .constant(5), onTap: {})
            DictationPill(state: .constant(.success), duration: .constant(5), onTap: {})
        }
    }
    .padding(40)
    .background(Color.black.opacity(0.8))
}
