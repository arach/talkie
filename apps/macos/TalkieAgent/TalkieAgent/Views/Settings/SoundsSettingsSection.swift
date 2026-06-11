//
//  SoundsSettingsSection.swift
//  TalkieAgent
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
                VStack(spacing: OpsSpacing.md) {
                    HStack(spacing: OpsSpacing.md) {
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
                                .font(OpsType.ui(OpsSize.xxs))
                            Text(isPlayingSequence ? "Playing..." : "Play Sequence")
                                .font(OpsType.ui(OpsSize.xs, weight: .medium))
                        }
                        .foregroundStyle(isPlayingSequence ? OpsInk.statusWarn : OpsTint.amber.color)
                        .padding(.horizontal, OpsSpacing.md)
                        .padding(.vertical, OpsSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: OpsRadius.standard)
                                .fill(isPlayingSequence ? OpsSurface.tintFill(OpsInk.statusWarn) : OpsSurface.tintGhost(OpsTint.amber.color))
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
            VStack(spacing: OpsSpacing.md) {
                // Icon
                Image(systemName: event.icon)
                    .font(OpsType.ui(OpsSize.xl, weight: .medium))
                    .foregroundStyle(isSelected ? OpsTint.amber.color : (isHovered ? OpsInk.ink : OpsInk.muted))
                    .frame(height: 24)

                // Event name
                Text(event.rawValue)
                    .font(OpsType.ui(OpsSize.xs, weight: .semibold))
                    .foregroundStyle(isSelected || isHovered ? OpsInk.ink : OpsInk.muted)

                // Current sound
                Text(sound.displayName)
                    .font(OpsType.ui(OpsSize.micro))
                    .foregroundStyle(OpsInk.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OpsSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: OpsRadius.standard)
                    .fill(isSelected ? OpsSurface.selected(OpsTint.amber.color) : (isHovered ? OpsSurface.hover : OpsSurface.control))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OpsRadius.standard)
                    .stroke(
                        isSelected ? OpsSurface.tintBorder(OpsTint.amber.color) : OpsHairline.subtle,
                        lineWidth: isSelected ? 1.5 : OpsStroke.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Sound Grid

struct SoundGrid: View {
    @Binding var selection: TalkieSound

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: OpsSpacing.md)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: OpsSpacing.md) {
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
                        .font(OpsType.ui(OpsSize.micro, weight: .bold))
                        .foregroundStyle(OpsTint.amber.color)
                } else if sound == .none {
                    Image(systemName: "speaker.slash")
                        .font(OpsType.ui(OpsSize.xxs))
                        .foregroundStyle(OpsInk.dim)
                } else {
                    Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(OpsType.ui(OpsSize.xxs))
                        .foregroundStyle(isHovered ? OpsInk.ink : OpsInk.muted)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }

                Text(sound.displayName)
                    .font(OpsType.ui(OpsSize.xxs, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? OpsTint.amber.color : (isHovered ? OpsInk.ink : OpsInk.muted))
            }
            .padding(.horizontal, OpsSpacing.md)
            .padding(.vertical, OpsSpacing.xs)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: OpsRadius.tight)
                    .fill(isSelected ? OpsSurface.selected(OpsTint.amber.color) : (isHovered ? OpsSurface.hover : OpsSurface.inset))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OpsRadius.tight)
                    .stroke(
                        isSelected ? OpsSurface.tintBorder(OpsTint.amber.color) : Color.clear,
                        lineWidth: isSelected ? 1.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
