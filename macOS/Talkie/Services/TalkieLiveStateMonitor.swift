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

    private var xpcConnection: NSXPCConnection?
    private var retryCount = 0
    private var maxRetries = 3
    private var hasLoggedUnavailable = false
    private var isConnecting = false

    private override init() {
        super.init()
        // Don't auto-connect - connect lazily when needed
    }

    /// Call this when you actually need to monitor TalkieLive state
    func startMonitoring() {
        guard xpcConnection == nil && !isConnecting else { return }

        NSLog("[Live] Checking...")

        // Check if TalkieLive is actually running first
        if !isTalkieLiveRunning() {
            NSLog("[Live] Not running (optional)")
            return
        }

        connectToXPCService()
    }

    /// Check if TalkieLive process is running
    private func isTalkieLiveRunning() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "TalkieLive"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
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

                // Only retry if we haven't exceeded max retries
                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    let delay = min(Double(self.retryCount) * 2.0, 10.0) // Exponential backoff, max 10s

                    if self.retryCount == 1 {
                        NSLog("[Live] Connection lost, retrying... (\(self.retryCount)/\(self.maxRetries))")
                    }

                    try? await Task.sleep(for: .seconds(delay))

                    // Check if service is still running before retry
                    if self.isTalkieLiveRunning() {
                        self.connectToXPCService()
                    } else {
                        // TalkieLive stopped - silently stop monitoring (it's optional)
                        self.retryCount = 0
                    }
                } else {
                    // Max retries reached - silently stop (TalkieLive is optional)
                    self.retryCount = 0
                }
            }
        }

        connection.interruptionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isConnecting = false
                // Interruption is temporary, try immediate reconnect once
                if self.retryCount == 0 {
                    try? await Task.sleep(for: .seconds(0.5))
                    if self.isTalkieLiveRunning() {
                        self.connectToXPCService()
                    }
                }
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
