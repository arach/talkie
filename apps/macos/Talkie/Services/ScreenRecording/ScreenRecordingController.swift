//
//  ScreenRecordingController.swift
//  Talkie
//
//  Orchestrator for screen video recording.
//  Flow: Hyper+R → chord HUD → select target → record → stop pill → tray.
//  Coordinates ScreenRecordingService, NotchComposer, and ClipTray (capture tray).
//

import Foundation
import TalkieKit

private let log = Log(.system)

@MainActor
@Observable
final class ScreenRecordingController {
    static let shared = ScreenRecordingController()

    // MARK: - State

    enum State: Equatable {
        case idle
        case selecting       // User is picking region/window
        case recording       // Actively recording
    }

    private(set) var state: State = .idle
    private(set) var recordingStartTime: Date?

    private init() {}

    // MARK: - Start Recording (from chord result)

    /// Start a screen recording with the given capture mode.
    /// Handles target selection, recording start, and pill display.
    func startRecording(mode: CaptureMode) async {
        guard state == .idle else {
            log.warning("Cannot start screen recording — state: \(String(describing: state))")
            return
        }

        state = .selecting

        let service = ScreenRecordingService.shared

        // Let user select what to record
        guard let target = await service.selectTarget(mode: mode) else {
            log.info("Screen recording target selection cancelled")
            state = .idle
            return
        }

        // Start recording
        let started = await service.startRecording(target: target)
        guard started else {
            log.error("Screen recording failed to start")
            state = .idle
            return
        }

        recordingStartTime = Date()
        state = .recording
        // NotchComposer observes our state change and activates .screenRecording automatically
        log.info("Screen recording in progress (mode: \(mode.rawValue))")
    }

    // MARK: - Stop Recording

    /// Stop the current screen recording and add the clip to the tray.
    func stopRecording() async {
        guard state == .recording else { return }

        // Capture start time before stop clears it
        let startTime = ScreenRecordingService.shared.recordingStartTime

        guard let result = await ScreenRecordingService.shared.stopRecording() else {
            log.error("Screen recording stop returned no result")
            recordingStartTime = nil
            state = .idle
            return
        }

        // Calculate duration
        let durationMs: Int
        if let startTime {
            durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        } else {
            durationMs = 0
        }

        // Determine capture mode string from target
        let captureMode: String
        switch result.target.kind {
        case .fullscreen: captureMode = "fullscreen"
        case .region: captureMode = "region"
        case .window: captureMode = "window"
        }

        // Add to clip tray
        ClipTray.shared.add(
            tempURL: result.url,
            durationMs: durationMs,
            width: result.width,
            height: result.height,
            captureMode: captureMode,
            windowTitle: result.target.windowTitle,
            appName: result.target.appName,
            displayName: result.target.displayName
        )

        recordingStartTime = nil
        state = .idle
        // NotchComposer observes our state change and deactivates .screenRecording automatically
        log.info("Screen recording stopped, \(durationMs)ms → tray (\(ClipTray.shared.count) total)")
    }

    // MARK: - Toggle (for stop via hotkey)

    /// If recording, stop. Otherwise do nothing (chord handles start).
    func stopIfRecording() async {
        if state == .recording {
            await stopRecording()
        }
    }
}
