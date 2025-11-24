//
//  RecordingView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData

struct RecordingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = AudioRecorderManager()
    @State private var recordingTitle = ""
    @State private var hasStartedRecording = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                VStack(spacing: Spacing.xxl) {
                    Spacer()

                    // Waveform visualization
                    if recorder.isRecording {
                        VStack(spacing: Spacing.lg) {
                            // Recording indicator - tactical style
                            HStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(Color.recording)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: Color.recording, radius: 4)

                                Text("● REC")
                                    .font(.techLabel)
                                    .fontWeight(.bold)
                                    .foregroundColor(.recording)
                                    .tracking(2)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.recording.opacity(0.08))
                            .cornerRadius(CornerRadius.sm)

                            // Waveform
                            WaveformView(
                                levels: recorder.audioLevels,
                                height: 120,
                                color: .recording
                            )
                            .padding(.horizontal, Spacing.lg)
                            .background(Color.surfaceSecondary)
                            .cornerRadius(CornerRadius.md)
                            .padding(.horizontal, Spacing.lg)

                            // Duration
                            Text(formatDuration(recorder.recordingDuration))
                                .font(.monoLarge)
                                .fontWeight(.medium)
                                .foregroundColor(.textPrimary)
                        }
                        .animation(TalkieAnimation.fast, value: recorder.audioLevels)
                    } else if hasStartedRecording {
                        VStack(spacing: Spacing.lg) {
                            // Success icon
                            ZStack {
                                Circle()
                                    .fill(Color.success.opacity(0.1))
                                    .frame(width: 80, height: 80)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.success)
                            }

                            Text("Saved")
                                .font(.displaySmall)
                                .foregroundColor(.textPrimary)

                            // Title input
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Title (Optional)")
                                    .font(.labelSmall)
                                    .foregroundColor(.textSecondary)
                                    .padding(.leading, Spacing.sm)

                                TextField("e.g., Meeting notes", text: $recordingTitle)
                                    .font(.bodyMedium)
                                    .padding(Spacing.md)
                                    .background(Color.surfaceSecondary)
                                    .cornerRadius(CornerRadius.md)
                            }
                            .padding(.horizontal, Spacing.xl)
                        }
                    } else {
                        VStack(spacing: Spacing.lg) {
                            ZStack {
                                Circle()
                                    .fill(Color.surfaceTertiary)
                                    .frame(width: 100, height: 100)

                                Image(systemName: "waveform")
                                    .font(.system(size: 48, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }

                            Text("Tap to Record")
                                .font(.headlineLarge)
                                .foregroundColor(.textPrimary)
                        }
                    }

                    Spacer()

                    // Recording button
                    Button(action: toggleRecording) {
                        ZStack {
                            if recorder.isRecording {
                                // Pulsing glow when recording
                                Circle()
                                    .fill(Color.recording)
                                    .frame(width: 80, height: 80)
                                    .blur(radius: 20)
                                    .opacity(0.6)

                                // Outer ring
                                Circle()
                                    .strokeBorder(Color.recording, lineWidth: 3)
                                    .frame(width: 88, height: 88)

                                // Stop icon
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.recording)
                                    .frame(width: 32, height: 32)
                            } else if !hasStartedRecording {
                                // Glow effect
                                Circle()
                                    .fill(Color.recording)
                                    .frame(width: 72, height: 72)
                                    .blur(radius: 20)
                                    .opacity(0.5)

                                // Main button
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.recording, Color.recordingGlow],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 72, height: 72)
                            } else {
                                Circle()
                                    .fill(Color.surfaceTertiary)
                                    .frame(width: 72, height: 72)
                            }
                        }
                    }
                    .padding(.bottom, Spacing.xxl)

                    if hasStartedRecording && !recorder.isRecording {
                        Button(action: {
                            saveRecording()
                            dismiss()
                        }) {
                            Text("Done")
                                .font(.bodyMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: 200)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    LinearGradient(
                                        colors: [Color.active, Color.activeGlow],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(CornerRadius.md)
                                .shadow(color: Color.active.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .padding(.bottom, Spacing.lg)
                    }
                }
            }
            .navigationTitle(recorder.isRecording ? "REC" : "NEW")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(recorder.isRecording ? "● RECORDING" : "NEW MEMO")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(recorder.isRecording ? .recording : .textPrimary)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if recorder.isRecording {
                            recorder.stopRecording()
                        }
                        dismiss()
                    }) {
                        Text("ESC")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(.textSecondary)
                    }
                }

                if hasStartedRecording && !recorder.isRecording {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            saveRecording()
                            dismiss()
                        }) {
                            Text("DONE")
                                .font(.techLabel)
                                .tracking(1)
                                .foregroundColor(.active)
                        }
                    }
                }
            }
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
            hasStartedRecording = true
        } else if !hasStartedRecording {
            recorder.startRecording()
        }
    }

    private func saveRecording() {
        guard let url = recorder.currentRecordingURL else { return }

        let newMemo = VoiceMemo(context: viewContext)
        newMemo.id = UUID()
        newMemo.title = recordingTitle.isEmpty ? "Recording \(formatDate(Date()))" : recordingTitle
        newMemo.createdAt = Date()
        newMemo.duration = recorder.recordingDuration
        newMemo.fileURL = url.lastPathComponent // Keep for backward compatibility
        newMemo.isTranscribing = false
        newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1) // Negative timestamp for newest first

        // Load and store audio data for CloudKit sync
        do {
            let audioData = try Data(contentsOf: url)
            newMemo.audioData = audioData
            print("✅ Audio data loaded: \(audioData.count) bytes")
        } catch {
            print("⚠️ Failed to load audio data: \(error)")
        }

        // Save waveform data
        if let waveformData = try? JSONEncoder().encode(recorder.audioLevels) {
            newMemo.waveformData = waveformData
        }

        do {
            try viewContext.save()
            print("✅ Memo saved with audio data for CloudKit sync")

            // Start transcription
            TranscriptionService.shared.transcribeVoiceMemo(newMemo, context: viewContext)
        } catch {
            let nsError = error as NSError
            print("❌ Error saving memo: \(nsError), \(nsError.userInfo)")
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    RecordingView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
