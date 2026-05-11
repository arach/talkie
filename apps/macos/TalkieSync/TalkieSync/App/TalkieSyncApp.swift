//
//  TalkieSyncApp.swift
//  TalkieSync
//
//  Background sync service with optional settings/performance windows.
//  Runs as a background agent (no dock icon, no menu bar).
//

import SwiftUI
import AppKit
import Security
import TalkieKit

private let log = Log(.sync)

@main
struct TalkieSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows - this is a background service
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // Windows for settings and performance views
    private var settingsWindow: NSWindow?
    private var performanceWindow: NSWindow?

    // WebSocket bridge for CLI access
    private var bridge: ServiceBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure TalkieLogger FIRST (before any log calls)
        TalkieLogger.configure(source: .talkieSync, minimumLevel: .debug)

        log.info("TalkieSync starting... (env: \(TalkieEnvironment.current.displayName))", critical: true)
        log.info("TalkieSync foundation: cloudkit-direct-v1", critical: true)
        logBuildFingerprint()
        logRuntimeEntitlements()

        // Hide from dock (we're a background service)
        NSApp.setActivationPolicy(.accessory)

        // Scaffolding-first startup: bring up XPC immediately and defer heavy
        // Core Data/CloudKit initialization until first sync request.
        TalkieSyncXPCService.shared.startListenerOnly()
        TalkieSyncXPCService.shared.postReadinessSignal()

        // Start WebSocket bridge for CLI access (ws://127.0.0.1:19820)
        startBridge()

        log.info("TalkieSync started (scaffolding ready, Core Data deferred)")
    }

    // MARK: - WebSocket Bridge

    private func startBridge() {
        let bridge = ServiceBridge(port: 19820, serviceName: "TalkieSync")

        bridge.handle("ping") { _, reply in
            reply(["pong": true], nil)
        }

        bridge.handleStreaming("syncNow") { params, progress, reply in
            let limit = params?["limit"] as? Int ?? 0
            let sinceDate: Date? = {
                guard let raw = params?["since"] as? String, !raw.isEmpty else { return nil }
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = fmt.date(from: raw) { return d }
                fmt.formatOptions = [.withInternetDateTime]
                if let d = fmt.date(from: raw) { return d }
                // Try yyyy-MM-dd
                let dayFmt = DateFormatter()
                dayFmt.dateFormat = "yyyy-MM-dd"
                dayFmt.timeZone = TimeZone.current
                return dayFmt.date(from: raw)
            }()

            let full = params?["full"] as? Bool ?? false

            let options: CloudKitDirectSyncEngine.SyncOptions
            if full {
                // Explicit full sync — fetch all records from CloudKit
                options = .all
            } else if limit > 0 || sinceDate != nil {
                // Explicit constraints from CLI flags — use as-is
                var opts = CloudKitDirectSyncEngine.SyncOptions.all
                if limit > 0 { opts.limit = limit }
                opts.since = sinceDate
                options = opts
            } else {
                // No explicit constraints — use incremental (same as UI "Sync Now")
                options = TalkieSyncXPCService.shared.incrementalOptions()
            }

            TalkieSyncXPCService.shared.performSync(options: options, onProgress: progress) { stats, error in
                reply(stats, error)
            }
        }

        bridge.handle("status") { _, reply in
            TalkieSyncXPCService.shared.getStatus { data in
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    reply(nil, "Failed to get status")
                    return
                }
                reply(json, nil)
            }
        }

        bridge.handle("runSyncPass") { _, reply in
            TalkieSyncXPCService.shared.runSyncPass { syncedCount, error in
                reply(["syncedCount": syncedCount], error)
            }
        }

        bridge.handle("iCloudCheck") { _, reply in
            TalkieSyncXPCService.shared.checkiCloudAvailability { available, error in
                reply(["available": available], error)
            }
        }

        bridge.handle("providers") { _, reply in
            TalkieSyncXPCService.shared.listProviders { data in
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) else {
                    reply(nil, "Failed to get providers")
                    return
                }
                reply(["providers": json], nil)
            }
        }

        bridge.handle("remoteMemoCount") { _, reply in
            TalkieSyncXPCService.shared.getRemoteMemoCount { count in
                reply(["count": count], nil)
            }
        }

        bridge.handle("fetchAudio") { params, reply in
            guard let memoId = params?["memoId"] as? String else {
                reply(nil, "Missing 'memoId' parameter")
                return
            }
            TalkieSyncXPCService.shared.fetchAudioForMemo(memoId) { success, error in
                reply(["success": success], error)
            }
        }

        bridge.start()
        self.bridge = bridge
    }

    private func logBuildFingerprint() {
        let bundle = Bundle.main
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let executablePath = bundle.executableURL?.path ?? "unknown"
        let pid = ProcessInfo.processInfo.processIdentifier
        let parentPid = getppid()
        let xpcServiceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] ?? "unset"
        let launchPath = ProcessInfo.processInfo.arguments.first ?? "unknown"

        log.info("TalkieSync build: v\(shortVersion) (\(buildNumber)) [\(bundleID)]", critical: true)
        log.info("TalkieSync XPC service: \(kTalkieSyncXPCServiceName)", critical: true)
        log.info("TalkieSync launch context: pid=\(pid), ppid=\(parentPid), XPC_SERVICE_NAME=\(xpcServiceName)", critical: true)
