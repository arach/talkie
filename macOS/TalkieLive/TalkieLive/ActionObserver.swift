//
//  ActionObserver.swift
//  TalkieLive
//
//  Proof of concept: Watch for "action completion" signals from apps.
//  Uses AXObserver to detect window title changes that indicate
//  a long-running task has completed.
//

import Foundation
import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "ActionObserver")

/// Tracks an initiated action waiting for completion
struct TrackedAction {
    let appBundleID: String
    let appName: String
    let windowTitle: String
    let startTime: Date
    var completed: Bool = false
    var completedTime: Date?
}

/// Proof of concept: Observes app window changes to detect action completions
@MainActor
final class ActionObserver: ObservableObject {
    static let shared = ActionObserver()

    @Published private(set) var trackedActions: [TrackedAction] = []
    @Published private(set) var lastCompletion: String?

    /// Track multiple apps (not just frontmost)
    private var observedApps: [pid_t: ObservedApp] = [:]
    private var pollingTimer: Timer?
    private let maxObservedApps = 10  // Track more apps for better coverage

    private struct ObservedApp {
        let pid: pid_t
        let name: String
        let observer: AXObserver
        let appElement: AXUIElement
        var previousTitle: String?
        var lastSeen: Date
    }

    // Patterns that suggest "working" state
    private let workingPatterns = [
        "Generating", "Loading", "Processing", "Thinking",
        "Running", "Building", "Compiling", "Analyzing",
        "Waiting", "Connecting", "Downloading", "Uploading",
        "...", "●", "⏳"
    ]

    // Patterns that suggest "done" state
    private let donePatterns = [
        "Done", "Complete", "Finished", "Ready",
        "Success", "Built", "Compiled", "✓", "✅"
    ]

    private init() {}

    /// Start observing apps
    func startObserving() {
        logger.info("ActionObserver starting...")

        // Watch for app activation changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Start observing current frontmost app
        if let app = NSWorkspace.shared.frontmostApplication {
            addAppObserver(app)
        }

        // Start polling timer for ALL observed apps
        startPollingTimer()

        logger.info("ActionObserver started - watching for action completions (keeps \(self.maxObservedApps) apps)")
    }

    /// Stop observing
    func stopObserving() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pollingTimer?.invalidate()
        pollingTimer = nil

