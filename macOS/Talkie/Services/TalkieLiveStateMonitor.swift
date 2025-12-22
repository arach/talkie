//
//  TalkieLiveStateMonitor.swift
//  Talkie
//
//  Monitors TalkieLive's recording state via XPC service for real-time sync.
//  Allows Talkie to display accurate recording state in StatusBar.
//

import Foundation
import Combine
import TalkieKit

@MainActor
@Observable
final class TalkieLiveStateMonitor: NSObject, TalkieLiveStateObserverProtocol {
    static let shared = TalkieLiveStateMonitor()

    var state: LiveState = .idle
    var elapsedTime: TimeInterval = 0
    var isRecording: Bool = false
    var processId: Int32? = nil
    var isRunning: Bool = false

    // XPC service manager with environment-aware connection
    private let xpcManager: XPCServiceManager<TalkieLiveXPCServiceProtocol>
    private var cancellables = Set<AnyCancellable>()

    /// Connected TalkieLive environment (from XPC connection)
    var connectedMode: TalkieEnvironment? {
        xpcManager.connectedMode
    }

    private var hasLoggedUnavailable = false

    private override init() {
        // Initialize XPC manager with environment-aware service names
        self.xpcManager = XPCServiceManager<TalkieLiveXPCServiceProtocol>(
            serviceNameProvider: { env in env.liveXPCService },
            interfaceProvider: {
                NSXPCInterface(with: TalkieLiveXPCServiceProtocol.self)
            },
            exportedInterface: NSXPCInterface(with: TalkieLiveStateObserverProtocol.self),
            exportedObject: nil  // Will be set to self after super.init
        )

        super.init()

        // Now we can set self as the exported object for receiving callbacks
        xpcManager.setExportedObject(self)

        // Observe XPC connection state and update isRunning
        xpcManager.$connectionInfo
            .map(\.isConnected)
            .sink { [weak self] isConnected in
                self?.isRunning = isConnected
            }
            .store(in: &cancellables)

        // Don't auto-connect - connect lazily when needed
    }

    /// Call this when you actually need to monitor TalkieLive state
    func startMonitoring() {
        guard !xpcManager.isConnected else { return }

        Task {
            await xpcManager.connect()

            // After connection, register as observer and get current state
            // Both methods will set our processId via XPC reply
            if xpcManager.isConnected {
                registerAsObserver()
                getCurrentState()
                NSLog("[Live] ✅ Connected to \(xpcManager.connectedMode?.displayName ?? "unknown")")
            }
        }
    }

    // MARK: - XPC Communication

    private func registerAsObserver() {
        guard let service = xpcManager.remoteObjectProxy(errorHandler: { error in
            NSLog("[Live] Error registering observer: \(error.localizedDescription)")
        }) else { return }

        service.registerStateObserver { [weak self] success, pid in
            Task { @MainActor [weak self] in
                if success {
                    self?.processId = pid
                    NSLog("[Live] Observer registered (PID: \(pid))")
                }
            }
        }
    }

    private func getCurrentState() {
        guard let service = xpcManager.remoteObjectProxy(errorHandler: { _ in
            // Silently fail - error already logged in registerAsObserver
        }) else { return }

        service.getCurrentState { [weak self] stateString, elapsed, pid in
            Task { @MainActor [weak self] in
                self?.processId = pid
                self?.updateState(stateString, elapsed)
            }
        }
    }

    /// Toggle recording in TalkieLive (start if idle, stop if listening)
    func toggleRecording() {
        // Ensure connection exists
        if !xpcManager.isConnected {
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
        guard let service = xpcManager.remoteObjectProxy(errorHandler: { error in
            NSLog("[Live] Error toggling recording: \(error.localizedDescription)")
        }) else {
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
            // Notify DictationStore to refresh
            DictationStore.shared.refresh()
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
        xpcManager.disconnect()
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
