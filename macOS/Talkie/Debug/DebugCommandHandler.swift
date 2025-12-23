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
        let args = CommandLine.arguments

        // Look for --debug=<command>
        guard let debugArg = args.first(where: { $0.hasPrefix("--debug=") }) else {
            return false
        }

        let command = String(debugArg.dropFirst("--debug=".count))

        // Get additional arguments (everything after the --debug flag)
        let additionalArgs = args.dropFirst(args.firstIndex(of: debugArg)! + 1)

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

        let report = DesignAuditor.shared.auditAll()

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

          help
              Show this help message

        Examples:
          --debug=settings-storyboard
          --debug=settings-screenshots ~/Documents/UI-Review/v1-baseline
          --debug=onboarding-storyboard ~/Documents/onboarding.png

        """)
    }
}
