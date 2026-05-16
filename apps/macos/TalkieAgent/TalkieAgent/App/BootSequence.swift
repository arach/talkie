//
//  BootSequence.swift
//  TalkieAgent
//
//  Explicit startup sequence with clear ordering and logging.
//  Implements Proposal 006: Standardize Service Initialization
//

import Foundation
import AppKit
import TalkieKit

private let log = Log(.system)

// MARK: - Startup Profiler

/// Precise process start time (set at file load)
private let _processStartTime = CFAbsoluteTimeGetCurrent()

/// Mark a startup milestone with precise timing
private func markStartup(_ milestone: String) {
    let elapsed = (CFAbsoluteTimeGetCurrent() - _processStartTime) * 1000
    log.info(String(format: "⏱️ [%6.1fms] %@", elapsed, milestone), critical: true)
}

/// Boot phases for service initialization
enum BootPhase: String, CaseIterable {
    case config = "Config"      // Settings, logging infrastructure
    case data = "Data"          // Database initialization
    case engine = "Engine"      // Embedded engine startup
    case services = "Services"  // Background services (retry manager, etc.)
    case ui = "UI"              // UI controllers (pill, overlay)
    case complete = "Complete"  // Boot finished

    var icon: String {
        switch self {
        case .config: return "gear"
        case .data: return "cylinder"
        case .engine: return "bolt"
        case .services: return "arrow.triangle.2.circlepath"
        case .ui: return "rectangle.on.rectangle"
        case .complete: return "checkmark.circle"
        }
    }
}

/// Orchestrates app startup with explicit ordering
@MainActor
final class BootSequence {
    static let shared = BootSequence()

    /// Current boot phase
    private(set) var currentPhase: BootPhase = .config

    /// Boot start time for measuring duration
    private var bootStartTime: Date?

    /// Whether boot has completed
    private(set) var isComplete = false

    /// Services initialized during boot (for debugging)
    private(set) var initializedServices: [String] = []

    private init() {}

    // MARK: - Boot Execution

    /// Execute the full boot sequence
    /// Called from AppDelegate.applicationDidFinishLaunching
    func execute() async {
        bootStartTime = Date()
        log.info("════════════════════════════════════════════════════════════", critical: true)
        log.info("TalkieAgent Boot Sequence", critical: true)
        log.info("  PID: \(ProcessInfo.processInfo.processIdentifier)", critical: true)
        log.info("════════════════════════════════════════════════════════════", critical: true)
        markStartup("Boot started")

        // Phase 1: Config
        await executePhase(.config) {
            self.initConfig()
        }
        markStartup("Config phase complete")

        // Phase 2: Data
        await executePhase(.data) {
            self.initData()
        }
        markStartup("Data phase complete")

        // Phase 3: Engine (async - connection may take time)
        await executePhase(.engine) {
            await self.initEngine()
        }
        markStartup("Engine phase complete")

        // Phase 4: Services (depends on engine being ready)
        await executePhase(.services) {
            self.initServices()
            await self.initBridgeServer()
        }
        markStartup("Services phase complete")

        // Phase 5: UI
        await executePhase(.ui) {
            self.initUI()
        }
        markStartup("UI phase complete")

        // Boot complete
        currentPhase = .complete
        isComplete = true

        let duration = bootStartTime.map { Date().timeIntervalSince($0) } ?? 0
        log.info("════════════════════════════════════════════════════════════", critical: true)
        markStartup("✅ BOOT COMPLETE (\(initializedServices.count) services)")
        log.info("  Total time: \(String(format: "%.2f", duration))s", critical: true)
        log.info("════════════════════════════════════════════════════════════", critical: true)

        #if DEBUG
        checkStaleLaunchRegistrations()
        #endif
    }

    private func executePhase(_ phase: BootPhase, action: () async -> Void) async {
        currentPhase = phase
        let phaseStart = Date()
        log.debug("\(phase.rawValue) phase starting...")

        await action()

        let duration = Date().timeIntervalSince(phaseStart)
        log.debug("\(phase.rawValue) complete (\(String(format: "%.0f", duration * 1000))ms)")
    }

    // MARK: - Phase Implementations

    private func initConfig() {
        // Settings - must be first, other services depend on it
        _ = LiveSettings.shared
        LiveSettings.shared.applyAppearance()
        record("LiveSettings")

        // Logging infrastructure (includes in-memory buffer for LogViewerConsole)
        _ = AppLogger.shared
        record("AppLogger")

        // TalkieReporter - unified error reporting
        initReporter()
        record("TalkieReporter")
    }

    private func initReporter() {
        let reporter = TalkieReporter.shared

        // Register Live app info
        reporter.registerAppInfo(for: .live) {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            return ReportAppInfo(
                running: true,
                pid: ProcessInfo.processInfo.processIdentifier,
                version: version,
                uptime: ProcessInfo.processInfo.systemUptime,
                memoryMB: Self.getMemoryUsageMB()
            )
        }

        // Register embedded engine info (hosted inside TalkieAgent)
        reporter.registerAppInfo(for: .engine) {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            return ReportAppInfo(
                running: true,
                pid: ProcessInfo.processInfo.processIdentifier,
                version: version,
                uptime: ProcessInfo.processInfo.systemUptime,
                memoryMB: Self.getMemoryUsageMB()
            )
        }

        // Register connection state provider
        reporter.registerConnectionState {
            EngineClient.shared.connectionState.rawValue
        }

        // Register last error provider
        reporter.registerLastError {
            EngineClient.shared.lastError
        }

        log.debug("TalkieReporter configured with Live + Engine providers")
    }

