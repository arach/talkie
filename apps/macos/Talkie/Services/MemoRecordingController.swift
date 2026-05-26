//
//  MemoRecordingController.swift
//  Talkie
//
//  Recording controller for creating memos from Mac
//  Unlike RecordingController (for dictations), this saves audio and creates a memo
//

import SwiftUI
import TalkieKit
import AVFoundation
import Observation

// MARK: - Processing Step

/// A step in the post-recording processing pipeline
struct ProcessingStep: Identifiable, Equatable {
    let id: String
    let title: String
    var subtitle: String?
    var status: StepStatus

    enum StepStatus: Equatable {
        case pending
        case inProgress
        case completed
        case failed(String)

        var isComplete: Bool {
            if case .completed = self { return true }
            return false
        }
    }

    static func == (lhs: ProcessingStep, rhs: ProcessingStep) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.status == rhs.status
    }
}

// MARK: - Memo Recording Controller

@MainActor
@Observable
final class MemoRecordingController {
    static let shared = MemoRecordingController()

    // MARK: - State

    enum RecordingState: Equatable {
        case idle
        case preparing    // Immediate feedback while mic/engine spin up
        case recording
        case processing   // Post-recording pipeline
        case complete(MemoModel)
        case error(String)

        var isPreparing: Bool {
            if case .preparing = self { return true }
            return false
        }

        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }

        var isProcessing: Bool {
            if case .processing = self { return true }
            return false
        }

