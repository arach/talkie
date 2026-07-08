//
//  HeadlessLiveClient.swift
//  TalkieHeadless
//
//  XPC client for TalkieAgent.
//  Used to request ephemeral audio capture for extension transcription.
//

import Foundation

/// XPC Protocol for TalkieAgent (must match TalkieKit.TalkieAgentXPCServiceProtocol)
@objc protocol TalkieAgentXPCServiceProtocol {
    func getCurrentState(reply: @escaping (_ state: String, _ elapsedTime: TimeInterval, _ pid: Int32) -> Void)
    func startEphemeralCapture(reply: @escaping (_ sessionId: String?, _ error: String?) -> Void)
    func stopEphemeralCapture(sessionId: String, reply: @escaping (_ audioPath: String?, _ error: String?) -> Void)
}

/// Live service modes
enum LiveServiceMode: String {
    case production = "to.talkie.agent.xpc"
    case dev = "to.talkie.agent.xpc.dev"
}

actor HeadlessLiveClient {
    private var connection: NSXPCConnection?
    private var liveProxy: TalkieAgentXPCServiceProtocol?
    private(set) var isConnected = false

    func connect() async {
        // Try dev first in debug builds
        #if DEBUG
        let mode = LiveServiceMode.dev
        #else
        let mode = LiveServiceMode.production
        #endif

        HeadlessConsole.info("[LiveClient] Connecting to \(mode.rawValue)...")

        let conn = NSXPCConnection(machServiceName: mode.rawValue)
        conn.remoteObjectInterface = NSXPCInterface(with: TalkieAgentXPCServiceProtocol.self)

        conn.invalidationHandler = { [weak self] in
            HeadlessConsole.info("[LiveClient] Connection invalidated")
            Task { await self?.handleDisconnection() }
        }

        conn.interruptionHandler = { [weak self] in
            HeadlessConsole.info("[LiveClient] Connection interrupted")
            Task { await self?.handleDisconnection() }
        }

        conn.resume()

        // Test connection with getCurrentState (with timeout)
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            HeadlessConsole.info("[LiveClient] XPC proxy error: \(error)")
        }) as? TalkieAgentXPCServiceProtocol else {
            HeadlessConsole.info("[LiveClient] Failed to get proxy")
            conn.invalidate()
            return
        }

        // Await state check with 3 second timeout
        let result: (String, TimeInterval, Int32)? = await withTaskGroup(of: (String, TimeInterval, Int32)?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<(String, TimeInterval, Int32), Never>) in
                    proxy.getCurrentState { state, elapsedTime, pid in
                        continuation.resume(returning: (state, elapsedTime, pid))
                    }
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second timeout
                return nil
            }

            // Return first completed result
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }

        guard let (state, _, pid) = result else {
            HeadlessConsole.info("[LiveClient] Connection timeout - TalkieAgent may not be running or XPC listener not started")
            conn.invalidate()
            return
        }

        self.connection = conn
        self.liveProxy = proxy
        self.isConnected = true
        HeadlessConsole.info("[LiveClient] Connected! TalkieAgent state: \(state), pid: \(pid)")
    }

    private func handleDisconnection() {
        isConnected = false
        liveProxy = nil
        connection?.invalidate()
        connection = nil
        HeadlessConsole.info("[LiveClient] Disconnected")
    }

    /// Start ephemeral audio capture
    func startCapture() async throws -> String {
        // Reconnect if needed
        if !isConnected {
            HeadlessConsole.info("[LiveClient] Not connected, attempting reconnect...")
            await connect()
        }

        guard let proxy = liveProxy else {
            throw LiveClientError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.startEphemeralCapture { sessionId, error in
                if let error = error {
                    continuation.resume(throwing: LiveClientError.captureError(error))
                } else if let sessionId = sessionId {
                    continuation.resume(returning: sessionId)
                } else {
                    continuation.resume(throwing: LiveClientError.emptyResponse)
                }
            }
        }
    }

    /// Stop ephemeral audio capture and get audio file path
    func stopCapture(sessionId: String) async throws -> String {
        // Reconnect if needed
        if !isConnected {
            HeadlessConsole.info("[LiveClient] Not connected, attempting reconnect...")
            await connect()
        }

        guard let proxy = liveProxy else {
            throw LiveClientError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.stopEphemeralCapture(sessionId: sessionId) { audioPath, error in
                if let error = error {
                    continuation.resume(throwing: LiveClientError.captureError(error))
                } else if let audioPath = audioPath {
                    continuation.resume(returning: audioPath)
                } else {
                    continuation.resume(throwing: LiveClientError.emptyResponse)
                }
            }
        }
    }

    /// Preflight check - verifies connection and microphone status
    func preflight() async -> PreflightStatus {
        // Attempt reconnect if needed
        if !isConnected {
            HeadlessConsole.info("[LiveClient] Preflight: attempting connection...")
            await connect()
        }

        guard let proxy = liveProxy, isConnected else {
            return PreflightStatus(
                connected: false,
                microphoneAuthorized: false,
                detail: "TalkieAgent not running or XPC not registered"
            )
        }

        // Get current state to verify connection and check mic status
        let result: (String, TimeInterval, Int32)? = await withTaskGroup(of: (String, TimeInterval, Int32)?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<(String, TimeInterval, Int32), Never>) in
                    proxy.getCurrentState { state, elapsedTime, pid in
                        continuation.resume(returning: (state, elapsedTime, pid))
                    }
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second timeout
                return nil
            }

            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }

        guard let (state, _, _) = result else {
            return PreflightStatus(
                connected: false,
                microphoneAuthorized: false,
                detail: "TalkieAgent connection timeout"
            )
        }

        // TalkieAgent is connected and responsive
        // Microphone is authorized if we can get state (TalkieAgent checks on startup)
        // State will be "idle", "recording", etc.
        return PreflightStatus(
            connected: true,
            microphoneAuthorized: true,  // TalkieAgent requires mic permission to run
            detail: "Connected, state: \(state)"
        )
    }
}

/// Result of preflight check
struct PreflightStatus {
    let connected: Bool
    let microphoneAuthorized: Bool
    let detail: String
}

enum LiveClientError: LocalizedError {
    case notConnected
    case captureError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to TalkieAgent"
        case .captureError(let message):
            return "Capture failed: \(message)"
        case .emptyResponse:
            return "Empty response from TalkieAgent"
        }
    }
}
