//
//  ScreenRecordingService.swift
//  TalkieAgent
//
//  SCStream + AVAssetWriter engine for screen video recording.
//  Supports region, fullscreen, and window capture modes.
//  Video-only (no audio) for MVP.
//

import AVFoundation
import AppKit
import ScreenCaptureKit
import TalkieKit

private let log = Log(.system)

extension CaptureMode: Codable {}

enum ScreenRecordingQualityPreset: String, CaseIterable, Codable {
    case agent
    case balanced
    case archive

    var label: String {
        switch self {
        case .agent: return "Agent"
        case .balanced: return "Balanced"
        case .archive: return "Archive"
        }
    }

    var detail: String {
        switch self {
        case .agent: return "Lowest bitrate and frame rate for AI-first clips."
        case .balanced: return "Smaller files while keeping motion readable."
        case .archive: return "Highest fidelity for human playback."
        }
    }

    var bitrate: Int {
        switch self {
        case .agent: return 2_000_000
        case .balanced: return 3_000_000
        case .archive: return 6_000_000
        }
    }

    var framesPerSecond: Int32 {
        switch self {
        case .agent: return 12
        case .balanced: return 20
        case .archive: return 30
        }
    }

    var bitrateSummary: String { "\(bitrate / 1_000_000) Mbps" }

    var fpsSummary: String { "\(framesPerSecond) fps" }
}

// MARK: - Screen Recording Target

/// Describes what to record — resolved from user selection.
struct ScreenRecordingTarget {
    enum Kind {
        case fullscreen(SCDisplay)
        case region(SCDisplay, CGRect)    // display + rect in screen coords
        case window(SCWindow)
    }

    let kind: Kind
    let windowTitle: String?
    let appName: String?
    let displayName: String?
}

private struct ScreenRecordingPreset: Codable {
    var mode: CaptureMode
    var displayID: UInt32?
    var rect: CGRect?
    var windowID: UInt32?
    var windowTitle: String?
    var appName: String?
    var displayName: String?
    var capturedAt: Date
}

@MainActor
private final class ScreenRecordingPresetStore {
    static let shared = ScreenRecordingPresetStore()

    private let key = "screenRecording.lastTargetPreset.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var hasPreset: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    func save(target: ScreenRecordingTarget) {
        let preset = preset(from: target)
        save(preset: preset)
        log.info("Saved screen recording preset (\(preset.mode.rawValue))")
    }

    func save(preset: ScreenRecordingPreset) {
        guard let data = try? encoder.encode(preset) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> ScreenRecordingPreset? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(ScreenRecordingPreset.self, from: data)
    }

    private func preset(from target: ScreenRecordingTarget) -> ScreenRecordingPreset {
        switch target.kind {
        case .fullscreen(let display):
            return ScreenRecordingPreset(
                mode: .fullscreen,
                displayID: display.displayID,
                rect: display.frame,
                windowID: nil,
                windowTitle: nil,
                appName: nil,
                displayName: target.displayName,
                capturedAt: Date()
            )

        case .region(let display, let rect):
            return ScreenRecordingPreset(
                mode: .region,
                displayID: display.displayID,
                rect: rect,
                windowID: nil,
                windowTitle: nil,
                appName: nil,
                displayName: target.displayName,
                capturedAt: Date()
            )

        case .window(let window):
            return ScreenRecordingPreset(
                mode: .window,
                displayID: nil,
                rect: window.frame,
                windowID: window.windowID,
                windowTitle: target.windowTitle,
                appName: target.appName,
                displayName: target.displayName,
                capturedAt: Date()
            )
        }
    }
}

// MARK: - Screen Recording Service

@MainActor
@Observable
final class ScreenRecordingService: NSObject {
    static let shared = ScreenRecordingService()
    private var recordingQualityPreset: ScreenRecordingQualityPreset {
        guard let raw = UserDefaults.standard.string(forKey: "screenRecordingQuality"),
              let preset = ScreenRecordingQualityPreset(rawValue: raw) else {
            return .agent
        }
        return preset
    }

