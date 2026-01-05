//
//  DebugCommandHandler.swift
//  Talkie macOS
//
//  Handles headless debug commands via CLI
//  Usage: Talkie.app/Contents/MacOS/Talkie --debug=<command> [args...]
//

import Foundation
import AppKit

@MainActor
class DebugCommandHandler {
    static let shared = DebugCommandHandler()

    private init() {}

    /// Check command line arguments and execute debug command if present
    /// Returns true if a debug command was executed (app should exit)
    func handleCommandLineArguments() async -> Bool {
        print("🔍 handleCommandLineArguments START")
        let args = CommandLine.arguments
        print("🔍 Got args: \(args.count) items")

        // Look for --debug=<command>
        guard let debugArg = args.first(where: { $0.hasPrefix("--debug=") }) else {
            print("🔍 No debug arg found")
            return false
        }
        print("🔍 Found debug arg: \(debugArg)")

        let command = String(debugArg.dropFirst("--debug=".count))
        print("🔍 Parsing command: \(command)")

        // Get additional arguments (everything after the --debug flag)
        let additionalArgs = args.dropFirst(args.firstIndex(of: debugArg)! + 1)
        print("🔍 Additional args: \(Array(additionalArgs))")

        print("🐛 Debug command: \(command)")

        await executeCommand(command, args: Array(additionalArgs))
        return true
    }

    private func executeCommand(_ command: String, args: [String]) async {
        switch command {
        case "onboarding-storyboard":
            await generateOnboardingStoryboard(args: args)

        case "settings-storyboard":
            await generateSettingsStoryboard(args: args)

        case "settings-screenshots":
            await captureSettingsScreenshots(args: args)

        case "design-audit":
            await runDesignAudit()

        case "environment-crash":
            await triggerEnvironmentCrash()

        case "pull-memo":
            await pullMemo(args: args)

        case "help":
            printHelp()
            exit(0)

        default:
            print("❌ Unknown debug command: \(command)")
            print("")
            printHelp()
            exit(1)
        }
    }

    // MARK: - Commands

    private func generateOnboardingStoryboard(args: [String]) async {
        let outputPath = args.first
        await OnboardingStoryboardGenerator.shared.generateAndExit(outputPath: outputPath)
    }

    private func generateSettingsStoryboard(args: [String]) async {
        let outputPath = args.first
        await SettingsStoryboardGenerator.shared.generateAndExit(outputPath: outputPath)
    }

