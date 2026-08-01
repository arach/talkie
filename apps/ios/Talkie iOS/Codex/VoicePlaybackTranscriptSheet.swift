//
//  VoicePlaybackTranscriptSheet.swift
//  Talkie iOS
//

import SwiftUI

/// The exact text attached to the audio currently owned by the global voice player.
struct VoicePlaybackTranscriptSheet: View {
    let title: String?
    let transcript: String

    @ObservedObject private var theme = ThemeManager.shared
    @State private var voicePlayback = WalkieFX.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        playbackStatus

                        if let title, !title.isEmpty {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(theme.colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text(transcript)
                            .font(.body)
                            .foregroundStyle(theme.colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Playback Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if voicePlayback.isVoicePlaybackActive {
                        Button(
                            voicePlayback.voicePlaybackState == .paused ? "Resume" : "Pause",
                            systemImage: voicePlayback.voicePlaybackState == .paused
                                ? "play.fill"
                                : "pause.fill"
                        ) {
                            voicePlayback.toggleVoicePlayback()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var playbackStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: playbackStatusIcon)
                Text(playbackStatusLabel)
                Spacer(minLength: 8)
                Text(playbackTimeReadout)
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(theme.chrome.accent)

            ProgressView(value: voicePlayback.voicePlaybackProgress)
                .tint(theme.chrome.accent)
        }
        .accessibilityElement(children: .combine)
    }

    private var playbackStatusLabel: String {
        switch voicePlayback.voicePlaybackState {
        case .idle: return "PLAYBACK COMPLETE"
        case .playing: return "NOW PLAYING"
        case .paused: return "PLAYBACK PAUSED"
        }
    }

    private var playbackStatusIcon: String {
        switch voicePlayback.voicePlaybackState {
        case .idle: return "checkmark.circle"
        case .playing: return "speaker.wave.2.fill"
        case .paused: return "pause.circle.fill"
        }
    }

    private var playbackTimeReadout: String {
        let current = voicePlayback.voicePlaybackCurrentTime
        let remaining = max(0, voicePlayback.voicePlaybackDuration - current)
        return "\(formatPlaybackTime(current)) · −\(formatPlaybackTime(remaining))"
    }

    private func formatPlaybackTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds < 10 ? "0" : "")\(seconds)"
    }
}
