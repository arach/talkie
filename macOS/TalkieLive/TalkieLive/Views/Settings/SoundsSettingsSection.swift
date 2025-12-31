//
//  SoundsSettingsSection.swift
//  TalkieLive
//
//  Sounds settings: audio feedback configuration for events
//

import SwiftUI
import TalkieKit

// MARK: - Sounds Settings Section

struct SoundsSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @State private var selectedEvent: SoundEvent = .start

    enum SoundEvent: String, CaseIterable {
        case start = "Start"
        case finish = "Finish"
        case paste = "Paste"

        var icon: String {
            switch self {
            case .start: return "mic.fill"
            case .finish: return "checkmark.circle.fill"
            case .paste: return "doc.on.clipboard.fill"
            }
        }

        var description: String {
            switch self {
            case .start: return "When recording begins"
            case .finish: return "When recording ends"
            case .paste: return "When text is pasted"
            }
        }
    }

    private func binding(for event: SoundEvent) -> Binding<TalkieSound> {
        switch event {
        case .start: return $settings.startSound
        case .finish: return $settings.finishSound
        case .paste: return $settings.pastedSound
        }
    }

    @State private var isPlayingSequence = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "speaker.wave.2",
                title: "SOUNDS",
                subtitle: "Configure audio feedback for different events."
            )
        } content: {
            // Event selector - horizontal row with play all
            SettingsCard(title: "EVENT") {
                VStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(SoundEvent.allCases, id: \.rawValue) { event in
                            SoundEventCard(
                                event: event,
                                sound: binding(for: event).wrappedValue,
                                isSelected: selectedEvent == event
                            ) {
                                selectedEvent = event
                            }
                        }
                    }

                    // Play sequence button
                    Button(action: playSequence) {
                        HStack(spacing: 6) {
                            Image(systemName: isPlayingSequence ? "stop.fill" : "play.fill")
                                .font(.system(size: 10))
                            Text(isPlayingSequence ? "Playing..." : "Play Sequence")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(isPlayingSequence ? .orange : .accentColor)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(isPlayingSequence ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPlayingSequence)
                }
            }

            // Sound picker for selected event
            SettingsCard(title: "SOUND FOR \(selectedEvent.rawValue.uppercased())") {
                SoundGrid(selection: binding(for: selectedEvent))
            }
        }
    }

    private func playSequence() {
        isPlayingSequence = true
        let sounds = [settings.startSound, settings.finishSound, settings.pastedSound]
        var delay: Double = 0

        for sound in sounds {
            if sound != .none {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    SoundManager.shared.preview(sound)
                }
                delay += 0.6
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) {
            isPlayingSequence = false
        }
    }
}

// MARK: - Sound Event Card

struct SoundEventCard: View {
    let event: SoundsSettingsSection.SoundEvent
    let sound: TalkieSound
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: event.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : (isHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary))
                    .frame(height: 24)

                // Event name
                Text(event.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? TalkieTheme.textPrimary : (isHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary))

                // Current sound
                Text(sound.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .glassHover(
                isHovered: isHovered,
                isSelected: isSelected,
                cornerRadius: CornerRadius.sm,
                accentColor: isSelected ? .accentColor : nil
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.6) : Color.clear,
                        lineWidth: isSelected ? 1.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(TalkieAnimation.fast, value: isHovered)
    }
}

// MARK: - Sound Grid

struct SoundGrid: View {
    @Binding var selection: TalkieSound

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: Spacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.sm) {
            ForEach(TalkieSound.allCases, id: \.self) { sound in
                SoundChip(
                    sound: sound,
                    isSelected: selection == sound
                ) {
                    selection = sound
                }
            }
        }
    }
}

// MARK: - Sound Chip

struct SoundChip: View {
    let sound: TalkieSound
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPlaying = false

    var body: some View {
        Button(action: {
            action()
            if sound != .none {
                isPlaying = true
                SoundManager.shared.preview(sound)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isPlaying = false
                }
            }
        }) {
            HStack(spacing: 4) {
                // Checkmark for selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.accentColor)
                } else if sound == .none {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                } else {
                    Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(.system(size: 10))
                        .foregroundColor(isHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }

                Text(sound.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .accentColor : (isHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .glassHover(
                isHovered: isHovered,
                isSelected: isSelected,
                cornerRadius: CornerRadius.xs,
                baseOpacity: 0.02,
                hoverOpacity: 0.15,
                accentColor: isSelected ? .accentColor : nil
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: isSelected ? 1.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(TalkieAnimation.fast, value: isHovered)
    }
}
