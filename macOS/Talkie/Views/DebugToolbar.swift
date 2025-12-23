//
//  DebugToolbar.swift
//  Talkie macOS
//
//  Debug toolbar overlay - available in DEBUG builds
//  Provides quick access to dev tools and convenience functions
//
//  Uses DebugKit package for the core overlay, with app-specific content below.
//

import SwiftUI
import CoreData
import AVFoundation
import UserNotifications
import DebugKit
import TalkieKit

#if DEBUG

// MARK: - Talkie Debug Toolbar Wrapper

/// Wrapper around DebugKit's DebugToolbar with Talkie-specific content
struct TalkieDebugToolbar<CustomContent: View>: View {
    let debugInfo: () -> [String: String]
    let customContent: CustomContent

    @State private var showingConsole = false

    /// Initialize with custom content and optional debug info (matches original API)
    init(
        @ViewBuilder content: @escaping () -> CustomContent,
        debugInfo: @escaping () -> [String: String] = { [:] }
    ) {
        self.customContent = content()
        self.debugInfo = debugInfo
    }

    var body: some View {
        DebugToolbar(
            title: "DEV",
            icon: "ant.fill",
            sections: buildSections(),
            actions: [
                DebugAction("View Console", icon: "doc.text.magnifyingglass") {
                    showingConsole = true
                }
            ],
            onCopy: { buildCopyText() }
        ) {
            customContent
        }
        .sheet(isPresented: $showingConsole) {
            DebugConsoleSheet()
        }
    }

    private func buildSections() -> [DebugKit.DebugSection] {
        let info = debugInfo()
        guard !info.isEmpty else { return [] }

        let rows = info.keys.sorted().map { key in
            (key, info[key] ?? "-")
        }
        return [DebugKit.DebugSection("STATE", rows)]
    }

    private func buildCopyText() -> String {
        var lines: [String] = []

        // App info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        lines.append("Talkie macOS \(appVersion) (\(buildNumber))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")

        // Context state
        let info = debugInfo()
        if !info.isEmpty {
            lines.append("State:")
            for key in info.keys.sorted() {
                lines.append("  \(key): \(info[key] ?? "-")")
            }
            lines.append("")
        }

        // Recent events
        let recentEvents = Array(SystemEventManager.shared.events.prefix(5))
        if !recentEvents.isEmpty {
            lines.append("Recent Events:")
            for event in recentEvents {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                let time = formatter.string(from: event.timestamp)
                lines.append("  [\(time)] \(event.type.rawValue): \(event.message)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

extension TalkieDebugToolbar where CustomContent == EmptyView {
    /// Convenience init with no context content (system-only)
    init() {
        self.init(content: { EmptyView() }, debugInfo: { [:] })
    }
}

// MARK: - Legacy Alias (for compatibility)
typealias DebugToolbarOverlay<Content: View> = TalkieDebugToolbar<Content>

// MARK: - Debug Console Sheet

struct DebugConsoleSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("System Logs")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Theme.current.surfaceBase)

            Divider()

            // Logs view
            SystemLogsView()
        }
        .frame(width: 700, height: 500)
    }
}

// MARK: - Reusable Debug Components

/// Section header for debug toolbar content
struct DebugSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            content()
        }
    }
}

/// Tappable debug action button
struct DebugActionButton: View {
    let icon: String
    let label: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(destructive ? .red : .accentColor)
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(destructive ? .red : .primary)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Theme.current.surface2)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

/// Table-style state display for debug toolbar
struct DebugStateTable: View {
    let info: [String: String]
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(info.keys.sorted().enumerated()), id: \.element) { index, key in
                HStack {
                    Text(key)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(info[key] ?? "-")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(index % 2 == 0 ? Theme.current.surfaceAlternate : Color.clear)
            }
        }
        .background(Theme.current.surface1)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Context-Specific Content

/// Debug content for the main memo list view
/// Follows iOS pattern: view-specific actions → convenience → platform-wide utils
struct ListViewDebugContent: View {
    @Environment(CloudKitSyncManager.self) private var syncManager
    @State private var showConfirmation = false
    @State private var confirmationAction: (() -> Void)?
    @State private var confirmationMessage = ""