    /// Get current memory usage in MB
    private static func getMemoryUsageMB() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.resident_size / (1024 * 1024))
    }

    private func initData() {
        // Database - triggers migration if needed
        // Access .shared to initialize the DatabaseQueue
        _ = UnifiedDatabase.shared
        record("UnifiedDatabase")

        // Audio storage directory
        _ = AudioStorage.audioDirectory
        record("AudioStorage")
    }

    private func initEngine() async {
        EmbeddedEngineCoordinator.shared.start()
        record("EmbeddedEngineCoordinator")

        // Engine client - connect to the embedded runtime
        let client = EngineClient.shared
        record("EngineClient")

        client.connect()

        try? await Task.sleep(for: .milliseconds(100))

        let status = client.isConnected ? "connected" : "connecting..."
        log.debug("Embedded engine status: \(status)")
    }

    private func initServices() {
        // Transcription retry manager - depends on EngineClient being initialized
        // It observes EngineClient.connectionState for reconnection events
        _ = TranscriptionRetryManager.shared
        record("TranscriptionRetryManager")

        // Context capture service
        _ = ContextCaptureService.shared
        record("ContextCaptureService")

        // Sound manager - preloads sounds
        _ = SoundManager.shared
        record("SoundManager")

        // Processing milestones (for status bar)
        _ = ProcessingMilestones.shared
        record("ProcessingMilestones")

        // Utterance store
        DictationStore.shared.refresh()
        record("DictationStore")
    }

    private func initBridgeServer() async {
        // HTTP API on :8767
        if #available(macOS 14.0, *) {
            do {
                try await BridgeServer.shared.start()
                record("BridgeServer")
            } catch {
                log.error("BridgeServer failed to start: \(error)")
            }
        }

        // WebSocket JSON-RPC on :19823
        AgentServiceBridge.shared.start()
        record("AgentServiceBridge")

        // TalkieSpeech (Kokoro TTS): not auto-started. The Kokoro models add
        // boot cost, the binary may not exist in a fresh checkout, and TTS
        // is opt-in. Token is still generated at `shared` init so any
        // future caller (settings toggle, first /tts request) can call
        // `TalkieSpeechSupervisor.shared.start()` to bring it up. We call
        // `stop()` rather than just touching `.shared` so any orphaned
        // TalkieSpeech on :8780 (from a previous agent that crashed before
        // SIGTERM-ing its child) gets killed — otherwise it lingers with
        // Kokoro models in RAM and no parent.
        await TalkieSpeechSupervisor.shared.stop()
        record("TalkieSpeechSupervisor[dormant]")

        // TalkieServer (Bun sidecar) supervision
        await TalkieAgentServerSupervisor.shared.start()
        record("TalkieAgentServerSupervisor")
    }

    private func initUI() {
        // These are lazy but we can warm them up here
        _ = RecordingOverlayController.shared
        record("RecordingOverlayController")

        _ = FloatingPillController.shared
        record("FloatingPillController")

        _ = QueuePickerController.shared
        record("QueuePickerController")

        _ = OnboardingManager.shared
        record("OnboardingManager")
    }

    // MARK: - Helpers

    private func record(_ service: String) {
        initializedServices.append(service)
        log.debug("Initialized: \(service)")
    }

    #if DEBUG
    // MARK: - Stale Launch Registration Check

    /// Check for stale/crashed Talkie launch registrations and log warnings.
    /// Stale registrations can cause confusing behavior — e.g. launchd claiming a
    /// MachService name that prevents the fresh process from registering it.
    private func checkStaleLaunchRegistrations() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.debug("Could not run launchctl list: \(error.localizedDescription)")
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }

        var stale: [(label: String, reason: String)] = []

        for line in output.components(separatedBy: "\n") {
            guard line.lowercased().contains("talkie") else { continue }

            // Format: "PID\tStatus\tLabel"
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }

            let pid = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let status = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let label = String(parts[2]).trimmingCharacters(in: .whitespaces)

            // Skip app-launched processes (application.* are fine)
            if label.hasPrefix("application.") { continue }

            // Skip our own process's registration
            if let myBundleId = Bundle.main.bundleIdentifier, label == myBundleId { continue }

            if pid == "-", status == "78" {
                stale.append((label, "not running (status 78)"))
            } else if let exitCode = Int(status), exitCode < 0 {
                stale.append((label, "crashed (signal \(-exitCode))"))
            } else if pid == "-", let exitCode = Int(status), exitCode != 0 {
                stale.append((label, "exited with error \(exitCode)"))
            }
        }

        if stale.isEmpty {
            log.debug("No stale launch registrations found")
        } else {
            log.warning("╔══════════════════════════════════════════════════════════", critical: true)
            log.warning("║ \(stale.count) STALE LAUNCH REGISTRATION(S) DETECTED", critical: true)
            for entry in stale {
                log.warning("║  \(entry.label) — \(entry.reason)", critical: true)
            }
            log.warning("║", critical: true)
            log.warning("║ Fix: launchctl bootout gui/$(id -u)/<label>", critical: true)
            log.warning("║  Or: ./scripts/launchctl-status.sh --clean", critical: true)
            log.warning("╚══════════════════════════════════════════════════════════", critical: true)
        }
    }
    #endif
}

// MARK: - Convenience for AppDelegate

extension BootSequence {
    /// Quick synchronous init for services that can't wait
    /// Use sparingly - prefer async boot for most services
    func initEssentials() {
        // Only truly essential sync initialization
        _ = LiveSettings.shared
        LiveSettings.shared.applyAppearance()
    }
}