        // Remove all observers
        for (_, app) in observedApps {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(app.observer),
                .defaultMode
            )
        }
        observedApps.removeAll()

        logger.info("ActionObserver stopped")
    }

    // MARK: - App Switching

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            logger.warning("appDidActivate: Could not get app from notification")
            return
        }

        let appName = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier
        logger.info("📱 App activated: \(appName) (pid: \(pid))")

        addAppObserver(app)
    }

    // MARK: - AX Observer Setup

    private func addAppObserver(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"

        // Update lastSeen if already observing
        if var existing = observedApps[pid] {
            existing.lastSeen = Date()
            observedApps[pid] = existing
            return
        }

        // Prune oldest if at capacity
        if observedApps.count >= maxObservedApps {
            pruneOldestObserver()
        }

        // Create new observer
        var observer: AXObserver?
        let result = AXObserverCreate(pid, axCallback, &observer)

        guard result == .success, let observer = observer else {
            logger.warning("Could not create AXObserver for \(appName) (pid: \(pid))")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Subscribe to notifications
        let notifications = [
            kAXFocusedWindowChangedNotification as CFString,
            kAXTitleChangedNotification as CFString,
            kAXValueChangedNotification as CFString
        ]

        var subscribed = 0
        for notification in notifications {
            if AXObserverAddNotification(observer, appElement, notification, Unmanaged.passUnretained(self).toOpaque()) == .success {
                subscribed += 1
            }
        }

        // Add to run loop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        // Get initial title
        let initialTitle = getWindowTitle(appElement)

        // Store observer
        observedApps[pid] = ObservedApp(
            pid: pid,
            name: appName,
            observer: observer,
            appElement: appElement,
            previousTitle: initialTitle,
            lastSeen: Date()
        )

        let appCount = observedApps.count
        logger.info("Now observing: \(appName) (pid: \(pid)) - title: \"\(initialTitle ?? "none")\" [\(appCount) apps tracked]")

        // Run diagnostics if we couldn't get a title (helps debug problematic apps)
        if initialTitle == nil {
            diagnoseApp(app)
        }
    }

    private func pruneOldestObserver() {
        guard let oldest = observedApps.min(by: { $0.value.lastSeen < $1.value.lastSeen }) else { return }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(oldest.value.observer),
            .defaultMode
        )
        observedApps.removeValue(forKey: oldest.key)
        logger.debug("Pruned observer for \(oldest.value.name)")
    }

    // MARK: - Polling (checks ALL observed apps)

    private func startPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollAllApps()
            }
        }
    }

    private var pollCount = 0

    private func pollAllApps() {
        pollCount += 1

        // Periodic status log every 10 polls (5 seconds)
        if pollCount % 10 == 0 {
            let appNames = observedApps.values.map { $0.name }.joined(separator: ", ")
            logger.debug("Polling \(self.observedApps.count) apps: [\(appNames)]")
        }

        for (pid, var app) in observedApps {
            let newTitle = getWindowTitle(app.appElement)

            // Log apps that consistently return nil
            if newTitle == nil && pollCount % 20 == 0 {
                logger.debug("[\(app.name)] still returning nil title")
            }

            // Skip if no title or unchanged
            guard let newTitle = newTitle else { continue }
            guard newTitle != app.previousTitle else { continue }

            let oldTitle = app.previousTitle ?? ""

            // Log change
            logger.info("[\(app.name)] Title: \"\(oldTitle.prefix(50))\" → \"\(newTitle.prefix(50))\"")

            // Check for completion
            checkForCompletion(appName: app.name, oldTitle: oldTitle, newTitle: newTitle)

            // Update stored title
            app.previousTitle = newTitle
            observedApps[pid] = app
        }
    }

    private func checkForCompletion(appName: String, oldTitle: String, newTitle: String) {
        let wasWorking = workingPatterns.contains { oldTitle.localizedCaseInsensitiveContains($0) }
        let isDone = donePatterns.contains { newTitle.localizedCaseInsensitiveContains($0) }
        let workingEnded = wasWorking && !workingPatterns.contains { newTitle.localizedCaseInsensitiveContains($0) }

        if wasWorking && (isDone || workingEnded) {
            let message = "🎯 Action completed in \(appName): \"\(oldTitle.prefix(40))\" → \"\(newTitle.prefix(40))\""
            logger.info("\(message)")

            lastCompletion = "\(appName): Task completed"
            SystemEventManager.shared.log(.system, "Action completed", detail: "\(appName) finished a task")
        }
    }

    // MARK: - Title Change Detection (from AX notifications)

    fileprivate func handleAXNotification(_ element: AXUIElement, notification: String) {
        // AX notifications come from specific apps - poll will catch changes
        logger.debug("AX notification received: \(notification)")
    }

    private func getWindowTitle(_ appElement: AXUIElement) -> String? {
        // Try focused window first (AX API)
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let window = windowRef {
            if let title = extractTitleFromWindow(window as! AXUIElement) {
                return title
            }
        }

        // Fallback: try main window (AX API)
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef) == .success,
           let window = windowRef {
            if let title = extractTitleFromWindow(window as! AXUIElement) {
                return title
            }
        }

        // Fallback: try ALL windows in windows array (AX API)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                if let title = extractTitleFromWindow(window) {
                    return title
                }
            }
        }

        // Final fallback: use CGWindowList API (works without full AX permissions)
        var pidRef: pid_t = 0
        AXUIElementGetPid(appElement, &pidRef)
        if pidRef != 0 {
            return getWindowTitleViaCGWindowList(pid: pidRef)
        }

        return nil
    }

    /// Use CGWindowListCopyWindowInfo as fallback for apps where AX doesn't work
    private func getWindowTitleViaCGWindowList(pid: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let windowPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid else {
                continue
            }

            // Skip minimized/offscreen windows
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
               let width = bounds["Width"], let height = bounds["Height"],
               width < 10 || height < 10 {
                continue
            }

            // Get window name
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                return name
            }
        }

        return nil
    }

    /// Extract title from a window element, trying multiple attributes
    private func extractTitleFromWindow(_ window: AXUIElement) -> String? {
        // List of attributes to try for title
        let titleAttributes = [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            "AXDocument"  // Some apps put URLs/paths here
        ]

        for attr in titleAttributes {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, attr as CFString, &valueRef) == .success {
                if let title = valueRef as? String, !title.isEmpty {
                    return title
                }
            }
        }

        // Try to get title from child elements (tabs, web content)
        // Some Electron apps have the title in a tab group or toolbar
        if let childTitle = getChildElementTitle(window) {
            return childTitle
        }

        return nil
    }

    /// Look for title in child elements (for Electron apps, tabs, etc.)
    private func getChildElementTitle(_ element: AXUIElement) -> String? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        // Look for tab groups, toolbars, or web areas that might have titles
        for child in children.prefix(10) {  // Limit to first 10 children
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else {
                continue
            }

            // Check for tab groups (common in browsers and Electron apps)
            if role == "AXTabGroup" {
                if let tabTitle = getSelectedTabTitle(child) {
                    return tabTitle
                }
            }

            // Check for web areas (might have document title)
            if role == "AXWebArea" {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    return title
                }
            }

            // For toolbars, look for static text or title
            if role == "AXToolbar" || role == "AXGroup" {
                if let toolbarTitle = findTitleInToolbar(child) {
                    return toolbarTitle
                }
            }
        }

        return nil
    }

    /// Get title from selected tab in a tab group
    private func getSelectedTabTitle(_ tabGroup: AXUIElement) -> String? {
        var tabsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(tabGroup, kAXTabsAttribute as CFString, &tabsRef) == .success,
              let tabs = tabsRef as? [AXUIElement] else {
            return nil
        }

        // Try to find selected tab
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(tabGroup, kAXValueAttribute as CFString, &selectedRef) == .success,
           let selectedTab = selectedRef {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(selectedTab as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, !title.isEmpty {
                return title
            }
        }

        // Fallback: try first tab
        if let firstTab = tabs.first {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(firstTab, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, !title.isEmpty {
                return title
            }
        }

        return nil
    }

    /// Look for title in toolbar children
    private func findTitleInToolbar(_ toolbar: AXUIElement) -> String? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(toolbar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children.prefix(5) {
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else {
                continue
            }

            if role == "AXStaticText" {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String, !value.isEmpty, value.count > 3 {
                    return value
                }
            }
        }

        return nil
    }

    // MARK: - Diagnostic: List all available attributes
    func diagnoseApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? "unknown"
        let appElement = AXUIElementCreateApplication(pid)

        logger.info("╔══════════════════════════════════════════════════")
        logger.info("║ DIAGNOSING: \(appName) (pid: \(pid))")
        logger.info("║ Bundle ID: \(bundleID)")
        logger.info("╚══════════════════════════════════════════════════")

        // Get windows via AX API
        var windowsRef: CFTypeRef?
        let axSuccess = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success
        let windows = (windowsRef as? [AXUIElement]) ?? []

        if axSuccess && !windows.isEmpty {
            logger.info("AX API: Found \(windows.count) window(s)")

            for (index, window) in windows.prefix(3).enumerated() {
                logger.info("── Window \(index) ──")

                // Try key attributes
                for attr in ["AXTitle", "AXDescription", "AXDocument", "AXRole", "AXSubrole"] {
                    var valueRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(window, attr as CFString, &valueRef) == .success {
                        if let strValue = valueRef as? String, !strValue.isEmpty {
                            logger.info("  \(attr): \"\(strValue.prefix(100))\"")
                        }
                    }
                }
            }
        } else {
            logger.info("⚠️ AX API: No windows found (may lack permissions)")
        }

        // Also try CGWindowList API as fallback
        let cgOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let cgWindowList = CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]] {
            let appWindows = cgWindowList.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
            if !appWindows.isEmpty {
                logger.info("CGWindowList: Found \(appWindows.count) window(s)")
                for (index, window) in appWindows.prefix(3).enumerated() {
                    let name = window[kCGWindowName as String] as? String ?? "(no name)"
                    let layer = window[kCGWindowLayer as String] as? Int ?? -1
                    logger.info("  CG Window \(index): \"\(name)\" (layer: \(layer))")
                }
            } else {
                logger.info("CGWindowList: No windows for this app")
            }
        }

        logger.info("════════════════════════════════════════════════════")
    }
}

// MARK: - AX Callback (C function)

private func axCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let actionObserver = Unmanaged<ActionObserver>.fromOpaque(refcon).takeUnretainedValue()

    // Handle on main thread
    Task { @MainActor in
        actionObserver.handleAXNotification(element, notification: notification as String)
    }
}
