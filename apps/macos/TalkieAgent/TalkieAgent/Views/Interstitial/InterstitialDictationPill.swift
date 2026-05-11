//
//  InterstitialDictationPill.swift
//  TalkieAgent
//
//  Floating pill for voice recording in the interstitial editor
//

import SwiftUI

/// State for the dictation pill
enum InterstitialDictationPillState {
    case idle
    case recording
    case transcribing
    case success
}

struct InterstitialDictationPill: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let audioLevel: Float
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var showSuccess = false

    private var pillState: InterstitialDictationPillState {
        if showSuccess { return .success }
        if isTranscribing { return .transcribing }
        if isRecording { return .recording }
        return .idle
    }

    private var isExpanded: Bool {
        pillState != .idle || isHovered
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
                            .stroke(pillState == .recording ? Color.red.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1)
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
        .onChange(of: isRecording) { wasRecording, nowRecording in
            if nowRecording && !wasRecording {
                // Started recording
                elapsedTime = 0
                timerTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                        elapsedTime += 0.1
                    }
                }
            } else if !nowRecording && wasRecording {
                // Stopped recording
                timerTask?.cancel()
                timerTask = nil
            }
        }
        .onChange(of: isTranscribing) { wasTranscribing, nowTranscribing in
            if !nowTranscribing && wasTranscribing {
                // Finished transcribing - show success briefly
                showSuccess = true
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    showSuccess = false
                }
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch pillState {
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
        switch pillState {
        case .idle:
            Text("Tap to dictate")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

        case .recording:
            HStack(spacing: 6) {
                Text(formatDuration(elapsedTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)

                // Audio level indicator
                audioLevelBar
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

    private var audioLevelBar: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.red.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: geo.size.width * CGFloat(min(audioLevel * 5, 1)))
                    , alignment: .leading
                )
        }
        .frame(width: 40, height: 4)
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
