//
//  TalkieLiveXPCProtocol.swift
//  Talkie
//
//  XPC protocol for communication between Talkie and TalkieLive
//  TalkieLive exposes this service, Talkie connects to it
//

import Foundation

/// XPC service name - TalkieLive registers as this
public let kTalkieLiveXPCServiceName = "live.talkie.xpc.liveState"

/// Protocol for TalkieLive's XPC service
@objc protocol TalkieLiveXPCServiceProtocol {
    /// Get current recording state
    func getCurrentState(reply: @escaping (String, TimeInterval) -> Void)

    /// Register for state change notifications
    func registerStateObserver(reply: @escaping (Bool) -> Void)

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
