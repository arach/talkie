//
//  TalkieLiveXPCService.swift
//  TalkieLive
//
//  XPC service that broadcasts TalkieLive's recording state to Talkie.
//  Also sends URL notifications for decoupled state sync.
//

import Foundation
import AppKit
import Combine
import TalkieKit

@MainActor
final class TalkieLiveXPCService: NSObject, TalkieLiveXPCServiceProtocol {
    static let shared = TalkieLiveXPCService()

    private var listener: NSXPCListener?
    private var observers: [NSXPCConnection] = []

    // Current state (updated by LiveController)
    private var currentState: String = "idle"
    private var currentElapsedTime: TimeInterval = 0

    // Track last logged state to avoid spam
    private var lastLoggedState: String = "idle"

    // Track if Talkie is connected (useful for UI indicators)
    @Published private(set) var isTalkieConnected: Bool = false
    private var lastConnectionChange: Date = Date()

    // Reference to LiveController for toggle recording
    weak var liveController: LiveController?

    // Audio level observation
    private var audioLevelCancellable: AnyCancellable?

    private override init() {
        super.init()
    }

    // MARK: - Service Lifecycle

    /// Start XPC service (fail-safe - won't crash if service fails to start)
    func startService() {
        listener = NSXPCListener(machServiceName: kTalkieLiveXPCServiceName)
        listener?.delegate = self
        listener?.resume()
        NSLog("[TalkieLiveXPC] ✓ Service started: \(kTalkieLiveXPCServiceName)")
        NSLog("[TalkieLiveXPC] ℹ️ State notifications are optional - recording will work even if no observers connect")

        // Observe audio level (throttled to 2Hz - "sign of life" indicator)
        audioLevelCancellable = AudioLevelMonitor.shared.$level
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] level in
                self?.broadcastAudioLevel(level)
            }
    }

    func stopService() {
        listener?.invalidate()
        listener = nil
        observers.removeAll()
        NSLog("[TalkieLiveXPC] Service stopped")
    }

    // MARK: - State Updates (Called by LiveController)

    /// Update state and notify observers immediately (synchronous, fail-safe)
    /// Called from MainActor so we can broadcast directly without async hops
    func updateState(_ state: String, elapsedTime: TimeInterval) {
        self.currentState = state
        self.currentElapsedTime = elapsedTime

        // Broadcast immediately to all observers (no async delay)
        broadcastStateChange(state: state, elapsedTime: elapsedTime)
    }

    /// Notify observers that a new dictation was added
    func notifyDictationAdded() {
        broadcastDictationAdded()
    }

    private func broadcastStateChange(state: String, elapsedTime: TimeInterval) {
        // Notify all connected observers immediately (XPC)
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ error in
                NSLog("[TalkieLiveXPC] ⚠️ Error sending state to observer: \(error)")
            }) as? TalkieLiveStateObserverProtocol else { continue }

            // Fire-and-forget notification
            observer.stateDidChange(state: state, elapsedTime: elapsedTime)
        }

        // Only log and send URL when state actually changes
        if state != lastLoggedState {
            NSLog("[TalkieLiveXPC] ✓ State changed to '\(state)' (broadcasting to \(observers.count) observers)")
            lastLoggedState = state

            // Send URL notification to Talkie (decoupled, no connection required)
            switch state {
            case "listening":
                TalkieNotifier.shared.recordingStarted()
            case "idle":
                TalkieNotifier.shared.recordingStopped()
            case "transcribing":
                TalkieNotifier.shared.transcribing()
            case "routing":
                TalkieNotifier.shared.routing()
            default:
                break
            }
        }
    }

    private func broadcastDictationAdded() {
        // Notify all connected observers (XPC)
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ error in
                NSLog("[TalkieLiveXPC] ⚠️ Error sending dictation notification to observer: \(error)")
            }) as? TalkieLiveStateObserverProtocol else { continue }

            observer.dictationWasAdded()
        }

        // Also send URL notification
        TalkieNotifier.shared.dictationAdded()

        NSLog("[TalkieLiveXPC] ✓ Notified \(observers.count) observers about new dictation")
    }

    private func broadcastAudioLevel(_ level: Float) {
        // Only broadcast if we have observers (skip if no Talkie connected)
        guard !observers.isEmpty else { return }

        // Fire-and-forget to all observers
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ _ in
                // Silently ignore - audio level is non-critical
            }) as? TalkieLiveStateObserverProtocol else { continue }

            observer.audioLevelDidChange(level: level)
        }
    }

    // MARK: - TalkieLiveXPCServiceProtocol

    nonisolated func getCurrentState(reply: @escaping (String, TimeInterval, Int32) -> Void) {
        Task { @MainActor in
            let pid = ProcessInfo.processInfo.processIdentifier
            reply(currentState, currentElapsedTime, pid)
        }
    }

    nonisolated func registerStateObserver(reply: @escaping (Bool, Int32) -> Void) {
        // Return success and our process ID
        let pid = ProcessInfo.processInfo.processIdentifier
        reply(true, pid)
    }

    nonisolated func unregisterStateObserver(reply: @escaping (Bool) -> Void) {
        // Remove the connection from observers
        reply(true)
    }

    nonisolated func toggleRecording(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            guard let liveController = self.liveController else {
                NSLog("[TalkieLiveXPC] ⚠️ Cannot toggle - LiveController not set")
                reply(false)
                return
            }

            // Toggle recording
            NSLog("[TalkieLiveXPC] Toggle recording requested")
            await liveController.toggleListening(interstitial: false)
            NSLog("[TalkieLiveXPC] ✓ Toggle completed")
            reply(true)
        }
    }

    func addObserverConnection(_ connection: NSXPCConnection) {
        observers.append(connection)
        updateConnectionStatus()
        NSLog("[TalkieLiveXPC] ✓ Talkie connected (total observers: \(observers.count))")
    }

    func removeObserverConnection(_ connection: NSXPCConnection) {
        observers.removeAll { $0 === connection }
        updateConnectionStatus()
        NSLog("[TalkieLiveXPC] ⚠️ Talkie disconnected (remaining observers: \(observers.count))")
    }

    private func updateConnectionStatus() {
        let wasConnected = isTalkieConnected
        isTalkieConnected = !observers.isEmpty

        if wasConnected != isTalkieConnected {
            lastConnectionChange = Date()
            if isTalkieConnected {
                NSLog("[TalkieLiveXPC] 🟢 Talkie is now connected")
            } else {
                NSLog("[TalkieLiveXPC] 🔴 Talkie disconnected")
            }
        }
    }
}

// MARK: - NSXPCListenerDelegate

extension TalkieLiveXPCService: NSXPCListenerDelegate {
    nonisolated func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure the connection
        newConnection.exportedInterface = NSXPCInterface(with: TalkieLiveXPCServiceProtocol.self)
        newConnection.exportedObject = self

        // Set up remote interface for callbacks
        newConnection.remoteObjectInterface = NSXPCInterface(with: TalkieLiveStateObserverProtocol.self)

        // Handle connection lifecycle
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            Task { @MainActor in
                guard let self, let conn = newConnection else { return }
                self.removeObserverConnection(conn)
                NSLog("[TalkieLiveXPC] Connection invalidated")
            }
        }

        newConnection.interruptionHandler = {
            NSLog("[TalkieLiveXPC] Connection interrupted")
        }

        // Add to observers
        Task { @MainActor [weak self, weak newConnection] in
            guard let self, let conn = newConnection else { return }
            self.addObserverConnection(conn)
        }

        newConnection.resume()
        NSLog("[TalkieLiveXPC] Accepted new connection")
        return true
    }
}
