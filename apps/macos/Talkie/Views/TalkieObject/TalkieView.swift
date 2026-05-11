//
//  TalkieView.swift
//  Talkie
//
//  The canonical view for rendering any TalkieObject.
//  Reads the type's recipe and renders sections via SectionRouter.
//  Owns all mutable state; sections receive bindings.
//

import SwiftUI
@preconcurrency import AVFoundation
import UniformTypeIdentifiers
import TalkieKit
import GRDB

private let log = Log(.ui)

struct TalkieView: View {
    let recording: TalkieObject
    var onDelete: (() -> Void)? = nil
    /// Override the type's default detail recipe (e.g. to promote media gallery to hero).
    var recipeOverride: [SectionSlot]? = nil

    private let settings = SettingsManager.shared
    private let repository = TalkieObjectRepository()

    // MARK: - State

    // Audio playback
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackTimer: Timer?

    // Notes
    @State private var editedNotes: String = ""
    @State private var notesSaveTimer: Timer?
    @State private var showNotesSaved = false
    @State private var notesInitialized = false

    // Edit mode
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedTranscript: String = ""
    @State private var isDirty = false
    @FocusState private var titleFieldFocused: Bool
    @State private var autoSaveTimer: Timer?

    // Last-saved snapshot — compare against this, not recording.text
    @State private var lastSavedTitle: String = ""
    @State private var lastSavedTranscript: String = ""

    /// Notes are always editable — no read/edit mode split.
    private var isAlwaysEditable: Bool { recording.isNote }
    private var effectiveIsEditing: Bool { isAlwaysEditable || isEditing }

    // Retranscription
    @State private var isRetranscribing = false

    // Segments (continued memos)
    @State private var hasSegments = false

    // Refinement
    @State private var showOriginalText = false

    // iCloud fetch
    @State private var isFetchingAudio = false
    @State private var fetchAudioError: String?
    @State private var fetchedAudioURL: URL?

    // Transcript
    @State private var showJSON = false
    @State private var transcriptVersions: [TranscriptVersionModel] = []

    // Workflow
    private let workflowService = WorkflowService.shared
    private let workflowPrefsRepository = WorkflowPreferencesRepository()
    @State private var processingWorkflowIDs: Set<UUID> = []
    @State private var showingWorkflowPicker = false
    @State private var cachedWorkflowRuns: [WorkflowRunModel] = []
    @State private var pinnedWorkflows: [Workflow] = []

    // Delete confirmation
    @State private var showDeleteConfirmation = false

    // TTS / Readout
    @State private var isGeneratingTTS = false

    // Attachments
    @State private var isDropTargeted = false
    @State private var localAttachments: [RecordingAttachment] = []

    // Debug
    #if DEBUG
    @State private var showingPowerInspector = false
    #endif

    // Keep transcript/notes/attachments readable on wide inspector columns.
    private let contentColumnMaxWidth: CGFloat = 860

    private var detailSlots: [SectionSlot] {
        recipeOverride ?? recording.type.detailRecipe
    }

    @MainActor
    private var bodyContent: AnyView {
        AnyView(
            ScrollView(.vertical, showsIndicators: true) {
                scrollContent
            }
        )
    }

    @MainActor
    private var scrollContent: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // Fixed header zone — aligns with sidebar/list primary band
                Color.clear
                    .frame(height: PageLayout.headerHeight)

                // Metadata cells — sits directly under the structural line,
                // aligned with the filter bar in the list column
                TOMetadataRow(recording: recording, settings: settings)
                    .padding(.bottom, Spacing.md)

