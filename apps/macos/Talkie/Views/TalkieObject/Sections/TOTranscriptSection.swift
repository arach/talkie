//
//  TOTranscriptSection.swift
//  Talkie
//
//  Transcript section — displays or edits the recording's text.
//  Notes get a full embedded compose editor (NoteComposeCard).
//  Other types use RecordingTranscriptCard (read-only or editable).
//

import SwiftUI
import TalkieKit

struct TOTranscriptSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager
    var isEditing: Bool = false
    @Binding var editedTranscript: String
    @Binding var showJSON: Bool
    var isRetranscribing: Bool = false
    var onTranscriptChange: () -> Void = {}
    var onImmediateSave: () -> Void = {}
    var onRetranscribe: (String) -> Void = { _ in }
    var onCopy: () -> Void = {}
    var onContinueMemo: (() -> Void)? = nil
    /// Optional audio-seek hook propagated to RecordingTranscriptCard's
    /// paragraph timestamps. Takes absolute seconds.
    var onTimestampSeek: ((Double) -> Void)? = nil
    /// Current playback time, threaded into RecordingTranscriptCard so
    /// DocumentBody can render a "now playing" highlight on the
    /// matching paragraph.
    var currentTime: TimeInterval = 0

    private var needsTranscription: Bool {
        (recording.transcriptionStatus == .failed || recording.transcriptionStatus == .pending)
        && recording.hasAudio
    }

    /// Heuristic: a freshly-created memo whose transcription hasn't
    /// landed yet is almost certainly being auto-transcribed in the
    /// background. Showing the manual CTA in that window suggests
    /// "stuck — click here", which is wrong. After ~2 minutes we
    /// assume the auto pass didn't run and surface the manual CTA.
    private var isProbablyAutoTranscribing: Bool {
        guard recording.transcriptionStatus == .pending else { return false }
        guard recording.hasAudio else { return false }
        return Date().timeIntervalSince(recording.createdAt) < 120 || isRetranscribing
    }

    var body: some View {
        if recording.isNote {
            NoteComposeCard(
                recording: recording,
                editedTranscript: $editedTranscript,
                onTranscriptChange: onTranscriptChange,
                onImmediateSave: onImmediateSave,
                onCopy: onCopy
            )
        } else if isProbablyAutoTranscribing {
            transcribingActive
        } else if needsTranscription {
            transcriptionCTA
        } else if let text = recording.text, !text.isEmpty {
            RecordingTranscriptCard(
                text: text,
                recording: recording,
                showJSON: $showJSON,
                isEditing: isEditing,
                editedTranscript: $editedTranscript,
                isRetranscribing: isRetranscribing,
                onTranscriptChange: { onTranscriptChange() },
                onRetranscribe: { modelId in onRetranscribe(modelId) },
                onTimestampSeek: onTimestampSeek,
                currentTime: currentTime
            )
            // Continue-memo affordance moved into TOHeaderSection's
            // inlineActionRow as a real labeled chip. The previous
            // .overlay(alignment: .bottom) placement was clipping the
            // label and leaving a bare red dot floating between
            // sections; the new placement reads as "another action you
            // can take" alongside Copy/Share/Export, which is what it
            // is.
        } else if recording.hasAudio {
            transcriptionCTA
        } else {
            emptyState
        }
    }

    // MARK: - Transcription CTA

    private var transcriptionCTA: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TRANSCRIPT")
                .font(settings.fontXSMedium)
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundSecondary)

            VStack(spacing: Spacing.md) {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: recording.transcriptionStatus == .failed ? "exclamationmark.triangle" : "clock")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(recording.transcriptionStatus == .failed ? .orange : Theme.current.foregroundSecondary)

                    Text(recording.transcriptionStatus == .failed ? "Transcription Failed" : "Transcription Pending")
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if let error = recording.transcriptionError {
                        Text(error)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }

                if isRetranscribing {
                    HStack(spacing: Spacing.sm) {
                        BrailleSpinner(size: 12)
                        Text("Transcribing...")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                } else {
                    HStack(spacing: Spacing.sm) {
                        Button {
                            onRetranscribe("parakeet:v3")
                        } label: {
                            Label("Transcribe", systemImage: "waveform")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Menu {
                            Section("Parakeet") {
                                Button("V3 (25 languages, fast)") {
                                    onRetranscribe("parakeet:v3")
                                }
                                Button("V2 (English, most accurate)") {
                                    onRetranscribe("parakeet:v2")
                                }
                            }
                            Section("Whisper") {
                                Button("Small (balanced)") {
                                    onRetranscribe("whisper:openai_whisper-small")
                                }
                                Button("Large V3 (best quality)") {
                                    onRetranscribe("whisper:distil-whisper_distil-large-v3")
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.current.foreground.opacity(0.08))
                                )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Theme.current.foreground.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Theme.current.foreground.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Active Transcribing

    /// State for a freshly-recorded memo where the auto-transcribe
    /// pass is most likely still running. Replaces the manual CTA so
    /// users don't think the system is stuck and click "Transcribe"
    /// (which would queue a redundant pass).
    private var transcribingActive: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TRANSCRIPT")
                .font(settings.fontXSMedium)
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundSecondary)

            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    BrailleSpinner(size: 14)
                    Text(isRetranscribing ? "Transcribing…" : "Working on your transcript…")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                Text(isRetranscribing
                     ? "Your selected model is running. The transcript will appear here when it's ready."
                     : "Auto-transcribe is running on your recording. This usually takes a few seconds.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Theme.current.foreground.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Theme.current.foreground.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Transcript pending")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "waveform.circle")
                .font(settings.fontDisplay)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
            Text("NO TRANSCRIPT AVAILABLE")
                .font(Theme.current.fontSMBold)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
