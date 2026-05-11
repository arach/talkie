//
//  AppDelegate.swift
//  Talkie macOS
//
//  App delegate and notification entry points
//

import AppKit
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {

    // CLI command handler
    private let cliHandler = CLICommandHandler()
    private var activeTTSSound: NSSound?

    // Capture chord local monitor (Hyper+S / Hyper+R)
    private var captureChordLocalMonitor: Any?
    // Direct screenshot shortcuts local monitor
    private var screenshotDirectLocalMonitor: Any?
    // Shelf toggle local monitor
    private var shelfLocalMonitor: Any?

    // MARK: - Window Restoration

    /// Prevent macOS from restoring old windows on launch
    /// This fixes the "blank windows" issue on fresh builds
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true  // Required for modern macOS, but we'll close stale windows
    }

    /// Close any windows restored from previous session that are blank/invalid
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register early URL handler to detect interstitial URLs before reopen handler runs
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

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
        // NOTE: Interstitial is now handled by TalkieAgent, so no check needed here

        // User explicitly clicked dock icon - restore to regular mode and show main window
        NSApp.setActivationPolicy(.regular)

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

        // Configure TalkieLogger FIRST (before any log calls)
        // This enables persistent file logging for all categories including sync
        TalkieLogger.configure(source: .talkie)

        // Configure glass effects from user preference (load-time only)
        GlassConfig.enableGlassEffects = SettingsManager.shared.enableGlassEffects

        // Record first launch date for onboarding
        SettingsManager.shared.recordFirstLaunchIfNeeded()

        // CRITICAL: Check for debug mode SYNCHRONOUSLY before initialization
        // Debug commands need isolated execution without CloudKit/helpers running
        let arguments = ProcessInfo.processInfo.arguments
        let isDebugMode = arguments.contains(where: { $0.starts(with: "--debug=") })
        if isDebugMode {
            // Register debug commands only for debug CLI runs.
            signposter.emitEvent("Debug Commands")
            registerDebugCommands()
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

        #if DEBUG
        // Start memory instrumentation for debugging
        Task { @MainActor in
            MemoryMonitor.shared.start()
            MemoryPressureHandler.shared.start()

            // Register cache purge handlers
            MemoryPressureHandler.shared.onPressure {
                AppIconProvider.shared.clearCache()
                logger.info("Memory pressure: purged icon cache")
            }

            // Log initial memory state
            MemoryMonitor.shared.logState(context: "startup")
        }
        #endif

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

        // Setup single-key shortcuts (C=compose, R=record) when not in text field
        setupSingleKeyShortcuts()

        // Sync feature flags to shared defaults so Agent can read them
        FeatureFlags.shared.syncAllToSharedDefaults()

        // NotchComposer — unified notch area coordinator
        NotchComposer.shared.setup()

        // Capture system (gated)
        if FeatureFlags.shared.enableCapture {
            // Start tray badge (auto-shows when tray non-empty)
            _ = TrayBadge.shared

            // Screenshot shortcuts (sub-gated)
            if FeatureFlags.shared.enableScreenshots {
                setupCaptureChord()
                setupDirectScreenshotShortcuts()

                // Warm core screenshot/tray path shortly after launch to reduce first-hit latency.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    _ = ScreenshotTray.shared.count
                    ScreenshotPreviewPanel.shared.prewarmIfNeeded()
                    ScreenshotCaptureService.shared.prewarmPipelineIfNeeded()
                }
            }

            // Camera bubble shortcut (sub-gated)
            if FeatureFlags.shared.enableCameraBubble {
                setupCameraBubbleShortcut()
            }

            setupShelfShortcut()
        }

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
                let timestamp = Date().iso8601.replacingOccurrences(of: ":", with: "-")
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
            "notch-status",
            description: "Print runtime notch diagnostics (flags, settings, screen detection, hot state)"
        ) { _ in
            let lines = await MainActor.run {
                NotchComposer.shared.debugStatusLines()
            }
            print("")
            print("Notch Diagnostics")
            print("═════════════════")
            for line in lines {
                print(line)
            }
            exit(0)
        }

        cliHandler.register(
            "console-loader-screenshot",
            description: "Capture the Console screen while the terminal loader is visible"
        ) { args in
            let outputURL: URL
            if let path = args.first {
                outputURL = URL(fileURLWithPath: path)
            } else {
                let timestamp = Date().iso8601.replacingOccurrences(of: ":", with: "-")
                outputURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("console-loader-\(timestamp).png")
            }

            print("📸 Capturing console loader to: \(outputURL.path)")
            if let savedURL = await ConsoleScreenshotGenerator.shared.captureLoaderFrame(to: outputURL) {
                print("✅ Saved console loader screenshot: \(savedURL.path)")
                exit(0)
            } else {
                print("❌ Failed to capture console loader screenshot")
                exit(1)
            }
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
                let timestamp = Date().iso8601.replacingOccurrences(of: ":", with: "-")
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
                let timestamp = Date().iso8601.replacingOccurrences(of: ":", with: "-")
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
                let timestamp = Date().iso8601.replacingOccurrences(of: ":", with: "-")
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
                        Theme.refresh()

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
                NSLog("[audit-screen] Capturing size: %@", size.rawValue)
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
                    NavigationState.shared.navigateToHome()
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
            - A view uses @Environment(AgentSettings.self)
            - But AgentSettings is NOT provided via .environment()
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
            description: "Trigger bridge sync from TalkieSync and check if memo exists. Usage: --debug=pull-memo <uuid>"
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

            print("📥 Looking for memo: \(uuid)")

            // Ensure SyncClient is connected
            await MainActor.run {
                SyncClient.shared.connect()
            }

            // Wait for connection
            try? await Task.sleep(for: .seconds(2))

            // Trigger bridge sync via TalkieSync
            print("🔄 Triggering bridge sync via TalkieSync...")
            do {
                let count = try await SyncClient.shared.runSyncPass()
                print("✅ Bridge sync complete: \(count) memos synced")
            } catch {
                print("⚠️ Bridge sync failed: \(error.localizedDescription)")
            }

            // Verify memo exists in GRDB
            let repo = LocalRepository()
            if let memo = try? await repo.fetchMemo(id: uuid) {
                print("✅ Found: '\(memo.memo.title ?? "Untitled")' (\(Int(memo.memo.duration))s)")
            } else {
                print("⚠️ Memo not found in GRDB after sync")
            }
            exit(0)
        }

        cliHandler.register(
            "audio-catchup",
            description: "Run one sync and verify recovery on N missing-audio memos. Usage: --debug=audio-catchup [count|--count=N]"
        ) { args in
            let defaultSampleCount = 2
            let optionCount = args
                .first { $0.hasPrefix("--count=") || $0.hasPrefix("--limit=") }
                .flatMap { arg -> Int? in
                    guard let value = arg.split(separator: "=", maxSplits: 1).last else { return nil }
                    return Int(value)
                }
            let positionalCount = args
                .first { !$0.starts(with: "--") }
                .flatMap(Int.init)
            let sampleCount = max(1, optionCount ?? positionalCount ?? defaultSampleCount)

            await StorageInventoryService.shared.refresh()
            let missingBefore = await MainActor.run {
                StorageInventoryService.shared.audioMissingMemos
                    .sorted { $0.createdAt > $1.createdAt }
            }

            guard !missingBefore.isEmpty else {
                print("✅ No missing audio memos found")
                exit(0)
                return
            }

            let targets = Array(missingBefore.prefix(sampleCount))
            print("🎧 Audio catch-up quick test")
            print("   Sample size: \(targets.count) memo(s)")
            print("   Missing audio before sync: \(missingBefore.count)")
            for memo in targets {
                print("   - \(memo.id.uuidString) \(memo.title)")
            }

            do {
                try await SyncClient.shared.runSyncOnce(keepRunning: false)
            } catch {
                print("❌ Sync failed: \(error.localizedDescription)")
                exit(1)
                return
            }

            await StorageInventoryService.shared.refresh()
            let missingAfter = await MainActor.run {
                StorageInventoryService.shared.audioMissingMemos
            }
            let missingIDsAfter = Set(missingAfter.map(\.id))
            let recovered = targets.filter { !missingIDsAfter.contains($0.id) }

            print("   Missing audio after sync: \(missingAfter.count)")
            print("   Recovered in sample: \(recovered.count)/\(targets.count)")
            for memo in targets {
                let recoveredLabel = missingIDsAfter.contains(memo.id) ? "still missing" : "recovered"
                print("   - \(memo.id.uuidString) \(recoveredLabel)")
            }

            if recovered.count == targets.count {
                print("✅ Audio catch-up sample completed")
                exit(0)
            } else {
                print("⚠️ Audio catch-up sample incomplete")
                exit(2)
            }
        }

        cliHandler.register(
            "test-workflow-import",
            description: "Run ImportPayloadConverter tests to verify URL workflow import converts to core WorkflowDefinition correctly"
        ) { _ in
            print("")
            ImportPayloadConverterTests.runAll()
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

        // NOTE: talkie://interstitial URLs are no longer handled by Talkie - interstitial moved to TalkieAgent

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

            // Handle talkie://agent and legacy talkie://live routes
            if let host = url.host, ["agent", "live"].contains(host) {
                // DEPRECATION WARNING: talkie://live is deprecated, use talkie://agent
                if host == "live" {
                    logger.warning("⚠️ DEPRECATED: talkie://live URL scheme used - migrate to talkie://agent")
                    NSLog("⚠️ [AppDelegate] DEPRECATED: talkie://live URL scheme is deprecated. Use talkie://agent instead.")
                }

                let path = url.pathComponents.dropFirst().first ?? ""
                NSLog("[AppDelegate] Navigating to Agent section: \(path.isEmpty ? "default" : path)")
                logger.info("Navigating to Agent section: \(path.isEmpty ? "default" : path)")

                // Ensure main window is visible
                NSApp.activate(ignoringOtherApps: true)
                if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    mainWindow.makeKeyAndOrderFront(nil)
                }

                if path == "recent" || path == "history" {
                    // Navigate to Agent Recent (history)
                    NavigationState.shared.navigateToDictations()
                } else if path == "dictation" {
                    // Navigate to specific dictation: talkie://agent/dictation?id={uuid}
                    if let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "id" })?.value,
                       let id = UUID(uuidString: idString) {
                        NavigationState.shared.navigateToDictation(id)
                    } else {
                        // Fallback to recent if no valid ID
                        NavigationState.shared.navigateToDictations()
                    }
                } else {
                    // Navigate to Agent Dashboard
                    NavigationState.shared.navigateToAgent()
                }
            }
            // Handle talkie://settings/agent and legacy talkie://settings/live
            else if url.host == "settings" {
                let path = url.pathComponents.dropFirst().first ?? ""
                NSLog("[AppDelegate] Navigating to Settings section: \(path)")
                logger.info("Navigating to Settings section: \(path)")

                if ["agent", "live"].contains(path) {
                    // DEPRECATION WARNING: talkie://settings/live is deprecated
                    if path == "live" {
                        logger.warning("⚠️ DEPRECATED: talkie://settings/live URL scheme used - migrate to talkie://settings/agent")
                        NSLog("⚠️ [AppDelegate] DEPRECATED: talkie://settings/live is deprecated. Use talkie://settings/agent instead.")
                    }
                    // Navigate directly to full Agent settings (bypasses main Settings)
                    NavigationState.shared.navigateToSettings(.dictationCapture)
                } else {
                    // Just open Settings
                    NavigationState.shared.navigate(to: .settings)
                }
            }
            // NOTE: talkie://interstitial/{id} was removed - interstitial now lives in TalkieAgent

            // Handle talkie://compose?text=... - opens Notes with pre-filled text
            else if url.host == "compose" {
                NSLog("[AppDelegate] Opening Notes")
                logger.info("Opening Notes from URL")

                // Ensure main window is visible
                NSApp.activate(ignoringOtherApps: true)
                if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    mainWindow.makeKeyAndOrderFront(nil)
                }

                // Extract text from query parameter
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let text = components?.queryItems?.first(where: { $0.name == "text" })?.value

                // Navigate to Notes with optional text
                NavigationState.shared.navigateToCompose(withText: text)
            }
            // Handle talkie://speak?text=... - speak text using the configured TTS voice
            else if url.host == "speak" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let text = components?.queryItems?.first(where: { $0.name == "text" })?.value
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Log(.system).info("Speaking text from URL")
                    Task { @MainActor in
                        await self.speakTextFromSelection(text)
                    }
                }
            }
            else if self.handleDebugURL(url) {
                // Handled by debug URL handler
            }
            else {
                NSLog("[AppDelegate] URL not handled: scheme=\(url.scheme ?? "nil"), host=\(url.host ?? "nil")")
            }
        }
    }

    @MainActor
    private func speakTextFromSelection(_ text: String) async {
        // Stop any previous TTS before starting a new one
        activeTTSSound?.stop()
        activeTTSSound = nil

        let log = Log(.system)
        let selectedVoiceId = TTSVoiceCatalog.voice(byId: SettingsManager.shared.selectedTTSVoiceId)?.id
            ?? TTSVoiceCatalog.recommendedSettingsVoiceId(hasOpenAIKey: SettingsManager.shared.hasOpenAIKey())

        if selectedVoiceId.hasPrefix("elevenlabs:") {
            let voiceId = String(selectedVoiceId.dropFirst("elevenlabs:".count))
            do {
                let audioURL = try await TTSService.synthesizeElevenLabs(
                    text: text,
                    voiceId: voiceId,
                    apiKey: SettingsManager.shared.fetchElevenLabsKey()
                )
                activeTTSSound = NSSound(contentsOf: audioURL, byReference: true)
                if activeTTSSound?.play() != true {
                    log.warning("Failed to play synthesized ElevenLabs audio")
                }
            } catch {
                log.error("Failed to synthesize ElevenLabs speech: \(error.localizedDescription)")
            }
            return
        }

        if selectedVoiceId.hasPrefix("openai:") {
            let voice = String(selectedVoiceId.dropFirst("openai:".count))
            do {
                let audioURL = try await TTSService.synthesizeOpenAI(
                    text: text,
                    voice: voice,
                    apiKey: SettingsManager.shared.openaiApiKey
                )
                activeTTSSound = NSSound(contentsOf: audioURL, byReference: true)
                if activeTTSSound?.play() != true {
                    log.warning("Failed to play synthesized OpenAI audio")
                }
            } catch {
                log.error("Failed to synthesize OpenAI speech: \(error.localizedDescription)")
            }
            return
        }

        let speechService = SpeechSynthesisService.shared
        if selectedVoiceId.hasPrefix("com.apple.voice") {
            speechService.selectedVoiceIdentifier = selectedVoiceId
        }
        speechService.speak(text)
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
                    NavigationState.shared.navigate(to: .settings)
                    try? await Task.sleep(for: .milliseconds(500))

                    // Capture all settings pages with navigation
                    let timestamp = Date().iso8601.replacingOccurrences(of: ":", with: "-")
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
                    NavigationState.shared.navigate(to: .settings)
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
            Task { @MainActor in
                NavigationState.shared.navigate(to: .settings)
            }

            // Then navigate to specific section (with slight delay for window to open)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task { @MainActor in
                    if let section = SettingsSection.from(path: String(components.dropFirst().joined(separator: "/"))) {
                        NavigationState.shared.navigateToSettings(section)
                    }
                }
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

    func applicationWillTerminate(_ notification: Notification) {
        ConsoleSessionPool.shared.detachAll()
        ManagedAgentConsoleSession.handleApplicationWillTerminate()
        ServiceManager.shared.bootoutHelpers()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Force redraw when app becomes active to ensure crisp rendering
        for window in NSApp.windows {
            window.contentView?.needsDisplay = true
        }

        // Refresh agent permissions — user may have granted/revoked in System Settings
        ServiceManager.shared.live.refreshPermissions()

        // Refresh local permissions without triggering first-run prompts.
        PermissionsManager.shared.refreshPassivePermissions()
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

        // Trigger a token-based sync to fetch only changed records
        Task { @MainActor in
            CloudKitSyncManager.shared.syncNow()
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

    // MARK: - Single-Key Shortcuts

    /// Setup Gmail-style single-key shortcuts that work when not in a text field:
    /// - C = Compose
    /// - R = Record (start a new memo recording)
    /// - D = Dictations
    /// - N = Notes, S = Screenshots
    /// - J = Navigate down (vim-style)
    /// - K = Navigate up (vim-style)
    /// - O = Open/activate selected item
    /// - ? = Show keyboard shortcuts help (Shift+/ or typed ?)
    private func setupSingleKeyShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if HotkeyRecordingCoordinator.shared.isRecording {
                return event
            }

            // Check if we're in a text input context - if so, pass through
            if let responder = NSApp.keyWindow?.firstResponder {
                // NSTextView = rich text editors, field editor, multi-line text
                if responder is NSTextView {
                    return event
                }
                // NSTextField / NSSearchField — typing must not be intercepted
                if responder is NSTextField {
                    return event
                }
                // Note: Avoid a blanket NSTextInputClient check — SwiftUI list/table focus
                // often uses input contexts that are not real typing; that blocked J/K/O and ?.
            }

            // Don't intercept if command palette, voice command, or keyboard help is active
            if SettingsManager.shared.isCommandPalettePresented ||
               SettingsManager.shared.isVoiceCommandPresented ||
               SettingsManager.shared.isKeyboardHelpPresented {
                return event
            }

            // Don't intercept in the console — terminal emulator needs all keys
            if NavigationState.shared.selectedSection == .systemConsole {
                return event
            }

            // Corner hint panel — ⌘⇧/ or ⌃⇧/ (same key as ?, with extra modifiers)
            if Self.isToggleInlineKeyboardHintsChord(event) {
                NotificationCenter.default.post(name: .toggleKeyboardHintOverlay, object: nil)
                return nil
            }

            // "?" keyboard help — Shift+/ (US) or any layout that yields "?" without ⌘⌥⌃
            let chordMods: NSEvent.ModifierFlags = [.command, .option, .control]
            if event.modifierFlags.intersection(chordMods).isEmpty {
                let isShiftSlash = event.charactersIgnoringModifiers == "/" &&
                    event.modifierFlags.contains(.shift)
                let isQuestion = event.characters == "?"
                if isShiftSlash || isQuestion {
                    NotificationCenter.default.post(name: .showKeyboardHelp, object: nil)
                    return nil  // Consume event
                }
            }

            // For other shortcuts, require no modifiers
            let significantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard event.modifierFlags.intersection(significantModifiers).isEmpty else {
                return event
            }

            // Handle single-key shortcuts
            guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            if let action = SingleKeyShortcutAction.action(for: chars) {
                Task { @MainActor in
                    action.perform()
                }
                return nil
            }

            switch chars {
            case "j":
                // J = Navigate down (vim-style)
                Self.postArrowKey(down: true)
                return nil

            case "k":
                // K = Navigate up (vim-style)
                Self.postArrowKey(down: false)
                return nil

            case "o":
                // O = Open/activate selected item
                Self.postKeyEvent(keyCode: 36)  // Return key
                return nil

            default:
                return event
            }
        }

        logger.info("Single-key shortcuts: C (compose) | R (record) | D (dictations) | N (notes) | S (screenshots) | J/K | O | ? | ⌘⇧? hints | ⌃⇧? hints")
    }

    /// ⌘⇧/ or ⌃⇧/ — toggles non-modal shortcut hint panel (same key as `?`).
    private static func isToggleInlineKeyboardHintsChord(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard event.charactersIgnoringModifiers == "/" else { return false }
        guard event.modifierFlags.contains(.shift) else { return false }
        if event.modifierFlags.contains(.option) { return false }
        let cmd = event.modifierFlags.contains(.command)
        let ctrl = event.modifierFlags.contains(.control)
        if cmd && ctrl { return false }
        return (cmd && !ctrl) || (!cmd && ctrl)
    }

    /// Synthesize an arrow key event to trigger list navigation
    private static func postArrowKey(down: Bool) {
        // Down arrow = keyCode 125, Up arrow = keyCode 126
        let keyCode: UInt16 = down ? 125 : 126
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        event.flags = []  // No modifiers
        if let nsEvent = NSEvent(cgEvent: event) {
            NSApp.sendEvent(nsEvent)
        }
    }

    /// Synthesize a key event
    private static func postKeyEvent(keyCode: UInt16, modifiers: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        event.flags = modifiers
        if let nsEvent = NSEvent(cgEvent: event) {
            NSApp.sendEvent(nsEvent)
        }
    }

    // MARK: - Unified Capture Chord (Hyper+S / Hyper+R)

    /// Register capture chord listeners.
    /// TalkieAgent owns the Hyper+S and Hyper+R hotkeys (via RegisterEventHotKey)
    /// and forwards them to Talkie via distributed notifications.
    /// We also keep a local monitor for when Talkie is focused.
    private func setupCaptureChord() {
        // Listen for TalkieAgent forwarding Hyper+S (screenshot) and Hyper+R (video)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenshotChordReceived),
            name: NSNotification.Name("com.jdi.talkie.screenshotChord"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenRecordChordReceived),
            name: NSNotification.Name("com.jdi.talkie.screenRecordChord"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectionContextCaptured),
            name: NSNotification.Name("com.jdi.talkie.captureSelectionContext"),
            object: nil
        )

        // Listen for TalkieAgent forwarding Hyper+V (paste)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(pasteChordReceived),
            name: NSNotification.Name("com.jdi.talkie.pasteChord"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(pasteLastScreenshotReceived),
            name: NSNotification.Name("com.jdi.talkie.pasteLastScreenshot"),
            object: nil
        )

        // Local: fires when Talkie is focused (Agent's hotkey may not forward in this case)
        // Read chord config directly from shared settings (avoids @MainActor isolation)
        let captureChord = HotkeyConfig.fromSharedSettings(
            key: AgentSettingsKey.captureChordHotkey, default: .defaultCaptureChord
        )
        let screenRecordChord = HotkeyConfig.fromSharedSettings(
            key: AgentSettingsKey.screenRecordChordHotkey, default: .defaultScreenRecordChord
        )
        let pasteChord = HotkeyConfig.fromSharedSettings(
            key: AgentSettingsKey.pasteChordHotkey, default: .defaultPasteChord
        )
        let captureKeyCode = captureChord.keyCode
        let captureMods = captureChord.nsModifierFlags
        let recordKeyCode = screenRecordChord.keyCode
        let recordMods = screenRecordChord.nsModifierFlags
        let pasteKeyCode = pasteChord.keyCode
        let pasteMods = pasteChord.nsModifierFlags
        captureChordLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if HotkeyRecordingCoordinator.shared.isRecording {
                return event
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Check screenshot chord
            if mods.contains(captureMods), event.keyCode == captureKeyCode {
                if self?.capturePerfLoggingEnabled == true {
                    Log(.system).info("Screenshot chord detected (local) — entering capture bar")
                }
                let frontApp = NSWorkspace.shared.frontmostApplication
                Task { @MainActor in
                    await self?.handleCaptureChord(initialMode: .screenshot, previousApp: frontApp)
                }
                return nil
            }

            // Check screen record chord
            if mods.contains(recordMods), event.keyCode == recordKeyCode {
                if self?.capturePerfLoggingEnabled == true {
                    Log(.system).info("Screen record chord detected (local) — entering capture bar")
                }
                let frontApp = NSWorkspace.shared.frontmostApplication
                Task { @MainActor in
                    await self?.handleCaptureChord(initialMode: .video, previousApp: frontApp)
                }
                return nil
            }

            // Check paste chord
            if mods.contains(pasteMods), event.keyCode == pasteKeyCode {
                if self?.capturePerfLoggingEnabled == true {
                    Log(.system).info("Paste chord detected (local) — entering paste bar")
                }
                let frontApp = NSWorkspace.shared.frontmostApplication
                Task { @MainActor in
                    await self?.handlePasteChord(previousApp: frontApp)
                }
                return nil
            }
            return event
        }

        logger.info("Capture chord registered: Hyper+S (screenshot) + Hyper+R (video) + Hyper+V (paste)")
    }

    @MainActor @objc private func screenshotChordReceived(_ notification: Notification) {
        // Snapshot and re-activate the frontmost app immediately — the distributed
        // notification delivery can cause macOS to bring Talkie forward.
        let frontApp = NSWorkspace.shared.frontmostApplication
        stageSelectionFromCaptureNotification(notification)
        if let prev = frontApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            // Schedule re-activation on next run loop tick so it beats the window server
            DispatchQueue.main.async { prev.activate() }
        }
        Task { @MainActor in
            await self.handleCaptureChord(initialMode: .screenshot, previousApp: frontApp)
        }
    }

    @MainActor @objc private func screenRecordChordReceived(_ notification: Notification) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        stageSelectionFromCaptureNotification(notification)
        if let prev = frontApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            DispatchQueue.main.async { prev.activate() }
        }
        Task { @MainActor in
            await self.handleCaptureChord(initialMode: .video, previousApp: frontApp)
        }
    }

    @MainActor @objc private func pasteChordReceived(_ notification: Notification) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        if let prev = frontApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            DispatchQueue.main.async { prev.activate() }
        }
        Task { @MainActor in
            await self.handlePasteChord(previousApp: frontApp)
        }
    }

    @MainActor @objc private func pasteLastScreenshotReceived(_ notification: Notification) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        if let prev = frontApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            DispatchQueue.main.async { prev.activate() }
        }
        Task { @MainActor in
            await self.pasteLatestScreenshot(previousApp: frontApp)
        }
    }

    @MainActor @objc private func selectionContextCaptured(_ notification: Notification) {
        stageSelectionFromCaptureNotification(notification)
    }

    @MainActor
    private func stageSelectionFromCaptureNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let text = userInfo["selectionText"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        SelectionTray.shared.add(
            text: text,
            appName: emptyToNil(userInfo["selectionAppName"] as? String),
            bundleID: emptyToNil(userInfo["selectionBundleID"] as? String),
            windowTitle: emptyToNil(userInfo["selectionWindowTitle"] as? String),
            displayName: "Selection"
        )
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private var isCaptureChordActive = false

    /// Handle Hyper+S or Hyper+R: show unified capture bar, get result.
    /// For video mode, if already recording, stop instead of showing bar.
    /// Important: must NOT bring the Talkie main window forward — the capture
    /// bar is a floating panel that appears over whatever app the user is in.
    @MainActor
    private func handleCaptureChord(initialMode: CaptureBarMode, previousApp: NSRunningApplication?) async {
        // If video mode and already recording, Hyper+R stops the recording
        if initialMode == .video && ScreenRecordingController.shared.state == .recording {
            await ScreenRecordingController.shared.stopRecording()
            return
        }

        guard !isCaptureChordActive else { return }
        isCaptureChordActive = true
        defer { isCaptureChordActive = false }

        // Immediately yield activation back to the previous app.
        // The capture bar panel floats above everything (.screenSaver+1 level)
        // so it stays visible even when Talkie isn't active.
        if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate()
        }

        let chord: any CaptureChordController =
            SettingsManager.shared.captureChordStyle == .hud
                ? CaptureHUDController()
                : CaptureRadialController()

        let trackCapturePerf = capturePerfLoggingEnabled && initialMode == .screenshot
        if trackCapturePerf {
            CapturePerformanceMonitor.shared.beginSession(trigger: "capture-chord", mode: "pending")
            CapturePerformanceMonitor.shared.mark("chord.panel.begin")
        }
        guard let result = await chord.beginChord(initialMode: initialMode) else {
            if trackCapturePerf {
                CapturePerformanceMonitor.shared.endSession(outcome: "cancelled")
            }
            return
        }
        if trackCapturePerf {
            CapturePerformanceMonitor.shared.mark("chord.selection.complete")
        }

        switch result {
        case .screenshot(let mode):
            if trackCapturePerf {
                CapturePerformanceMonitor.shared.updateMode(mode.rawValue)
                CapturePerformanceMonitor.shared.mark("capture.route.begin")
            }
            let success = await executeCapture(mode: mode)
            if trackCapturePerf {
                CapturePerformanceMonitor.shared.endSession(outcome: success ? "success" : "cancelled_or_failed")
            }
        case .screenRecord(let mode):
            await ScreenRecordingController.shared.startRecording(mode: mode)
            if trackCapturePerf {
                CapturePerformanceMonitor.shared.endSession(outcome: "screen_record_selected")
            }
        case .toggleCamera:
            CameraBubbleController.shared.toggle()
            if trackCapturePerf {
                CapturePerformanceMonitor.shared.endSession(outcome: "toggle_camera_selected")
            }
        case .saveSelection:
            await TrayViewer.saveLatestSelectionToNote()
            if trackCapturePerf {
                CapturePerformanceMonitor.shared.endSession(outcome: "save_selection_selected")
            }
        case .viewTray:
            TrayViewer.shared.show()
            if trackCapturePerf {
                CapturePerformanceMonitor.shared.endSession(outcome: "view_tray_selected")
            }
        case .pasteLastTray:
            await pasteLatestScreenshot(previousApp: previousApp)
            if trackCapturePerf {
                CapturePerformanceMonitor.shared.endSession(outcome: "paste_last_selected")
            }
        }

        // For background ops, ensure the previous app stays in front
        if result.isBackground, let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate()
        }
    }

    /// Shared capture logic used by both chord flow and direct shortcuts.
    /// If recording is active, attaches screenshot to the recording (always uses built-in).
    /// Otherwise, checks the preferred launcher setting.
    @MainActor
    private func executeCapture(mode: CaptureMode) async -> Bool {
        let recorder = MemoRecordingController.shared

        if recorder.state.isRecording {
            // Always use built-in capture when recording — need the image data for attachment
            await recorder.captureScreenshot(mode: mode)
            Log(.system).info("Screenshot attached to active recording (mode=\(mode.rawValue))")
            return true
        }

        return await captureWithBuiltin(mode: mode)
    }

    @MainActor
    private func pasteLatestScreenshot(previousApp: NSRunningApplication?) async {
        guard let latest = ScreenshotTray.shared.items.max(by: { $0.capturedAt < $1.capturedAt }),
              let data = latest.loadData() else {
            Log(.system).info("Paste latest screenshot: no screenshot available")
            return
        }

        guard let durableURL = durablePasteURL(for: latest, data: data) else {
            Log(.system).error("Paste latest screenshot: failed to create durable screenshot copy")
            return
        }

        writeScreenshotPasteboard(data: data, fileURL: durableURL)

        if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate()
        }

        try? await Task.sleep(for: .milliseconds(80))
        simulateCmdV()
        Log(.system).info("Pasted latest screenshot: \(durableURL.lastPathComponent)")
    }

    // MARK: - Quick Paste Chord (Hyper+V)

    private var isPasteChordActive = false

    @MainActor
    private func handlePasteChord(previousApp: NSRunningApplication?) async {
        guard !isPasteChordActive else { return }
        isPasteChordActive = true
        defer { isPasteChordActive = false }

        // Yield activation back to the previous app — panel floats above
        if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate()
        }

        let controller = PasteChordController()
        guard let result = await controller.beginChord() else { return }

        if result.format == .dragFile {
            // Drag mode: start a drag session from a transparent window at cursor
            beginFileDrag(item: result.item)
            return
        }

        // Re-activate previous app before pasting into it
        if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate()
        }

        executePaste(item: result.item, format: result.format)

        // Brief delay for app activation to settle, then simulate Cmd+V
        try? await Task.sleep(for: .milliseconds(80))
        simulateCmdV()
    }

    @MainActor
    private func executePaste(item: TrayItem, format: PasteFormat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch format {
        case .image:
            if case .screenshot(let screenshot) = item,
               let data = screenshot.loadData(),
               let durableURL = durablePasteURL(for: screenshot, data: data) {
                writeScreenshotPasteboard(data: data, fileURL: durableURL)
                Log(.system).info("Quick Paste: screenshot image + markdown → clipboard")
                return
            }

            guard let data = loadTrayItemData(item) else { return }
            pasteboard.setData(data, forType: .png)
            Log(.system).info("Quick Paste: image → clipboard")

        case .filePath:
            let path = item.tempURL.path
            pasteboard.setString(path, forType: .string)
            Log(.system).info("Quick Paste: file path → clipboard")

        case .url:
            let urlString = "http://localhost:8766/tray/\(item.id.uuidString).png"
            pasteboard.setString(urlString, forType: .string)
            Log(.system).info("Quick Paste: URL → clipboard")

        case .base64:
            guard let data = loadTrayItemData(item) else { return }
            let b64 = "data:image/png;base64," + data.base64EncodedString()
            pasteboard.setString(b64, forType: .string)
            Log(.system).info("Quick Paste: base64 → clipboard")

        case .dragFile:
            break // Handled separately via beginFileDrag
        }
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func durablePasteURL(for screenshot: TrayScreenshot, data: Data) -> URL? {
        ScreenshotStorage.saveStandalone(
            data,
            capturedAt: screenshot.capturedAt,
            captureMode: screenshot.mode.rawValue,
            width: screenshot.width,
            height: screenshot.height,
            windowTitle: screenshot.windowTitle,
            appName: screenshot.appName,
            displayName: screenshot.displayName
        )
    }

    private func writeScreenshotPasteboard(data: Data, fileURL: URL) {
        let markdown = "![Talkie Capture](<\(fileURL.path)>)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        pasteboard.setData(data, forType: .png)
    }

    // MARK: - File Drag

    private var fileDragPanel: FileDragPanel?

    @MainActor
    private func beginFileDrag(item: TrayItem) {
        let panel = FileDragPanel()
        panel.show(item: item)
        self.fileDragPanel = panel
    }

    private func loadTrayItemData(_ item: TrayItem) -> Data? {
        switch item {
        case .screenshot(let s):
            return s.loadData()
        case .clip(let c):
            return try? Data(contentsOf: c.tempURL)
        case .selection:
            return nil
        }
    }

    @MainActor
    private func captureWithBuiltin(mode: CaptureMode) async -> Bool {
        CapturePerformanceMonitor.shared.mark("capture.service.begin")
        guard let result = await ScreenshotCaptureService.shared.captureStandalone(mode: mode) else {
            CapturePerformanceMonitor.shared.mark("capture.service.failed")
            return false
        }
        CapturePerformanceMonitor.shared.mark("capture.service.complete")

        CapturePerformanceMonitor.shared.mark("tray.add.begin")
        await ScreenshotTray.shared.add(
            data: result.data,
            width: result.width,
            height: result.height,
            mode: mode,
            windowTitle: result.windowTitle,
            appName: result.appName,
            displayName: result.displayName
        )
        CapturePerformanceMonitor.shared.mark("tray.add.complete")
        // Show preview with the tray item's file URL for drag support
        if let latestItem = ScreenshotTray.shared.items.last {
            CapturePerformanceMonitor.shared.mark("preview.show.begin")
            let previewImage: CGImage
            if let decodedImage = NSImage(data: result.data),
               let decodedCG = decodedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                previewImage = decodedCG
            } else {
                previewImage = result.image
            }
            ScreenshotPreviewPanel.shared.show(image: previewImage, fileURL: latestItem.tempURL)
            CapturePerformanceMonitor.shared.mark("preview.show.complete")
        }
        return true
    }

    // MARK: - Direct Screenshot Shortcuts

    /// Listen for Cmd+Shift+3/4/5/6 forwarded from TalkieAgent.
    /// These bypass the chord HUD and execute the capture mode directly.
    private var isDirectScreenshotCaptureActive = false
    private var lastDirectScreenshotMode: String?
    private var lastDirectScreenshotAt: Date = .distantPast
    private let capturePerfLoggingEnabled: Bool = {
        let env = ProcessInfo.processInfo.environment["CAPTURE_PERF"]
        if env == "0" { return false }
        if env == "1" { return true }
        return UserDefaults.standard.bool(forKey: "capturePerfEnabled")
    }()

    private func setupDirectScreenshotShortcuts() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.jdi.talkie.screenshotDirect"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let mode = notification.object as? String ?? ""
            Task { @MainActor in
                await self?.handleDirectScreenshot(mode: mode)
            }
        }

        // Local monitor for when Talkie is focused (Agent's Carbon hotkey may not fire)
        // Uses HotkeyRegistry so shortcuts are user-configurable.
        screenshotDirectLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if HotkeyRecordingCoordinator.shared.isRecording {
                return event
            }

            if event.isARepeat {
                return nil
            }

            let registry = HotkeyRegistry.shared
            let actionMap: [HotkeyAction: String] = [
                .captureFullscreen: "fullscreen",
                .captureRegion:     "region",
                .openTrayViewer:    "viewTray",
                .captureWindow:     "window",
                .pasteLastScreenshot: "pasteLastScreenshot",
            ]

            for (action, mode) in actionMap {
                let cfg = registry.config(for: action)
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == UInt16(cfg.keyCode) && mods == cfg.nsModifierFlags {
                    Task { @MainActor in
                        await self?.handleDirectScreenshot(mode: mode)
                    }
                    return nil
                }
            }
            return event
        }

        logger.info("Direct screenshot shortcuts registered via HotkeyRegistry")
    }

    @MainActor
    private func handleDirectScreenshot(mode: String) async {
        let start = CFAbsoluteTimeGetCurrent()
        let now = Date()
        // Collapse duplicate trigger paths (distributed + local monitors) and bursty repeats.
        if lastDirectScreenshotMode == mode, now.timeIntervalSince(lastDirectScreenshotAt) < 0.20 {
            return
        }
        lastDirectScreenshotMode = mode
        lastDirectScreenshotAt = now

        guard !isDirectScreenshotCaptureActive else { return }
        isDirectScreenshotCaptureActive = true
        defer { isDirectScreenshotCaptureActive = false }

        let trackCapturePerfSession = capturePerfLoggingEnabled && mode != "viewTray" && mode != "pasteLastScreenshot"
        if trackCapturePerfSession {
            CapturePerformanceMonitor.shared.beginSession(trigger: "direct-shortcut", mode: mode)
            CapturePerformanceMonitor.shared.mark("direct.dispatch.begin")
        }

        var outcome = "noop"
        switch mode {
        case "fullscreen":
            outcome = await executeCapture(mode: .fullscreen) ? "success" : "cancelled_or_failed"
        case "region":
            outcome = await executeCapture(mode: .region) ? "success" : "cancelled_or_failed"
        case "window":
            outcome = await executeCapture(mode: .window) ? "success" : "cancelled_or_failed"
        case "viewTray":
            await handleCaptureChord(initialMode: .screenshot, previousApp: NSWorkspace.shared.frontmostApplication)
            outcome = "view_tray"
        case "pasteLastScreenshot":
            await pasteLatestScreenshot(previousApp: NSWorkspace.shared.frontmostApplication)
            outcome = "paste_last_screenshot"
        default: break
        }
        if trackCapturePerfSession {
            CapturePerformanceMonitor.shared.mark("direct.dispatch.complete")
            CapturePerformanceMonitor.shared.endSession(outcome: outcome)
        }

        if capturePerfLoggingEnabled {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Log(.system).info("Direct screenshot action finished: mode=\(mode), elapsed=\(Int(elapsedMs.rounded()))ms")
        }
    }

    // MARK: - Camera Bubble

    /// Local monitor for Cmd+Shift+C to toggle the face camera bubble.
    private var cameraLocalMonitor: Any?

    private func setupCameraBubbleShortcut() {
        // Listen for TalkieAgent forwarding camera toggle
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(cameraBubbleToggleReceived),
            name: NSNotification.Name("com.jdi.talkie.cameraBubbleToggle"),
            object: nil
        )

        // Local: Cmd+Shift+C (keyCode 8) when Talkie is focused
        cameraLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if HotkeyRecordingCoordinator.shared.isRecording {
                return event
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // keyCode 8 = C key
            if mods.contains([.command, .shift]) && event.keyCode == 8 {
                Task { @MainActor in
                    guard FeatureFlags.shared.enableCameraBubble else { return }
                    CameraBubbleController.shared.toggle()
                }
                return nil
            }
            return event
        }

        logger.info("Camera bubble shortcut registered: Cmd+Shift+C")
    }

    @objc private func cameraBubbleToggleReceived(_ notification: Notification) {
        Task { @MainActor in
            guard FeatureFlags.shared.enableCameraBubble else { return }
            CameraBubbleController.shared.toggle()
        }
    }

    // MARK: - Tray Shortcuts (Viewer + Shelf)

    private func setupShelfShortcut() {
        // Listen for TalkieAgent forwarding shelf/viewer toggles
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(shelfToggleReceived),
            name: NSNotification.Name("com.jdi.talkie.shelfToggle"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(trayViewerToggleReceived),
            name: NSNotification.Name("com.jdi.talkie.trayViewerToggle"),
            object: nil
        )

        // Local shortcuts when Talkie is focused:
        // - Cmd+Shift+T (keyCode 17) = Shelf toggle
        // - Cmd+Shift+W (keyCode 13) = Tray viewer toggle
        shelfLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if HotkeyRecordingCoordinator.shared.isRecording {
                return event
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains([.command, .shift]) else { return event }

            switch event.keyCode {
            case 17: // T
                Task { @MainActor in
                    TrayShelf.shared.toggle()
                }
                return nil
            case 13: // W
                Task { @MainActor in
                    if TrayViewer.shared.isVisible {
                        TrayViewer.shared.dismiss()
                    } else {
                        TrayViewer.shared.show()
                    }
                }
                return nil
            default:
                return event
            }
        }

        logger.info("Tray shortcuts registered: Cmd+Shift+T (shelf), Cmd+Shift+W (viewer)")
    }

    @objc private func shelfToggleReceived(_ notification: Notification) {
        Task { @MainActor in
            TrayShelf.shared.toggle()
        }
    }

    @objc private func trayViewerToggleReceived(_ notification: Notification) {
        Task { @MainActor in
            if TrayViewer.shared.isVisible {
                TrayViewer.shared.dismiss()
            } else {
                TrayViewer.shared.show()
            }
        }
    }

    // MARK: - Design God Mode

    #if DEBUG
    /// Setup design mode keyboard shortcuts:
    /// - ⌘⇧D = Toggle Design God Mode (auto-enables guides)
    /// - ⌘⇧⌥D = Screenshot with dimensions (saved to Desktop, path copied)
    /// - G = Toggle guides (when design mode is active, no modifiers)
    /// - R = Toggle rulers (when design mode is active, no modifiers)
    /// - B = Toggle borders (when design mode is active, no modifiers)
    private func setupDesignModeShortcut() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if HotkeyRecordingCoordinator.shared.isRecording {
                return event
            }

            let hasCommand = event.modifierFlags.contains(.command)
            let hasShift = event.modifierFlags.contains(.shift)
            let hasOption = event.modifierFlags.contains(.option)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let noModifiers = !hasCommand && !hasShift && !hasOption

            // ⌘⇧⌥D = Screenshot (with Option)
            if hasCommand && hasShift && hasOption && key == "d" {
                if let path = DesignModeManager.shared.captureScreenshot() {
                    self?.showToast(message: "📸 Screenshot saved!\n\(path)")
                }
                return nil
            }

            // ⌘⇧D = Toggle Design Mode (auto-enables guides on activation)
            if hasCommand && hasShift && key == "d" && !hasOption {
                let dm = DesignModeManager.shared
                dm.isEnabled.toggle()

                if dm.isEnabled {
                    // Auto-enable guides when entering design mode
                    dm.showGuides = true
                    self?.showToast(message: "🎨 Design Mode + Guides ON")
                } else {
                    self?.showToast(message: "Design Mode: OFF")
                }

                return nil
            }

            // Design mode chord keys (only when design mode is active, no modifiers held)
            // These let you quickly toggle decorators without reaching for modifier keys
            if DesignModeManager.shared.isEnabled && noModifiers {
                let dm = DesignModeManager.shared
                switch key {
                case "g":
                    dm.showGuides.toggle()
                    self?.showToast(message: dm.showGuides ? "Guides: ON" : "Guides: OFF")
                    return nil
                case "r":
                    dm.showRulers.toggle()
                    self?.showToast(message: dm.showRulers ? "Rulers: ON" : "Rulers: OFF")
                    return nil
                case "b":
                    dm.showBorders.toggle()
                    self?.showToast(message: dm.showBorders ? "Borders: ON" : "Borders: OFF")
                    return nil
                case "x":
                    dm.showGrid.toggle()
                    self?.showToast(message: dm.showGrid ? "Grid: ON" : "Grid: OFF")
                    return nil
                default:
                    break
                }
            }

            return event
        }

        logger.info("Design shortcuts: ⌘⇧D (toggle) | ⌘⇧⌥D (screenshot) | G/R/B/X (chords when active)")
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