    private func captureSettingsScreenshots(args: [String]) async {
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

    private func runDesignAudit() async {
        print("🔍 Running design audit...")

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

        print("📁 Output: \(runDir.path)")

        let report = await DesignAuditor.shared.auditAll()

        print("📊 Grade: \(report.grade) (\(report.overallScore)%)")
        print("   Issues: \(report.totalIssues) total across \(report.screens.count) screens")

        // Generate reports
        DesignAuditor.shared.generateHTMLReport(from: report, to: runDir.appendingPathComponent("report.html"))
        DesignAuditor.shared.generateMarkdownReport(from: report, to: runDir.appendingPathComponent("report.md"))

        print("✅ Reports generated:")
        print("   - report.html")
        print("   - report.md")

        // Capture settings screenshots
        let screenshotsDir = runDir.appendingPathComponent("screenshots")
        print("📸 Capturing settings screenshots...")
        let screenshots = await SettingsStoryboardGenerator.shared.captureAllPages(to: screenshotsDir)
        print("✅ Captured \(screenshots.count) screenshots")

        // Open result
        NSWorkspace.shared.open(runDir.appendingPathComponent("report.html"))
        exit(0)
    }

    private func pullMemo(args: [String]) async {
        guard let uuidString = args.first else {
            print("❌ Usage: --debug=pull-memo <uuid>")
            print("   Example: --debug=pull-memo 25E8709E-CAF7-4612-92F5-730B419A5902")
            exit(1)
        }

        // Parse UUID (handle both hyphenated and compact formats)
        let normalizedUUID: String
        if uuidString.contains("-") {
            normalizedUUID = uuidString.uppercased()
        } else {
            // Convert compact to hyphenated: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX -> XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
            let s = uuidString.uppercased()
            guard s.count == 32 else {
                print("❌ Invalid UUID format: \(uuidString)")
                exit(1)
            }
            let idx = s.startIndex
            normalizedUUID = "\(s[idx..<s.index(idx, offsetBy: 8)])-\(s[s.index(idx, offsetBy: 8)..<s.index(idx, offsetBy: 12)])-\(s[s.index(idx, offsetBy: 12)..<s.index(idx, offsetBy: 16)])-\(s[s.index(idx, offsetBy: 16)..<s.index(idx, offsetBy: 20)])-\(s[s.index(idx, offsetBy: 20)..<s.index(idx, offsetBy: 32)])"
        }

        guard let uuid = UUID(uuidString: normalizedUUID) else {
            print("❌ Invalid UUID: \(uuidString)")
            exit(1)
        }

        print("📥 Pulling memo: \(uuid)")

        // Initialize Core Data
        let context = PersistenceController.shared.container.viewContext

        // Configure TalkieData with context
        TalkieData.shared.configure(with: context)

        // Wait for TalkieData to be ready
        try? await Task.sleep(for: .seconds(1))

        // Sync the specific memo
        await TalkieData.shared.syncMissingMemos(ids: [uuid])

        print("✅ Done")
        exit(0)
    }

    private func triggerEnvironmentCrash() async {
        print("""
        🔴 Environment Crash Test
        =========================

        This reproduces the crash from the crash report where:
        - A view uses @Environment(LiveSettings.self)
        - But LiveSettings is NOT provided via .environment()
        - SwiftUI crashes with: "No Observable object of type X found"

        The crash happens because @Environment(Type.self) for @Observable
        objects has NO default value - it MUST be provided.

        Triggering crash in 2 seconds...
        """)

        // Give time to read the message
        try? await Task.sleep(for: .seconds(2))

        // Trigger the crash
        EnvironmentCrashTestView.triggerImmediateCrash()

        // Keep app running long enough for window to render and crash
        try? await Task.sleep(for: .seconds(5))
        exit(0)
    }

    // MARK: - Help

    private func printHelp() {
        print("""
        Talkie Debug Commands
        =====================

        Usage: Talkie.app/Contents/MacOS/Talkie --debug=<command> [args...]

        Available Commands:

          onboarding-storyboard [output-path]
              Generate a storyboard image of all onboarding screens
              Default: ~/Desktop/onboarding-storyboard-<timestamp>.png

          settings-storyboard [output-path]
              Generate a storyboard image of all settings pages
              Default: ~/Desktop/settings-storyboard-<timestamp>.png

          settings-screenshots [output-dir]
              Capture individual screenshots of each settings page
              Default: ~/Desktop/settings-screenshots-<timestamp>/

          design-audit
              Run design system audit with reports and screenshots
              Output: ~/Desktop/talkie-audit/run-XXX/
                - report.html (interactive report)
                - report.md (markdown report)
                - screenshots/ (all settings pages)

          environment-crash
              Trigger a crash by rendering a view that uses
              @Environment(LiveSettings.self) without providing it.
              This reproduces the crash from the crash report.

          pull-memo <uuid>
              Pull a specific memo from Core Data to GRDB by UUID.
              Useful for testing the intake pipeline.
              Example: --debug=pull-memo 25E8709E-CAF7-4612-92F5-730B419A5902

          help
              Show this help message

        Examples:
          --debug=settings-storyboard
          --debug=settings-screenshots ~/Documents/UI-Review/v1-baseline
          --debug=onboarding-storyboard ~/Documents/onboarding.png

        """)
    }
}
