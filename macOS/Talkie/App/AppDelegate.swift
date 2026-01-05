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
private let signposter = OSSignposter(subsystem: "jdi.talkie.performance", category: "Startup")

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

    // MARK: - Window Restoration

    /// Prevent macOS from restoring old windows on launch
    /// This fixes the "blank windows" issue on fresh builds
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true  // Required for modern macOS, but we'll close stale windows
    }

    /// Close any windows restored from previous session that are blank/invalid
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Detect fresh build by checking if bundle version changed
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let lastBuild = UserDefaults.standard.string(forKey: "lastLaunchedBuild")

        if lastBuild != currentBuild {
            // Fresh build - clear window restoration state to prevent stale windows
            logger.info("Fresh build detected (\(lastBuild ?? "none") → \(currentBuild)), clearing window state")
            clearSavedWindowState()
            UserDefaults.standard.set(currentBuild, forKey: "lastLaunchedBuild")
        }

        // Close any pre-existing windows from state restoration that are blank/invalid
        for window in NSApp.windows where window.contentView == nil || window.contentViewController == nil {
            window.close()
        }
    }

    /// Clear macOS saved window state to prevent blank/duplicate windows
    private func clearSavedWindowState() {
        // Remove SwiftUI window state
        if let bundleID = Bundle.main.bundleIdentifier {
            let savedStateDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Saved Application State")
                .appendingPathComponent("\(bundleID).savedState")

            if let dir = savedStateDir, FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.removeItem(at: dir)
                logger.debug("Cleared saved window state")
            }
        }
    }

    override init() {
        super.init()
        // Early theme parsing - set theme BEFORE views are created
        Self.parseAndSetThemeEarly()
    }

    // MARK: - Window Lifecycle

    /// Prevent macOS from creating untitled windows on launch
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Handle dock click - show existing window instead of creating new one
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows - show the main window
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    /// Parse --theme argument early and set UserDefaults before SettingsManager initializes
    private static func parseAndSetThemeEarly() {
        let args = ProcessInfo.processInfo.arguments
        for arg in args {
            if arg.hasPrefix("--theme=") {
                let themeName = String(arg.dropFirst("--theme=".count))
                if let theme = ThemePreset(rawValue: themeName) {
                    // Set UserDefaults directly - SettingsManager will read this on init
                    UserDefaults.standard.set(theme.rawValue, forKey: "currentTheme")
                    UserDefaults.standard.synchronize()
                    NSLog("[AppDelegate] Early theme set: %@", theme.rawValue)
                }
                break
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        StartupProfiler.shared.markEarly("appDelegate.didFinishLaunching")
        let launchState = signposter.beginInterval("App Launch")

        // Configure glass effects from user preference (load-time only)
        GlassConfig.enableGlassEffects = SettingsManager.shared.enableGlassEffects

        // CRITICAL: Check for debug mode SYNCHRONOUSLY before initialization
        // Debug commands need isolated execution without CloudKit/helpers running
        let arguments = ProcessInfo.processInfo.arguments
        let isDebugMode = arguments.contains(where: { $0.starts(with: "--debug=") })

        // Register debug commands early (before checking debug mode)
        signposter.emitEvent("Debug Commands")
        registerDebugCommands()

        if isDebugMode {
            NSLog("[AppDelegate] ⚙️ Debug CLI mode")
            // Schedule CLI handler to run after app finishes initializing
            Task { @MainActor in
                // Wait for app to finish initializing and GPU to be ready
                try? await Task.sleep(for: .milliseconds(2000))
                NSLog("[AppDelegate] 🎯 Running CLI handler...")
                let handled = await self.cliHandler.handleCommandLineArguments()
                if !handled {
                    NSLog("[AppDelegate] ❌ No CLI command executed")
                    exit(1)
                }
            }
            // Continue with normal initialization so MainActor works properly
        } else {
            NSLog("[AppDelegate] ✓ Normal mode")
        }

        // App initialization (runs in both normal and debug mode)
        // Debug mode needs this for MainActor to work properly

        // Phase 1: Critical - Only what's needed before UI renders
        StartupProfiler.shared.markEarly("phase1.critical.start")
        StartupCoordinator.shared.initializeCritical()
        StartupProfiler.shared.markEarly("phase1.critical.done")

        // Set notification delegate to show notifications while app is in foreground
        signposter.emitEvent("Notification Delegate")
        UNUserNotificationCenter.current().delegate = self

        // Phase 3: Deferred - CloudKit, remote notifications (after UI visible)
        // These run with 300ms delay to let UI settle first
        StartupCoordinator.shared.initializeDeferred()

        // Phase 4: Background - Helper apps, XPC connections (lowest priority)
        // These run with 1s delay after UI is responsive
        StartupCoordinator.shared.initializeBackground()

        StartupProfiler.shared.markEarly("appDelegate.didFinishLaunching.done")

        // Register URL handler for Apple Events
        signposter.emitEvent("URL Handler")
        let eventManager = NSAppleEventManager.shared()
        eventManager.setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        logger.info("URL handler registered")

        signposter.endInterval("App Launch", launchState)

        #if DEBUG
        // Setup keyboard shortcut for Design God Mode (⌘⇧D)
        setupDesignModeShortcut()
        #endif
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

        cliHandler.register(
            "audit-screen",
            description: "Audit a specific screen with screenshot capture. Usage: --debug=audit-screen <screen-id> [--theme=<theme>]"
        ) { args in
            NSLog("[audit-screen] Handler started")

            // Parse arguments
            var screenId: String?
            var themeName: String?

            for arg in args {
                if arg.hasPrefix("--theme=") {
                    themeName = String(arg.dropFirst("--theme=".count))
                } else if !arg.hasPrefix("--") {
                    screenId = arg
                }
            }

            guard let screenId = screenId else {
                print("❌ No screen ID provided")
                print("Usage: --debug=audit-screen <screen-id> [--theme=<theme>]")
                print("Themes: talkiePro, linear, terminal, minimal, classic, warm")
                exit(1)
            }
            NSLog("[audit-screen] screenId: %@", screenId)

            guard let screen = AppScreen(rawValue: screenId) else {
                print("❌ Invalid screen ID: \(screenId)")
                print("   Available screens:")
                for screen in AppScreen.allCases {
                    print("     - \(screen.rawValue)")
                }
                exit(1)
            }
            NSLog("[audit-screen] screen: %@", screen.rawValue)

            // Set theme if specified
            var originalTheme: ThemePreset?
            if let themeName = themeName {
                if let theme = ThemePreset(rawValue: themeName) {
                    await MainActor.run {
                        originalTheme = SettingsManager.shared.currentTheme
                        SettingsManager.shared.currentTheme = theme

                        // Force theme cache to update
                        Theme.invalidate()

                        print("🎨 Theme set to: \(theme.displayName)")

                        // Force all windows to redisplay
                        for window in NSApp.windows {
                            // Invalidate the window content to force SwiftUI view rebuild
                            if let contentView = window.contentView {
                                contentView.needsDisplay = true
                                contentView.needsLayout = true

                                // Force SwiftUI hosting view to update
                                if let hostingView = contentView.subviews.first {
                                    hostingView.needsDisplay = true
                                    hostingView.needsLayout = true
                                }
                            }
                            window.displayIfNeeded()
                        }
                    }

                    // Wait for views to update
                    try? await Task.sleep(for: .milliseconds(500))
                } else {
                    print("⚠️ Unknown theme: \(themeName)")
                    print("   Available themes: talkiePro, linear, terminal, minimal, classic, warm")
                }
            }

            let baseDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent("talkie-audit")
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            NSLog("[audit-screen] baseDir: %@", baseDir.path)

            let existing = (try? FileManager.default.contentsOfDirectory(atPath: baseDir.path)) ?? []
            let auditFolders = existing.filter { $0.hasPrefix("run-") }
            let nextNum = (auditFolders.compactMap { Int($0.dropFirst(4)) }.max() ?? 0) + 1
            let runDir = baseDir.appendingPathComponent(String(format: "run-%03d", nextNum))
            let screenshotDir = runDir.appendingPathComponent("screenshots")
            try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
            NSLog("[audit-screen] runDir: %@", runDir.path)

            print("🔍 Auditing \(screen.title) (run-\(String(format: "%03d", nextNum)))...")
            print("📸 Capturing screenshots (small/medium/large)...")

            // Capture screenshots at all three sizes
            var screenshotPaths: [String] = []
            if screen.section == .settings, let settingsPage = screen.settingsPage {
                NSLog("[audit-screen] Capturing settings page: %@", settingsPage.title)
                // Capture each size separately to avoid window reuse issues
                // Only capture medium size for now to avoid multi-capture crash
                let size = WindowSize.medium
                NSLog("[audit-screen] Capturing size: %@ (thread: %@)", size.rawValue, Thread.current.description)
                NSLog("[audit-screen] About to call captureSinglePage...")

                if let url = await SettingsStoryboardGenerator.shared.captureSinglePage(settingsPage, size: size, to: screenshotDir) {
                    screenshotPaths.append("\(size.rawValue): \(url.lastPathComponent)")
                    NSLog("[audit-screen] Captured: %@", url.lastPathComponent)
                } else {
                    NSLog("[audit-screen] Capture returned nil for size: %@", size.rawValue)
                }
                NSLog("[audit-screen] Done capturing screenshots")
            } else if screen.section == .home {
                // Capture home dashboard from main window
                NSLog("[audit-screen] Capturing home screen: %@", screen.rawValue)

                await MainActor.run {
                    // Navigate to home
                    NotificationCenter.default.post(name: .init("NavigateToHome"), object: nil)
                }

                // Wait for navigation
                try? await Task.sleep(for: .milliseconds(500))

                // Find and capture the main window
                if let mainWindow = await MainActor.run(body: {
                    NSApp.windows.first { $0.title.contains("Talkie") && !$0.title.contains("Settings") }
                }) {
                    await MainActor.run {
                        mainWindow.makeKeyAndOrderFront(nil)
                    }
                    try? await Task.sleep(for: .milliseconds(200))

                    // Capture using CGWindowListCreateImage
                    let windowNumber = await MainActor.run(body: { CGWindowID(mainWindow.windowNumber) })
                    if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowNumber, [.boundsIgnoreFraming]) {
                        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                        if let tiffData = image.tiffRepresentation,
                           let bitmapImage = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                            let filename = "\(screen.rawValue).png"
                            let fileURL = screenshotDir.appendingPathComponent(filename)
                            try? pngData.write(to: fileURL)
                            screenshotPaths.append(filename)
                            print("  ✅ Captured: \(filename)")
                        }
                    }
                } else {
                    print("  ⚠️ No main window found")
                }
            } else {
                print("⚠️ Screenshot capture not yet implemented for \(screen.section.rawValue) screens")
            }

            // TEMPORARILY SKIP AUDIT - crashes on async context switch
            // NSLog("[audit-screen] About to analyze code...")
            // print("📊 Analyzing code...")
            // NSLog("[audit-screen] Calling DesignAuditor.shared.audit...")
            // let result = await DesignAuditor.shared.audit(screen: screen, withScreenshot: false)
            // NSLog("[audit-screen] Audit complete!")

            print("\n✅ Screenshot capture complete!")
            if !screenshotPaths.isEmpty {
                print("   Screenshots:")
                for path in screenshotPaths {
                    print("     - \(path)")
                }
            }
            print("   Output: \(runDir.path)")

            NSLog("[audit-screen] Exiting with code 0")
            exit(0)
        }

        cliHandler.register(
            "clear-pending",
            description: "Clear all pending and recent actions from the queue"
        ) { _ in
            await MainActor.run {
                PendingActionsManager.shared.cancelAll()
                PendingActionsManager.shared.clearAllRecentActions()
            }
            print("✅ Cleared all pending and recent actions")
            exit(0)
        }

        cliHandler.register(
            "environment-crash",
            description: "Trigger a crash by rendering a view without required @Environment value (reproduces crash report)"
        ) { _ in
            print("""
            🔴 Environment Crash Test
            =========================

            This reproduces the crash from the crash report where:
            - A view uses @Environment(LiveSettings.self)
            - But LiveSettings is NOT provided via .environment()
            - SwiftUI crashes with: "No Observable object of type X found"

            Triggering crash in 2 seconds...
            """)

            try? await Task.sleep(for: .seconds(2))

            await MainActor.run {
                EnvironmentCrashTestView.triggerImmediateCrash()
            }

            // Keep running long enough for the crash to occur
            try? await Task.sleep(for: .seconds(10))
            exit(0)
        }

        cliHandler.register(
            "pull-memo",
            description: "Pull a specific memo from Core Data to GRDB by UUID. Usage: --debug=pull-memo <uuid>"
        ) { args in
            guard let uuidString = args.first else {
                print("❌ Usage: --debug=pull-memo <uuid>")
                print("   Example: --debug=pull-memo 25E8709E-CAF7-4612-92F5-730B419A5902")
                exit(1)
                return
            }

            // Parse UUID (handle both hyphenated and compact formats)
            let normalizedUUID: String
            if uuidString.contains("-") {
                normalizedUUID = uuidString.uppercased()
            } else {
                // Convert compact to hyphenated
                let s = uuidString.uppercased()
                guard s.count == 32 else {
                    print("❌ Invalid UUID format: \(uuidString)")
                    exit(1)
                    return
                }
                let idx = s.startIndex
                normalizedUUID = "\(s[idx..<s.index(idx, offsetBy: 8)])-\(s[s.index(idx, offsetBy: 8)..<s.index(idx, offsetBy: 12)])-\(s[s.index(idx, offsetBy: 12)..<s.index(idx, offsetBy: 16)])-\(s[s.index(idx, offsetBy: 16)..<s.index(idx, offsetBy: 20)])-\(s[s.index(idx, offsetBy: 20)..<s.index(idx, offsetBy: 32)])"
            }

            guard let uuid = UUID(uuidString: normalizedUUID) else {
                print("❌ Invalid UUID: \(uuidString)")
                exit(1)
                return
            }

            print("📥 Pulling memo: \(uuid)")

            // Ensure TalkieData has CoreData context
            await MainActor.run {
                let context = PersistenceController.shared.container.viewContext
                TalkieData.shared.configure(with: context)
            }

            // Wait for initialization
            try? await Task.sleep(for: .seconds(1))

            // Sync the specific memo
            await TalkieData.shared.syncMissingMemos(ids: [uuid])

            // Verify it was synced
            let repo = LocalRepository()
            if let memo = try? await repo.fetchMemo(id: uuid) {
                print("✅ Synced: '\(memo.memo.title ?? "Untitled")' (\(Int(memo.memo.duration))s)")
            } else {
                print("⚠️ Memo not found in Core Data or sync failed")
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

        logger.debug("URL: \(urlString)")

        // Accept environment-specific URL schemes (talkie, talkie-staging, talkie-dev)
        guard url.scheme == TalkieEnvironment.current.talkieURLScheme else {
            NSLog("[AppDelegate] URL not handled: invalid scheme (expected \(TalkieEnvironment.current.talkieURLScheme), got \(url.scheme ?? "nil"))")
            return
        }

        // Try Router first (handles Live notifications, app shortcuts, system commands)
        // This is the new unified routing system that replaces XPC for Live communication
        Task { @MainActor in
            if Router.shared.route(url) {
                // Router handled it - done
                return
            }

            // Fallback to legacy handlers for routes not yet migrated to Router

            // Handle talkie://live, talkie://live/home, talkie://live/recent
            if url.host == "live" {
                let path = url.pathComponents.dropFirst().first ?? ""
                NSLog("[AppDelegate] Navigating to Live section: \(path.isEmpty ? "default" : path)")
                logger.info("Navigating to Live section: \(path.isEmpty ? "default" : path)")

                // Ensure main window is visible
                NSApp.activate(ignoringOtherApps: true)
                if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    mainWindow.makeKeyAndOrderFront(nil)
                }

                if path == "recent" || path == "history" {
                    // Navigate to Live Recent (history)
                    NotificationCenter.default.post(name: .init("NavigateToLiveRecent"), object: nil)
                } else {
                    // Navigate to Live Dashboard
                    NotificationCenter.default.post(name: .navigateToLive, object: nil)
                }
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
                NSLog("[AppDelegate] Opening interstitial for dictation ID: \(id)")
                logger.info("Opening interstitial for dictation ID: \(id)")
                // Hide all main app windows when showing interstitial
                for window in NSApp.windows where window.title != "" {
                    window.orderOut(nil)
                }
                InterstitialManager.shared.show(dictationId: id)
            }
            else if self.handleDebugURL(url) {
                // Handled by debug URL handler
            }
            else {
                NSLog("[AppDelegate] URL not handled: scheme=\(url.scheme ?? "nil"), host=\(url.host ?? "nil")")
            }
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
                Task.detached {
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
                    let report = await DesignAuditor.shared.auditAll()
                    NSLog("[AppDelegate] ✅ Audit complete: \(report.grade) (\(report.overallScore)%)")

                    NSLog("[AppDelegate] 📝 Generating reports...")
                    await MainActor.run {
                        DesignAuditor.shared.generateHTMLReport(from: report, to: runDir.appendingPathComponent("report.html"))
                        DesignAuditor.shared.generateMarkdownReport(from: report, to: runDir.appendingPathComponent("report.md"))
                    }

                    // Back to main for UI operations
                    await Self.generateAuditIndex(at: baseDir)
                    await MainActor.run {
                        NSLog("[AppDelegate] ✅ All done!")
                        NSWorkspace.shared.open(runDir.appendingPathComponent("report.html"))
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
                    Task.detached {
                        NSLog("[AppDelegate] 🔍 Running code audit...")
                        let report = await DesignAuditor.shared.auditAll()
                        NSLog("[AppDelegate] ✅ Audit complete: \(report.grade) (\(report.overallScore)%)")

                        NSLog("[AppDelegate] 📝 Generating reports...")
                        await MainActor.run {
                            DesignAuditor.shared.generateHTMLReport(from: report, to: runDir.appendingPathComponent("report.html"))
                            DesignAuditor.shared.generateMarkdownReport(from: report, to: runDir.appendingPathComponent("report.md"))
                        }

                        await Self.generateAuditIndex(at: baseDir)
                        await MainActor.run {
                            NSLog("[AppDelegate] ✅ All done!")
                            NSWorkspace.shared.open(runDir.appendingPathComponent("report.html"))
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
        // Log notification for debugging
        let title = notification.request.content.title
        let body = notification.request.content.body
        logger.info("📬 Notification received - title: '\(title)', body: '\(body)'")

        // Filter out test/example notifications
        if title.lowercased().contains("example") || body.lowercased().contains("example") {
            logger.warning("⚠️ Suppressing example notification")
            completionHandler([])
            return
        }

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
        // Push is optional - sync still works via timer; push just enables instant sync
        // Debug level since this is expected on dev machines without push entitlement
        logger.debug("Push unavailable: \(error.localizedDescription)")
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

    // MARK: - Design God Mode

    #if DEBUG
    /// Setup ⌘⇧D keyboard shortcut to toggle Design God Mode
    /// When enabled, adds design sections to sidebar and enables visual overlays
    private func setupDesignModeShortcut() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for ⌘⇧D (Command+Shift+D)
            let hasCommand = event.modifierFlags.contains(.command)
            let hasShift = event.modifierFlags.contains(.shift)
            let isD = event.charactersIgnoringModifiers?.lowercased() == "d"

            if hasCommand && hasShift && isD {
                // Toggle Design God Mode
                DesignModeManager.shared.isEnabled.toggle()

                // Show toast notification
                let message = DesignModeManager.shared.isEnabled
                    ? "🎨 Design God Mode: ON"
                    : "Design God Mode: OFF"
                self?.showToast(message: message)

                return nil  // Consume event
            }

            return event  // Pass through
        }

        logger.info("⌘⇧D keyboard shortcut registered for Design God Mode")
    }

    /// Show a brief toast notification (simple alert-style for now)
    private func showToast(message: String) {
        DispatchQueue.main.async {
            // For now, use console + optional visual feedback later
            print(message)

            // Future: Could use NSUserNotification or custom window overlay
            // For V0, console print is sufficient
        }
    }
    #endif
}
