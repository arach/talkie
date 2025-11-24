//
//  MemoDetailView.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AVFoundation
import AppKit

struct MemoDetailView: View {
    @ObservedObject var memo: VoiceMemo

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var editedTitle: String = ""
    @State private var editedNotes: String = ""
    @State private var isEditingTitle = false
    @FocusState private var titleFieldFocused: Bool

    @Environment(\.managedObjectContext) private var viewContext

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with editable title
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if isEditingTitle {
                            TextField("Recording title", text: $editedTitle)
                                .font(.system(size: 16, weight: .regular, design: .monospaced))
                                .textFieldStyle(.plain)
                                .focused($titleFieldFocused)
                                .onSubmit {
                                    saveTitle()
                                }
                        } else {
                            Text(memoTitle)
                                .font(.system(size: 16, weight: .regular, design: .monospaced))
                                .foregroundColor(.primary)
                        }

                        Button(action: {
                            if isEditingTitle {
                                saveTitle()
                            } else {
                                editedTitle = memoTitle
                                isEditingTitle = true
                                titleFieldFocused = true
                            }
                        }) {
                            Image(systemName: isEditingTitle ? "checkmark.circle.fill" : "pencil.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

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

                // Notes Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.secondary)

                    TextEditor(text: $editedNotes)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(minHeight: 80)
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                        .onChange(of: editedNotes) { newValue in
                            saveNotes()
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
                                isCompleted: memo.summary != nil,
                                action: { executeWorkflow(.summarize) }
                            )

                            ActionButtonMac(
                                icon: "checkmark.square",
                                title: "TASKIFY",
                                isProcessing: memo.isProcessingTasks,
                                isCompleted: memo.tasks != nil,
                                action: { executeWorkflow(.extractTasks) }
                            )

                            ActionButtonMac(
                                icon: "bell",
                                title: "REMIND",
                                isProcessing: memo.isProcessingReminders,
                                isCompleted: memo.reminders != nil,
                                action: { executeWorkflow(.reminders) }
                            )

                            ActionButtonMac(
                                icon: "square.and.arrow.up",
                                title: "SHARE",
                                isProcessing: false,
                                isCompleted: false,
                                action: { shareTranscript() }
                            )
                        }
                    }
                }

                // Quick Actions
                Divider()

                HStack(spacing: 8) {
                    // Copy transcript
                    Button(action: copyTranscript) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10))
                            Text("COPY TRANSCRIPT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(memo.transcription == nil)

                    // Delete memo
                    Button(action: deleteMemo) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("DELETE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            editedTitle = memoTitle
            editedNotes = memo.notes ?? ""
        }
    }

    private func saveTitle() {
        guard let context = memo.managedObjectContext else { return }
        context.perform {
            memo.title = editedTitle
            try? context.save()
        }
        isEditingTitle = false
    }

    private func saveNotes() {
        guard let context = memo.managedObjectContext else { return }
        // Debounce: save after 500ms of no typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.perform {
                memo.notes = editedNotes
                try? context.save()
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
        } else if audioPlayer != nil {
            audioPlayer?.play()
            isPlaying = true
        } else {
            // Initialize player with synced audio data
            guard let audioData = memo.audioData else {
                print("⚠️ No audio data available (not yet synced from iOS)")
                return
            }

            do {
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.prepareToPlay()
                duration = audioPlayer?.duration ?? 0
                audioPlayer?.play()
                isPlaying = true
                print("✅ Playing synced audio: \(audioData.count) bytes, duration: \(duration)s")
            } catch {
                print("❌ Failed to play audio: \(error)")
            }
        }
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

    private func copyTranscript() {
        guard let transcription = memo.transcription else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcription, forType: .string)
    }

    private func deleteMemo() {
        guard let context = memo.managedObjectContext else { return }
        context.perform {
            context.delete(memo)
            try? context.save()
        }
    }

    private func executeWorkflow(_ actionType: WorkflowActionType) {
        Task {
            do {
                try await WorkflowExecutor.shared.execute(
                    action: actionType,
                    for: memo,
                    model: .geminiFlash,
                    context: viewContext
                )
                print("✅ \(actionType.rawValue) workflow completed")
            } catch {
                print("❌ Workflow error: \(error.localizedDescription)")
            }
        }
    }

    private func shareTranscript() {
        guard let transcript = memo.transcription else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        print("📋 Transcript copied to clipboard")
    }
}

// MARK: - Action Button for macOS
struct ActionButtonMac: View {
    let icon: String
    let title: String
    let isProcessing: Bool
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
