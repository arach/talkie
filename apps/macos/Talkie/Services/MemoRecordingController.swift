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

private struct AudioFileMeasurement {
    let duration: TimeInterval
    let byteCount: Int
    let sampleRate: Double
    let frameCount: AVAudioFramePosition
    let readableFrameCount: AVAudioFrameCount
}

private enum MemoRecordingError: LocalizedError {
    case unreadableAudioFile(String)
    case unusableAudio(duration: TimeInterval)
    case incompleteRecording(expected: TimeInterval, actual: TimeInterval)
    case copiedAudioMismatch(source: TimeInterval, destination: TimeInterval)
    case copiedAudioByteMismatch(source: Int, destination: Int)

    var errorDescription: String? {
        switch self {
        case .unreadableAudioFile(let filename):
            return "Could not read recorded audio file: \(filename)"
        case .unusableAudio(let duration):
            return "Recording is too short to use (\(Self.displayDuration(duration)))."
        case .incompleteRecording(let expected, let actual):
            return "Recording stopped early: captured \(Self.displayDuration(actual)) of \(Self.displayDuration(expected)). Please try again."
        case .copiedAudioMismatch(let source, let destination):
            return "Saved audio duration mismatch: source \(Self.displayDuration(source)), saved \(Self.displayDuration(destination))."
        case .copiedAudioByteMismatch(let source, let destination):
            return "Saved audio byte mismatch: source \(source) bytes, saved \(destination) bytes."
        }
    }

    private static func displayDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            let seconds = duration.formatted(.number.precision(.fractionLength(1)))
            return "\(seconds) seconds"
        }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
}

