//
//  TalkieLiveXPCProtocol.swift
//  Talkie
//
//  XPC protocol for communication between Talkie and TalkieLive
//  TalkieLive exposes this service, Talkie connects to it
//

import Foundation
import TalkieKit

/// XPC service name - TalkieLive registers as this (environment-aware)
public var kTalkieLiveXPCServiceName: String {
    TalkieEnvironment.current.liveXPCService
}

/// Protocol for TalkieLive's XPC service
@objc protocol TalkieLiveXPCServiceProtocol {
    /// Get current recording state and process ID
    func getCurrentState(reply: @escaping (String, TimeInterval, Int32) -> Void)

    /// Register for state change notifications (returns success and PID)
    func registerStateObserver(reply: @escaping (Bool, Int32) -> Void)

    /// Unregister from state change notifications
    func unregisterStateObserver(reply: @escaping (Bool) -> Void)

    /// Toggle recording (start if idle, stop if listening)
    func toggleRecording(reply: @escaping (Bool) -> Void)
}

/// Protocol for Talkie (the client) to receive state updates
@objc protocol TalkieLiveStateObserverProtocol {
    /// Called when TalkieLive's state changes
    func stateDidChange(state: String, elapsedTime: TimeInterval)

    /// Called when TalkieLive adds a new utterance to the database
    func utteranceWasAdded()
}
