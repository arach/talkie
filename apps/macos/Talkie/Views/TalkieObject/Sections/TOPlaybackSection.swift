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
    //
    // Typesetter's bar at the foot of the document. No "PLAYBACK" header
    // (the player IS the affordance), no card chrome — a themed surface
    // band with a top hairline that reads as embedded in the page.

    private var playerSection: some View {
        let resolvedDuration = duration > 0 ? duration : recording.duration

        // Studio mock pads the player rail with 36pt horizontal (`px-9`)
        // and 16pt vertical (`py-4`) inside the themed rail band. The
        // negative outer margin cancels the parent's 36pt body padding so
        // the band runs edge-to-edge of the document paper.
        // The playback footer is rendered by TalkieView's `bodyContent`
        // VStack — outside the body's 36pt padding wrap. So it's already
        // edge-to-edge on the document pane; no negative outer margin
        // needed.
        return AudioPlayerCard(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: max(resolvedDuration, 0),
            onTogglePlayback: onTogglePlayback,
            onSeek: onSeek,
            noInternalPadding: true
        )
        .padding(.horizontal, 36)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(ThemedScopeCanvas.surface)
        .overlay(alignment: .top) {
            ThemedScopeRule(.row)
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
