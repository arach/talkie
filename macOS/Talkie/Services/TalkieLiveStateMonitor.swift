//
//  TalkieLiveStateMonitor.swift
//  Talkie
//
//  Monitors TalkieLive's recording state via XPC service for real-time sync.
//  Allows Talkie to display accurate recording state in StatusBar.
//

import Foundation
import Combine

@MainActor
final class TalkieLiveStateMonitor: NSObject, ObservableObject, TalkieLiveStateObserverProtocol {
    static let shared = TalkieLiveStateMonitor()

    @Published var state: LiveState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var isRecording: Bool = false
    @Published var processId: Int32? = nil
    @Published var isRunning: Bool = false

    private var xpcConnection: NSXPCConnection?
    private var retryCount = 0
    private var maxRetries = 3
    private var hasLoggedUnavailable = false
    private var isConnecting = false

    private override init() {
        super.init()
        // Check initial running state immediately to prevent UI flicker
        _ = isTalkieLiveRunning()
        // Don't auto-connect - connect lazily when needed
    }

    /// Call this when you actually need to monitor TalkieLive state
    func startMonitoring() {
        guard xpcConnection == nil && !isConnecting else { return }

        // Only check if we haven't determined the state yet (isRunning is still false from init)
        // After init, we trust the XPC connection state instead of repeatedly calling pgrep
        if !isRunning {
            // Check if TalkieLive is actually running first
            if !isTalkieLiveRunning() {
                // Not running and that's OK (TalkieLive is optional)
                return
            }
        }

        connectToXPCService()
    }

    /// Check if TalkieLive process is running and update processId
    private func isTalkieLiveRunning() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "TalkieLive"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let isRunning = task.terminationStatus == 0

            if isRunning {
                // Try to read the PID from output, but don't fail if we can't
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let pid = Int32(output) {
                    self.processId = pid
                } else {
                    // Couldn't parse PID, but process is still running
                    self.processId = nil
                }
                self.isRunning = true
            } else {
                self.processId = nil
                self.isRunning = false
            }

            return isRunning
        } catch {
            self.processId = nil
            self.isRunning = false
            return false
        }
    }

    // MARK: - XPC Connection

    private func connectToXPCService() {
        guard !isConnecting else { return }
        isConnecting = true

        let connection = NSXPCConnection(machServiceName: kTalkieLiveXPCServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: TalkieLiveXPCServiceProtocol.self)

        // Set up interface for receiving callbacks
        connection.exportedInterface = NSXPCInterface(with: TalkieLiveStateObserverProtocol.self)
        connection.exportedObject = self

        connection.invalidationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.xpcConnection = nil
                self.isConnecting = false

                // Keep isRunning/processId based on actual process state
                // XPC is just for state updates, not for determining if Live is running
                _ = self.isTalkieLiveRunning()

                NSLog("[Live] Connection lost (not retrying - TalkieLive is optional)")
                self.retryCount = 0
            }
        }

        connection.interruptionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isConnecting = false
                NSLog("[Live] Connection interrupted")
            }
        }

        connection.resume()
        self.xpcConnection = connection
        isConnecting = false

        // Register as observer
        registerAsObserver()

        // Get current state immediately
        getCurrentState()

        NSLog("[Live] ✅ Connected")
        hasLoggedUnavailable = false
        retryCount = 0
    }

    private func registerAsObserver() {
        guard let service = xpcConnection?.remoteObjectProxyWithErrorHandler({ error in
            // Only log first error
            if self.retryCount == 0 {
                NSLog("[Live] Error: \(error.localizedDescription)")
            }
        }) as? TalkieLiveXPCServiceProtocol else { return }

        service.registerStateObserver { success in
            if success {
                NSLog("[Live] Observer registered")
            }
        }
    }

    private func getCurrentState() {
        guard let service = xpcConnection?.remoteObjectProxyWithErrorHandler({ _ in
            // Silently fail - error already logged in registerAsObserver
        }) as? TalkieLiveXPCServiceProtocol else { return }

        service.getCurrentState { [weak self] stateString, elapsed in
            Task { @MainActor [weak self] in
                self?.updateState(stateString, elapsed)
            }
        }
    }

    /// Toggle recording in TalkieLive (start if idle, stop if listening)
    func toggleRecording() {
        // Ensure connection exists
        if xpcConnection == nil {
            startMonitoring()
            // Wait a moment for connection to establish
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                self.performToggle()
            }
            return
        }

        performToggle()
    }

    private func performToggle() {
        guard let service = xpcConnection?.remoteObjectProxyWithErrorHandler({ error in
            NSLog("[Live] Error toggling recording: \(error.localizedDescription)")
        }) as? TalkieLiveXPCServiceProtocol else {
            NSLog("[Live] Cannot toggle - service not available")
            return
        }

        service.toggleRecording { success in
            if success {
                NSLog("[Live] ✓ Toggle recording request sent")
            } else {
                NSLog("[Live] ⚠️ Toggle recording failed")
            }
        }
    }

    // MARK: - TalkieLiveStateObserverProtocol

    nonisolated func stateDidChange(state stateString: String, elapsedTime elapsed: TimeInterval) {
        Task { @MainActor [weak self] in
            self?.updateState(stateString, elapsed)
        }
    }

    nonisolated func utteranceWasAdded() {
        Task { @MainActor in
            // Notify UtteranceStore to refresh
            UtteranceStore.shared.refresh()
            NSLog("[Live] 🔄 Utterance notification received, refreshed store")
        }
    }

    private func updateState(_ stateString: String, _ elapsed: TimeInterval) {
        let newState = LiveState(rawValue: stateString) ?? .idle

        if newState != state {
            state = newState
            isRecording = (newState == .listening || newState == .transcribing)
            NSLog("[Live] State: \(stateString)")
        }

        elapsedTime = elapsed
    }

    // MARK: - Cleanup

    deinit {
        xpcConnection?.invalidate()
    }

    // MARK: - Helper Methods

    /// Check if TalkieLive is actively recording
    var isActivelyRecording: Bool {
        state == .listening || state == .transcribing
    }

    /// Get display string for current state
    var stateDisplayString: String {
        switch state {
        case .idle: return "Ready"
        case .listening: return "Recording"
        case .transcribing: return "Processing"
        case .routing: return "Routing"
        }
    }
}
