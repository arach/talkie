//
//  CameraCaptureService.swift
//  Talkie
//
//  AVCaptureSession + AVAssetWriter for face camera video capture.
//  Video-only (no audio) — audio is already captured by MemoRecordingController's AVAudioRecorder.
//

import AVFoundation
import AppKit
import TalkieKit

private let log = Log(.system)

// MARK: - Camera Quality

enum CameraQuality: String, CaseIterable, Codable {
    case standard  // 720p
    case high      // 1080p

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .standard: return .hd1280x720
        case .high: return .high
        }
    }

    var bitrate: Int {
        switch self {
        case .standard: return 2_000_000   // 2 Mbps
        case .high: return 4_000_000       // 4 Mbps
        }
    }

    var label: String {
        switch self {
        case .standard: return "720p"
        case .high: return "1080p"
        }
    }
}

// MARK: - Camera Capture Service

@MainActor
@Observable
final class CameraCaptureService: NSObject {
    static let shared = CameraCaptureService()

    // MARK: - State

    enum State: Equatable {
        case idle
        case previewing
        case recording
    }

    private(set) var state: State = .idle
    private(set) var isAuthorized = false
    private(set) var isSessionRunning = false

    /// The capture session for preview layer access
    private(set) var captureSession: AVCaptureSession?

    /// Actual camera frame dimensions (set after preview starts)
    private(set) var cameraWidth: Int = 0
    private(set) var cameraHeight: Int = 0

    /// Revision counter — bumped on every preference write so @Observable
    /// tracking picks up changes to UserDefaults-backed computed properties.
    private(set) var settingsRevision: Int = 0

    @ObservationIgnored
    private var settings: SettingsManager { SettingsManager.shared }

    /// Quality preference
    var quality: CameraQuality {
        get {
            _ = settings.cameraSettingsRevision
            return settings.cameraQuality
        }
        set {
            settings.cameraQuality = newValue
            settingsRevision += 1
        }
    }

    /// Selected camera device ID
    var selectedDeviceID: String {
        get {
            _ = settings.cameraSettingsRevision
            return settings.cameraDeviceID
        }
        set {
            settings.cameraDeviceID = newValue
            settingsRevision += 1
        }
    }

    /// Bubble size preference
    var bubbleSize: CameraBubbleSize {
        get {
            _ = settings.cameraSettingsRevision
            return settings.cameraBubbleSize
        }
        set {
            settings.cameraBubbleSize = newValue
            settingsRevision += 1
        }
    }

    /// Video codec preference
    var videoCodec: CameraVideoCodec {
        get {
            _ = settings.cameraSettingsRevision
            return settings.cameraVideoCodec
        }
        set {
            settings.cameraVideoCodec = newValue
            settingsRevision += 1
        }
    }

    /// Max clip duration in seconds
    var maxClipDurationSeconds: Double {
        get {
            _ = settings.cameraSettingsRevision
            return settings.cameraMaxClipDuration
        }
        set {
            settings.cameraMaxClipDuration = newValue
            settingsRevision += 1
        }
    }

    // MARK: - Private (main-actor only)

    @ObservationIgnored
    private var recordingURL: URL?
    @ObservationIgnored
    private var clipContinuation: CheckedContinuation<URL?, Never>?
    @ObservationIgnored
    private var previewReadyContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored
    private var maxDurationTimer: Timer?

    /// Maximum clip duration safety valve (reads from settings)
    private var maxClipDuration: TimeInterval { maxClipDurationSeconds }

    // MARK: - Shared state (accessed from capture queue via lock)

    /// Lock protecting writer state shared between main thread and capture queue
    @ObservationIgnored
    private let writerLock = NSLock()
    @ObservationIgnored
    nonisolated(unsafe) private var _assetWriter: AVAssetWriter?
    @ObservationIgnored
    nonisolated(unsafe) private var _videoInput: AVAssetWriterInput?
    @ObservationIgnored
    nonisolated(unsafe) private var _isRecording = false
    @ObservationIgnored
    nonisolated(unsafe) private var _isWriterStarted = false
    @ObservationIgnored
    nonisolated(unsafe) private var _lastRecordedWidth: Int = 0
    @ObservationIgnored
    nonisolated(unsafe) private var _lastRecordedHeight: Int = 0

