import Cocoa
import AVFoundation
import SwiftUI
import TalkieKit
import Carbon.HIToolbox
import Combine
import ScreenCaptureKit
import UniformTypeIdentifiers

private let log = Log(.system)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var agentController: AgentController!
    private let speechPlaybackController = SelectionSpeechPlaybackController.shared
    private let selectionFeedbackController = SelectionFeedbackOverlayController.shared

    // Hotkey signatures derived from TalkieEnvironment (see TalkieEnvironment.swift for philosophy)
    private static var sig: String { TalkieEnvironment.current.hotkeySignaturePrefix }

    private let hotKeyManager = HotKeyManager(signature: "\(sig)IV", hotkeyID: 1)  // Toggle mode
    private let pttHotKeyManager = HotKeyManager(signature: "\(sig)PT", hotkeyID: 3)  // Push-to-talk
    private let queuePickerHotKeyManager = HotKeyManager(signature: "\(sig)QP", hotkeyID: 2)  // Queue picker
    private let ambientHotKeyManager = HotKeyManager(signature: "\(sig)AB", hotkeyID: 6)  // Ambient mode toggle
    private let composeHotKeyManager = HotKeyManager(signature: "\(sig)CO", hotkeyID: 7)  // Compose with selection
    private let speakSelectionHotKeyManager = HotKeyManager(signature: "\(sig)SP", hotkeyID: 14)  // Speak selected text
    private let screenshotHotKeyManager = HotKeyManager(signature: "\(sig)SS", hotkeyID: 8)  // Screenshot during recording

    // Direct screenshot shortcuts. Defaults intentionally avoid macOS screenshot shortcuts.
    private let ssFullscreenHotKey = HotKeyManager(signature: "\(sig)S3", hotkeyID: 9)
    private let ssRegionHotKey     = HotKeyManager(signature: "\(sig)S4", hotkeyID: 10)
    private let ssBufferHotKey     = HotKeyManager(signature: "\(sig)S5", hotkeyID: 11)
    private let ssWindowHotKey     = HotKeyManager(signature: "\(sig)S6", hotkeyID: 12)
    private let ssShelfHotKey      = HotKeyManager(signature: "\(sig)ST", hotkeyID: 17)
    private let screenRecordHotKeyManager = HotKeyManager(signature: "\(sig)SR", hotkeyID: 13)  // Screen recording chord
    private let pasteChordHotKeyManager = HotKeyManager(signature: "\(sig)PV", hotkeyID: 15)  // Quick Paste chord
    private let pasteLastScreenshotHotKey = HotKeyManager(signature: "\(sig)PF", hotkeyID: 16)  // Paste last screenshot
    private let walkieHotKeyManager = HotKeyManager(signature: "\(sig)WT", hotkeyID: 17)  // Hyper+T walkie instrument (TLK-020)
    private let captureHotPathLoggingEnabled = ProcessInfo.processInfo.environment["CAPTURE_PERF"] == "1"

    #if DEBUG
    private let debugPasteHotKeyManager = HotKeyManager(signature: "\(sig)DP", hotkeyID: 5)  // Debug paste test
    #endif

    /// All hotkey managers with labels — exposed for XPC diagnostics
    static var hotkeyManagers: [(label: String, manager: HotKeyManager)] = []

    private var cancellables = Set<AnyCancellable>()
    private var lastHotkey: HotkeyConfig?
    private var lastPTTHotkey: HotkeyConfig?
    private var lastPTTEnabled: Bool?
    private var lastSelectionQuickHotkey: HotkeyConfig?
    private var lastExternalSelectionSourceApp: NSRunningApplication?

    // Lazy UI controllers - initialized during boot sequence
    private var overlayController: RecordingOverlayController { RecordingOverlayController.shared }
    private var floatingPill: FloatingPillController { FloatingPillController.shared }
    private var notchOverlay: NotchOverlayController { NotchOverlayController.shared }

    // Settings window (consolidated - includes permissions tab)
    private var settingsWindow: NSWindow?

    // Event monitors (stored to allow cleanup if needed)
    private var controlKeyMonitor: Any?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app - keep running when windows are closed
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: prevent duplicate TalkieAgent processes
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myBundleID = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: myBundleID)
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty {
            // Check if existing instances are actually responsive (not zombie/stuck)
            let terminated = others.filter { $0.isTerminated }
            let alive = others.filter { !$0.isTerminated }

            if !alive.isEmpty {
                let alivePIDs = alive.map { String($0.processIdentifier) }.joined(separator: ", ")
                NSLog("[TalkieAgent] Another instance already running (PID: %@) — exiting duplicate (PID: %d)", alivePIDs, myPID)
                NSApplication.shared.terminate(nil)
                return
            }

            // All other instances are terminated/zombie — we're the valid one, continue
            if !terminated.isEmpty {
                let zombiePIDs = terminated.map { String($0.processIdentifier) }.joined(separator: ", ")
                NSLog("[TalkieAgent] Found zombie instances (PID: %@) — taking over as PID %d", zombiePIDs, myPID)
            }
        }

        // Configure unified logger first
        TalkieLogger.configure(source: .talkieLive, mirrorToOSLogInDebug: true)

        do {
            try TalkieHelperRuntimeStateStore.writeCurrentProcess(for: .agent)
        } catch {
            log.error("Failed to write helper runtime state: \(error.localizedDescription)")
        }

        // Start XPC listener immediately so Talkie can connect during boot
        TalkieAgentXPCService.shared.startService()

        // Start memory monitoring (logs when crossing thresholds)
        MemoryMonitor.shared.start()

        // Essential sync init (settings needed for appearance)
        BootSequence.shared.initEssentials()

        // Start async boot sequence
        Task {
            await BootSequence.shared.execute()
            await self.postBootSetup()
        }

        // Sync setup that can't wait for boot
        setupStatusBar()
        setupMenu()
        configureSelectionFeedback()
        trackSelectionSourceApp()
    }

    /// Setup that runs after boot sequence completes
    private func postBootSetup() async {
        let settings = LiveSettings.shared

        // Pre-flight accessibility check - warm the cache early so we don't pay the cost
        // during recording. This runs once on boot and caches the result.
        let hasAccessibility = PermissionManager.shared.preflightAccessibilityCheck()
        if !hasAccessibility {
            log.warning(
                "Accessibility permission not granted - paste may fail",
                detail: "bundle=\(Bundle.main.bundleIdentifier ?? "unknown"), executable=\(Bundle.main.executableURL?.path ?? "unknown")"
            )
        }

        // Listen for permissions window notification from FloatingPill
        NotificationCenter.default.addObserver(
            forName: .showPermissionsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showPermissions()
        }

        // Listen for paste-blocked notification and show toast
        NotificationCenter.default.addObserver(
            forName: .pasteBlockedByPermission,
            object: nil,
            queue: .main
        ) { _ in
            ToastOverlayController.shared.showPermissionBlocked()
        }

        // Create core pipeline with pre-warmed audio capture
        let audio = AudioCaptureService()
        _ = await audio.warmUp()  // Pre-warm engine for fast recording start

        let transcription = EngineTranscriptionService(modelId: settings.selectedModelId)
        let router = TranscriptRouter(mode: settings.routingMode)

        agentController = AgentController(
            audio: audio,
            transcription: transcription,
            router: router
        )

        // Set controller reference in XPC service for remote toggle
        TalkieAgentXPCService.shared.agentController = agentController

        // Pre-load the embedded engine model
        await preloadModel(settings: settings)

        // Setup UI wiring
        setupStateObservation()
        setupHotkeys()
        setupFloatingPill()

        // Bridge messages now routed through Talkie (TalkieServer → XPC)

        // Show floating pill on launch
        floatingPill.show()

        log.info("Boot complete — hotkey change observers active")
    }

    func applicationWillTerminate(_ notification: Notification) {
        TalkieAgentServerSupervisor.shared.stopSync()
        TalkieSpeechSupervisor.shared.stopSync()
        TalkieHelperRuntimeStateStore.clear(for: .agent)
        TalkieAgentXPCService.shared.stopService()

        // Clean up event monitors
        if let monitor = controlKeyMonitor {
            NSEvent.removeMonitor(monitor)
            controlKeyMonitor = nil
        }
    }

    // MARK: - URL Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        // Handle talkieagent:// URLs
        guard url.scheme?.hasPrefix("talkieagent") == true else { return }

        NSLog("[TalkieAgent] Received URL: \(url.absoluteString)")

        switch url.host {
        case "settings":
            showSettings(tab: .shortcuts)
        case "performance":
            showSettings(tab: .performance)
        case "toggle":
            toggleListening(interstitial: false)
        default:
            // Unknown command - show settings as fallback
            showSettings(tab: .shortcuts)
        }
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Start with mic icon (idle state)
            updateMenuBarIcon(isRecording: false)
            updateStatusBarTooltip()

            // Monitor Control key to show environment badge
            controlKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                self?.updateStatusBarBadge(controlPressed: event.modifierFlags.contains(.control))
                return event
            }
        }
    }

    /// Update menu bar icon based on recording state and mic permission.
    private func updateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem.button else { return }

        let hasMicPermission = PermissionManager.shared.microphoneStatus == .granted
        let image = createMenuBarIcon(isRecording: isRecording, hasMicPermission: hasMicPermission)
        button.image = image

        // Reset any tint - color is handled in the drawing
        button.contentTintColor = nil
    }

    /// Create a custom menu bar icon.
    /// - Recording: pill with mic + waveform (red background, white symbols)
    /// - Idle, mic denied: mic symbol + small orange dot badge
    /// - Idle, mic granted: plain mic symbol (template, adapts to system appearance)
    private func createMenuBarIcon(isRecording: Bool, hasMicPermission: Bool) -> NSImage {
        if isRecording {
            // Recording: pill with mic + waveform
            let height: CGFloat = 22      // Taller pill
            let pillWidth: CGFloat = 40   // Wider pill

            let image = NSImage(size: NSSize(width: pillWidth, height: height), flipped: false) { rect in
                // Red pill background
                let bgRect = rect.insetBy(dx: 1, dy: 1)
                let cornerRadius = bgRect.height / 2  // Fully rounded ends

                let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor.systemRed.withAlphaComponent(0.9).setFill()
                bgPath.fill()

                // Symbol configuration
                let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)

                // Draw mic on the left
                if let micSymbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(symbolConfig) {

                    let micSize = NSSize(width: 11, height: 14)
                    let micX: CGFloat = 6
                    let micY = (height - micSize.height) / 2

                    let micRect = NSRect(x: micX, y: micY, width: micSize.width, height: micSize.height)
                    let tintedMic = micSymbol.tinted(with: .white)
                    tintedMic.draw(in: micRect)
                }

                // Draw waveform on the right
                if let waveSymbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
                    .withSymbolConfiguration(symbolConfig) {

                    let waveSize = NSSize(width: 16, height: 12)
                    let waveX = pillWidth - waveSize.width - 5
                    let waveY = (height - waveSize.height) / 2

                    let waveRect = NSRect(x: waveX, y: waveY, width: waveSize.width, height: waveSize.height)
                    let tintedWave = waveSymbol.tinted(with: .white)
                    tintedWave.draw(in: waveRect)
                }

                return true
            }

            image.isTemplate = false  // Keep red color
            return image

        } else if !hasMicPermission {
            // Idle + mic permission missing: mic icon with small orange warning dot in top-right
            let menuBarHeight = NSStatusBar.system.thickness
            let pointSize = min(15, menuBarHeight * 0.55)
            let dotDiameter: CGFloat = 5
            let iconWidth = pointSize + dotDiameter * 0.6
            let iconHeight = pointSize + dotDiameter * 0.6
            let iconSize = NSSize(width: iconWidth, height: iconHeight)

            let image = NSImage(size: iconSize, flipped: false) { _ in
                let symbolConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
                if let micSymbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone permission missing")?
                    .withSymbolConfiguration(symbolConfig) {
                    let tinted = micSymbol.tinted(with: NSColor.labelColor)
                    tinted.draw(in: NSRect(x: 0, y: 0, width: pointSize, height: iconHeight))
                }

                // Orange dot badge anchored to top-right corner of the mic
                let dotX = iconWidth - dotDiameter
                let dotY = iconHeight - dotDiameter
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotDiameter, height: dotDiameter)).fill()

                return true
            }
            image.isTemplate = false
            return image

        } else {
            // Idle: just the mic icon, no background (minimalist)
            // Scale to fit the actual menu bar height (varies: ~24pt non-notch, ~33pt M2 Air, ~38pt Pro)
            let menuBarHeight = NSStatusBar.system.thickness
            let pointSize = min(15, menuBarHeight * 0.55)
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)

            if let micSymbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Ready")?
                .withSymbolConfiguration(symbolConfig) {
                micSymbol.isTemplate = true  // Adapts to menu bar (light/dark mode)
                return micSymbol
            }

            // Fallback
            let fallback = NSImage(size: NSSize(width: 15, height: 15))
            return fallback
        }
    }

    private func updateStatusBarBadge(controlPressed: Bool) {
        guard let button = statusItem.button,
              let bundleID = Bundle.main.bundleIdentifier else { return }

        // Only show badge for dev builds when Control is held
        if controlPressed && bundleID.hasSuffix(".dev") {
            button.title = "DEV"
            button.image = nil
            button.contentTintColor = nil
        } else {
            // Restore icon based on current state
            button.title = ""
            let isRecording = agentController?.state == .listening
            let isProcessing = agentController?.state == .transcribing || agentController?.state == .routing
            updateMenuBarIcon(isRecording: isRecording || isProcessing)
        }
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleListeningFromMenu), keyEquivalent: "")
        recordItem.target = self
        menu.addItem(recordItem)

        menu.addItem(NSMenuItem.separator())

        let speakSelectionItem = NSMenuItem(title: "Quick Selection Action", action: #selector(speakSelectionFromMenu), keyEquivalent: "")
        speakSelectionItem.target = self
        menu.addItem(speakSelectionItem)

        let historyItem = NSMenuItem(title: "Show History", action: #selector(showHistory), keyEquivalent: "h")
        historyItem.keyEquivalentModifierMask = [.option, .command]
        historyItem.target = self
        menu.addItem(historyItem)

        // Recent dictations submenu
        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let recentSubmenu = NSMenu()
        recentItem.submenu = recentSubmenu
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "Permissions...", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        // Add warning indicator if permissions are missing
        if !PermissionManager.shared.allRequiredGranted {
            permissionsItem.title = "⚠️ Permissions..."
        }
        menu.addItem(permissionsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Talkie Agent", action: #selector(confirmQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Set initial key equivalents from settings
        updateMenuKeyEquivalent()
    }

    // MARK: - State Observation

    private func setupStateObservation() {
        let hasNotch = NotchInfo.detect().hasNotch
        let notchEnabled = LiveSettings.shared.notchOverlayEnabled

        // Initialize notch overlay if Talkie isn't currently connected
        if hasNotch && notchEnabled && !TalkieAgentXPCService.shared.isTalkieConnected {
            notchOverlay.initialize()
        }

        // Observe state changes to update the icon, overlay, and floating pill
        agentController.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)

                let talkieConnected = TalkieAgentXPCService.shared.isTalkieConnected
                // Pill stays visible always — it doesn't compete for notch/top-bar real estate
                self?.floatingPill.updateState(state)
                if talkieConnected {
                    self?.overlayController.hide()
                    self?.notchOverlay.hide()
                } else {
                    let notchActive = hasNotch && LiveSettings.shared.notchOverlayEnabled
                    if notchActive {
                        // Notch overlay replaces the top bar recording overlay
                        self?.notchOverlay.updateState(state)
                        self?.overlayController.hide()
                    } else {
                        self?.overlayController.updateState(state)
                    }
                }

                SidecarOverlayController.shared.updateState(state)
            }
            .store(in: &cancellables)

        // When Talkie connects/disconnects, hand off the recording indicator
        TalkieAgentXPCService.shared.$isTalkieConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if connected {
                    // Talkie takes over top bar / notch — pill stays independent
                    self.overlayController.hide()
                    self.notchOverlay.hide()
                } else {
                    // Talkie gone — Agent takes over top bar / notch
                    let currentState = self.agentController.state
                    if hasNotch && LiveSettings.shared.notchOverlayEnabled {
                        self.notchOverlay.initialize()
                        self.notchOverlay.updateState(currentState)
                    } else {
                        self.overlayController.updateState(currentState)
                    }
                }
            }
            .store(in: &cancellables)

        // Wire up overlay controls
        overlayController.onStop = { [weak self] in
            Task {
                await self?.agentController.toggleListening()
            }
        }
        overlayController.onCancel = { [weak self] in
            self?.agentController.cancelListening()
        }
        overlayController.agentController = agentController  // For mid-recording intent updates

        // Wire up notch overlay controls
        notchOverlay.onStop = { [weak self] in
            Task {
                await self?.agentController.toggleListening()
            }
        }
        notchOverlay.onCancel = { [weak self] in
            self?.agentController.cancelListening()
        }

        // React to notch overlay setting changes at runtime
        if hasNotch {
            LiveSettings.shared.$notchOverlayEnabled
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enabled in
                    guard let self else { return }
                    if enabled {
                        self.notchOverlay.initialize()
                        let currentState = self.agentController.state
                        self.notchOverlay.updateState(currentState)
                        self.overlayController.hide()
                    } else {
                        self.notchOverlay.hide()
                        let currentState = self.agentController.state
                        self.overlayController.updateState(currentState)
                    }
                }
                .store(in: &cancellables)
        }

        // Reactively update the menubar icon when mic permission changes.
        PermissionManager.shared.$microphoneStatus
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let isRecording = self.agentController?.state == .listening
                let isProcessing = self.agentController?.state == .transcribing || self.agentController?.state == .routing
                self.updateMenuBarIcon(isRecording: isRecording || isProcessing)
            }
            .store(in: &cancellables)

        // Re-check mic permission when the user returns from another app (e.g. System Settings).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard self != nil else { return }
            Task { @MainActor in
                PermissionManager.shared.checkMicrophone()
            }
        }

        // Wire up Sidecar overlay controls (for iPad displays)
        let sidecarController = SidecarOverlayController.shared
        sidecarController.onStart = { [weak self] in
            Task {
                await self?.agentController.toggleListening()
            }
        }
        sidecarController.onStop = { [weak self] in
            Task {
                await self?.agentController.toggleListening()
            }
        }
        sidecarController.onCancel = { [weak self] in
            self?.agentController.cancelListening()
        }
        sidecarController.onScratchpad = { [weak self] in
            self?.agentController.setInterstitialIntent()
        }
        sidecarController.agentController = agentController
    }

    // MARK: - Floating Pill

    private func setupFloatingPill() {
        // Wire up floating pill - handle taps based on current state
        floatingPill.onTap = { [weak self] state, modifiers in
            log.debug("onTap received: state=\(state.rawValue), modifiers=\(modifiers.rawValue)")

            guard let self = self else {
                log.warning("self is nil in onTap")
                return
            }

            let shiftHeld = modifiers.contains(.shift)
            let commandHeld = modifiers.contains(.command)
            let optionHeld = modifiers.contains(.option)

            switch state {
            case .idle:
                // Option+tap: Show failed queue picker if there are queued items
                if optionHeld {
                    let queuedCount = UnifiedDatabase.countQueued()
                    log.debug("Option+tap: queuedCount=\(queuedCount)")

                    if queuedCount > 0 {
                        log.debug("Showing failed queue picker")
                        FailedQueueController.shared.show()
                    } else {
                        log.debug("No queued items to show")
                        NSSound.beep()
                    }
                } else {
                    // Normal tap: start recording (with optional interstitial mode)
                    // No hotkey timestamp for click-triggered recordings
                    log.debug("Starting recording (interstitial=\(shiftHeld))")
                    self.toggleListening(interstitial: shiftHeld, hotkeyTimestamp: nil)
                }

            case .listening:
                // Listening state: stop recording (with optional interstitial mode)
                self.toggleListening(interstitial: shiftHeld, hotkeyTimestamp: nil)

            case .transcribing, .routing, .refining:
                // Processing states: offer escape options
                if commandHeld {
                    // ⌘+tap: Force reset (emergency exit - abandons everything)
                    self.agentController.forceReset()
                } else {
                    // Regular tap: Push to queue (graceful save for later retry)
                    self.agentController.pushToQueue()
                }
            }
        }

        // Set agentController reference for Shift toggle on hover
        floatingPill.agentController = agentController
    }

    // MARK: - Hotkeys

    /// Load a HotkeyConfig from shared settings, falling back to hardcoded defaults.
    private static func loadHotkeyConfig(key: String, fallbackKeyCode: UInt32, fallbackModifiers: UInt32) -> (keyCode: UInt32, modifiers: UInt32) {
        if let data = TalkieSharedSettings.data(forKey: key) {
            if let config = try? JSONDecoder().decode(HotkeyConfigDTO.self, from: data) {
                return (config.keyCode, config.modifiers)
            }
        }
        return (fallbackKeyCode, fallbackModifiers)
    }

    private struct HotkeyConfigDTO: Codable, Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
    }

    private static var hyperModifiers: UInt32 {
        UInt32(cmdKey | optionKey | controlKey | shiftKey)
    }

    private static func migrateReservedCaptureDefaultsIfNeeded() {
        let migrationKey = "hotkeyCapture.safeDefaultsMigration.v1"
        guard !TalkieSharedSettings.bool(forKey: migrationKey) else { return }

        let oldCmdShift = UInt32(cmdKey | shiftKey)
        let migrations: [(key: String, old: HotkeyConfigDTO, new: HotkeyConfigDTO)] = [
            ("hotkeyCapture.fullscreen", .init(keyCode: 20, modifiers: oldCmdShift), .init(keyCode: 20, modifiers: hyperModifiers)),
            ("hotkeyCapture.region", .init(keyCode: 21, modifiers: oldCmdShift), .init(keyCode: 21, modifiers: hyperModifiers)),
            ("hotkeyCapture.trayViewer", .init(keyCode: 23, modifiers: oldCmdShift), .init(keyCode: 23, modifiers: hyperModifiers)),
            ("hotkeyCapture.window", .init(keyCode: 22, modifiers: oldCmdShift), .init(keyCode: 22, modifiers: hyperModifiers)),
            (AgentSettingsKey.pasteLastScreenshotHotkey, .init(keyCode: 9, modifiers: oldCmdShift), .init(keyCode: 35, modifiers: hyperModifiers)),
        ]

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var migrated: [String] = []

        for migration in migrations {
            guard let data = TalkieSharedSettings.data(forKey: migration.key),
                  let current = try? decoder.decode(HotkeyConfigDTO.self, from: data),
                  current == migration.old,
                  let newData = try? encoder.encode(migration.new) else {
                continue
            }

            TalkieSharedSettings.set(newData, forKey: migration.key)
            migrated.append(migration.key)
        }

        TalkieSharedSettings.set(true, forKey: migrationKey)

        if !migrated.isEmpty {
            log.info("Migrated reserved screenshot hotkeys", detail: "keys=\(migrated.joined(separator: ","))")
        }
    }

    private func setupHotkeys() {
        Self.migrateReservedCaptureDefaultsIfNeeded()

        let settings = LiveSettings.shared

        // Register all hotkeys once at the end of boot
        registerHotkeys()

        // Register queue picker hotkey: ⌥⌘V (Option + Command + V)
        // keyCode 9 = V key
        queuePickerHotKeyManager.registerHotKey(
            modifiers: UInt32(cmdKey | optionKey),
            keyCode: 9
        ) { [weak self] _ in  // Ignore timestamp for non-recording hotkeys
            self?.showQueuePicker()
        }

        // Register ambient mode toggle hotkey: ⌥⌘A (Option + Command + A)
        // Only register if ambient mode feature flag is enabled
        let ambientEnabled = TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureAmbientModeEnabled)
        if ambientEnabled {
            // keyCode 0 = A key
            ambientHotKeyManager.registerHotKey(
                modifiers: UInt32(cmdKey | optionKey),
                keyCode: 0
            ) { [weak self] _ in  // Ignore timestamp for non-recording hotkeys
                self?.toggleAmbientMode()
            }
            log.info("Ambient mode hotkey registered: ⌥⌘A")
        }

        registerCaptureHotkeys()

        // Register compose hotkey: ⌥⌘E (Option + Command + E) — capture selection and open Compose
        // keyCode 14 = E key
        composeHotKeyManager.registerHotKey(
            modifiers: UInt32(cmdKey | optionKey),
            keyCode: 14
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sendSelectedTextToCompose()
            }
        }
        log.info("Compose hotkey registered: ⌥⌘E")

        registerSelectionQuickHotkey()

        #if DEBUG
        // Register debug paste test hotkey: ⌃⌘T (Control + Command + T)
        // keyCode 17 = T key
        debugPasteHotKeyManager.registerHotKey(
            modifiers: UInt32(cmdKey | controlKey),
            keyCode: 17
        ) { [weak self] _ in  // Ignore timestamp for non-recording hotkeys
            Task { @MainActor in
                self?.testTextInserterPaste()
            }
        }
        log.debug("Debug paste hotkey registered: ⌃⌘T")
        #endif

        // Snapshot current config so change observers can diff against it
        lastHotkey = settings.hotkey
        lastPTTHotkey = settings.pttHotkey
        lastPTTEnabled = settings.pttEnabled
        lastSelectionQuickHotkey = settings.selectionQuickHotkey

        refreshHotkeyManagerDiagnostics(
            pttEnabled: settings.pttEnabled,
            ambientEnabled: ambientEnabled
        )

        // Listen for hotkey config changes (from settings UI in this process)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidChange),
            name: .hotkeyDidChange,
            object: nil
        )

        // Listen for UserDefaults changes (from Talkie main app updating settings)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(sharedHotkeysDidChange(_:)),
            name: NSNotification.Name("to.talkie.app.agentHotkeysDidChange"),
            object: nil
        )

        // Listen for toggle recording from status bar button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleListeningFromMenu),
            name: .toggleRecording,
            object: nil
        )

        // Listen for showSettings from XPC (Talkie → Live)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettingsAction),
            name: .showSettingsFromXPC,
            object: nil
        )
    }

    private func registerCaptureHotkeys() {
        unregisterCaptureHotkeys()

        guard TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureCaptureEnabled) else {
            log.info("Capture hotkeys skipped — feature disabled in shared settings")
            return
        }

        let captureChord = Self.loadHotkeyConfig(
            key: AgentSettingsKey.captureChordHotkey,
            fallbackKeyCode: 1,
            fallbackModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)
        )
        let screenRecordChord = Self.loadHotkeyConfig(
            key: AgentSettingsKey.screenRecordChordHotkey,
            fallbackKeyCode: 15,
            fallbackModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)
        )

        screenshotHotKeyManager.registerHotKey(
            modifiers: captureChord.modifiers,
            keyCode: captureChord.keyCode
        ) { [weak self] _ in
            Task { @MainActor in
                if let controller = self?.agentController, controller.state == .listening {
                    let selectionPayload = self?.selectionCaptureUserInfo()
                    DistributedNotificationCenter.default().postNotificationName(
                        NSNotification.Name("to.talkie.app.screenshotChord"),
                        object: nil,
                        userInfo: selectionPayload,
                        deliverImmediately: true
                    )
                    if self?.captureHotPathLoggingEnabled == true {
                        Log(.system).info("Screenshot chord: forwarded to Talkie picker (recording active)")
                    }
                } else {
                    DistributedNotificationCenter.default().postNotificationName(
                        NSNotification.Name("to.talkie.app.screenshotChord"),
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                    if self?.captureHotPathLoggingEnabled == true {
                        Log(.system).info("Screenshot chord: forwarded to Talkie via distributed notification")
                    }
                }
            }
        }
        log.info("Screenshot hotkey registered: keyCode=\(captureChord.keyCode) modifiers=\(captureChord.modifiers)")

        screenRecordHotKeyManager.registerHotKey(
            modifiers: screenRecordChord.modifiers,
            keyCode: screenRecordChord.keyCode
        ) { [weak self] _ in
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("to.talkie.app.screenRecordChord"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            if self?.captureHotPathLoggingEnabled == true {
                Log(.system).info("Screen record chord: forwarded to Talkie via distributed notification")
            }
        }
        log.info("Screen recording hotkey registered: keyCode=\(screenRecordChord.keyCode) modifiers=\(screenRecordChord.modifiers)")

        let pasteChord = Self.loadHotkeyConfig(
            key: AgentSettingsKey.pasteChordHotkey,
            fallbackKeyCode: 9,
            fallbackModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)
        )
        pasteChordHotKeyManager.registerHotKey(
            modifiers: pasteChord.modifiers,
            keyCode: pasteChord.keyCode
        ) { _ in
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("to.talkie.app.pasteChord"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            Log(.system).info("Paste chord: forwarded to Talkie via distributed notification")
        }
        log.info("Paste chord hotkey registered: keyCode=\(pasteChord.keyCode) modifiers=\(pasteChord.modifiers)")

        let directShortcuts: [(HotKeyManager, String, UInt32, UInt32, String)] = [
            (ssFullscreenHotKey, "hotkeyCapture.fullscreen", 20, Self.hyperModifiers, "fullscreen"),
            (ssRegionHotKey,     "hotkeyCapture.region",     21, Self.hyperModifiers, "region"),
            (ssBufferHotKey,     "hotkeyCapture.trayViewer", 23, Self.hyperModifiers, "viewTray"),
            (ssWindowHotKey,     "hotkeyCapture.window",     22, Self.hyperModifiers, "window"),
            (ssShelfHotKey,      "hotkeyCapture.trayShelf",  17, Self.hyperModifiers, "viewShelf"),
        ]

        for (manager, settingsKey, defaultKeyCode, defaultModifiers, mode) in directShortcuts {
            let config = Self.loadHotkeyConfig(
                key: settingsKey,
                fallbackKeyCode: defaultKeyCode,
                fallbackModifiers: defaultModifiers
            )
            if config.keyCode == captureChord.keyCode && config.modifiers == captureChord.modifiers {
                log.info("Direct screenshot hotkey skipped because it matches the capture chord: \(settingsKey)")
                continue
            }
            if config.keyCode == screenRecordChord.keyCode && config.modifiers == screenRecordChord.modifiers {
                log.info("Direct screenshot hotkey skipped because it matches the screen record chord: \(settingsKey)")
                continue
            }
            manager.registerHotKey(modifiers: config.modifiers, keyCode: config.keyCode) { _ in
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name("to.talkie.app.screenshotDirect"),
                    object: mode,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
        }

        log.info("Direct screenshot hotkeys registered from shared settings (defaults: Hyper+3/4/5/6, Hyper+T shelf)")

        let pasteLastScreenshot = Self.loadHotkeyConfig(
            key: AgentSettingsKey.pasteLastScreenshotHotkey,
            fallbackKeyCode: 35,
            fallbackModifiers: Self.hyperModifiers
        )
        pasteLastScreenshotHotKey.registerHotKey(
            modifiers: pasteLastScreenshot.modifiers,
            keyCode: pasteLastScreenshot.keyCode
        ) { _ in
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("to.talkie.app.pasteLastScreenshot"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            Log(.system).info("Paste last screenshot: forwarded to Talkie via distributed notification")
        }
        log.info("Paste last screenshot hotkey registered: keyCode=\(pasteLastScreenshot.keyCode) modifiers=\(pasteLastScreenshot.modifiers)")
    }

    private func unregisterCaptureHotkeys() {
        screenshotHotKeyManager.unregisterAll()
        screenRecordHotKeyManager.unregisterAll()
        pasteChordHotKeyManager.unregisterAll()
        ssFullscreenHotKey.unregisterAll()
        ssRegionHotKey.unregisterAll()
        ssBufferHotKey.unregisterAll()
        ssWindowHotKey.unregisterAll()
        ssShelfHotKey.unregisterAll()
        pasteLastScreenshotHotKey.unregisterAll()
    }

    private func registerSelectionQuickHotkey() {
        let selectionQuickHotkey = LiveSettings.shared.selectionQuickHotkey
        speakSelectionHotKeyManager.registerHotKey(
            modifiers: selectionQuickHotkey.modifiers,
            keyCode: selectionQuickHotkey.keyCode
        ) { [weak self] _ in
            Task { @MainActor in
                self?.speakSelectedText()
            }
        }
        log.info("Quick selection hotkey registered: \(selectionQuickHotkey.displayString)")
    }

    private func refreshHotkeyManagerDiagnostics(pttEnabled: Bool, ambientEnabled: Bool) {
        var managers: [(label: String, manager: HotKeyManager)] = [
            ("Toggle Recording", hotKeyManager),
            ("Queue Picker", queuePickerHotKeyManager),
            ("Compose", composeHotKeyManager),
            ("Speak Selection", speakSelectionHotKeyManager),
            ("Walkie", walkieHotKeyManager),
        ]

        if TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureCaptureEnabled) {
            managers.append(("Screenshot Chord", screenshotHotKeyManager))
            managers.append(("Screen Record", screenRecordHotKeyManager))
            managers.append(("Paste Chord", pasteChordHotKeyManager))
            managers.append(("Hyper+3 Fullscreen", ssFullscreenHotKey))
            managers.append(("Hyper+4 Region", ssRegionHotKey))
            managers.append(("Hyper+5 Tray", ssBufferHotKey))
            managers.append(("Hyper+6 Window", ssWindowHotKey))
            managers.append(("Hyper+T Shelf", ssShelfHotKey))
            managers.append(("Hyper+P Paste Last Screenshot", pasteLastScreenshotHotKey))
        }

        if pttEnabled {
            managers.append(("Push-to-Talk", pttHotKeyManager))
        }
        if ambientEnabled {
            managers.append(("Ambient Mode", ambientHotKeyManager))
        }
        #if DEBUG
        managers.append(("Debug Paste", debugPasteHotKeyManager))
        #endif
        Self.hotkeyManagers = managers
    }

    private func registerHotkeys() {
        let settings = LiveSettings.shared

        // Register toggle hotkey (press to start, press to stop)
        // The callback receives a precise timestamp from the Carbon callback for performance measurement
        hotKeyManager.registerHotKey(
            modifiers: settings.hotkey.modifiers,
            keyCode: settings.hotkey.keyCode
        ) { [weak self] timestamp in
            NSLog("[HotKey] Toggle hotkey callback fired (dispatch: %dms)", timestamp.elapsedMs())
            guard let self else {
                NSLog("[HotKey] ⚠️ self is nil in hotkey callback!")
                return
            }

            // Check for Cmd modifier as an EXTRA key beyond the configured hotkey.
            // Only trigger compose if Cmd is NOT already part of the hotkey modifiers.
            let commandHeld = NSEvent.modifierFlags.contains(.command)
            let hotkeyIncludesCmd = settings.hotkey.modifiers & UInt32(cmdKey) != 0
            if commandHeld && !hotkeyIncludesCmd && self.agentController.state == .idle {
                Task { @MainActor in
                    self.sendSelectedTextToCompose()
                }
                return
            }

            self.toggleListening(interstitial: false, hotkeyTimestamp: timestamp)
        }

        // Register push-to-talk hotkey if enabled
        // Press callback receives timestamp for accurate measurement
        if settings.pttEnabled {
            pttHotKeyManager.registerHotKey(
                modifiers: settings.pttHotkey.modifiers,
                keyCode: settings.pttHotkey.keyCode,
                onPress: { [weak self] timestamp in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.agentController.pttStart(hotkeyTimestamp: timestamp)
                    }
                },
                onRelease: { [weak self] in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.agentController.pttStop()
                    }
                }
            )
        }

        // Register walkie hotkey — default Hyper+T (⇧⌃⌥⌘T). Press-and-hold
        // semantics: press blooms the floating instrument, release dismisses.
        // Unit 1 (TLK-020): mechanic only — no audio, no LLM yet.
        walkieHotKeyManager.registerHotKey(
            modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey),
            keyCode: 17,
            onPress: { _ in
                Task { @MainActor in
                    WalkieController.shared.press()
                }
            },
            onRelease: {
                Task { @MainActor in
                    WalkieController.shared.release()
                }
            }
        )
        log.info("Walkie hotkey registered: ⇧⌃⌥⌘T")

        // Track what we registered to avoid needless re-registration
        lastHotkey = settings.hotkey
        lastPTTHotkey = settings.pttHotkey
        lastPTTEnabled = settings.pttEnabled
    }

    @objc private func hotkeyDidChange() {
        guard BootSequence.shared.isComplete else { return }

        let settings = LiveSettings.shared
        NSLog("[HotKey] hotkeyDidChange: re-registering (keyCode=%d, modifiers=%d)", settings.hotkey.keyCode, settings.hotkey.modifiers)
        log.info("Received .hotkeyDidChange notification")
        log.debug("Current hotkey: \(settings.hotkey.displayString) (keyCode=\(settings.hotkey.keyCode), modifiers=\(settings.hotkey.modifiers))")

        // Unregister old hotkeys and register new ones
        hotKeyManager.unregisterAll()
        pttHotKeyManager.unregisterAll()
        speakSelectionHotKeyManager.unregisterAll()
        walkieHotKeyManager.unregisterAll()
        unregisterCaptureHotkeys()
        registerHotkeys()
        registerSelectionQuickHotkey()
        registerCaptureHotkeys()

        // Track current config for debounce comparison
        lastHotkey = settings.hotkey
        lastPTTHotkey = settings.pttHotkey
        lastPTTEnabled = settings.pttEnabled
        lastSelectionQuickHotkey = settings.selectionQuickHotkey

        refreshHotkeyManagerDiagnostics(
            pttEnabled: settings.pttEnabled,
            ambientEnabled: TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureAmbientModeEnabled)
        )

        // Update menu item key equivalent
        updateMenuKeyEquivalent()
    }

    @objc private func userDefaultsDidChange() {
        guard BootSequence.shared.isComplete else { return }

        // UserDefaults.didChangeNotification fires on every write, not just hotkey settings.
        // Only re-register if the hotkey config actually changed.
        let settings = LiveSettings.shared
        guard settings.hotkey != lastHotkey ||
              settings.pttHotkey != lastPTTHotkey ||
              settings.pttEnabled != lastPTTEnabled ||
              settings.selectionQuickHotkey != lastSelectionQuickHotkey else {
            return  // No change
        }

        log.info("Hotkey config changed via UserDefaults — re-registering")
        hotkeyDidChange()
    }

    @objc private func sharedHotkeysDidChange(_ notification: Notification) {
        let sharedConfig = Self.loadHotkeyConfig(
            key: AgentSettingsKey.selectionQuickHotkey,
            fallbackKeyCode: HotkeyConfig.defaultSelectionQuick.keyCode,
            fallbackModifiers: HotkeyConfig.defaultSelectionQuick.modifiers
        )
        let config = HotkeyConfig(keyCode: sharedConfig.keyCode, modifiers: sharedConfig.modifiers)
        let settings = LiveSettings.shared

        if settings.selectionQuickHotkey != config {
            settings.selectionQuickHotkey = config
        }

        if let action = notification.object as? String {
            log.info("Shared hotkey change received for \(action) — refreshing registrations")
        } else {
            log.info("Shared hotkey change received — refreshing registrations")
        }

        hotkeyDidChange()
    }

    private func updateMenuKeyEquivalent() {
        guard let menu = statusItem.menu else {
            return
        }

        guard let recordItem = menu.items.first(where: { $0.action == #selector(toggleListeningFromMenu) }) else {
            return
        }

        let settings = LiveSettings.shared
        let config = settings.hotkey

        // Update modifiers
        var modifiers: NSEvent.ModifierFlags = []
        if config.modifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        if config.modifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if config.modifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if config.modifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }

        recordItem.keyEquivalentModifierMask = modifiers

        // Update key equivalent (simplified - just common keys)
        let keyMap: [UInt32: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m"
        ]
        recordItem.keyEquivalent = keyMap[config.keyCode] ?? ""

        if let speakSelectionItem = menu.items.first(where: { $0.action == #selector(speakSelectionFromMenu) }) {
            let selectionConfig = settings.selectionQuickHotkey
            var selectionModifiers: NSEvent.ModifierFlags = []
            if selectionConfig.modifiers & UInt32(cmdKey) != 0 { selectionModifiers.insert(.command) }
            if selectionConfig.modifiers & UInt32(optionKey) != 0 { selectionModifiers.insert(.option) }
            if selectionConfig.modifiers & UInt32(controlKey) != 0 { selectionModifiers.insert(.control) }
            if selectionConfig.modifiers & UInt32(shiftKey) != 0 { selectionModifiers.insert(.shift) }

            speakSelectionItem.keyEquivalentModifierMask = selectionModifiers
            speakSelectionItem.keyEquivalent = keyMap[selectionConfig.keyCode] ?? ""
        }

        // Update tooltip too
        updateStatusBarTooltip()
    }

    private func updateStatusBarTooltip() {
        guard let button = statusItem.button else { return }
        let shortcut = LiveSettings.shared.hotkey.displayString
        button.toolTip = "Talkie Agent (\(shortcut) to record)"
    }

    @objc private func toggleListeningFromMenu() {
        toggleListening(interstitial: false, hotkeyTimestamp: nil)
    }

    private func toggleListening(interstitial: Bool, hotkeyTimestamp: HotKeyTimestamp? = nil) {
        log.debug("toggleListening called: interstitial=\(interstitial)")
        Task {
            log.debug("Calling agentController.toggleListening...")
            await agentController.toggleListening(interstitial: interstitial, hotkeyTimestamp: hotkeyTimestamp)
            log.debug("agentController.toggleListening completed")
        }
    }

    private func trackSelectionSourceApp() {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalSelectionSourceApp = frontApp
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return
            }

            self.lastExternalSelectionSourceApp = app
        }
    }

    private func selectionSourceApp() -> NSRunningApplication? {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            return frontApp
        }

        return lastExternalSelectionSourceApp
    }

    /// Capture selected text from the frontmost app and open Talkie Compose with it.
    /// Selected text is a nice-to-have — Compose always opens, with or without text.
    private func sendSelectedTextToCompose() {
        log.info("Attempting to capture selected text for Compose")

        let sourceApp = selectionSourceApp()

        // Try to get selected text — AX first, then clipboard fallback for terminals
        let selectedText = ContextCaptureService.shared.getSelectedText(in: sourceApp)
            ?? ContextCaptureService.shared.getSelectedTextViaClipboard(in: sourceApp)

        if let text = selectedText, !text.isEmpty {
            log.info("Captured \(text.count) chars - opening Talkie Compose")

            if let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "\(TalkieEnvironment.current.talkieURLScheme)://compose?text=\(encodedText)") {
                NSWorkspace.shared.open(url)
                return
            }
        }

        // No text or encoding failed — still open Compose
        log.debug("No selected text found - opening Compose without text")
        if let url = URL(string: "\(TalkieEnvironment.current.talkieURLScheme)://compose") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Capture selected text from the frontmost app and ask Talkie to speak it.
    private func speakSelectedText() {
        log.info("Attempting to capture selected text for speech")

        let sourceApp = selectionSourceApp()
        let selectedText = ContextCaptureService.shared.getSelectedText(in: sourceApp)
            ?? ContextCaptureService.shared.getSelectedTextViaClipboard(in: sourceApp)

        if let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            runSpeakSelectionPipeline(text: text, sourceApp: sourceApp, source: .highlighted)
            return
        }

        // AX + clipboard both empty. Offer OCR region-picker fallback if enabled.
        let ocrEnabled = TalkieSharedSettings.object(forKey: AgentSettingsKey.selectionOCRFallbackEnabled) as? Bool ?? true
        guard ocrEnabled else {
            log.info("Quick selection aborted: no selected text found (OCR fallback disabled)")
            selectionFeedbackController.show(
                SelectionFeedbackMessage(
                    title: "No text selected",
                    detail: "Highlight text first, then run Quick Selection.",
                    tone: .warning,
                    actionTitle: nil,
                    action: nil
                ),
                duration: 1.8
            )
            return
        }

        log.info("Quick selection falling back to OCR region picker")
        selectionFeedbackController.show(
            SelectionFeedbackMessage(
                title: "Draw a region to read",
                detail: "Couldn't grab selected text — pick visually.",
                tone: .neutral,
                actionTitle: nil,
                action: nil
            ),
            duration: 1.4
        )

        Task { @MainActor in
            guard let ocrText = await SelectionOCRFlow.shared.capture()?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !ocrText.isEmpty else {
                log.info("OCR fallback returned no text")
                return
            }
            runSpeakSelectionPipeline(text: ocrText, sourceApp: sourceApp, source: .ocr)
        }
    }

    /// Origin of the selection text flowing into the speak pipeline.
    private enum SelectionTextSource {
        case highlighted
        case ocr
    }

    /// Shared downstream pipeline: LLM prep → TTS → persistence.
    /// Callers are responsible for having produced a non-empty trimmed `text`.
    private func runSpeakSelectionPipeline(
        text: String,
        sourceApp: NSRunningApplication?,
        source: SelectionTextSource
    ) {
        let sourceLabel = sourceApp?.localizedName ?? "Current App"
        log.info(
            "Quick selection started",
            detail: "app=\(sourceLabel) chars=\(text.count) source=\(source == .ocr ? "ocr" : "highlighted")"
        )

        Task { @MainActor in
            let startTime = CFAbsoluteTimeGetCurrent()
            let recordingId = UUID()

            // Kick off screenshot capture in parallel (async, just the source window)
            let screenshotTask: Task<RecordingScreenshot?, Never>?
            if let app = sourceApp,
               TalkieSharedSettings.object(forKey: AgentSettingsKey.selectionCaptureScreenshot) as? Bool ?? false {
                screenshotTask = Task.detached {
                    await Self.captureWindowScreenshotAsync(for: app, recordingId: recordingId)
                }
            } else {
                screenshotTask = nil
            }

            do {
                // LLM processing
                let result = try await SelectionQuickProcessor.shared.process(text: text, sourceApp: sourceApp)
                let statusTitle: String
                switch result.mode {
                case .verbatim:
                    statusTitle = "Reading"
                case .summary:
                    statusTitle = "Summarizing"
                case .explanation:
                    statusTitle = "Explaining"
                }
                let processingMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                log.info(
                    "Quick selection prepared",
                    detail: "mode=\(String(describing: result.mode)) inputChars=\(text.count) outputChars=\(result.text.count) ms=\(processingMs)"
                )

                showSelectionFeedback(
                    title: statusTitle,
                    detail: nil,
                    tone: .neutral,
                    actionTitle: nil,
                    action: nil
                )

                // TTS readback (measure precisely). Persistence should not depend
                // on audio playback: if TTS fails, this is still a valid capture.
                let ttsStart = CFAbsoluteTimeGetCurrent()
                let playbackResult: SelectionSpeechPlaybackResult?
                let ttsError: String?
                do {
                    playbackResult = try await speechPlaybackController.speakSelection(result.text)
                    ttsError = nil
                } catch {
                    playbackResult = nil
                    ttsError = error.localizedDescription
                    log.error("Quick selection TTS failed", detail: error.localizedDescription, error: error)
                    selectionFeedbackController.show(
                        SelectionFeedbackMessage(
                            title: "Speech failed",
                            detail: "Saved to captures. \(error.localizedDescription)",
                            tone: .failure,
                            actionTitle: nil,
                            action: nil
                        ),
                        duration: 2.3
                    )
                }
                let ttsMs = Int((CFAbsoluteTimeGetCurrent() - ttsStart) * 1000)

                // Collect screenshot (should be done by now — it runs in parallel)
                let screenshot = await screenshotTask?.value

                // Store as a Selection TalkieObject
                let endToEndMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                let storedVoiceId = TalkieSharedSettings.string(forKey: AgentSettingsKey.selectionTTSVoiceId)
                    ?? TalkieSharedSettings.string(forKey: AgentSettingsKey.selectedTTSVoiceId)
                    ?? "system"
                let voiceId = playbackResult?.voiceId ?? (storedVoiceId.hasPrefix("kokoro:") ? "system" : storedVoiceId)
                storeSelectionObject(
                    recordingId: recordingId,
                    inputText: text,
                    outputText: result.text,
                    result: result,
                    sourceApp: sourceApp,
                    voiceId: voiceId,
                    processingMs: processingMs,
                    ttsMs: ttsMs,
                    endToEndMs: endToEndMs,
                    screenshot: screenshot,
                    ttsError: ttsError
                )
            } catch {
                log.error("Speak selection failed", detail: error.localizedDescription, error: error)
                selectionFeedbackController.show(
                    SelectionFeedbackMessage(
                        title: "Speech failed",
                        detail: error.localizedDescription,
                        tone: .failure,
                        actionTitle: nil,
                        action: nil
                    ),
                    duration: 2.3
                )
            }
        }
    }

    @objc private func speakSelectionFromMenu() {
        speakSelectedText()
    }

    private func storeSelectionObject(
        recordingId: UUID,
        inputText: String,
        outputText: String,
        result: SelectionQuickResult,
        sourceApp: NSRunningApplication?,
        voiceId: String,
        processingMs: Int,
        ttsMs: Int,
        endToEndMs: Int,
        screenshot: RecordingScreenshot?,
        ttsError: String? = nil
    ) {
        let keepHistoryEnabled = TalkieSharedSettings.object(forKey: AgentSettingsKey.selectionKeepHistory) as? Bool ?? true
        guard keepHistoryEnabled || result.shouldPersist else {
            return
        }

        // Build service call records
        var calls: [ServiceCallRecord] = []

        // LLM call (if not verbatim)
        if let prompt = result.systemPrompt, result.mode != .verbatim {
            var messages: [ServiceCallMessage] = []
            messages.append(ServiceCallMessage(role: "system", content: prompt))
            messages.append(ServiceCallMessage(role: "user", content: inputText))

            calls.append(ServiceCallRecord(
                kind: "llm",
                provider: result.llmProvider ?? "unknown",
                model: result.llmModel,
                endpoint: "chat/completions",
                messages: messages,
                response: outputText,
                latencyMs: result.llmLatencyMs,
                status: "success"
            ))
        }

        // TTS call
        let ttsProvider: String
        let ttsModel: String?
        if voiceId.hasPrefix("openai:") {
            ttsProvider = "openai"
            ttsModel = OpenAISpeechService.model
        } else if voiceId.hasPrefix("elevenlabs:") {
            ttsProvider = "elevenlabs"
            ttsModel = ElevenLabsSpeechService.model
        } else {
            ttsProvider = "apple"
            ttsModel = nil
        }

        calls.append(ServiceCallRecord(
            kind: "tts",
            provider: ttsProvider,
            model: ttsModel,
            endpoint: "audio/speech",
            inputText: String(outputText.prefix(500)),
            latencyMs: ttsMs,
            status: ttsError == nil ? "success" : "failed",
            error: ttsError
        ))

        let metadata = RecordingMetadata(
            app: AppContext(
                bundleId: sourceApp?.bundleIdentifier,
                name: sourceApp?.localizedName,
                windowTitle: nil
            ),
            performance: PerformanceMetrics(
                engineMs: processingMs,
                endToEndMs: endToEndMs
            ),
            selection: SelectionInfo(
                inputText: inputText,
                mode: result.mode.rawValue,
                voiceId: voiceId,
                delivery: ttsError == nil ? "speak" : "capture",
                llmPrompt: result.prompt,
                llmResponse: result.mode != .verbatim ? outputText : nil,
                llmModel: result.llmModel,
                llmProvider: result.llmProvider,
                processingMs: processingMs,
                endToEndMs: endToEndMs,
                contextRuleName: result.contextRuleName
            ),
            serviceCalls: calls
        )

        var recording = LiveRecording(
            id: recordingId,
            text: outputText,
            duration: 0,
            transcriptionStatus: "success"
        )
        recording.type = "selection"
        recording.source = "live"
        recording.sourceDeviceId = nil
        recording.metadataJSON = metadata.toJSON()

        if let screenshot {
            let assets = TalkieObjectAssets(screenshots: [screenshot])
            recording.assetsJSON = assets.toJSON()
        }

        if let id = UnifiedDatabase.store(recording) {
            log.info("Selection stored", detail: "id=\(id.uuidString.prefix(8)) mode=\(result.mode.rawValue) chars=\(outputText.count) screenshot=\(screenshot != nil)")
            TalkieAgentXPCService.shared.notifyDictationAdded()
        } else {
            log.warning("Failed to store selection object")
        }
    }

    /// Async window screenshot capture — runs on a detached task, captures just the source app window
    private static func captureWindowScreenshotAsync(for app: NSRunningApplication, recordingId: UUID) async -> RecordingScreenshot? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Find the frontmost (topmost in window order) window for this app
            // SCShareableContent returns windows in front-to-back order
            guard let window = content.windows
                .filter({
                    $0.owningApplication?.processID == app.processIdentifier
                    && $0.isOnScreen
                    && $0.frame.width > 100
                    && $0.frame.height > 100
                })
                .first  // First match = frontmost window
            else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.captureResolution = .best
            config.scalesToFit = false
            // Let ScreenCaptureKit auto-size to the window at native resolution
            // Don't set explicit width/height — that can cause full-display capture

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            // Encode directly from CGImage; NSBitmapImageRep can lose orientation context in the round-trip.
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, cgImage, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
            guard let savedURL = ScreenshotStorage.save(
                data as Data,
                recordingId: recordingId,
                timestampMs: 0,
                capturedAt: Date(),
                captureMode: "window",
                width: cgImage.width,
                height: cgImage.height,
                windowTitle: window.title,
                appName: app.localizedName
            ) else { return nil }

            return RecordingScreenshot(
                filename: savedURL.lastPathComponent,
                timestampMs: 0,
                captureMode: "window",
                width: cgImage.width,
                height: cgImage.height,
                windowTitle: window.title,
                appName: app.localizedName
            )
        } catch {
            Log(.system).warning("Selection screenshot failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func selectionCaptureUserInfo() -> [AnyHashable: Any]? {
        let sourceApp = selectionSourceApp()
        let selectedText = ContextCaptureService.shared.getSelectedText(in: sourceApp)
            ?? ContextCaptureService.shared.getSelectedTextViaClipboard(in: sourceApp)

        guard let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        return [
            "selectionText": text,
            "selectionAppName": sourceApp?.localizedName ?? "",
            "selectionBundleID": sourceApp?.bundleIdentifier ?? "",
            "selectionWindowTitle": sourceApp?.localizedName ?? ""
        ]
    }

    private func toggleAmbientMode() {
        let wasEnabled = AmbientController.shared.state != .disabled
        log.info("Toggling ambient mode (currently \(wasEnabled ? "enabled" : "disabled"))")
        AmbientController.shared.toggle()
    }

    @objc private func toggleAmbientModeFromMenu(_ sender: NSMenuItem) {
        toggleAmbientMode()
        sender.state = AmbientSettings.shared.isEnabled ? .on : .off
    }

    @objc private func clearFailedQueue() {
        let count = UnifiedDatabase.countQueued()
        guard count > 0 else {
            log.info("No failed items to clear")
            return
        }

        TranscriptionRetryManager.shared.clearPending()
        log.info("Cleared \(count) failed transcriptions from queue")
    }

    @objc private func rebootAudioSystem() {
        log.info("════════════════════════════════════════════════════════════")
        log.info("🔄 MANUAL AUDIO REBOOT requested from menu")
        log.info("════════════════════════════════════════════════════════════")
        Task { @MainActor in
            // Show "rebooting" toast
            showToast(emoji: "🔄", message: "Rebooting audio...", color: .systemBlue)

            // Perform reboot and get result
            let result = await agentController.rebootAudio()

            // Show result toast after a brief delay so user sees the transition
            try? await Task.sleep(for: .milliseconds(300))

            switch result {
            case .success:
                showToast(emoji: "✅", message: "Audio ready", color: .systemGreen)
            case .successDegraded:
                showToast(emoji: "⚠️", message: "Audio ready (HAL slow)", color: .systemOrange)
            case .failed:
                showToast(emoji: "❌", message: "Audio reboot failed", color: .systemRed)
            }
        }
    }

    @objc private func toggleStreamingWakeFromMenu(_ sender: NSMenuItem) {
        let newValue = !AmbientSettings.shared.useStreamingASR
        AmbientSettings.shared.useStreamingASR = newValue
        sender.state = newValue ? .on : .off
        log.info("Streaming wake detection: \(newValue ? "enabled" : "disabled")")

        // If ambient is currently running, it will pick up the change via the settings binding
    }

    @objc private func showHistory() {
        // Show lightweight history panel within TalkieAgent
        HistoryPanelController.shared.show()
    }

    // MARK: - Recent Dictations

    @objc private func copyRecentDictation(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        log.info("Copied dictation to clipboard: \(text.prefix(30))...")
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            self.updateRecentMenu()
            self.updatePermissionsMenuItem()
            self.updateAmbientMenuItem()
            self.updateStreamingMenuItem()
            self.updateClearQueueMenuItem()
        }
    }

    private func updateAmbientMenuItem() {
        guard let menu = statusItem.menu,
              let ambientItem = menu.items.first(where: { $0.action == #selector(toggleAmbientModeFromMenu) }) else {
            return
        }
        ambientItem.state = AmbientSettings.shared.isEnabled ? .on : .off
    }

    private func updateStreamingMenuItem() {
        guard let menu = statusItem.menu,
              let streamingItem = menu.items.first(where: { $0.action == #selector(toggleStreamingWakeFromMenu) }) else {
            return
        }
        streamingItem.state = AmbientSettings.shared.useStreamingASR ? .on : .off
    }

    private func updateClearQueueMenuItem() {
        guard let menu = statusItem.menu,
              let clearItem = menu.items.first(where: { $0.action == #selector(clearFailedQueue) }) else {
            return
        }
        let count = UnifiedDatabase.countQueued()
        if count > 0 {
            clearItem.title = "Clear Failed Queue (\(count))"
            clearItem.isHidden = false
        } else {
            clearItem.isHidden = true
        }
    }

    private func updatePermissionsMenuItem() {
        guard let menu = statusItem.menu,
              let permissionsItem = menu.items.first(where: { $0.action == #selector(showPermissions) }) else {
            return
        }

        // Refresh permission state and update menu item
        PermissionManager.shared.refreshAll()
        if PermissionManager.shared.allRequiredGranted {
            permissionsItem.title = "Permissions..."
        } else {
            permissionsItem.title = "⚠️ Permissions..."
        }
    }

    private func updateRecentMenu() {
        guard let menu = statusItem.menu,
              let recentItem = menu.items.first(where: { $0.title == "Recent" }),
              let submenu = recentItem.submenu else { return }

        submenu.removeAllItems()

        Task { @MainActor in
            let store = DictationStore.shared
            let recent = Array(store.utterances.prefix(5))

            if recent.isEmpty {
                let emptyItem = NSMenuItem(title: "No recent dictations", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                submenu.addItem(emptyItem)
            } else {
                for (index, utterance) in recent.enumerated() {
                    // Truncate text for display
                    let displayText = utterance.text.prefix(40) + (utterance.text.count > 40 ? "..." : "")
                    let timeAgo = utterance.timestamp.timeAgoShort

                    let item = NSMenuItem(
                        title: "\(displayText)",
                        action: #selector(copyRecentDictation(_:)),
                        keyEquivalent: index < 3 ? "\(index + 1)" : ""
                    )
                    if index < 3 {
                        item.keyEquivalentModifierMask = [.control, .option]
                    }
                    item.target = self
                    item.representedObject = utterance.text
                    item.toolTip = "\(timeAgo) • Click to copy"
                    submenu.addItem(item)
                }

                submenu.addItem(NSMenuItem.separator())
                let showAllItem = NSMenuItem(title: "Show All History...", action: #selector(showHistory), keyEquivalent: "")
                showAllItem.target = self
                submenu.addItem(showAllItem)
            }
        }
    }

    @objc private func toggleFloatingPill(_ sender: NSMenuItem) {
        floatingPill.toggle()
        sender.state = floatingPill.isVisible ? .on : .off
    }

    private func configureSelectionFeedback() {
        speechPlaybackController.onPlaybackStarted = { [weak self] in
            Task { @MainActor in
                self?.showSelectionFeedback(
                    title: "Speaking",
                    detail: nil,
                    tone: .active,
                    actionTitle: nil,
                    action: nil
                )
            }
        }

        speechPlaybackController.onPlaybackFinished = { [weak self] in
            Task { @MainActor in
                log.info("Quick selection playback finished")
                self?.selectionFeedbackController.dismiss()
            }
        }
    }

    private func showSelectionFeedback(
        title: String,
        detail: String?,
        tone: SelectionFeedbackMessage.Tone,
        actionTitle: String?,
        action: (() -> Void)?
    ) {
        selectionFeedbackController.show(
            SelectionFeedbackMessage(
                title: title,
                detail: detail,
                tone: tone,
                actionTitle: actionTitle,
                action: action
            )
        )
    }

    // MARK: - Toast Notifications

    /// Show a brief toast notification to the user
    /// - Parameters:
    ///   - emoji: Emoji to display
    ///   - message: Message text
    ///   - color: Background color
    ///   - duration: How long to show (default 2s)
    private func showToast(emoji: String, message: String, color: NSColor, duration: TimeInterval = 2.0) {
        let text = "\(emoji) \(message)"

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 16
        let width = label.frame.width + padding * 2
        let height: CGFloat = 36

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = color.withAlphaComponent(0.9).cgColor

        label.frame = NSRect(x: padding, y: (height - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        container.addSubview(label)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.contentView = container
        window.hasShadow = true

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.midY + 100
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)

        // Auto dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        }
    }

    #if DEBUG
    // MARK: - TextInserter Debug Test

    /// Debug function to test TextInserter paste in isolation (Command+Shift+P)
    private func testTextInserterPaste() {
        let testText = "[TextInserter test: \(Date().formatted(date: .omitted, time: .standard))]"
        log.info("🧪 Testing TextInserter with: \(testText)")

        Task { @MainActor in
            let success = await TextInserter.shared.insert(testText, intoAppWithBundleID: nil, replaceSelection: false)

            if success {
                log.info("✅ TextInserter test PASSED - text should be inserted")
                showTextInserterToast(success: true, message: "Insert succeeded")
            } else {
                log.error("❌ TextInserter test FAILED - check if target has focus")
                showTextInserterToast(success: false, message: "Insert failed")
            }
        }
    }

    private func showTextInserterToast(success: Bool, message: String) {
        showToast(
            emoji: success ? "✅" : "❌",
            message: message,
            color: success ? .systemGreen : .systemRed
        )
    }
    #endif

    // MARK: - Quit

    @objc private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Talkie Agent?"
        alert.informativeText = "The agent will stay off until you restart your Mac or relaunch from the Talkie app."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            log.info("User confirmed quit - booting out launch agent")
            let env = TalkieEnvironment.current
            let uid = getuid()
            // Dev uses XPC service name as launchd label; production uses bundle ID
            for label in [TalkieHelper.agent.xpcServiceName(for: env), TalkieHelper.agent.bundleId(for: env)] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["bootout", "gui/\(uid)/\(label)"]
                try? process.run()
                process.waitUntilExit()
            }
            NSApp.terminate(nil)
        }
    }

    @objc private func showOnboarding() {
        OnboardingManager.shared.resetOnboarding()
        OnboardingManager.shared.shouldShowOnboarding = true
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsAction() {
        showSettings(tab: .shortcuts)
    }

    private func showSettings(tab: QuickSettingsTab) {
        log.debug("showSettings(tab: \(tab.title)) called")

        // If window already exists and is visible, bring it to front
        if let window = settingsWindow, window.isVisible {
            log.debug("Reusing existing settings window")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Close old window if it exists but isn't visible
        settingsWindow?.close()
        settingsWindow = nil

        log.debug("Creating new settings window")

        // Create focused settings window (Capture + Output + Permissions)
        let contentView = QuickSettingsView(initialTab: tab)
            .frame(minWidth: 650, minHeight: 550)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Store reference
        settingsWindow = window

        // Show in Dock/Cmd+Tab while window is open
        NSApp.setActivationPolicy(.regular)

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPermissions() {
        // If window already exists and is visible, just switch to permissions tab
        if let window = settingsWindow, window.isVisible {
            let contentView = QuickSettingsView(initialTab: .permissions)
                .frame(minWidth: 650, minHeight: 550)
            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Close old window if it exists but isn't visible
        settingsWindow?.close()
        settingsWindow = nil

        // Create settings window with permissions tab selected
        let contentView = QuickSettingsView(initialTab: .permissions)
            .frame(minWidth: 650, minHeight: 550)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Store in settings window (consolidate into one window)
        settingsWindow = window

        // Show in Dock/Cmd+Tab while window is open
        NSApp.setActivationPolicy(.regular)

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }

        // Return to menu bar app mode (no Dock icon)
        settingsWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func updateIcon(for state: LiveState) {
        guard let button = statusItem.button else { return }

        // Update icon based on state:
        // - Idle: mic icon (template, follows system appearance)
        // - Listening: waveform icon with subtle red tint
        // - Transcribing/Routing: waveform icon (processing)
        let isRecording = state == .listening
        let isProcessing = state == .transcribing || state == .routing

        updateMenuBarIcon(isRecording: isRecording || isProcessing)

        // Clear any text suffix (no more big dot)
        button.title = ""

        // Update menu item text
        updateRecordingMenuItem(isRecording: isRecording)
    }

    /// Update the "Start Recording" / "Stop Recording" menu item
    private func updateRecordingMenuItem(isRecording: Bool) {
        guard let menu = statusItem.menu,
              let recordItem = menu.items.first(where: { $0.action == #selector(toggleListeningFromMenu) }) else {
            return
        }
        recordItem.title = isRecording ? "Stop Recording" : "Start Recording"
    }

    private func showQueuePicker() {
        // Only show if there are queued items
        let queuedCount = UnifiedDatabase.countQueued()
        guard queuedCount > 0 else {
            // Could play a "nothing queued" sound here
            return
        }

        QueuePickerController.shared.show()
    }

    // MARK: - Model Preloading

    /// Preload model via the embedded engine hosted inside TalkieAgent.
    private func preloadModel(settings: LiveSettings) async {
        let modelId = settings.selectedModelId
        log.info("Loading model", detail: modelId)
        let loadStart = Date()

        let client = EngineClient.shared
        let engineConnected = await client.ensureConnected()

        guard engineConnected else {
            log.error("Embedded engine failed to start")
            return
        }

        log.info("Embedded engine ready")
        await client.refreshAvailableModels()

        guard client.availableModels.contains(where: { $0.id == modelId && $0.isDownloaded }) else {
            log.info("Skipping preload for undownloaded model", detail: modelId)
            return
        }

        do {
            try await client.preloadModel(modelId)
            let totalTime = Date().timeIntervalSince(loadStart)
            log.info("Model ready (Embedded Engine)", detail: String(format: "%.1fs total", totalTime))
        } catch {
            log.error("Embedded engine preload failed", detail: error.localizedDescription)
        }
    }
}

@MainActor
struct SelectionSpeechPlaybackResult {
    let voiceId: String
    let provider: String
    let model: String?
}

@MainActor
final class SelectionSpeechPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = SelectionSpeechPlaybackController()

    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var audioLevel: Float = 0

    var hasPlaybackSession: Bool {
        audioPlayer != nil || isPaused || isPlaying
    }

    private var audioPlayer: AVAudioPlayer?
    private var meterTimer: Timer?
    private var renderedSpeechSynthesizer: AVSpeechSynthesizer?
    var onPlaybackStarted: (() -> Void)?
    var onPlaybackFinished: (() -> Void)?

    private override init() { super.init() }

    func speakSelection(_ text: String) async throws -> SelectionSpeechPlaybackResult {
        stopPlayback(notify: false)

        var lastError: Error?
        for voiceId in candidateVoiceIDs() {
            do {
                let synthesis = try await synthesizeSelection(text: text, selectedVoiceId: voiceId)
                try playAudioFile(at: synthesis.audioURL)
                if synthesis.voiceId != voiceId {
                    log.info("Quick selection TTS used normalized voice", detail: "requested=\(voiceId) used=\(synthesis.voiceId)")
                }
                return SelectionSpeechPlaybackResult(
                    voiceId: synthesis.voiceId,
                    provider: synthesis.provider,
                    model: synthesis.model
                )
            } catch {
                lastError = error
                log.warning("Quick selection TTS candidate failed", detail: "voice=\(voiceId) error=\(error.localizedDescription)")
            }
        }

        throw lastError ?? SelectionSpeechError.audioPlaybackUnavailable
    }

    private func playAudioFile(at url: URL) throws {
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.enableRate = true
        player.isMeteringEnabled = true
        player.prepareToPlay()

        guard player.play() else {
            throw SelectionSpeechError.audioPlaybackUnavailable
        }

        audioPlayer = player
        isPlaying = true
        isPaused = false
        startMetering()
        notifyPlaybackStarted()
    }

    private func normalizeSelectionVoiceId(_ voiceId: String) -> String {
        voiceId.hasPrefix("kokoro:") ? "system" : voiceId
    }

    private struct SpeechSynthesisResult {
        let audioURL: URL
        let voiceId: String
        let provider: String
        let model: String?
    }

    private func candidateVoiceIDs() -> [String] {
        let selectionVoiceId = TalkieSharedSettings.string(forKey: AgentSettingsKey.selectionTTSVoiceId)
        let globalVoiceId = TalkieSharedSettings.string(forKey: AgentSettingsKey.selectedTTSVoiceId)
        let hasOpenAIKey = TalkieSharedSettings.string(forKey: AgentSettingsKey.openaiApiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let hasElevenLabsKey = TalkieSharedSettings.string(forKey: AgentSettingsKey.elevenLabsApiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        var candidates: [String] = []

        func append(_ voiceId: String?) {
            guard let voiceId else { return }
            let normalized = normalizeSelectionVoiceId(voiceId)
            guard !normalized.isEmpty, !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }

        append(selectionVoiceId)
        append(globalVoiceId)

        if hasOpenAIKey {
            append("openai:alloy")
        }
        if hasElevenLabsKey {
            append("elevenlabs:21m00Tcm4TlvDq8ikWAM")
        }
        append("system")

        return candidates
    }

    private func synthesizeSelection(text: String, selectedVoiceId: String) async throws -> SpeechSynthesisResult {
        if selectedVoiceId.hasPrefix("openai:") {
            let voiceId = String(selectedVoiceId.dropFirst("openai:".count))
            let apiKey = TalkieSharedSettings.string(forKey: AgentSettingsKey.openaiApiKey)
            let audioURL = try await OpenAISpeechService.synthesize(text: text, voice: voiceId, apiKey: apiKey)
            return SpeechSynthesisResult(
                audioURL: audioURL,
                voiceId: selectedVoiceId,
                provider: "openai",
                model: OpenAISpeechService.model
            )
        }

        if selectedVoiceId.hasPrefix("elevenlabs:") {
            let voiceId = String(selectedVoiceId.dropFirst("elevenlabs:".count))
            let apiKey = TalkieSharedSettings.string(forKey: AgentSettingsKey.elevenLabsApiKey)
            let audioURL = try await ElevenLabsSpeechService.synthesize(text: text, voiceId: voiceId, apiKey: apiKey)
            return SpeechSynthesisResult(
                audioURL: audioURL,
                voiceId: selectedVoiceId,
                provider: "elevenlabs",
                model: ElevenLabsSpeechService.model
            )
        }

        let audioURL = try await synthesizeAppleSpeechToFile(text: text, selectedVoiceId: selectedVoiceId)
        return SpeechSynthesisResult(
            audioURL: audioURL,
            voiceId: "system",
            provider: "apple",
            model: nil
        )
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        }
    }

    private func pause() {
        guard let audioPlayer, audioPlayer.isPlaying else { return }
        audioPlayer.pause()
        stopMetering()
        audioLevel = 0
        isPlaying = false
        isPaused = true
    }

    private func resume() {
        guard let audioPlayer, isPaused else { return }
        guard audioPlayer.play() else { return }
        isPlaying = true
        isPaused = false
        startMetering()
    }

    func stop() {
        stopPlayback()
    }

    private func stopPlayback(notify: Bool = true) {
        let hadSession = hasPlaybackSession
        audioPlayer?.stop()
        audioPlayer = nil
        renderedSpeechSynthesizer = nil
        stopMetering()
        audioLevel = 0
        isPlaying = false
        isPaused = false

        if notify && hadSession {
            notifyPlaybackFinished()
        }
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMeters()
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateMeters() {
        guard let audioPlayer else {
            audioLevel = 0
            return
        }
        audioPlayer.updateMeters()
        let averagePower = audioPlayer.averagePower(forChannel: 0)
        let linearLevel = pow(10, averagePower / 20)
        audioLevel = Float(min(max(linearLevel, 0), 1))
    }

    private func synthesizeAppleSpeechToFile(text: String, selectedVoiceId: String) async throws -> URL {
        let utterance = AVSpeechUtterance(string: text)
        if selectedVoiceId.hasPrefix("com.apple.voice"),
           let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceId) {
            utterance.voice = voice
        } else if let englishVoice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = englishVoice
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-selection-\(UUID().uuidString)")
            .appendingPathExtension("caf")

        let synthesizer = AVSpeechSynthesizer()
        renderedSpeechSynthesizer = synthesizer

        return try await withCheckedThrowingContinuation { continuation in
            var audioFile: AVAudioFile?
            var didResume = false

            synthesizer.write(utterance) { buffer in
                guard !didResume else { return }
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                do {
                    if pcmBuffer.frameLength == 0 {
                        didResume = true
                        Task { @MainActor in
                            self.renderedSpeechSynthesizer = nil
                        }
                        if audioFile == nil {
                            continuation.resume(throwing: SelectionSpeechError.audioPlaybackUnavailable)
                        } else {
                            continuation.resume(returning: outputURL)
                        }
                        return
                    }

                    if audioFile == nil {
                        audioFile = try AVAudioFile(
                            forWriting: outputURL,
                            settings: pcmBuffer.format.settings,
                            commonFormat: pcmBuffer.format.commonFormat,
                            interleaved: pcmBuffer.format.isInterleaved
                        )
                    }

                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    didResume = true
                    Task { @MainActor in
                        self.renderedSpeechSynthesizer = nil
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopMetering()
        audioPlayer = nil
        audioLevel = 0
        isPlaying = false
        isPaused = false
        notifyPlaybackFinished()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        log.error("Selection playback decode error", detail: error?.localizedDescription ?? "unknown", error: error)
        stopPlayback()
    }

    private func notifyPlaybackStarted() {
        onPlaybackStarted?()
    }

    private func notifyPlaybackFinished() {
        onPlaybackFinished?()
    }
}

private enum SelectionSpeechError: LocalizedError {
    case missingElevenLabsKey
    case missingOpenAIKey
    case audioPlaybackUnavailable
    case elevenLabsRejected(String)
    case openAIRejected(String)

    var errorDescription: String? {
        switch self {
        case .missingElevenLabsKey:
            return "Add an ElevenLabs API key in Settings to use that voice."
        case .missingOpenAIKey:
            return "Add an OpenAI API key in Settings to use that voice."
        case .audioPlaybackUnavailable:
            return "The generated audio could not be played."
        case .elevenLabsRejected(let message):
            return message
        case .openAIRejected(let message):
            return message
        }
    }
}

private struct SelectionQuickResult {
    enum Mode: String {
        case verbatim
        case summary
        case explanation
    }

    let text: String
    let mode: Mode
    let prompt: String?              // Full LLM prompt (system + user combined, nil if verbatim)
    let systemPrompt: String?        // System message sent to LLM
    let userPrompt: String?          // User message sent to LLM (the selected text embedded in prompt)
    let llmModel: String?            // Model used for processing
    let llmProvider: String?         // Provider used
    let llmLatencyMs: Int?           // LLM call latency
    let contextRuleName: String?     // File-based rule or context rule name
    let shouldPersist: Bool          // Store even when global history is off
}

@MainActor
private final class SelectionQuickProcessor {
    static let shared = SelectionQuickProcessor()

    private let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.openai.chat"
    ]

    private let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.github.wez.wezterm"
    ]

    private let codeAppBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.apple.dt.Xcode"
    ]

    private let documentBundleIDs: Set<String> = [
        "com.apple.Preview",
        "com.adobe.Reader"
    ]

    private let fileBasedResolver = TalkieSelectionRuleResolver()

    private init() {}

    func process(text: String, sourceApp: NSRunningApplication?) async throws -> SelectionQuickResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let verbatim = {
            SelectionQuickResult(
                text: trimmed,
                mode: .verbatim,
                prompt: nil,
                systemPrompt: nil,
                userPrompt: nil,
                llmModel: nil,
                llmProvider: nil,
                llmLatencyMs: nil,
                contextRuleName: nil,
                shouldPersist: false
            )
        }
        guard !trimmed.isEmpty else { return verbatim() }

        let plan = plan(for: trimmed, sourceApp: sourceApp)
        guard let prompt = plan.prompt else { return verbatim() }

        let registry = LLMProviderRegistry.shared
        let resolved = await registry.resolveProviderAndModel()
        let providerId = resolved?.provider.id
        let modelId = resolved?.modelId

        // The prompt contains a system instruction + the selected text appended
        // Split for structured recording
        let systemPrompt = prompt.components(separatedBy: "\n\nSelected text:").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPrompt = trimmed

        let llmStart = CFAbsoluteTimeGetCurrent()
        do {
            let processed = try await generate(prompt: prompt, timeout: plan.timeout)
            let llmMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1000)
            let cleaned = processed.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                return SelectionQuickResult(
                    text: trimmed,
                    mode: .verbatim,
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    llmModel: modelId,
                    llmProvider: providerId,
                    llmLatencyMs: llmMs,
                    contextRuleName: plan.contextRuleName,
                    shouldPersist: plan.shouldPersist
                )
            }
            return SelectionQuickResult(
                text: cleaned,
                mode: plan.mode,
                prompt: prompt,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                llmModel: modelId,
                llmProvider: providerId,
                llmLatencyMs: llmMs,
                contextRuleName: plan.contextRuleName,
                shouldPersist: plan.shouldPersist
            )
        } catch {
            let llmMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1000)
            log.warning("Selection quick processing fell back to verbatim", detail: error.localizedDescription)
            return SelectionQuickResult(
                text: trimmed,
                mode: .verbatim,
                prompt: prompt,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                llmModel: modelId,
                llmProvider: providerId,
                llmLatencyMs: llmMs,
                contextRuleName: plan.contextRuleName,
                shouldPersist: plan.shouldPersist
            )
        }
    }

    private func plan(for text: String, sourceApp: NSRunningApplication?) -> SelectionPlan {
        if let fileBasedPlan = planFromFileRules(for: text, sourceApp: sourceApp) {
            return fileBasedPlan
        }

        let bundleID = sourceApp?.bundleIdentifier
        let appName = sourceApp?.localizedName?.lowercased() ?? ""
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let characterCount = text.count
        let isShortSelection = wordCount <= 45 && characterCount <= 280

        if let bundleID, terminalBundleIDs.contains(bundleID) {
            return SelectionPlan(
                mode: .explanation,
                prompt: """
                You are helping someone understand a terminal selection quickly.

                Explain the selected text in a concise spoken-friendly way.

                Guidelines:
                - Focus on what happened, what matters, and any obvious next step
                - Keep command names, errors, paths, and numbers accurate
                - Use plain language instead of reading every symbol literally
                - Limit to 3 short sentences

                Selected text:
                \(text)
                """,
                timeout: .seconds(6),
                contextRuleName: nil,
                shouldPersist: false
            )
        }

        if let bundleID, codeAppBundleIDs.contains(bundleID) || appName.contains("cursor") {
            return SelectionPlan(
                mode: .summary,
                prompt: """
                You are helping someone skim a coding-related selection.

                Turn the selected text into a tight spoken summary.

                Guidelines:
                - Prioritize decisions, risks, constraints, and next actions
                - Mention concrete files, systems, or APIs only if they matter
                - Skip filler and restate the gist in plain language
                - Keep it to 4 short sentences maximum

                Selected text:
                \(text)
                """,
                timeout: .seconds(7),
                contextRuleName: nil,
                shouldPersist: false
            )
        }

        if let bundleID, documentBundleIDs.contains(bundleID) || browserBundleIDs.contains(bundleID) {
            if isShortSelection {
                return SelectionPlan(mode: .verbatim, prompt: nil, timeout: .seconds(0), contextRuleName: nil, shouldPersist: false)
            }
            return SelectionPlan(
                mode: .summary,
                prompt: """
                Turn this selection into a short spoken summary.

                Guidelines:
                - Preserve names, dates, numbers, and conclusions
                - Focus on the main point rather than every detail
                - Keep it to 3 or 4 sentences
                - Return only the summary

                Selected text:
                \(text)
                """,
                timeout: .seconds(6),
                contextRuleName: nil,
                shouldPersist: false
            )
        }

        if isShortSelection {
            return SelectionPlan(mode: .verbatim, prompt: nil, timeout: .seconds(0), contextRuleName: nil, shouldPersist: false)
        }

        return SelectionPlan(
            mode: .summary,
            prompt: """
            Create a concise spoken summary of this selected text.

            Guidelines:
            - Keep the most important idea first
            - Preserve important names, dates, and decisions
            - Make it easy to listen to
            - Keep it to 3 short sentences maximum

            Selected text:
            \(text)
            """,
            timeout: .seconds(6),
            contextRuleName: nil,
            shouldPersist: false
        )
    }

    private func planFromFileRules(for text: String, sourceApp: NSRunningApplication?) -> SelectionPlan? {
        let context = TalkieSelectionRuleResolver.Context(
            text: text,
            appName: sourceApp?.localizedName,
            bundleID: sourceApp?.bundleIdentifier
        )

        do {
            guard let plan = try fileBasedResolver.resolve(context: context) else {
                return nil
            }

            return SelectionPlan(
                mode: mode(for: plan.mode),
                prompt: plan.prompt,
                timeout: plan.timeout,
                contextRuleName: plan.ruleName ?? plan.ruleID,
                shouldPersist: plan.shouldPersist
            )
        } catch {
            log.warning("Selection file rule resolution failed", detail: error.localizedDescription)
            return nil
        }
    }

    private func mode(for mode: SelectionMode) -> SelectionQuickResult.Mode {
        switch mode {
        case .verbatim:
            return .verbatim
        case .summary:
            return .summary
        case .explanation:
            return .explanation
        case .auto:
            return .summary
        }
    }

    private func generate(prompt: String, timeout: Duration) async throws -> String {
        let registry = LLMProviderRegistry.shared
        guard let resolved = await registry.resolveProviderAndModel() else {
            throw SelectionSpeechError.elevenLabsRejected("No LLM provider configured for quick selection processing.")
        }

        let options = LLMGenerationOptions(
            temperature: 0.3,
            maxTokens: 512
        )

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await resolved.provider.generate(
                    prompt: prompt,
                    model: resolved.modelId,
                    options: options
                )
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw CancellationError()
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    private struct SelectionPlan {
        let mode: SelectionQuickResult.Mode
        let prompt: String?
        let timeout: Duration
        let contextRuleName: String?
        let shouldPersist: Bool
    }
}

private enum ElevenLabsSpeechService {
    private static let baseURL = URL(string: "https://api.elevenlabs.io/v1/text-to-speech")!
    static let model = "eleven_flash_v2_5"

    private struct RequestBody: Encodable {
        let text: String
        let model_id: String
    }

    static func synthesize(text: String, voiceId: String, apiKey: String?) async throws -> URL {
        guard let apiKey, !apiKey.isEmpty else {
            throw SelectionSpeechError.missingElevenLabsKey
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-elevenlabs-\(UUID().uuidString)")
            .appendingPathExtension("mp3")

        var components = URLComponents(url: baseURL.appendingPathComponent(voiceId), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "output_format", value: "mp3_44100_128")
        ]

        guard let requestURL = components?.url else {
            throw SelectionSpeechError.elevenLabsRejected("Could not build the ElevenLabs request URL.")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            text: text,
            model_id: model
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SelectionSpeechError.elevenLabsRejected("ElevenLabs returned an invalid response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SelectionSpeechError.elevenLabsRejected(
                message?.isEmpty == false ? message! : "ElevenLabs request failed (\(httpResponse.statusCode))."
            )
        }

        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }
}

// MARK: - OpenAI TTS Service

private enum OpenAISpeechService {
    private static let baseURL = URL(string: "https://api.openai.com/v1/audio/speech")!
    static let model = "gpt-4o-mini-tts"

    private struct RequestBody: Encodable {
        let model: String
        let input: String
        let voice: String
        let response_format: String
    }

    static func synthesize(text: String, voice: String, apiKey: String?) async throws -> URL {
        guard let apiKey, !apiKey.isEmpty else {
            throw SelectionSpeechError.missingOpenAIKey
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-openai-tts-\(UUID().uuidString)")
            .appendingPathExtension("mp3")

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            input: text,
            voice: voice,
            response_format: "mp3"
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SelectionSpeechError.openAIRejected("OpenAI returned an invalid response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SelectionSpeechError.openAIRejected(
                message?.isEmpty == false ? message! : "OpenAI TTS request failed (\(httpResponse.statusCode))."
            )
        }

        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }
}

// MARK: - Date Extension

// MARK: - NSImage Tinting Extension

extension NSImage {
    /// Create a copy of the image tinted with the specified color
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}

// MARK: - Date Extension

extension Date {
    var timeAgoShort: String {
        let interval = -self.timeIntervalSinceNow

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        }
    }
}