    // MARK: - State

    enum State: Equatable {
        case idle
        case recording
    }

    private(set) var state: State = .idle
    private(set) var recordingStartTime: Date?

    // MARK: - Private (main-actor only)

    @ObservationIgnored
    private var recordingURL: URL?
    @ObservationIgnored
    private var stopContinuation: CheckedContinuation<URL?, Never>?
    @ObservationIgnored
    private var maxDurationTimer: Timer?
    @ObservationIgnored
    private var stream: SCStream?
    @ObservationIgnored
    private var target: ScreenRecordingTarget?

    /// Max recording duration safety valve (seconds)
    private let maxDuration: TimeInterval = 300  // 5 minutes

    // MARK: - Shared state (accessed from stream output queue via lock)

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
    nonisolated(unsafe) private var _recordedWidth: Int = 0
    @ObservationIgnored
    nonisolated(unsafe) private var _recordedHeight: Int = 0

    @ObservationIgnored
    private let outputQueue = DispatchQueue(label: "to.talkie.agent.screenRecording")

    private override init() {
        super.init()
    }

    // MARK: - Permission

    func hasPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            log.warning("Screen recording permission check failed: \(error)")
            return false
        }
    }

    // MARK: - Target Selection

    /// Select a recording target using the given capture mode.
    /// Reuses ScreenCaptureOverlay for region/window selection.
    func selectTarget(mode: CaptureMode) async -> ScreenRecordingTarget? {
        guard await hasPermission() else {
            showPermissionAlert()
            return nil
        }

        switch mode {
        case .fullscreen:
            return await selectFullscreen()
        case .region:
            return await selectRegion()
        case .window:
            return await selectWindow()
        }
    }

    var hasReusableTarget: Bool {
        ScreenRecordingPresetStore.shared.hasPreset
    }

    func reusableTarget() async -> ScreenRecordingTarget? {
        guard await hasPermission() else {
            showPermissionAlert()
            return nil
        }
        guard let preset = reusablePreset() else {
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            switch preset.mode {
            case .fullscreen:
                guard let display = display(for: preset, from: content.displays) else { return nil }
                return ScreenRecordingTarget(
                    kind: .fullscreen(display),
                    windowTitle: nil,
                    appName: nil,
                    displayName: screenNameForDisplay(display) ?? preset.displayName
                )

            case .region:
                guard let rect = preset.rect, rect.width > 5, rect.height > 5,
                      let display = display(for: preset, from: content.displays),
                      displayFrame(display).intersects(rect) else {
                    return nil
                }
                return ScreenRecordingTarget(
                    kind: .region(display, rect),
                    windowTitle: nil,
                    appName: nil,
                    displayName: screenNameForDisplay(display) ?? preset.displayName
                )

            case .window:
                guard let window = window(for: preset, from: content.windows) else { return nil }
                let meta = windowMetadata(for: window.windowID)
                return ScreenRecordingTarget(
                    kind: .window(window),
                    windowTitle: meta.title ?? preset.windowTitle,
                    appName: meta.appName ?? preset.appName,
                    displayName: preset.displayName
                )
            }
        } catch {
            log.error("Failed to resolve screen recording preset: \(error)")
            return nil
        }
    }

    func regionTarget(
        for rect: CGRect,
        preferredTarget: ScreenRecordingTarget? = nil
    ) async -> ScreenRecordingTarget? {
        guard await hasPermission() else {
            showPermissionAlert()
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = display(for: rect, preferredTarget: preferredTarget, from: content.displays) else {
                return nil
            }
            let displayFrame = displayFrame(display)
            let constrainedRect = rect.intersection(displayFrame).standardized
            guard !constrainedRect.isNull, constrainedRect.width > 5, constrainedRect.height > 5 else {
                return nil
            }
            return ScreenRecordingTarget(
                kind: .region(display, constrainedRect),
                windowTitle: nil,
                appName: nil,
                displayName: screenNameForDisplay(display)
            )
        } catch {
            log.error("Failed to resolve adjusted screen recording region: \(error)")
            return nil
        }
    }

    private func reusablePreset() -> ScreenRecordingPreset? {
        ScreenRecordingPresetStore.shared.load()
    }

    private func selectFullscreen() async -> ScreenRecordingTarget? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = displayUnderCursor(from: content.displays) else {
                log.error("No display found under cursor")
                return nil
            }
            let displayName = screenNameForDisplay(display)
            return ScreenRecordingTarget(kind: .fullscreen(display), windowTitle: nil, appName: nil, displayName: displayName)
        } catch {
            log.error("Failed to get shareable content: \(error)")
            return nil
        }
    }

    private func selectRegion() async -> ScreenRecordingTarget? {
        let overlay = ScreenCaptureOverlay()
        guard let selectedRect = await overlay.selectRegion() else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = displayUnderCursor(from: content.displays) else {
                log.error("No display found under cursor")
                return nil
            }
            return ScreenRecordingTarget(kind: .region(display, selectedRect), windowTitle: nil, appName: nil, displayName: nil)
        } catch {
            log.error("Failed to get shareable content: \(error)")
            return nil
        }
    }

    private func selectWindow() async -> ScreenRecordingTarget? {
        let overlay = ScreenCaptureOverlay()
        guard let windowID = await overlay.selectWindow() else { return nil }

        let meta = windowMetadata(for: windowID)

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                log.error("Window \(windowID) not found in shareable content")
                return nil
            }
            return ScreenRecordingTarget(kind: .window(scWindow), windowTitle: meta.title, appName: meta.appName, displayName: nil)
        } catch {
            log.error("Failed to get shareable content: \(error)")
            return nil
        }
    }

    // MARK: - Start Recording

    func startRecording(target: ScreenRecordingTarget) async -> Bool {
        guard state == .idle else {
            log.warning("Cannot start screen recording — already recording")
            return false
        }

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "TalkieAgentScreenRecording", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("screen_\(UUID().uuidString).mp4")

        // Build filter and config
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.showsCursor = true
        config.capturesAudio = false

        switch target.kind {
        case .fullscreen(let display):
            filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = scaleFactorForDisplay(display)
            config.width = Int(display.width) * scale
            config.height = Int(display.height) * scale

        case .region(let display, let rect):
            filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = scaleFactorForDisplay(display)
            // Set source rect to capture only the selected region
            let displayFrame = CGRect(
                x: CGFloat(display.frame.origin.x),
                y: CGFloat(display.frame.origin.y),
                width: CGFloat(display.width),
                height: CGFloat(display.height)
            )
            let relX = rect.origin.x - displayFrame.origin.x
            let relY = displayFrame.height - (rect.origin.y - displayFrame.origin.y) - rect.height  // Flip Y
            config.sourceRect = CGRect(x: relX, y: relY, width: rect.width, height: rect.height)
            config.width = Int(rect.width) * scale
            config.height = Int(rect.height) * scale

        case .window(let scWindow):
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
            config.width = Int(scWindow.frame.width) * 2   // Retina
            config.height = Int(scWindow.frame.height) * 2
        }

        // Tune capture cadence for storage-first AI workflows by default.
        config.minimumFrameInterval = CMTime(value: 1, timescale: recordingQualityPreset.framesPerSecond)

        // Setup AVAssetWriter
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: config.width,
                AVVideoHeightKey: config.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: recordingQualityPreset.bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ],
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true

            guard writer.canAdd(input) else {
                log.error("Cannot add video input to asset writer")
                return false
            }
            writer.add(input)
            writer.startWriting()

            setWriterState(
                writer: writer,
                input: input,
                recordedWidth: config.width,
                recordedHeight: config.height
            )

            // Start SCStream
            let scStream = SCStream(filter: filter, configuration: config, delegate: self)
            try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            try await scStream.startCapture()

            self.stream = scStream
            self.recordingURL = url
            self.target = target
            self.recordingStartTime = Date()
            state = .recording
            ScreenRecordingPresetStore.shared.save(target: target)

            log.info("Screen recording started → \(url.lastPathComponent) (\(config.width)x\(config.height), \(recordingQualityPreset.rawValue), \(recordingQualityPreset.bitrateSummary), \(recordingQualityPreset.fpsSummary))")

            // Safety valve: auto-stop after max duration (routes through controller for proper cleanup)
            maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { _ in
                Task { @MainActor in
                    log.warning("Screen recording hit max duration (\(Int(self.maxDuration))s), auto-stopping")
                    await ScreenRecordingController.shared.stopRecording()
                }
            }

            return true
        } catch {
            log.error("Failed to start screen recording: \(error)")
            resetWriterState()
            return false
        }
    }

    // MARK: - Stop Recording

    /// Stop recording and return the temp URL + metadata.
    func stopRecording() async -> (url: URL, width: Int, height: Int, target: ScreenRecordingTarget)? {
        guard state == .recording else { return nil }

        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        // Stop the stream first
        if let scStream = stream {
            do {
                try await scStream.stopCapture()
            } catch {
                log.error("Failed to stop SCStream: \(error)")
            }
            stream = nil
        }

        let result: URL? = await withCheckedContinuation { continuation in
            self.stopContinuation = continuation
            self.finishWriting()
        }

        let savedTarget = target
        target = nil
        recordingStartTime = nil

        guard let url = result, let savedTarget else { return nil }

        let (width, height) = recordedDimensions()

        return (url: url, width: width, height: height, target: savedTarget)
    }

    private func finishWriting() {
        let (writer, input) = prepareWriterForFinish()

        guard let writer else {
            stopContinuation?.resume(returning: nil)
            stopContinuation = nil
            state = .idle
            return
        }

        input?.markAsFinished()
        let url = recordingURL

        writer.finishWriting { [weak self] in
            let status = writer.status
            let errorDescription = writer.error?.localizedDescription ?? "unknown"
            Task { @MainActor in
                guard let self else { return }

                if status == .completed, let url {
                    log.info("Screen recording saved: \(url.lastPathComponent)")
                    self.stopContinuation?.resume(returning: url)
                } else {
                    log.error("Screen recording write failed: \(errorDescription)")
                    self.stopContinuation?.resume(returning: nil)
                }

                self.stopContinuation = nil
                self.recordingURL = nil

                self.resetWriterState()

                self.state = .idle
            }
        }
    }

    // MARK: - Teardown

    func teardown() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        // Resume any pending continuation before tearing down (prevents CheckedContinuation leak)
        stopContinuation?.resume(returning: nil)
        stopContinuation = nil

        if let scStream = stream {
            let s = scStream
            stream = nil
            Task {
                try? await s.stopCapture()
            }
        }

        writerLock.lock()
        if _isRecording {
            _videoInput?.markAsFinished()
            _assetWriter?.cancelWriting()
            _assetWriter = nil
            _videoInput = nil
            _isRecording = false
        }
        writerLock.unlock()

        recordingURL = nil
        target = nil
        recordingStartTime = nil
        state = .idle
        log.info("Screen recording service torn down")
    }

    // MARK: - Helpers

    private func displayUnderCursor(from displays: [SCDisplay]) -> SCDisplay? {
        let mouseLocation = NSEvent.mouseLocation
        for display in displays {
            if displayFrame(display).contains(mouseLocation) { return display }
        }
        return displays.first
    }

    private func display(for preset: ScreenRecordingPreset, from displays: [SCDisplay]) -> SCDisplay? {
        if let displayID = preset.displayID,
           let display = displays.first(where: { $0.displayID == displayID }) {
            return display
        }
        if let rect = preset.rect,
           let display = displays.first(where: { displayFrame($0).intersects(rect) }) {
            return display
        }
        return displayUnderCursor(from: displays)
    }

    private func display(
        for rect: CGRect,
        preferredTarget: ScreenRecordingTarget?,
        from displays: [SCDisplay]
    ) -> SCDisplay? {
        switch preferredTarget?.kind {
        case .fullscreen(let display), .region(let display, _):
            if displayFrame(display).intersects(rect) {
                return display
            }
        case .window, .none:
            break
        }

        return displays.max { lhs, rhs in
            intersectionArea(displayFrame(lhs), rect) < intersectionArea(displayFrame(rhs), rect)
        }
    }

    private func displayFrame(_ display: SCDisplay) -> CGRect {
        CGRect(
            x: CGFloat(display.frame.origin.x),
            y: CGFloat(display.frame.origin.y),
            width: CGFloat(display.width),
            height: CGFloat(display.height)
        )
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func window(for preset: ScreenRecordingPreset, from windows: [SCWindow]) -> SCWindow? {
        if let windowID = preset.windowID,
           let window = windows.first(where: { $0.windowID == windowID }) {
            return window
        }

        return windows.first { window in
            let meta = windowMetadata(for: window.windowID)
            let titleMatches = preset.windowTitle.map { $0 == meta.title } ?? true
            let appMatches = preset.appName.map { $0 == meta.appName } ?? true
            return titleMatches && appMatches
        }
    }

    private func scaleFactorForDisplay(_ display: SCDisplay) -> Int {
        let frame = displayFrame(display)
        for screen in NSScreen.screens {
            if screen.frame == frame || screen.frame.intersects(frame) {
                return Int(screen.backingScaleFactor)
            }
        }
        return 2
    }

    private func screenNameForDisplay(_ display: SCDisplay) -> String? {
        let displayFrame = CGRect(
            x: CGFloat(display.frame.origin.x),
            y: CGFloat(display.frame.origin.y),
            width: CGFloat(display.width),
            height: CGFloat(display.height)
        )
        for screen in NSScreen.screens {
            if screen.frame == displayFrame { return screen.localizedName }
        }
        if NSScreen.screens.count == 1 { return NSScreen.screens.first?.localizedName }
        return nil
    }

    private func windowMetadata(for windowID: CGWindowID) -> (title: String?, appName: String?) {
        guard let infoList = CGWindowListCreateDescriptionFromArray([windowID] as CFArray) as? [[String: Any]],
              let info = infoList.first else {
            return (nil, nil)
        }
        let title = info[kCGWindowName as String] as? String
        let appName = info[kCGWindowOwnerName as String] as? String
        return (title, appName)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "TalkieAgent needs Screen Recording permission to capture your screen. Please enable it in System Settings > Privacy & Security > Screen Recording."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func setWriterState(
        writer: AVAssetWriter,
        input: AVAssetWriterInput,
        recordedWidth: Int,
        recordedHeight: Int
    ) {
        writerLock.lock()
        _assetWriter = writer
        _videoInput = input
        _isRecording = true
        _isWriterStarted = false
        _recordedWidth = recordedWidth
        _recordedHeight = recordedHeight
        writerLock.unlock()
    }

    private func resetWriterState() {
        writerLock.lock()
        _assetWriter = nil
        _videoInput = nil
        _isRecording = false
        _isWriterStarted = false
        writerLock.unlock()
    }

    private func recordedDimensions() -> (width: Int, height: Int) {
        writerLock.lock()
        let width = _recordedWidth
        let height = _recordedHeight
        writerLock.unlock()
        return (width, height)
    }

    private func prepareWriterForFinish() -> (writer: AVAssetWriter?, input: AVAssetWriterInput?) {
        writerLock.lock()
        let writer = _assetWriter
        let input = _videoInput
        _isRecording = false
        writerLock.unlock()
        return (writer, input)
    }
}

// MARK: - SCStreamOutput

extension ScreenRecordingService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Check attachment status to filter idle/blank frames
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusValue),
              status == .complete else {
            return
        }

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
        }
        writerLock.unlock()

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecordingService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Log(.system).error("SCStream stopped with error: \(error)")
        Task { @MainActor in
            self.teardown()
        }
    }
}
