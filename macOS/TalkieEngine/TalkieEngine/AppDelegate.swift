//
//  AppDelegate.swift
//  TalkieEngine
//
//  Background app that hosts the transcription XPC service
//  Now with menu bar presence and status dashboard
//

import Cocoa
import SwiftUI

// Note: @main is in main.swift which sets up XPC before NSApplication
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statusWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.info(.system, "TalkieEngine app delegate ready")
        // Signal handling is set up in main.swift before run loop starts

        // Ensure we have window server access (needed when launched by launchd)
        NSApp.setActivationPolicy(.accessory)

        // Set up menu bar item
        setupMenuBar()

        // Log to status manager
        EngineStatusManager.shared.log(.info, "AppDelegate", "TalkieEngine ready")

        // Auto-preload default model (parakeet:v3) on startup
        Task {
            await autoPreloadDefaultModel()
        }
    }

    // MARK: - Auto Preload

    /// Automatically preload the default model on startup so clients don't have to
    @MainActor
    private func autoPreloadDefaultModel() async {
        let defaultModelId = "parakeet:v3"
        AppLogger.shared.info(.model, "Auto-preloading default model: \(defaultModelId)")
        EngineStatusManager.shared.log(.info, "AutoPreload", "Preloading default model: \(defaultModelId)")

        let startTime = Date()

        await withCheckedContinuation { continuation in
            engineService.preloadModel(defaultModelId) { error in
                Task { @MainActor in
                    if let error = error {
                        AppLogger.shared.error(.model, "Auto-preload failed: \(error)")
                        EngineStatusManager.shared.log(.error, "AutoPreload", "Failed: \(error)")
                    } else {
                        let elapsed = Date().timeIntervalSince(startTime)
                        AppLogger.shared.info(.model, "Auto-preload complete in \(String(format: "%.1f", elapsed))s")
                        EngineStatusManager.shared.log(.info, "AutoPreload", "✓ Default model ready in \(String(format: "%.1f", elapsed))s")
                    }
                    continuation.resume()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("[TalkieEngine] 🛑 applicationWillTerminate - beginning graceful shutdown")
        AppLogger.shared.info(.system, "TalkieEngine shutting down gracefully")
        EngineStatusManager.shared.log(.info, "AppDelegate", "Shutting down gracefully...")

        // Suspend XPC listener to stop accepting new connections
        xpcListener?.suspend()

        // Invalidate XPC listener to close existing connections gracefully
        xpcListener?.invalidate()

        // Give in-flight XPC calls time to complete
        Thread.sleep(forTimeInterval: 0.2)

        NSLog("[TalkieEngine] ✅ Shutdown complete")
        AppLogger.shared.info(.system, "TalkieEngine shutdown complete")
    }

    // MARK: - URL Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "talkieengine" else { return }

        AppLogger.shared.info(.system, "Received URL: \(url.absoluteString)")
        EngineStatusManager.shared.log(.info, "URL", "Received: \(url.absoluteString)")

        // Handle talkieengine://dashboard (or legacy "status")
        if url.host == "dashboard" || url.host == "status" {
            showStatusWindow()
            return
        }

        // Handle talkieengine://trace/{refId}
        if url.host == "trace" {
            let refId = url.lastPathComponent
            // Validate refId: must be non-empty, not equal to path component, and a valid UUID format
            if !refId.isEmpty && refId != "trace" && isValidRefId(refId) {
                showTraceDetail(refId: refId)
            } else {
                // Invalid or missing refId - just show the performance tab
                AppLogger.shared.warning(.system, "Invalid refId in URL: '\(refId)'")
                showStatusWindow()
            }
        }
    }

    /// Validate that refId is a valid 8-character hex string
    /// This prevents injection attacks and ensures we only accept properly formatted IDs
    private func isValidRefId(_ refId: String) -> Bool {
        // Must be exactly 8 lowercase hex characters
        guard refId.count == 8 else { return false }

        // Validate hex format: only 0-9 and a-f allowed
        let hexPattern = "^[0-9a-f]{8}$"
        return refId.range(of: hexPattern, options: .regularExpression) != nil
    }

    private func showTraceDetail(refId: String) {
        AppLogger.shared.info(.system, "Showing trace detail for refId: \(refId)")
        EngineStatusManager.shared.log(.info, "URL", "Looking up trace: \(refId)")

        // Set the highlighted metric
        EngineStatusManager.shared.highlightedMetricRefId = refId

        // Open the status window
        showStatusWindow()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use a gear/engine icon with mode-specific color
            let mode = EngineStatusManager.shared.launchMode
            let iconColor: NSColor = switch mode {
            case .dev: NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0)
            case .staging: NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)  // Orange for staging
            case .production: .gray
            }

            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [iconColor]))
            let image = NSImage(systemSymbolName: "engine.combustion", accessibilityDescription: "TalkieEngine")
            image?.isTemplate = false  // Allow custom coloring
            button.image = image?.withSymbolConfiguration(config)
            button.imagePosition = .imageOnly
            button.action = #selector(toggleStatusWindow)
            button.target = self
        }

        // Build menu
        let menu = NSMenu()

        let mode = EngineStatusManager.shared.launchMode
        menu.addItem(NSMenuItem(title: "TalkieEngine (\(mode.rawValue))", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "Show Status...", action: #selector(showStatusWindow), keyEquivalent: "s")
        statusMenuItem.target = self
        menu.addItem(statusMenuItem)

        // Add daemon control options for dev mode
        if mode == .dev {
            menu.addItem(NSMenuItem.separator())

            let reloadItem = NSMenuItem(title: "Reload Engine", action: #selector(reloadEngine), keyEquivalent: "r")
            reloadItem.target = self
            menu.addItem(reloadItem)

            menu.addItem(NSMenuItem.separator())

            if EngineStatusManager.shared.isDaemonMode {
                // Running as daemon - offer to stop
                let stopDaemonItem = NSMenuItem(title: "Stop & Disable Daemon", action: #selector(stopAndDisableDaemon), keyEquivalent: "")
                stopDaemonItem.target = self
                menu.addItem(stopDaemonItem)
            } else {
                // Running from Xcode - offer to switch to daemon OR take over from daemon
                let switchToDaemonItem = NSMenuItem(title: "Switch to Daemon Mode", action: #selector(switchToDaemonMode), keyEquivalent: "")
                switchToDaemonItem.target = self
                menu.addItem(switchToDaemonItem)

                let takeOverItem = NSMenuItem(title: "Stop Daemon (Dev Takes Over)", action: #selector(stopDaemonForDev), keyEquivalent: "")
                takeOverItem.target = self
                menu.addItem(takeOverItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit TalkieEngine", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleStatusWindow() {
        if statusWindow?.isVisible == true {
            statusWindow?.close()
        } else {
            showStatusWindow()
        }
    }

    @objc private func showStatusWindow() {
        if statusWindow == nil {
            let contentView = EngineStatusView()

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "TalkieEngine Status"
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.setFrameAutosaveName("TalkieEngineStatus")
            window.isReleasedWhenClosed = false

            // Dark appearance
            window.appearance = NSAppearance(named: .darkAqua)

            statusWindow = window
        }

        statusWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reloadEngine() {
        AppLogger.shared.info(.system, "Manual reload requested via menu")
        EngineStatusManager.shared.log(.info, "System", "Reloading engine...")

        // For dev/debug modes: kill current process and relaunch from stable path
        // Find stable build path (where run.sh installs the engine)
        let buildPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("dev/talkie/build/Debug/TalkieEngine.app")

        if FileManager.default.fileExists(atPath: buildPath.path) {
            AppLogger.shared.info(.system, "Relaunching from: \(buildPath.path)")

            // Launch new instance
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [buildPath.path]

            do {
                try task.run()
                AppLogger.shared.info(.system, "New instance launched, exiting current")

                // Exit current instance after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    exit(0)
                }
            } catch {
                AppLogger.shared.error(.system, "Failed to relaunch: \(error)")
                EngineStatusManager.shared.log(.error, "Reload", "Failed: \(error.localizedDescription)")
            }
        } else {
            AppLogger.shared.error(.system, "Stable build not found at: \(buildPath.path)")
            EngineStatusManager.shared.log(.error, "Reload", "Build path not found - run ./run.sh engine first")
        }
    }

    @objc private func stopAndDisableDaemon() {
        // Use launchdLabel (the plist Label), not activeServiceName (the XPC MachService)
        let launchdLabel = EngineStatusManager.shared.launchMode.launchdLabel
        let userID = getuid()

        AppLogger.shared.info(.system, "Stopping and disabling daemon: \(launchdLabel)")
        EngineStatusManager.shared.log(.warning, "Daemon", "Disabling daemon - will not auto-restart")

        // Unload the launchd service
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["bootout", "gui/\(userID)/\(launchdLabel)"]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.info(.system, "Daemon disabled successfully")
                EngineStatusManager.shared.log(.info, "Daemon", "✓ Daemon disabled - use 'launchctl bootstrap' to re-enable")

                // Show notification
                let notification = NSUserNotification()
                notification.title = "TalkieEngine Daemon Disabled"
                notification.informativeText = "The daemon will not auto-restart. Use 'launchctl bootstrap' or the installer script to re-enable."
                NSUserNotificationCenter.default.deliver(notification)

                // Exit after disabling
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApp.terminate(nil)
                }
            } else {
                AppLogger.shared.error(.system, "Failed to disable daemon (exit code: \(task.terminationStatus))")
                EngineStatusManager.shared.log(.error, "Daemon", "Failed to disable (may already be stopped)")
            }
        } catch {
            AppLogger.shared.error(.system, "Error disabling daemon: \(error)")
            EngineStatusManager.shared.log(.error, "Daemon", "Error: \(error.localizedDescription)")
        }
    }

    @objc private func stopDaemonForDev() {
        // Stop the daemon so this dev instance can take over the XPC service
        let launchdLabel = EngineStatusManager.shared.launchMode.launchdLabel
        let userID = getuid()

        AppLogger.shared.info(.system, "Stopping daemon for dev takeover: \(launchdLabel)")
        EngineStatusManager.shared.log(.info, "Daemon", "Stopping daemon - dev will take over")

        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["bootout", "gui/\(userID)/\(launchdLabel)"]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.info(.system, "Daemon stopped - dev is now primary")
                EngineStatusManager.shared.log(.info, "Daemon", "✓ Daemon stopped - dev instance is now primary")
            } else if task.terminationStatus == 3 {
                // Exit code 3 = not running, which is fine
                AppLogger.shared.info(.system, "Daemon was not running")
                EngineStatusManager.shared.log(.info, "Daemon", "Daemon was not running - dev is primary")
            } else {
                AppLogger.shared.error(.system, "Failed to stop daemon (exit code: \(task.terminationStatus))")
                EngineStatusManager.shared.log(.error, "Daemon", "Failed to stop (code: \(task.terminationStatus))")
            }
        } catch {
            AppLogger.shared.error(.system, "Error stopping daemon: \(error)")
            EngineStatusManager.shared.log(.error, "Daemon", "Error: \(error.localizedDescription)")
        }
    }

    @objc private func switchToDaemonMode() {
        let launchdLabel = EngineStatusManager.shared.launchMode.launchdLabel
        let userID = getuid()
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(launchdLabel).plist"

        AppLogger.shared.info(.system, "Switching to daemon mode: \(launchdLabel)")
        EngineStatusManager.shared.log(.info, "Daemon", "Switching to daemon mode...")

        // Check if plist exists
        guard FileManager.default.fileExists(atPath: plistPath) else {
            AppLogger.shared.error(.system, "Daemon plist not found at: \(plistPath)")
            EngineStatusManager.shared.log(.error, "Daemon", "Plist not found - run install script first")

            let alert = NSAlert()
            alert.messageText = "Daemon Not Installed"
            alert.informativeText = "The daemon plist was not found at:\n\(plistPath)\n\nRun the install script first."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        // Bootstrap (load) the launchd service
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["bootstrap", "gui/\(userID)", plistPath]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.info(.system, "Daemon started successfully")
                EngineStatusManager.shared.log(.info, "Daemon", "✓ Daemon started - quitting Xcode instance")

                // Quit this instance - daemon will take over
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            } else {
                // Exit code 37 = already loaded, which is fine
                if task.terminationStatus == 37 {
                    AppLogger.shared.info(.system, "Daemon already running")
                    EngineStatusManager.shared.log(.info, "Daemon", "Daemon already running - quitting Xcode instance")

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApp.terminate(nil)
                    }
                } else {
                    AppLogger.shared.error(.system, "Failed to start daemon (exit code: \(task.terminationStatus))")
                    EngineStatusManager.shared.log(.error, "Daemon", "Failed to start daemon (code: \(task.terminationStatus))")
                }
            }
        } catch {
            AppLogger.shared.error(.system, "Error starting daemon: \(error)")
            EngineStatusManager.shared.log(.error, "Daemon", "Error: \(error.localizedDescription)")
        }
    }

    @objc private func quitApp() {
        // If this is an Xcode debug build (not daemon), offer to re-enable the daemon
        if EngineStatusManager.shared.launchMode == .dev && !EngineStatusManager.shared.isDaemonMode {
            offerToReenableDaemon()
        } else {
            NSApp.terminate(nil)
        }
    }

    private func offerToReenableDaemon() {
        let alert = NSAlert()
        alert.messageText = "Re-enable Daemon?"
        alert.informativeText = "Would you like to re-enable the TalkieEngine daemon before quitting?\n\nThis will restore automatic background operation."
        alert.addButton(withTitle: "Re-enable & Quit")
        alert.addButton(withTitle: "Just Quit")
        alert.alertStyle = .informational

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Re-enable daemon
            reenableDaemon()
            // Quit after re-enabling
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        } else {
            // Just quit without re-enabling
            NSApp.terminate(nil)
        }
    }

    private func reenableDaemon() {
        // Use launchdLabel (the plist Label), not activeServiceName (the XPC MachService)
        let launchdLabel = EngineStatusManager.shared.launchMode.launchdLabel
        let userID = getuid()
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(launchdLabel).plist"

        AppLogger.shared.info(.system, "Re-enabling daemon: \(launchdLabel)")

        // Bootstrap (load) the launchd service
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["bootstrap", "gui/\(userID)", plistPath]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.info(.system, "Daemon re-enabled successfully")

                // Show notification
                let notification = NSUserNotification()
                notification.title = "TalkieEngine Daemon Enabled"
                notification.informativeText = "The daemon will auto-start and run in the background."
                NSUserNotificationCenter.default.deliver(notification)
            } else {
                AppLogger.shared.warning(.system, "Failed to re-enable daemon (exit code: \(task.terminationStatus)) - may already be running")
            }
        } catch {
            AppLogger.shared.error(.system, "Error re-enabling daemon: \(error)")
        }
    }

}
