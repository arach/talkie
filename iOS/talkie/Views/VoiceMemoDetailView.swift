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
        guard let path = memo.fileURL else { return nil }
        return URL(fileURLWithPath: path)
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
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    if isEditing {
                        TextField("Title", text: $editedTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .padding(.horizontal)
                    } else {
                        Text(memoTitle)
                            .font(.title2)
                            .bold()
                    }

                    // Metadata
                    VStack(spacing: 8) {
                        Text(formatDate(memoCreatedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(formatDuration(memo.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Large, detailed waveform
                    if let waveformData = memo.waveformData,
                       let levels = try? JSONDecoder().decode([Float].self, from: waveformData) {
                        VStack(spacing: 8) {
                            WaveformView(
                                levels: levels,
                                height: 120,
                                color: isPlaying ? .blue : .gray.opacity(0.6)
                            )
                            .animation(.easeInOut(duration: 0.3), value: isPlaying)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)

                            Text("\(levels.count) samples")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Playback controls
                    VStack(spacing: 15) {
                        // Progress slider
                        if let url = memoURL,
                           audioPlayer.currentPlayingURL == url {
                            VStack(spacing: 5) {
                                Slider(
                                    value: Binding(
                                        get: { audioPlayer.currentTime },
                                        set: { audioPlayer.seek(to: $0) }
                                    ),
                                    in: 0...max(audioPlayer.duration, 1)
                                )

                                HStack {
                                    Text(formatDuration(audioPlayer.currentTime))
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text(formatDuration(audioPlayer.duration))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Play/Pause button
                        Button(action: togglePlayback) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.top)

                    // Transcription section
                    if memo.isTranscribing {
                        HStack {
                            ProgressView()
                            Text("Transcribing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    } else if let transcription = memo.transcription {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Transcription")
                                .font(.headline)

                            Text(transcription)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }

                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        if isEditing {
                            saveTitle()
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            saveTitle()
                        } else {
                            editedTitle = memoTitle
                            isEditing = true
                        }
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