private enum MemoRecordingArtifactStatus {
    case inProgress
    case succeeded
    case failed
    case cancelled
    case interrupted
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
            if case .idle = state {
                presentationOwnerID = nil
            }
            CompanionRuntimeSignal.notify(reason: "memo-\(state.signalToken)")
        }
    }
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0  // For waveform visualization
    var captureStatusMessage: String?

    /// Window that owns the large recording presentation for the active memo.
    /// The recorder remains process-global; this prevents every window from
    /// mounting the same canvas-level companion surface.
    private(set) var presentationOwnerID: UUID?

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
    private var originalAudioURL: URL?
    @ObservationIgnored
    private var levelTimer: Timer?
    @ObservationIgnored
    private var userInitiatedRecorderStop = false
    @ObservationIgnored
    private var wallClockDurationAtStop: TimeInterval?
    @ObservationIgnored
    private var recorderDurationAtStop: TimeInterval?
    @ObservationIgnored
    private var isRecoveringAudioCapture = false
    @ObservationIgnored
    private var audioCaptureRecoveryAttempts = 0
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
    private let minimumUsableRecordingDuration: TimeInterval = 1
    private let originalAudioFilenameSuffix = ".original.m4a"
    private let problemAudioFilenameSuffix = ".problem.m4a"

    private init() {}

    // MARK: - Public Methods

    /// Start recording a new memo
    func startRecording() {
        claimPresentationOwner()

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

        // Prepare capture state
        recordingId = UUID()
        capturedScreenshots = []
        capturedClips = []

        // Setup audio recording
        setupAudioRecording()
        guard audioRecorder != nil else { return }

        // Single combined timer for elapsed time + audio levels (~15Hz)
        startTime = Date()
        audioRecorder?.isMeteringEnabled = true
        startProgressTimer()

        // Start recording
        guard audioRecorder?.record() == true, audioRecorder?.isRecording == true else {
            Log(.audio).error("Failed to start memo recorder")
            cleanupRecorderAfterFailure(removeTempFile: true)
            state = .error("Failed to start recording")
            return
        }
        state = .recording
    }

    /// Start recording audio for an existing note/recording
    func startRecordingForNote(noteId: UUID) {
        claimPresentationOwner()

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

        // Set IDs — do NOT drain buffers (note already has its attachments)
        recordingId = noteId
        targetNoteId = noteId
        capturedScreenshots = []
        capturedClips = []

        // Setup audio recording
        setupAudioRecording()
        guard audioRecorder != nil else { return }

        // Single combined timer for elapsed time + audio levels (~15Hz)
        startTime = Date()
        audioRecorder?.isMeteringEnabled = true
        startProgressTimer()

        // Start recording
        guard audioRecorder?.record() == true, audioRecorder?.isRecording == true else {
            Log(.audio).error("Failed to start note recorder")
            cleanupRecorderAfterFailure(removeTempFile: true)
            state = .error("Failed to start recording")
            return
        }
        state = .recording
    }

    /// Start recording a continuation segment for an existing memo
    func startContinuingMemo(memoId: UUID) {
        claimPresentationOwner()
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

        // Segment gets its own ID, linked to the parent memo
        recordingId = UUID()
        continuingMemoId = memoId
        capturedScreenshots = []
        capturedClips = []

        setupAudioRecording()
        guard audioRecorder != nil else { return }

        startTime = Date()
        audioRecorder?.isMeteringEnabled = true
        startProgressTimer()

        guard audioRecorder?.record() == true, audioRecorder?.isRecording == true else {
            Log(.audio).error("Failed to start continuation recorder")
            cleanupRecorderAfterFailure(removeTempFile: true)
            state = .error("Failed to start recording")
            return
        }
        state = .recording

        Log(.audio).info("Started continuation recording for memo \(memoId.uuidString.prefix(8))")
    }

    /// Cancel recording for a note without saving
    func cancelRecordingForNote() {
        userInitiatedRecorderStop = true
        audioRecorder?.stop()
        audioRecorder = nil

        timer?.invalidate()
        timer = nil
        // levelTimer merged into main timer
        startTime = nil
        elapsedTime = 0
        audioLevel = 0
        captureStatusMessage = nil
        isRecoveringAudioCapture = false
        audioCaptureRecoveryAttempts = 0

        markArtifact(status: .cancelled)
        removeCurrentArtifact()
        tempAudioURL = nil
        originalAudioURL = nil
        targetNoteId = nil
        recordingId = nil

        state = .idle
    }

    /// Stop recording and save as memo (or update existing note if targetNoteId is set)
    func stopRecording() {
        guard case .recording = state else { return }

        userInitiatedRecorderStop = true
        wallClockDurationAtStop = wallClockRecordingDuration()
        recorderDurationAtStop = audioRecorder?.currentTime
        audioRecorder?.stop()
        audioRecorder = nil
        timer?.invalidate()
        timer = nil
        // levelTimer merged into main timer
        captureStatusMessage = nil
        isRecoveringAudioCapture = false

        guard let tempURL = tempAudioURL else {
            failStoppedRecording("No recording found")
            return
        }

        let isContinuation = continuingMemoId != nil
        let isNoteRecording = targetNoteId != nil
        let context = isContinuation ? "continuation" : (isNoteRecording ? "note" : "memo")
        let duration: TimeInterval

        do {
            duration = try validatedFinalAudioDuration(at: tempURL, context: context)
        } catch {
            Log(.audio).error("Memo recording did not enter processing: \(error.localizedDescription)")
            failStoppedRecording(error.localizedDescription)
            return
        }

        // Initialize processing pipeline only after the finalized audio is readable.
        elapsedTime = duration
        let durationText = formatDuration(duration)
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

    private func failStoppedRecording(_ message: String) {
        markArtifact(
            status: .failed,
            expectedWallDuration: wallClockDurationAtStop ?? wallClockRecordingDuration(),
            recorderDuration: recorderDurationAtStop,
            finalizedDuration: tempAudioURL.flatMap { measureAudioFile(at: $0)?.duration },
            errorMessage: message
        )
        cleanupRecorderAfterFailure(removeTempFile: false)
        processingSteps = []
        elapsedTime = 0
        state = .error(message)
        ToastService.shared.showError(message)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            let seconds = duration.formatted(.number.precision(.fractionLength(1)))
            return "\(seconds) seconds"
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
        userInitiatedRecorderStop = true
        audioRecorder?.stop()
        audioRecorder = nil

        timer?.invalidate()
        timer = nil
        // levelTimer merged into main timer
        startTime = nil
        elapsedTime = 0
        audioLevel = 0
        captureStatusMessage = nil
        isRecoveringAudioCapture = false
        audioCaptureRecoveryAttempts = 0

        markArtifact(status: .cancelled)
        removeCurrentArtifact()
        tempAudioURL = nil
        originalAudioURL = nil

        // Clean up any captured screenshots and clips
        if let id = recordingId {
            ScreenshotStorage.delete(for: id)
            VideoClipStorage.delete(for: id)
        }
        capturedScreenshots = []
        capturedClips = []
        recordingId = nil
        targetNoteId = nil
        continuingMemoId = nil

        state = .idle
    }

    /// Reset to idle state (after completion or error)
    func reset() {
        state = .idle
        elapsedTime = 0
        audioLevel = 0
        captureStatusMessage = nil
        userInitiatedRecorderStop = false
        wallClockDurationAtStop = nil
        recorderDurationAtStop = nil
        isRecoveringAudioCapture = false
        audioCaptureRecoveryAttempts = 0
        processingSteps = []
        capturedScreenshots = []
        capturedClips = []
        recordingId = nil
        targetNoteId = nil
        continuingMemoId = nil
        tempAudioURL = nil
        originalAudioURL = nil
        presentationOwnerID = nil
    }

    // MARK: - Private Methods

    private func claimPresentationOwner() {
        presentationOwnerID = NavigationState.activeWindowID
    }

    private var memoRecordingArtifactsDirectory: URL {
        AudioStorage.audioDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("MemoRecordings", isDirectory: true)
    }

    private func recordingContextLabel() -> String {
        if continuingMemoId != nil {
            return "continuation"
        }

        if targetNoteId != nil {
            return "note"
        }

        return "memo"
    }

    private func originalAudioFileURL(for recordingID: UUID, context: String) -> URL {
        let baseURL = memoRecordingArtifactsDirectory
            .appendingPathComponent(recordingID.uuidString + originalAudioFilenameSuffix)

        guard context == "note",
              FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacing(":", with: "-")
        return memoRecordingArtifactsDirectory
            .appendingPathComponent("\(recordingID.uuidString)-\(timestamp)\(originalAudioFilenameSuffix)")
    }

    private func createOriginalAudioFile(recordingID: UUID, context: String) throws -> URL {
        try FileManager.default.createDirectory(at: memoRecordingArtifactsDirectory, withIntermediateDirectories: true)

        let url = originalAudioFileURL(for: recordingID, context: context)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        originalAudioURL = url
        Log(.audio).info("Prepared durable memo original at \(url.path)")
        return url
    }

    private func markArtifact(
        status: MemoRecordingArtifactStatus,
        canonicalFilename: String? = nil,
        expectedWallDuration: TimeInterval? = nil,
        recorderDuration: TimeInterval? = nil,
        finalizedDuration: TimeInterval? = nil,
        canonicalDuration: TimeInterval? = nil,
        errorMessage: String? = nil
    ) {
        guard let url = originalAudioURL else { return }

        if status == .failed || status == .interrupted {
            moveOriginalToProblemFilenameIfNeeded(url)
        }

        let canonical = canonicalFilename ?? "none"
        let expected = expectedWallDuration.map { "\($0)s" } ?? "n/a"
        let recorder = recorderDuration.map { "\($0)s" } ?? "n/a"
        let finalized = finalizedDuration.map { "\($0)s" } ?? "n/a"
        let canonicalDurationText = canonicalDuration.map { "\($0)s" } ?? "n/a"
        let errorText = errorMessage ?? "none"
        Log(.audio).info("Memo original status=\(String(describing: status)) file=\(originalAudioURL?.lastPathComponent ?? url.lastPathComponent) canonical=\(canonical) expected=\(expected) recorder=\(recorder) finalized=\(finalized) canonicalDuration=\(canonicalDurationText) error=\(errorText)")
    }

    private func removeCurrentArtifact() {
        if let originalAudioURL {
            do {
                try FileManager.default.removeItem(at: originalAudioURL)
            } catch {
                Log(.audio).warning("Failed to remove memo recording original: \(error.localizedDescription)")
            }
            return
        }

        if let tempAudioURL {
            try? FileManager.default.removeItem(at: tempAudioURL)
        }
    }

    private func moveOriginalToProblemFilenameIfNeeded(_ url: URL) {
        guard url.lastPathComponent.hasSuffix(originalAudioFilenameSuffix),
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let base = String(url.lastPathComponent.dropLast(originalAudioFilenameSuffix.count))
        let problemURL = url.deletingLastPathComponent()
            .appendingPathComponent(base + problemAudioFilenameSuffix)

        do {
            if FileManager.default.fileExists(atPath: problemURL.path) {
                try FileManager.default.removeItem(at: problemURL)
            }
            try FileManager.default.moveItem(at: url, to: problemURL)
            originalAudioURL = problemURL
        } catch {
            Log(.audio).warning("Failed to mark memo original as problem file: \(error.localizedDescription)")
        }
    }

    private func pruneExpiredMemoRecordingArtifacts(now: Date = Date()) {
        let directory = memoRecordingArtifactsDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let retentionSeconds = TimeInterval(max(1, SettingsManager.shared.memoOriginalRetentionDays)) * 24 * 60 * 60

        for fileURL in files {
            let filename = fileURL.lastPathComponent
            let isProblemOriginal = filename.hasSuffix(problemAudioFilenameSuffix)
            let isSuccessfulOriginal = filename.hasSuffix(originalAudioFilenameSuffix)
            guard isProblemOriginal || isSuccessfulOriginal else { continue }

            if isProblemOriginal && SettingsManager.shared.keepProblemMemoOriginalsUntilReviewed {
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  values.isDirectory != true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt.addingTimeInterval(retentionSeconds) <= now else {
                continue
            }

            do {
                try FileManager.default.removeItem(at: fileURL)
                Log(.audio).info("Pruned expired memo recording original: \(filename)")
            } catch {
                Log(.audio).warning("Failed to prune expired memo recording original \(fileURL.path): \(error.localizedDescription)")
            }
        }
    }

    private func setupAudioRecording() {
        userInitiatedRecorderStop = false
        wallClockDurationAtStop = nil
        recorderDurationAtStop = nil
        isRecoveringAudioCapture = false
        audioCaptureRecoveryAttempts = 0
        captureStatusMessage = nil
        elapsedTime = 0
        audioLevel = 0

        pruneExpiredMemoRecordingArtifacts()

        let context = recordingContextLabel()
        let activeRecordingID = recordingId ?? UUID()
        recordingId = activeRecordingID

        // Audio settings - optimized for voice
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let url = try createOriginalAudioFile(recordingID: activeRecordingID, context: context)
            tempAudioURL = url
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
        } catch {
            Log(.audio).error("Failed to create audio recorder: \(error)")
            state = .error("Failed to initialize recorder")
        }
    }

    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRecordingProgress()
            }
        }
    }

    private func updateRecordingProgress() {
        guard case .recording = state,
              let recorder = audioRecorder else {
            return
        }

        elapsedTime = max(0, recorder.currentTime)

        guard recorder.isRecording else {
            guard !userInitiatedRecorderStop else { return }

            let measuredDuration = tempAudioURL.flatMap { measureAudioFile(at: $0)?.duration }
            elapsedTime = max(elapsedTime, measuredDuration ?? 0)
            recoverInterruptedAudioCapture(recorder)
            return
        }

        if isRecoveringAudioCapture || captureStatusMessage != nil {
            finishAudioCaptureRecovery()
        }

        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (db + 60) / 60))
        audioLevel = pow(normalized, 0.5)
    }

    private func recoverInterruptedAudioCapture(_ recorder: AVAudioRecorder) {
        guard !isRecoveringAudioCapture else { return }

        audioCaptureRecoveryAttempts += 1
        isRecoveringAudioCapture = true
        captureStatusMessage = "Microphone stopped capturing audio. Preserving original..."
        audioLevel = 0

        let measuredDuration = tempAudioURL.flatMap { measureAudioFile(at: $0)?.duration }
        let actualDuration = max(recorder.currentTime, measuredDuration ?? 0)
        let wallDuration = wallClockRecordingDuration()
        Log(.audio).error(
            "Memo audio capture stopped unexpectedly: audio=\(actualDuration)s wall=\(wallDuration)s temp=\(tempAudioURL?.path ?? "nil")"
        )
        finishInterruptedRecording(message: "Microphone stopped capturing audio. Original audio was preserved for recovery.")
    }

    private func finishInterruptedRecording(message: String) {
        userInitiatedRecorderStop = true
        wallClockDurationAtStop = wallClockRecordingDuration()
        recorderDurationAtStop = audioRecorder?.currentTime
        let finalizedDuration = tempAudioURL.flatMap { measureAudioFile(at: $0)?.duration }

        markArtifact(
            status: .interrupted,
            expectedWallDuration: wallClockDurationAtStop,
            recorderDuration: recorderDurationAtStop,
            finalizedDuration: finalizedDuration,
            errorMessage: message
        )

        cleanupRecorderAfterFailure(removeTempFile: false)
        processingSteps = []
        elapsedTime = finalizedDuration ?? recorderDurationAtStop ?? elapsedTime
        state = .error(message)
        ToastService.shared.showError(message)
    }

    private func finishAudioCaptureRecovery() {
        let attempts = audioCaptureRecoveryAttempts
        isRecoveringAudioCapture = false
        audioCaptureRecoveryAttempts = 0
        captureStatusMessage = nil
        Log(.audio).info("Memo audio capture recovered after \(attempts) attempt(s)")
    }

    private func cleanupRecorderAfterFailure(removeTempFile: Bool) {
        userInitiatedRecorderStop = true
        audioRecorder?.stop()
        audioRecorder = nil

        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        startTime = nil
        audioLevel = 0
        captureStatusMessage = nil
        isRecoveringAudioCapture = false
        audioCaptureRecoveryAttempts = 0

        if removeTempFile {
            markArtifact(status: .cancelled)
            removeCurrentArtifact()
        }

        if removeTempFile, let id = recordingId {
            ScreenshotStorage.delete(for: id)
            VideoClipStorage.delete(for: id)
        }

        tempAudioURL = nil
        originalAudioURL = nil

        if removeTempFile {
            capturedScreenshots = []
            capturedClips = []
            recordingId = nil
            targetNoteId = nil
            continuingMemoId = nil
        }
    }

    private func wallClockRecordingDuration() -> TimeInterval {
        guard let startTime else { return elapsedTime }
        return Date().timeIntervalSince(startTime)
    }

    private func validatedFinalAudioDuration(at url: URL, context: String) throws -> TimeInterval {
        guard let measurement = measureAudioFile(at: url) else {
            Log(.audio).error("Failed to read finalized \(context) audio at \(url.path)")
            throw MemoRecordingError.unreadableAudioFile(url.lastPathComponent)
        }

        let actualDuration = measurement.duration
        let wallDuration = wallClockDurationAtStop ?? wallClockRecordingDuration()
        let recorderDuration = recorderDurationAtStop ?? elapsedTime
        Log(.audio).info("Finalized \(context) audio: file=\(actualDuration)s recorder=\(recorderDuration)s wall=\(wallDuration)s bytes=\(measurement.byteCount) sampleRate=\(measurement.sampleRate) readableFrames=\(measurement.readableFrameCount)")

        guard measurement.readableFrameCount > 0 else {
            throw MemoRecordingError.unusableAudio(duration: actualDuration)
        }

        guard actualDuration >= minimumUsableRecordingDuration else {
            throw MemoRecordingError.unusableAudio(duration: actualDuration)
        }

        if isSevereDurationMismatch(expected: wallDuration, actual: actualDuration) {
            Log(.audio).error("Rejecting incomplete \(context) audio: file=\(actualDuration)s wall=\(wallDuration)s recorder=\(recorderDuration)s")
            throw MemoRecordingError.incompleteRecording(expected: wallDuration, actual: actualDuration)
        }

        return actualDuration
    }

    private func measureAudioFile(at url: URL) -> AudioFileMeasurement? {
        do {
            let file = try AVAudioFile(forReading: url)
            let sampleRate = file.processingFormat.sampleRate
            let duration = Double(file.length) / sampleRate
            let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let frameCapacity = AVAudioFrameCount(min(file.length, AVAudioFramePosition(sampleRate)))
            let readableFrames: AVAudioFrameCount

            if frameCapacity > 0,
               let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity) {
                try file.read(into: buffer, frameCount: frameCapacity)
                readableFrames = buffer.frameLength
            } else {
                readableFrames = 0
            }

            return AudioFileMeasurement(
                duration: duration,
                byteCount: byteCount,
                sampleRate: sampleRate,
                frameCount: file.length,
                readableFrameCount: readableFrames
            )
        } catch {
            Log(.audio).error("Failed to measure audio file \(url.path): \(error)")
            return nil
        }
    }

    private func isSevereDurationMismatch(expected: TimeInterval, actual: TimeInterval) -> Bool {
        guard expected >= minimumUsableRecordingDuration else { return false }
        let tolerance = max(2.0, expected * 0.05)
        return actual + tolerance < expected
    }

    private func isCopiedAudioDurationMismatch(source: TimeInterval, destination: TimeInterval) -> Bool {
        abs(source - destination) > 0.1
    }

    private func processRecording() async {
        guard let tempURL = tempAudioURL else {
            await MainActor.run { state = .error("No recording found") }
            return
        }

        let expectedDuration = wallClockDurationAtStop ?? elapsedTime
        Log(.audio).info("Processing memo recording: \(tempURL.path), expected duration: \(expectedDuration)s")

        let modelId = AgentSettings.shared.selectedModelId
        let memoId = recordingId ?? UUID()
        var savedMemo: MemoModel?
        var savedAudioPath: String?
        var savedAudioDuration: TimeInterval?

        do {
            // Step 1: Save audio file
            await MainActor.run { updateStep("saved", status: .inProgress) }

            let duration = try validatedFinalAudioDuration(at: tempURL, context: "memo")
            await MainActor.run { updateStep("recorded", status: .completed, subtitle: formatDuration(duration)) }

            let audioPath = try await saveAudioFile(from: tempURL, memoId: memoId, expectedDuration: duration)
            savedAudioPath = audioPath
            savedAudioDuration = duration

            markArtifact(
                status: .inProgress,
                canonicalFilename: audioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: duration,
                canonicalDuration: measureAudioFile(
                    at: AudioStorage.audioDirectory.appendingPathComponent(audioPath)
                )?.duration
            )

            let displayPath = "~/Library/Application Support/Talkie/Audio/\(audioPath)"
            await MainActor.run { updateStep("saved", status: .completed, subtitle: displayPath) }

            // Create a pending memo before transcription. The audio memo exists even
            // if the transcription request fails or the app exits during processing.
            let deviceName = Host.current().localizedName ?? "Mac"
            let originDeviceId = "mac-\(deviceName)"
            let createdAt = Date()

            var memo = MemoModel(
                id: memoId,
                createdAt: createdAt,
                lastModified: createdAt,
                title: nil,
                duration: duration,
                sortOrder: 0,
                transcription: nil,
                audioFilePath: audioPath,
                isTranscribing: true,
                originDeviceId: originDeviceId,
                macReceivedAt: createdAt
            )

            try await repository.saveMemo(memo)
            savedMemo = memo

            var pendingRecording = TalkieObject(from: memo)
            var pendingAssets = pendingRecording.assets ?? TalkieObjectAssets()
            if !capturedScreenshots.isEmpty {
                pendingAssets.screenshots = capturedScreenshots
            }
            if !capturedClips.isEmpty {
                pendingAssets.clips = capturedClips
            }
            pendingRecording.assetsJSON = pendingAssets.toJSON()
            pendingRecording.transcriptionStatus = .pending
            pendingRecording.transcriptionModel = modelId
            try await recordingRepository.saveRecording(pendingRecording)

            await MemosViewModel.shared.loadMemos()
            await RecordingsViewModel.shared.loadRecordings()

            // Step 2: Transcribe
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

            // Step 3: Complete memo
            await MainActor.run { updateStep("complete", status: .inProgress) }

            memo.transcription = transcript
            memo.isTranscribing = false
            memo.lastModified = Date()

            if let firstLine = transcript.components(separatedBy: .newlines).first,
               !firstLine.isEmpty {
                let title = String(firstLine.prefix(50))
                memo.title = title.count < firstLine.count ? title + "..." : title
            }

            try await repository.saveMemo(memo)

            // Create Recording with word-level timestamps and screenshot metadata
            var recording = TalkieObject(from: memo)
            recording.transcriptionStatus = .success
            recording.transcriptionModel = modelId
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

            markArtifact(
                status: .succeeded,
                canonicalFilename: audioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: duration,
                canonicalDuration: measureAudioFile(
                    at: AudioStorage.audioDirectory.appendingPathComponent(audioPath)
                )?.duration
            )
            tempAudioURL = nil
            originalAudioURL = nil

            await MainActor.run {
                updateStep("complete", status: .completed, subtitle: "Ready to view")
                state = .complete(memo)
            }

            Log(.database).info("Created memo from Mac recording: \(memoId)")

        } catch {
            Log(.audio).error("Failed to process memo recording: \(error)")

            if var memo = savedMemo {
                memo.isTranscribing = false
                memo.lastModified = Date()
                try? await repository.saveMemo(memo)

                var failedRecording = TalkieObject(from: memo)
                var assets = failedRecording.assets ?? TalkieObjectAssets()
                if !capturedScreenshots.isEmpty {
                    assets.screenshots = capturedScreenshots
                }
                if !capturedClips.isEmpty {
                    assets.clips = capturedClips
                }
                failedRecording.assetsJSON = assets.toJSON()
                failedRecording.transcriptionStatus = .failed
                failedRecording.transcriptionError = error.localizedDescription
                failedRecording.transcriptionModel = modelId
                try? await recordingRepository.saveRecording(failedRecording)
                await MemosViewModel.shared.loadMemos()
                await RecordingsViewModel.shared.loadRecordings()
            }

            markArtifact(
                status: .failed,
                canonicalFilename: savedAudioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: savedAudioDuration ?? tempAudioURL.flatMap { measureAudioFile(at: $0)?.duration },
                canonicalDuration: savedAudioPath.flatMap {
                    measureAudioFile(at: AudioStorage.audioDirectory.appendingPathComponent($0))?.duration
                },
                errorMessage: error.localizedDescription
            )
            tempAudioURL = nil
            originalAudioURL = nil

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

        let expectedDuration = wallClockDurationAtStop ?? elapsedTime
        Log(.audio).info("Processing note audio: \(tempURL.path), expected duration: \(expectedDuration)s, noteId: \(noteId)")

        let modelId = AgentSettings.shared.selectedModelId
        var savedAudioPath: String?
        var savedAudioDuration: TimeInterval?

        do {
            // Step 1: Save audio file
            await MainActor.run { updateStep("saved", status: .inProgress) }

            let duration = try validatedFinalAudioDuration(at: tempURL, context: "note")
            await MainActor.run { updateStep("recorded", status: .completed, subtitle: formatDuration(duration)) }

            let audioPath = try await saveAudioFile(from: tempURL, memoId: noteId, expectedDuration: duration)
            savedAudioPath = audioPath
            savedAudioDuration = duration
            markArtifact(
                status: .inProgress,
                canonicalFilename: audioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: duration,
                canonicalDuration: measureAudioFile(
                    at: AudioStorage.audioDirectory.appendingPathComponent(audioPath)
                )?.duration
            )

            var pendingRecording: TalkieObject
            if var existing = try await recordingRepository.fetchRecording(id: noteId) {
                existing.audioFilename = audioPath
                existing.duration = duration
                existing.transcriptionStatus = .pending
                existing.transcriptionError = nil
                existing.transcriptionModel = modelId
                existing.lastModified = Date()
                pendingRecording = existing
            } else {
                pendingRecording = TalkieObject.newNote(id: noteId, text: "", title: nil)
                pendingRecording.audioFilename = audioPath
                pendingRecording.duration = duration
                pendingRecording.transcriptionStatus = .pending
                pendingRecording.transcriptionModel = modelId
                pendingRecording.lastModified = Date()
            }
            try await recordingRepository.saveRecording(pendingRecording)
            await RecordingsViewModel.shared.loadRecordings()

            await MainActor.run { updateStep("saved", status: .completed) }

            // Step 2: Transcribe
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

            markArtifact(
                status: .succeeded,
                canonicalFilename: audioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: duration,
                canonicalDuration: measureAudioFile(
                    at: AudioStorage.audioDirectory.appendingPathComponent(audioPath)
                )?.duration
            )
            tempAudioURL = nil
            originalAudioURL = nil

            await MainActor.run {
                updateStep("complete", status: .completed, subtitle: "Ready to view")
                targetNoteId = nil
                state = .idle
                processingSteps = []
            }

            Log(.database).info("Added audio to recording: \(noteId)")

        } catch {
            Log(.audio).error("Failed to process note audio: \(error)")
            if savedAudioPath != nil,
               var existing = try? await recordingRepository.fetchRecording(id: noteId) {
                existing.transcriptionStatus = .failed
                existing.transcriptionError = error.localizedDescription
                existing.transcriptionModel = modelId
                existing.lastModified = Date()
                try? await recordingRepository.saveRecording(existing)
                await RecordingsViewModel.shared.loadRecordings()
            }

            markArtifact(
                status: .failed,
                canonicalFilename: savedAudioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: savedAudioDuration ?? tempAudioURL.flatMap { measureAudioFile(at: $0)?.duration },
                canonicalDuration: savedAudioPath.flatMap {
                    measureAudioFile(at: AudioStorage.audioDirectory.appendingPathComponent($0))?.duration
                },
                errorMessage: error.localizedDescription
            )
            tempAudioURL = nil
            originalAudioURL = nil

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

        let expectedDuration = wallClockDurationAtStop ?? elapsedTime
        Log(.audio).info("Processing continuation segment for memo \(parentId.uuidString.prefix(8)), expected duration: \(expectedDuration)s")

        let modelId = AgentSettings.shared.selectedModelId
        var savedAudioPath: String?
        var savedAudioDuration: TimeInterval?
        var pendingSegment: TalkieObject?

        do {
            // Step 1: Save audio file (using segment's own ID)
            await MainActor.run { updateStep("saved", status: .inProgress) }

            let duration = try validatedFinalAudioDuration(at: tempURL, context: "continuation")
            await MainActor.run { updateStep("recorded", status: .completed, subtitle: formatDuration(duration)) }

            let audioPath = try await saveAudioFile(from: tempURL, memoId: segmentId, expectedDuration: duration)
            savedAudioPath = audioPath
            savedAudioDuration = duration
            markArtifact(
                status: .inProgress,
                canonicalFilename: audioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: duration,
                canonicalDuration: measureAudioFile(
                    at: AudioStorage.audioDirectory.appendingPathComponent(audioPath)
                )?.duration
            )

            try await recordingRepository.promoteMemoToSegmented(memoId: parentId)
            let segmentIndex = try await recordingRepository.countSegments(forNoteId: parentId)
            var segment = TalkieObject(
                id: segmentId,
                type: .segment,
                text: nil,
                duration: duration,
                audioFilename: audioPath,
                source: .mac,
                transcriptionStatus: .pending,
                transcriptionModel: modelId,
                parentId: parentId,
                segmentIndex: segmentIndex
            )
            try await recordingRepository.saveRecording(segment)
            pendingSegment = segment
            try await recordingRepository.refreshParentAggregates(memoId: parentId)
            await RecordingsViewModel.shared.loadRecordings()

            await MainActor.run { updateStep("saved", status: .completed) }

            // Step 2: Transcribe
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

            segment.text = transcript
            segment.transcriptionStatus = .success
            segment.transcriptionError = nil
            segment.transcriptionModel = modelId
            segment.assetsJSON = assets.toJSON()
            segment.lastModified = Date()
            try await recordingRepository.saveRecording(segment)
            try await recordingRepository.refreshParentAggregates(memoId: parentId)

            // Refresh views
            await RecordingsViewModel.shared.loadRecordings()

            markArtifact(
                status: .succeeded,
                canonicalFilename: audioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: duration,
                canonicalDuration: measureAudioFile(
                    at: AudioStorage.audioDirectory.appendingPathComponent(audioPath)
                )?.duration
            )
            tempAudioURL = nil
            originalAudioURL = nil

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
            if var failedSegment = pendingSegment {
                failedSegment.transcriptionStatus = .failed
                failedSegment.transcriptionError = error.localizedDescription
                failedSegment.transcriptionModel = modelId
                failedSegment.lastModified = Date()
                try? await recordingRepository.saveRecording(failedSegment)
                try? await recordingRepository.refreshParentAggregates(memoId: parentId)
                await RecordingsViewModel.shared.loadRecordings()
            }

            markArtifact(
                status: .failed,
                canonicalFilename: savedAudioPath,
                expectedWallDuration: expectedDuration,
                recorderDuration: recorderDurationAtStop,
                finalizedDuration: savedAudioDuration ?? tempAudioURL.flatMap { measureAudioFile(at: $0)?.duration },
                canonicalDuration: savedAudioPath.flatMap {
                    measureAudioFile(at: AudioStorage.audioDirectory.appendingPathComponent($0))?.duration
                },
                errorMessage: error.localizedDescription
            )
            tempAudioURL = nil
            originalAudioURL = nil

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

    private func saveAudioFile(from tempURL: URL, memoId: UUID, expectedDuration: TimeInterval) async throws -> String {
        let audioDir = AudioStorage.audioDirectory
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        guard let sourceMeasurement = measureAudioFile(at: tempURL) else {
            throw MemoRecordingError.unreadableAudioFile(tempURL.lastPathComponent)
        }
        if isCopiedAudioDurationMismatch(source: expectedDuration, destination: sourceMeasurement.duration) {
            throw MemoRecordingError.copiedAudioMismatch(
                source: expectedDuration,
                destination: sourceMeasurement.duration
            )
        }

        let fileName = "\(memoId.uuidString).m4a"
        let destinationURL = audioDir.appendingPathComponent(fileName)
        let stagingURL = audioDir.appendingPathComponent(".\(fileName).\(UUID().uuidString).tmp")
        let backupURL = audioDir.appendingPathComponent(".\(fileName).backup.\(UUID().uuidString)")
        let fileManager = FileManager.default
        var didMoveExistingDestination = false

        do {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try fileManager.removeItem(at: stagingURL)
            }

            try fileManager.copyItem(at: tempURL, to: stagingURL)

            guard let stagedMeasurement = measureAudioFile(at: stagingURL) else {
                throw MemoRecordingError.unreadableAudioFile(fileName)
            }
            if isCopiedAudioDurationMismatch(source: sourceMeasurement.duration, destination: stagedMeasurement.duration) {
                throw MemoRecordingError.copiedAudioMismatch(
                    source: sourceMeasurement.duration,
                    destination: stagedMeasurement.duration
                )
            }
            if sourceMeasurement.byteCount != stagedMeasurement.byteCount {
                throw MemoRecordingError.copiedAudioByteMismatch(
                    source: sourceMeasurement.byteCount,
                    destination: stagedMeasurement.byteCount
                )
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.moveItem(at: destinationURL, to: backupURL)
                didMoveExistingDestination = true
            }

            do {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            } catch {
                if didMoveExistingDestination {
                    try? fileManager.moveItem(at: backupURL, to: destinationURL)
                }
                throw error
            }

            guard let copiedMeasurement = measureAudioFile(at: destinationURL) else {
                if didMoveExistingDestination {
                    try? fileManager.removeItem(at: destinationURL)
                    try? fileManager.moveItem(at: backupURL, to: destinationURL)
                } else {
                    try? fileManager.removeItem(at: destinationURL)
                }
                throw MemoRecordingError.unreadableAudioFile(fileName)
            }
            if isCopiedAudioDurationMismatch(source: sourceMeasurement.duration, destination: copiedMeasurement.duration) {
                if didMoveExistingDestination {
                    try? fileManager.removeItem(at: destinationURL)
                    try? fileManager.moveItem(at: backupURL, to: destinationURL)
                } else {
                    try? fileManager.removeItem(at: destinationURL)
                }
                throw MemoRecordingError.copiedAudioMismatch(
                    source: sourceMeasurement.duration,
                    destination: copiedMeasurement.duration
                )
            }
            if sourceMeasurement.byteCount != copiedMeasurement.byteCount {
                if didMoveExistingDestination {
                    try? fileManager.removeItem(at: destinationURL)
                    try? fileManager.moveItem(at: backupURL, to: destinationURL)
                } else {
                    try? fileManager.removeItem(at: destinationURL)
                }
                throw MemoRecordingError.copiedAudioByteMismatch(
                    source: sourceMeasurement.byteCount,
                    destination: copiedMeasurement.byteCount
                )
            }

            if didMoveExistingDestination {
                try? fileManager.removeItem(at: backupURL)
            }

            Log(.audio).info("Copied memo audio: file=\(fileName) duration=\(copiedMeasurement.duration)s bytes=\(copiedMeasurement.byteCount)")
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            if didMoveExistingDestination,
               !fileManager.fileExists(atPath: destinationURL.path),
               fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            throw error
        }

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
            ScreenRecordingController.shared.recordScreenshotHighlight(
                capturedAt: start.addingTimeInterval(Double(screenshot.timestampMs) / 1000.0),
                filename: screenshot.filename,
                captureMode: screenshot.captureMode,
                width: screenshot.width,
                height: screenshot.height,
                windowTitle: screenshot.windowTitle,
                appName: screenshot.appName,
                appBundleID: screenshot.appBundleID,
                displayName: screenshot.displayName
            )
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
                appBundleID: screenshot.appBundleID,
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
