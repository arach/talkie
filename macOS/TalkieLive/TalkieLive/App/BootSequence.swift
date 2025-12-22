//
//  BootSequence.swift
//  TalkieLive
//
//  Explicit startup sequence with clear ordering and logging.
//  Implements Proposal 006: Standardize Service Initialization
//

import Foundation
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "Boot")

/// Boot phases for service initialization
enum BootPhase: String, CaseIterable {
    case config = "Config"      // Settings, logging infrastructure
    case data = "Data"          // Database initialization
    case engine = "Engine"      // XPC connection to TalkieEngine
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
        logger.info("╔══════════════════════════════════════════════════╗")
        logger.info("║           TALKIE LIVE BOOT SEQUENCE              ║")
        logger.info("╚══════════════════════════════════════════════════╝")

        // Phase 1: Config
        await executePhase(.config) {
            self.initConfig()
        }

        // Phase 2: Data
        await executePhase(.data) {
            self.initData()
        }

        // Phase 3: Engine (async - connection may take time)
        await executePhase(.engine) {
            await self.initEngine()
        }

        // Phase 4: Services (depends on engine being ready)
        await executePhase(.services) {
            self.initServices()
        }

        // Phase 5: UI
        await executePhase(.ui) {
            self.initUI()
        }

        // Boot complete
        currentPhase = .complete
        isComplete = true

        let duration = bootStartTime.map { Date().timeIntervalSince($0) } ?? 0
        logger.info("╔══════════════════════════════════════════════════╗")
        logger.info("║  ✓ BOOT COMPLETE in \(String(format: "%.2f", duration))s")
        logger.info("║  Services: \(self.initializedServices.count)")
        logger.info("╚══════════════════════════════════════════════════╝")

        AppLogger.shared.log(.system, "Boot complete", detail: String(format: "%.2fs, %d services", duration, initializedServices.count))
    }

    private func executePhase(_ phase: BootPhase, action: () async -> Void) async {
        currentPhase = phase
        let phaseStart = Date()
        logger.info("┌─ \(phase.rawValue) phase starting...")

        await action()

        let duration = Date().timeIntervalSince(phaseStart)
        logger.info("└─ \(phase.rawValue) complete (\(String(format: "%.0f", duration * 1000))ms)")
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
    }

    private func initData() {
        // Database - triggers migration if needed
        // Access .shared to initialize the DatabaseQueue
        _ = LiveDatabase.shared
        record("LiveDatabase")

        // Audio storage directory
        _ = AudioStorage.audioDirectory
        record("AudioStorage")
    }

    private func initEngine() async {
        // Engine client - start connection
        let client = EngineClient.shared
        record("EngineClient")

        // Attempt to connect (non-blocking, will retry in background)
        // We don't wait for full connection here - just initiate it
        client.connect()

        // Give engine a moment to connect (optional quick check)
        // This doesn't block if engine isn't ready - services handle that
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let status = client.isConnected ? "connected" : "connecting..."
        logger.info("   Engine status: \(status)")
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
        logger.debug("   ✓ \(service)")
    }
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