    var body: some View {
        VStack(spacing: 10) {
            // 1. Page-specific convenience actions
            DebugSection(title: "SYNC") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "arrow.triangle.2.circlepath", label: "Force Sync") {
                        syncManager.syncNow()
                    }
                    DebugActionButton(icon: "arrow.clockwise", label: "Full Sync") {
                        syncManager.forceFullSync()
                    }
                }
            }

            // 2. Auto-run convenience
            DebugSection(title: "AUTO-RUN") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "checkmark.circle", label: "Mark All Processed") {
                        markAllMemosAsProcessed()
                    }
                    DebugActionButton(icon: "arrow.counterclockwise", label: "Reset Migration") {
                        confirmationMessage = "Reset auto-run migration? All memos will be re-processed."
                        confirmationAction = { resetAutoRunMigration() }
                        showConfirmation = true
                    }
                }
            }

            // 3. Utilities
            DebugSection(title: "UTILITIES") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "waveform.slash", label: "Reset Transcription") {
                        resetTranscriptionState()
                    }
                    DebugActionButton(icon: "bell.badge", label: "Test Notification") {
                        sendTestNotification()
                    }
                    DebugActionButton(icon: "sparkles", label: "Test Interstitial") {
                        testInterstitial()
                    }
                }
            }

            // 4. Design Audit
            DebugSection(title: "DESIGN") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "checkmark.seal", label: "Run Audit") {
                        runDesignAudit()
                    }
                    DebugActionButton(icon: "camera.viewfinder", label: "Capture Settings") {
                        captureSettingsScreenshots()
                    }
                }
            }

            // 5. Audio Testing
            AudioPaddingTestDebugContent()

            // 5. Danger zone (platform-wide destructive utils)
            DebugSection(title: "RESET") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "arrow.counterclockwise", label: "Onboarding", destructive: true) {
                        confirmationMessage = "Reset onboarding state?"
                        confirmationAction = { resetOnboarding() }
                        showConfirmation = true
                    }
                    DebugActionButton(icon: "trash", label: "UserDefaults", destructive: true) {
                        confirmationMessage = "Clear all UserDefaults? This will reset all app settings."
                        confirmationAction = { clearUserDefaults() }
                        showConfirmation = true
                    }
                }
            }
        }
        .alert("Confirm Action", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Confirm", role: .destructive) {
                confirmationAction?()
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - Actions

    private func resetTranscriptionState() {
        // Reset service states
        WhisperService.shared.resetTranscriptionState()
        ParakeetService.shared.resetTranscriptionState()

        // Reset any memos stuck in transcribing state
        let context = PersistenceController.shared.container.viewContext
        let request = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(format: "isTranscribing == YES")

        do {
            let stuckMemos = try context.fetch(request)
            if stuckMemos.count > 0 {
                for memo in stuckMemos {
                    memo.isTranscribing = false
                }
                try context.save()
                SystemEventManager.shared.logSync(.system, "Reset transcription state", detail: "Services + \(stuckMemos.count) stuck memo(s)")
            } else {
                SystemEventManager.shared.logSync(.system, "Transcription state reset", detail: "WhisperKit + Parakeet (no stuck memos)")
            }
        } catch {
            SystemEventManager.shared.logSync(.error, "Failed to reset memo states", detail: error.localizedDescription)
        }
    }

    private func markAllMemosAsProcessed() {
        let context = PersistenceController.shared.container.viewContext
        let request = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(format: "autoProcessed == NO OR autoProcessed == nil")

        do {
            let memos = try context.fetch(request)
            for memo in memos {
                memo.autoProcessed = true
            }
            try context.save()
            SystemEventManager.shared.logSync(.system, "Marked all memos as processed", detail: "\(memos.count) memo(s)")
        } catch {
            SystemEventManager.shared.logSync(.error, "Failed to mark memos", detail: error.localizedDescription)
        }
    }

    private func resetAutoRunMigration() {
        UserDefaults.standard.removeObject(forKey: "autoRunMigrationCompleted")
        SystemEventManager.shared.logSync(.system, "Auto-run migration reset", detail: "Will re-run on next sync")
    }

    private func resetOnboarding() {
        OnboardingManager.shared.resetOnboarding()
        SystemEventManager.shared.logSync(.system, "Onboarding reset - will show on next launch")
    }

    private func clearUserDefaults() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
            SystemEventManager.shared.logSync(.system, "UserDefaults cleared")
        }
    }

    private func sendTestNotification() {
        // Send iOS push notification via CloudKit
        let context = PersistenceController.shared.container.viewContext

        let pushNotification = PushNotification(context: context)
        pushNotification.id = UUID()
        pushNotification.title = "Extracted 2 Intents"
        pushNotification.body = "• summarize 85%\n• remind (tomorrow) 70%"
        pushNotification.createdAt = Date()
        pushNotification.soundEnabled = true
        pushNotification.isRead = false
        pushNotification.workflowName = "Test Notification"

        do {
            try context.save()
            SystemEventManager.shared.logSync(.system, "iOS push notification queued")
        } catch {
            SystemEventManager.shared.logSync(.error, "Failed to queue notification", detail: error.localizedDescription)
        }
    }

    private func testInterstitial() {
        NSLog("[DEBUG] Testing interstitial panel directly")
        SystemEventManager.shared.logSync(.system, "Testing interstitial panel")

        // Test with a fake utterance ID - the panel should show an error if not found
        // or work if there's a matching record in the Live database
        Task { @MainActor in
            // TODO: Update this to work with new Utterance model
            NSLog("[DEBUG] Interstitial test temporarily disabled")
            SystemEventManager.shared.logSync(.system, "Interstitial test", detail: "Temporarily disabled")
            // InterstitialManager.shared.show(utteranceId: 999)
        }
    }

    // MARK: - Design Audit

    private func runDesignAudit() {
        NSLog("[DEBUG] Running design audit (code only, no screenshots)...")

        // Run on background task
        Task.detached {
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

            NSLog("[DEBUG] Running audit (run-\(String(format: "%03d", nextNum)))...")
            let report = await DesignAuditor.shared.auditAll()

            NSLog("[DEBUG] Audit results: Grade \(report.grade) (\(report.overallScore)%)")

            // Generate reports
            await MainActor.run {
                DesignAuditor.shared.generateHTMLReport(from: report, to: runDir.appendingPathComponent("report.html"))
                DesignAuditor.shared.generateMarkdownReport(from: report, to: runDir.appendingPathComponent("report.md"))
            }

            // Generate index
            await MainActor.run {
                self.generateAuditIndexSync(at: baseDir)
            }

            // Open result on main thread
            await MainActor.run {
                NSWorkspace.shared.open(runDir.appendingPathComponent("report.html"))
            }
        }
    }

    /// Synchronous version of generateAuditIndex - NO Swift Concurrency
    private func generateAuditIndexSync(at baseDir: URL) {
        let fm = FileManager.default
        let existing = (try? fm.contentsOfDirectory(atPath: baseDir.path)) ?? []
        let runs = existing.filter { $0.hasPrefix("run-") }.sorted().reversed()

        var rows = ""
        for run in runs {
            let runDir = baseDir.appendingPathComponent(run)
            let mdPath = runDir.appendingPathComponent("report.md")

            var grade = "?"
            var score = "?"

            if let content = try? String(contentsOf: mdPath, encoding: .utf8) {
                if let gradeMatch = content.range(of: #"Grade:\s*([A-F])"#, options: .regularExpression) {
                    grade = String(content[gradeMatch]).replacingOccurrences(of: "Grade: ", with: "")
                }
                if let scoreMatch = content.range(of: #"\((\d+)%\)"#, options: .regularExpression) {
                    score = String(content[scoreMatch]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: "%)", with: "")
                }
            }

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
            </style>
        </head>
        <body>
            <h1>Talkie Design Audits</h1>
            <p class="subtitle">Click any row to view the report.</p>
            <table>
                <tr><th>Run</th><th>Date</th><th>Grade</th><th>Score</th><th>Report</th></tr>
                \(rows)
            </table>
        </body>
        </html>
        """

        try? html.write(to: baseDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    private func captureSettingsScreenshots() {
        NSLog("[DEBUG] Capturing settings screenshots...")

        // Use pure GCD to avoid Swift Concurrency crash in objc_release
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let outputDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("settings-screenshots")
                try? FileManager.default.removeItem(at: outputDir)
                try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

                // Run the capture on main thread synchronously
                var resultCount = 0
                let semaphore = DispatchSemaphore(value: 0)

                DispatchQueue.main.async {
                    // Create a simple capture using window snapshots instead of navigation
                    let results = Self.captureCurrentSettingsWindow(to: outputDir)
                    resultCount = results
                    semaphore.signal()
                }

                semaphore.wait()

                NSLog("[DEBUG] Captured \(resultCount) screenshots to \(outputDir.path)")

                // Open folder on main thread
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(outputDir)
                }
            }
        }
    }

    /// Capture current settings window without navigation (avoids Swift Concurrency crash)
    private static func captureCurrentSettingsWindow(to outputDir: URL) -> Int {
        // Get all windows
        guard let windows = NSApplication.shared.windows as? [NSWindow] else { return 0 }

        var captured = 0
        for window in windows {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }

            view.cacheDisplay(in: view.bounds, to: bitmap)

            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(bitmap)

            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else { continue }

            let filename = "window-\(captured).png"
            let path = outputDir.appendingPathComponent(filename)

            do {
                try pngData.write(to: path)
                captured += 1
                NSLog("[DEBUG] Captured window to \(filename)")
            } catch {
                NSLog("[DEBUG] Failed to write \(filename): \(error)")
            }
        }

        return captured
    }

    private func generateAuditIndex(at baseDir: URL) async {
        let fm = FileManager.default
        let existing = (try? fm.contentsOfDirectory(atPath: baseDir.path)) ?? []
        let runs = existing.filter { $0.hasPrefix("run-") }.sorted().reversed()

        var rows = ""
        for run in runs {
            let runDir = baseDir.appendingPathComponent(run)
            let mdPath = runDir.appendingPathComponent("report.md")

            var grade = "?"
            var score = "?"

            if let content = try? String(contentsOf: mdPath, encoding: .utf8) {
                if let gradeMatch = content.range(of: #"Grade:\s*([A-F])"#, options: .regularExpression) {
                    grade = String(content[gradeMatch]).replacingOccurrences(of: "Grade: ", with: "")
                }
                if let scoreMatch = content.range(of: #"\((\d+)%\)"#, options: .regularExpression) {
                    score = String(content[scoreMatch]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: "%)", with: "")
                }
            }

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
            <p class="subtitle">Auto-refreshes every 5 seconds. Click "Run Audit" in Debug toolbar to add new audit.</p>
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

/// Alias for backwards compatibility
typealias MainDebugContent = ListViewDebugContent

// MARK: - Engine Processes Monitor

struct RunningProcess: Identifiable {
    let id: Int32
    let name: String
    let path: String
    let pid: Int32
}

struct EngineProcessesDebugContent: View {
    @State private var processes: [RunningProcess] = []
    @State private var isRestarting = false

    private var currentEnv: TalkieEnvironment {
        TalkieEnvironment.current
    }

    var body: some View {
        DebugSection(title: "RUNNING PROCESSES") {
            VStack(spacing: 4) {
                // Environment badge
                HStack {
                    Text("Environment:")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text(currentEnv.badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(envColor)
                        .cornerRadius(3)

                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

                HStack {
                    Text("Found \(processes.count) process(es)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: refreshProcesses) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

                if processes.isEmpty {
                    Text("No TalkieEngine or TalkieLive processes running")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(processes) { process in
                        processRow(process)
                    }
                }

                // Clean Slate button
                Divider()
                    .padding(.vertical, 4)

                Button(action: cleanSlate) {
                    HStack(spacing: 6) {
                        if isRestarting {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .medium))
                        }
                        Text(isRestarting ? "Restarting..." : "Clean Slate")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(envColor)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isRestarting)
                .help("Kill all helpers and restart \(currentEnv.displayName) environment")
            }
        }
        .onAppear {
            refreshProcesses()
        }
    }

    private var envColor: Color {
        switch currentEnv {
        case .production: return .green   // Green = live/stable
        case .staging: return .orange     // Orange = testing/caution
        case .dev: return .purple        // Purple = development
        }
    }

    private func processRow(_ process: RunningProcess) -> some View {
        HStack(spacing: 6) {
            Image(systemName: process.name.contains("TalkieEngine") ? "cpu" : "waveform.circle")
                .font(.system(size: 10))
                .foregroundColor(process.name.contains("TalkieEngine") ? .blue : .green)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)

                Text(verbatim: "PID: \(String(format: "%d", process.pid))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                killProcess(process)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Kill process \(process.pid)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.current.surface2)
        .cornerRadius(4)
    }

    private func refreshProcesses() {
        Task {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-ax", "-o", "pid,comm"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: "\n")
                    var foundProcesses: [RunningProcess] = []

                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { continue }

                        let components = trimmed.components(separatedBy: .whitespaces)
                        guard components.count >= 2 else { continue }

                        guard let pid = Int32(components[0]) else { continue }
                        let comm = components[1]

                        // Check if it's TalkieEngine or TalkieLive
                        if comm.contains("TalkieEngine") || comm.contains("TalkieLive") {
                            foundProcesses.append(RunningProcess(
                                id: pid,
                                name: comm,
                                path: comm,
                                pid: pid
                            ))
                        }
                    }

                    await MainActor.run {
                        self.processes = foundProcesses.sorted { $0.name < $1.name }
                    }
                }
            } catch {
                // Silent fail - process enumeration is non-critical
            }
        }
    }

    private func killProcess(_ process: RunningProcess) {
        Task {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/kill")
            task.arguments = ["-9", "\(process.pid)"]

            do {
                try task.run()
                task.waitUntilExit()

                SystemEventManager.shared.logSync(.system, "Killed process", detail: "\(process.name) (PID: \(process.pid))")

                // Refresh after a short delay
                try? await Task.sleep(for: .milliseconds(500))
                refreshProcesses()
            } catch {
                SystemEventManager.shared.logSync(.error, "Failed to kill process", detail: "\(process.pid): \(error.localizedDescription)")
            }
        }
    }

    private func cleanSlate() {
        isRestarting = true

        Task { @MainActor in
            // 1. Kill ALL TalkieEngine and TalkieLive processes (any environment)
            SystemEventManager.shared.logSync(.system, "Clean Slate", detail: "Killing all helper processes")
            for process in processes {
                killProcess(process)
            }

            // 2. Wait for processes to die
            try? await Task.sleep(for: .seconds(1))

            // 3. Refresh to confirm they're dead
            refreshProcesses()

            // 4. Restart only the current environment's helpers
            SystemEventManager.shared.logSync(.system, "Clean Slate", detail: "Restarting \(currentEnv.displayName) helpers")

            // Launch Engine for current environment
            AppLauncher.shared.launchEngine()

            // Launch Live for current environment
            AppLauncher.shared.launchLive()

            // 5. Wait a bit then refresh to show new processes
            try? await Task.sleep(for: .seconds(2))
            refreshProcesses()

            isRestarting = false
            SystemEventManager.shared.logSync(.system, "Clean Slate Complete", detail: "\(currentEnv.displayName) helpers restarted")
        }
    }
}

/// Debug content for the memo detail view
/// Follows iOS pattern: view-specific actions → convenience → platform-wide utils
struct DetailViewDebugContent: View {
    let memo: VoiceMemo
    @State private var showingInspector = false

    var body: some View {
        VStack(spacing: 10) {
            // 1. Page-specific actions (memo operations)
            DebugSection(title: "MEMO") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "bolt.circle", label: "Re-run Auto-Run") {
                        Task {
                            let context = PersistenceController.shared.container.viewContext
                            await AutoRunProcessor.shared.reprocessMemo(memo, context: context)
                        }
                    }
                    DebugActionButton(icon: "arrow.counterclockwise", label: "Reset autoProcessed") {
                        memo.autoProcessed = false
                        try? memo.managedObjectContext?.save()
                        SystemEventManager.shared.logSync(.system, "Reset autoProcessed", detail: memo.title ?? "Untitled")
                    }
                }
            }

            // 2. Data inspection
            DebugSection(title: "INSPECT") {
                DebugActionButton(icon: "tablecells", label: "VoiceMemo Data") {
                    showingInspector = true
                }
            }
        }
        .sheet(isPresented: $showingInspector) {
            ManagedObjectInspector(object: memo)
        }
    }
}

/// Alias for backwards compatibility
typealias MemoDetailDebugContent = DetailViewDebugContent

// MARK: - Data Inspector

/// Generic data inspector for any NSManagedObject
struct ManagedObjectInspector: View {
    @ObservedObject var object: NSManagedObject
    @Environment(\.dismiss) private var dismiss
    private let settings = SettingsManager.shared
    @State private var showCopied = false
    @State private var expandedRelationship: String? = nil

    private var entityName: String {
        object.entity.name ?? "Unknown"
    }

    private var attributes: [(name: String, value: String, type: String)] {
        let entity = object.entity
        return entity.attributesByName
            .sorted { $0.key < $1.key }
            .map { (name, attr) in
                let value = formatValue(object.value(forKey: name), type: attr.attributeType)
                return (name: name, value: value, type: attr.attributeTypeName)
            }
    }

    private var relationships: [(name: String, count: Int, objects: [NSManagedObject])] {
        let entity = object.entity
        return entity.relationshipsByName
            .sorted { $0.key < $1.key }
            .compactMap { (name, rel) in
                if rel.isToMany {
                    if let set = object.value(forKey: name) as? NSSet {
                        let objects = set.allObjects as? [NSManagedObject] ?? []
                        return (name: name, count: objects.count, objects: objects)
                    }
                    return (name: name, count: 0, objects: [])
                } else {
                    if let related = object.value(forKey: name) as? NSManagedObject {
                        return (name: name, count: 1, objects: [related])
                    }
                    return (name: name, count: 0, objects: [])
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(entityName)
                    .font(.headline)

                Spacer()

                Button(action: copyAllData) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.clipboard")
                        if showCopied {
                            Text("Copied")
                                .font(.system(size: 12))
                        }
                    }
                }

                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Theme.current.surfaceBase)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Object info
                    inspectorSection("OBJECT") {
                        inspectorRow("Entity", entityName)
                        inspectorRow("Object ID", object.objectID.uriRepresentation().lastPathComponent)
                    }

                    // Attributes
                    inspectorSection("ATTRIBUTES (\(attributes.count))") {
                        ForEach(attributes, id: \.name) { attr in
                            inspectorRow(attr.name, attr.value, typeHint: attr.type)
                        }
                    }

                    // Relationships
                    if !relationships.isEmpty {
                        inspectorSection("RELATIONSHIPS (\(relationships.count))") {
                            ForEach(relationships, id: \.name) { rel in
                                relationshipRow(rel.name, rel.count, rel.objects)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }

    private func inspectorSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                content()
            }
            .background(Theme.current.surface2)
            .cornerRadius(6)
        }
    }

    private func inspectorRow(_ label: String, _ value: String, typeHint: String? = nil) -> some View {
        HStack(alignment: .top) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                if let type = typeHint {
                    Text(type)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 140, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(value == "nil" ? .gray : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func relationshipRow(_ name: String, _ count: Int, _ objects: [NSManagedObject]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation {
                    if expandedRelationship == name {
                        expandedRelationship = nil
                    } else {
                        expandedRelationship = name
                    }
                }
            }) {
                HStack {
                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(count == 0 ? .gray : .primary)

                    Image(systemName: expandedRelationship == name ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if expandedRelationship == name && !objects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(objects, id: \.objectID) { obj in
                        relatedObjectRow(obj)
                    }
                }
                .padding(.leading, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private func relatedObjectRow(_ object: NSManagedObject) -> some View {
        HStack {
            Text(object.entity.name ?? "?")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.accentColor)

            Text(displayName(for: object))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Theme.current.surface2)
        .cornerRadius(4)
    }

    private func displayName(for object: NSManagedObject) -> String {
        let entity = object.entity
        let attributeNames = Set(entity.attributesByName.keys)

        if attributeNames.contains("title"),
           let title = object.value(forKey: "title") as? String,
           !title.isEmpty {
            return title
        }
        if attributeNames.contains("name"),
           let name = object.value(forKey: "name") as? String,
           !name.isEmpty {
            return name
        }
        if attributeNames.contains("id"),
           let id = object.value(forKey: "id") as? UUID {
            return String(id.uuidString.prefix(8))
        }
        return object.objectID.uriRepresentation().lastPathComponent
    }

    private func formatValue(_ value: Any?, type: NSAttributeType) -> String {
        guard let value = value else { return "nil" }

        switch type {
        case .dateAttributeType:
            if let date = value as? Date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return formatter.string(from: date)
            }
        case .binaryDataAttributeType:
            if let data = value as? Data {
                return "\(data.count) bytes"
            }
        case .UUIDAttributeType:
            if let uuid = value as? UUID {
                return uuid.uuidString
            }
        case .booleanAttributeType:
            if let bool = value as? Bool {
                return bool ? "true" : "false"
            }
        case .doubleAttributeType, .floatAttributeType:
            if let num = value as? Double {
                return String(format: "%.2f", num)
            }
        default:
            break
        }

        let stringValue = String(describing: value)
        // Truncate very long values
        if stringValue.count > 200 {
            return String(stringValue.prefix(200)) + "..."
        }
        return stringValue
    }

    private func copyAllData() {
        var lines: [String] = []
        lines.append("=== \(entityName.uppercased()) ===")
        lines.append("Object ID: \(object.objectID.uriRepresentation().lastPathComponent)")
        lines.append("")
        lines.append("ATTRIBUTES")
        for attr in attributes {
            lines.append("  \(attr.name): \(attr.value)")
        }
        lines.append("")
        lines.append("RELATIONSHIPS")
        for rel in relationships {
            lines.append("  \(rel.name): \(rel.count) object(s)")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)

        withAnimation {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

extension NSAttributeDescription {
    var attributeTypeName: String {
        switch attributeType {
        case .undefinedAttributeType: return "undefined"
        case .integer16AttributeType: return "Int16"
        case .integer32AttributeType: return "Int32"
        case .integer64AttributeType: return "Int64"
        case .decimalAttributeType: return "Decimal"
        case .doubleAttributeType: return "Double"
        case .floatAttributeType: return "Float"
        case .stringAttributeType: return "String"
        case .booleanAttributeType: return "Bool"
        case .dateAttributeType: return "Date"
        case .binaryDataAttributeType: return "Data"
        case .UUIDAttributeType: return "UUID"
        case .URIAttributeType: return "URI"
        case .transformableAttributeType: return "Transformable"
        case .objectIDAttributeType: return "ObjectID"
        case .compositeAttributeType: return "Composite"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Audio Padding Test Harness

/// Padding strategies for A/B testing
enum AudioPaddingStrategy: String, CaseIterable, Identifiable {
    case exponentialFade3 = "Exp Fade (-3)"
    case exponentialFade5 = "Exp Fade (-5)"
    case exponentialFade7 = "Exp Fade (-7)"
    case exponentialFade10 = "Exp Fade (-10)"
    case linearFade = "Linear Fade"
    case duplication = "Duplication"
    case silenceWithSpikes = "Silence + Spikes"
    case pureSilence = "Pure Silence"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .exponentialFade3:
            return "Exponential fade with decay rate -3.0"
        case .exponentialFade5:
            return "Exponential fade with decay rate -5.0 (current default)"
        case .exponentialFade7:
            return "Exponential fade with decay rate -7.0"
        case .exponentialFade10:
            return "Exponential fade with decay rate -10.0 (rapid)"
        case .linearFade:
            return "Linear fade from 100% to 0% amplitude"
        case .duplication:
            return "Duplicate last 300ms (old approach)"
        case .silenceWithSpikes:
            return "Silence with periodic impulse spikes every 50ms"
        case .pureSilence:
            return "Pure silence (zeros)"
        }
    }

    /// Apply this padding strategy to the given samples
    func apply(to samples: [Float], duration: Int = 4800) -> [Float] {
        let padSource = min(duration, samples.count)
        let tailSegment = Array(samples.suffix(padSource))

        switch self {
        case .exponentialFade3:
            return applyExponentialFade(tailSegment, rate: -3.0)
        case .exponentialFade5:
            return applyExponentialFade(tailSegment, rate: -5.0)
        case .exponentialFade7:
            return applyExponentialFade(tailSegment, rate: -7.0)
        case .exponentialFade10:
            return applyExponentialFade(tailSegment, rate: -10.0)
        case .linearFade:
            return applyLinearFade(tailSegment)
        case .duplication:
            return tailSegment // Just duplicate
        case .silenceWithSpikes:
            return applySilenceWithSpikes(duration)
        case .pureSilence:
            return Array(repeating: 0.0, count: duration)
        }
    }

    private func applyExponentialFade(_ samples: [Float], rate: Float) -> [Float] {
        return samples.enumerated().map { index, sample in
            let progress = Float(index) / Float(samples.count)
            let fadeMultiplier = exp(rate * progress)
            return sample * fadeMultiplier
        }
    }

    private func applyLinearFade(_ samples: [Float]) -> [Float] {
        return samples.enumerated().map { index, sample in
            let progress = Float(index) / Float(samples.count)
            let fadeMultiplier = 1.0 - progress
            return sample * fadeMultiplier
        }
    }

    private func applySilenceWithSpikes(_ duration: Int) -> [Float] {
        var result = Array(repeating: Float(0.0), count: duration)
        // Add small impulse spikes every 50ms (800 samples at 16kHz)
        let spikeInterval = 800
        let spikeAmplitude: Float = 0.01 // Small spike
        for i in stride(from: 0, to: duration, by: spikeInterval) {
            if i < duration {
                result[i] = spikeAmplitude
            }
        }
        return result
    }
}

/// Test result for a single padding strategy
struct PaddingTestResult: Identifiable {
    let id = UUID()
    let strategy: AudioPaddingStrategy
    var transcript: String = ""
    var isRunning: Bool = false
    var error: String? = nil
    var duration: TimeInterval = 0
}

/// A/B test view for comparing padding strategies
struct AudioPaddingTestView: View {
    @State private var selectedAudioPath: String = ""
    @State private var testResults: [PaddingTestResult] = []
    @State private var isRunningTests = false
    @Environment(\.dismiss) private var dismiss
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Audio Padding A/B Test")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Theme.current.surfaceBase)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Audio file selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TEST AUDIO FILE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button("Select Audio File...") {
                                selectAudioFile()
                            }
                            .buttonStyle(.bordered)

                            Button("Use JFK Sample") {
                                selectedAudioPath = "/Users/arach/dev/talkie/build/TalkieEngine/SourcePackages/checkouts/WhisperKit/Tests/WhisperKitTests/Resources/jfk.wav"
                            }
                            .buttonStyle(.bordered)

                            Button("Use Last Recording") {
                                selectLastRecording()
                            }
                            .buttonStyle(.bordered)
                        }

                        if !selectedAudioPath.isEmpty {
                            Text(selectedAudioPath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding()
                    .background(Theme.current.surface2)
                    .cornerRadius(8)

                    // Test controls
                    HStack(spacing: 8) {
                        Button(action: runAllTests) {
                            HStack {
                                if isRunningTests {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(isRunningTests ? "Running..." : "Run All Tests")
                            }
                        }
                        .disabled(selectedAudioPath.isEmpty || isRunningTests)
                        .buttonStyle(.borderedProminent)

                        Button("Clear Results") {
                            testResults.removeAll()
                        }
                        .disabled(testResults.isEmpty)
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)

                    // Results
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TEST RESULTS")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            ForEach(testResults) { result in
                                resultCard(result)
                            }
                        }
                    }

                    // Strategy reference
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PADDING STRATEGIES")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)

                        ForEach(AudioPaddingStrategy.allCases) { strategy in
                            HStack(alignment: .top, spacing: 8) {
                                Text(strategy.rawValue)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 120, alignment: .leading)

                                Text(strategy.description)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Theme.current.surface2)
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .frame(width: 750, height: 650)
        .onAppear {
            // Default to JFK sample
            selectedAudioPath = "/Users/arach/dev/talkie/build/TalkieEngine/SourcePackages/checkouts/WhisperKit/Tests/WhisperKitTests/Resources/jfk.wav"
        }
    }

    private func resultCard(_ result: PaddingTestResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.strategy.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)

                Spacer()

                if result.isRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if result.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                } else {
                    Text(String(format: "%.2fs", result.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if let error = result.error {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            } else if !result.transcript.isEmpty {
                Text(result.transcript)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Theme.current.surface1)
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Theme.current.surface2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(result.isRunning ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func selectAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedAudioPath = url.path
            }
        }
    }

    private func selectLastRecording() {
        let context = PersistenceController.shared.container.viewContext
        let request = VoiceMemo.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)]
        request.fetchLimit = 1

        do {
            if let lastMemo = try context.fetch(request).first,
               let audioPath = lastMemo.fileURL {
                selectedAudioPath = audioPath
            }
        } catch {
            print("Failed to fetch last recording: \(error)")
        }
    }

    private func runAllTests() {
        guard !selectedAudioPath.isEmpty else { return }

        isRunningTests = true
        testResults = AudioPaddingStrategy.allCases.map { strategy in
            PaddingTestResult(strategy: strategy, isRunning: false)
        }

        Task {
            for index in testResults.indices {
                await runTest(at: index)
            }
            await MainActor.run {
                isRunningTests = false
            }
        }
    }

    private func runTest(at index: Int) async {
        await MainActor.run {
            testResults[index].isRunning = true
        }

        let strategy = testResults[index].strategy
        let startTime = Date()

        do {
            // Load audio
            let audioURL = URL(fileURLWithPath: selectedAudioPath)
            var samples = try await loadAudioSamples(from: audioURL)

            // Apply padding strategy
            let padding = strategy.apply(to: samples)
            samples.append(contentsOf: padding)

            // Transcribe using Parakeet
            let transcript = try await transcribeWithParakeet(samples: samples)

            let duration = Date().timeIntervalSince(startTime)

            await MainActor.run {
                testResults[index].transcript = transcript
                testResults[index].duration = duration
                testResults[index].isRunning = false
            }
        } catch {
            await MainActor.run {
                testResults[index].error = error.localizedDescription
                testResults[index].isRunning = false
            }
        }
    }

    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "AudioPaddingTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat)!

        var conversionError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            do {
                let tempBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: inNumPackets)!
                try file.read(into: tempBuffer)
                outStatus.pointee = .haveData
                return tempBuffer
            } catch {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        converter.convert(to: buffer, error: &conversionError, withInputFrom: inputBlock)

        if let error = conversionError {
            throw error
        }

        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioPaddingTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get channel data"])
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }

    private func transcribeWithParakeet(samples: [Float]) async throws -> String {
        // Write samples to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).wav")
        try writeSamplesToWav(samples: samples, url: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Load audio data and transcribe using ParakeetService
        let audioData = try Data(contentsOf: tempURL)
        let transcript = try await ParakeetService.shared.transcribe(audioData: audioData)
        return transcript
    }

    private func writeSamplesToWav(samples: [Float], url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity

        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

/// Debug toolbar button to launch the A/B test view
struct AudioPaddingTestDebugContent: View {
    @State private var showTestView = false

    var body: some View {
        DebugSection(title: "AUDIO TESTING") {
            DebugActionButton(icon: "waveform.badge.magnifyingglass", label: "Padding A/B Test") {
                showTestView = true
            }
        }
        .sheet(isPresented: $showTestView) {
            AudioPaddingTestView()
        }
    }
}

#endif
