import Cocoa
import SwiftUI
import Carbon.HIToolbox
import Combine
import TalkieServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var liveController: LiveController!
    private let hotKeyManager = HotKeyManager()
    private let overlayController = RecordingOverlayController.shared
    private let floatingPill = FloatingPillController.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = LiveSettings.shared
        let audio = MicrophoneCapture()
        let transcription = WhisperTranscriptionService(model: settings.whisperModel)
        let router = TranscriptRouter(mode: settings.routingMode)

        liveController = LiveController(
            audio: audio,
            transcription: transcription,
            router: router
        )

        // Pre-load Whisper model so first transcription is fast
        Task {
            try? await WhisperService.shared.preloadModel(settings.whisperModel)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🎙"
            updateStatusBarTooltip()
        }

        // Create menu
        let menu = NSMenu()

        let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleListening), keyEquivalent: "")
        recordItem.target = self
        menu.addItem(recordItem)

        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(title: "Show History...", action: #selector(showMainWindow), keyEquivalent: "h")
        historyItem.keyEquivalentModifierMask = [.option, .command]
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        let pillItem = NSMenuItem(title: "Show Floating Pill", action: #selector(toggleFloatingPill), keyEquivalent: "")
        pillItem.target = self
        pillItem.state = .on
        menu.addItem(pillItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Talkie Live", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Set initial key equivalents from settings
        updateMenuKeyEquivalent()

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

        // Wire up floating pill - tap to toggle recording
        floatingPill.onTap = { [weak self] in
            self?.toggleListening()
        }

        // Show floating pill on launch
        floatingPill.show()

        // Register hotkey from settings
        registerHotkey()

        // Listen for hotkey changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidChange),
            name: .hotkeyDidChange,
            object: nil
        )
    }

    private func registerHotkey() {
        let settings = LiveSettings.shared
        hotKeyManager.registerHotKey(
            modifiers: settings.hotkey.modifiers,
            keyCode: settings.hotkey.keyCode
        ) { [weak self] in
            guard let self else { return }
            self.toggleListening()
        }
    }

    @objc private func hotkeyDidChange() {
        // Unregister old hotkey and register new one
        hotKeyManager.unregisterAll()
        registerHotkey()

        // Update menu item key equivalent
        updateMenuKeyEquivalent()
    }

    private func updateMenuKeyEquivalent() {
        guard let menu = statusItem.menu,
              let recordItem = menu.items.first(where: { $0.action == #selector(toggleListening) }) else {
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

    @objc private func toggleListening() {
        Task {
            await liveController.toggleListening()
        }
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Find and show the main window
        for window in NSApp.windows {
            if window.title == "Talkie Live" || window.identifier?.rawValue.contains("main") == true {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        // If no window found, just activate the app - SwiftUI will create it
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleFloatingPill(_ sender: NSMenuItem) {
        floatingPill.toggle()
        sender.state = floatingPill.isVisible ? .on : .off
    }

    private func updateIcon(for state: LiveState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .idle:
            button.title = "🎙"
        case .listening:
            button.title = "🎙◉"
        case .transcribing:
            button.title = "🎙⟳"
        case .routing:
            button.title = "🎙→"
        }
    }
}