                detailContent
            }
            .frame(maxWidth: contentColumnMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PageLayout.horizontalPadding)
            .padding(.top, 0)
            .padding(.bottom, PageLayout.bottomPadding)
        )
    }

    @MainActor
    private var detailContent: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection
                recipeSections
                deleteButton

                Spacer()
            }
        )
    }

    @MainActor
    private var headerSection: some View {
        TOHeaderSection(
            recording: recording,
            settings: settings,
            isEditing: effectiveIsEditing,
            isAlwaysEditable: isAlwaysEditable,
            editedTitle: $editedTitle,
            titleFieldFocused: $titleFieldFocused,
            onToggleEdit: { toggleEditMode() },
            onCancelEdit: { cancelEditing() },
            onSaveEdit: { saveChanges() },
            onDelete: { showDeleteConfirmation = true },
            onOpenInCompose: openInComposeAction,
            isDirty: isDirty,
            onTitleChange: titleChangeAction
        )
    }

    @MainActor
    private var openInComposeAction: (() -> Void)? {
        recording.isNote ? nil : { openInCompose() }
    }

    @MainActor
    private var titleChangeAction: (() -> Void)? {
        isAlwaysEditable ? { scheduleSave() } : nil
    }

    @MainActor
    private var recipeSections: AnyView {
        AnyView(
            ForEach(detailSlots.indices, id: \.self) { index in
                recipeSection(at: index)
            }
        )
    }

    @MainActor
    private func recipeSection(at index: Int) -> AnyView {
        AnyView(sectionRouter(for: detailSlots[index]))
    }

    @MainActor
    private var deleteButton: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(settings.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .buttonStyle(.plain)
            .help("Delete this item")
        }
    }

    // MARK: - Body

    var body: some View {
        bodyContent
        // Drop target overlay
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .strokeBorder(settings.resolvedAccentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(settings.resolvedAccentColor.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                    .padding(Spacing.sm)
                    .overlay {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 32, weight: .thin))
                            Text("Drop files to attach")
                                .font(Theme.current.fontSM)
                        }
                        .foregroundColor(settings.resolvedAccentColor)
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image, .pdf], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Theme.current.background
                LinearGradient(
                    colors: [
                        Theme.current.foreground.opacity(0.02),
                        Color.clear,
                        Theme.current.background.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        // Lifecycle
        .onAppear {
            let title = recording.title ?? ""
            let transcript = recording.text ?? ""
            editedTitle = title
            editedTranscript = transcript
            lastSavedTitle = title
            lastSavedTranscript = transcript
            editedNotes = recording.notes ?? ""
            localAttachments = recording.attachments
            scheduleNotesInitialization()
            // Probe for audio by recording ID (covers TTS audio from iOS sync or workflows)
            if !recording.hasAudio && AudioStorage.exists(forRecordingID: recording.id) {
                fetchedAudioURL = AudioStorage.url(forRecordingID: recording.id)
            }
            Task {
                async let runs: () = fetchWorkflowRuns()
                async let pinned: () = fetchPinnedWorkflows()
                async let versions: () = fetchTranscriptVersions()
                _ = await (runs, pinned, versions)
            }
        }
        .onChange(of: recording.id) { oldId, _ in
            // Save pending changes for the OLD note in background, then reset to the new one.
            let pendingSave = needsSave
            resetStateWithoutFlush()
            if pendingSave {
                Task { saveNow(forRecordingId: oldId) }
            }
        }
        .onDisappear {
            saveNow(forRecordingId: recording.id)
        }
        .onChange(of: recording.text) { _, newText in
            // Sync from DB only when we don't have unsaved local changes
            if !needsSave {
                editedTranscript = newText ?? ""
                lastSavedTranscript = newText ?? ""
            }
        }
        // Sheets
        .sheet(isPresented: $showingWorkflowPicker) {
            WorkflowPickerSheet(
                memo: recording.toMemoModel(),
                onSelect: { workflow in
                    showingWorkflowPicker = false
                    executeWorkflow(workflow)
                },
                onCancel: {
                    showingWorkflowPicker = false
                }
            )
        }
        .alert("Delete Recording", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteRecording() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be permanently deleted.")
        }
        #if DEBUG
        .sheet(isPresented: $showingPowerInspector) {
            RecordingPowerInspector(recording: recording)
        }
        .background {
            Button("") { showingPowerInspector = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .hidden()
        }
        #endif
    }

    // MARK: - Section Router Factory

    private func sectionRouter(for slot: SectionSlot) -> SectionRouter {
        SectionRouter(
            slot: slot,
            recording: recording,
            settings: settings,
            isEditing: effectiveIsEditing,
            editedTranscript: $editedTranscript,
            showJSON: $showJSON,
            isRetranscribing: isRetranscribing,
            onTranscriptChange: {
                if isAlwaysEditable {
                    scheduleSave()
                } else {
                    isDirty = needsSave
                }
            },
            onImmediateSave: { saveNow(forRecordingId: recording.id) },
            onRetranscribe: { modelId in retranscribe(modelId: modelId) },
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            fetchedAudioURL: fetchedAudioURL,
            onTogglePlayback: togglePlayback,
            onSeek: seekTo,
            onVolumeChange: { newVolume in audioPlayer?.volume = newVolume },
            onRevealAudio: revealAudioInFinder,
            onFetchFromiCloud: { Task { await fetchAudioFromiCloud() } },
            isFetchingAudio: isFetchingAudio,
            fetchAudioError: fetchAudioError,
            editedNotes: $editedNotes,
            showNotesSaved: showNotesSaved,
            onNotesChange: { debouncedSaveNotes() },
            onContinueMemo: {
                MemoRecordingController.shared.startContinuingMemo(memoId: recording.id)
            },
            hasSegments: hasSegments,
            onSegmentsLoaded: { hasSegments = $0 },
            pinnedWorkflows: pinnedWorkflows,
            processingWorkflowIDs: processingWorkflowIDs,
            onCopy: copyTranscript,
            onExecuteWorkflow: executeWorkflow,
            onShowWorkflowPicker: { showingWorkflowPicker = true },
            onStartRecording: {
                MemoRecordingController.shared.startRecordingForNote(noteId: recording.id)
            },
            cachedWorkflowRuns: cachedWorkflowRuns,
            showOriginalText: $showOriginalText,
            isGeneratingTTS: $isGeneratingTTS,
            onGenerateTTS: generateCloudTTS,
            localAttachments: $localAttachments,
            onPickFiles: pickFiles,
            onRemoveAttachment: removeAttachment,
            onInsertProvenance: { segment in insertProvenance(segment) },
            onDismissProvenance: { segment in dismissProvenance(segment) }
        )
    }

    // MARK: - Provenance Actions

    /// Append provenance text to canonical transcript, mark segment as applied.
    /// Canonical text is user-owned — this only runs on explicit user action.
    private func insertProvenance(_ segment: ProvenanceSegment) {
        let appendix = segment.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appendix.isEmpty else { return }

        if editedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editedTranscript = appendix
        } else {
            editedTranscript = editedTranscript + "\n\n" + appendix
        }
        saveNow(forRecordingId: recording.id, source: .typing)

        markProvenance(segment.id) { seg in
            seg.appliedAt = Date()
        }
    }

    private func dismissProvenance(_ segment: ProvenanceSegment) {
        Task {
            do {
                guard let fresh = try await repository.fetchRecording(id: recording.id) else { return }
                var assets = fresh.assets ?? TalkieObjectAssets()
                var list = assets.textProvenance ?? []
                list.removeAll { $0.id == segment.id }
                assets.textProvenance = list.isEmpty ? nil : list
                try await repository.updateAssets(id: recording.id, assetsJSON: assets.isEmpty ? nil : assets.toJSON())
            } catch {
                log.error("Failed to dismiss provenance: \(error.localizedDescription)")
            }
        }
    }

    private func markProvenance(_ id: UUID, mutate: @escaping (inout ProvenanceSegment) -> Void) {
        Task {
            do {
                guard let fresh = try await repository.fetchRecording(id: recording.id) else { return }
                var assets = fresh.assets ?? TalkieObjectAssets()
                guard var list = assets.textProvenance,
                      let idx = list.firstIndex(where: { $0.id == id }) else { return }
                mutate(&list[idx])
                assets.textProvenance = list
                try await repository.updateAssets(id: recording.id, assetsJSON: assets.toJSON())
            } catch {
                log.error("Failed to update provenance: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - State Reset

    /// Whether local edits differ from last-saved snapshot.
    private var needsSave: Bool {
        editedTitle != lastSavedTitle || editedTranscript != lastSavedTranscript
    }

    /// The single save gate. All triggers (debounce, dictation, navigation) call this.
    /// Writes to DB only if content changed since last save. Idempotent.
    /// Appends to content_history on every real change (append-only log).
    private func saveNow(forRecordingId id: UUID, source: ContentSnapshot.Source = .typing) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        // Capture values before async — avoid reading stale state later
        let title = editedTitle
        let transcript = editedTranscript

        guard title != lastSavedTitle || transcript != lastSavedTranscript else { return }

        // Track whether transcript actually changed (for versioning)
        let transcriptChanged = transcript != lastSavedTranscript

        // Update snapshot immediately to prevent re-entrant saves
        lastSavedTitle = title
        lastSavedTranscript = transcript
        isDirty = false

        Task {
            do {
                try await repository.updateTitleAndText(
                    id: id,
                    title: title.isEmpty ? nil : title,
                    text: transcript
                )

                // Append-only content history
                if transcriptChanged {
                    try await repository.appendContentSnapshot(
                        recordingId: id,
                        title: title.isEmpty ? nil : title,
                        text: transcript,
                        source: source
                    )
                }

                log.info("Saved \(id.uuidString.prefix(8)) [\(source.rawValue), \(transcript.count) chars]")
            } catch {
                log.error("Save failed for \(id.uuidString.prefix(8)): \(error.localizedDescription)")
            }
        }
    }

    /// Schedule a debounced save (for typing). Resets on each call.
    private func scheduleSave() {
        autoSaveTimer?.invalidate()
        let recordingID = recording.id
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            Task { @MainActor in
                autoSaveTimer = nil
                saveNow(forRecordingId: recordingID)
            }
        }
    }

    /// Reset all editing state for a new recording (no flush — caller handles that).
    private func resetStateWithoutFlush() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        isEditing = false
        isDirty = false
        let title = recording.title ?? ""
        let transcript = recording.text ?? ""
        editedTitle = title
        editedTranscript = transcript
        lastSavedTitle = title
        lastSavedTranscript = transcript
        editedNotes = recording.notes ?? ""
        localAttachments = recording.attachments
        notesInitialized = false

        isPlaying = false
        audioPlayer?.stop()
        audioPlayer = nil
        currentTime = 0
        fetchedAudioURL = nil
        // Probe for audio by recording ID
        if !recording.hasAudio && AudioStorage.exists(forRecordingID: recording.id) {
            fetchedAudioURL = AudioStorage.url(forRecordingID: recording.id)
        }

        scheduleNotesInitialization()
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            stopPlaybackTimer()
            isPlaying = false
        } else if audioPlayer != nil {
            audioPlayer?.play()
            startPlaybackTimer()
            isPlaying = true
        } else {
            guard let audioURL = fetchedAudioURL ?? recording.audioURL else {
                log.warning("No audio file for recording \(recording.id)")
                return
            }

            // Load audio data off main thread to avoid blocking UI on large files
            let playbackVolume = settings.playbackVolume
            Task.detached(priority: .userInitiated) {
                do {
                    let data = try Data(contentsOf: audioURL)
                    await MainActor.run {
                        do {
                            let player = try AVAudioPlayer(data: data)
                            audioPlayer = player
                            player.volume = playbackVolume
                            player.prepareToPlay()
                            duration = player.duration
                            player.play()
                            startPlaybackTimer()
                            isPlaying = true
                        } catch {
                            log.error("Failed to create audio player: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    await MainActor.run {
                        log.error("Failed to play audio: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let player = audioPlayer else { return }
                currentTime = player.currentTime
                if !player.isPlaying && currentTime >= duration - 0.1 {
                    stopPlaybackTimer()
                    isPlaying = false
                    currentTime = 0
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func seekTo(_ progress: Double) {
        guard let player = audioPlayer else { return }
        let time = progress * player.duration
        player.currentTime = time
        currentTime = time
    }

    private func revealAudioInFinder() {
        if let audioURL = fetchedAudioURL ?? recording.audioURL {
            NSWorkspace.shared.activateFileViewerSelecting([audioURL])
        }
    }

    private func fetchAudioFromiCloud() async {
        isFetchingAudio = true
        fetchAudioError = nil
        do {
            _ = try await SyncClient.shared.fetchAudioForMemo(memoID: recording.id)
            let url = AudioStorage.audioDirectory.appendingPathComponent("\(recording.id.uuidString).m4a")
            if FileManager.default.fileExists(atPath: url.path) {
                fetchedAudioURL = url
            }
            NotificationCenter.default.post(name: .syncDataAvailable, object: nil)
        } catch {
            fetchAudioError = error.localizedDescription
        }
        isFetchingAudio = false
    }

    // MARK: - Cloud TTS Generation

    private func generateCloudTTS() {
        guard !isGeneratingTTS, let text = recording.text, !text.isEmpty else { return }

        isGeneratingTTS = true
        Task {
            defer { isGeneratingTTS = false }
            do {
                let settings = SettingsManager.shared
                // Try OpenAI TTS first (most common), then ElevenLabs
                let audioFileURL: URL
                if let openaiKey = settings.openaiApiKey, !openaiKey.isEmpty {
                    // selectedTTSVoiceId is prefixed (e.g. "openai:echo") — resolve to raw API voice name
                    let rawVoice: String
                    if let catalogVoice = OpenAITTSVoiceCatalog.voice(byId: settings.selectedTTSVoiceId) {
                        rawVoice = catalogVoice.voiceId
                    } else if settings.selectedTTSVoiceId.hasPrefix("openai:") {
                        rawVoice = String(settings.selectedTTSVoiceId.dropFirst("openai:".count))
                    } else {
                        rawVoice = "alloy"
                    }
                    audioFileURL = try await TTSService.synthesizeOpenAI(text: text, voice: rawVoice, apiKey: openaiKey)
                } else if let elevenKey = settings.fetchElevenLabsKey(), !elevenKey.isEmpty {
                    // Resolve ElevenLabs voice ID from catalog
                    let elVoiceId: String
                    if let catalogVoice = TTSVoiceCatalog.voice(byId: settings.selectedTTSVoiceId) {
                        elVoiceId = catalogVoice.voiceId
                    } else {
                        elVoiceId = "21m00Tcm4TlvDq8ikWAM" // Rachel default
                    }
                    audioFileURL = try await TTSService.synthesizeElevenLabs(text: text, voiceId: elVoiceId, apiKey: elevenKey)
                } else {
                    log.warning("No cloud TTS API key configured — using on-device voice")
                    return
                }

                // Copy generated audio to AudioStorage keyed by recording ID
                let audioData = try Data(contentsOf: audioFileURL)
                AudioStorage.save(audioData, forRecordingID: recording.id)
                let savedURL = AudioStorage.url(forRecordingID: recording.id)
                fetchedAudioURL = savedURL

                // Auto-play
                togglePlayback()

                log.info("Generated TTS audio for \(recording.id.uuidString.prefix(8))")
            } catch {
                log.error("Cloud TTS failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Notes

    private func debouncedSaveNotes() {
        guard notesInitialized else { return }
        notesSaveTimer?.invalidate()
        withAnimation { showNotesSaved = false }

        notesSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            Task { @MainActor in
                saveNotes()
            }
        }
    }

    private func saveNotes() {
        Task {
            do {
                try await repository.updateNotes(id: recording.id, notes: editedNotes)

                await MainActor.run {
                    withAnimation { showNotesSaved = true }
                }
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    withAnimation { showNotesSaved = false }
                }
            } catch {
                log.error("Failed to save notes: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Compose

    private func openInCompose() {
        let text = recording.text ?? ""
        guard !text.isEmpty else { return }
        NavigationState.shared.navigateToCompose(withText: text, sourceRecordingId: recording.id)
    }

    // MARK: - Edit Mode

    private func toggleEditMode() {
        if isEditing {
            saveNow(forRecordingId: recording.id)
            isEditing = false
            titleFieldFocused = false
        } else {
            editedTitle = recording.title ?? ""
            editedTranscript = recording.text ?? ""
            lastSavedTitle = editedTitle
            lastSavedTranscript = editedTranscript
            isEditing = true
            isDirty = false
        }
    }

    private func saveChanges() {
        saveNow(forRecordingId: recording.id)
        titleFieldFocused = false
    }

    private func cancelEditing() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        editedTitle = lastSavedTitle
        editedTranscript = lastSavedTranscript
        isDirty = false
        titleFieldFocused = false
        isEditing = false
    }

    // MARK: - Retranscription

    private func retranscribe(modelId: String) {
        isRetranscribing = true

        Task {
            do {
                let newTranscript = try await RecordingRetranscriptionService.shared.retranscribe(
                    recording,
                    modelId: modelId
                )

                await MainActor.run {
                    editedTranscript = newTranscript
                    lastSavedTranscript = newTranscript
                    isDirty = false
                    isRetranscribing = false
                }

                await fetchTranscriptVersions()
            } catch {
                log.error("Retranscription failed: \(error.localizedDescription)")
                await RecordingRetranscriptionService.shared.persistFailureState(
                    for: recording,
                    errorMessage: error.localizedDescription
                )
                await MainActor.run { isRetranscribing = false }
            }
        }
    }

    // MARK: - Quick Actions

    private func copyTranscript() {
        guard let text = recording.text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Transcript Versions

    private func fetchTranscriptVersions() async {
        do {
            let versions = try await repository.fetchTranscriptVersions(for: recording.id)
            transcriptVersions = versions
        } catch {
            log.error("Failed to fetch transcript versions: \(error.localizedDescription)")
        }
    }

    // MARK: - Workflows

    private func fetchPinnedWorkflows() async {
        do {
            let pinnedIDs = try workflowPrefsRepository.fetchPinnedIDs()
            let workflows = pinnedIDs.compactMap { workflowService.workflow(byID: $0) }
            pinnedWorkflows = workflows
        } catch {
            log.error("Failed to fetch pinned workflows: \(error.localizedDescription)")
        }
    }

    private func fetchWorkflowRuns() async {
        do {
            let db = try DatabaseManager.shared.database()
            let runs = try await db.read { db in
                try WorkflowRunModel
                    .filter(Column("memoId") == recording.id)
                    .order(Column("runDate").desc)
                    .limit(10)
                    .fetchAll(db)
            }
            cachedWorkflowRuns = runs
        } catch {
            log.error("Failed to fetch workflow runs: \(error.localizedDescription)")
        }
    }

    private func executeWorkflow(_ workflow: Workflow) {
        processingWorkflowIDs.insert(workflow.id)

        Task {
            do {
                _ = try await WorkflowExecutor.shared.executeWorkflow(
                    workflow.definition,
                    for: recording.toMemoModel()
                )
                await fetchWorkflowRuns()
            } catch {
                log.error("Workflow failed: \(workflow.name) - \(error.localizedDescription)")
            }

            await MainActor.run {
                _ = processingWorkflowIDs.remove(workflow.id)
            }
        }
    }

    private func scheduleNotesInitialization() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            notesInitialized = true
        }
    }

    // MARK: - Delete

    private func deleteRecording() {
        Task {
            if recording.type == .memo || recording.type == .note {
                try? await repository.softDeleteRecording(id: recording.id)
            } else {
                try? await repository.hardDeleteRecording(id: recording.id)
            }
            onDelete?()
        }
    }

    // MARK: - Attachments

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose files to attach"
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                addAttachmentFromURL(url)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        addAttachmentFromURL(url)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage,
                          let tiff = image.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    Task { @MainActor in
                        let name = "dropped_image_\(Int(Date().timeIntervalSince1970)).png"
                        guard let result = AttachmentStorage.save(data: png, originalName: name, recordingId: recording.id) else { return }
                        let attachment = RecordingAttachment(
                            filename: result.filename,
                            originalName: name,
                            kind: .image,
                            fileSizeBytes: result.size,
                            width: Int(image.size.width),
                            height: Int(image.size.height)
                        )
                        localAttachments.append(attachment)
                        saveAttachments()
                    }
                }
            }
        }
    }

    private func addAttachmentFromURL(_ url: URL) {
        guard let result = AttachmentStorage.save(from: url, recordingId: recording.id) else { return }
        let ext = url.pathExtension
        let kind = AttachmentKind.from(extension: ext)

        var width: Int?
        var height: Int?
        if kind == .image, let image = NSImage(contentsOf: url) {
            width = Int(image.size.width)
            height = Int(image.size.height)
        }

        let attachment = RecordingAttachment(
            filename: result.filename,
            originalName: url.lastPathComponent,
            kind: kind,
            fileSizeBytes: result.size,
            width: width,
            height: height
        )
        localAttachments.append(attachment)
        saveAttachments()
    }

    private func removeAttachment(_ attachment: RecordingAttachment) {
        AttachmentStorage.delete(filename: attachment.filename)
        localAttachments.removeAll { $0.filename == attachment.filename }
        saveAttachments()
    }

    private func saveAttachments() {
        Task {
            do {
                // Fetch fresh assets from DB to avoid overwriting other asset fields
                let fresh = try await repository.fetchRecording(id: recording.id)
                var assets = fresh?.assets ?? TalkieObjectAssets()
                assets.attachments = localAttachments
                try await repository.updateAssets(id: recording.id, assetsJSON: assets.toJSON())
            } catch {
                log.error("Failed to save attachments: \(error)")
            }
        }
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
