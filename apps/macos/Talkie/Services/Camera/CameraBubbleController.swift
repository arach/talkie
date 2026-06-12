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
        let t0 = CFAbsoluteTimeGetCurrent()
        state = .previewing  // Set immediately to prevent double-entry race

        // Show "loading camera" via NotchComposer
        NotchComposer.shared.activate(.cameraLoading, payload: .cameraLoading)
        let t1 = CFAbsoluteTimeGetCurrent()
        log.warning("Camera: notch cameraLoading at +\(Int((t1 - t0) * 1000))ms")

        Task {
            let captureService = CameraCaptureService.shared

            // Yield to run loop so the notch panel actually renders before we block
            await MainActor.run { }
            try? await Task.sleep(for: .milliseconds(1))

            let t2 = CFAbsoluteTimeGetCurrent()
            log.warning("Camera: Task entered at +\(Int((t2 - t0) * 1000))ms")

            guard await captureService.requestPermission() else {
                log.warning("Camera permission denied, cannot show bubble")
                NotchComposer.shared.deactivate(.cameraLoading)
                state = .hidden
                return
            }
            let t3 = CFAbsoluteTimeGetCurrent()
            log.warning("Camera: permission at +\(Int((t3 - t0) * 1000))ms")

            // Use async startPreview so we don't block the main thread
            guard await captureService.startPreviewAsync() else {
                log.error("Camera preview failed to start")
                NotchComposer.shared.deactivate(.cameraLoading)
                state = .hidden
                return
            }
            let t4 = CFAbsoluteTimeGetCurrent()
            log.warning("Camera: preview ready at +\(Int((t4 - t0) * 1000))ms")

            panel.show()
            let t5 = CFAbsoluteTimeGetCurrent()
            log.warning("Camera: panel.show at +\(Int((t5 - t0) * 1000))ms")

            // Dismiss pill when session is running (or after timeout)
            awaitSessionReady(t0: t0)
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
        NotchComposer.shared.deactivate(.cameraLoading)
        CameraCaptureService.shared.stopPreview()
        panel.dismiss()
        state = .hidden
        log.info("Camera bubble hidden")
    }

    // MARK: - Session Ready

    private func awaitSessionReady(t0: CFAbsoluteTime) {
        Task {
            // Poll for session running (lightweight, ~50ms intervals)
            let captureService = CameraCaptureService.shared
            for _ in 0..<60 {  // Max 3s timeout
                try? await Task.sleep(for: .milliseconds(50))
                if captureService.isSessionRunning { break }
            }
            let t6 = CFAbsoluteTimeGetCurrent()
            log.warning("Camera: session running at +\(Int((t6 - t0) * 1000))ms")

            // Brief hold so the label registers visually
            try? await Task.sleep(for: .milliseconds(300))
            NotchComposer.shared.deactivate(.cameraLoading)
            let t7 = CFAbsoluteTimeGetCurrent()
            log.warning("Camera: notch cameraLoading dismissed at +\(Int((t7 - t0) * 1000))ms (total)")
        }
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
            let capture = CameraCaptureService.shared

            // Add to buffer with actual recorded dimensions
            await ClipTray.shared.add(
                tempURL: url,
                durationMs: durationMs,
                width: capture.cameraWidth > 0 ? capture.cameraWidth : 1280,
                height: capture.cameraHeight > 0 ? capture.cameraHeight : 720
            )

            log.info("Clip recording stopped, \(durationMs)ms → tray (\(ClipTray.shared.count) total)")

            if shouldHide { hide() }
        }
    }

    // MARK: - Drain (called by MemoRecordingController)

    /// Drain all buffered clips to a recording.
    func drainClipsToRecording(recordingId: UUID, recordingStartTime: Date) -> [RecordingClip] {
        ClipTray.shared.drainToRecording(
            recordingId: recordingId,
            recordingStartTime: recordingStartTime
        )
    }
}

/// Shared metrics so tray pill and status pill render at the same width.
enum TrayPillMetrics {
    static let fixedWidth: CGFloat = 180
}
