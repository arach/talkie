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
        AppLogger.shared.info(.system, "TalkieEngine shutting down")
        EngineStatusManager.shared.log(.info, "AppDelegate", "Shutting down...")
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
            case .debug: .orange
            case .dev: NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0)
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

        // Add reload option for debug and dev modes
        if mode == .debug || mode == .dev {
            menu.addItem(NSMenuItem.separator())

            let reloadItem = NSMenuItem(title: "Reload Engine", action: #selector(reloadEngine), keyEquivalent: "r")
            reloadItem.target = self
            menu.addItem(reloadItem)
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
        Task { @MainActor in
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
                        autoreleasepool {
                            exit(0)
                        }
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
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

}
