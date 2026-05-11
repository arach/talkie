import Foundation
import TalkieKit

/// WebSocket JSON-RPC bridge for TalkieAgent on port 19823.
/// Exposes dictation and agent methods to external clients (Lattices, Hudson, CLI SDK).
///
/// Methods:
///   ping → {pong: true}
///   register → {sessionToken: "...", grantedCapabilities: [...]}
///   startDictation (streaming) → stateChange, partialTranscript, finalTranscript events
///   stopDictation → {stopped: true}
///   cancelDictation → {cancelled: true}
final class AgentServiceBridge: @unchecked Sendable {
    @MainActor static let shared = AgentServiceBridge()

    private let log = Log(.system)
    private let port: UInt16 = 19823
    private var bridge: ServiceBridge?

    // Track client IDs per connection (for disconnect cleanup)
    private let lock = NSLock()
    private var _clientsByConnection: [String: String] = [:]  // connectionID → clientId

    private func setClient(_ clientId: String, forConnection connID: String) {
        lock.withLock { _clientsByConnection[connID] = clientId }
    }

    private func clientId(forConnection connID: String) -> String? {
        lock.withLock { _clientsByConnection[connID] }
    }

    private func removeClient(forConnectionHash hashValue: Int) -> String? {
        let key = "\(hashValue)"
        return lock.withLock {
            let clientId = _clientsByConnection.removeValue(forKey: key)
            return clientId
        }
    }

    func start() {
        let bridge = ServiceBridge(port: port, serviceName: "Agent")
        self.bridge = bridge

        // MARK: - Disconnect cleanup

        bridge.onClientDisconnected = { [weak self] connectionID in
            guard let self else { return }
            guard let clientId = self.removeClient(forConnectionHash: connectionID.hashValue) else { return }
            self.log.info("[AgentBridge] Client disconnected: \(clientId)")
            Task { @MainActor in
                DictationBridge.shared.clientDisconnected(clientId: clientId)
            }
        }

        // MARK: - ping

        bridge.handle("ping") { _, reply in
            reply(["pong": true], nil)
        }

        // MARK: - register (client identification, not security)

        bridge.handle("register") { [weak self] params, reply in
            let clientId = params?["clientId"] as? String ?? "unknown"
            let capabilities = params?["capabilities"] as? [String] ?? []
            let connID = params?["_connectionID"] as? String ?? ""

            self?.setClient(clientId, forConnection: connID)
            self?.log.info("[AgentBridge] Client registered: \(clientId) conn=\(connID.prefix(8)) caps=\(capabilities)")

            reply([
                "sessionToken": UUID().uuidString,
                "grantedCapabilities": capabilities
            ], nil)
        }

        // MARK: - startDictation (streaming)

        bridge.handleStreaming("startDictation") { [weak self] params, progress, reply in
            let persist = params?["persist"] as? Bool ?? true
            let connID = params?["_connectionID"] as? String ?? ""
            let clientId = self?.clientId(forConnection: connID) ?? (connID.isEmpty ? UUID().uuidString : connID)

            // Auto-register so disconnect handler can clean up
            if !connID.isEmpty, self?.clientId(forConnection: connID) == nil {
                self?.setClient(clientId, forConnection: connID)
            }

            self?.log.info("[AgentBridge] startDictation called: client=\(clientId) persist=\(persist)")

            // Send immediate acknowledgment before hopping to main actor
            progress("stateChange", ["state": "starting", "previous": "idle"])

            Task { @MainActor in
                DictationBridge.shared.startDictation(
                    clientId: clientId,
                    persist: persist,
                    progress: progress,
                    reply: reply
                )
            }
        }

        // MARK: - stopDictation

        bridge.handle("stopDictation") { [weak self] params, reply in
            let connID = params?["_connectionID"] as? String ?? ""
            let clientId = self?.clientId(forConnection: connID) ?? (connID.isEmpty ? UUID().uuidString : connID)
            Task { @MainActor in
                DictationBridge.shared.stopDictation(clientId: clientId)
                reply(["stopped": true], nil)
            }
        }

        // MARK: - cancelDictation

        bridge.handle("cancelDictation") { [weak self] params, reply in
            let connID = params?["_connectionID"] as? String ?? ""
            let clientId = self?.clientId(forConnection: connID) ?? (connID.isEmpty ? UUID().uuidString : connID)
            Task { @MainActor in
                DictationBridge.shared.cancelDictation(clientId: clientId, reply: reply)
            }
        }

        // MARK: - Black Channel Tests (DEBUG only)

        #if DEBUG
        bridge.handle("runBlackChannelTests") { _, reply in
            Task { @MainActor in
                guard let controller = TalkieAgentXPCService.shared.agentController else {
                    reply(nil, "AgentController not available")
                    return
                }
                let results = await controller.runBlackChannelTests()
                reply(["results": results], nil)
            }
        }
        #endif

        bridge.start()
        log.info("[AgentBridge] Started on ws://127.0.0.1:\(port)")
    }

    func stop() {
        bridge?.stop()
        bridge = nil
        log.info("[AgentBridge] Stopped")
    }
}
