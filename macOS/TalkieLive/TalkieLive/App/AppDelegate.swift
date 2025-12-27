import Cocoa
import SwiftUI
import TalkieKit
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

    // Lazy UI controllers - initialized during boot sequence
    private var overlayController: RecordingOverlayController { RecordingOverlayController.shared }
    private var floatingPill: FloatingPillController { FloatingPillController.shared }

    // Settings windows
    private var permissionsWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app - keep running when windows are closed
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fratricide prevention: if another instance is already running, quit
        if let bundleID = Bundle.main.bundleIdentifier {
            let runningApps = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == bundleID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            if !runningApps.isEmpty {
                print("⚠️ Another TalkieLive (\(bundleID)) is already running - exiting to prevent fratricide")
                NSApp.terminate(nil)
                return
            }
        }

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

        // Listen for permissions window notification from FloatingPill
        NotificationCenter.default.addObserver(
            forName: .showPermissionsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showPermissions()
        }

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

            // Monitor Control key to show environment badge
            NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                self?.updateStatusBarBadge(controlPressed: event.modifierFlags.contains(.control))
                return event
            }
        }
    }

    private func updateStatusBarBadge(controlPressed: Bool) {
        guard let button = statusItem.button,
              let bundleID = Bundle.main.bundleIdentifier else { return }

        // Only show badge for dev/staging builds when Control is held
        if controlPressed && (bundleID.hasSuffix(".dev") || bundleID.hasSuffix(".staging")) {
            let badge = bundleID.hasSuffix(".dev") ? "DEV" : "STG"
            button.title = badge
            button.image = nil
        } else {
            // Restore icon
            button.title = ""
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "🎙"
            }
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

        let permissionsItem = NSMenuItem(title: "Permissions...", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        // Add warning indicator if permissions are missing
        if !PermissionManager.shared.allRequiredGranted {
            permissionsItem.title = "⚠️ Permissions..."
        }
        menu.addItem(permissionsItem)

        let onboardingItem = NSMenuItem(title: "Show Onboarding...", action: #selector(showOnboarding), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        menu.addItem(NSMenuItem.separator())

        // Show bundle identifier (helpful for dev builds)
        if let bundleID = Bundle.main.bundleIdentifier {
            let bundleItem = NSMenuItem(title: bundleID, action: nil, keyEquivalent: "")
            bundleItem.isEnabled = false
            menu.addItem(bundleItem)
            menu.addItem(NSMenuItem.separator())
        }

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
        overlayController.liveController = liveController  // For mid-recording intent updates
    }

    // MARK: - Floating Pill

    private func setupFloatingPill() {
        // Wire up floating pill - handle taps based on current state
        floatingPill.onTap = { [weak self] state, modifiers in
            NSLog("[AppDelegate] onTap received: state=%@, modifiers=%d", state.rawValue, modifiers.rawValue)

            guard let self = self else {
                NSLog("[AppDelegate] self is nil in onTap")
                return
            }

            let shiftHeld = modifiers.contains(.shift)
            let commandHeld = modifiers.contains(.command)
            let optionHeld = modifiers.contains(.option)

            switch state {
            case .idle:
                // Option+tap: Show failed queue picker if there are queued items
                if optionHeld {
                    let queuedCount = LiveDatabase.countQueued()
                    NSLog("[AppDelegate] Option+tap: queuedCount=%d", queuedCount)

                    if queuedCount > 0 {
                        NSLog("[AppDelegate] Showing failed queue picker")
                        FailedQueueController.shared.show()
                    } else {
                        NSLog("[AppDelegate] No queued items to show")
                        NSSound.beep()
                    }
                } else {
                    // Normal tap: start recording (with optional interstitial mode)
                    NSLog("[AppDelegate] Starting recording (interstitial=%d)", shiftHeld)
                    self.toggleListening(interstitial: shiftHeld)
                }

            case .listening:
                // Listening state: stop recording (with optional interstitial mode)
                self.toggleListening(interstitial: shiftHeld)

            case .transcribing, .routing:
                // Processing states: offer escape options
                if commandHeld {
                    // ⌘+tap: Force reset (emergency exit - abandons everything)
                    self.liveController.forceReset()
                } else {
                    // Regular tap: Push to queue (graceful save for later retry)
                    self.liveController.pushToQueue()
                }
            }
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

        // Listen for hotkey changes (from settings UI in this process)
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
        print("[AppDelegate] 📨 Received .hotkeyDidChange notification")
        print("[AppDelegate] Current hotkey: \(LiveSettings.shared.hotkey.displayString) (keyCode=\(LiveSettings.shared.hotkey.keyCode), modifiers=\(LiveSettings.shared.hotkey.modifiers))")

        // Unregister old hotkeys and register new ones
        hotKeyManager.unregisterAll()
        pttHotKeyManager.unregisterAll()
        registerHotkeys()

        // Update menu item key equivalent
        updateMenuKeyEquivalent()
    }

    @objc private func userDefaultsDidChange() {
        // UserDefaults changed (possibly from Talkie main app)
        // Re-register hotkeys in case they were updated from the settings UI in Talkie
        Task { @MainActor in
            print("[AppDelegate] 🔄 UserDefaults changed - re-registering hotkeys")
            hotkeyDidChange()
        }
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
        NSLog("[AppDelegate] toggleListening called: interstitial=%d", interstitial)
        Task {
            NSLog("[AppDelegate] Calling liveController.toggleListening...")
            await liveController.toggleListening(interstitial: interstitial)
            NSLog("[AppDelegate] liveController.toggleListening completed")
        }
    }

    @objc private func showHistory() {
        // Open Talkie app and navigate to Live section
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true  // Bring to front

        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/Talkie.app"),
            configuration: configuration
        ) { app, error in
            if let error = error {
                AppLogger.shared.log(.error, "Failed to launch Talkie", detail: error.localizedDescription)
                return
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
        // If window already exists, bring it to front
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create focused settings window (Capture + Output + Permissions)
        let contentView = QuickSettingsView()
            .frame(minWidth: 500, minHeight: 450)
            .background(TalkieTheme.background)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TalkieLive Settings"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false

        // Store reference
        settingsWindow = window

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPermissions() {
        // If window already exists, bring it to front
        if let window = permissionsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create permissions window with SwiftUI content
        let contentView = PermissionsSettingsSection()
            .frame(minWidth: 450, minHeight: 500)
            .background(TalkieTheme.background)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TalkieLive Permissions"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false

        // Store reference
        permissionsWindow = window

        // Show window
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
