//
//  TOReadoutSection.swift
//  Talkie
//
//  Readout/TTS section for selections and text-only objects.
//  Two modes:
//  1. Audio file exists → full player (play/pause, scrubber, duration)
//  2. No audio → on-device TTS play/stop + "Generate" cloud TTS button
//
//  Mirrors iOS CapturePlayerBar behavior for macOS parity.
//

import SwiftUI
import AVFoundation
import TalkieKit

private let log = Log(.ui)

struct TOReadoutSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager

    // Audio state (managed by parent)
    var audioURL: URL?
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var onTogglePlayback: () -> Void = {}
    var onSeek: (Double) -> Void = { _ in }

    // TTS state
    @Binding var isGeneratingTTS: Bool
    var onGenerateTTS: () -> Void = {}

    private let speechService = SpeechSynthesisService.shared

    private var hasText: Bool {
        guard let text = recording.text else { return false }
        return !text.isEmpty
    }

    var body: some View {
        if hasText {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("READOUT")
                        .font(settings.fontXSMedium)
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                if audioURL != nil {
                    audioPlayerBar
                } else {
                    localTTSBar
                }
            }
        }
    }

    // MARK: - Audio Player (when cloud/generated audio exists)

    private var audioPlayerBar: some View {
        AudioPlayerCard(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: max(duration, 0),
            onTogglePlayback: onTogglePlayback,
            onSeek: onSeek
        )
        .modifier(TechnicalCardModifier(cornerRadius: CornerRadius.card))
    }

    // MARK: - Local TTS Fallback (no audio file yet)

    private var localTTSBar: some View {
        HStack(spacing: Spacing.md) {
            // On-device play/stop
            Button {
                if speechService.isSpeaking {
                    speechService.stop()
                } else if let text = recording.text {
                    speechService.speak(text)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(speechService.isSpeaking
                              ? Color.orange.opacity(0.15)
                              : Theme.current.foreground.opacity(0.06))
                        .frame(width: 40, height: 40)

                    Circle()
                        .strokeBorder(
                            speechService.isSpeaking
                                ? Color.orange.opacity(0.3)
                                : Theme.current.foreground.opacity(0.1),
                            lineWidth: 0.5
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: speechService.isSpeaking ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(speechService.isSpeaking ? .orange : Theme.current.foregroundSecondary)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                if speechService.isSpeaking {
                    Text("Reading aloud…")
                        .font(settings.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    ReadoutPulseBar()
                } else {
                    Text("On-device voice")
                        .font(settings.fontSMMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Play to read aloud, or generate cloud audio")
                        .font(settings.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }

            Spacer()

            // Generate cloud TTS button
            if !speechService.isSpeaking {
                Button(action: onGenerateTTS) {
                    if isGeneratingTTS {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 15, weight: .medium))
                            Text("Generate")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingTTS)
                .help("Generate cloud TTS audio")
            }
        }
        .padding(Spacing.sm)
        .padding(.horizontal, 4)
        .modifier(TechnicalCardModifier(cornerRadius: CornerRadius.card))
    }
}

// MARK: - Readout Pulse Bar (macOS version)

struct ReadoutPulseBar: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.2))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: geo.size.width * 0.3, height: 3)
                        .offset(x: animate ? geo.size.width * 0.7 : 0)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: animate
                        )
                }
        }
        .frame(height: 3)
        .onAppear { animate = true }
    }
}
