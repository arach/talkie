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
    @State private var showSavedAnimation = false
    @State private var pulseDown = false
    @State private var defaultTitle = ""
    @State private var showDeleteConfirmation = false
    @State private var recPulse = false

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
                            // Recording indicator badge with pulsating animation
                            Text("REC")
                                .font(.techLabel)
                                .fontWeight(.bold)
                                .foregroundColor(.recording)
                                .tracking(2)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.recording.opacity(recPulse ? 0.2 : 0.08))
                                .cornerRadius(CornerRadius.sm)
                                .scaleEffect(recPulse ? 1.05 : 1.0)
                                .shadow(color: Color.recording.opacity(recPulse ? 0.5 : 0), radius: 8)
                                .animation(
                                    .easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true),
                                    value: recPulse
                                )
                                .onAppear { recPulse = true }

                            // Live waveform - fixed width, rolling display
                            LiveWaveformView(
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
                    } else if hasStartedRecording {
                        VStack(spacing: Spacing.lg) {
                            // Success icon with animation
                            ZStack {
                                Circle()
                                    .fill(Color.success.opacity(0.1))
                                    .frame(width: 64, height: 64)
                                    .scaleEffect(showSavedAnimation ? 1 : 0.5)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.success)
                                    .scaleEffect(showSavedAnimation ? 1 : 0)
                            }
                            .opacity(showSavedAnimation ? 1 : 0)

                            // Working title display
                            VStack(spacing: Spacing.xs) {
                                Text(defaultTitle)
                                    .font(.bodyLarge)
                                    .foregroundColor(.textPrimary)
                                    .multilineTextAlignment(.center)

                                Text(formatDuration(recorder.recordingDuration))
                                    .font(.monoSmall)
                                    .foregroundColor(.textSecondary)
                            }
                            .opacity(showSavedAnimation ? 1 : 0)
                            .offset(y: showSavedAnimation ? 0 : 10)

                            // Rename input
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("RENAME (OPTIONAL)")
                                    .font(.techLabelSmall)
                                    .tracking(1)
                                    .foregroundColor(.textTertiary)
                                    .padding(.leading, Spacing.sm)

                                TextField("e.g., Meeting notes", text: $recordingTitle)
                                    .font(.bodyMedium)
                                    .padding(Spacing.md)
                                    .background(Color.surfaceSecondary)
                                    .cornerRadius(CornerRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.md)
                                            .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                    )
                            }
                            .padding(.horizontal, Spacing.xl)
                            .opacity(showSavedAnimation ? 1 : 0)

                            // Action buttons
                            HStack(spacing: Spacing.md) {
                                // Delete button
                                Button(action: {
                                    showDeleteConfirmation = true
                                }) {
                                    HStack(spacing: Spacing.xs) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("DELETE")
                                            .font(.techLabel)
                                            .tracking(1)
                                    }
                                    .foregroundColor(.recording)
                                    .padding(.horizontal, Spacing.lg)
                                    .padding(.vertical, Spacing.md)
                                    .background(Color.recording.opacity(0.1))
                                    .cornerRadius(CornerRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.md)
                                            .strokeBorder(Color.recording.opacity(0.3), lineWidth: 1)
                                    )
                                }

                                // Done button
                                Button(action: {
                                    saveRecording()
                                    dismiss()
                                }) {
                                    HStack(spacing: Spacing.xs) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("SAVE")
                                            .font(.techLabel)
                                            .tracking(1)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, Spacing.xl)
                                    .padding(.vertical, Spacing.md)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.active, Color.activeGlow],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(CornerRadius.md)
                                    .shadow(color: Color.active.opacity(0.3), radius: 8, x: 0, y: 4)
                                }
                            }
                            .padding(.top, Spacing.md)
                            .opacity(showSavedAnimation ? 1 : 0)
                            .scaleEffect(showSavedAnimation ? 1 : 0.9)
                        }
                        .onAppear {
                            defaultTitle = "Recording \(formatDate(Date()))"
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                showSavedAnimation = true
                            }
                        }
                        .alert("Delete Recording?", isPresented: $showDeleteConfirmation) {
                            Button("Cancel", role: .cancel) { }
                            Button("Delete", role: .destructive) {
                                deleteRecording()
                                dismiss()
                            }
                        } message: {
                            Text("This recording will be permanently deleted.")
                        }
                    } else {
                        // Initial state - guide user to tap the record button
                        VStack(spacing: Spacing.md) {
                            Text("TAP TO RECORD")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textSecondary)

                            // Animated arrow pointing down
                            Image(systemName: "chevron.down")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.recording.opacity(0.7))
                                .offset(y: pulseDown ? 8 : 0)
                                .animation(
                                    .easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true),
                                    value: pulseDown
                                )
                                .onAppear { pulseDown = true }
                        }
                    }

                    Spacer()

                    // Recording button - only show when recording or ready to record
                    if recorder.isRecording || !hasStartedRecording {
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
                                } else {
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
                                }
                            }
                        }
                        .padding(.bottom, Spacing.xxl)
                    }
                }
            }
            .navigationTitle(recorder.isRecording ? "REC" : "NEW")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(recorder.isRecording ? "RECORDING" : "NEW MEMO")
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

    private func deleteRecording() {
        // Delete the temporary audio file
        if let url = recorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            AppLogger.recording.info("Deleted unsaved recording: \(url.lastPathComponent)")
        }
    }

    private func saveRecording() {
        guard let url = recorder.currentRecordingURL else { return }

        let newMemo = VoiceMemo(context: viewContext)
        newMemo.id = UUID()
        newMemo.title = recordingTitle.isEmpty ? defaultTitle : recordingTitle
        newMemo.createdAt = Date()
        newMemo.duration = recorder.recordingDuration
        newMemo.fileURL = url.lastPathComponent // Keep for backward compatibility
        newMemo.isTranscribing = false
        newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1) // Negative timestamp for newest first

        // Load and store audio data for CloudKit sync
        do {
            let audioData = try Data(contentsOf: url)
            newMemo.audioData = audioData
            AppLogger.recording.info("Audio data loaded: \(audioData.count) bytes")
        } catch {
            AppLogger.recording.warning("Failed to load audio data: \(error.localizedDescription)")
        }

        // Save waveform data
        if let waveformData = try? JSONEncoder().encode(recorder.audioLevels) {
            newMemo.waveformData = waveformData
        }

        do {
            // First save: persist the recording to Core Data (triggers iCloud sync)
            try viewContext.save()
            AppLogger.persistence.info("Memo saved with audio data for CloudKit sync")

            // Get the memo's ObjectID for safe background access
            let memoObjectID = newMemo.objectID

            // Start transcription AFTER save is complete
            // Use a slight delay to ensure the save has fully committed
            // and iCloud sync has been initiated
            Task { @MainActor in
                // Small delay to ensure Core Data save is fully committed
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // Fetch the memo fresh to ensure we have the persisted version
                if let savedMemo = viewContext.object(with: memoObjectID) as? VoiceMemo {
                    AppLogger.transcription.info("Starting transcription for persisted memo")
                    TranscriptionService.shared.transcribeVoiceMemo(savedMemo, context: viewContext)
                }
            }
        } catch {
            let nsError = error as NSError
            AppLogger.persistence.error("Error saving memo: \(nsError.localizedDescription)")
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