#if DEBUG
        log.info("TalkieSync executable: \(executablePath)", critical: true)
        log.info("TalkieSync launch path: \(launchPath)", critical: true)
#endif
    }

    private func logRuntimeEntitlements() {
        guard let task = SecTaskCreateFromSelf(nil) else {
            log.warning("Could not read runtime entitlements (SecTaskCreateFromSelf failed)", critical: true)
            return
        }

        let keys = [
            "com.apple.application-identifier",
            "com.apple.developer.team-identifier",
            "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.icloud-services",
            "com.apple.developer.icloud-container-environment",
            "com.apple.developer.aps-environment",
            "com.apple.security.app-sandbox",
            "com.apple.security.application-groups",
        ]

        for key in keys {
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
            log.info("TalkieSync entitlement \(key): \(String(describing: value))", critical: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("TalkieSync terminating...")

        bridge?.stop()
        TalkieSyncXPCService.shared.stopService()

        log.info("TalkieSync terminated")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Background service - keep running when windows are closed
        return false
    }

    // MARK: - URL Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        // Handle talkiesync:// URLs
        guard url.scheme?.hasPrefix("talkiesync") == true else { return }

        log.info("Received URL: \(url.absoluteString)")

        switch url.host {
        case "settings":
            showSettings()
        case "performance", "perf":
            showPerformance()
        default:
            // Unknown command - show settings as fallback
            showSettings()
        }
    }

    // MARK: - Settings Window

    private func showSettings() {
        // If window already exists and is visible, bring it to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Close old window if it exists but isn't visible
        settingsWindow?.close()
        settingsWindow = nil

        // Create settings window
        let contentView = SyncSettingsView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = "TalkieSync Settings"
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

    // MARK: - Performance Window

    private func showPerformance() {
        // If window already exists and is visible, bring it to front
        if let window = performanceWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Close old window if it exists but isn't visible
        performanceWindow?.close()
        performanceWindow = nil

        // Create performance window
        let contentView = SyncPerformanceView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = "TalkieSync Performance"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Store reference
        performanceWindow = window

        // Show in Dock/Cmd+Tab while window is open
        NSApp.setActivationPolicy(.regular)

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === settingsWindow {
            settingsWindow = nil
        } else if window === performanceWindow {
            performanceWindow = nil
        }

        // If no windows open, return to background mode
        if settingsWindow == nil && performanceWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
