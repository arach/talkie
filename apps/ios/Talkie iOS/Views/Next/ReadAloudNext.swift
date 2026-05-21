//
//  ReadAloudNext.swift
//  Talkie iOS
//
//  Read Aloud — TTS playback surface for the Next shell.
//

import AVFoundation
import SwiftUI
import UIKit

struct ReadAloudNext: View {
    @EnvironmentObject private var chromeState: ShellChrome
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var player = ReadAloudPlayer.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                hairline

                ScrollView {
                    VStack(spacing: 0) {
                        if player.variant == .idle {
                            IdleSourcePicker(player: player)
                        } else {
                            NowReadingPanel(player: player)
                            SourceViewer(player: player)
                        }

                        VoiceControls(player: player)

                        if player.variant == .queue {
                            QueueList(player: player)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 88)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            player.configureAudio()
            player.bind(source: AppShellRouter.shared.pendingReadAloudSource)
            AppShellRouter.shared.pendingReadAloudSource = nil
        }
        .onDisappear {
            player.stop()
        }

    }

    private var header: some View {
        HStack {
            Text("TALKIE · READ ALOUD")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
            Button {
                player.stop()
                chromeState.dismissChrome()
                AppShellRouter.shared.openHome()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(theme.currentTheme.chrome.edgeFaint.opacity(0.72)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var hairline: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
    }
}

// MARK: - Player model

// MARK: - Top-level states

private struct IdleSourcePicker: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    private let rows: [(ReadAloudPlayer.SourceKind, String, String)] = [
        (.text, "Recent memo", "Conference Bio · 31w"),
        (.image, "Recent capture", "Scope dashboard notes"),
        (.pdf, "Library selection", "On Bullshit · Frankfurt"),
        (.url, "Ask AI response", "Daring Fireball · 2m ago")
    ]

    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(text: "PICK A SOURCE")
            VStack(spacing: 8) {
                ForEach(rows.enumerated(), id: \.offset) { index, row in
                    Button {
                        player.selectSource(row.0)
                    } label: {
                        HStack(spacing: 12) {
                            Text("S\((index + 1), format: .number.precision(.integerLength(2)))")
                                .talkieType(.channelLabelTiny)
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.1)
                                    .talkieType(.preview)
                                    .foregroundStyle(theme.colors.textPrimary)
                                Text(row.2)
                                    .talkieType(.metaMono)
                                    .foregroundStyle(theme.colors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.colors.cardBackground)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct NowReadingPanel: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOW READING")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Text(player.currentItem.title)
                .talkieType(.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(player.currentItem.meta)
                .talkieType(.metaMono)
                .foregroundStyle(theme.colors.textTertiary)
            ReadAloudWaveformView(playedBarCount: player.playedBarCount)
            TransportView(player: player)
        }
        .padding(.top, 8)
    }
}

private struct ReadAloudWaveformView: View {
    let playedBarCount: Int
    @ObservedObject private var theme = ThemeManager.shared

    private let heights: [CGFloat] = (0..<32).map { index in
        let seed = (index * 9_301 + 49_297) % 233_280
        return CGFloat(20 + (seed % 26))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.enumerated(), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < playedBarCount ? theme.currentTheme.chrome.accent : theme.colors.textTertiary.opacity(0.28))
                    .opacity(index < playedBarCount ? 0.9 : 1)
                    .frame(width: 4, height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct TransportView: View {
    let player: ReadAloudPlayer

    var body: some View {
        HStack(spacing: 28) {
            transportButton(systemImage: "backward.end.fill", size: 36) { player.skipBackward() }
            transportButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill", size: 56, primary: true) { player.togglePlayback() }
            transportButton(systemImage: "forward.end.fill", size: 36) { player.skipForward() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func transportButton(systemImage: String, size: CGFloat, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: primary ? 20 : 15, weight: .semibold))
                .foregroundStyle(primary ? ThemeManager.shared.colors.cardBackground : ThemeManager.shared.colors.textPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(primary ? ThemeManager.shared.currentTheme.chrome.accent : Color.clear))
                .overlay(Circle().strokeBorder(primary ? Color.clear : ThemeManager.shared.currentTheme.chrome.edgeFaint, lineWidth: ThemeManager.shared.currentTheme.chrome.hairlineWidth))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Source viewer

private struct SourceViewer: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Button {
                player.sourceExpanded.toggle()
            } label: {
                HStack {
                    Text("SOURCE · \(player.selectedKind.label)")
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                    Text(player.sourceExpanded ? "HIDE" : "SHOW")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .padding(.top, 16)
                .padding(.bottom, 7)
                .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
            }
            .buttonStyle(.plain)

            if player.sourceExpanded {
                VStack(spacing: 0) {
                    SourceStamp(player: player)
                    if player.selectedKind == .text {
                        SourceTranscript(player: player)
                    } else {
                        SourceReference(player: player)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.colors.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth))
                )
                .padding(.top, 12)
            }
        }
        .padding(.top, 4)
    }
}

private struct SourceStamp: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: player.selectedKind.icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .frame(width: 20, height: 20)
            Text(player.currentItem.sourcePath)
                .talkieType(.fieldValue)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("OPEN ›") {
                player.openOriginal()
            }
            .talkieType(.chipLabel)
            .foregroundStyle(theme.currentTheme.chrome.accent)
            .buttonStyle(.plain)
            .disabled(player.currentItem.sourceURL == nil)
            .opacity(player.currentItem.sourceURL == nil ? 0.45 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
    }
}

private struct SourceTranscript: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(player.chunks.enumerated(), id: \.offset) { index, chunk in
                SourceChunk(text: chunk, state: player.chunkState(for: index))
            }
        }
        .padding(12)
    }
}

private struct SourceReference: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(player.currentItem.referenceEyebrow ?? "EXTRACTED TEXT")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Text("“\(player.currentItem.text)… ”")
                .talkieType(.preview)
                .italic()
                .foregroundStyle(theme.colors.textTertiary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct SourceChunk: View {
    let text: String
    let state: ReadAloudChunkState
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(state == .playing ? theme.currentTheme.chrome.accent : Color.clear)
                .frame(width: 2)
            Text(text)
                .talkieType(.preview)
                .foregroundStyle(color)
                .opacity(opacity)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var color: Color {
        switch state {
        case .played: return theme.colors.textTertiary
        case .playing: return theme.colors.textPrimary
        case .upcoming: return theme.colors.textTertiary
        }
    }

    private var opacity: Double {
        state == .upcoming ? 0.55 : 1
    }
}

// MARK: - Voice controls

private struct VoiceControls: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "VOICE")
                .padding(.top, 8)
            VoicePickerRow(player: player)
            SliderControlRow(label: "Rate", value: player.rate, range: 0.75...2.0, suffix: "×") { player.rate = $0 }
            SliderControlRow(label: "Pitch", value: player.pitch, range: 0.6...1.6, suffix: "") { player.pitch = $0 }
            Button {
                player.autoPause.toggle()
            } label: {
                ControlRowShell(label: "Auto-pause") {
                    Text(player.autoPause ? "On sentences" : "Off")
                        .talkieType(.fieldValue)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}

private struct VoicePickerRow: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ControlRowShell(label: "Voice") {
            Menu {
                ForEach(player.voices, id: \.identifier) { voice in
                    Button("\(voice.name) · \(voice.language)") {
                        player.selectedVoiceIdentifier = voice.identifier
                    }
                }
            } label: {
                Text(player.selectedVoiceLabel)
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct SliderControlRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let suffix: String
    let onChange: (Double) -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ControlRowShell(label: label) {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { value }, set: onChange), in: range)
                    .tint(theme.currentTheme.chrome.accent)
                    .frame(width: 96)
                Text(valueLabel)
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }

    private var valueLabel: String {
        let rounded = (value * 10).rounded() / 10
        return rounded.formatted(.number.precision(.fractionLength(1))) + suffix
    }
}

private struct ControlRowShell<Accessory: View>: View {
    let label: String
    @ViewBuilder let accessory: Accessory
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer(minLength: 12)
            accessory
        }
        .frame(height: 44)
        .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
    }
}

// MARK: - Queue

private struct QueueList: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "UP NEXT · \(player.queue.count)")
            ForEach(player.queue.enumerated(), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Text("\((index + 1), format: .number.precision(.integerLength(2)))")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                    Text(item.title)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(item.meta)
                        .talkieType(.timestamp)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .frame(height: 44)
                .overlay(Rectangle().fill(index < player.queue.count - 1 ? theme.currentTheme.chrome.edgeFaint : Color.clear).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
            }
        }
        .padding(.top, 8)
    }
}

private struct SectionHeader: View {
    let text: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Text(text)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 7)
        .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
    }
}
