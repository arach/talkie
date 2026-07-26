//
//  CameraBubbleController.swift
//  Talkie
//
//  Orchestrator for the face camera bubble.
//  State machine: hidden → previewing → recording.
//  Coordinates CameraCaptureService, CameraBubblePanel, and ClipTray.
//

import AppKit
import SwiftUI
import TalkieKit

private let log = Log(.system)

// MARK: - Camera Bubble Controller

@MainActor
@Observable
final class CameraBubbleController {
    static let shared = CameraBubbleController()

    // MARK: - State

    enum State: Equatable {
        case hidden
        case previewing
        case recording
    }

    private(set) var state: State = .hidden

    @ObservationIgnored
    private let panel = CameraBubblePanel()
    @ObservationIgnored
    private var clipStartTime: Date?
    @ObservationIgnored
    private var hideAfterStop = false

    private init() {}

    // MARK: - Toggle

    func toggle() {
        log.warning("Camera: toggle() entered, state=\(String(describing: self.state))")
        switch state {
        case .hidden:
            show()
        case .previewing:
            hide()
        case .recording:
            // Stop recording first — hide() will be called after the async stop completes
            hideAfterStop = true
            stopClip()
        }
    }

    // MARK: - Show / Hide

    func show() {
        guard state == .hidden else { return }
        state = .previewing  // Set immediately to prevent double-entry race

        Task {
            let captureService = CameraCaptureService.shared

            guard await captureService.requestPermission() else {
                log.warning("Camera permission denied, cannot show bubble")
                state = .hidden
                return
            }

            // Use async startPreview so we don't block the main thread
            guard await captureService.startPreviewAsync() else {
                log.error("Camera preview failed to start")
                state = .hidden
                return
            }

            panel.show()
            log.info("Camera bubble shown")
        }
    }

    func hide() {
        guard state != .recording else {
            // If still recording, stop first and hide on completion
            hideAfterStop = true
            stopClip()
            return
        }

        hideAfterStop = false
        CameraCaptureService.shared.stopPreview()
        panel.dismiss()
        state = .hidden
        log.info("Camera bubble hidden")
    }

    // MARK: - Clip Recording

    func startClip() {
        guard state == .previewing else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkieClipBuffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let filename = "clip_\(UUID().uuidString).mp4"
        let url = tempDir.appendingPathComponent(filename)

        clipStartTime = Date()
        CameraCaptureService.shared.startClipRecording(to: url)
        state = .recording
        log.info("Clip recording started")
    }

    func stopClip() {
        guard state == .recording else { return }
        state = .previewing  // Set immediately to prevent double-entry race

        let startTime = clipStartTime ?? Date()
        let shouldHide = hideAfterStop
        hideAfterStop = false

        Task {
            guard let url = await CameraCaptureService.shared.stopClipRecording() else {
                log.error("Clip recording returned no URL")
                if shouldHide { hide() }
                return
            }

            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            try? FileManager.default.removeItem(at: url)
            log.info("Clip recording stopped, \(durationMs)ms; camera clip tray is retired")

            if shouldHide { hide() }
        }
    }

    // MARK: - Drain (called by MemoRecordingController)

    /// Drain all buffered clips to a recording.
    func drainClipsToRecording(recordingId: UUID, recordingStartTime: Date) -> [RecordingClip] {
        _ = (recordingId, recordingStartTime)
        return []
    }
}

/// Shared metrics so tray pill and status pill render at the same width.
enum TrayPillMetrics {
    static let fixedWidth: CGFloat = 180
}
