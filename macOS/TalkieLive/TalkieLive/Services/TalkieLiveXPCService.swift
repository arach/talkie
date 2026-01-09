//
//  TalkieLiveXPCService.swift
//  TalkieLive
//
//  XPC service that broadcasts TalkieLive's recording state to Talkie.
//  Also sends URL notifications for decoupled state sync.
//

import Foundation
import AppKit
import ApplicationServices  // For AXIsProcessTrusted
import AVFoundation         // For AVCaptureDevice
import Combine
import TalkieKit

@MainActor
final class TalkieLiveXPCService: NSObject, TalkieLiveXPCServiceProtocol, ObservableObject {
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

    // MARK: - Ambient Mode

    /// Notify observers about an ambient voice command
    /// Called by AmbientController when a command is captured
    func notifyAmbientCommand(_ command: String, duration: TimeInterval, bufferContext: String?) {
        broadcastAmbientCommand(command: command, duration: duration, bufferContext: bufferContext)
    }

    private func broadcastAmbientCommand(command: String, duration: TimeInterval, bufferContext: String?) {
        // Notify all connected observers (XPC)
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ error in
                NSLog("[TalkieLiveXPC] ⚠️ Error sending ambient command to observer: \(error)")
            }) as? TalkieLiveStateObserverProtocol else { continue }

            observer.ambientCommandReceived(command: command, duration: duration, bufferContext: bufferContext)
        }

        // Also send URL notification for decoupled handling
        TalkieNotifier.shared.ambientCommand(command)

        NSLog("[TalkieLiveXPC] ✓ Ambient command broadcasted to \(observers.count) observers: '\(command.prefix(50))...'")
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

    nonisolated func getPermissions(reply: @escaping (Bool, Bool, Bool) -> Void) {
        Task { @MainActor in
            // Check microphone permission
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let hasMicrophone = micStatus == .authorized

            // Check accessibility permission (required for autopaste)
            let hasAccessibility = AXIsProcessTrusted()

            // Check screen recording permission
            let hasScreenRecording = checkScreenRecordingPermission()

            NSLog("[TalkieLiveXPC] Permissions: mic=\(hasMicrophone), accessibility=\(hasAccessibility), screenRecording=\(hasScreenRecording)")
            reply(hasMicrophone, hasAccessibility, hasScreenRecording)
        }
    }

    nonisolated func pasteText(_ text: String, toAppWithBundleID bundleID: String?, reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            NSLog("[TalkieLiveXPC] Paste request: \(text.count) chars to \(bundleID ?? "frontmost")")
            let success = await TextInserter.shared.insert(text, intoAppWithBundleID: bundleID)
            NSLog("[TalkieLiveXPC] Paste result: \(success ? "success" : "failed")")
            reply(success)
        }
    }

    nonisolated func appendMessage(_ text: String, sessionId: String, projectPath: String?, submit: Bool, reply: @escaping (Bool, String?) -> Void) {
        Task { @MainActor in
            NSLog("[TalkieLiveXPC] appendMessage for session: \(sessionId), projectPath: \(projectPath ?? "nil"), submit: \(submit), text: \(text.prefix(50))...")

            // Try to find terminal context
            var context: SessionContext? = nil

            // 1. Try to find by sessionId first
            context = BridgeContextMapper.shared.getContext(for: sessionId)

            // 2. If not found and we have projectPath, try matching by path
            if context == nil, let projectPath = projectPath {
                context = BridgeContextMapper.shared.getContextByProjectPath(projectPath)
            }

            // 3. If still not found, do a terminal scan and try again
            if context == nil {
                NSLog("[TalkieLiveXPC] No cached context, attempting terminal scan...")
                BridgeContextMapper.shared.refreshFromScan()

                // Try sessionId first
                context = BridgeContextMapper.shared.getContext(for: sessionId)

                // Then try projectPath
                if context == nil, let projectPath = projectPath {
                    context = BridgeContextMapper.shared.getContextByProjectPath(projectPath)
                }
            }

            // 4. Last resort: If we still have no context but found a Claude terminal,
            //    use the first Claude terminal as a fallback (likely the active one)
            if context == nil {
                let scanResult = TerminalScanner.shared.scanAllTerminals()
                if let claudeTerminal = scanResult.terminals.first(where: { $0.isClaudeSession }) {
                    NSLog("[TalkieLiveXPC] Using fallback Claude terminal: \(claudeTerminal.windowTitle) (\(claudeTerminal.bundleID))")
                    context = SessionContext(
                        app: claudeTerminal.appName,
                        bundleId: claudeTerminal.bundleID,
                        windowTitle: claudeTerminal.windowTitle,
                        pid: claudeTerminal.pid,
                        workingDirectory: claudeTerminal.workingDirectory,
                        timestamp: Date()
                    )
                }
            }

            guard let ctx = context else {
                NSLog("[TalkieLiveXPC] Could not find terminal for session: \(sessionId), project: \(projectPath ?? "nil")")
                let scanResult = TerminalScanner.shared.scanAllTerminals()
                let terminalInfo = scanResult.terminals.map { "\($0.appName): \($0.windowTitle)" }.joined(separator: ", ")
                let error = """
                    No terminal found for project '\(projectPath?.components(separatedBy: "/").last ?? sessionId)'.

                    Troubleshooting:
                    1. Open a terminal in the project directory
                    2. Start a Claude Code session (run 'claude')
                    3. Make sure the terminal window title shows the project path

                    Found terminals: \(terminalInfo.isEmpty ? "none" : terminalInfo)
                    """
                reply(false, error)
                return
            }

            NSLog("[TalkieLiveXPC] Appending to \(ctx.app) (\(ctx.bundleId)), submit=\(submit), textLen=\(text.count)")

            // Use TextInserter to append the text (and optionally press Enter)
            let success: Bool

            // Handle empty text + submit as "just press Enter" (for force submit from iOS)
            if text.isEmpty && submit {
                NSLog("[TalkieLiveXPC] Empty text with submit - pressing Enter only")
                success = await TextInserter.shared.simulateEnterInApp(bundleId: ctx.bundleId)
            } else if text.isEmpty {
                // Empty text without submit - nothing to do
                NSLog("[TalkieLiveXPC] Empty text without submit - no action")
                reply(true, nil)
                return
            } else if submit {
                // Insert text and press Enter to submit
                success = await TextInserter.shared.insertAndSubmit(
                    text,
                    intoAppWithBundleID: ctx.bundleId
                )
            } else {
                // Just insert text, no Enter
                success = await TextInserter.shared.insert(
                    text,
                    intoAppWithBundleID: ctx.bundleId,
                    replaceSelection: false
                )
            }

            if success {
                NSLog("[TalkieLiveXPC] Message appended\(submit ? " + submitted" : "") to \(ctx.app)")
                reply(true, nil)
            } else {
                NSLog("[TalkieLiveXPC] Message append failed for \(ctx.app)")
                let error = """
                    Failed to insert text into \(ctx.app).

                    Troubleshooting:
                    1. Check Accessibility permission is granted for TalkieLive
                    2. Make sure the terminal window is visible (not minimized)
                    3. The terminal may be blocked by a modal dialog
                    4. Try clicking on the terminal window first

                    Target: \(ctx.windowTitle)
                    """
                reply(false, error)
            }
        }
    }

    private func checkScreenRecordingPermission() -> Bool {
        // Screen recording permission check - try to get window info
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // If we can see window owner names, we have permission
        return windowList.contains { $0[kCGWindowOwnerName as String] != nil }
    }

    // MARK: - Screenshot Methods

    nonisolated func listClaudeWindows(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            NSLog("[TalkieLiveXPC] listClaudeWindows requested")

            if #available(macOS 14.0, *) {
                let windows = await ScreenshotService.shared.findClaudeWindows()

                let windowDicts: [[String: Any]] = windows.map { window in
                    var dict: [String: Any] = [
                        "windowID": window.windowID,
                        "pid": window.pid,
                        "appName": window.appName,
                        "isOnScreen": window.isOnScreen
                    ]
                    if let bundleId = window.bundleId { dict["bundleId"] = bundleId }
                    if let title = window.title { dict["title"] = title }
                    if let bounds = window.bounds {
                        dict["bounds"] = [
                            "x": bounds.origin.x,
                            "y": bounds.origin.y,
                            "width": bounds.width,
                            "height": bounds.height
                        ]
                    }
                    return dict
                }

                if let jsonData = try? JSONSerialization.data(withJSONObject: windowDicts) {
                    NSLog("[TalkieLiveXPC] Found \(windows.count) Claude windows")
                    reply(jsonData)
                } else {
                    reply(nil)
                }
            } else {
                NSLog("[TalkieLiveXPC] ScreenshotService requires macOS 14+")
                reply(nil)
            }
        }
    }

    nonisolated func captureWindow(windowID: UInt32, reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            NSLog("[TalkieLiveXPC] captureWindow requested: \(windowID)")

            if #available(macOS 14.0, *) {
                guard let image = await ScreenshotService.shared.captureWindow(windowID: CGWindowID(windowID)) else {
                    reply(nil, "Failed to capture window - check Screen Recording permission")
                    return
                }

                guard let jpegData = await ScreenshotService.shared.encodeAsJPEG(image, quality: 0.85) else {
                    reply(nil, "Failed to encode image")
                    return
                }

                NSLog("[TalkieLiveXPC] Captured window \(windowID): \(jpegData.count) bytes")
                reply(jpegData, nil)
            } else {
                reply(nil, "Requires macOS 14+")
            }
        }
    }

    nonisolated func captureTerminalWindows(reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            NSLog("[TalkieLiveXPC] captureTerminalWindows requested")

            if #available(macOS 14.0, *) {
                let terminals = await ScreenshotService.shared.captureTerminalWindows()

                var screenshots: [[String: Any]] = []
                for terminal in terminals {
                    if let jpegData = await ScreenshotService.shared.encodeAsJPEG(terminal.image, quality: 0.75) {
                        screenshots.append([
                            "windowID": terminal.windowID,
                            "bundleId": terminal.bundleId,
                            "title": terminal.title,
                            "imageBase64": jpegData.base64EncodedString()
                        ])
                    }
                }

                let result: [String: Any] = [
                    "screenshots": screenshots,
                    "count": screenshots.count
                ]

                if let jsonData = try? JSONSerialization.data(withJSONObject: result) {
                    NSLog("[TalkieLiveXPC] Captured \(screenshots.count) terminal windows")
                    reply(jsonData, nil)
                } else {
                    reply(nil, "Failed to encode response")
                }
            } else {
                reply(nil, "Requires macOS 14+")
            }
        }
    }

    nonisolated func hasScreenRecordingPermission(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            if #available(macOS 14.0, *) {
                let hasPermission = await ScreenshotService.shared.hasScreenRecordingPermission()
                reply(hasPermission)
            } else {
                reply(checkScreenRecordingPermission())
            }
        }
    }

    nonisolated func retranscribe(dictationId: Int64, modelId: String, reply: @escaping (String?, String?) -> Void) {
        Task { @MainActor in
            NSLog("[TalkieLiveXPC] Retranscribe requested: id=\(dictationId), model=\(modelId)")

            // 1. Fetch dictation from database
            guard let dictation = LiveDatabase.fetch(id: dictationId) else {
                NSLog("[TalkieLiveXPC] Retranscribe failed: dictation \(dictationId) not found")
                reply(nil, "Dictation not found")
                return
            }

            // 2. Get audio file path
            guard let audioFilename = dictation.audioFilename else {
                NSLog("[TalkieLiveXPC] Retranscribe failed: no audio file for dictation \(dictationId)")
                reply(nil, "No audio file available for this dictation")
                return
            }

            let audioPath = AudioStorage.audioDirectory.appendingPathComponent(audioFilename).path

            guard FileManager.default.fileExists(atPath: audioPath) else {
                NSLog("[TalkieLiveXPC] Retranscribe failed: audio file not found at \(audioPath)")
                reply(nil, "Audio file not found")
                return
            }

            // 3. Transcribe via Engine
            do {
                let newText = try await EngineClient.shared.transcribe(
                    audioPath: audioPath,
                    modelId: modelId,
                    priority: .userInitiated  // User explicitly requested retranscription
                )

                // 4. Update database
                LiveDatabase.updateText(id: dictationId, text: newText, modelId: modelId)

                // 5. Notify observers that dictation was updated
                self.broadcastDictationAdded()

                NSLog("[TalkieLiveXPC] Retranscribe succeeded: \(newText.prefix(50))...")
                reply(newText, nil)
            } catch {
                NSLog("[TalkieLiveXPC] Retranscribe failed: \(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
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
