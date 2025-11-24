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
            VStack(spacing: 30) {
                Spacer()

                // Waveform visualization
                if recorder.isRecording {
                    VStack(spacing: 10) {
                        Text("Recording...")
                            .font(.headline)
                            .foregroundColor(.red)

                        WaveformView(
                            levels: recorder.audioLevels,
                            height: 100,
                            color: .red
                        )
                        .padding(.horizontal)

                        Text(formatDuration(recorder.recordingDuration))
                            .font(.system(.title, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .animation(.easeInOut, value: recorder.audioLevels)
                } else if hasStartedRecording {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Recording Saved")
                            .font(.title2)

                        TextField("Add title (optional)", text: $recordingTitle)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 40)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)

                        Text("Tap to start recording")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Recording button
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                recorder.isRecording ? Color.red : Color.gray.opacity(0.3),
                                lineWidth: 4
                            )
                            .frame(width: 80, height: 80)

                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 30, height: 30)
                        } else if !hasStartedRecording {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                                .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .padding(.bottom, 40)

                if hasStartedRecording && !recorder.isRecording {
                    Button(action: {
                        saveRecording()
                        dismiss()
                    }) {
                        Text("Save & Close")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: 200)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(recorder.isRecording ? "Recording" : "New Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if recorder.isRecording {
                            recorder.stopRecording()
                        }
                        dismiss()
                    }
                }

                if hasStartedRecording && !recorder.isRecording {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveRecording()
                            dismiss()
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
        newMemo.fileURL = url.absoluteString
        newMemo.isTranscribing = false

        // Save waveform data
        if let waveformData = try? JSONEncoder().encode(recorder.audioLevels) {
            newMemo.waveformData = waveformData
        }

        do {
            try viewContext.save()

            // Start transcription
            TranscriptionService.shared.transcribeVoiceMemo(newMemo, context: viewContext)
        } catch {
            let nsError = error as NSError
            print("Error saving memo: \(nsError), \(nsError.userInfo)")
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
