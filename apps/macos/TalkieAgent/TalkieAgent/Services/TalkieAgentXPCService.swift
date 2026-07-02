//
//  TalkieAgentXPCService.swift
//  TalkieAgent
//
//  XPC service that broadcasts TalkieAgent's recording state to Talkie.
//  Also sends URL notifications for decoupled state sync.
//

import Foundation
import AppKit
import ApplicationServices  // For AXIsProcessTrusted
import AVFoundation         // For AVCaptureDevice
import Combine
import IOKit.hid            // For IOHIDCheckAccess (Input Monitoring)
import TalkieKit

private let xpcLog = Log(.xpc)

@MainActor
final class TalkieAgentXPCService: NSObject, TalkieAgentXPCServiceProtocol, ObservableObject {
    static let shared = TalkieAgentXPCService()

    private var listener: NSXPCListener?
    private var observers: [NSXPCConnection] = []

    // Current state (updated by AgentController)
    private var currentState: String = "idle"
    private var currentElapsedTime: TimeInterval = 0

    // Track last logged state to avoid spam
    private var lastLoggedState: String = "idle"

    // Track if Talkie is connected (useful for UI indicators)
    @Published private(set) var isTalkieConnected: Bool = false
    private var lastConnectionChange: Date = Date()

    // Reference to AgentController for toggle recording
    weak var agentController: AgentController?

    // Audio level observation
    private var audioLevelCancellable: AnyCancellable?
    private var hotStateLevelCancellable: AnyCancellable?

    // Memory-mapped hot state for zero-latency notch UI
    private var hotStateWriter: NotchHotStateWriter?

    // Ephemeral capture sessions (for TalkieHeadless/extensions)
    private var ephemeralSessions: [String: EphemeralCaptureSession] = [:]

    private let embeddedEngine = EmbeddedEngineCoordinator.shared

    private override init() {
        super.init()
    }

    // MARK: - Ephemeral Capture Support

    /// Holds state for an ephemeral capture session
    /// Updated to use UnifiedAudioCapture for consistency with main capture path
    private class EphemeralCaptureSession {
        let id: String
        let capture: UnifiedAudioCapture
        var captureSession: CaptureSession?
        var audioPath: String?
        var error: String?
        var isComplete = false

        init(id: String, capture: UnifiedAudioCapture) {
            self.id = id
            self.capture = capture
        }
    }

    // MARK: - Service Lifecycle

