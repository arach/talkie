import Foundation
import AppKit
import TalkieKit

// MARK: - Surface Coordinator

/// Single state owner for the capture surface system.
///
/// Coordinates hover, explicit-open, and recording state for the remaining
/// Talkie-owned tray surfaces:
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

    private init() {}

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

    /// Recording always wins and auto-dismisses the shelf.
    func beginRecording(phase: RecordingPhase = .active) {
        // Auto-dismiss shelf if it's open — recording always wins
        if case .explicitOpen(.shelf) = state {
            TrayShelf.shared.dismiss()
        }
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

}
