//
//  SoundPicker.swift
//  Talkie
//
//  Sound picker components for Live settings
//  Ported from TalkieLive with instrumentation
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveSettings")

// MARK: - Sound Event Type

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

// MARK: - Sound Event Card

struct SoundEventCard: View {
    let event: SoundEvent
    let sound: TalkieSound
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            action()
            logger.debug("Selected sound event: \(event.rawValue)")
        }) {
            VStack(spacing: Spacing.xs) {
                // Icon
                Image(systemName: event.icon)
                    .font(.headlineMedium)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(height: 24)

                // Event name
                Text(event.rawValue)
                    .font(.labelMedium)
                    .foregroundColor(isSelected ? .primary : .secondary)

                // Current sound
                Text(sound.displayName)
                    .font(.techLabelSmall)
                    .foregroundColor(.secondary.opacity(Opacity.prominent))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Color.accentColor.opacity(Opacity.medium) : (isHovered ? Color.primary.opacity(Opacity.subtle) : Color.primary.opacity(Opacity.subtle)))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(isSelected ? Color.accentColor.opacity(Opacity.half) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sound Grid

struct SoundGrid: View {
    @Binding var selection: TalkieSound

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(TalkieSound.allCases, id: \.self) { sound in
                SoundChip(
                    sound: sound,
                    isSelected: selection == sound
                ) {
                    selection = sound
                    logger.info("Sound selected: \(sound.displayName)")
                }
            }
        }
    }
}

// MARK: - Sound Chip with Preview

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
                logger.debug("Previewing sound: \(sound.displayName)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isPlaying = false
                }
            }
        }) {
            HStack(spacing: 4) {
                // Icon based on state
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.techLabelSmall)
                        .foregroundColor(.accentColor)
                } else if sound == .none {
                    Image(systemName: "speaker.slash")
                        .font(.labelSmall)
                        .foregroundColor(.secondary.opacity(Opacity.prominent))
                } else {
                    Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(.labelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }

                Text(sound.displayName)
                    .font(.labelSmall)
                    .fontWeight(isSelected ? .bold : .medium)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isSelected ? Color.accentColor.opacity(Opacity.medium + 0.1) : (isHovered ? Color.primary.opacity(Opacity.light) : Color.primary.opacity(Opacity.subtle)))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Play Sequence Button

struct PlaySequenceButton: View {
    let sounds: [TalkieSound]
    @State private var isPlaying = false
    @State private var isHovered = false

    var body: some View {
        Button(action: playSequence) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.labelSmall)
                Text(isPlaying ? "Playing..." : "Play Sequence")
                    .font(.labelMedium)
            }
            .foregroundColor(isPlaying ? .orange : .accentColor)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isPlaying ? Color.orange.opacity(Opacity.medium) : (isHovered ? Color.accentColor.opacity(Opacity.medium) : Color.accentColor.opacity(Opacity.light)))
            )
        }
        .buttonStyle(.plain)
        .disabled(isPlaying)
        .onHover { isHovered = $0 }
    }

    private func playSequence() {
        isPlaying = true
        logger.info("Playing sound sequence: \(sounds.map { $0.displayName }.joined(separator: ", "))")

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
            isPlaying = false
            logger.debug("Sound sequence playback completed")
        }
    }
}
