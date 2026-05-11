//
//  DictationPill.swift
//  Talkie
//
//  Floating dictation pill for voice recording in DraftsScreen
//

import SwiftUI
import TalkieKit

/// State for the dictation pill
enum DictationPillState {
    case idle
    case recording
    case transcribing
    case success
}

struct DictationPill: View {
    @Binding var state: DictationPillState
    @Binding var duration: TimeInterval
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var showSuccess = false

    private var isExpanded: Bool {
        state != .idle || isHovered
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: isExpanded ? 8 : 0) {
                // Left: State indicator
                stateIndicator

                // Content (when expanded)
                if isExpanded {
                    stateContent
                }
            }
            .padding(.horizontal, isExpanded ? 12 : 8)
            .padding(.vertical, isExpanded ? 8 : 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        Capsule()
                            .stroke(state == .recording ? Color.red.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onChange(of: state) { oldState, newState in
            if newState == .success {
                showSuccess = true
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    if state == .success {
                        showSuccess = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

        case .recording:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .scaleEffect(1.5)
                        .opacity(0.6)
                )

        case .transcribing:
            BrailleSpinner(size: 12)

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.green)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle:
            Text("Tap to dictate")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

        case .recording:
            HStack(spacing: 6) {
                Text(formatDuration(duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
            }

        case .transcribing:
            Text("Processing...")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

        case .success:
            Text("Done")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.green)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        if minutes > 0 {
            return String(format: "%d:%02d.%d", minutes, seconds, tenths)
        }
        return String(format: "%d.%d", seconds, tenths)
    }
}
