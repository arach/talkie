//
//  MemoDetailView.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AVFoundation

struct MemoDetailView: View {
    @ObservedObject var memo: VoiceMemo

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(memoTitle)
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Text(formatDate(memoCreatedAt).uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)

                        Text("·")
                            .font(.system(size: 9))

                        Text(formatDuration(memo.duration))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                }

                // Playback controls
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: togglePlayback) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDuration(currentTime))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.primary)

                            Text(formatDuration(memo.duration))
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Transcription
                if memo.isTranscribing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("PROCESSING TRANSCRIPT...")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.purple)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.08))
                    .cornerRadius(6)
                } else if let transcription = memo.transcription {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRANSCRIPT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.secondary)

                        Text(transcription)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                }

                // Workflow Actions
                if memo.transcription != nil && !memo.isTranscribing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIONS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ActionButtonMac(
                                icon: "list.bullet.clipboard",
                                title: "SUMMARIZE",
                                isProcessing: memo.isProcessingSummary,
                                isCompleted: memo.summary != nil
                            )

                            ActionButtonMac(
                                icon: "checkmark.square",
                                title: "TASKIFY",
                                isProcessing: memo.isProcessingTasks,
                                isCompleted: memo.tasks != nil
                            )

                            ActionButtonMac(
                                icon: "bell",
                                title: "REMIND",
                                isProcessing: memo.isProcessingReminders,
                                isCompleted: memo.reminders != nil
                            )

                            ActionButtonMac(
                                icon: "square.and.arrow.up",
                                title: "SHARE",
                                isProcessing: false,
                                isCompleted: false
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private func togglePlayback() {
        // Placeholder - would need audio player implementation
        isPlaying.toggle()
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

// MARK: - Action Button for macOS
struct ActionButtonMac: View {
    let icon: String
    let title: String
    let isProcessing: Bool
    let isCompleted: Bool

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isCompleted ? .green : .primary)
                }

                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(isProcessing ? .purple : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isCompleted ? Color.green.opacity(0.05) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isCompleted ? Color.green : Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }
}
