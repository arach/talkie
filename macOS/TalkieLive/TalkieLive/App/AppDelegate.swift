import Cocoa
import SwiftUI
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var liveController: LiveController!
    private let hotKeyManager = HotKeyManager()  // Toggle mode hotkey
    private let pttHotKeyManager = HotKeyManager(signature: "TLPT", hotkeyID: 3)  // Push-to-talk hotkey
    private let queuePickerHotKeyManager = HotKeyManager(signature: "TLQP", hotkeyID: 2)
    private var cancellables = Set<AnyCancellable>()

    // Settings window
    private var settingsWindow: NSWindow?

    // Lazy UI controllers - initialized during boot sequence
    private var overlayController: RecordingOverlayController { RecordingOverlayController.shared }
    private var floatingPill: FloatingPillController { FloatingPillController.shared }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app - keep running when windows are closed
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    /// Setup that runs after boot sequence completes
    private func postBootSetup() async {
        let settings = LiveSettings.shared

        // Start XPC service for inter-app communication with Talkie
        TalkieLiveXPCService.shared.startService()

        // Create core pipeline
        let audio = MicrophoneCapture()
        let transcription = EngineTranscriptionService(modelId: settings.selectedModelId)
        let router = TranscriptRouter(mode: settings.routingMode)

        liveController = LiveController(
            audio: audio,
            transcription: transcription,
            router: router
        )

        // Set controller reference in XPC service for remote toggle
        TalkieLiveXPCService.shared.liveController = liveController

        // Pre-load model via Engine (no fallback)
        await preloadModel(settings: settings)

        // Setup UI wiring
        setupStateObservation()
        setupHotkeys()
        setupFloatingPill()

        // Show floating pill on launch
        floatingPill.show()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "🎙"  // Fallback
            }
            updateStatusBarTooltip()
        }
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        let menu = NSMenu()

        let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleListeningFromMenu), keyEquivalent: "")
        recordItem.target = self
        menu.addItem(recordItem)

        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(title: "Show History", action: #selector(showHistory), keyEquivalent: "l")
        historyItem.keyEquivalentModifierMask = [.option, .command]
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        let pillItem = NSMenuItem(title: "Show Floating Pill", action: #selector(toggleFloatingPill), keyEquivalent: "")
        pillItem.target = self
        pillItem.state = .on
        menu.addItem(pillItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboardingItem = NSMenuItem(title: "Show Onboarding...", action: #selector(showOnboarding), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Talkie Live", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Set initial key equivalents from settings
        updateMenuKeyEquivalent()
    }

    // MARK: - State Observation

    private func setupStateObservation() {
        // Observe state changes to update the icon, overlay, and floating pill
        liveController.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
                self?.overlayController.updateState(state)
                self?.floatingPill.updateState(state)
            }
            .store(in: &cancellables)

        // Wire up overlay controls
        overlayController.onStop = { [weak self] in
            Task {
                await self?.liveController.toggleListening()
            }
        }
        overlayController.onCancel = { [weak self] in
            self?.liveController.cancelListening()
        }
    }

    // MARK: - Floating Pill

    private func setupFloatingPill() {
        // Wire up floating pill - tap to toggle recording
        // Shift-click triggers interstitial mode (route to Talkie Core for editing)
        floatingPill.onTapWithShift = { [weak self] shiftHeld in
            self?.toggleListening(interstitial: shiftHeld)
        }

        // Wire up push-to-queue - escape hatch when stuck in transcribing
        floatingPill.onPushToQueue = { [weak self] in
            self?.liveController.pushToQueue()
        }
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        // Register hotkeys from settings
        registerHotkeys()

        // Register queue picker hotkey: ⌥⌘V (Option + Command + V)
        // keyCode 9 = V key
        queuePickerHotKeyManager.registerHotKey(
            modifiers: UInt32(cmdKey | optionKey),
            keyCode: 9
        ) { [weak self] in
            self?.showQueuePicker()
        }

        // Listen for hotkey changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidChange),
            name: .hotkeyDidChange,
            object: nil
        )

        // Listen for toggle recording from status bar button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleListeningFromMenu),
            name: .toggleRecording,
            object: nil
        )
    }

    private func registerHotkeys() {
        let settings = LiveSettings.shared

        // Register toggle hotkey (press to start, press to stop)
        // Note: Hotkey-triggered stops don't check for Shift modifier (intentional)
        hotKeyManager.registerHotKey(
            modifiers: settings.hotkey.modifiers,
            keyCode: settings.hotkey.keyCode
        ) { [weak self] in
            guard let self else { return }
            self.toggleListening(interstitial: false)
        }

        // Register push-to-talk hotkey if enabled
        if settings.pttEnabled {
            pttHotKeyManager.registerHotKey(
                modifiers: settings.pttHotkey.modifiers,
                keyCode: settings.pttHotkey.keyCode,
                onPress: { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.liveController.pttStart()
                    }
                },
                onRelease: { [weak self] in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.liveController.pttStop()
                    }
                }
            )
        }
    }

    @objc private func hotkeyDidChange() {
        // Unregister old hotkeys and register new ones
        hotKeyManager.unregisterAll()
        pttHotKeyManager.unregisterAll()
        registerHotkeys()

        // Update menu item key equivalent
        updateMenuKeyEquivalent()
    }

    private func updateMenuKeyEquivalent() {
        guard let menu = statusItem.menu,
              let recordItem = menu.items.first(where: { $0.action == #selector(toggleListeningFromMenu) }) else {
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

        // Update tooltip too
        updateStatusBarTooltip()
    }

    private func updateStatusBarTooltip() {
        guard let button = statusItem.button else { return }
        let shortcut = LiveSettings.shared.hotkey.displayString
        button.toolTip = "Talkie Live (\(shortcut) to record)"
    }

    @objc private func toggleListeningFromMenu() {
        toggleListening(interstitial: false)
    }

    private func toggleListening(interstitial: Bool) {
        Task {
            await liveController.toggleListening(interstitial: interstitial)
        }
    }

    @objc private func showHistory() {
        // Open Talkie app and navigate to Live section
        let talkieBundleID = "jdi.talkie.core"

        // First, open Talkie app
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true  // Bring to front

        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/Talkie.app"),
            configuration: configuration
        ) { app, error in
            if let error = error {
                AppLogger.shared.log(.error, "Failed to launch Talkie", detail: error.localizedDescription)

                // Fallback: try opening via bundle ID
                NSWorkspace.shared.launchApplication(
                    withBundleIdentifier: talkieBundleID,
                    options: [.default],
                    additionalEventParamDescriptor: nil,
                    launchIdentifier: nil
                )
            }

            // After opening Talkie, navigate to Live section via URL scheme
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let url = URL(string: "talkie://live") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @objc private func toggleFloatingPill(_ sender: NSMenuItem) {
        floatingPill.toggle()
        sender.state = floatingPill.isVisible ? .on : .off
    }

    @objc private func showOnboarding() {
        OnboardingManager.shared.resetOnboarding()
        OnboardingManager.shared.shouldShowOnboarding = true
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        // If settings window already exists, just bring it to front
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create settings view
        let settingsView = EmbeddedSettingsView()
            .frame(minWidth: 800, minHeight: 600)

        // Create hosting controller
        let hostingController = NSHostingController(rootView: settingsView)

        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Talkie Live Settings"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("TalkieLiveSettings")
        window.isReleasedWhenClosed = false

        // Handle window close
        window.delegate = self

        // Store and show
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateIcon(for state: LiveState) {
        guard let button = statusItem.button else { return }

        // Set base image
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            button.image = image
        }

        // Add state indicator as title suffix
        switch state {
        case .idle:
            button.title = ""
        case .listening:
            button.title = " ◉"
        case .transcribing:
            button.title = " ⟳"
        case .routing:
            button.title = " →"
        }
    }

    private func showQueuePicker() {
        // Only show if there are queued items
        let queuedCount = LiveDatabase.countQueued()
        guard queuedCount > 0 else {
            // Could play a "nothing queued" sound here
            return
        }

        QueuePickerController.shared.show()
    }

    // MARK: - Model Preloading

    /// Preload model via TalkieEngine - NO FALLBACK
    /// Engine must be running for TalkieLive to work
    private func preloadModel(settings: LiveSettings) async {
        let modelId = settings.selectedModelId
        AppLogger.shared.log(.system, "Loading model", detail: modelId)
        let loadStart = Date()

        // Connect to TalkieEngine - NO FALLBACK
        let client = EngineClient.shared
        let engineConnected = await client.ensureConnected()

        guard engineConnected else {
            AppLogger.shared.log(.error, "═══════════════════════════════════════════════════")
            AppLogger.shared.log(.error, "  ❌ TALKIE ENGINE NOT RUNNING")
            AppLogger.shared.log(.error, "  TalkieLive requires TalkieEngine to be running.")
            AppLogger.shared.log(.error, "  Please start the Engine service.")
            AppLogger.shared.log(.error, "═══════════════════════════════════════════════════")
            return
        }

        AppLogger.shared.log(.system, "═══════════════════════════════════════════════════")
        AppLogger.shared.log(.system, "  🔗 CONNECTED TO TALKIE ENGINE (XPC)")
        AppLogger.shared.log(.system, "═══════════════════════════════════════════════════")

        do {
            try await client.preloadModel(modelId)
            let totalTime = Date().timeIntervalSince(loadStart)
            AppLogger.shared.log(.system, "Model ready (Engine)", detail: String(format: "%.1fs total", totalTime))
        } catch {
            AppLogger.shared.log(.error, "Engine preload failed", detail: error.localizedDescription)
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }
}
