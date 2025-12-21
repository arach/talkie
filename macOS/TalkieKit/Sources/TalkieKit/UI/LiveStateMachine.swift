//
//  LiveStateMachine.swift
//  TalkieKit
//
//  Robust state machine for TalkieLive recording states
//  Ensures only valid transitions and centralizes state change logic
//

import Foundation

// MARK: - State Transition Events

/// Events that trigger state transitions
public enum LiveStateEvent {
    case startRecording
    case stopRecording
    case beginTranscription
    case beginRouting
    case complete
    case cancel
    case error(String)
    case forceReset
}

// MARK: - State Machine

/// Manages LiveState transitions with validation
@MainActor
public final class LiveStateMachine: ObservableObject {
    @Published public private(set) var state: LiveState = .idle

    /// Callback invoked on every state transition
    public var onStateChange: ((LiveState, LiveState) -> Void)?

    /// Callback invoked when an invalid transition is attempted
    public var onInvalidTransition: ((LiveState, LiveStateEvent) -> Void)?

    public init() {}

    /// Attempt a state transition based on an event
    /// Returns true if transition was valid and completed, false if rejected
    @discardableResult
    public func transition(_ event: LiveStateEvent) -> Bool {
        let oldState = state

        guard let newState = validTransition(from: state, event: event) else {
            onInvalidTransition?(state, event)
            return false
        }

        state = newState
        onStateChange?(oldState, newState)
        return true
    }

    /// Force set state (use sparingly, only for initialization or recovery)
    public func forceSetState(_ newState: LiveState) {
        let oldState = state
        state = newState
        onStateChange?(oldState, newState)
    }

    /// Check if a transition is valid without executing it
    public func canTransition(_ event: LiveStateEvent) -> Bool {
        return validTransition(from: state, event: event) != nil
    }

    // MARK: - Transition Logic

    /// Determines the next valid state given current state and event
    /// Returns nil if transition is invalid
    private func validTransition(from currentState: LiveState, event: LiveStateEvent) -> LiveState? {
        switch (currentState, event) {

        // IDLE state transitions
        case (.idle, .startRecording):
            return .listening
        case (.idle, .forceReset):
            return .idle  // Already idle, but allow for cleanup

        // LISTENING state transitions
        case (.listening, .stopRecording):
            return .transcribing  // Always transition to transcribing when stopping
        case (.listening, .cancel):
            return .transcribing  // Cancelled recordings still go through transcribing for cleanup
        case (.listening, .error):
            return .idle  // Audio capture error, abort immediately
        case (.listening, .forceReset):
            return .idle

        // TRANSCRIBING state transitions
        case (.transcribing, .beginRouting):
            return .routing
        case (.transcribing, .complete):
            return .idle  // Cancelled or queued, skip routing
        case (.transcribing, .cancel):
            return .idle  // User pushed to queue during transcription
        case (.transcribing, .error):
            return .idle  // Transcription failed
        case (.transcribing, .forceReset):
            return .idle

        // ROUTING state transitions
        case (.routing, .complete):
            return .idle
        case (.routing, .cancel):
            return .idle  // User pushed to queue during routing
        case (.routing, .error):
            return .idle  // Routing failed
        case (.routing, .forceReset):
            return .idle

        // Invalid transitions
        default:
            return nil
        }
    }
}

// MARK: - Valid Transitions Documentation

/*
 State Transition Graph:

 IDLE
  ├─ startRecording → LISTENING
  └─ forceReset → IDLE

 LISTENING
  ├─ stopRecording → TRANSCRIBING
  ├─ cancel → TRANSCRIBING (audio preserved)
  ├─ error → IDLE (capture failure)
  └─ forceReset → IDLE

 TRANSCRIBING
  ├─ beginRouting → ROUTING
  ├─ complete → IDLE (cancelled/queued)
  ├─ cancel → IDLE (pushed to queue)
  ├─ error → IDLE (transcription failed)
  └─ forceReset → IDLE

 ROUTING
  ├─ complete → IDLE (success)
  ├─ cancel → IDLE (pushed to queue)
  ├─ error → IDLE (routing failed)
  └─ forceReset → IDLE

 Invalid transitions (will be rejected):
 - IDLE → transcribing/routing
 - LISTENING → routing
 - TRANSCRIBING → listening
 - ROUTING → listening/transcribing
 - Any state → startRecording (except IDLE)
 */
