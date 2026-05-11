//
//  NoteComposeCard.swift
//  Talkie
//
//  Embedded compose editor for notes — same experience as the Compose screen.
//  Text editor with floating dictation pill, voice command bar, and AI actions.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct NoteComposeCard: View {
    let recording: TalkieObject
    @Binding var editedTranscript: String
    var onTranscriptChange: () -> Void = {}
    var onImmediateSave: () -> Void = {}
    var onCopy: () -> Void = {}

    private let settings = SettingsManager.shared
    private let repository = TalkieObjectRepository()

    // Dictation state (owned by this card, not parent)
    @State private var dictationPillState: DictationPillState = .idle
    @State private var dictationDuration: TimeInterval = 0
    @State private var dictationTimerRef: Task<Void, Never>?

    // Voice command state
    @State private var editorState = VoiceEditorState()
    @State private var isRecordingInstruction = false
    @State private var isTranscribingInstruction = false
    @State private var isPulsing = false
    @State private var pendingInstruction: String?
    @State private var showPromptDetails = false
    @State private var showHistory = false
    @State private var selectedRange: NSRange?
    @State private var initialized = false

    private var availableActions: [SmartAction] {
        SmartAction.combinedActionsForDrafts(appPreset: nil)
    }

    private var dictationOwnsCapture: Bool {
        dictationPillState == .recording || dictationPillState == .transcribing
    }

    private var instructionOwnsCapture: Bool {
        isRecordingInstruction || isTranscribingInstruction
    }

    private var dictationPillDisabled: Bool {
        !dictationOwnsCapture && instructionOwnsCapture
    }

    private var voicePromptDisabled: Bool {
        if isRecordingInstruction {
            return false
        }
        if isTranscribingInstruction {
            return true
        }
        return editorState.isProcessing || editorState.text.isEmpty || dictationOwnsCapture
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area: editing or reviewing
            Group {
                switch editorState.mode {
                case .editing:
                    editingContent
                case .reviewing:
                    if let diff = editorState.currentDiff {
                        reviewingContent(diff: diff)
                    } else {
                        editingContent
                    }
                }
            }

            // Command feedback bar
            if pendingInstruction != nil || editorState.isProcessing {
                commandFeedbackBar
            }

            Divider()
                .background(Theme.current.divider)

            // Action bar
            actionBar
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .strokeBorder(Theme.current.divider, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        .onAppear {
            guard !initialized else { return }
            initialized = true
            editorState.autoSaveEnabled = false  // TalkieView owns persistence
            editorState.currentNoteId = recording.id
            editorState.text = editedTranscript
            Task { await editorState.initializeLLMSettings() }
        }
        .onChange(of: recording.id) { _, _ in
            editorState.currentNoteId = recording.id
            editorState.text = editedTranscript
        }
        // Sync editorState.text -> editedTranscript (for parent's auto-save)
        .onChange(of: editorState.text) { _, newText in
            if editedTranscript != newText {
                editedTranscript = newText
                onTranscriptChange()
            }
        }
        // Sync editedTranscript -> editorState.text (for segment recording appends)
        .onChange(of: editedTranscript) { _, newText in
            if editorState.text != newText {
                editorState.text = newText
            }
        }
    }

    // MARK: - Editing Content

    private var editingContent: some View {
        ZStack(alignment: .bottom) {
            TalkieTextEditor(
                text: $editorState.text,
                selectedRange: $selectedRange,
                font: NSFont.systemFont(ofSize: 13 * settings.contentFontSize.scale),
                textColor: NSColor(Theme.current.foreground),
                insertionPointColor: NSColor(Theme.current.accent)
            )
            .padding(Spacing.md)
            .padding(.bottom, 40)
            .frame(minHeight: 200)
            .overlay(alignment: .topTrailing) {
                floatingCopyButton
                    .padding(Spacing.sm)
            }

            if editorState.isTransformingSelection {
                selectionIndicator
            }

            DictationPill(
                state: $dictationPillState,
                duration: $dictationDuration,
                onTap: handleDictationPillTap
            )
            .disabled(dictationPillDisabled)
            .padding(.bottom, Spacing.sm)
        }
    }

    private var selectionIndicator: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 10))
                    Text("Selection")
                        .font(Theme.current.fontXSBold)
                }
                .foregroundColor(settings.resolvedAccentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(settings.resolvedAccentColor.opacity(0.15))
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            Spacer()
        }
    }

    // MARK: - Reviewing Content

    private func reviewingContent(diff: TextDiff) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                diffPane(title: "ORIGINAL", indicatorColor: SemanticColor.error,
                         content: diff.attributedOriginal(baseColor: Theme.current.foreground, deleteColor: SemanticColor.error))
                Rectangle().fill(Theme.current.divider).frame(width: 1)
                diffPane(title: "PROPOSED", indicatorColor: SemanticColor.success,
                         content: diff.attributedProposed(baseColor: Theme.current.foreground, insertColor: SemanticColor.success))
            }
            .frame(minHeight: 200, maxHeight: 400)

            if let instruction = editorState.currentInstruction {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundColor(settings.resolvedAccentColor)
                    Text("You said:")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text(instruction)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(settings.resolvedAccentColor.opacity(0.1))
            }

            HStack(spacing: Spacing.md) {
                Text("\(diff.changeCount) change\(diff.changeCount == 1 ? "" : "s")")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                Spacer()
                Button(action: { editorState.rejectRevision() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        Text("REJECT").font(Theme.current.fontXSBold)
                    }
                    .foregroundColor(SemanticColor.error)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().stroke(SemanticColor.error, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: { editorState.acceptRevision() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                        Text("ACCEPT").font(Theme.current.fontXSBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(SemanticColor.success))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func diffPane(title: String, indicatorColor: Color, content: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(indicatorColor).frame(width: 6, height: 6)
                Text(title).font(Theme.current.fontXSBold).foregroundColor(Theme.current.foregroundMuted)
                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .background(Theme.current.backgroundSecondary)

            ScrollView {
                Text(content)
                    .font(Theme.current.contentFontBody)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Command Feedback Bar

    private var commandFeedbackBar: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.current.divider)

            HStack(spacing: Spacing.sm) {
                if editorState.isProcessing {
                    BrailleSpinner(size: 12)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundColor(settings.resolvedAccentColor)
                }

                Text(pendingInstruction ?? editorState.currentInstruction ?? "Processing...")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)

                Spacer()

                if editorState.isProcessing {
                    Button(action: { editorState.cancelGeneration() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel generation")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Theme.current.surface2.opacity(0.5))
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.sm) {
            voicePromptButton

            if editorState.isTransformingSelection {
                Text("Selection")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().stroke(Theme.current.foregroundMuted.opacity(0.3), lineWidth: 1))
            }

            ForEach(availableActions.prefix(3)) { action in
                quickActionChip(action)
            }

            Spacer()

            if let error = editorState.error {
                Text(error)
                    .font(Theme.current.fontXS)
                    .foregroundColor(SemanticColor.error)
                    .lineLimit(1)
            }

            if !editorState.revisions.isEmpty {
                historyButton
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var floatingCopyButton: some View {
        Button(action: { onCopy() }) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.current.foregroundMuted)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.current.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.current.divider, lineWidth: BorderWidth.thin)
                )
        }
        .buttonStyle(.plain)
        .opacity(editorState.text.isEmpty ? 0 : 0.7)
        .animation(.easeOut(duration: 0.15), value: editorState.text.isEmpty)
        .help("Copy text")
    }

    private var voicePromptButton: some View {
        Button(action: toggleVoicePrompt) {
            HStack(spacing: 6) {
                if isTranscribingInstruction {
                    BrailleSpinner(size: 12).foregroundColor(.white)
                } else if isRecordingInstruction {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "sparkle")
                            .font(.system(size: 7, weight: .bold))
                            .offset(x: 4, y: -2)
                    }
                }

                Text(isRecordingInstruction ? "STOP" : "Command")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(isRecordingInstruction ? .white : settings.resolvedAccentColor)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                Capsule().fill(isRecordingInstruction ? SemanticColor.error : settings.resolvedAccentColor.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(isRecordingInstruction
                            ? SemanticColor.error.opacity(isPulsing ? 0.6 : 0)
                            : settings.resolvedAccentColor.opacity(0.25),
                            lineWidth: isRecordingInstruction ? 2 : BorderWidth.thin)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)
            )
        }
        .buttonStyle(.plain)
        .disabled(voicePromptDisabled)
        .help("Speak to tell AI what to do with your text")
        .onChange(of: isRecordingInstruction) { _, isRecording in
            if isRecording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isPulsing = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { isPulsing = false }
            }
        }
    }

    private func quickActionChip(_ action: SmartAction) -> some View {
        Button(action: {
            Task { await editorState.requestRevision(instruction: action.defaultPrompt) }
        }) {
            HStack(spacing: 3) {
                Image(systemName: action.icon).font(.system(size: 9, weight: .medium))
                Text(action.name).font(Theme.current.fontXS)
            }
            .foregroundColor(Theme.current.foregroundSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule().fill(Theme.current.foreground.opacity(0.05))
            )
            .overlay(
                Capsule().stroke(Theme.current.foreground.opacity(0.12), lineWidth: BorderWidth.thin)
            )
        }
        .buttonStyle(.plain)
        .disabled(editorState.isProcessing || editorState.text.isEmpty)
    }

    private var historyButton: some View {
        Button(action: { showHistory.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 10, weight: .medium))
                Text("\(editorState.revisions.count)").font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(Theme.current.foregroundMuted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                Capsule().fill(Theme.current.surface2)
                    .overlay(Capsule().stroke(showHistory ? settings.resolvedAccentColor : Theme.current.divider, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showHistory) {
            historyPopover
        }
    }

    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EDIT HISTORY").font(Theme.current.fontXSBold).foregroundColor(Theme.current.foregroundMuted)
                Spacer()
                Text("\(editorState.revisions.count) edits").font(Theme.current.fontXS).foregroundColor(Theme.current.foregroundMuted)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(editorState.revisions.reversed()) { revision in
                        Button(action: { editorState.previewRevision(revision) }) {
                            HStack(spacing: Spacing.sm) {
                                Circle().fill(settings.resolvedAccentColor).frame(width: 6, height: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(revision.shortInstruction).font(Theme.current.fontSM).foregroundColor(Theme.current.foreground).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("\(revision.changeCount) changes").font(Theme.current.fontXS).foregroundColor(Theme.current.foregroundMuted)
                                        Text(revision.timeAgo).font(Theme.current.fontXS).foregroundColor(Theme.current.foregroundMuted)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs + 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.sm)
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 320)
        .background(Theme.current.background)
    }

    // MARK: - Dictation (Segment Recording)

    private func handleDictationPillTap() {
        switch dictationPillState {
        case .idle:
            guard !instructionOwnsCapture else { return }
            startDictationRecording()
        case .recording:
            stopDictationRecording()
        case .transcribing, .success:
            break
        }
    }

    private func startDictationRecording() {
        // Show recording UI immediately for instant feedback
        dictationPillState = .recording
        dictationDuration = 0

        dictationTimerRef = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                dictationDuration += 0.1
            }
        }

        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .composeDictation)
        } catch {
            log.error("Dictation start failed: \(error)")
            dictationTimerRef?.cancel()
            dictationTimerRef = nil
            dictationPillState = .idle
            editorState.error = error.localizedDescription
        }
    }

    private func stopDictationRecording() {
        dictationTimerRef?.cancel()
        dictationTimerRef = nil
        dictationPillState = .transcribing

        Task {
            do {
                let result = try await EphemeralTranscriber.shared.stopAndTranscribePersistent()

                if !result.text.isEmpty {
                    let noteId = recording.id

                    // Copy audio to persistent storage
                    let segmentId = UUID()
                    let audioFilename = "\(segmentId.uuidString).m4a"
                    let destURL = AudioStorage.audioDirectory.appendingPathComponent(audioFilename)
                    do {
                        try FileManager.default.moveItem(at: result.audioURL, to: destURL)
                    } catch {
                        try? FileManager.default.copyItem(at: result.audioURL, to: destURL)
                        try? FileManager.default.removeItem(at: result.audioURL)
                    }

                    // Count existing segments for index
                    let existingCount = try await repository.countSegments(forNoteId: noteId)

                    // Save segment recording
                    let segment = TalkieObject.newSegment(
                        parentId: noteId,
                        segmentIndex: existingCount,
                        text: result.text,
                        duration: dictationDuration,
                        audioFilename: audioFilename,
                        transcriptionModel: nil
                    )
                    try await repository.saveRecording(segment)

                    // Build the updated note text
                    var updatedText = editorState.text
                    let needsSpace = !updatedText.isEmpty && !updatedText.hasSuffix(" ") && !updatedText.hasSuffix("\n")
                    if needsSpace {
                        updatedText += " "
                    }
                    updatedText += result.text

                    // Save note text to DB immediately — don't rely on binding chain
                    let title = updatedText.components(separatedBy: .newlines).first.flatMap { $0.isEmpty ? nil : $0 }
                    try await repository.updateTitleAndText(id: noteId, title: title, text: updatedText)

                    // Append-only content history
                    try await repository.appendContentSnapshot(
                        recordingId: noteId, title: title, text: updatedText, source: .dictation
                    )

                    // Update UI state
                    editorState.text = updatedText
                    editedTranscript = updatedText
                    onImmediateSave()  // Updates parent's lastSaved snapshot to prevent redundant save

                    log.info("Dictation segment saved: \(result.text.count) chars, segment \(existingCount) for note \(noteId.uuidString.prefix(8))")
                }

                dictationPillState = .success
                try? await Task.sleep(for: .milliseconds(800))
                dictationPillState = .idle
            } catch {
                log.error("Dictation transcribe failed: \(error)")
                editorState.error = error.localizedDescription
                dictationPillState = .idle
            }
        }
    }

    // MARK: - Voice Prompt Actions

    private func toggleVoicePrompt() {
        if isRecordingInstruction {
            Task { await stopVoicePrompt() }
        } else {
            guard !dictationOwnsCapture else { return }
            startVoicePrompt()
        }
    }

    private func startVoicePrompt() {
        guard !isRecordingInstruction else { return }
        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .composeCommand)
            isRecordingInstruction = true
        } catch {
            log.error("Voice prompt capture failed: \(error)")
            editorState.error = error.localizedDescription
        }
    }

    private func stopVoicePrompt() async {
        guard isRecordingInstruction else { return }
        isRecordingInstruction = false
        isTranscribingInstruction = true

        do {
            let instruction = try await EphemeralTranscriber.shared.stopAndTranscribe()
            isTranscribingInstruction = false

            if !instruction.isEmpty {
                pendingInstruction = instruction
                await editorState.requestRevision(instruction: instruction)
                pendingInstruction = nil
            }
        } catch {
            log.error("Voice prompt transcribe failed: \(error)")
            isTranscribingInstruction = false
            pendingInstruction = nil
            editorState.error = error.localizedDescription
        }
    }
}
