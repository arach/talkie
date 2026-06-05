import Foundation
import AppKit
import TalkieKit

// MARK: - Surface Coordinator

/// Single state owner for the capture surface system.
///
/// Wraps NotchComposer (which handles intent priority for recording/screenRecording/idle)
/// and adds the missing state layers:
/// - Hover state (previously implicit in mouse position + expansion timers)
/// - Explicit-open state for the primary non-recording viewer/shelf surface
/// - Dismiss coordination (previously each surface handled its own dismiss)
///
/// Renderers read `state` to decide what to show. No renderer reads raw state
/// from another renderer.
///
/// Precedence (highest first):
/// 1. Recording — always wins, auto-dismisses shelf
/// 2. ExplicitOpen — viewer or shelf when recording is not active
/// 3. Hovering — passive, never overrides explicit-open
/// 4. Idle — baseline
@MainActor
@Observable
final class SurfaceCoordinator {
    static let shared = SurfaceCoordinator()

    // MARK: - State

    enum SurfaceState: Equatable {
        case idle
        case hovering
        case recording(phase: RecordingPhase)
        case explicitOpen(surface: ExplicitSurface)
    }

    enum ExplicitSurface: Equatable {
        case viewer
        case shelf
    }

    enum RecordingPhase: Equatable {
        case starting
        case active
        case processing
    }

    /// The current surface state. Renderers observe this.
    private(set) var state: SurfaceState = .idle

    /// Whether hover is currently active (tracked independently so it can
    /// resume after explicit-open dismiss without re-entering the shell region).
    @ObservationIgnored
    private var hoverActive = false

    /// Guards against re-entrant intent observation Tasks.
    @ObservationIgnored
    private var intentChangeTask: Task<Void, Never>?

    private init() {
        observeRecordingIntent()
    }

    // MARK: - Hover

    func enterHover() {
        hoverActive = true
        // Hover is passive — don't override explicit-open or recording
        if case .idle = state {
            state = .hovering
        }
    }

    func exitHover() {
        hoverActive = false
        if case .hovering = state {
            state = .idle
        }
    }

    // MARK: - Recording

    /// Called when NotchComposer resolves to a recording intent.
    func beginRecording(phase: RecordingPhase = .active) {
        state = .recording(phase: phase)
    }

    func updateRecordingPhase(_ phase: RecordingPhase) {
        if case .recording = state {
            state = .recording(phase: phase)
        }
    }

    func endRecording() {
        guard case .recording = state else { return }
        // Return to hover if mouse is still in shell region, otherwise idle
        state = hoverActive ? .hovering : .idle
    }

    // MARK: - Explicit Open (Viewer / Shelf)

    func openViewer() {
        // Viewer may still open as an auxiliary panel during recording, but the
        // primary overlay state remains `.recording`.
        if case .recording = state { return }
        state = .explicitOpen(surface: .viewer)
    }

    func openShelf() {
        // Shelf cannot open during recording — recording wins
        if case .recording = state { return }
        state = .explicitOpen(surface: .shelf)
    }

    func dismiss() {
        guard case .explicitOpen = state else { return }
        state = hoverActive ? .hovering : .idle
    }

    // MARK: - Query

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isExplicitOpen: Bool {
        if case .explicitOpen = state { return true }
        return false
    }

    // MARK: - NotchComposer Bridge

    /// Observe NotchComposer's resolved intent and map to SurfaceCoordinator state.
    /// This is the bridge — NotchComposer handles intent priority,
    /// SurfaceCoordinator handles the state layers on top.
    private func observeRecordingIntent() {
        withObservationTracking {
            let _ = NotchComposer.shared.resolvedIntent
            let _ = NotchComposer.shared.resolvedPayload
        } onChange: {
            Task { @MainActor in
                self.intentChangeTask?.cancel()
                self.intentChangeTask = Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    self.handleIntentChange()
                }
                self.observeRecordingIntent()
            }
        }
    }

    private func handleIntentChange() {
        let intent = NotchComposer.shared.resolvedIntent
        let payload = NotchComposer.shared.resolvedPayload

        switch intent {
        case .recording:
            // Map payload state to recording phase
            let phase: RecordingPhase
            switch payload {
            case .recording(let recordingState, _, _):
                switch recordingState {
                case .listening:
                    phase = .active
                case .transcribing, .routing, .refining:
                    phase = .processing
                case .idle:
                    phase = .active
                }
            default:
                phase = .active
            }

            if case .recording = state {
                updateRecordingPhase(phase)
            } else {
                beginRecording(phase: phase)
            }

        case .screenRecording:
            // Screen recording uses the same recording state for now
            if case .recording = state {
                // Already in recording state
            } else {
                beginRecording(phase: .active)
            }

        case .idle, .cameraLoading:
            if case .recording = state {
                endRecording()
            }
        }
    }
}