        var signalToken: String {
            switch self {
            case .idle:
                return "idle"
            case .preparing:
                return "preparing"
            case .recording:
                return "recording"
            case .processing:
                return "processing"
            case .complete:
                return "complete"
            case .error:
                return "error"
            }
        }
    }

    var state: RecordingState = .idle {
        didSet {
            guard state != oldValue else { return }
            CompanionRuntimeSignal.notify(reason: "memo-\(state.signalToken)")
        }
    }
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0  // For waveform visualization

    /// Processing pipeline steps - shown after recording stops
    var processingSteps: [ProcessingStep] = []

    /// Whether all processing steps are complete
    var allStepsComplete: Bool {
        !processingSteps.isEmpty && processingSteps.allSatisfy { $0.status.isComplete }
    }

    @ObservationIgnored
    private var timer: Timer?
    @ObservationIgnored
    private var startTime: Date?
    @ObservationIgnored
    private var audioRecorder: AVAudioRecorder?
    @ObservationIgnored
    private var tempAudioURL: URL?
    @ObservationIgnored
    private var levelTimer: Timer?
    @ObservationIgnored
    private var capturedScreenshots: [RecordingScreenshot] = []
    @ObservationIgnored
    private var capturedClips: [RecordingClip] = []
    @ObservationIgnored
    private var recordingId: UUID?
    @ObservationIgnored
    private(set) var targetNoteId: UUID?
    @ObservationIgnored
    private(set) var continuingMemoId: UUID?

    private let repository = LocalRepository()
    private let recordingRepository = TalkieObjectRepository()

    private init() {}

    // MARK: - Public Methods

    /// Start recording a new memo
    func startRecording() {
        // Immediate visual feedback
        state = .preparing

        // Check microphone permission first
        let micStatus = MicrophonePermission.status
        guard micStatus == .granted else {
            if micStatus == .notDetermined {
                Task {
                    let granted = await MicrophonePermission.request()
                    await MainActor.run {
                        if granted {
                            self.startRecording()
                        } else {
                            self.state = .error("Microphone access denied")
                            NotificationCenter.default.post(name: .showMicrophonePermissionRequired, object: nil)
                        }
                    }
                }
            } else {
                state = .error("Microphone access required")
                NotificationCenter.default.post(name: .showMicrophonePermissionRequired, object: nil)
            }
            return
        }

        // Check if engine is available for transcription
        guard ServiceManager.shared.engine.state == .running else {
            state = .error("TalkieAgent not running")
            NotificationCenter.default.post(name: .showEngineRequiredToast, object: nil)
            return
        }

        // Setup audio recording
        setupAudioRecording()

        // Single combined timer for elapsed time + audio levels (~15Hz)
        startTime = Date()
        audioRecorder?.isMeteringEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Elapsed time
                if let start = self.startTime {
                    self.elapsedTime = Date().timeIntervalSince(start)
                }
                // Audio level
                if let recorder = self.audioRecorder, recorder.isRecording {
                    recorder.updateMeters()
                    let db = recorder.averagePower(forChannel: 0)
                    self.audioLevel = max(0, (db + 60) / 60)
                }
            }
        }

        // Prepare capture state
        recordingId = UUID()
        capturedScreenshots = []
        capturedClips = []

        // Start recording
        audioRecorder?.record()
        state = .recording
    }

    /// Start recording audio for an existing note/recording
    func startRecordingForNote(noteId: UUID) {
        // Check microphone permission first
        let micStatus = MicrophonePermission.status
        guard micStatus == .granted else {
            if micStatus == .notDetermined {
                Task {
                    let granted = await MicrophonePermission.request()
                    await MainActor.run {
                        if granted {
                            self.startRecordingForNote(noteId: noteId)
                        } else {
                            self.state = .error("Microphone access denied")
                            NotificationCenter.default.post(name: .showMicrophonePermissionRequired, object: nil)
                        }
                    }
                }
            } else {
                state = .error("Microphone access required")
                NotificationCenter.default.post(name: .showMicrophonePermissionRequired, object: nil)
            }
            return
        }

        // Check if engine is available for transcription
        guard ServiceManager.shared.engine.state == .running else {
            state = .error("TalkieAgent not running")
            NotificationCenter.default.post(name: .showEngineRequiredToast, object: nil)
            return
        }

        // Setup audio recording
        setupAudioRecording()

        // Single combined timer for elapsed time + audio levels (~15Hz)
        startTime = Date()
        audioRecorder?.isMeteringEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let start = self.startTime {
                    self.elapsedTime = Date().timeIntervalSince(start)
                }
                if let recorder = self.audioRecorder, recorder.isRecording {
                    recorder.updateMeters()
                    let db = recorder.averagePower(forChannel: 0)
                    self.audioLevel = max(0, (db + 60) / 60)
                }
            }
        }

        // Set IDs — do NOT drain buffers (note already has its attachments)
        recordingId = noteId
        targetNoteId = noteId
        capturedScreenshots = []
        capturedClips = []

        // Start recording
        audioRecorder?.record()
        state = .recording
    }

    /// Start recording a continuation segment for an existing memo
    func startContinuingMemo(memoId: UUID) {
        state = .preparing

        let micStatus = MicrophonePermission.status
        guard micStatus == .granted else {
            if micStatus == .notDetermined {
                Task {
                    let granted = await MicrophonePermission.request()
                    await MainActor.run {
                        if granted {
                            self.startContinuingMemo(memoId: memoId)
                        } else {
                            self.state = .error("Microphone access denied")
                            NotificationCenter.default.post(name: .showMicrophonePermissionRequired, object: nil)
                        }
                    }
                }
            } else {
                state = .error("Microphone access required")
                NotificationCenter.default.post(name: .showMicrophonePermissionRequired, object: nil)
            }
            return
        }

        guard ServiceManager.shared.engine.state == .running else {
            state = .error("TalkieAgent not running")
            NotificationCenter.default.post(name: .showEngineRequiredToast, object: nil)
            return
        }

        setupAudioRecording()

        startTime = Date()
        audioRecorder?.isMeteringEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let start = self.startTime {
                    self.elapsedTime = Date().timeIntervalSince(start)
                }
                if let recorder = self.audioRecorder, recorder.isRecording {
                    recorder.updateMeters()
                    let db = recorder.averagePower(forChannel: 0)
                    self.audioLevel = max(0, (db + 60) / 60)
                }
            }
        }

        // Segment gets its own ID, linked to the parent memo
        recordingId = UUID()
        continuingMemoId = memoId
        capturedScreenshots = []
        capturedClips = []

        audioRecorder?.record()
        state = .recording

        Log(.audio).info("Started continuation recording for memo \(memoId.uuidString.prefix(8))")
    }

    /// Cancel recording for a note without saving
    func cancelRecordingForNote() {
        audioRecorder?.stop()
        audioRecorder = nil

        timer?.invalidate()
        timer = nil
        // levelTimer merged into main timer
        startTime = nil
        elapsedTime = 0
        audioLevel = 0

        // Clean up temp file
        if let url = tempAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempAudioURL = nil
        targetNoteId = nil
        recordingId = nil

        state = .idle
    }

    /// Stop recording and save as memo (or update existing note if targetNoteId is set)
    func stopRecording() {
        guard case .recording = state else { return }

        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
        // levelTimer merged into main timer

        // Initialize processing pipeline
        let duration = elapsedTime
        let durationText = formatDuration(duration)
        let isContinuation = continuingMemoId != nil
        let isNoteRecording = targetNoteId != nil
        let completeTitle = isContinuation ? "Segment added" : (isNoteRecording ? "Audio added" : "Memo created")
        processingSteps = [
            ProcessingStep(id: "recorded", title: "Recorded", subtitle: durationText, status: .completed),
            ProcessingStep(id: "saved", title: "File saved", subtitle: nil, status: .pending),
            ProcessingStep(id: "transcribing", title: "Transcribing", subtitle: nil, status: .pending),
            ProcessingStep(id: "complete", title: completeTitle, subtitle: nil, status: .pending)
        ]

        state = .processing

        Task {
            if isContinuation {
                await processContinuationAudio()
            } else if isNoteRecording {
                await processNoteAudio()
            } else {
                await processRecording()
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1f seconds", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }

    /// Update a processing step's status and subtitle
    private func updateStep(_ id: String, status: ProcessingStep.StepStatus, subtitle: String? = nil) {
        if let index = processingSteps.firstIndex(where: { $0.id == id }) {
            processingSteps[index].status = status
            if let subtitle = subtitle {
                processingSteps[index].subtitle = subtitle
            }
        }
    }

    /// Cancel recording without saving
    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder = nil

        timer?.invalidate()
        timer = nil
        // levelTimer merged into main timer
        startTime = nil
        elapsedTime = 0
        audioLevel = 0

        // Clean up temp file
        if let url = tempAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempAudioURL = nil

        // Clean up any captured screenshots and clips
        if let id = recordingId {
            ScreenshotStorage.delete(for: id)
            VideoClipStorage.delete(for: id)
        }
        capturedScreenshots = []
        capturedClips = []
        recordingId = nil
        continuingMemoId = nil

        state = .idle
    }

    /// Reset to idle state (after completion or error)
    func reset() {
        state = .idle
        elapsedTime = 0
        audioLevel = 0
        processingSteps = []
        capturedScreenshots = []
        capturedClips = []
        recordingId = nil
        targetNoteId = nil
        continuingMemoId = nil
    }

    // MARK: - Private Methods

    private func setupAudioRecording() {
        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "talkie-memo-\(UUID().uuidString).m4a"
        let url = tempDir.appendingPathComponent(filename)
        self.tempAudioURL = url

        // Audio settings - optimized for voice
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
        } catch {
            Log(.audio).error("Failed to create audio recorder: \(error)")
            state = .error("Failed to initialize recorder")
        }
    }

    private func processRecording() async {
        guard let tempURL = tempAudioURL else {
            await MainActor.run { state = .error("No recording found") }
            return
        }

        let duration = elapsedTime
        Log(.audio).info("Processing memo recording: \(tempURL.path), duration: \(duration)s")

        do {
            // Step 1: Save audio file
            await MainActor.run { updateStep("saved", status: .inProgress) }

            let memoId = recordingId ?? UUID()
            let audioPath = try await saveAudioFile(from: tempURL, memoId: memoId)

            // Get app support path for display
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let displayPath = "~/Library/Application Support/Talkie/Audio/\(audioPath)"
            await MainActor.run { updateStep("saved", status: .completed, subtitle: displayPath) }

            // Step 2: Transcribe
            let modelId = AgentSettings.shared.selectedModelId
            let modelName = modelId.replacingOccurrences(of: "-", with: " ").capitalized
            await MainActor.run { updateStep("transcribing", status: .inProgress, subtitle: "Using \(modelName)") }

            Log(.audio).info("Starting transcription with model: \(modelId)")
            let (transcript, timedTranscription) = try await EngineClient.shared.transcribeWithTimings(
                audioPath: tempURL.path,
                modelId: modelId,
                priority: .userInitiated,
                postProcess: .inverseTextNormalization
            )
            Log(.audio).info("Transcription complete: \(transcript.prefix(50))... (\(timedTranscription?.words.count ?? 0) word timings)")

            let wordCount = transcript.split(separator: " ").count
            await MainActor.run { updateStep("transcribing", status: .completed, subtitle: "\(wordCount) words") }

            // Step 3: Create and save memo
            await MainActor.run { updateStep("complete", status: .inProgress) }

            // Get device name for source
            let deviceName = Host.current().localizedName ?? "Mac"
            let originDeviceId = "mac-\(deviceName)"

            // Create memo model
            var memo = MemoModel(
                id: memoId,
                createdAt: Date(),
                lastModified: Date(),
                title: nil,  // Will be generated from transcript
                duration: duration,
                sortOrder: 0,
                transcription: transcript,
                audioFilePath: audioPath,
                isTranscribing: false,
                originDeviceId: originDeviceId,
                macReceivedAt: Date()
            )

            // Generate title from first line of transcript
            if let firstLine = transcript.components(separatedBy: .newlines).first,
               !firstLine.isEmpty {
                let title = String(firstLine.prefix(50))
                memo.title = title.count < firstLine.count ? title + "..." : title
            }

            // Save to database (both tables for unified view)
            try await repository.saveMemo(memo)

            // Create Recording with word-level timestamps and screenshot metadata
            var recording = TalkieObject(from: memo)
            var assets = recording.assets ?? TalkieObjectAssets()
            assets.segments = timedTranscription

            // If screenshots were captured during recording, interleave with transcript
            if !capturedScreenshots.isEmpty {
                assets.screenshots = capturedScreenshots

                // If we have word timings, create interleaved markdown for notes
                if let timed = timedTranscription {
                    let result = ScreenshotInserter.interleave(
                        timedTranscription: timed,
                        screenshots: capturedScreenshots
                    )
                    recording.notes = result.markdown
                }
            }

            // If video clips were captured during recording, serialize to JSON
            if !capturedClips.isEmpty {
                assets.clips = capturedClips
            }

            recording.assetsJSON = assets.toJSON()

            try await recordingRepository.saveRecording(recording)

            // Refresh views - both MemosViewModel and RecordingsViewModel
            await MemosViewModel.shared.loadMemos()
            await RecordingsViewModel.shared.loadRecordings()

            if SettingsManager.shared.extensionsFrameworkEnabled {
                // Track milestone progress via extension system
                ExtensionManager.shared.notifyMemoCreated(wordCount: wordCount)

                // Notify Apps (JS extensions)
                let manager = ExtensionManager.shared
                AppsRuntime.shared.notifyMemoCreated(
                    wordCount: wordCount,
                    memoCount: manager.memoCount,
                    totalWords: manager.totalWords
                )
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            tempAudioURL = nil

            await MainActor.run {
                updateStep("complete", status: .completed, subtitle: "Ready to view")
                state = .complete(memo)
            }

            Log(.database).info("Created memo from Mac recording: \(memoId)")

        } catch {
            Log(.audio).error("Failed to process memo recording: \(error)")
            await MainActor.run {
                // Mark current in-progress step as failed
                for i in processingSteps.indices {
                    if case .inProgress = processingSteps[i].status {
                        processingSteps[i].status = .failed(error.localizedDescription)
                        break
                    }
                }
                state = .error(error.localizedDescription)
            }
        }
    }

    private func processNoteAudio() async {
        guard let tempURL = tempAudioURL, let noteId = targetNoteId else {
            await MainActor.run { state = .error("No recording found") }
            return
        }

        let duration = elapsedTime
        Log(.audio).info("Processing note audio: \(tempURL.path), duration: \(duration)s, noteId: \(noteId)")

        do {
            // Step 1: Save audio file
            await MainActor.run { updateStep("saved", status: .inProgress) }

            let audioPath = try await saveAudioFile(from: tempURL, memoId: noteId)
            await MainActor.run { updateStep("saved", status: .completed) }

            // Step 2: Transcribe
            let modelId = AgentSettings.shared.selectedModelId
            let modelName = modelId.replacingOccurrences(of: "-", with: " ").capitalized
            await MainActor.run { updateStep("transcribing", status: .inProgress, subtitle: "Using \(modelName)") }

            let (transcript, timedTranscription) = try await EngineClient.shared.transcribeWithTimings(
                audioPath: tempURL.path,
                modelId: modelId,
                priority: .userInitiated,
                postProcess: .inverseTextNormalization
            )

            let wordCount = transcript.split(separator: " ").count
            await MainActor.run { updateStep("transcribing", status: .completed, subtitle: "\(wordCount) words") }

            // Step 3: Update existing recording, or create it if not yet persisted
            // (auto-save from DraftsScreen has a 2s debounce, so the note may not be in GRDB yet)
            await MainActor.run { updateStep("complete", status: .inProgress) }

            var recording: TalkieObject
            if var existing = try await recordingRepository.fetchRecording(id: noteId) {
                existing.audioFilename = audioPath
                existing.duration = duration
                // Append transcript to existing text rather than replacing it
                if let existingText = existing.text, !existingText.isEmpty {
                    existing.text = existingText + "\n\n" + transcript
                } else {
                    existing.text = transcript
                }
                var existingAssets = existing.assets ?? TalkieObjectAssets()
                existingAssets.segments = timedTranscription
                existing.assetsJSON = existingAssets.toJSON()
                existing.transcriptionStatus = .success
                existing.transcriptionModel = modelId
                existing.lastModified = Date()
                recording = existing
            } else {
                // Note wasn't persisted yet — create it as a new recording
                Log(.database).info("Note \(noteId) not in GRDB yet, creating new recording")
                recording = TalkieObject.newNote(id: noteId, text: transcript, title: nil)
                recording.audioFilename = audioPath
                recording.duration = duration
                var newAssets = recording.assets ?? TalkieObjectAssets()
                newAssets.segments = timedTranscription
                recording.assetsJSON = newAssets.toJSON()
                recording.transcriptionStatus = .success
                recording.transcriptionModel = modelId
                recording.lastModified = Date()
            }

            try await recordingRepository.saveRecording(recording)

            // Refresh views
            await RecordingsViewModel.shared.loadRecordings()

            // Clean up
            try? FileManager.default.removeItem(at: tempURL)
            tempAudioURL = nil

            await MainActor.run {
                updateStep("complete", status: .completed, subtitle: "Ready to view")
                targetNoteId = nil
                state = .idle
                processingSteps = []
            }

            Log(.database).info("Added audio to recording: \(noteId)")

        } catch {
            Log(.audio).error("Failed to process note audio: \(error)")
            await MainActor.run {
                for i in processingSteps.indices {
                    if case .inProgress = processingSteps[i].status {
                        processingSteps[i].status = .failed(error.localizedDescription)
                        break
                    }
                }
                targetNoteId = nil
                state = .error(error.localizedDescription)
            }
        }
    }

    private func processContinuationAudio() async {
        guard let tempURL = tempAudioURL, let parentId = continuingMemoId, let segmentId = recordingId else {
            Log(.audio).error("processContinuationAudio guard failed — tempURL: \(tempAudioURL != nil), continuingMemoId: \(continuingMemoId != nil), recordingId: \(recordingId != nil)")
            await MainActor.run { state = .error("No recording found") }
            return
        }

        let duration = elapsedTime
        Log(.audio).info("Processing continuation segment for memo \(parentId.uuidString.prefix(8)), duration: \(duration)s")

        do {
            // Step 1: Save audio file (using segment's own ID)
            await MainActor.run { updateStep("saved", status: .inProgress) }

            let audioPath = try await saveAudioFile(from: tempURL, memoId: segmentId)
            await MainActor.run { updateStep("saved", status: .completed) }

            // Step 2: Transcribe
            let modelId = AgentSettings.shared.selectedModelId
            let modelName = modelId.replacingOccurrences(of: "-", with: " ").capitalized
            await MainActor.run { updateStep("transcribing", status: .inProgress, subtitle: "Using \(modelName)") }

            let (transcript, timedTranscription) = try await EngineClient.shared.transcribeWithTimings(
                audioPath: tempURL.path,
                modelId: modelId,
                priority: .userInitiated,
                postProcess: .inverseTextNormalization
            )

            let wordCount = transcript.split(separator: " ").count
            await MainActor.run { updateStep("transcribing", status: .completed, subtitle: "\(wordCount) words") }

            // Step 3: Add segment to parent memo
            await MainActor.run { updateStep("complete", status: .inProgress) }

            var assets = TalkieObjectAssets()
            assets.segments = timedTranscription

            let segment = try await recordingRepository.addSegment(
                parentId: parentId,
                text: transcript,
                duration: duration,
                audioFilename: audioPath,
                transcriptionModel: modelId,
                assets: assets
            )

            // Refresh views
            await RecordingsViewModel.shared.loadRecordings()

            // Clean up
            try? FileManager.default.removeItem(at: tempURL)
            tempAudioURL = nil

            let segmentCount = try await recordingRepository.countSegments(forNoteId: parentId)
            await MainActor.run {
                updateStep("complete", status: .completed, subtitle: "Segment \(segmentCount) added")
                continuingMemoId = nil
                state = .idle
                processingSteps = []
            }

            Log(.database).info("✅ Continuation complete: segment \(segment.segmentIndex ?? 0) added to memo \(parentId.uuidString.prefix(8)), segmentCount=\(segmentCount), transcript=\(transcript.prefix(60))")

        } catch {
            Log(.audio).error("❌ Failed to process continuation: \(error)")
            await MainActor.run {
                for i in processingSteps.indices {
                    if case .inProgress = processingSteps[i].status {
                        processingSteps[i].status = .failed(error.localizedDescription)
                        break
                    }
                }
                continuingMemoId = nil
                state = .error(error.localizedDescription)
            }
        }
    }

    private func saveAudioFile(from tempURL: URL, memoId: UUID) async throws -> String {
        // Get audio storage directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let audioDir = appSupport.appendingPathComponent("Talkie/Audio", isDirectory: true)

        // Create directory if needed
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        // Copy file to permanent location
        let fileName = "\(memoId.uuidString).m4a"
        let destinationURL = audioDir.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: tempURL, to: destinationURL)

        // Background augmentation — VAD, opportunistic re-transcription,
        // embeddings, diarization (none registered yet, all TODO). Never
        // blocks the transcription-insertion critical path; this fires
        // after the user-facing save has already returned.
        var context = TKAugmentationContext()
        context["recording.id"] = memoId.uuidString
        MediaAugmentationService.shared.enqueue(
            AugmentationTask(
                assetURL: destinationURL,
                assetKind: .audio,
                context: context
            )
        )

        return fileName
    }

    // MARK: - Screenshot Capture (called by AppDelegate when recording is active)

    /// Capture a screenshot and attach it to the current recording.
    /// Called by AppDelegate's global Hyper+S handler when a recording is active.
    func captureScreenshot(mode: CaptureMode, preselectedRegion: CGRect? = nil) async {
        guard case .recording = state,
              let id = recordingId,
              let start = startTime else { return }

        let screenshot = await ScreenshotCaptureService.shared.capture(
            mode: mode,
            recordingId: id,
            recordingStartTime: start,
            preselectedRegion: preselectedRegion
        )

        if let screenshot {
            capturedScreenshots.append(screenshot)
            mirrorScreenshotToTrayIfNeeded(screenshot, fallbackMode: mode)
            Log(.system).info("Screenshot \(capturedScreenshots.count) captured at \(screenshot.timestampMs)ms mode=\(mode.rawValue)")
        }
    }

    private func mirrorScreenshotToTrayIfNeeded(_ screenshot: RecordingScreenshot, fallbackMode: CaptureMode) {
        guard FeatureFlags.shared.enableCapture else { return }

        let fileURL = ScreenshotStorage.screenshotsDirectory.appendingPathComponent(screenshot.filename)
        let captureMode = CaptureMode(rawValue: screenshot.captureMode) ?? fallbackMode

        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL) else { return }
            await ScreenshotTray.shared.add(
                data: data,
                width: screenshot.width ?? 0,
                height: screenshot.height ?? 0,
                mode: captureMode,
                windowTitle: screenshot.windowTitle,
                appName: screenshot.appName,
                displayName: screenshot.displayName
            )
        }
    }

}

// MARK: - Convenience Extensions

extension MemoRecordingController.RecordingState {
    var statusText: String {
        switch self {
        case .idle: return "Ready to record"
        case .preparing: return "Preparing…"
        case .recording: return "Recording..."
        case .processing: return "Processing..."
        case .complete: return "Memo saved!"
        case .error(let msg): return msg
        }
    }

    var icon: String {
        switch self {
        case .idle: return "mic.fill"
        case .preparing: return "mic.fill"
        case .recording: return "stop.fill"
        case .processing: return "gearshape.2"
        case .complete: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .cyan
        case .preparing: return .orange
        case .recording: return .red
        case .processing: return .orange
        case .complete: return .green
        case .error: return .red
        }
    }
}
