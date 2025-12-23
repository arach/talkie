//
//  AppDelegate.swift
//  Talkie macOS
//
//  Handles push notifications for instant CloudKit sync
//

import AppKit
import CloudKit
import UserNotifications
import os
import DebugKit
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "AppDelegate")

// Free function to capture settings screenshots using subprocess
@MainActor
private func captureSettingsScreenshots(to directory: URL) async -> Int {
    // Get the path to this executable
    let execPath = Bundle.main.executablePath ?? ""

    // Run settings-screenshots command as subprocess
    let process = Process()
    process.executableURL = URL(fileURLWithPath: execPath)
    process.arguments = ["--debug=settings-screenshots", directory.path]

    do {
        try process.run()
        process.waitUntilExit()

        // Count files in directory
        let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        return files?.filter { $0.hasSuffix(".png") }.count ?? 0
    } catch {
        print("   ⚠️ Failed to capture screenshots: \(error)")
        return 0
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    // CLI command handler
    private let cliHandler = CLICommandHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] 🎬 applicationDidFinishLaunching called")

        // CRITICAL: Check for debug mode SYNCHRONOUSLY before initialization
        // Debug commands need isolated execution without CloudKit/helpers running
        let arguments = ProcessInfo.processInfo.arguments
        let isDebugMode = arguments.contains(where: { $0.starts(with: "--debug=") })

        NSLog("[AppDelegate] isDebugMode = \(isDebugMode)")

        if isDebugMode {
            NSLog("[AppDelegate] ⚙️ Debug mode - skipping initialization")
            logger.debug("⚙️ Debug mode detected - running headless, skipping initialization")
            // Register debug commands and handle them
            registerDebugCommands()
            Task { @MainActor in
                _ = await cliHandler.handleCommandLineArguments()
            }
            return  // Exit early - don't initialize app services
        }

        NSLog("[AppDelegate] ✓ Normal initialization mode")

        // Normal app initialization (only runs when NOT in debug mode)
        registerDebugCommands()

        // Configure window appearance to match theme before SwiftUI renders
        // This prevents the "flicker" of default colors before theme loads
        configureWindowAppearance()

        // Set notification delegate to show notifications while app is in foreground
        UNUserNotificationCenter.current().delegate = self

        // Request local notification permissions for workflow notifications
        requestNotificationPermissions()

        // Register for remote notifications
        NSApplication.shared.registerForRemoteNotifications()

        // Set up CloudKit subscription for instant sync
        setupCloudKitSubscription()

        // Ensure helper apps (TalkieLive, TalkieEngine) are running
        // This registers them as login items and launches them if needed
        Task { @MainActor in
            NSLog("[AppDelegate] 🚀 Starting helper apps...")
            AppLauncher.shared.ensureHelpersRunning()

            // Connect to TalkieEngine XPC service (has built-in retry logic)
            NSLog("[AppDelegate] 🔌 Calling EngineClient.shared.connect()...")
            EngineClient.shared.connect()
            NSLog("[AppDelegate] ✓ EngineClient.connect() returned")
        }

        // Register URL handler for Apple Events
        let eventManager = NSAppleEventManager.shared()
        eventManager.setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        logger.info("URL handler registered")
    }

    // MARK: - Debug Commands

    private func registerDebugCommands() {
        cliHandler.register(
            "onboarding-storyboard",
            description: "Generate storyboard of onboarding screens with layout grid overlay"
        ) { args in
            let outputPath = args.first
            await OnboardingStoryboardGenerator.shared.generateAndExit(outputPath: outputPath)
        }

        cliHandler.register(
            "settings-storyboard",
            description: "Generate storyboard of all settings pages"
        ) { args in
            let outputPath = args.first
            await SettingsStoryboardGenerator.shared.generateAndExit(outputPath: outputPath)
        }

        cliHandler.register(
            "settings-screenshots",
            description: "Capture individual screenshots of each settings page to a directory"
        ) { args in
            let outputDir: URL
            if let path = args.first {
                outputDir = URL(fileURLWithPath: path)
            } else {
                let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                outputDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("settings-screenshots-\(timestamp)")
            }

            print("📸 Capturing settings pages to: \(outputDir.path)")
            let results = await SettingsStoryboardGenerator.shared.captureAllPages(to: outputDir)
            print("✅ Captured \(results.count) pages")
            exit(0)
        }

        cliHandler.register(
            "settings-grid",
            description: "Capture all settings pages as a grid composite (use --overlay for layout guides)"
        ) { args in
            let withOverlay = args.contains("--overlay")
            let outputPath: URL
            if let path = args.first(where: { !$0.starts(with: "--") }) {
                outputPath = URL(fileURLWithPath: path)
            } else {
                let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let suffix = withOverlay ? "-overlay" : ""
                outputPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("settings-grid\(suffix)-\(timestamp).png")
            }

            print("📸 Generating settings grid\(withOverlay ? " with overlay" : "")...")
            await SettingsStoryboardGenerator.shared.captureGrid(columns: 4, withOverlay: withOverlay, to: outputPath)
            exit(0)
        }

        cliHandler.register(
            "settings-analyze",
            description: "Generate styling analysis report for all settings pages"
        ) { args in
            let outputPath: URL
            if let path = args.first {
                outputPath = URL(fileURLWithPath: path)
            } else {
                let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                outputPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("settings-analysis-\(timestamp).md")
            }

            print("🔍 Analyzing settings page styling...")
            await SettingsStoryboardGenerator.shared.generateAnalysisReport(to: outputPath)
            exit(0)
        }

        cliHandler.register(
            "settings-full",
            description: "Generate complete package: grid, analysis report, and individual screenshots"
        ) { args in
            let outputDir: URL
            if let path = args.first {
                outputDir = URL(fileURLWithPath: path)
            } else {
                let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                outputDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("settings-audit-\(timestamp)")
            }

            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            print("📦 Generating full settings audit package...")

            // 1. Grid (clean)
            print("\n1️⃣ Grid view...")
            await SettingsStoryboardGenerator.shared.captureGrid(
                columns: 4,
                withOverlay: false,
                to: outputDir.appendingPathComponent("grid.png")
            )

            // 2. Grid with overlay
            print("\n2️⃣ Grid with layout overlay...")
            await SettingsStoryboardGenerator.shared.captureGrid(
                columns: 4,
                withOverlay: true,
                to: outputDir.appendingPathComponent("grid-overlay.png")
            )

            // 3. Individual screenshots
            print("\n3️⃣ Individual screenshots...")
            _ = await SettingsStoryboardGenerator.shared.captureAllPages(
                to: outputDir.appendingPathComponent("pages")
            )

            // 4. Analysis report
            print("\n4️⃣ Styling analysis...")
            await SettingsStoryboardGenerator.shared.generateAnalysisReport(
                to: outputDir.appendingPathComponent("analysis.md")
            )

            print("\n✅ Full audit package saved to: \(outputDir.path)")
            exit(0)
        }

        // MARK: - Design Auditor Commands

        cliHandler.register(
            "audit",
            description: "Run full design audit on all screens (outputs HTML + Markdown reports)"
        ) { args in
            // Fixed location: ~/Desktop/talkie-audit/
            let baseDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent("talkie-audit")
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

            // Each audit gets a numbered folder
            let existing = (try? FileManager.default.contentsOfDirectory(atPath: baseDir.path)) ?? []
            let auditFolders = existing.filter { $0.hasPrefix("run-") }
            let nextNum = (auditFolders.compactMap { Int($0.dropFirst(4)) }.max() ?? 0) + 1
            let runDir = baseDir.appendingPathComponent(String(format: "run-%03d", nextNum))
            try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

            print("🔍 Running full design audit (run-\(String(format: "%03d", nextNum)))...")
            let report = await DesignAuditor.shared.auditAll()

            print("\n📊 Results:")
            print("   Grade: \(report.grade) (\(report.overallScore)%)")
            print("   Screens: \(report.screens.count)")
            print("   Issues: \(report.totalIssues)")

            // Generate reports for this run
            print("\n📝 Generating reports...")
            await DesignAuditor.shared.generateHTMLReport(from: report, to: runDir.appendingPathComponent("report.html"))
            await DesignAuditor.shared.generateMarkdownReport(from: report, to: runDir.appendingPathComponent("report.md"))

            // Capture settings page screenshots by calling separate generator
            let screenshotDir = runDir.appendingPathComponent("screenshots")
            print("\n📸 Capturing settings screenshots...")
            let screenshotResults = await captureSettingsScreenshots(to: screenshotDir)
            print("   ✅ Captured \(screenshotResults) screenshots")

            // Update master index.html with all runs
            await Self.generateAuditIndex(at: baseDir)

            print("\n✅ Audit complete!")
            print("   📂 ~/Desktop/talkie-audit/")
            print("   🌐 index.html - lists all audits")

            // Open report
            NSWorkspace.shared.open(runDir.appendingPathComponent("report.html"))

            // Graceful exit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        }

        cliHandler.register(
            "audit-section",
            description: "Audit a specific section (settings, live, memos, onboarding, navigation)"
        ) { args in
            guard let sectionName = args.first,
                  let section = ScreenSection(rawValue: sectionName.capitalized) else {
                print("❌ Usage: --debug=audit-section <section>")
                print("   Sections: settings, live, memos, onboarding, navigation")
                exit(1)
            }

            print("🔍 Auditing \(section.rawValue) section...")
            let report = await DesignAuditor.shared.audit(section: section)

            print("\n📊 Results:")
            print("   Grade: \(report.grade) (\(report.overallScore)%)")
            print("   Screens: \(report.screens.count)")
            print("   Issues: \(report.totalIssues)")

            for screen in report.screens {
                print("   - \(screen.screen.title): \(screen.grade) (\(screen.overallScore)%)")
            }

            exit(0)
        }
    }

    // MARK: - URL Handling

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            NSLog("[AppDelegate] Invalid URL event received")
            logger.warning("Invalid URL event received")
            return
        }

        NSLog("[AppDelegate] Received URL: \(urlString)")
        logger.info("Received URL: \(urlString)")

        // Accept environment-specific URL schemes (talkie, talkie-staging, talkie-dev)
        guard url.scheme == TalkieEnvironment.current.talkieURLScheme else {
            NSLog("[AppDelegate] URL not handled: invalid scheme (expected \(TalkieEnvironment.current.talkieURLScheme), got \(url.scheme ?? "nil"))")
            return
        }

        // Handle talkie://live or talkie://live/home - navigate to Live section
        if url.host == "live" {
            let path = url.pathComponents.dropFirst().first ?? ""
            NSLog("[AppDelegate] Navigating to Live section: \(path.isEmpty ? "default" : path)")
            logger.info("Navigating to Live section: \(path.isEmpty ? "default" : path)")
            NotificationCenter.default.post(name: .navigateToLive, object: nil)
        }
        // Handle talkie://settings/live - navigate directly to full Live settings
        else if url.host == "settings" {
            let path = url.pathComponents.dropFirst().first ?? ""
            NSLog("[AppDelegate] Navigating to Settings section: \(path)")
            logger.info("Navigating to Settings section: \(path)")

            if path == "live" {
                // Navigate directly to full Live settings (bypasses main Settings)
                NotificationCenter.default.post(name: .navigateToLiveSettings, object: nil)
            } else {
                // Just open Settings
                NotificationCenter.default.post(name: .navigateToSettings, object: nil)
            }
        }
        // Handle talkie://interstitial/{id}
        else if url.host == "interstitial",
           let idString = url.pathComponents.dropFirst().first,
           let id = Int64(idString) {
            NSLog("[AppDelegate] Opening interstitial for utterance ID: \(id)")
            logger.info("Opening interstitial for utterance ID: \(id)")
            Task { @MainActor in
                // Hide all main app windows when showing interstitial
                for window in NSApp.windows where window.title != "" {
                    window.orderOut(nil)
                }
                InterstitialManager.shared.show(utteranceId: id)
            }
        }
        else if handleDebugURL(url) {
            // Handled by debug URL handler
        }
        else {
            NSLog("[AppDelegate] URL not handled: scheme=\(url.scheme ?? "nil"), host=\(url.host ?? "nil")")
        }
    }

    /// Handle debug URLs (talkie://d/...) - only in DEBUG builds
    private func handleDebugURL(_ url: URL) -> Bool {
        #if DEBUG
        guard url.host == "d" else { return false }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        NSLog("[AppDelegate] Debug navigation: /d/\(path)")

        let components = path.split(separator: "/")

        // Handle capture commands: /d/capture/settings
        if components.first == "capture" {
            if components.count >= 2 && components[1] == "settings" {
                NSLog("[AppDelegate] 📸 Triggering settings capture sequence...")
                Task { @MainActor in
                    // Open Settings first
                    NotificationCenter.default.post(name: .navigateToSettings, object: nil)
                    try? await Task.sleep(for: .milliseconds(500))

                    // Capture all settings pages with navigation
                    let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                    let outputDir = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Desktop")
                        .appendingPathComponent("settings-capture-\(timestamp)")
                    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

                    let results = await SettingsStoryboardGenerator.shared.captureAllPages(to: outputDir)
                    NSLog("[AppDelegate] ✅ Captured \(results.count) settings pages to \(outputDir.path)")
                    NSWorkspace.shared.open(outputDir)
                }
                return true
            }
            // Handle /d/capture/audit - run code audit only (no window navigation)
            // Use /d/capture/full for screenshots + audit
            if components.count >= 2 && components[1] == "audit" {
                NSLog("[AppDelegate] 🔍 Triggering code audit (no screenshots)...")

                // Run entirely on background queue
                DispatchQueue.global(qos: .userInitiated).async {
                    autoreleasepool {
                        // Setup directories
                        let baseDir = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Desktop")
                            .appendingPathComponent("talkie-audit")
                        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

                        let existing = (try? FileManager.default.contentsOfDirectory(atPath: baseDir.path)) ?? []
                        let auditFolders = existing.filter { $0.hasPrefix("run-") }
                        let nextNum = (auditFolders.compactMap { Int($0.dropFirst(4)) }.max() ?? 0) + 1
                        let runDir = baseDir.appendingPathComponent(String(format: "run-%03d", nextNum))
                        try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

                        NSLog("[AppDelegate] 🔍 Running code audit...")
                        let report = DesignAuditor.shared.auditAll()
                        NSLog("[AppDelegate] ✅ Audit complete: \(report.grade) (\(report.overallScore)%)")

                        NSLog("[AppDelegate] 📝 Generating reports...")
                        DesignAuditor.shared.generateHTMLReport(from: report, to: runDir.appendingPathComponent("report.html"))
                        DesignAuditor.shared.generateMarkdownReport(from: report, to: runDir.appendingPathComponent("report.md"))

                        // Back to main for UI operations
                        DispatchQueue.main.async {
                            Task { @MainActor in
                                await Self.generateAuditIndex(at: baseDir)
                                NSLog("[AppDelegate] ✅ All done!")
                                NSWorkspace.shared.open(runDir.appendingPathComponent("report.html"))
                            }
                        }
                    }
                }
                return true
            }

            // Handle /d/capture/full - screenshots + audit combined
            if components.count >= 2 && components[1] == "full" {
                NSLog("[AppDelegate] 🔍 Triggering full audit with screenshots...")

                // Setup directories synchronously first
                let baseDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("talkie-audit")
                try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

                let existing = (try? FileManager.default.contentsOfDirectory(atPath: baseDir.path)) ?? []
                let auditFolders = existing.filter { $0.hasPrefix("run-") }
                let nextNum = (auditFolders.compactMap { Int($0.dropFirst(4)) }.max() ?? 0) + 1
                let runDir = baseDir.appendingPathComponent(String(format: "run-%03d", nextNum))
                let screenshotsDir = runDir.appendingPathComponent("screenshots")
                try? FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)

                // Screenshot capture phase
                Task { @MainActor in
                    // Open Settings first
                    NotificationCenter.default.post(name: .navigateToSettings, object: nil)
                    try? await Task.sleep(for: .milliseconds(500))

                    // Capture screenshots
                    NSLog("[AppDelegate] 📸 Capturing settings screenshots...")
                    let screenshots = await SettingsStoryboardGenerator.shared.captureAllPages(to: screenshotsDir)
                    NSLog("[AppDelegate] ✅ Captured \(screenshots.count) screenshots")

                    // Let UI settle before audit
                    try? await Task.sleep(for: .milliseconds(500))

                    // Run audit on background queue
                    DispatchQueue.global(qos: .userInitiated).async {
                        autoreleasepool {
                            NSLog("[AppDelegate] 🔍 Running code audit...")
                            let report = DesignAuditor.shared.auditAll()
                            NSLog("[AppDelegate] ✅ Audit complete: \(report.grade) (\(report.overallScore)%)")

                            NSLog("[AppDelegate] 📝 Generating reports...")
                            DesignAuditor.shared.generateHTMLReport(from: report, to: runDir.appendingPathComponent("report.html"))
                            DesignAuditor.shared.generateMarkdownReport(from: report, to: runDir.appendingPathComponent("report.md"))

                            DispatchQueue.main.async {
                                Task { @MainActor in
                                    await Self.generateAuditIndex(at: baseDir)
                                    NSLog("[AppDelegate] ✅ All done!")
                                    NSWorkspace.shared.open(runDir.appendingPathComponent("report.html"))
                                }
                            }
                        }
                    }
                }
                return true
            }
        }

        // Handle settings navigation: /d/settings/{section}
        if components.first == "settings" {
            // Open Settings window first
            NotificationCenter.default.post(name: .navigateToSettings, object: nil)

            // Then navigate to specific section (with slight delay for window to open)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .debugNavigate,
                    object: nil,
                    userInfo: ["path": path]
                )
            }
            return true
        }

        return false
        #else
        return false
        #endif
    }

    private func configureWindowAppearance() {
        // Apply appearance mode from saved preferences
        let settings = SettingsManager.shared

        // Set the application-wide appearance to match user preference
        switch settings.appearanceMode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil  // Follow system
        }

        // Configure window style for any existing windows
        for window in NSApp.windows {
            window.backgroundColor = NSColor.windowBackgroundColor
            window.isOpaque = true
            // Prevent blur effect when window is inactive by disabling layer caching
            window.contentView?.wantsLayer = true
            window.contentView?.layerContentsRedrawPolicy = .onSetNeedsDisplay
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Force redraw when app becomes active to ensure crisp rendering
        for window in NSApp.windows {
            window.contentView?.needsDisplay = true
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                logger.info("✅ Local notification permissions granted")
            } else if let error = error {
                logger.warning("⚠️ Notification permission error: \(error.localizedDescription)")
            } else {
                logger.info("ℹ️ Local notification permissions denied")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even when app is active
        completionHandler([.banner, .sound])
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        logger.info("📬 User tapped notification: \(response.notification.request.identifier)")
        completionHandler()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("✅ Registered for remote notifications: \(tokenString.prefix(20))...")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // This is expected in debug builds without Push Notification entitlement
        // Sync still works via 5-minute timer; push is only for instant sync in production
        #if DEBUG
        logger.info("Push notifications unavailable (debug build) - using timer sync")
        #else
        logger.error("❌ Failed to register for remote notifications: \(error.localizedDescription)")
        #endif
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        logger.info("📬 Received remote notification")

        // Check if this is a CloudKit notification
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            handleCloudKitNotification(ckNotification)
        }
    }

    private func handleCloudKitNotification(_ notification: CKNotification) {
        logger.info("☁️ CloudKit notification received: \(notification.notificationType.rawValue)")

        // Trigger a token-based sync to fetch only changed records
        Task { @MainActor in
            CloudKitSyncManager.shared.syncNow()
        }
    }

    private func setupCloudKitSubscription() {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase

        // Create a subscription to the Core Data CloudKit zone
        // NSPersistentCloudKitContainer uses "com.apple.coredata.cloudkit.zone"
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        let subscriptionID = "talkie-private-db-subscription"

        // Check if subscription already exists
        privateDB.fetch(withSubscriptionID: subscriptionID) { [weak self] existingSubscription, error in
            if existingSubscription != nil {
                logger.info("✅ CloudKit subscription already exists")
                return
            }

            // Create new subscription
            self?.createDatabaseSubscription(database: privateDB, subscriptionID: subscriptionID, zoneID: zoneID)
        }
    }

    private func createDatabaseSubscription(database: CKDatabase, subscriptionID: String, zoneID: CKRecordZone.ID) {
        // Use CKRecordZoneSubscription for zone-specific changes
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)

        // Configure notification info for silent push
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // Silent push
        subscription.notificationInfo = notificationInfo

        database.save(subscription) { savedSubscription, error in
            if let error = error {
                logger.error("❌ Failed to create CloudKit subscription: \(error.localizedDescription)")
            } else {
                logger.info("✅ CloudKit subscription created successfully")
            }
        }
    }

    // MARK: - Window Capture

    /// Capture screenshots from running Talkie app windows
    @MainActor
    private static func captureRunningAppWindows(to directory: URL) async -> Int {
        var count = 0

        // Get list of all windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }

        // Find Talkie windows
        for windowInfo in windowList {
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  ownerName.contains("Talkie"),
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  width > 100 && height > 100 else {
                continue
            }

            let windowName = windowInfo[kCGWindowName as String] as? String ?? "window"
            let safeName = windowName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")

            // Capture the window
            if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming]) {
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

                let filename = "\(String(format: "%02d", count))-\(safeName).png"
                let fileURL = directory.appendingPathComponent(filename)

                if let tiffData = image.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: fileURL)
                    count += 1
                    print("   📷 Captured: \(windowName)")
                }
            }
        }

        return count
    }

    // MARK: - Audit Index Generator

    /// Generate index.html listing all audit runs
    @MainActor
    private static func generateAuditIndex(at baseDir: URL) async {
        let fm = FileManager.default
        let existing = (try? fm.contentsOfDirectory(atPath: baseDir.path)) ?? []
        let runs = existing.filter { $0.hasPrefix("run-") }.sorted().reversed()

        var rows = ""
        for run in runs {
            let runDir = baseDir.appendingPathComponent(run)
            let mdPath = runDir.appendingPathComponent("report.md")

            // Parse grade and score from markdown
            var grade = "?"
            var score = "?"
            var screens = "?"
            var issues = "?"

            if let content = try? String(contentsOf: mdPath, encoding: .utf8) {
                if let gradeMatch = content.range(of: #"Grade:\s*([A-F])"#, options: .regularExpression) {
                    grade = String(content[gradeMatch]).replacingOccurrences(of: "Grade: ", with: "")
                }
                if let scoreMatch = content.range(of: #"\((\d+)%\)"#, options: .regularExpression) {
                    score = String(content[scoreMatch]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: "%)", with: "")
                }
                if let screensMatch = content.range(of: #"Screens Audited:\s*\*\*(\d+)\*\*"#, options: .regularExpression) {
                    let matched = String(content[screensMatch])
                    screens = matched.components(separatedBy: "**").dropFirst().first ?? "?"
                }
            }

            // Get folder modification date
            let attrs = try? fm.attributesOfItem(atPath: runDir.path)
            let date = (attrs?[.modificationDate] as? Date) ?? Date()
            let dateStr = date.formatted(date: .abbreviated, time: .shortened)

            let gradeColor = grade == "A" ? "#22c55e" : grade == "B" ? "#84cc16" : grade == "C" ? "#eab308" : grade == "D" ? "#f97316" : "#ef4444"

            rows += """
                <tr onclick="window.location='\(run)/report.html'" style="cursor:pointer">
                    <td style="font-weight:600">\(run)</td>
                    <td>\(dateStr)</td>
                    <td><span style="color:\(gradeColor);font-weight:700;font-size:18px">\(grade)</span></td>
                    <td>\(score)%</td>
                    <td><a href="\(run)/report.html">View →</a></td>
                </tr>
            """
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Talkie Design Audits</title>
            <meta http-equiv="refresh" content="5">
            <style>
                body { font-family: -apple-system, system-ui, sans-serif; background: #0a0a0a; color: #fff; padding: 40px; }
                h1 { font-size: 28px; margin-bottom: 8px; }
                .subtitle { color: #888; margin-bottom: 32px; }
                table { width: 100%; border-collapse: collapse; }
                th, td { padding: 12px 16px; text-align: left; border-bottom: 1px solid #222; }
                th { color: #888; font-size: 12px; text-transform: uppercase; }
                tr:hover { background: #1a1a1a; }
                a { color: #00d4ff; text-decoration: none; }
                .refresh { color: #666; font-size: 12px; }
            </style>
        </head>
        <body>
            <h1>Talkie Design Audits</h1>
            <p class="subtitle">Auto-refreshes every 5 seconds. Run <code>--debug=audit</code> to add new audit.</p>
            <table>
                <tr><th>Run</th><th>Date</th><th>Grade</th><th>Score</th><th>Report</th></tr>
                \(rows)
            </table>
            <p class="refresh">Last updated: \(Date().formatted())</p>
        </body>
        </html>
        """

        try? html.write(to: baseDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
}
