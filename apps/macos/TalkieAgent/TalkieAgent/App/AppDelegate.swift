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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var agentStatusMenu: NSMenu?
    private var agentMenuPopover: NSPopover?
    private var cachedAgentMenuModel: AgentMenuModel?
    private var cachedAgentMenuActions: AgentMenuActions?
    private var agentMenuPrewarmTask: Task<Void, Never>?
    private var agentMenuRefreshTask: Task<Void, Never>?
    private var modelPreloadTask: Task<Void, Never>?
    private var agentController: AgentController!
    private let speechPlaybackController = SelectionSpeechPlaybackController.shared
    private let selectionFeedbackController = SelectionFeedbackOverlayController.shared

    // Hotkey signatures derived from TalkieEnvironment (see TalkieEnvironment.swift for philosophy)
    private static var sig: String { TalkieEnvironment.current.hotkeySignaturePrefix }
    private static let markupEmergencyDismissNotification = Notification.Name("to.talkie.shared.markupEmergencyDismiss")

    private let hotKeyManager = HotKeyManager(signature: "\(sig)IV", hotkeyID: 1)  // Toggle mode
    private let pttHotKeyManager = HotKeyManager(signature: "\(sig)PT", hotkeyID: 3)  // Push-to-talk
    private let queuePickerHotKeyManager = HotKeyManager(signature: "\(sig)QP", hotkeyID: 2)  // Queue picker
    private let ambientHotKeyManager = HotKeyManager(signature: "\(sig)AB", hotkeyID: 6)  // Ambient mode toggle
    private let composeHotKeyManager = HotKeyManager(signature: "\(sig)CO", hotkeyID: 7)  // Compose with selection
    private let speakSelectionHotKeyManager = HotKeyManager(signature: "\(sig)SP", hotkeyID: 14)  // Speak selected text
    private let screenshotHotKeyManager = HotKeyManager(signature: "\(sig)SS", hotkeyID: 8)  // Screenshot during recording
    private let markupScreenshotHotKeyManager = HotKeyManager(signature: "\(sig)SM", hotkeyID: 21)  // Screenshot with markup destination

    // Direct screenshot shortcuts. Defaults intentionally avoid macOS screenshot shortcuts.
    private let ssFullscreenHotKey = HotKeyManager(signature: "\(sig)S3", hotkeyID: 9)
    private let ssRegionHotKey     = HotKeyManager(signature: "\(sig)S4", hotkeyID: 10)
    private let ssBufferHotKey     = HotKeyManager(signature: "\(sig)S5", hotkeyID: 11)
    private let ssWindowHotKey     = HotKeyManager(signature: "\(sig)S6", hotkeyID: 12)
    private let ssShelfHotKey      = HotKeyManager(signature: "\(sig)ST", hotkeyID: 17)
    private let screenRecordHotKeyManager = HotKeyManager(signature: "\(sig)SR", hotkeyID: 13)  // Screen recording chord
    private let desktopInkHotKey   = HotKeyManager(signature: "\(sig)DI", hotkeyID: 18)  // Toggle desktop ink layer
    private let desktopInkPassthroughHotKey = HotKeyManager(signature: "\(sig)DP", hotkeyID: 19)  // Draw <-> arrange
    private let desktopMagnifierHotKey = HotKeyManager(signature: "\(sig)DM", hotkeyID: 20)  // Freeze a region into a desktop magnifier
    private let markupEmergencyHotKey = HotKeyManager(signature: "\(sig)MX", hotkeyID: 22)  // Force-dismiss capture markup
    private var desktopInkTapMonitor: ModifierTapMonitor?  // Bare left/right Ctrl taps for ink

    private struct AgentMenuInputState {
        var name: String
        var ready: Bool
        var systemDefault: Bool
        var devices: [AgentMenuInputDevice]
    }

    private struct AgentMenuDeferredData: Sendable {
        var failedQueueCount: Int
        var recentItems: [AgentMenuRecentItem]
    }
    private let pasteChordHotKeyManager = HotKeyManager(signature: "\(sig)PV", hotkeyID: 15)  // Quick Paste chord
    private let pasteLastScreenshotHotKey = HotKeyManager(signature: "\(sig)PF", hotkeyID: 16)  // Paste last screenshot
    private let agentVoiceHotKeyManager = HotKeyManager(signature: "\(sig)WT", hotkeyID: 17)  // Hyper+T agent voice panel (TLK-020)
    private let captureHotPathLoggingEnabled = ProcessInfo.processInfo.environment["CAPTURE_PERF"] == "1"
    private static let walkieHotkeyKeyCode: UInt32 = 17
    private static var walkieHotkeyModifiers: UInt32 { hyperModifiers }

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
    private var isAgentCaptureChordActive = false
    private var isAgentDirectScreenshotCaptureActive = false
    private var isAgentPasteChordActive = false
    private var agentPasteChordSuppressesShortcutTriggersUntil: Date = .distantPast
    private var fileDragPanel: FileDragPanel?
    private var lastAgentDirectScreenshotMode: String?
    private var lastAgentDirectScreenshotAt: Date = .distantPast

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AgentHomeController.shared.show()
        return true
    }

    /// Keep the process that owns the launchd MachService alive.
    ///
    /// Talkie talks to Agent through the launchd-registered MachService. A
    /// LaunchServices-opened Agent can show UI, but it cannot satisfy that
    /// launchd endpoint. When both exist, prefer the launchd process so XPC
    /// calls like ping/transcribe have a live receiver.
    private func claimLaunchOwnership() -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myBundleID = Bundle.main.bundleIdentifier ?? ""
        let expectedLaunchLabel = TalkieHelper.agent.launchdLabel(for: TalkieEnvironment.current)
        let xpcServiceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]
        let isLaunchAgentOwned = xpcServiceName == expectedLaunchLabel
        let allowStandalone = ProcessInfo.processInfo.environment["TALKIE_AGENT_ALLOW_STANDALONE"] == "1"

        let others = NSRunningApplication.runningApplications(withBundleIdentifier: myBundleID)
            .filter { $0.processIdentifier != myPID }
        let terminated = others.filter { $0.isTerminated }
        let alive = others.filter { !$0.isTerminated }

        if isLaunchAgentOwned {
            if !alive.isEmpty {
                terminateDuplicateInstances(alive, reason: "LaunchAgent instance is taking over XPC")
            }

            if !terminated.isEmpty {
                let zombiePIDs = terminated.map { String($0.processIdentifier) }.joined(separator: ", ")
                AgentConsole.critical("[TalkieAgent] Found zombie instances (PID: %@) — taking over as PID %d", zombiePIDs, myPID)
            }

            return true
        }

        if !allowStandalone && launchAgentIsLoaded(label: expectedLaunchLabel, uid: getuid()) {
            AgentConsole.critical(
                "[TalkieAgent] LaunchAgent %@ owns XPC; handing off standalone PID %d",
                expectedLaunchLabel,
                myPID
            )
            _ = kickstartLaunchAgentForHandoff(label: expectedLaunchLabel, uid: getuid())
            NSApplication.shared.terminate(nil)
            return false
        }

        if !alive.isEmpty {
            let alivePIDs = alive.map { String($0.processIdentifier) }.joined(separator: ", ")
            AgentConsole.critical("[TalkieAgent] Another instance already running (PID: %@) — exiting duplicate (PID: %d)", alivePIDs, myPID)
            NSApplication.shared.terminate(nil)
            return false
        }

        if !terminated.isEmpty {
            let zombiePIDs = terminated.map { String($0.processIdentifier) }.joined(separator: ", ")
            AgentConsole.critical("[TalkieAgent] Found zombie instances (PID: %@) — taking over as PID %d", zombiePIDs, myPID)
        }

        return true
    }

    private func terminateDuplicateInstances(_ apps: [NSRunningApplication], reason: String) {
        for app in apps {
            let pid = app.processIdentifier
            AgentConsole.critical("[TalkieAgent] %@ — terminating duplicate PID %d", reason, pid)
            _ = app.terminate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard !app.isTerminated else { return }
                AgentConsole.critical("[TalkieAgent] Duplicate PID %d still running — force terminating", pid)
                _ = app.forceTerminate()
            }
        }
    }

    private func kickstartLaunchAgentForHandoff(label: String, uid: uid_t) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(uid)/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            AgentConsole.critical("[TalkieAgent] Failed to hand off to LaunchAgent %@: %@", label, error.localizedDescription)
            return false
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard claimLaunchOwnership() else { return }

        // Register brand fonts bundled in TalkieKit so JetBrains Mono resolves
        // here (the Agent target doesn't ship fonts of its own).
        TalkieKitFonts.registerBundledFonts()

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
        scheduleAgentMenuPrewarm()
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

        // Setup UI wiring
        setupStateObservation()
        setupHotkeys()
        setupFloatingPill()

        // Bridge messages now routed through Talkie (TalkieServer → XPC)

        // Show floating pill on launch
        floatingPill.show()

        refreshAgentMenuCacheAndPopover(reason: "post-boot")

        log.info("Boot complete — hotkey change observers active")

        // Pre-load the embedded engine after hotkeys/UI are responsive. Model
        // loading can take a while on a clean launch, but shortcuts should not
        // be gated on warmup.
        modelPreloadTask?.cancel()
        modelPreloadTask = Task { @MainActor [weak self, settings] in
            await self?.preloadModel(settings: settings)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        forceDismissCaptureSurfaces(reason: "application termination")
        TalkieAgentServerSupervisor.shared.stopSync()
        TalkieHelperRuntimeStateStore.clear(for: .agent)
        TalkieAgentXPCService.shared.stopService()

        // Clean up event monitors
        if let monitor = controlKeyMonitor {
            NSEvent.removeMonitor(monitor)
            controlKeyMonitor = nil
        }
        agentMenuPrewarmTask?.cancel()
        agentMenuRefreshTask?.cancel()
        modelPreloadTask?.cancel()
        AgentCameraBubbleController.shared.teardown()
        ScreenRecordingService.shared.teardown()
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

        AgentConsole.critical("[TalkieAgent] Received URL: \(url.absoluteString)")

        switch url.host {
        case "home", "agent":
            AgentHomeController.shared.show()
        case "settings":
            AgentHomeController.shared.showSettings()
        case "performance":
            showSettings(tab: .performance)
        case "toggle":
            toggleListening(interstitial: false)
        default:
            // Unknown command - show Agent Home settings as fallback.
            AgentHomeController.shared.showSettings()
        }
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Start with Talkie's menu bar glyph.
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        statusItem.length = image.size.width + 6
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.image = image

        // Reset any tint - color is handled in the drawing
        button.contentTintColor = nil
    }

    /// Create the status item icon.
    /// - Recording: high-contrast red active capsule.
    /// - Idle, mic denied: high-contrast orange warning capsule.
    /// - Idle, mic granted: Talkie glyph as a native template symbol.
    private func createMenuBarIcon(isRecording: Bool, hasMicPermission: Bool) -> NSImage {
        if isRecording {
            return Self.createActiveTalkieMenuBarIcon(style: .recording)
        }

        if hasMicPermission {
            return Self.createTalkieMenuBarIcon()
        }

        return Self.createActiveTalkieMenuBarIcon(style: .microphoneWarning)
    }

    private enum TalkieMenuBarIconStyle {
        case recording
        case microphoneWarning
    }

    /// Status dot drawn on the menu-bar tile.
    private enum TalkieMenuBarDot {
        case none
        case recording
        case microphoneWarning

        var color: NSColor? {
            switch self {
            case .none: return nil
            case .recording: return NSColor(calibratedRed: 0.93, green: 0.21, blue: 0.16, alpha: 1.0)
            case .microphoneWarning: return NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.16, alpha: 1.0)
            }
        }
    }

    // The menu-bar mark is a fixed white tile with a black "T". State is shown by
    // a small corner dot (red = recording, amber = mic blocked) rather than by
    // recoloring the whole mark, so the icon never jumps shape or width.
    private static let talkieMenuBarTileSize = NSSize(width: 21, height: 18)

    private static func createTalkieMenuBarIcon() -> NSImage {
        makeTalkieTileIcon(dot: .none)
    }

    private static func createActiveTalkieMenuBarIcon(style: TalkieMenuBarIconStyle) -> NSImage {
        switch style {
        case .recording: return makeTalkieTileIcon(dot: .recording)
        case .microphoneWarning: return makeTalkieTileIcon(dot: .microphoneWarning)
        }
    }

    private static func makeTalkieTileIcon(dot: TalkieMenuBarDot) -> NSImage {
        let image = NSImage(size: Self.talkieMenuBarTileSize, flipped: false) { rect in
            // White rounded tile.
            let tile = NSRect(x: rect.minX + 1.0, y: rect.minY + 1.5, width: 17, height: 15)
            let tilePath = NSBezierPath(roundedRect: tile, xRadius: 4.5, yRadius: 4.5)
            NSColor.white.withAlphaComponent(0.97).setFill()
            tilePath.fill()
            NSColor.black.withAlphaComponent(0.14).setStroke()
            tilePath.lineWidth = 0.75
            tilePath.stroke()

            // Black "T" centered in the tile.
            Self.drawTalkieT(in: tile.insetBy(dx: 4.6, dy: 3.0), color: .black)

            // Corner status dot, ringed so it reads against tile and menu bar alike.
            if let dotColor = dot.color {
                let d: CGFloat = 5.5
                let dotRect = NSRect(x: tile.maxX - d + 1.0, y: tile.maxY - d + 1.0, width: d, height: d)
                NSColor.white.withAlphaComponent(0.95).setStroke()
                let halo = NSBezierPath(ovalIn: dotRect.insetBy(dx: -0.5, dy: -0.5))
                halo.lineWidth = 1.0
                halo.stroke()
                dotColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawTalkieT(in rect: NSRect, color: NSColor) {
        let sourceBounds = NSRect(x: 313, y: 224, width: 381, height: 591)
        let scale = min(rect.width / sourceBounds.width, rect.height / sourceBounds.height)
        let drawSize = NSSize(width: sourceBounds.width * scale, height: sourceBounds.height * scale)
        let origin = NSPoint(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2)

        func mappedX(_ value: CGFloat) -> CGFloat {
            origin.x + (value - sourceBounds.minX) * scale
        }

        func mappedY(_ value: CGFloat) -> CGFloat {
            origin.y + (sourceBounds.maxY - value) * scale
        }

        color.setFill()

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: mappedX(436), y: mappedY(224)))
        stem.line(to: NSPoint(x: mappedX(520), y: mappedY(224)))
        stem.line(to: NSPoint(x: mappedX(520), y: mappedY(681)))
        stem.curve(
            to: NSPoint(x: mappedX(579), y: mappedY(737)),
            controlPoint1: NSPoint(x: mappedX(520), y: mappedY(716)),
            controlPoint2: NSPoint(x: mappedX(542), y: mappedY(737))
        )
        stem.line(to: NSPoint(x: mappedX(694), y: mappedY(737)))
        stem.line(to: NSPoint(x: mappedX(694), y: mappedY(815)))
        stem.line(to: NSPoint(x: mappedX(559), y: mappedY(815)))
        stem.curve(
            to: NSPoint(x: mappedX(436), y: mappedY(696)),
            controlPoint1: NSPoint(x: mappedX(483), y: mappedY(815)),
            controlPoint2: NSPoint(x: mappedX(436), y: mappedY(767))
        )
        stem.close()
        stem.fill()

        let crossbar = NSRect(
            x: mappedX(313),
            y: mappedY(452),
            width: 381 * scale,
            height: 76 * scale
        )
        NSBezierPath(
            roundedRect: crossbar,
            xRadius: 8 * scale,
            yRadius: 8 * scale
        ).fill()
    }

    private func updateStatusBarBadge(controlPressed: Bool) {
        guard let button = statusItem.button,
              let bundleID = Bundle.main.bundleIdentifier else { return }

        // Only show badge for dev builds when Control is held
        if controlPressed && bundleID.hasSuffix(".dev") {
            statusItem.length = 38
            button.imagePosition = .noImage
            button.title = "DEV"
            button.image = nil
            button.contentTintColor = nil
        } else {
            // Restore icon based on current state
            button.title = ""
            let isRecording = agentController?.state == .listening
            updateMenuBarIcon(isRecording: isRecording)
        }
    }

    // MARK: - Menu Setup

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let homeItem = NSMenuItem(title: "Open Agent Home", action: #selector(showAgentHome), keyEquivalent: "0")
        homeItem.keyEquivalentModifierMask = [.option, .command]
        homeItem.target = self
        menu.addItem(homeItem)

        menu.addItem(NSMenuItem.separator())

        let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleListeningFromMenu), keyEquivalent: "")
        recordItem.target = self
        menu.addItem(recordItem)

        menu.addItem(NSMenuItem.separator())

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

        let ambientItem = NSMenuItem(title: "Ambient Mode", action: #selector(toggleAmbientModeFromMenu), keyEquivalent: "")
        ambientItem.target = self
        ambientItem.state = AmbientSettings.shared.isEnabled ? .on : .off
        menu.addItem(ambientItem)

        let streamingItem = NSMenuItem(title: "Streaming Wake Detection", action: #selector(toggleStreamingWakeFromMenu), keyEquivalent: "")
        streamingItem.target = self
        streamingItem.state = AmbientSettings.shared.useStreamingASR ? .on : .off
        menu.addItem(streamingItem)

        let clearQueueItem = NSMenuItem(title: "Clear Failed Queue", action: #selector(clearFailedQueue), keyEquivalent: "")
        clearQueueItem.target = self
        clearQueueItem.isHidden = true
        menu.addItem(clearQueueItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Open Agent Home Settings...", action: #selector(showSettingsAction), keyEquivalent: ",")
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

        let restartItem = NSMenuItem(title: "Restart Talkie Agent", action: #selector(restartAgent), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit Talkie Agent", action: #selector(confirmQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        agentStatusMenu = menu

        // Set initial key equivalents from settings
        updateMenuKeyEquivalent()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else {
            log.warning("Agent menu status item click ignored because the button was unavailable")
            return
        }

        let event = NSApp.currentEvent
        if event == nil {
            log.warning("Agent menu status item click had no current event; treating it as a left click")
        }

        let isNativeMenuRequest = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isNativeMenuRequest {
            log.info("Agent menu native menu requested", detail: Self.statusClickEventDescription(event))
            showNativeStatusMenu(from: button)
            return
        }

        if let popover = agentMenuPopover, popover.isShown {
            log.info("Agent menu popover close requested from status item", detail: Self.statusClickEventDescription(event))
            popover.performClose(sender)
            return
        }

        log.info("Agent menu popover open requested from status item", detail: Self.statusClickEventDescription(event))
        showAgentMenuPopover(from: button)
    }

    private static func statusClickEventDescription(_ event: NSEvent?) -> String {
        guard let event else { return "event=nil" }
        return "event=\(event.type) modifiers=\(event.modifierFlags.rawValue)"
    }

    private func showNativeStatusMenu(from button: NSStatusBarButton) {
        agentMenuPopover?.performClose(nil)
        updateStatusMenuItems()
        agentStatusMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func showAgentMenuPopover(from button: NSStatusBarButton) {
        let openStart = CFAbsoluteTimeGetCurrent()
        let initialModel = makeAgentMenuModel(refreshPermissions: false, loadSlowData: false)
        let wasPrewarmed = agentMenuPopover != nil
        let popover = prepareAgentMenuPopover(with: initialModel)

        agentMenuPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.sharingType = .readOnly
        popover.contentViewController?.view.window?.makeKey()

        let firstPaintMs = Int((CFAbsoluteTimeGetCurrent() - openStart) * 1000)
        log.info(
            "Agent menu popover shown",
            detail: "firstPaintMs=\(firstPaintMs) prewarmed=\(wasPrewarmed) cached=\(cachedAgentMenuModel != nil)"
        )

        refreshAgentMenuPopoverAsync(reason: "open", openedAt: openStart)
    }

    private func scheduleAgentMenuPrewarm() {
        agentMenuPrewarmTask?.cancel()
        agentMenuPrewarmTask = Task { @MainActor [weak self] in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }
            self.prewarmAgentMenuPopover()
        }
    }

    private func prewarmAgentMenuPopover() {
        guard agentMenuPopover == nil else { return }

        let start = CFAbsoluteTimeGetCurrent()
        let initialModel = makeAgentMenuModel(refreshPermissions: false, loadSlowData: false)
        _ = prepareAgentMenuPopover(with: initialModel)
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        log.info("Agent menu popover prewarmed", detail: "elapsedMs=\(elapsedMs)")
    }

    private func prepareAgentMenuPopover(with model: AgentMenuModel) -> NSPopover {
        let popover = agentMenuPopover ?? NSPopover()
        popover.delegate = self
        popover.behavior = .transient
        // Match the popover chrome (menus, scrollbars) to the active tray skin.
        popover.appearance = NSAppearance(named: AgentTraySkin.current().isDark ? .darkAqua : .aqua)
        popover.contentSize = AgentMenuPopoverView.preferredContentSize(for: model)

        if let hostingController = popover.contentViewController as? NSHostingController<AgentMenuPopoverView> {
            hostingController.rootView = AgentMenuPopoverView(
                model: model,
                actions: makeAgentMenuActions()
            )
        } else {
            popover.contentViewController = NSHostingController(
                rootView: AgentMenuPopoverView(
                    model: model,
                    actions: makeAgentMenuActions()
                )
            )
        }

        agentMenuPopover = popover
        return popover
    }

    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === agentMenuPopover else { return }
        log.info("Agent menu popover closed")
    }

    private func makeAgentMenuModel(
        refreshPermissions: Bool,
        loadSlowData: Bool,
        deferredData: AgentMenuDeferredData? = nil,
        inputState providedInputState: AgentMenuInputState? = nil
    ) -> AgentMenuModel {
        let cachedModel = cachedAgentMenuModel

        if refreshPermissions {
            PermissionManager.shared.refreshAll()
        }

        let settings = LiveSettings.shared
        let state = agentController?.state
        let isRecording = state == .listening
        let isReady = agentController != nil
        let permissionsGranted = PermissionManager.shared.allRequiredGranted
        let isLoadingData = !loadSlowData && cachedModel == nil
        let resolvedDeferredData = deferredData ?? (loadSlowData ? Self.loadAgentMenuDeferredData() : nil)
        let failedQueueCount = resolvedDeferredData?.failedQueueCount ?? cachedModel?.failedQueueCount ?? 0

        let stateTitle: String
        let stateDetail: String
        switch state {
        case .some(.listening):
            stateTitle = "Recording"
            stateDetail = "Listening for dictation"
        case .some(.transcribing):
            stateTitle = "Transcribing"
            stateDetail = "Processing the last capture"
        case .some(.routing):
            stateTitle = "Routing"
            stateDetail = "Delivering the result"
        case .some(.refining):
            stateTitle = "Refining"
            stateDetail = "Polishing the transcript"
        case .some(.idle):
            stateTitle = permissionsGranted ? "Ready" : "Needs Permissions"
            stateDetail = AmbientSettings.shared.isEnabled ? "Ambient wake is on" : "Ready for \(settings.hotkey.displayString)"
        case nil:
            stateTitle = "Starting"
            stateDetail = "Audio engine starting"
        }

        let recentItems = resolvedDeferredData?.recentItems ?? cachedModel?.recentItems ?? []
        let inputState = providedInputState ?? (
            loadSlowData
                ? makeAgentMenuInputState()
                : AgentMenuInputState(
                    name: cachedModel?.inputDeviceName ?? "Loading inputs",
                    ready: cachedModel?.inputDevicesReady ?? false,
                    systemDefault: cachedModel?.isSystemDefaultInput ?? true,
                    devices: cachedModel?.inputDevices ?? []
                )
        )

        return AgentMenuModel(
            stateTitle: stateTitle,
            stateDetail: stateDetail,
            isReady: isReady,
            isRecording: isRecording,
            permissionsGranted: permissionsGranted,
            recordingShortcut: settings.hotkey.displayString,
            inputDeviceName: inputState.name,
            inputDevicesReady: inputState.ready,
            isSystemDefaultInput: inputState.systemDefault,
            inputDevices: inputState.devices,
            failedQueueCount: failedQueueCount,
            recentItems: recentItems,
            isLoadingData: isLoadingData
        )
    }

    private func refreshAgentMenuPopoverAsync(reason: String, openedAt: CFAbsoluteTime) {
        agentMenuRefreshTask?.cancel()
        agentMenuRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }

            let refreshStart = CFAbsoluteTimeGetCurrent()
            let deferredData = await Task.detached(priority: .utility) {
                Self.loadAgentMenuDeferredData()
            }.value
            guard !Task.isCancelled else { return }

            PermissionManager.shared.refreshAll()
            let inputState = self.makeAgentMenuInputState()
            let model = self.makeAgentMenuModel(
                refreshPermissions: false,
                loadSlowData: true,
                deferredData: deferredData,
                inputState: inputState
            )
            self.cachedAgentMenuModel = model
            self.updateAgentMenuPopoverContent(with: model)

            let refreshMs = Int((CFAbsoluteTimeGetCurrent() - refreshStart) * 1000)
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - openedAt) * 1000)
            log.info(
                "Agent menu model refreshed",
                detail: "reason=\(reason) refreshMs=\(refreshMs) totalSinceOpenMs=\(totalMs)"
            )
        }
    }

    @discardableResult
    private func refreshAgentMenuCacheAndPopover(reason: String) -> AgentMenuModel {
        let model = makeAgentMenuModel(refreshPermissions: true, loadSlowData: true)
        cachedAgentMenuModel = model
        updateAgentMenuPopoverContent(with: model)
        log.info("Agent menu cache refreshed", detail: "reason=\(reason)")
        return model
    }

    private func updateAgentMenuPopoverContent(with model: AgentMenuModel) {
        guard let popover = agentMenuPopover, popover.isShown else { return }
        popover.contentSize = AgentMenuPopoverView.preferredContentSize(for: model)

        if let hostingController = popover.contentViewController as? NSHostingController<AgentMenuPopoverView> {
            hostingController.rootView = AgentMenuPopoverView(
                model: model,
                actions: makeAgentMenuActions()
            )
            return
        }

        popover.contentViewController = NSHostingController(
            rootView: AgentMenuPopoverView(
                model: model,
                actions: makeAgentMenuActions()
            )
        )
    }

    private nonisolated static func loadAgentMenuDeferredData() -> AgentMenuDeferredData {
        let failedQueueCount = UnifiedDatabase.countQueued()
        let recentItems = UnifiedDatabase.recentDictations(limit: 5).map { recording in
            let text = recording.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = Self.truncatedMenuText(text, limit: 58)
            return AgentMenuRecentItem(
                id: recording.id,
                preview: preview.isEmpty ? "Empty dictation" : preview,
                timestamp: recording.createdAt.timeAgoShort,
                text: recording.text
            )
        }

        return AgentMenuDeferredData(
            failedQueueCount: failedQueueCount,
            recentItems: recentItems
        )
    }

    private func makeAgentMenuInputState() -> AgentMenuInputState {
        let audioDevices = AudioDeviceManager.shared
        let settings = LiveSettings.shared
        let devices = audioDevices.inputDevices.map { device in
            AgentMenuInputDevice(
                id: device.id,
                uid: device.uid,
                name: device.name,
                isDefault: device.isDefault
            )
        }

        let isSystemDefault = settings.selectedMicrophoneMode == .systemDefault
        let selectedName: String
        if isSystemDefault {
            if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
                selectedName = "System Default (\(defaultDevice.name))"
            } else {
                selectedName = "System Default"
            }
        } else if let selectedUID = settings.selectedMicrophoneUID,
                  let selectedDevice = audioDevices.inputDevices.first(where: { $0.uid == selectedUID }) {
            selectedName = selectedDevice.name
        } else if let savedName = settings.selectedMicrophoneName {
            selectedName = "\(savedName) unavailable"
        } else {
            selectedName = "System Default"
        }

        return AgentMenuInputState(
            name: selectedName,
            ready: !devices.isEmpty,
            systemDefault: isSystemDefault,
            devices: devices
        )
    }

    private func makeAgentMenuActions() -> AgentMenuActions {
        if let cachedAgentMenuActions {
            return cachedAgentMenuActions
        }

        let actions = AgentMenuActions(
            toggleRecording: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.toggleListeningFromMenu()
                }
            },
            openHome: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.showAgentHome()
                }
            },
            openTalkie: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    TalkieAppOpener.openApp()
                }
            },
            openSettings: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    AgentHomeController.shared.showSettings()
                }
            },
            openHistory: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.showHistory()
                }
            },
            openAllGrabs: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    AgentHomeController.shared.show(section: .libraryCaptures)
                }
            },
            openGrab: { [weak self] item in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.openAgentMenuGrab(item)
                }
            },
            openAudioSettings: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.showSettings(tab: .audio)
                }
            },
            openLogs: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    AgentHomeController.shared.show(section: .logs)
                }
            },
            openPermissions: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.showPermissions()
                }
            },
            openQueue: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.showQueuePicker()
                }
            },
            clearQueue: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.clearFailedQueue()
                }
            },
            refreshAudioDevices: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    AudioDeviceManager.shared.refreshDevices()
                    self.refreshAgentMenuCacheAndPopover(reason: "audio-devices-refresh")
                }
            },
            selectSystemDefaultInput: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    AudioDeviceManager.shared.selectSystemDefault()
                    self.refreshAgentMenuCacheAndPopover(reason: "audio-input-system-default")
                }
            },
            selectInputDevice: { [weak self] device in
                Task { @MainActor in
                    guard let self else { return }
                    guard let inputDevice = AudioDeviceManager.shared.inputDevices.first(where: { $0.uid == device.uid }) else {
                        AudioDeviceManager.shared.refreshDevices()
                        self.refreshAgentMenuCacheAndPopover(reason: "audio-input-missing")
                        return
                    }
                    AudioDeviceManager.shared.selectDevice(inputDevice)
                    self.refreshAgentMenuCacheAndPopover(reason: "audio-input-selected")
                }
            },
            rebootAudio: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.rebootAudioSystem()
                }
            },
            copyRecent: { [weak self] text in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.copyRecentDictationText(text)
                }
            },
            restart: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.restartAgent()
                }
            },
            quit: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.dismissAgentMenuPopover()
                    self.confirmQuit()
                }
            }
        )
        cachedAgentMenuActions = actions
        return actions
    }

    private func openAgentMenuGrab(_ item: AgentLiveTrayItem) {
        if item.isClip {
            AgentCaptureClipPreviewController.shared.open(item: item)
        } else if item.isScreenshot {
            AgentCaptureMarkupController.shared.open(item: item)
        } else {
            NSWorkspace.shared.open(item.fileURL)
        }
    }

    private func dismissAgentMenuPopover() {
        agentMenuPopover?.performClose(nil)
    }

    private func updateStatusMenuItems() {
        updateRecordingMenuItem(isRecording: agentController?.state == .listening)
        updateRecentMenu()
        updatePermissionsMenuItem()
        updateAmbientMenuItem()
        updateStreamingMenuItem()
        updateClearQueueMenuItem()
    }

    private nonisolated static func truncatedMenuText(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return "\(String(text.prefix(limit)))..."
    }

    // MARK: - State Observation

    private func setupStateObservation() {
        // Agent-owned capture island: surfaces a draggable preview at top-center
        // when a screenshot/clip lands in the live tray. Works on any display.
        CaptureIslandController.shared.initialize()

        let hasNotch = NotchInfo.detect().hasNotch
        let notchEnabled = LiveSettings.shared.notchOverlayEnabled

        // TLK-027: Agent owns live notch/island rendering. Talkie remains the
        // durable media view/edit/save surface and should no longer suppress
        // Agent's live overlay when it connects.
        if hasNotch && notchEnabled {
            notchOverlay.initialize()
        }

        // Observe state changes to update the icon, overlay, and floating pill
        agentController.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)

                // Pill stays visible always — it doesn't compete for notch/top-bar real estate
                self?.floatingPill.updateState(state)
                let notchActive = hasNotch && LiveSettings.shared.notchOverlayEnabled
                if notchActive {
                    // Notch overlay replaces the top bar recording overlay
                    self?.notchOverlay.updateState(state)
                    self?.overlayController.hide()
                } else {
                    self?.overlayController.updateState(state)
                }

                SidecarOverlayController.shared.updateState(state)
            }
            .store(in: &cancellables)

        // Keep Agent-owned live overlays stable across Talkie connects/disconnects.
        TalkieAgentXPCService.shared.$isTalkieConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let currentState = self.agentController.state
                if hasNotch && LiveSettings.shared.notchOverlayEnabled {
                    self.notchOverlay.initialize()
                    self.notchOverlay.updateState(currentState)
                    self.overlayController.hide()
                } else {
                    self.notchOverlay.hide()
                    self.overlayController.updateState(currentState)
                }
            }
            .store(in: &cancellables)

        // Wire up overlay controls
        overlayController.onStop = { [weak self] in
            self?.agentController.stopListening()
        }
        overlayController.onCancel = { [weak self] in
            self?.agentController.cancelListening()
        }
        overlayController.agentController = agentController  // For mid-recording intent updates

        // Wire up notch overlay controls
        notchOverlay.onStop = { [weak self] in
            guard let self else { return }
            if self.agentController.state == .idle {
                Task { @MainActor in
                    await self.agentController.toggleListening()
                }
            } else {
                self.agentController.stopListening()
            }
        }
        notchOverlay.onCancel = { [weak self] in
            self?.agentController.cancelListening()
        }
        notchOverlay.onStopScreenRecording = {
            Task { @MainActor in
                await ScreenRecordingController.shared.stopRecording()
            }
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
                self.updateMenuBarIcon(isRecording: isRecording)
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
            self?.agentController.stopListening()
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
    private static func loadHotkeyConfig(
        key: String,
        fallbackKeyCode: UInt32,
        fallbackModifiers: UInt32,
        avoidsAppleScreenshotShortcuts: Bool = false
    ) -> (keyCode: UInt32, modifiers: UInt32) {
        if let data = TalkieSharedSettings.data(forKey: key) {
            if let config = try? JSONDecoder().decode(HotkeyConfigDTO.self, from: data) {
                if avoidsAppleScreenshotShortcuts,
                   SystemReservedHotkeys.isAppleScreenshotShortcut(keyCode: config.keyCode, modifiers: config.modifiers) {
                    let fallback = HotkeyConfigDTO(keyCode: fallbackKeyCode, modifiers: fallbackModifiers)
                    if let fallbackData = try? JSONEncoder().encode(fallback) {
                        TalkieSharedSettings.set(fallbackData, forKey: key)
                    }
                    log.warning(
                        "Reset Apple-reserved capture hotkey to default",
                        detail: "key=\(key) keyCode=\(config.keyCode) modifiers=\(config.modifiers)"
                    )
                    return (fallback.keyCode, fallback.modifiers)
                }
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

    private static var captureFeatureEnabled: Bool {
        if TalkieEnvironment.current == .production {
            return true
        }
        return TalkieSharedSettings.bool(forKey: AgentSettingsKey.featureCaptureEnabled)
    }

    private static func syncProductionCaptureDefaultIfNeeded() {
        guard TalkieEnvironment.current == .production else { return }
        TalkieSharedSettings.set(true, forKey: AgentSettingsKey.featureCaptureEnabled)
    }

    private static func migrateReservedCaptureDefaultsIfNeeded() {
        let legacyMigrationKey = "hotkeyCapture.safeDefaultsMigration.v1"
        let previousMigrationKey = "hotkeyCapture.safeDefaultsMigration.v2"
        let migrationKey = "hotkeyCapture.safeDefaultsMigration.v3"
        guard !TalkieSharedSettings.bool(forKey: migrationKey) else { return }

        let oldCmdShift = UInt32(cmdKey | shiftKey)
        let migrations: [(key: String, old: HotkeyConfigDTO, new: HotkeyConfigDTO)] = [
            ("hotkeyCapture.fullscreen", .init(keyCode: 20, modifiers: oldCmdShift), .init(keyCode: 20, modifiers: hyperModifiers)),
            ("hotkeyCapture.region", .init(keyCode: 21, modifiers: oldCmdShift), .init(keyCode: 21, modifiers: hyperModifiers)),
            ("hotkeyCapture.trayViewer", .init(keyCode: 23, modifiers: oldCmdShift), .init(keyCode: 23, modifiers: hyperModifiers)),
            ("hotkeyCapture.window", .init(keyCode: 22, modifiers: oldCmdShift), .init(keyCode: 22, modifiers: hyperModifiers)),
            ("hotkeyCapture.trayShelf", .init(keyCode: 17, modifiers: oldCmdShift), .init(keyCode: 17, modifiers: hyperModifiers)),
            (AgentSettingsKey.pasteLastScreenshotHotkey, .init(keyCode: 9, modifiers: oldCmdShift), .init(keyCode: 35, modifiers: hyperModifiers)),
            ("hotkeyCapture.desktopMagnifier", .init(keyCode: 46, modifiers: hyperModifiers), .init(keyCode: 6, modifiers: hyperModifiers)),
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

        TalkieSharedSettings.set(true, forKey: legacyMigrationKey)
        TalkieSharedSettings.set(true, forKey: previousMigrationKey)
        TalkieSharedSettings.set(true, forKey: migrationKey)

        if !migrated.isEmpty {
            log.info("Migrated reserved screenshot hotkeys", detail: "keys=\(migrated.joined(separator: ","))")
        }
    }

    private func setupHotkeys() {
        Self.migrateReservedCaptureDefaultsIfNeeded()
        Self.syncProductionCaptureDefaultIfNeeded()

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
        registerMarkupSafetyHotkey()

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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(markupEmergencyDismissReceived(_:)),
            name: Self.markupEmergencyDismissNotification,
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

        guard Self.captureFeatureEnabled else {
            log.info("Capture hotkeys skipped — feature disabled in shared settings")
            return
        }

        let captureChord = Self.loadHotkeyConfig(
            key: AgentSettingsKey.captureChordHotkey,
            fallbackKeyCode: 1,
            fallbackModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey),
            avoidsAppleScreenshotShortcuts: true
        )
        let screenRecordChord = Self.loadHotkeyConfig(
            key: AgentSettingsKey.screenRecordChordHotkey,
            fallbackKeyCode: 15,
            fallbackModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey),
            avoidsAppleScreenshotShortcuts: true
        )

        screenshotHotKeyManager.registerHotKey(
            modifiers: captureChord.modifiers,
            keyCode: captureChord.keyCode
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAgentCaptureChord(initialMode: .screenshot)
            }
        }
        log.info("Screenshot hotkey registered: keyCode=\(captureChord.keyCode) modifiers=\(captureChord.modifiers)")

        let markupCaptureChord = Self.loadHotkeyConfig(
            key: AgentSettingsKey.markupCaptureChordHotkey,
            fallbackKeyCode: 46,
            fallbackModifiers: Self.hyperModifiers,
            avoidsAppleScreenshotShortcuts: true
        )
        markupScreenshotHotKeyManager.registerHotKey(
            modifiers: markupCaptureChord.modifiers,
            keyCode: markupCaptureChord.keyCode
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAgentCaptureChord(initialMode: .screenshot, startsMarkupEnabled: true)
            }
        }
        log.info("Markup screenshot hotkey registered: keyCode=\(markupCaptureChord.keyCode) modifiers=\(markupCaptureChord.modifiers)")

        screenRecordHotKeyManager.registerHotKey(
            modifiers: screenRecordChord.modifiers,
            keyCode: screenRecordChord.keyCode
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAgentCaptureChord(initialMode: .video)
            }
        }
        log.info("Screen recording hotkey registered: keyCode=\(screenRecordChord.keyCode) modifiers=\(screenRecordChord.modifiers)")

        // Desktop ink: draw straight on the desktop, then snap and the marks
        // bake in. Toggle the layer (Hyper+N) and flip draw <-> arrange so you
        // can move windows under the ink (Hyper+H). Hyper+D is dictation; bare
        // left/right Ctrl triggers are being explored as a conflict-free option.
        let inkToggle = Self.loadHotkeyConfig(
            key: "hotkeyCapture.desktopInk",
            fallbackKeyCode: 45,                   // N — toggle ink layer
            fallbackModifiers: Self.hyperModifiers
        )
        desktopInkHotKey.registerHotKey(modifiers: inkToggle.modifiers, keyCode: inkToggle.keyCode) { [weak self] _ in
            Task { @MainActor in self?.toggleDesktopInk() }
        }
        let inkArrange = Self.loadHotkeyConfig(
            key: "hotkeyCapture.desktopInkArrange",
            fallbackKeyCode: 4,                    // H — hand / arrange (clicks fall through)
            fallbackModifiers: Self.hyperModifiers
        )
        desktopInkPassthroughHotKey.registerHotKey(modifiers: inkArrange.modifiers, keyCode: inkArrange.keyCode) { [weak self] _ in
            Task { @MainActor in self?.toggleDesktopInkPassthrough() }
        }
        log.info("Desktop ink hotkeys registered: toggle keyCode=\(inkToggle.keyCode) arrange keyCode=\(inkArrange.keyCode)")

        // Bare-modifier triggers: tap LEFT Ctrl to toggle the ink layer, RIGHT
        // Ctrl to flip draw <-> arrange. Conflict-free dedicated keys; only a
        // clean solitary tap fires (see ModifierTapMonitor), so normal Ctrl use
        // is untouched. Runs alongside the Hyper hotkeys above.
        let tapMonitor = ModifierTapMonitor(watching: [.leftControl, .rightControl])
        tapMonitor.onTap = { [weak self] side in
            Task { @MainActor in
                switch side {
                case .leftControl: self?.toggleDesktopInk()
                case .rightControl: self?.toggleDesktopInkPassthrough()
                }
            }
        }
        tapMonitor.start()
        desktopInkTapMonitor = tapMonitor
        log.info("Desktop ink bare-Ctrl taps armed: left=toggle right=arrange")

        // The screenshot button in the ink toolbar snaps a region; strokes bake
        // in via executeAgentScreenshotCapture's desktop-ink path.
        DesktopInkController.shared.onCaptureRequested = { [weak self] in
            Task { @MainActor in
                await self?.executeAgentScreenshotCapture(mode: .region)
            }
        }

        let magnifier = Self.loadHotkeyConfig(
            key: "hotkeyCapture.desktopMagnifier",
            fallbackKeyCode: 6,                   // Z - freeze a source region into a movable magnifier
            fallbackModifiers: Self.hyperModifiers,
            avoidsAppleScreenshotShortcuts: true
        )
        if magnifier.keyCode == markupCaptureChord.keyCode,
           magnifier.modifiers == markupCaptureChord.modifiers {
            log.warning("Desktop magnifier hotkey skipped because it conflicts with Markup capture")
        } else {
            desktopMagnifierHotKey.registerHotKey(modifiers: magnifier.modifiers, keyCode: magnifier.keyCode) { [weak self] _ in
                Task { @MainActor in self?.startDesktopMagnifier() }
            }
            log.info("Desktop magnifier hotkey registered: keyCode=\(magnifier.keyCode) modifiers=\(magnifier.modifiers)")
        }

        let pasteChord = Self.loadHotkeyConfig(
            key: AgentSettingsKey.pasteChordHotkey,
            fallbackKeyCode: 9,
            fallbackModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey),
            avoidsAppleScreenshotShortcuts: true
        )
        pasteChordHotKeyManager.registerHotKey(
            modifiers: pasteChord.modifiers,
            keyCode: pasteChord.keyCode
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAgentPasteChord()
            }
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
                fallbackModifiers: defaultModifiers,
                avoidsAppleScreenshotShortcuts: true
            )
            if config.keyCode == captureChord.keyCode && config.modifiers == captureChord.modifiers {
                log.info("Direct screenshot hotkey skipped because it matches the capture chord: \(settingsKey)")
                continue
            }
            if config.keyCode == screenRecordChord.keyCode && config.modifiers == screenRecordChord.modifiers {
                log.info("Direct screenshot hotkey skipped because it matches the screen record chord: \(settingsKey)")
                continue
            }
            if config.keyCode == Self.walkieHotkeyKeyCode && config.modifiers == Self.walkieHotkeyModifiers {
                log.info("Direct screenshot hotkey skipped because it matches the talk-to-agents chord: \(settingsKey)")
                continue
            }
            manager.registerHotKey(modifiers: config.modifiers, keyCode: config.keyCode) { _ in
                Task { @MainActor [weak self] in
                    await self?.handleAgentDirectScreenshot(mode: mode)
                }
            }
        }

        log.info("Direct screenshot hotkeys registered from shared settings (defaults: Hyper+3/4/5/6, Hyper+T shelf)")

        let pasteLastScreenshot = Self.loadHotkeyConfig(
            key: AgentSettingsKey.pasteLastScreenshotHotkey,
            fallbackKeyCode: 35,
            fallbackModifiers: Self.hyperModifiers,
            avoidsAppleScreenshotShortcuts: true
        )
        pasteLastScreenshotHotKey.registerHotKey(
            modifiers: pasteLastScreenshot.modifiers,
            keyCode: pasteLastScreenshot.keyCode
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.pasteLatestAgentScreenshot()
            }
        }
        log.info("Paste last screenshot hotkey registered: keyCode=\(pasteLastScreenshot.keyCode) modifiers=\(pasteLastScreenshot.modifiers)")
    }

    private func registerMarkupSafetyHotkey() {
        markupEmergencyHotKey.unregisterAll()
        markupEmergencyHotKey.registerHotKey(
            modifiers: Self.hyperModifiers,
            keyCode: 53
        ) { [weak self] _ in
            Task { @MainActor in
                self?.forceDismissCaptureSurfaces(reason: "Hyper+Escape")
                self?.broadcastMarkupEmergencyDismiss(reason: "Hyper+Escape")
            }
        }
        log.info("Capture markup emergency hotkey registered: Hyper+Escape")
    }

    @MainActor
    private func forceDismissCaptureSurfaces(reason: String) {
        log.warning("Force dismissing capture surfaces", detail: reason)
        ScreenRecordingController.shared.dismissMarkupOverlaysForSafety(reason: reason)
        AgentCaptureMarkupController.shared.dismiss()
        DesktopInkController.shared.hide(clear: true)
        DesktopMagnifierController.shared.dismissForSafety()
        CaptureIslandController.shared.dismiss(animated: false)
        CaptureFreezeStore.shared.clear()
    }

    @objc private func markupEmergencyDismissReceived(_ notification: Notification) {
        let reason = notification.object as? String ?? "shared emergency dismiss"
        forceDismissCaptureSurfaces(reason: reason)
    }

    private func broadcastMarkupEmergencyDismiss(reason: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Self.markupEmergencyDismissNotification,
            object: reason,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @MainActor
    private func toggleDesktopInk() {
        DesktopInkController.shared.toggle()
    }

    @MainActor
    private func toggleDesktopInkPassthrough() {
        DesktopInkController.shared.togglePassthrough()
    }

    @MainActor
    private func startDesktopMagnifier() {
        DesktopMagnifierController.shared.startSelection()
    }

    private func handleAgentCaptureChord(
        initialMode: CaptureBarMode,
        startsMarkupEnabled: Bool = false
    ) async {
        if initialMode == .video {
            if await ScreenRecordingController.shared.stopIfRecording() {
                return
            }
        }

        guard !isAgentCaptureChordActive else { return }
        isAgentCaptureChordActive = true
        defer { isAgentCaptureChordActive = false }

        if startsMarkupEnabled {
            TalkieSharedSettings.set(true, forKey: CaptureDestinationSettings.markupEnabled)
            log.info("Markup capture destination enabled from hotkey")
        }

        let previousApp = NSWorkspace.shared.frontmostApplication
        if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }

        var hudInitialMode = initialMode
        if initialMode == .video {
            switch await ScreenRecordingController.shared.startReusableRecordingWithCountdown() {
            case .started, .cancelled:
                return
            case .needsSelection:
                break
            case .needsSelectionInMode(let mode):
                hudInitialMode = mode
            }
        }

        let chord: any CaptureChordController = CaptureHUDController()
        guard let result = await chord.beginChord(initialMode: hudInitialMode, options: .captureWithPeripherals) else {
            return
        }

        switch result {
        case .screenshot(let mode):
            _ = await executeAgentScreenshotCapture(mode: mode)
        case .screenshotMarkup(let mode):
            _ = await executeAgentScreenshotCapture(mode: mode, opensMarkup: true)
        case .screenshotRegion(let rect):
            _ = await executeAgentScreenshotCapture(mode: .region, preselectedRegion: rect)
        case .screenshotMarkupRegion(let rect):
            _ = await executeAgentScreenshotCapture(mode: .region, preselectedRegion: rect, opensMarkup: true)
        case .screenRecord(let mode):
            await ScreenRecordingController.shared.startRecording(mode: mode)
        case .toggleCamera:
            AgentCameraBubbleController.shared.toggle()
        case .saveSelection:
            log.info("Selection note action ignored in Agent screenshot HUD")
        case .viewTray:
            forwardScreenshotDirectAction(mode: "viewTray")
        case .pasteLastTray:
            await pasteLatestAgentScreenshot(previousApp: previousApp)
        }

        if result.isBackground,
           let previousApp,
           previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }
    }

    private func handleAgentDirectScreenshot(mode: String) async {
        guard !isAgentPasteChordSuppressingShortcutTriggers else {
            log.debug("Ignoring direct screenshot shortcut while Quick Paste HUD is active")
            return
        }

        let now = Date()
        if lastAgentDirectScreenshotMode == mode,
           now.timeIntervalSince(lastAgentDirectScreenshotAt) < 0.20 {
            return
        }
        lastAgentDirectScreenshotMode = mode
        lastAgentDirectScreenshotAt = now

        guard !isAgentDirectScreenshotCaptureActive else { return }
        isAgentDirectScreenshotCaptureActive = true
        defer { isAgentDirectScreenshotCaptureActive = false }

        switch mode {
        case "fullscreen":
            _ = await executeAgentScreenshotCapture(mode: .fullscreen)
        case "region":
            _ = await executeAgentScreenshotCapture(mode: .region)
        case "window":
            _ = await executeAgentScreenshotCapture(mode: .window)
        case "viewTray", "viewShelf":
            forwardScreenshotDirectAction(mode: mode)
        default:
            log.warning("Unknown Agent screenshot shortcut mode", detail: mode)
        }
    }

    @discardableResult
    private func executeAgentScreenshotCapture(
        mode: CaptureMode,
        preselectedRegion: CGRect? = nil,
        opensMarkup: Bool = false
    ) async -> Bool {
        // The ink overlay sits above the capture's own selection UI and is key,
        // so step it aside while we capture — otherwise the crosshair is
        // unreachable. The strokes stay alive for the bake below.
        let inkYielded = DesktopInkController.shared.isActive
        if inkYielded { DesktopInkController.shared.beginCaptureYield() }

        guard let captured = await ScreenshotCaptureService.shared.captureStandalone(
            mode: mode,
            preselectedRegion: preselectedRegion
        ) else {
            if inkYielded { DesktopInkController.shared.endCaptureYield() }
            return false
        }

        // Bake any desktop-ink strokes into the shot. The live ink panel is
        // sharingType .none (invisible to ScreenCaptureKit), so the marks only
        // reach the saved asset through this software composite.
        let (result, bakedInk) = await bakeDesktopInkIfNeeded(into: captured)
        if bakedInk {
            // The strokes are now in the screenshot; drop the on-screen ink so it
            // doesn't linger or double up on the next capture.
            DesktopInkController.shared.hide(clear: true)
        } else if inkYielded {
            // Capture didn't consume the ink (cancelled, or it missed the inked
            // screen) — bring the overlay back so drawing continues.
            DesktopInkController.shared.endCaptureYield()
        }

        let recordedLive = agentController?.recordLiveScreenshot(
            imageData: result.data,
            capturedAt: result.capturedAt,
            captureMode: mode.rawValue,
            width: result.width,
            height: result.height,
            windowTitle: result.windowTitle,
            appName: result.appName,
            displayName: result.displayName
        ) ?? false

        let captureID = UUID()
        guard let persisted = AgentCaptureLibraryWriter.persistScreenshot(
            data: result.data,
            id: captureID,
            capturedAt: result.capturedAt,
            captureMode: mode.rawValue,
            width: result.width,
            height: result.height,
            windowTitle: result.windowTitle,
            appName: result.appName,
            appBundleID: result.appBundleID,
            displayName: result.displayName
        ) else {
            log.error("Agent screenshot Library write failed")
            return recordedLive
        }

        do {
            let stored = try await AgentLiveTrayAssetStore.shared.registerScreenshot(
                fileURL: persisted.fileURL,
                id: captureID,
                capturedAt: result.capturedAt,
                mode: mode.rawValue,
                width: result.width,
                height: result.height,
                windowTitle: result.windowTitle,
                appName: result.appName,
                appBundleID: result.appBundleID,
                displayName: result.displayName
            )
            ScreenRecordingController.shared.recordScreenshotHighlight(
                capturedAt: result.capturedAt,
                filename: stored.filename,
                captureMode: mode.rawValue,
                width: result.width,
                height: result.height,
                windowTitle: result.windowTitle,
                appName: result.appName,
                appBundleID: result.appBundleID,
                displayName: result.displayName
            )
            log.info(
                "Agent screenshot captured",
                detail: "mode=\(mode.rawValue) file=\(stored.filename) live=\(recordedLive)"
            )
            let item = AgentLiveTrayItem(
                id: stored.id,
                kind: .screenshot,
                capturedAt: stored.capturedAt,
                filename: stored.filename,
                width: result.width,
                height: result.height,
                captureMode: mode.rawValue,
                windowTitle: result.windowTitle,
                appName: result.appName,
                appBundleID: result.appBundleID,
                displayName: result.displayName,
                fileURL: stored.fileURL
            )
            if opensMarkup {
                openMarkupForAgentCapture(item, captureRect: result.captureRect)
            } else {
                CaptureIslandController.shared.presentImmediate(
                    item,
                    near: screenshotPreviewAnchor(for: result)
                )
            }
            return true
        } catch {
            log.error("Agent screenshot tray write failed: \(error.localizedDescription)")
            return recordedLive
        }
    }

    private func openMarkupForAgentCapture(_ item: AgentLiveTrayItem, captureRect: CGRect?) {
        log.info("Opening agent screenshot in quick markup", detail: item.fileURL.lastPathComponent)
        AgentCaptureMarkupController.shared.open(item: item, captureRect: captureRect)
    }

    private func screenshotPreviewAnchor(for result: TalkieKit.CaptureResult) -> NSPoint {
        guard let rect = result.captureRect,
              rect.width > 1,
              rect.height > 1 else {
            return NSEvent.mouseLocation
        }
        return NSPoint(x: rect.maxX, y: rect.maxY)
    }

    /// Composite the desktop-ink layer into a freshly captured screenshot so the
    /// strokes bake into the saved asset. Returns the original result untouched
    /// (with `baked == false`) when there's no ink, the mode carries no screen
    /// rect (window captures), or the ink was drawn on a different display.
    ///
    /// The ink layers are normalized 0…1 to the full overlay (one screen). The
    /// renderer's `viewport` rebases them onto whatever sub-rect the screenshot
    /// covers: `imageX/Y` is the captured region's top-left offset inside the
    /// overlay (Y flipped from AppKit's bottom-left to the layers' top-left), and
    /// `imageScale` is points-per-pixel so region crops land in the right place.
    private func bakeDesktopInkIfNeeded(into result: TalkieKit.CaptureResult) async -> (result: TalkieKit.CaptureResult, baked: Bool) {
        let ink = DesktopInkController.shared
        let overlay = ink.overlayScreenFrame
        let layers = ink.currentLayers

        guard ink.hasInk, !layers.isEmpty,
              let region = result.captureRect,
              overlay.width > 1, overlay.height > 1,
              region.width > 1, region.height > 1,
              result.width > 0, result.height > 0,
              overlay.intersects(region) else {
            return (result, false)
        }

        let viewport = CaptureMarkupViewport(
            width: Double(overlay.width),
            height: Double(overlay.height),
            imageX: Double(region.minX - overlay.minX),
            imageY: Double(overlay.maxY - region.maxY),
            imageScale: Double(region.width) / Double(result.width)
        )
        let document = CaptureMarkupDocument(
            imageWidth: Double(result.width),
            imageHeight: Double(result.height),
            viewport: viewport,
            layers: layers
        )

        let source = result.image
        let previewScale = min(1.0, 440.0 / Double(max(result.width, result.height)))

        let baked = await Task.detached(priority: .userInitiated) { () -> (data: Data, image: CGImage, preview: CGImage)? in
            guard let image = CaptureMarkupRenderer.render(image: source, document: document, scale: 1),
                  let data = CaptureMarkupRenderer.encodedData(image: source, document: document, format: .png, scale: 1) else {
                return nil
            }
            let preview = CaptureMarkupRenderer.render(image: source, document: document, scale: previewScale) ?? image
            return (data: data, image: image, preview: preview)
        }.value

        guard let baked else {
            log.error("Desktop ink bake failed; saving screenshot without ink")
            return (result, false)
        }

        log.info(
            "Desktop ink baked into screenshot",
            detail: "layers=\(layers.count) size=\(baked.image.width)x\(baked.image.height)"
        )

        let merged = TalkieKit.CaptureResult(
            data: baked.data,
            image: baked.image,
            previewImage: baked.preview,
            capturedAt: result.capturedAt,
            width: baked.image.width,
            height: baked.image.height,
            windowTitle: result.windowTitle,
            appName: result.appName,
            appBundleID: result.appBundleID,
            displayName: result.displayName,
            captureRect: result.captureRect
        )
        return (merged, true)
    }

    private func handleAgentPasteChord() async {
        guard !isAgentPasteChordSuppressingShortcutTriggers else {
            log.debug("Ignoring Quick Paste chord while a previous Quick Paste trigger is settling")
            return
        }
        isAgentPasteChordActive = true
        pasteChordHotKeyManager.clearPressedState()
        defer {
            pasteChordHotKeyManager.clearPressedState()
            agentPasteChordSuppressesShortcutTriggersUntil = Date().addingTimeInterval(0.35)
            isAgentPasteChordActive = false
        }

        log.info("Quick Paste chord opened")

        let previousApp = NSWorkspace.shared.frontmostApplication
        if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }

        let controller = PasteChordController()
        guard let result = await controller.beginChord() else {
            log.info("Quick Paste chord cancelled")
            return
        }

        if result.format == .dragFile {
            beginFileDrag(item: result.item)
            return
        }

        if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }

        let shouldPaste = await executeAgentPaste(
            item: result.item,
            format: result.format,
            targetApp: previousApp
        )
        guard shouldPaste else { return }

        try? await Task.sleep(for: .milliseconds(80))
        simulateCmdV()
    }

    @MainActor
    private func pasteLatestAgentScreenshot(previousApp: NSRunningApplication? = nil) async {
        guard !isAgentPasteChordSuppressingShortcutTriggers else {
            log.debug("Ignoring paste-last screenshot shortcut while Quick Paste HUD is active")
            return
        }

        let targetApp = previousApp ?? NSWorkspace.shared.frontmostApplication
        guard let latest = await AgentLiveTrayAssetStore.shared
            .recentItems(limit: 20)
            .first(where: \.isScreenshot) else {
            log.info("Paste latest screenshot: no Agent tray screenshot available")
            return
        }

        guard await executeAgentPaste(item: latest, format: .image, targetApp: targetApp) else {
            return
        }

        if let targetApp, targetApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp.activate()
        }
        try? await Task.sleep(for: .milliseconds(80))
        simulateCmdV()
    }

    private var isAgentPasteChordSuppressingShortcutTriggers: Bool {
        isAgentPasteChordActive || Date() < agentPasteChordSuppressesShortcutTriggersUntil
    }

    @MainActor
    private func executeAgentPaste(
        item: AgentLiveTrayItem,
        format: PasteFormat,
        targetApp: NSRunningApplication?
    ) async -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch format {
        case .image:
            guard item.isScreenshot,
                  let data = try? Data(contentsOf: item.fileURL),
                  let durableURL = durablePasteURL(for: item, data: data) else {
                return false
            }
            writeScreenshotPasteboard(data: data, fileURL: durableURL)
            log.info("Quick Paste: Agent screenshot image + markdown → clipboard")
            return true

        case .filePath:
            pasteboard.setString(item.fileURL.path, forType: .string)
            log.info("Quick Paste: Agent tray file path → clipboard")
            return true

        case .url:
            let urlString = "http://localhost:8766/tray/\(item.id.uuidString).png"
            pasteboard.setString(urlString, forType: .string)
            log.info("Quick Paste: Agent tray URL → clipboard")
            return true

        case .base64:
            guard item.isScreenshot,
                  let data = try? Data(contentsOf: item.fileURL) else {
                return false
            }
            pasteboard.setString("data:image/png;base64," + data.base64EncodedString(), forType: .string)
            log.info("Quick Paste: Agent screenshot base64 → clipboard")
            return true

        case .visionDescription:
            let fallback = agentPasteDescription(for: item, targetApp: targetApp)
            pasteboard.setString(fallback, forType: .string)
            log.info("Quick Paste: Agent tray fallback description → clipboard")
            return true

        case .dragFile:
            return false
        }
    }

    private func agentPasteDescription(
        for item: AgentLiveTrayItem,
        targetApp: NSRunningApplication?
    ) -> String {
        let mediaKind = item.isClip ? "screen recording" : "screenshot"
        let dimensions = "\(item.width)×\(item.height)"
        let source = [item.appName, item.windowTitle, item.displayName]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " · ")
        let target: String?
        if let trimmed = targetApp?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            target = trimmed
        } else {
            target = nil
        }
        return [
            "Talkie \(mediaKind)",
            source.isEmpty ? nil : source,
            dimensions,
            target.map { "target: \($0)" },
            item.fileURL.path
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private func durablePasteURL(for item: AgentLiveTrayItem, data: Data) -> URL? {
        ScreenshotStorage.saveStandalone(
            data,
            capturedAt: item.capturedAt,
            captureMode: item.captureMode,
            width: item.width,
            height: item.height,
            windowTitle: item.windowTitle,
            appName: item.appName,
            displayName: item.displayName
        )
    }

    private func writeScreenshotPasteboard(data: Data, fileURL: URL) {
        let markdown = "[Talkie Capture](<\(fileURL.path)>)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        pasteboard.setData(data, forType: .png)
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    @MainActor
    private func beginFileDrag(item: AgentLiveTrayItem) {
        let panel = FileDragPanel()
        panel.show(item: item)
        fileDragPanel = panel
    }

    private func forwardScreenshotDirectAction(mode: String) {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("to.talkie.app.screenshotDirect"),
            object: mode,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func unregisterCaptureHotkeys() {
        screenshotHotKeyManager.unregisterAll()
        markupScreenshotHotKeyManager.unregisterAll()
        screenRecordHotKeyManager.unregisterAll()
        pasteChordHotKeyManager.unregisterAll()
        ssFullscreenHotKey.unregisterAll()
        ssRegionHotKey.unregisterAll()
        ssBufferHotKey.unregisterAll()
        ssWindowHotKey.unregisterAll()
        ssShelfHotKey.unregisterAll()
        pasteLastScreenshotHotKey.unregisterAll()
        desktopInkHotKey.unregisterAll()
        desktopInkPassthroughHotKey.unregisterAll()
        desktopMagnifierHotKey.unregisterAll()
        markupEmergencyHotKey.unregisterAll()
        desktopInkTapMonitor?.stop()
        desktopInkTapMonitor = nil
    }

    private func registerSelectionQuickHotkey() {
        let selectionQuickHotkey = LiveSettings.shared.selectionQuickHotkey
        speakSelectionHotKeyManager.registerHotKey(
            modifiers: selectionQuickHotkey.modifiers,
            keyCode: selectionQuickHotkey.keyCode
        ) { [weak self] _ in
            Task { @MainActor in
                log.info(
                    "Quick selection hotkey pressed",
                    detail: "shortcut=\(selectionQuickHotkey.displayString) enabled=\(Self.isSelectionQuickEnabled())"
                )
                self?.speakSelectedText()
            }
        }

        let registrationDetail = [
            "shortcut=\(selectionQuickHotkey.displayString)",
            "keyCode=\(selectionQuickHotkey.keyCode)",
            "modifiers=\(selectionQuickHotkey.modifiers)"
        ].joined(separator: " ")
        if speakSelectionHotKeyManager.isRegistered {
            log.info("Quick selection hotkey registered", detail: registrationDetail)
        } else {
            log.error("Quick selection hotkey registration failed", detail: registrationDetail)
        }
    }

    private func refreshHotkeyManagerDiagnostics(pttEnabled: Bool, ambientEnabled: Bool) {
        var managers: [(label: String, manager: HotKeyManager)] = [
            ("Toggle Recording", hotKeyManager),
            ("Queue Picker", queuePickerHotKeyManager),
            ("Compose", composeHotKeyManager),
            ("Speak Selection", speakSelectionHotKeyManager),
            ("Talk to Agents", agentVoiceHotKeyManager),
        ]

        if Self.captureFeatureEnabled {
            managers.append(("Screenshot Chord", screenshotHotKeyManager))
            managers.append(("Markup Screenshot Chord", markupScreenshotHotKeyManager))
            managers.append(("Screen Record", screenRecordHotKeyManager))
            managers.append(("Paste Chord", pasteChordHotKeyManager))
            managers.append(("Hyper+3 Fullscreen", ssFullscreenHotKey))
            managers.append(("Hyper+4 Region", ssRegionHotKey))
            managers.append(("Hyper+5 Tray", ssBufferHotKey))
            managers.append(("Hyper+6 Window", ssWindowHotKey))
            managers.append(("Hyper+T Shelf", ssShelfHotKey))
            managers.append(("Hyper+P Paste Last Screenshot", pasteLastScreenshotHotKey))
            managers.append(("Hyper+Z Desktop Magnifier", desktopMagnifierHotKey))
        }
        managers.append(("Hyper+Esc Markup Safety", markupEmergencyHotKey))

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
            AgentConsole.critical("[HotKey] Toggle hotkey callback fired (dispatch: %dms)", timestamp.elapsedMs())
            guard let self else {
                AgentConsole.critical("[HotKey] ⚠️ self is nil in hotkey callback!")
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

        // Register agent voice hotkey — default Hyper+T (⇧⌃⌥⌘T). Press-and-hold
        // semantics: press blooms the floating instrument, release dismisses.
        // Unit 1 (TLK-020): mechanic only — no audio, no LLM yet.
        agentVoiceHotKeyManager.registerHotKey(
            modifiers: Self.walkieHotkeyModifiers,
            keyCode: Self.walkieHotkeyKeyCode,
            onPress: { _ in
                Task { @MainActor in
                    AgentVoiceController.shared.press()
                }
            },
            onRelease: {
                Task { @MainActor in
                    AgentVoiceController.shared.release()
                }
            }
        )
        log.info("Talk-to-agents hotkey registered: ⇧⌃⌥⌘T")

        // Track what we registered to avoid needless re-registration
        lastHotkey = settings.hotkey
        lastPTTHotkey = settings.pttHotkey
        lastPTTEnabled = settings.pttEnabled
    }

    @objc private func hotkeyDidChange() {
        guard BootSequence.shared.isComplete else { return }

        let settings = LiveSettings.shared
        AgentConsole.critical("[HotKey] hotkeyDidChange: re-registering (keyCode=%d, modifiers=%d)", settings.hotkey.keyCode, settings.hotkey.modifiers)
        log.info("Received .hotkeyDidChange notification")
        log.debug("Current hotkey: \(settings.hotkey.displayString) (keyCode=\(settings.hotkey.keyCode), modifiers=\(settings.hotkey.modifiers))")

        // Unregister old hotkeys and register new ones
        hotKeyManager.unregisterAll()
        pttHotKeyManager.unregisterAll()
        speakSelectionHotKeyManager.unregisterAll()
        agentVoiceHotKeyManager.unregisterAll()
        unregisterCaptureHotkeys()
        registerHotkeys()
        registerSelectionQuickHotkey()
        registerCaptureHotkeys()
        registerMarkupSafetyHotkey()

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
        guard let menu = agentStatusMenu else {
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
        guard let agentController else {
            log.warning("Recording toggle requested before audio engine was ready")
            return
        }

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
                TalkieAppOpener.open(url)
                return
            }
        }

        // No text or encoding failed — still open Compose
        log.debug("No selected text found - opening Compose without text")
        if let url = URL(string: "\(TalkieEnvironment.current.talkieURLScheme)://compose") {
            TalkieAppOpener.open(url)
        }
    }

    /// Capture selected text from the frontmost app and ask Talkie to speak it.
    private func speakSelectedText() {
        guard Self.isSelectionQuickEnabled() else {
            log.info("Quick selection ignored: feature disabled")
            selectionFeedbackController.show(
                SelectionFeedbackMessage(
                    title: "Quick Selection is off",
                    detail: "Turn it on in Talkie Settings > Selection.",
                    tone: .warning,
                    actionTitle: nil,
                    action: nil
                ),
                duration: 1.8
            )
            return
        }

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

    private static func isSelectionQuickEnabled() -> Bool {
        TalkieSharedSettings.object(forKey: AgentSettingsKey.selectionEnabled) as? Bool ?? true
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
        toggleStreamingWake()
        sender.state = AmbientSettings.shared.useStreamingASR ? .on : .off
    }

    private func toggleStreamingWake() {
        let newValue = !AmbientSettings.shared.useStreamingASR
        AmbientSettings.shared.useStreamingASR = newValue
        log.info("Streaming wake detection: \(newValue ? "enabled" : "disabled")")

        // If ambient is currently running, it will pick up the change via the settings binding
    }

    @objc private func showHistory() {
        // Show lightweight history panel within TalkieAgent
        HistoryPanelController.shared.show()
    }

    @objc private func showAgentHome() {
        AgentHomeController.shared.show()
    }

    // MARK: - Recent Dictations

    @objc private func copyRecentDictation(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        copyRecentDictationText(text)
    }

    private func copyRecentDictationText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        log.info("Copied dictation to clipboard: \(text.prefix(30))...")
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            self.updateRecordingMenuItem(isRecording: self.agentController?.state == .listening)
            self.updateRecentMenu()
            self.updatePermissionsMenuItem()
            self.updateAmbientMenuItem()
            self.updateStreamingMenuItem()
            self.updateClearQueueMenuItem()
        }
    }

    private func updateAmbientMenuItem() {
        guard let menu = agentStatusMenu,
              let ambientItem = menu.items.first(where: { $0.action == #selector(toggleAmbientModeFromMenu) }) else {
            return
        }
        ambientItem.state = AmbientSettings.shared.isEnabled ? .on : .off
    }

    private func updateStreamingMenuItem() {
        guard let menu = agentStatusMenu,
              let streamingItem = menu.items.first(where: { $0.action == #selector(toggleStreamingWakeFromMenu) }) else {
            return
        }
        streamingItem.state = AmbientSettings.shared.useStreamingASR ? .on : .off
    }

    private func updateClearQueueMenuItem() {
        guard let menu = agentStatusMenu,
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
        guard let menu = agentStatusMenu,
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
        guard let menu = agentStatusMenu,
              let recentItem = menu.items.first(where: { $0.title == "Recent" }),
              let submenu = recentItem.submenu else { return }

        submenu.removeAllItems()

        let store = DictationStore.shared
        let recent = Array(store.utterances.prefix(5))

        if recent.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent dictations", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for (index, utterance) in recent.enumerated() {
                let displayText = Self.truncatedMenuText(utterance.text, limit: 40)
                let timeAgo = utterance.timestamp.timeAgoShort

                let item = NSMenuItem(
                    title: displayText,
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

    // MARK: - Restart / Quit

    @objc private func restartAgent() {
        log.info("User requested Talkie Agent restart")

        let env = TalkieEnvironment.current
        let uid = getuid()
        let labels = [
            TalkieHelper.agent.bundleId(for: env),
            TalkieHelper.agent.xpcServiceName(for: env)
        ]

        for label in labels where launchAgentIsLoaded(label: label, uid: uid) {
            if kickstartLaunchAgent(label: label, uid: uid) {
                return
            }
        }

        relaunchCurrentBundle()
    }

    private func launchAgentIsLoaded(label: String, uid: uid_t) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(uid)/\(label)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            log.warning("Could not inspect launch agent \(label): \(error.localizedDescription)")
            return false
        }
    }

    private func kickstartLaunchAgent(label: String, uid: uid_t) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(uid)/\(label)"]

        do {
            try process.run()
            log.info("Restarting Talkie Agent via launchctl", detail: label)
            return true
        } catch {
            log.error("Failed to restart launch agent \(label): \(error.localizedDescription)")
            return false
        }
    }

    private func relaunchCurrentBundle() {
        let appURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    log.error("Failed to relaunch Talkie Agent: \(error.localizedDescription)")
                    self?.showToast(emoji: "⚠️", message: "Restart failed", color: .systemOrange)
                    return
                }

                log.info("Relaunched Talkie Agent from bundle", detail: appURL.path)
                NSApp.terminate(nil)
            }
        }
    }

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
        AgentHomeController.shared.showSettings()
    }

    private func openLogsDirectory() {
        let logsDirectory = TalkieEnvironment.current.logsDirectory

        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(logsDirectory)
            log.info("Opened Talkie logs directory", detail: logsDirectory.path)
        } catch {
            log.error("Failed to open Talkie logs directory: \(error.localizedDescription)")
            showToast(emoji: "⚠️", message: "Could not open logs", color: .systemOrange)
        }
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
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Store reference
        settingsWindow = window

        AgentAppPresentationController.shared.retainRegularPresentation(for: "settings")

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPermissions() {
        // Deep-link into Agent Home's Permissions tab (the new app surface)
        // instead of spawning the legacy standalone QuickSettings window.
        AgentHomeController.shared.show(section: .permissions)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }

        settingsWindow = nil
        AgentAppPresentationController.shared.releaseRegularPresentation(for: "settings")
    }

    private func updateIcon(for state: LiveState) {
        guard let button = statusItem.button else { return }

        // Update icon based on state:
        // - Idle/processing: Talkie glyph
        // - Listening: Talkie glyph plus bottom-left Hot Mic dot
        let isRecording = state == .listening

        updateMenuBarIcon(isRecording: isRecording)

        // Clear any text suffix (no more big dot)
        button.title = ""

        // Update menu item text
        updateRecordingMenuItem(isRecording: isRecording)
    }

    /// Update the "Start Recording" / "Stop Recording" menu item
    private func updateRecordingMenuItem(isRecording: Bool) {
        guard let menu = agentStatusMenu,
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

struct SelectionSpeechAudio {
    let data: Data
    let format: String
    let mimeType: String
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

        let synthesis = try await synthesizeSelectionAudio(text)
        try playSynthesizedAudio(synthesis)
        return SelectionSpeechPlaybackResult(
            voiceId: synthesis.voiceId,
            provider: synthesis.provider,
            model: synthesis.model
        )
    }

    func synthesizeSelectionAudio(_ text: String) async throws -> SelectionSpeechAudio {
        var lastError: Error?
        for voiceId in candidateVoiceIDs() {
            do {
                let synthesis = try await synthesizeSelection(text: text, selectedVoiceId: voiceId)
                if synthesis.voiceId != voiceId {
                    log.info("Quick selection TTS used normalized voice", detail: "requested=\(voiceId) used=\(synthesis.voiceId)")
                }
                let audioData = try Data(contentsOf: synthesis.audioURL)
                let descriptor = speechAudioDescriptor(for: synthesis.audioURL)
                return SelectionSpeechAudio(
                    data: audioData,
                    format: descriptor.format,
                    mimeType: descriptor.mimeType,
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

    func playSynthesizedAudio(_ audio: SelectionSpeechAudio) throws {
        stopPlayback(notify: false)
        try playAudioData(audio.data)
    }

    private func playAudioData(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
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

    private func speechAudioDescriptor(for url: URL) -> (format: String, mimeType: String) {
        switch url.pathExtension.lowercased() {
        case "mp3":
            return ("mp3", "audio/mpeg")
        case "wav":
            return ("wav", "audio/wav")
        case "caf":
            return ("caf", "audio/x-caf")
        case "m4a":
            return ("m4a", "audio/mp4")
        case "aac":
            return ("aac", "audio/aac")
        default:
            return ("unknown", "application/octet-stream")
        }
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
        let agentVoiceId = TalkieSharedSettings.string(forKey: AgentSettingsKey.agentVoiceTTSVoiceId)
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

        append(agentVoiceId)
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
