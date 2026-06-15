//
//  DebugCommandHandler.swift
//  Talkie macOS
//
//  Handles headless debug commands via CLI
//  Usage: Talkie.app/Contents/MacOS/Talkie --debug=<command> [args...]
//

import Foundation
import AppKit
import TalkieKit

@MainActor
class DebugCommandHandler {
    static let shared = DebugCommandHandler()

    private init() {}

    /// Check command line arguments and execute debug command if present
    /// Returns true if a debug command was executed (app should exit)
    func handleCommandLineArguments() async -> Bool {
        TalkieConsole.info("🔍 handleCommandLineArguments START")
        let args = CommandLine.arguments
        TalkieConsole.info("🔍 Got args: \(args.count) items")

        // Look for --debug=<command>
        guard let debugArg = args.first(where: { $0.hasPrefix("--debug=") }) else {
            TalkieConsole.info("🔍 No debug arg found")
            return false
        }
        TalkieConsole.info("🔍 Found debug arg: \(debugArg)")

        let command = String(debugArg.dropFirst("--debug=".count))
        TalkieConsole.info("🔍 Parsing command: \(command)")

        // Get additional arguments (everything after the --debug flag)
        let additionalArgs = args.dropFirst(args.firstIndex(of: debugArg)! + 1)
        TalkieConsole.info("🔍 Additional args: \(Array(additionalArgs))")

        TalkieConsole.info("🐛 Debug command: \(command)")

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

        case "audio-catchup":
            await audioCatchup(args: args)

        case "retranscribe-memo":
            await retranscribeMemo(args: args)

        case "capture-markup-describe":
            await captureMarkupDescribe(args: args)

        case "capture-markup-plan":
            await captureMarkupPlan(args: args)

        case "capture-markup-apply":
            await captureMarkupApply(args: args)

        case "capture-markup-render":
            await captureMarkupRender(args: args)

        case "test-workflow-import":
            testWorkflowImport()

        case "test-skill-file-format":
            testSkillFileFormat()

        case "help":
            printHelp()
            exit(0)

        default:
            TalkieConsole.info("❌ Unknown debug command: \(command)")
            TalkieConsole.info("")
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
            let timestamp = Date().iso8601.replacingOccurrences(of: ":", with: "-")
            outputDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent("settings-screenshots-\(timestamp)")
        }

