//
//  VoiceMemoDetailView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

struct VoiceMemoDetailView: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject var audioPlayer: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editedTitle = ""

    private var memoURL: URL? {
        guard let filename = memo.fileURL else { return nil }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(filename)
    }

    private var isPlaying: Bool {
        guard let url = memoURL else { return false }
        return audioPlayer.isPlaying && audioPlayer.currentPlayingURL == url
    }

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Header: Title + Metadata
                        VStack(spacing: Spacing.sm) {
                            // Title
                            if isEditing {
                                TextField("Title", text: $editedTitle)
                                    .font(.bodyMedium)
                                    .padding(Spacing.sm)
                                    .background(Color.surfaceSecondary)
                                    .cornerRadius(CornerRadius.sm)
                                    .padding(.horizontal, Spacing.md)
                            } else {
                                Text(memoTitle)
                                    .font(.bodyLarge)
                                    .foregroundColor(.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, Spacing.md)
                            }

                            // Metadata row - tactical
                            HStack(spacing: Spacing.xs) {
                                Text(formatDate(memoCreatedAt).uppercased())
                                    .font(.techLabelSmall)
                                    .tracking(1)

                                Text("·")
                                    .font(.labelSmall)

                                Text(formatDuration(memo.duration))
                                    .font(.monoSmall)
                            }
                            .foregroundColor(.textSecondary)
                        }
                        .padding(.top, Spacing.md)

                        // Waveform
                        if let waveformData = memo.waveformData,
                           let levels = try? JSONDecoder().decode([Float].self, from: waveformData) {
                            VStack(spacing: Spacing.xs) {
                                WaveformView(
                                    levels: levels,
                                    height: 100,
                                    color: isPlaying ? .active : .textTertiary
                                )
                                .padding(.horizontal, Spacing.md)
                                .background(Color.surfaceSecondary)
                                .cornerRadius(CornerRadius.sm)
                                .padding(.horizontal, Spacing.md)

                                Text("[\(levels.count) SAMPLES]")
                                    .font(.techLabelSmall)
                                    .tracking(1)
                                    .foregroundColor(.textTertiary)
                            }
                        }

                        // Playback controls
                        VStack(spacing: Spacing.md) {
                            // Progress slider
                            if let url = memoURL,
                               audioPlayer.currentPlayingURL == url {
                                VStack(spacing: Spacing.xxs) {
                                    Slider(
                                        value: Binding(
                                            get: { audioPlayer.currentTime },
                                            set: { audioPlayer.seek(to: $0) }
                                        ),
                                        in: 0...max(audioPlayer.duration, 1)
                                    )
                                    .tint(.active)

                                    HStack {
                                        Text(formatDuration(audioPlayer.currentTime))
                                            .font(.monoSmall)
                                            .foregroundColor(.textSecondary)

                                        Spacer()

                                        Text(formatDuration(audioPlayer.duration))
                                            .font(.monoSmall)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                .padding(.horizontal, Spacing.md)
                            }

                            // Play/Pause button
                            Button(action: togglePlayback) {
                                ZStack {
                                    Circle()
                                        .fill(isPlaying ? Color.active : Color.surfaceSecondary)
                                        .frame(width: 64, height: 64)

                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(isPlaying ? .white : .textPrimary)
                                }
                            }
                        }

                        // Transcription section
                        if memo.isTranscribing {
                            HStack(spacing: Spacing.xs) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("PROCESSING TRANSCRIPT...")
                                    .font(.techLabel)
                                    .tracking(1)
                                    .foregroundColor(.transcribing)
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Color.transcribing.opacity(0.08))
                            .cornerRadius(CornerRadius.sm)
                            .padding(.horizontal, Spacing.md)
                        } else if let transcription = memo.transcription {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("TRANSCRIPT")
                                    .font(.techLabel)
                                    .tracking(2)
                                    .foregroundColor(.textSecondary)

                                Text(transcription)
                                    .font(.bodySmall)
                                    .foregroundColor(.textPrimary)
                                    .textSelection(.enabled)
                                    .lineSpacing(4)
                                    .padding(Spacing.md)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.surfaceSecondary)
                                    .cornerRadius(CornerRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                                            .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                    )
                            }
                            .padding(.horizontal, Spacing.md)
                        }

                        Spacer(minLength: Spacing.xxl)
                    }
                    .padding(.vertical, Spacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("MEMO DETAIL")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if isEditing {
                            saveTitle()
                        }
                        dismiss()
                    }) {
                        Text("CLOSE")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(.textSecondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if isEditing {
                            saveTitle()
                        } else {
                            editedTitle = memoTitle
                            isEditing = true
                        }
                    }) {
                        Text(isEditing ? "SAVE" : "EDIT")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(.active)
                    }
                }
            }
        }
    }

    private func togglePlayback() {
        guard let url = memoURL else { return }
        audioPlayer.togglePlayPause(url: url)
    }

    private func saveTitle() {
        memo.title = editedTitle
        try? memo.managedObjectContext?.save()
        isEditing = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
