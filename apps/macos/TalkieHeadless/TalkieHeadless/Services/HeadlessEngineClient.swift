//
//  HeadlessEngineClient.swift
//  TalkieHeadless
//
//  XPC client for the engine hosted inside TalkieAgent.
//  Simplified version for headless operation.
//

import Foundation

/// Minimal engine surface exposed by TalkieAgent.
@objc protocol TalkieAgentEngineProtocol {
    func ping(reply: @escaping (Bool) -> Void)
    func transcribe(audioPath: String, modelId: String, externalRefId: String?, priority: Int, postProcess: Int, reply: @escaping (String?, String?) -> Void)
    func getStatus(reply: @escaping (Data?) -> Void)
}

/// Agent XPC service modes for the embedded engine.
enum EmbeddedEngineServiceMode: String {
    case production = "to.talkie.app.agent.xpc"
    case dev = "to.talkie.app.agent.xpc.dev"
}

actor HeadlessEngineClient {
    private var connection: NSXPCConnection?
    private var engineProxy: TalkieAgentEngineProtocol?
    private(set) var isConnected = false

    func connect() async {
        // Try dev first in debug builds
        #if DEBUG
        let mode = EmbeddedEngineServiceMode.dev
        #else
        let mode = EmbeddedEngineServiceMode.production
        #endif

        print("[EngineClient] Connecting to embedded engine via \(mode.rawValue)...")

        let conn = NSXPCConnection(machServiceName: mode.rawValue)
        conn.remoteObjectInterface = NSXPCInterface(with: TalkieAgentEngineProtocol.self)

        conn.invalidationHandler = { [weak self] in
            Task { await self?.handleDisconnection() }
        }

        conn.interruptionHandler = { [weak self] in
            Task { await self?.handleDisconnection() }
        }

        conn.resume()

        // Test connection with ping
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            print("[EngineClient] XPC error: \(error)")
        }) as? TalkieAgentEngineProtocol else {
            print("[EngineClient] Failed to get proxy")
            return
        }

        // Await ping result
        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            proxy.ping { pong in
                continuation.resume(returning: pong)
            }
        }

        if success {
            self.connection = conn
            self.engineProxy = proxy
            self.isConnected = true
            print("[EngineClient] Connected to embedded engine!")
        } else {
            conn.invalidate()
            print("[EngineClient] Ping failed")
        }
    }

    private func handleDisconnection() {
        isConnected = false
        engineProxy = nil
        connection?.invalidate()
        connection = nil
        print("[EngineClient] Disconnected")
    }

    func transcribe(audioPath: String, modelId: String = "parakeet:v3") async throws -> String {
        guard let proxy = engineProxy else {
            throw EngineError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.transcribe(
                audioPath: audioPath,
                modelId: modelId,
                externalRefId: nil,
                priority: 1,  // High priority
                postProcess: 0  // None
            ) { transcript, error in
                if let error = error {
                    continuation.resume(throwing: EngineError.transcriptionFailed(error))
                } else if let transcript = transcript {
                    continuation.resume(returning: transcript)
                } else {
                    continuation.resume(throwing: EngineError.emptyResponse)
                }
            }
        }
    }

    /// Check connection status, attempting reconnect if needed
    func checkConnection() async -> Bool {
        // Attempt reconnect if needed
        if !isConnected {
            print("[EngineClient] Preflight: attempting connection...")
            await connect()
        }

        guard let proxy = engineProxy, isConnected else {
            return false
        }

        // Verify with ping (with timeout)
        let result: Bool? = await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    proxy.ping { pong in
                        continuation.resume(returning: pong)
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

        return result == true
    }
}

enum EngineError: LocalizedError {
    case notConnected
    case transcriptionFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to TalkieAgent embedded engine"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .emptyResponse:
            return "Empty response from engine"
        }
    }
}
