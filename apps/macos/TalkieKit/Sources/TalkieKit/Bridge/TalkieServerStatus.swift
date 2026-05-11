//
//  TalkieAgentServerStatus.swift
//  TalkieKit
//
//  Shared status struct for TalkieServer (Bun sidecar) supervision.
//  Used across XPC between TalkieAgent (supervisor) and Talkie.app (observer).
//

import Foundation

public struct TalkieAgentServerStatus: Codable, Sendable {
    public enum ProcessState: String, Codable, Sendable {
        case stopped
        case starting
        case running
        case degraded
        case error
    }

    public let processState: ProcessState
    public let pid: Int32?
    public let uptime: TimeInterval?
    public let lastHealthCheckOk: Bool
    public let consecutiveFailures: Int
    public let restartCount: Int
    public let lastError: String?
    public let tailscaleReady: Bool
    public let backoffSeconds: TimeInterval?

    public init(
        processState: ProcessState,
        pid: Int32? = nil,
        uptime: TimeInterval? = nil,
        lastHealthCheckOk: Bool = false,
        consecutiveFailures: Int = 0,
        restartCount: Int = 0,
        lastError: String? = nil,
        tailscaleReady: Bool = false,
        backoffSeconds: TimeInterval? = nil
    ) {
        self.processState = processState
        self.pid = pid
        self.uptime = uptime
        self.lastHealthCheckOk = lastHealthCheckOk
        self.consecutiveFailures = consecutiveFailures
        self.restartCount = restartCount
        self.lastError = lastError
        self.tailscaleReady = tailscaleReady
        self.backoffSeconds = backoffSeconds
    }

    public static let stopped = TalkieAgentServerStatus(processState: .stopped)
}