    /// Start XPC service (fail-safe - won't crash if service fails to start)
    func startService() {
        listener = NSXPCListener(machServiceName: kTalkieAgentXPCServiceName)
        listener?.delegate = self
        listener?.resume()
        AgentConsole.critical("[TalkieAgentXPC] ✓ Service started: \(kTalkieAgentXPCServiceName)")
        AgentConsole.critical("[TalkieAgentXPC] ℹ️ State notifications are optional - recording will work even if no observers connect")

        // Observe audio level (throttled to 2Hz - "sign of life" indicator)
        audioLevelCancellable = AudioLevelMonitor.shared.$level
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] level in
                self?.broadcastAudioLevel(level)
            }

        // Hot state: memory-mapped file for zero-latency notch UI
        hotStateWriter = NotchHotStateWriter()
        if hotStateWriter?.isActive == true {
            // Write audio level at ~60Hz (every 16ms) — reader samples at display rate
            hotStateLevelCancellable = AudioLevelMonitor.shared.$level
                .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] level in
                    self?.hotStateWriter?.writeAudioLevel(level)
                }
        }
    }

    func stopService() {
        listener?.invalidate()
        listener = nil
        observers.removeAll()
        AgentConsole.critical("[TalkieAgentXPC] Service stopped")
    }

    // MARK: - State Updates (Called by AgentController)

    /// Update state and notify observers immediately (synchronous, fail-safe)
    /// Called from MainActor so we can broadcast directly without async hops
    func updateState(_ state: String, elapsedTime: TimeInterval) {
        self.currentState = state
        self.currentElapsedTime = elapsedTime

        // Write to hot state immediately (zero-latency path for notch UI)
        let phase = NotchHotState.phaseValue(for: LiveState(rawValue: state) ?? .idle)
        hotStateWriter?.writePhase(phase, elapsedTime: Float(elapsedTime))

        // Broadcast immediately to all observers (no async delay)
        broadcastStateChange(state: state, elapsedTime: elapsedTime)
    }

    /// Notify observers that a new dictation was added
    func notifyDictationAdded() {
        broadcastDictationAdded()
    }

    /// Legacy paste callback retained for older observers. TalkieAgent no longer asks Talkie to mutate tray items.
    func notifyDictationPasted(recordingId: UUID) {
        let idString = recordingId.uuidString
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ error in
                AgentConsole.critical("[TalkieAgentXPC] Error sending dictationWasPasted: \(error)")
            }) as? TalkieAgentStateObserverProtocol else { continue }
            observer.dictationWasPasted(recordingId: idString)
        }
        AgentConsole.critical("[TalkieAgentXPC] ✓ Notified \(observers.count) observers about dictation paste (recording: \(idString.prefix(8)))")
    }

    private func broadcastStateChange(state: String, elapsedTime: TimeInterval) {
        // Notify all connected observers immediately (XPC)
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ error in
                AgentConsole.critical("[TalkieAgentXPC] ⚠️ Error sending state to observer: \(error)")
            }) as? TalkieAgentStateObserverProtocol else { continue }

            // Fire-and-forget notification
            observer.stateDidChange(state: state, elapsedTime: elapsedTime)
        }

        // Only log and send URL when state actually changes
        if state != lastLoggedState {
            AgentConsole.critical("[TalkieAgentXPC] ✓ State changed to '\(state)' (broadcasting to \(observers.count) observers)")
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
                AgentConsole.critical("[TalkieAgentXPC] ⚠️ Error sending dictation notification to observer: \(error)")
            }) as? TalkieAgentStateObserverProtocol else { continue }

            observer.dictationWasAdded()
        }

        // Also send URL notification
        TalkieNotifier.shared.dictationAdded()

        AgentConsole.critical("[TalkieAgentXPC] ✓ Notified \(observers.count) observers about new dictation")
    }

    private func broadcastAudioLevel(_ level: Float) {
        // Only broadcast if we have observers (skip if no Talkie connected)
        guard !observers.isEmpty else { return }

        // Fire-and-forget to all observers
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ _ in
                // Silently ignore - audio level is non-critical
            }) as? TalkieAgentStateObserverProtocol else { continue }

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
                AgentConsole.critical("[TalkieAgentXPC] ⚠️ Error sending ambient command to observer: \(error)")
            }) as? TalkieAgentStateObserverProtocol else { continue }

            observer.ambientCommandReceived(command: command, duration: duration, bufferContext: bufferContext)
        }

        // Also send URL notification for decoupled handling
        TalkieNotifier.shared.ambientCommand(command)

        AgentConsole.critical("[TalkieAgentXPC] ✓ Ambient command broadcasted to \(observers.count) observers: '\(command.prefix(50))...'")
    }

    // MARK: - Voice Navigation

    /// Notify observers about a voice navigation intent
    /// Called by VoiceNavigationHandler when an intent is recognized
    func notifyVoiceNavigation(intent: String, confidence: Float, rawText: String) {
        broadcastVoiceNavigation(intent: intent, confidence: confidence, rawText: rawText)
    }

    private func broadcastVoiceNavigation(intent: String, confidence: Float, rawText: String) {
        // Notify all connected observers (XPC)
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ error in
                AgentConsole.critical("[TalkieAgentXPC] ⚠️ Error sending voice navigation to observer: \(error)")
            }) as? TalkieAgentStateObserverProtocol else { continue }

            observer.voiceNavigationReceived(intent: intent, confidence: confidence, rawText: rawText)
        }

        AgentConsole.critical("[TalkieAgentXPC] ✓ Voice navigation broadcasted: \(intent) (confidence: \(String(format: "%.0f%%", confidence * 100)))")
    }

    // MARK: - TalkieAgentXPCServiceProtocol

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
            guard let agentController = self.agentController else {
                AgentConsole.critical("[TalkieAgentXPC] ⚠️ Cannot toggle - AgentController not set")
                reply(false)
                return
            }

            // Toggle recording
            AgentConsole.critical("[TalkieAgentXPC] Toggle recording requested")
            await agentController.toggleListening(interstitial: false)
            AgentConsole.critical("[TalkieAgentXPC] ✓ Toggle completed")
            reply(true)
        }
    }

    nonisolated func getPermissions(reply: @escaping (Bool, Bool, Bool) -> Void) {
        Task { @MainActor in
            // When embedded as a Login Item inside Talkie.app, mic permission belongs to
            // the parent app — no separate Agent entry appears in System Settings.
            // Only check independently when running standalone (dev builds).
            let hasMicrophone = Self.isEmbeddedHelper || MicrophonePermission.isGranted

            // Check accessibility permission (required for autopaste).
            // Using preflight() keeps AccessibilityCache in sync with the XPC result,
            // so TalkieAgent's internal state is never stale after a revocation.
            let hasAccessibility = AccessibilityCache.shared.preflight()

            // Check screen recording permission
            let hasScreenRecording = checkScreenRecordingPermission()

            AgentConsole.critical("[TalkieAgentXPC] Permissions: mic=\(hasMicrophone), accessibility=\(hasAccessibility), screenRecording=\(hasScreenRecording)")
            reply(hasMicrophone, hasAccessibility, hasScreenRecording)
        }
    }

    /// True when running as an embedded Login Item inside another .app bundle (prod).
    /// False when launched standalone (dev).
    private static let isEmbeddedHelper: Bool = {
        let components = Bundle.main.bundlePath.components(separatedBy: "/")
        return components.filter { $0.hasSuffix(".app") }.count > 1
    }()

    nonisolated func requestMicrophonePermission(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            xpcLog.info(
                "Microphone permission request received",
                detail: "bundle=\(Bundle.main.bundleIdentifier ?? "unknown"), executable=\(Bundle.main.executableURL?.path ?? "unknown")"
            )
            let granted = await MicrophonePermission.request()
            AgentConsole.critical("[TalkieAgentXPC] Microphone permission request result: \(granted)")
            reply(granted)
        }
    }

    nonisolated func requestAccessibilityPermission(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            xpcLog.info(
                "Accessibility permission request received",
                detail: "bundle=\(Bundle.main.bundleIdentifier ?? "unknown"), executable=\(Bundle.main.executableURL?.path ?? "unknown")"
            )

            let refreshed = AccessibilityCache.shared.preflight()

            if !refreshed {
                PermissionManager.shared.requestAccessibility()
            }

            AgentConsole.critical("[TalkieAgentXPC] Accessibility permission request result: \(refreshed)")
            reply(refreshed)
        }
    }

    nonisolated func requestScreenRecordingPermission(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let granted = await ScreenshotService.shared.requestPermission()
            AgentConsole.critical("[TalkieAgentXPC] Screen recording permission request result: \(granted)")
            reply(granted)
        }
    }

    nonisolated func getInputMonitoringPermission(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            // IOHIDCheckAccess returns kIOHIDAccessTypeGranted (0) when allowed.
            let granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            AgentConsole.critical("[TalkieAgentXPC] Input Monitoring permission: \(granted)")
            reply(granted)
        }
    }

    nonisolated func pasteText(_ text: String, toAppWithBundleID bundleID: String?, reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            AgentConsole.critical("[TalkieAgentXPC] Paste request: \(text.count) chars to \(bundleID ?? "frontmost")")
            let success = await TextInserter.shared.insert(text, intoAppWithBundleID: bundleID)
            AgentConsole.critical("[TalkieAgentXPC] Paste result: \(success ? "success" : "failed")")
            reply(success)
        }
    }

    nonisolated func appendMessage(_ text: String, sessionId: String, projectPath: String?, submit: Bool, reply: @escaping (Bool, String?) -> Void) {
        Task { @MainActor in
            AgentConsole.critical("[TalkieAgentXPC] appendMessage for session: \(sessionId), projectPath: \(projectPath ?? "nil"), submit: \(submit), text: \(text.prefix(50))...")

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
                AgentConsole.critical("[TalkieAgentXPC] No cached context, attempting terminal scan...")
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
                    AgentConsole.critical("[TalkieAgentXPC] Using fallback Claude terminal: \(claudeTerminal.windowTitle) (\(claudeTerminal.bundleID))")
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
                AgentConsole.critical("[TalkieAgentXPC] Could not find terminal for session: \(sessionId), project: \(projectPath ?? "nil")")
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

            AgentConsole.critical("[TalkieAgentXPC] Appending to \(ctx.app) (\(ctx.bundleId)), submit=\(submit), textLen=\(text.count)")

            // Use TextInserter to append the text (and optionally press Enter)
            let success: Bool

            // Handle empty text + submit as "just press Enter" (for force submit from iOS)
            if text.isEmpty && submit {
                AgentConsole.critical("[TalkieAgentXPC] Empty text with submit - pressing Enter only")
                success = await TextInserter.shared.simulateEnterInApp(bundleId: ctx.bundleId)
            } else if text.isEmpty {
                // Empty text without submit - nothing to do
                AgentConsole.critical("[TalkieAgentXPC] Empty text without submit - no action")
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
                AgentConsole.critical("[TalkieAgentXPC] Message appended\(submit ? " + submitted" : "") to \(ctx.app)")
                reply(true, nil)
            } else {
                AgentConsole.critical("[TalkieAgentXPC] Message append failed for \(ctx.app)")
                let error = """
                    Failed to insert text into \(ctx.app).

                    Troubleshooting:
                    1. Check Accessibility permission is granted for TalkieAgent
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
            AgentConsole.critical("[TalkieAgentXPC] listClaudeWindows requested")

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
                    AgentConsole.critical("[TalkieAgentXPC] Found \(windows.count) Claude windows")
                    reply(jsonData)
                } else {
                    reply(nil)
                }
            } else {
                AgentConsole.critical("[TalkieAgentXPC] ScreenshotService requires macOS 14+")
                reply(nil)
            }
        }
    }

    nonisolated func captureWindow(windowID: UInt32, reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            AgentConsole.critical("[TalkieAgentXPC] captureWindow requested: \(windowID)")

            if #available(macOS 14.0, *) {
                guard let image = await ScreenshotService.shared.captureWindow(windowID: CGWindowID(windowID)) else {
                    reply(nil, "Failed to capture window - check Screen Recording permission")
                    return
                }

                guard let jpegData = await ScreenshotService.shared.encodeAsJPEG(image, quality: 0.85) else {
                    reply(nil, "Failed to encode image")
                    return
                }

                AgentConsole.critical("[TalkieAgentXPC] Captured window \(windowID): \(jpegData.count) bytes")
                reply(jpegData, nil)
            } else {
                reply(nil, "Requires macOS 14+")
            }
        }
    }

    nonisolated func captureMainDisplay(maxDimension: UInt32, quality: Double, reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            AgentConsole.critical("[TalkieAgentXPC] captureMainDisplay requested: maxDimension=\(maxDimension) quality=\(quality)")

            if #available(macOS 14.0, *) {
                let requestedDimension = maxDimension > 0 ? Int(maxDimension) : nil
                let requestedQuality = min(max(CGFloat(quality), 0.1), 1.0)

                guard let image = await ScreenshotService.shared.captureMainDisplay(maxDimension: requestedDimension) else {
                    reply(nil, "Failed to capture display - check Screen Recording permission")
                    return
                }

                guard let jpegData = await ScreenshotService.shared.encodeAsJPEG(image, quality: requestedQuality) else {
                    reply(nil, "Failed to encode display image")
                    return
                }

                AgentConsole.critical("[TalkieAgentXPC] Captured main display: \(jpegData.count) bytes")
                reply(jpegData, nil)
            } else {
                reply(nil, "Requires macOS 14+")
            }
        }
    }

    nonisolated func captureTerminalWindows(reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            AgentConsole.critical("[TalkieAgentXPC] captureTerminalWindows requested")

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
                    AgentConsole.critical("[TalkieAgentXPC] Captured \(screenshots.count) terminal windows")
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

    nonisolated func retranscribe(dictationId: String, modelId: String, reply: @escaping (String?, String?) -> Void) {
        Task { @MainActor in
            AgentConsole.critical("[TalkieAgentXPC] Retranscribe requested: id=\(dictationId), model=\(modelId)")

            // Parse UUID from string
            guard let uuid = UUID(uuidString: dictationId) else {
                AgentConsole.critical("[TalkieAgentXPC] Retranscribe failed: invalid UUID \(dictationId)")
                reply(nil, "Invalid dictation ID")
                return
            }

            // 1. Fetch dictation from database
            guard let dictation = UnifiedDatabase.fetch(id: uuid) else {
                AgentConsole.critical("[TalkieAgentXPC] Retranscribe failed: dictation \(dictationId) not found")
                reply(nil, "Dictation not found")
                return
            }

            // 2. Get audio file path
            guard let audioFilename = dictation.audioFilename else {
                AgentConsole.critical("[TalkieAgentXPC] Retranscribe failed: no audio file for dictation \(dictationId)")
                reply(nil, "No audio file available for this dictation")
                return
            }

            let audioPath = AudioStorage.audioDirectory.appendingPathComponent(audioFilename).path

            guard FileManager.default.fileExists(atPath: audioPath) else {
                AgentConsole.critical("[TalkieAgentXPC] Retranscribe failed: audio file not found at \(audioPath)")
                reply(nil, "Audio file not found")
                return
            }

            // 3. Transcribe via embedded engine
            do {
                let newText = try await self.embeddedEngine.transcribe(
                    audioPath: audioPath,
                    modelId: modelId,
                    priority: .userInitiated  // User explicitly requested retranscription
                )

                // 4. Update database
                UnifiedDatabase.updateTranscription(id: uuid, text: newText, model: modelId)

                // 5. Notify observers that dictation was updated
                self.broadcastDictationAdded()

                AgentConsole.critical("[TalkieAgentXPC] Retranscribe succeeded: \(newText.prefix(50))...")
                reply(newText, nil)
            } catch {
                AgentConsole.critical("[TalkieAgentXPC] Retranscribe failed: \(error.localizedDescription)")
                reply(nil, error.localizedDescription)
            }
        }
    }

    // MARK: - Embedded Engine

    nonisolated func ping(reply: @escaping (Bool) -> Void) {
        // Keep the XPC health probe independent from embedded-engine readiness.
        // Talkie uses this during connection verification, so it must respond
        // immediately even if the engine is still warming up or recovering.
        reply(true)
    }

    nonisolated func getStatus(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            let status = await self.embeddedEngine.statusSnapshot()
            reply(try? JSONEncoder().encode(status))
        }
    }

    nonisolated func transcribe(audioPath: String, modelId: String, externalRefId: String?, priority: TranscriptionPriority, postProcess: PostProcessOption, reply: @escaping (String?, String?) -> Void) {
        Task { @MainActor in
            do {
                let transcript = try await self.embeddedEngine.transcribe(
                    audioPath: audioPath,
                    modelId: modelId,
                    externalRefId: externalRefId,
                    priority: priority,
                    postProcess: postProcess
                )
                reply(transcript, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    nonisolated func transcribeWithTimings(audioPath: String, modelId: String, externalRefId: String?, priority: TranscriptionPriority, postProcess: PostProcessOption, reply: @escaping (String?, Data?, String?) -> Void) {
        Task { @MainActor in
            do {
                let result = try await self.embeddedEngine.transcribeWithTimings(
                    audioPath: audioPath,
                    modelId: modelId,
                    externalRefId: externalRefId,
                    priority: priority,
                    postProcess: postProcess
                )
                reply(result.text, result.timedTranscription?.toData(), nil)
            } catch {
                reply(nil, nil, error.localizedDescription)
            }
        }
    }

    nonisolated func preloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                try await self.embeddedEngine.preloadModel(modelId)
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    nonisolated func unloadModel(reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.embeddedEngine.unloadModel()
            reply()
        }
    }

    nonisolated func downloadModel(_ modelId: String, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                try await self.embeddedEngine.downloadModel(modelId)
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    nonisolated func getDownloadProgress(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            let progress = await self.embeddedEngine.downloadProgressSnapshot()
            reply(try? progress.map { try JSONEncoder().encode($0) })
        }
    }

    nonisolated func cancelDownload(reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.embeddedEngine.cancelDownload()
            reply()
        }
    }

    nonisolated func getAvailableModels(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            let models = await self.embeddedEngine.availableModelsSnapshot()
            reply(try? JSONEncoder().encode(models))
        }
    }

    nonisolated func updateDictionary(entriesJSON: Data, reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                try await self.embeddedEngine.updateDictionary(entriesJSON: entriesJSON)
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    nonisolated func setDictionaryEnabled(_ enabled: Bool, reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.embeddedEngine.setDictionaryEnabled(enabled)
            reply()
        }
    }

    nonisolated func setSymbolicMappingEnabled(_ enabled: Bool, reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.embeddedEngine.setSymbolicMappingEnabled(enabled)
            reply()
        }
    }

    nonisolated func setFillerRemovalEnabled(_ enabled: Bool, reply: @escaping () -> Void) {
        Task { @MainActor in
            await self.embeddedEngine.setFillerRemovalEnabled(enabled)
            reply()
        }
    }

    nonisolated func reloadSymbolicMapping(reply: @escaping (String?) -> Void) {
        Task { @MainActor in
            do {
                try await self.embeddedEngine.reloadSymbolicMapping()
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    nonisolated func startStreamingASR(_ reply: @escaping (String?, String?) -> Void) {
        Task { @MainActor in
            do {
                let sessionId = try await self.embeddedEngine.startStreamingASR()
                reply(sessionId, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    nonisolated func feedStreamingASR(sessionId: String, audio: Data, _ reply: @escaping (Data?, String?) -> Void) {
        Task { @MainActor in
            do {
                let events = try await self.embeddedEngine.feedStreamingASR(sessionId: sessionId, audio: audio)
                if let events {
                    let data = try JSONEncoder().encode(events)
                    reply(data, nil)
                } else {
                    reply(nil, nil)
                }
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    nonisolated func stopStreamingASR(sessionId: String, _ reply: @escaping (String?, String?) -> Void) {
        Task { @MainActor in
            do {
                let transcript = try await self.embeddedEngine.stopStreamingASR(sessionId: sessionId)
                reply(transcript, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    // MARK: - Ephemeral Capture (for TalkieHeadless/Extensions)

    nonisolated func startEphemeralCapture(reply: @escaping (String?, String?) -> Void) {
        Task { @MainActor in
            // Check if normal recording is in progress
            if let controller = self.agentController, controller.state != .idle {
                AgentConsole.critical("[TalkieAgentXPC] Cannot start ephemeral capture - recording in progress (state: \(controller.state))")
                reply(nil, "Recording already in progress")
                return
            }

            // Check microphone permission
            guard MicrophonePermission.isGranted else {
                AgentConsole.critical("[TalkieAgentXPC] Ephemeral capture failed - no microphone permission")
                reply(nil, "Microphone permission not granted")
                return
            }

            // Create new capture session using UnifiedAudioCapture
            let sessionId = UUID().uuidString
            let capture = UnifiedAudioCapture()
            let session = EphemeralCaptureSession(id: sessionId, capture: capture)
            self.ephemeralSessions[sessionId] = session

            // Set up error handler
            capture.onError = { [weak self] error in
                Task { @MainActor in
                    if let session = self?.ephemeralSessions[sessionId] {
                        session.error = error.localizedDescription
                        session.isComplete = true
                    }
                }
            }

            // Warm up the capture system
            let warmedUp = await capture.warmUp()
            guard warmedUp else {
                AgentConsole.critical("[TalkieAgentXPC] Ephemeral capture failed - warm up failed")
                self.ephemeralSessions.removeValue(forKey: sessionId)
                reply(nil, "Audio capture initialization failed")
                return
            }

            // Start capture with AAC config (ephemeral captures use AAC for smaller files)
            do {
                let captureSession = try await capture.startCapture(config: .ephemeral)
                session.captureSession = captureSession
                AgentConsole.critical("[TalkieAgentXPC] ✓ Ephemeral capture started: \(sessionId)")
                reply(sessionId, nil)
            } catch {
                AgentConsole.critical("[TalkieAgentXPC] Ephemeral capture start failed: \(error.localizedDescription)")
                self.ephemeralSessions.removeValue(forKey: sessionId)
                reply(nil, error.localizedDescription)
            }
        }
    }

    nonisolated func stopEphemeralCapture(sessionId: String, reply: @escaping (String?, String?) -> Void) {
        Task { @MainActor in
            guard let session = self.ephemeralSessions[sessionId] else {
                AgentConsole.critical("[TalkieAgentXPC] Ephemeral capture stop failed - session not found: \(sessionId)")
                reply(nil, "Session not found")
                return
            }

            // Stop capture and get result
            let result = await session.capture.stopCapture()

            // Clean up session
            session.capture.tearDown()
            self.ephemeralSessions.removeValue(forKey: sessionId)

            if let error = session.error {
                AgentConsole.critical("[TalkieAgentXPC] Ephemeral capture failed: \(error)")
                reply(nil, error)
            } else if let captureResult = result, captureResult.isValid {
                let audioPath = captureResult.fileURL.path
                AgentConsole.critical("[TalkieAgentXPC] ✓ Ephemeral capture stopped: \(audioPath)")
                reply(audioPath, nil)
            } else {
                AgentConsole.critical("[TalkieAgentXPC] Ephemeral capture failed - no audio captured or recording too short")
                reply(nil, "No audio was captured")
            }
        }
    }

    nonisolated func showSettings(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            AgentConsole.critical("[TalkieAgentXPC] showSettings requested")
            NSApp.activate(ignoringOtherApps: true)
            // Post notification that AppDelegate listens for
            NotificationCenter.default.post(name: .showSettingsFromXPC, object: nil)
            reply(true)
        }
    }

    nonisolated func openCaptureMarkup(filePath: String, reply: @escaping (Bool, String?) -> Void) {
        Task { @MainActor in
            let expanded = (filePath as NSString).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                let message = "Image file does not exist"
                AgentConsole.critical("[TalkieAgentXPC] openCaptureMarkup failed: \(message) \(fileURL.path)")
                reply(false, message)
                return
            }

            let opened = AgentCaptureMarkupController.shared.open(fileURL: fileURL)
            AgentConsole.critical("[TalkieAgentXPC] openCaptureMarkup: \(opened ? "opened" : "failed") \(fileURL.lastPathComponent)")
            reply(opened, opened ? nil : "Agent quick markup could not open this image")
        }
    }

    nonisolated func simulatePaste(reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let success = TextInserter.shared.simulatePaste()
            AgentConsole.critical("[TalkieAgentXPC] simulatePaste: \(success ? "success" : "failed")")
            reply(success)
        }
    }

    nonisolated func attachScreenshots(dictationId: String, screenshotsJSON: String, reply: @escaping (Bool) -> Void) {
        Task { @MainActor in
            guard let uuid = UUID(uuidString: dictationId) else {
                AgentConsole.critical("[TalkieAgentXPC] attachScreenshots: invalid UUID \(dictationId)")
                reply(false)
                return
            }

            // Merge screenshots into the dictation record
            let success = UnifiedDatabase.mergeScreenshots(id: uuid, screenshotsJSON: screenshotsJSON)
            AgentConsole.critical("[TalkieAgentXPC] attachScreenshots(\(dictationId.prefix(8))): \(success ? "merged" : "failed")")
            reply(success)
        }
    }

    nonisolated func recordLiveScreenshot(
        imageData: Data,
        capturedAt: TimeInterval,
        captureMode: String,
        width: Int,
        height: Int,
        windowTitle: String?,
        appName: String?,
        displayName: String?,
        reply: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            let success = self.agentController?.recordLiveScreenshot(
                imageData: imageData,
                capturedAt: Date(timeIntervalSince1970: capturedAt),
                captureMode: captureMode,
                width: width,
                height: height,
                windowTitle: windowTitle,
                appName: appName,
                displayName: displayName
            ) ?? false
            AgentConsole.critical("[TalkieAgentXPC] recordLiveScreenshot: \(success ? "recorded" : "ignored")")
            reply(success)
        }
    }

    // MARK: - Diagnostics

    nonisolated func getHotkeyStatus(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            let statuses = AppDelegate.hotkeyManagers.map { label, manager in
                HotKeyStatusInfo(
                    id: manager.signature,
                    label: label,
                    hotkeyID: manager.hotkeyID,
                    isRegistered: manager.isRegistered,
                    keyCode: manager.registeredKeyCode,
                    modifiers: manager.registeredModifiers
                )
            }
            let data = try? JSONEncoder().encode(statuses)
            reply(data)
        }
    }

    // MARK: - TalkieServer Supervision

    nonisolated func getTalkieAgentServerStatus(reply: @escaping (Data?) -> Void) {
        Task { @MainActor in
            let status = TalkieAgentServerSupervisor.shared.currentStatus
            reply(try? JSONEncoder().encode(status))
        }
    }

    nonisolated func controlTalkieAgentServer(action: String, reply: @escaping (Bool, String?) -> Void) {
        Task { @MainActor in
            switch action {
            case "start":
                await TalkieAgentServerSupervisor.shared.start()
                reply(true, nil)
            case "stop":
                await TalkieAgentServerSupervisor.shared.stop()
                reply(true, nil)
            case "restart":
                await TalkieAgentServerSupervisor.shared.restart()
                reply(true, nil)
            default:
                reply(false, "Unknown action: \(action)")
            }
        }
    }

    func broadcastTalkieAgentServerStatus(_ status: TalkieAgentServerStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        for connection in observers {
            guard let observer = connection.remoteObjectProxyWithErrorHandler({ _ in
            }) as? TalkieAgentStateObserverProtocol else { continue }
            observer.talkieAgentServerStatusDidChange?(data)
        }
    }

    func addObserverConnection(_ connection: NSXPCConnection) {
        observers.append(connection)
        updateConnectionStatus()
        AgentConsole.critical("[TalkieAgentXPC] ✓ Talkie connected (total observers: \(observers.count))")
    }

    func removeObserverConnection(_ connection: NSXPCConnection) {
        observers.removeAll { $0 === connection }
        updateConnectionStatus()
        AgentConsole.critical("[TalkieAgentXPC] ⚠️ Talkie disconnected (remaining observers: \(observers.count))")
    }

    private func updateConnectionStatus() {
        let wasConnected = isTalkieConnected
        isTalkieConnected = !observers.isEmpty

        if wasConnected != isTalkieConnected {
            lastConnectionChange = Date()
            if isTalkieConnected {
                AgentConsole.critical("[TalkieAgentXPC] 🟢 Talkie is now connected")
            } else {
                AgentConsole.critical("[TalkieAgentXPC] 🔴 Talkie disconnected")
            }
        }
    }
}

// MARK: - NSXPCListenerDelegate

extension TalkieAgentXPCService: NSXPCListenerDelegate {
    nonisolated func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure the connection
        newConnection.exportedInterface = NSXPCInterface(with: TalkieAgentXPCServiceProtocol.self)
        newConnection.exportedObject = self

        // Set up remote interface for callbacks
        newConnection.remoteObjectInterface = NSXPCInterface(with: TalkieAgentStateObserverProtocol.self)

        // Handle connection lifecycle
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            Task { @MainActor in
                guard let self, let conn = newConnection else { return }
                self.removeObserverConnection(conn)
                AgentConsole.critical("[TalkieAgentXPC] Connection invalidated")
            }
        }

        newConnection.interruptionHandler = {
            AgentConsole.critical("[TalkieAgentXPC] Connection interrupted")
        }

        // Add to observers
        Task { @MainActor [weak self, weak newConnection] in
            guard let self, let conn = newConnection else { return }
            self.addObserverConnection(conn)
        }

        newConnection.resume()
        AgentConsole.critical("[TalkieAgentXPC] Accepted new connection")
        return true
    }
}