    @ObservationIgnored
    private var videoOutput: AVCaptureVideoDataOutput?
    @ObservationIgnored
    private let captureQueue = DispatchQueue(label: "com.jdi.talkie.cameraCapture")

    private override init() {
        super.init()
        checkAuthorization()
    }

    // MARK: - Authorization

    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            return granted
        default:
            isAuthorized = false
            return false
        }
    }

    private func checkAuthorization() {
        isAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    // MARK: - Preview

    /// Start camera preview and wait until the session is running.
    /// Returns `false` if setup fails.
    func startPreviewAsync() async -> Bool {
        guard startPreview() else { return false }
        await withCheckedContinuation { continuation in
            self.previewReadyContinuation = continuation
        }
        return true
    }

    /// Start camera preview. Returns `false` if setup fails.
    /// Note: session.startRunning() completes asynchronously — use startPreviewAsync() to wait.
    @discardableResult
    func startPreview() -> Bool {
        guard state == .idle else { return false }
        guard isAuthorized else {
            log.warning("Camera not authorized, cannot start preview")
            return false
        }

        let session = AVCaptureSession()
        session.sessionPreset = quality.sessionPreset

        // Find camera: prefer selected device, fall back to front camera
        let device: AVCaptureDevice
        if !selectedDeviceID.isEmpty, let selected = AVCaptureDevice(uniqueID: selectedDeviceID) {
            device = selected
        } else if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            device = frontCamera
        } else {
            log.error("No camera available")
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                log.error("Cannot add camera input to session")
                return false
            }
            session.addInput(input)

            // Video data output for recording
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: captureQueue)

            guard session.canAddOutput(output) else {
                log.error("Cannot add video output to session")
                return false
            }
            session.addOutput(output)
            videoOutput = output

            // Mirror front camera
            if let connection = output.connection(with: .video) {
                connection.isVideoMirrored = true
            }

            self.captureSession = session
            self.isSessionRunning = false
            self.state = .previewing  // Set immediately so state machine is consistent

            // startRunning() is blocking — dispatch to background
            let capturedDevice = device
            let capturedQuality = quality
            captureQueue.async { [weak self] in
                session.startRunning()

                let dims = CMVideoFormatDescriptionGetDimensions(capturedDevice.activeFormat.formatDescription)

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.cameraWidth = Int(dims.width)
                    self.cameraHeight = Int(dims.height)
                    self.isSessionRunning = true
                    log.info("Camera preview started (quality: \(capturedQuality.label), \(self.cameraWidth)x\(self.cameraHeight))")

                    // Signal async waiters that preview is ready
                    self.previewReadyContinuation?.resume()
                    self.previewReadyContinuation = nil
                }
            }
            return true
        } catch {
            log.error("Failed to setup camera: \(error)")
            return false
        }
    }

    func stopPreview() {
        guard state == .previewing else {
            if state == .recording {
                log.warning("Cannot stop preview while recording — stop recording first")
            }
            return
        }

        let session = captureSession
        captureSession = nil
        videoOutput = nil
        isSessionRunning = false
        state = .idle

        captureQueue.async { session?.stopRunning() }
        log.info("Camera preview stopped")
    }

    // MARK: - Clip Recording

    func startClipRecording(to url: URL) {
        guard state == .previewing else {
            log.warning("Cannot start clip recording — not previewing (state: \(String(describing: state)))")
            return
        }

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

            // Use actual camera dimensions (fall back to 720p if unknown)
            let recordWidth = cameraWidth > 0 ? cameraWidth : 1280
            let recordHeight = cameraHeight > 0 ? cameraHeight : 720

            let codec = videoCodec.avCodec
            var compressionProperties: [String: Any] = [
                AVVideoAverageBitRateKey: quality.bitrate,
            ]
            if codec == .h264 {
                compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            }

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: recordWidth,
                AVVideoHeightKey: recordHeight,
                AVVideoCompressionPropertiesKey: compressionProperties,
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true

            guard writer.canAdd(input) else {
                log.error("Cannot add video input to asset writer")
                return
            }
            writer.add(input)
            writer.startWriting()

            writerLock.lock()
            _assetWriter = writer
            _videoInput = input
            _isRecording = true
            _isWriterStarted = false
            _lastRecordedWidth = 0
            _lastRecordedHeight = 0
            writerLock.unlock()

            self.recordingURL = url

            state = .recording
            log.info("Clip recording started → \(url.lastPathComponent)")

            // Safety valve: auto-stop after max duration (routes through controller for proper cleanup)
            maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxClipDuration, repeats: false) { _ in
                Task { @MainActor in
                    log.warning("Clip hit max duration, auto-stopping")
                    CameraBubbleController.shared.stopClip()
                }
            }

        } catch {
            log.error("Failed to create asset writer: \(error)")
        }
    }

    func stopClipRecording() async -> URL? {
        guard state == .recording else { return nil }

        // Cancel timer first to prevent it from racing with finishClipRecording
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        return await withCheckedContinuation { continuation in
            self.clipContinuation = continuation
            self.finishClipRecording()
        }
    }

    private func finishClipRecording() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        writerLock.lock()
        let writer = _assetWriter
        let input = _videoInput
        let width = _lastRecordedWidth
        let height = _lastRecordedHeight
        _isRecording = false
        writerLock.unlock()

        guard let writer else {
            clipContinuation?.resume(returning: nil)
            clipContinuation = nil
            state = .previewing
            return
        }

        input?.markAsFinished()

        let url = recordingURL

        writer.finishWriting { [weak self] in
            Task { @MainActor in
                guard let self else { return }

                if writer.status == .completed, let url {
                    log.info("Clip saved: \(url.lastPathComponent) (\(width)x\(height))")
                    self.clipContinuation?.resume(returning: url)
                } else {
                    log.error("Clip writing failed: \(writer.error?.localizedDescription ?? "unknown")")
                    self.clipContinuation?.resume(returning: nil)
                }

                self.clipContinuation = nil
                self.recordingURL = nil

                self.writerLock.lock()
                self._assetWriter = nil
                self._videoInput = nil
                self._isWriterStarted = false
                self._lastRecordedWidth = 0
                self._lastRecordedHeight = 0
                self.writerLock.unlock()

                self.state = .previewing
            }
        }
    }

    // MARK: - Teardown

    func teardown() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        // Resume any pending continuation before tearing down (prevents CheckedContinuation leak)
        clipContinuation?.resume(returning: nil)
        clipContinuation = nil

        writerLock.lock()
        if _isRecording {
            _videoInput?.markAsFinished()
            _assetWriter?.cancelWriting()
            _assetWriter = nil
            _videoInput = nil
            _isRecording = false
        }
        writerLock.unlock()

        let session = captureSession
        captureSession = nil
        captureQueue.async { session?.stopRunning() }
        videoOutput = nil
        recordingURL = nil

        isSessionRunning = false
        state = .idle
        log.info("Camera capture service torn down")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        writerLock.lock()
        guard let writer = _assetWriter,
              let input = _videoInput,
              _isRecording else {
            writerLock.unlock()
            return
        }

        if !_isWriterStarted {
            writer.startSession(atSourceTime: timestamp)
            _isWriterStarted = true
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                _lastRecordedWidth = CVPixelBufferGetWidth(pixelBuffer)
                _lastRecordedHeight = CVPixelBufferGetHeight(pixelBuffer)
            }
        }
        writerLock.unlock()

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
