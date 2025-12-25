//
//  TalkieLiveStateMonitor.swift
//  Talkie
//
//  Monitors TalkieLive's recording state for real-time sync.
//  Supports both URL-based notifications (preferred) and XPC (legacy).
//
//  URL notifications are simpler and avoid XPC complexity:
//    talkie://recording/started  →  updateFromNotification(.listening)
//    talkie://transcribing       →  updateFromNotification(.transcribing)
//

import Foundation
import Combine
import TalkieKit
import Observation

@MainActor
@Observable
final class TalkieLiveStateMonitor: NSObject, TalkieLiveStateObserverProtocol {
    static let shared = TalkieLiveStateMonitor()

    var state: LiveState = .idle
    var elapsedTime: TimeInterval = 0
    var isRecording: Bool = false
    var processId: Int32? = nil
    var audioLevel: Float = 0

    // MARK: - Connection State (separated to avoid conflicts)

    /// True if XPC connection to TalkieLive is active
    private(set) var isXPCConnected: Bool = false

    /// True if TalkieLive process is running (detected via bundle ID)
    private(set) var isProcessDetected: Bool = false

    /// True if TalkieLive is available (either XPC connected OR process detected)
    /// This is the primary property views should observe
    var isRunning: Bool {
        isXPCConnected || isProcessDetected
    }

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

        // Observe XPC connection state separately from process detection
        xpcManager.$connectionInfo
            .map(\.isConnected)
            .sink { [weak self] isConnected in
                self?.isXPCConnected = isConnected
                if isConnected {
                    NSLog("[Live] XPC connected")
                }
            }
            .store(in: &cancellables)

        // Don't auto-connect - connect lazily when needed
    }

    /// Call this when you actually need to monitor TalkieLive state
    func startMonitoring() {
        guard !xpcManager.isConnected else { return }

        // First try to get PID from running app (fallback if XPC not available)
        refreshProcessId()

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
        // Use DispatchQueue for lower latency than Task scheduling
        DispatchQueue.main.async { [weak self] in
            self?.updateState(stateString, elapsed)
        }
    }

    nonisolated func utteranceWasAdded() {
        DispatchQueue.main.async {
            // Notify DictationStore to refresh
            DictationStore.shared.refresh()
            NSLog("[Live] 🔄 Utterance notification received, refreshed store")
        }
    }

    nonisolated func audioLevelDidChange(level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
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

    /// Refresh process ID by checking for running TalkieLive app
    /// This provides a fallback when XPC isn't available yet
    func refreshProcessId() {
        // Try to find running TalkieLive app for current environment
        let bundleId = TalkieEnvironment.current.liveBundleId
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)

        if let app = apps.first {
            processId = app.processIdentifier
            isProcessDetected = true
            NSLog("[Live] Found running process - PID: \(app.processIdentifier) (bundle: \(bundleId))")
        } else {
            // Only clear if we don't have XPC connection (which provides its own PID)
            if !isXPCConnected {
                isProcessDetected = false
            }
            NSLog("[Live] No process found for bundle: \(bundleId)")
        }
    }

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

    // MARK: - URL Notification Updates (preferred over XPC)

    /// Update state from URL notification (e.g., talkie://recording/started)
    /// This is the preferred method - simpler than XPC, no connection management.
    func updateFromNotification(state newState: LiveState, elapsedTime elapsed: TimeInterval = 0) {
        // Mark process as detected since we're receiving notifications
        isProcessDetected = true

        if newState != state {
            state = newState
            isRecording = (newState == .listening || newState == .transcribing)
            NSLog("[Live] State (via notification): \(newState.rawValue)")
        }

        elapsedTime = elapsed
    }

}
