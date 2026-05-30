//
//  SectionRouter.swift
//  Talkie
//
//  Routes a SectionSlot to the corresponding section view.
//  Each section receives the slot (for mode/chrome) and relevant state bindings.
//

import SwiftUI
import TalkieKit

/// Routes a SectionSlot to its concrete section view.
/// Sections self-gate: they render EmptyView if the recording has no relevant data.
struct SectionRouter: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager

    // Transcript state
    var isEditing: Bool = false
    @Binding var editedTranscript: String
    @Binding var showJSON: Bool
    var isRetranscribing: Bool = false
    var onTranscriptChange: () -> Void = {}
    var onImmediateSave: () -> Void = {}
    var onRetranscribe: (String) -> Void = { _ in }

    // Playback state
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var fetchedAudioURL: URL? = nil
    var onTogglePlayback: () -> Void = {}
    var onSeek: (Double) -> Void = { _ in }
    var onVolumeChange: (Float) -> Void = { _ in }
    var onRevealAudio: () -> Void = {}
    var onFetchFromiCloud: () -> Void = {}
    var isFetchingAudio: Bool = false
    var fetchAudioError: String? = nil

    // Notes state
    @Binding var editedNotes: String
    var showNotesSaved: Bool = false
    var onNotesChange: () -> Void = {}

    // Segments (continue memo)
    var onContinueMemo: () -> Void = {}
    var hasSegments: Bool = false
    var onSegmentsLoaded: ((Bool) -> Void)?

    // Action bar
    var pinnedWorkflows: [Workflow] = []
    var processingWorkflowIDs: Set<UUID> = []
    var onCopy: () -> Void = {}
    var onExecuteWorkflow: (Workflow) -> Void = { _ in }
    var onShowWorkflowPicker: () -> Void = {}
    var onStartRecording: () -> Void = {}

    // Workflow runs
    var cachedWorkflowRuns: [WorkflowRunModel] = []

    // Refinement
    @Binding var showOriginalText: Bool

    // Readout / TTS
    var readoutAudioURL: URL? = nil
    @Binding var isGeneratingTTS: Bool
    var onGenerateTTS: () -> Void = {}

    // Attachments
    @Binding var localAttachments: [RecordingAttachment]
    var onPickFiles: () -> Void = {}
    var onRemoveAttachment: (RecordingAttachment) -> Void = { _ in }

    // Text provenance
    var onInsertProvenance: (ProvenanceSegment) -> Void = { _ in }
    var onDismissProvenance: (ProvenanceSegment) -> Void = { _ in }

    var body: some View {
        switch slot.kind {
        case .transcript:
            TOTranscriptSection(
                slot: slot,
                recording: recording,
                settings: settings,
                isEditing: isEditing,
                editedTranscript: $editedTranscript,
                showJSON: $showJSON,
                isRetranscribing: isRetranscribing,
                onTranscriptChange: onTranscriptChange,
                onImmediateSave: onImmediateSave,
                onRetranscribe: onRetranscribe,
                onCopy: onCopy,
                onContinueMemo: recording.isMemo && recording.hasAudio ? onContinueMemo : nil,
                // Convert absolute seconds → progress (0..1) so the
                // shared playback onSeek handler can stay
                // progress-based. Use `recording.duration` (metadata,
                // always present) rather than the live-player duration
                // — that's 0 until the audio actually loads, which
                // would dead-disable seek before first play.
                onTimestampSeek: (recording.hasAudio && recording.duration > 0)
                    ? { seconds in onSeek(seconds / recording.duration) }
                    : nil,
                currentTime: currentTime
            )

        case .playback:
            if !hasSegments {
                TOPlaybackSection(
                    slot: slot,
                    recording: recording,
                    settings: settings,
                    isPlaying: isPlaying,
                    currentTime: currentTime,
                    duration: duration,
                    fetchedAudioURL: fetchedAudioURL,
                    onTogglePlayback: onTogglePlayback,
                    onSeek: onSeek,
                    onVolumeChange: onVolumeChange,
                    onRevealAudio: onRevealAudio,
                    onFetchFromiCloud: onFetchFromiCloud,
                    isFetchingAudio: isFetchingAudio,
                    fetchAudioError: fetchAudioError
                )
            }

        case .readout:
            TOReadoutSection(
                slot: slot,
                recording: recording,
                settings: settings,
                audioURL: readoutAudioURL ?? fetchedAudioURL,
                isPlaying: isPlaying,
                currentTime: currentTime,
                duration: duration,
                onTogglePlayback: onTogglePlayback,
                onSeek: onSeek,
                isGeneratingTTS: $isGeneratingTTS,
                onGenerateTTS: onGenerateTTS
            )

        case .mediaGallery:
            TOMediaGallerySection(
                slot: slot,
                recording: recording,
                settings: settings
            )

        case .attachments:
            TOAttachmentsSection(
                slot: slot,
                recording: recording,
                settings: settings,
                localAttachments: $localAttachments,
                onPickFiles: onPickFiles,
                onRemoveAttachment: onRemoveAttachment
            )

        case .notes:
            TONotesSection(
                slot: slot,
                recording: recording,
                settings: settings,
                editedNotes: $editedNotes,
                showNotesSaved: showNotesSaved,
                onNotesChange: onNotesChange
            )

        case .workflowRuns:
            TOWorkflowRunsSection(
                slot: slot,
                settings: settings,
                cachedWorkflowRuns: cachedWorkflowRuns
            )

        case .refinement:
            TORefinementSection(
                slot: slot,
                recording: recording,
                settings: settings,
                showOriginalText: $showOriginalText
            )

        case .dictationContext:
            TODictationContextSection(
                slot: slot,
                recording: recording,
                settings: settings
            )

        case .segments:
            TOSegmentsSection(
                slot: slot,
                recording: recording,
                settings: settings,
                onContinue: onContinueMemo,
                onSegmentsLoaded: onSegmentsLoaded
            )

        case .textProvenance:
            TOTextProvenanceSection(
                slot: slot,
                recording: recording,
                settings: settings,
                onInsert: onInsertProvenance,
                onDismiss: onDismissProvenance
            )

        case .actionBar:
            TOActionBarSection(
                slot: slot,
                recording: recording,
                settings: settings,
                pinnedWorkflows: pinnedWorkflows,
                processingWorkflowIDs: processingWorkflowIDs,
                onCopy: onCopy,
                onExecuteWorkflow: onExecuteWorkflow,
                onShowWorkflowPicker: onShowWorkflowPicker,
                onStartRecording: onStartRecording,
                onContinueMemo: onContinueMemo
            )
        }
    }
}