        TalkieConsole.info("📸 Capturing settings pages to: \(outputDir.path)")
        let results = await SettingsStoryboardGenerator.shared.captureAllPages(to: outputDir)
        TalkieConsole.info("✅ Captured \(results.count) pages")
        exit(0)
    }

    private func runDesignAudit() async {
        TalkieConsole.info("🔍 Running design audit...")

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

        TalkieConsole.info("📁 Output: \(runDir.path)")

        let report = await DesignAuditor.shared.auditAll()

        TalkieConsole.info("📊 Grade: \(report.grade) (\(report.overallScore)%)")
        TalkieConsole.info("   Issues: \(report.totalIssues) total across \(report.screens.count) screens")

        // Generate reports
        DesignAuditor.shared.generateHTMLReport(from: report, to: runDir.appendingPathComponent("report.html"))
        DesignAuditor.shared.generateMarkdownReport(from: report, to: runDir.appendingPathComponent("report.md"))

        TalkieConsole.info("✅ Reports generated:")
        TalkieConsole.info("   - report.html")
        TalkieConsole.info("   - report.md")

        // Capture settings screenshots
        let screenshotsDir = runDir.appendingPathComponent("screenshots")
        TalkieConsole.info("📸 Capturing settings screenshots...")
        let screenshots = await SettingsStoryboardGenerator.shared.captureAllPages(to: screenshotsDir)
        TalkieConsole.info("✅ Captured \(screenshots.count) screenshots")

        // Open result
        NSWorkspace.shared.open(runDir.appendingPathComponent("report.html"))
        exit(0)
    }

    private func pullMemo(args: [String]) async {
        guard let uuidString = args.first else {
            TalkieConsole.info("❌ Usage: --debug=pull-memo <uuid>")
            TalkieConsole.info("   Example: --debug=pull-memo 25E8709E-CAF7-4612-92F5-730B419A5902")
            exit(1)
        }

        guard let uuid = parseUUIDArgument(uuidString) else {
            TalkieConsole.info("❌ Invalid UUID: \(uuidString)")
            exit(1)
        }

        TalkieConsole.info("📥 Looking for memo: \(uuid)")

        // Connect to TalkieSync
        await MainActor.run {
            SyncClient.shared.connect()
        }

        // Wait for connection
        try? await Task.sleep(for: .seconds(2))

        // Trigger bridge sync via TalkieSync
        TalkieConsole.info("🔄 Triggering bridge sync via TalkieSync...")
        do {
            let count = try await SyncClient.shared.runSyncPass()
            TalkieConsole.info("✅ Bridge sync complete: \(count) memos synced")
        } catch {
            TalkieConsole.info("⚠️ Bridge sync failed: \(error.localizedDescription)")
        }

        // Check if memo exists in GRDB
        let repo = LocalRepository()
        if let memo = try? await repo.fetchMemo(id: uuid) {
            TalkieConsole.info("✅ Found: '\(memo.memo.title ?? "Untitled")' (\(Int(memo.memo.duration))s)")
        } else {
            TalkieConsole.info("⚠️ Memo not found in GRDB after sync")
        }

        exit(0)
    }

    private func retranscribeMemo(args: [String]) async {
        guard let uuidString = args.first else {
            TalkieConsole.info("❌ Usage: --debug=retranscribe-memo <uuid> [model-id]")
            TalkieConsole.info("   Example: --debug=retranscribe-memo 25E8709E-CAF7-4612-92F5-730B419A5902 parakeet:v3")
            exit(1)
        }

        guard let uuid = parseUUIDArgument(uuidString) else {
            TalkieConsole.info("❌ Invalid UUID: \(uuidString)")
            exit(1)
        }

        let modelId = args.dropFirst().first ?? "parakeet:v3"

        TalkieConsole.info("🎙️ Retranscribing memo: \(uuid)")
        TalkieConsole.info("   Model: \(modelId)")

        do {
            let transcript = try await RecordingRetranscriptionService.shared.retranscribeMemo(
                id: uuid,
                modelId: modelId
            )
            TalkieConsole.info("✅ Retranscribed successfully (\(transcript.count) chars)")
            TalkieConsole.info("")
            TalkieConsole.info(transcript)
            exit(0)
        } catch {
            TalkieConsole.info("❌ Retranscription failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func audioCatchup(args: [String]) async {
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
        let missingBefore = StorageInventoryService.shared.audioMissingMemos
            .sorted { $0.createdAt > $1.createdAt }
        guard !missingBefore.isEmpty else {
            TalkieConsole.info("✅ No missing audio files detected")
            exit(0)
            return
        }

        let targets = Array(missingBefore.prefix(sampleCount))
        TalkieConsole.info("🎧 Audio catch-up quick test")
        TalkieConsole.info("   Sample size: \(targets.count) memo(s)")
        TalkieConsole.info("   Missing audio before sync: \(missingBefore.count)")
        for memo in targets {
            TalkieConsole.info("   - \(memo.id.uuidString) \(memo.title)")
        }

        do {
            try await SyncClient.shared.runSyncOnce(keepRunning: false)
        } catch {
            TalkieConsole.info("❌ Sync failed: \(error.localizedDescription)")
            exit(1)
            return
        }

        await StorageInventoryService.shared.refresh()
        let missingAfter = StorageInventoryService.shared.audioMissingMemos
        let missingIDsAfter = Set(missingAfter.map(\.id))
        let recovered = targets.filter { !missingIDsAfter.contains($0.id) }

        TalkieConsole.info("   Missing audio after sync: \(missingAfter.count)")
        TalkieConsole.info("   Recovered in sample: \(recovered.count)/\(targets.count)")
        for memo in targets {
            let recoveredLabel = missingIDsAfter.contains(memo.id) ? "still missing" : "recovered"
            TalkieConsole.info("   - \(memo.id.uuidString) \(recoveredLabel)")
        }

        if recovered.count == targets.count {
            TalkieConsole.info("✅ Audio catch-up sample completed")
            exit(0)
        } else {
            TalkieConsole.info("⚠️ Audio catch-up sample incomplete")
            exit(2)
        }
    }

    private func captureMarkupDescribe(args: [String]) async {
        guard let path = args.first else {
            TalkieConsole.info("❌ Usage: --debug=capture-markup-describe <image-path>")
            exit(1)
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            let description = try await CaptureMarkupAgentService.shared.describe(imageURL: url)
            TalkieConsole.info(description)
            exit(0)
        } catch {
            TalkieConsole.info("❌ \(error.localizedDescription)")
            exit(1)
        }
    }

    private func captureMarkupPlan(args: [String]) async {
        guard args.count >= 2 else {
            TalkieConsole.info("❌ Usage: --debug=capture-markup-plan <image-path> <instruction>")
            exit(1)
        }
        let url = URL(fileURLWithPath: (args[0] as NSString).expandingTildeInPath)
        let instruction = args.dropFirst().joined(separator: " ")
        do {
            let plan = try await CaptureMarkupAgentService.shared.plan(
                imageURL: url,
                instruction: instruction
            )
            let data = try JSONEncoder().encode(plan)
            TalkieConsole.info(String(data: data, encoding: .utf8) ?? "{}")
            exit(0)
        } catch {
            TalkieConsole.info("❌ \(error.localizedDescription)")
            exit(1)
        }
    }

    private func captureMarkupApply(args: [String]) async {
        guard args.count >= 2 else {
            TalkieConsole.info("❌ Usage: --debug=capture-markup-apply <image-path> <plan-json-path>")
            exit(1)
        }
        let url = URL(fileURLWithPath: (args[0] as NSString).expandingTildeInPath)
        let planURL = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath)
        do {
            let data = try Data(contentsOf: planURL)
            let plan = try JSONDecoder().decode(CaptureMarkupPlan.self, from: data)
            let document = try CaptureMarkupAgentService.shared.applyPlan(
                imageURL: url,
                plan: plan
            )
            let encoded = try JSONEncoder().encode(document)
            TalkieConsole.info(String(data: encoded, encoding: .utf8) ?? "{}")
            exit(0)
        } catch {
            TalkieConsole.info("❌ \(error.localizedDescription)")
            exit(1)
        }
    }

    private func captureMarkupRender(args: [String]) async {
        guard let path = args.first else {
            TalkieConsole.info("❌ Usage: --debug=capture-markup-render <image-path> [output-path]")
            exit(1)
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let output = args.dropFirst().first.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        }
        do {
            let png = try CaptureMarkupAgentService.shared.renderPNG(imageURL: url)
            if let output {
                try png.write(to: output)
                TalkieConsole.info(output.path)
            } else {
                FileHandle.standardOutput.write(png)
            }
            exit(0)
        } catch {
            TalkieConsole.info("❌ \(error.localizedDescription)")
            exit(1)
        }
    }

    private func parseUUIDArgument(_ uuidString: String) -> UUID? {
        let normalizedUUID: String
        if uuidString.contains("-") {
            normalizedUUID = uuidString.uppercased()
        } else {
            let s = uuidString.uppercased()
            guard s.count == 32 else {
                return nil
            }
            let idx = s.startIndex
            normalizedUUID = "\(s[idx..<s.index(idx, offsetBy: 8)])-\(s[s.index(idx, offsetBy: 8)..<s.index(idx, offsetBy: 12)])-\(s[s.index(idx, offsetBy: 12)..<s.index(idx, offsetBy: 16)])-\(s[s.index(idx, offsetBy: 16)..<s.index(idx, offsetBy: 20)])-\(s[s.index(idx, offsetBy: 20)..<s.index(idx, offsetBy: 32)])"
        }

        return UUID(uuidString: normalizedUUID)
    }

    private func triggerEnvironmentCrash() async {
        TalkieConsole.info("""
        🔴 Environment Crash Test
        =========================

        This reproduces the crash from the crash report where:
        - A view uses @Environment(AgentSettings.self)
        - But AgentSettings is NOT provided via .environment()
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

    private func testWorkflowImport() {
        TalkieConsole.info("")
        ImportPayloadConverterTests.runAll()
        exit(0)
    }

    private func testSkillFileFormat() {
        TalkieConsole.info("")
        SkillFileFormatTests.runAll()
        exit(0)
    }

    private func printHelp() {
        TalkieConsole.info("""
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
              @Environment(AgentSettings.self) without providing it.
              This reproduces the crash from the crash report.

          pull-memo <uuid>
              Pull a specific memo from Core Data to GRDB by UUID.
              Useful for testing the intake pipeline.
              Example: --debug=pull-memo 25E8709E-CAF7-4612-92F5-730B419A5902

          audio-catchup [count|--count=N]
              Run one sync and verify recovery on N missing-audio memos.
              Default count: 2
              Example: --debug=audio-catchup --count=2

          retranscribe-memo <uuid> [model-id]
              Retranscribe a memo from its saved audio without opening the UI.
              Default model: parakeet:v3
              Example: --debug=retranscribe-memo 25E8709E-CAF7-4612-92F5-730B419A5902 parakeet:v3

          test-workflow-import
              Run ImportPayloadConverter tests to verify URL workflow
              import converts to core WorkflowDefinition correctly.

          test-skill-file-format
              Run parser/serializer tests for bundled .skill.md files.

          help
              Show this help message

        Examples:
          --debug=settings-storyboard
          --debug=settings-screenshots ~/Documents/UI-Review/v1-baseline
          --debug=onboarding-storyboard ~/Documents/onboarding.png

        """)
    }
}
