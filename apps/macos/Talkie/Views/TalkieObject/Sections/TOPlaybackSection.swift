//
//  TOPlaybackSection.swift
//  Talkie
//
//  Audio playback section — player card, iCloud fetch, reveal in Finder.
//  Self-gates: renders nothing if no audio.
//

import SwiftUI
import TalkieKit

struct TOPlaybackSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager

    // Playback state (managed by parent)
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var fetchedAudioURL: URL? = nil

    // Callbacks
    var onTogglePlayback: () -> Void = {}
    var onSeek: (Double) -> Void = { _ in }
    var onVolumeChange: (Float) -> Void = { _ in }
    var onRevealAudio: () -> Void = {}
    var onFetchFromiCloud: () -> Void = {}
    var isFetchingAudio: Bool = false
    var fetchAudioError: String? = nil

    private var hasAudio: Bool {
        recording.hasAudio || fetchedAudioURL != nil
    }

    private var audioFileExists: Bool {
        if let audioURL = fetchedAudioURL ?? recording.audioURL {
            return FileManager.default.fileExists(atPath: audioURL.path)
        }
        return false
    }

    var body: some View {
        if hasAudio {
            if audioFileExists {
                playerSection
            } else {
                fetchFromiCloudSection
            }
        }
    }

    // MARK: - Player

    private var playerSection: some View {
        let resolvedDuration = duration > 0 ? duration : recording.duration
        let playbackProgress = resolvedDuration > 0 ? min(max(currentTime / resolvedDuration, 0), 1) : 0

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("PLAYBACK")
                    .font(settings.fontXSMedium)
                    .tracking(Tracking.wide)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button {
                    onRevealAudio()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Theme.current.foreground.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }

            AudioPlayerCard(
                isPlaying: isPlaying,
                currentTime: currentTime,
                duration: max(resolvedDuration, 0),
                onTogglePlayback: onTogglePlayback,
                onSeek: onSeek
            )
            .modifier(TechnicalCardModifier(cornerRadius: CornerRadius.card))
        }
    }

    // MARK: - iCloud Fetch

    private var fetchFromiCloudSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("AUDIO")
                .font(settings.fontXSMedium)
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundSecondary)

            VStack(spacing: Spacing.md) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)

                Text("Audio file not on this Mac")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if let error = fetchAudioError {
                    Text(error)
                        .font(Theme.current.fontXS)
                        .foregroundColor(.red)
                }

                Button {
                    onFetchFromiCloud()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if isFetchingAudio {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "icloud.and.arrow.down")
                        }
                        Text("Fetch from iCloud")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFetchingAudio)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
            .modifier(TechnicalCardModifier(cornerRadius: CornerRadius.card))
        }
    }
}
