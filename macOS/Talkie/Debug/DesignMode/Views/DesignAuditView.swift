//
//  DesignAuditView.swift
//  Talkie macOS
//
//  Design System Audit - Container view with responsive master-detail layout
//  Manages state and coordinates between runs list and run detail views
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import TalkieKit

#if DEBUG

/// Text that shows underline and pointer cursor only when Cmd is held
struct ClickableLogText: View {
    let text: String
    let color: Color
    let onCommandClick: () -> Void

    @State private var isHovering = false
    @State private var isCmdHeld = false

    var body: some View {
        Text(text)
            .foregroundColor(color)
            .underline(isCmdHeld && isHovering, color: color.opacity(0.7))
            .onHover { hovering in
                isHovering = hovering
                updateCursor()
            }
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command) {
                    onCommandClick()
                }
            }
            .onAppear {
                // Monitor modifier key changes
                NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    isCmdHeld = event.modifierFlags.contains(.command)
                    if isHovering { updateCursor() }
                    return event
                }
            }
    }

    private func updateCursor() {
        if isHovering && NSEvent.modifierFlags.contains(.command) {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}

/// Log entry for audit progress
struct AuditLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LogType
    let clickablePath: String?
    let screen: AppScreen?

    init(timestamp: Date, message: String, type: LogType, clickablePath: String? = nil, screen: AppScreen? = nil) {
        self.timestamp = timestamp
        self.message = message
        self.type = type
        self.clickablePath = clickablePath
        self.screen = screen
    }

    enum LogType {
        case info, perfect, good, caution, poor, error, screen, screenshot

        var icon: String {
            switch self {
            case .info: return "arrow.right"
            case .perfect: return "checkmark.circle.fill"  // 100%
            case .good: return "checkmark.circle"          // 90-99%
            case .caution: return "checkmark.circle"       // 60-89%
            case .poor: return "xmark.circle"              // <60%
            case .error: return "xmark.circle.fill"
            case .screen: return "rectangle.portrait"
            case .screenshot: return "camera"
            }
        }

        var color: Color {
            switch self {
            case .info: return .secondary
            case .perfect: return .green
            case .good: return .green.opacity(0.8)
            case .caution: return .orange
            case .poor: return .red
            case .error: return .red
            case .screen: return .cyan
            case .screenshot: return .purple
            }
        }
    }
}

struct DesignAuditView: View {
    // Core state
    @State private var selectedRunNumber: Int?
    @State private var selectedReport: FullAuditReport?
    @State private var availableRuns: [DesignAuditor.AuditRunInfo] = []
    @State private var selectedScreen: AppScreen?
    @State private var isRunningAudit = false
    @State private var includeScreenshots = true
    @State private var isViewingLogs = false  // Show logs view instead of detail

    // Audit log state
    @State private var auditLogs: [AuditLogEntry] = []
    @State private var logRunNumber: Int? = nil  // Which run the logs are for
    @State private var currentScreen: String = ""
    @State private var auditStartTime: Date?
    @State private var screensCompleted: Int = 0
    @State private var totalScreens: Int = 0
    @State private var currentPhase: AuditPhase = .idle

    private let compactThreshold: CGFloat = 700

    enum AuditPhase {
        case idle, analysis, screenshots, complete

        var label: String {
            switch self {
            case .idle: return "Ready"
            case .analysis: return "Analyzing"
            case .screenshots: return "Capturing"
            case .complete: return "Complete"
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < compactThreshold

            if isRunningAudit || isViewingLogs {
                auditRunnerView
            } else if isCompact {
                compactLayout
            } else {
                wideLayout
            }
        }
        .background(Theme.current.background)
        .onAppear { loadCachedAudit() }
        .onChange(of: selectedRunNumber) { _, newValue in
            if let runNumber = newValue {
                loadRun(runNumber)
            } else {
                selectedReport = nil
            }
        }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var wideLayout: some View {
        HSplitView {
            AuditRunsListView(
                selectedRunNumber: $selectedRunNumber,
                availableRuns: availableRuns,
                isRunningAudit: isRunningAudit,
                includeScreenshots: includeScreenshots,
                onToggleScreenshots: { includeScreenshots.toggle() },
                onRunAudit: runAudit,
                onViewLogs: viewLogsForRun
            )
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)

            if let report = selectedReport {
                AuditRunDetailView(
                    report: report,
                    selectedScreen: $selectedScreen
                )
            } else {
                placeholderView
            }
        }
    }

    @ViewBuilder
    private var compactLayout: some View {
        AuditRunsListView(
            selectedRunNumber: $selectedRunNumber,
            availableRuns: availableRuns,
            isRunningAudit: isRunningAudit,
            includeScreenshots: includeScreenshots,
            onToggleScreenshots: { includeScreenshots.toggle() },
            onRunAudit: runAudit,
            onViewLogs: viewLogsForRun
        )
        .sheet(isPresented: Binding(
            get: { selectedReport != nil },
            set: { if !$0 { selectedReport = nil; selectedRunNumber = nil } }
        )) {
            if let report = selectedReport {
                AuditRunDetailView(
                    report: report,
                    selectedScreen: $selectedScreen
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("Select an audit run")
                .font(Theme.current.fontHeadline)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Choose a run from the list to view its details")
                .font(Theme.current.fontBody)
                .foregroundColor(Theme.current.foregroundMuted)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: - Audit Runner View

    @ViewBuilder
    private var auditRunnerView: some View {
        let isJustViewingLogs = isViewingLogs && !isRunningAudit

        VStack(spacing: 0) {
            // Header - matches log entry structure exactly
            HStack(alignment: .top, spacing: Spacing.sm) {
                // Timestamp (shows current time or log run info)
                if isJustViewingLogs, let runNum = logRunNumber {
                    Text("run-\(String(format: "%03d", runNum))")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(.gray)
                } else {
                    Text(logTimestamp(Date()))
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(.gray)
                }

                // Icon (same position/size as log icons)
                if currentPhase == .complete || isJustViewingLogs {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                        .frame(width: 14)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundColor(.cyan)
                        .frame(width: 14)
                }

                // Status text
                if isJustViewingLogs {
                    Text("logs")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(.green)
                } else {
                    Text(currentPhase == .complete ? "complete" : currentScreen.isEmpty ? "starting..." : currentScreen.lowercased())
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(currentPhase == .complete ? .green : .white)
                }

                Spacer()

                if !isJustViewingLogs && totalScreens > 0 {
                    Text("\(screensCompleted)/\(totalScreens)")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                // Close button
                Button(action: closeLogsView) {
                    Text("×")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.black)

            // Progress line
            if totalScreens > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.cyan.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(screensCompleted) / CGFloat(totalScreens))
                }
                .frame(height: 1)
                .background(Theme.current.surface2)
            }

            // Terminal log
            auditLogTerminal

            // Subtle completion indicator
            if currentPhase == .complete {
                HStack(spacing: Spacing.sm) {
                    Text("done")
                        .font(.system(size: 10, weight: .light, design: .monospaced))
                        .foregroundColor(.green)
                    Text("—")
                        .foregroundColor(Theme.current.foregroundMuted)
                    Button("view results →") {
                        isRunningAudit = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .light, design: .monospaced))
                    .foregroundColor(TalkieTheme.accent)

                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.black)
            }
        }
    }

    @ViewBuilder
    private var auditLogTerminal: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(auditLogs) { entry in
                        logEntryRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(Spacing.md)
            }
            .onChange(of: auditLogs.count) { _, _ in
                if let lastEntry = auditLogs.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.black.opacity(0.95))
        .font(.system(size: 11, weight: .light, design: .monospaced))
    }

    @ViewBuilder
    private func logEntryRow(_ entry: AuditLogEntry) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(logTimestamp(entry.timestamp))
                .foregroundColor(.gray)

            Image(systemName: entry.type.icon)
                .foregroundColor(entry.type.color)
                .frame(width: 14)

            if let path = entry.clickablePath {
                // Screenshot path - Cmd+Click to reveal in Finder
                HStack(spacing: 0) {
                    Text(entry.message.replacingOccurrences(of: path, with: ""))
                        .foregroundColor(.white)

                    Text(path)
                        .foregroundColor(.blue)
                        .underline()
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) {
                                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                            }
                        }
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .help("⌘+Click to reveal in Finder")
                }
            } else if let screen = entry.screen {
                // Screen entry - Cmd+Click to navigate to screen
                ClickableLogText(
                    text: entry.message,
                    color: entry.type.color,
                    onCommandClick: {
                        isRunningAudit = false
                        selectedScreen = screen
                    }
                )
                .help("⌘+Click to view screen audit")
            } else {
                Text(entry.message)
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func loadCachedAudit() {
        Task {
            let entries = await AuditStore.shared.listRuns()
            await MainActor.run {
                availableRuns = entries.map { entry in
                    DesignAuditor.AuditRunInfo(
                        id: entry.id,
                        timestamp: entry.timestamp,
                        appVersion: entry.appVersion,
                        gitBranch: entry.gitBranch,
                        gitCommit: entry.gitCommit,
                        themeName: entry.themeName,
                        overallScore: entry.overallScore,
                        grade: entry.grade,
                        totalIssues: entry.totalIssues,
                        screenshotCount: 0
                    )
                }
            }

            // Fall back to scanning if no index
            if entries.isEmpty {
                let scannedRuns = DesignAuditor.shared.listAllRuns()
                await MainActor.run {
                    availableRuns = scannedRuns
                }
            }

            // Load latest run if available
            if await MainActor.run(body: { selectedReport }) == nil {
                if let latestEntry = await AuditStore.shared.latestRun(),
                   let report = await AuditStore.shared.loadReport(for: latestEntry) {
                    await MainActor.run {
                        selectedReport = report
                        selectedRunNumber = latestEntry.id
                    }
                } else if let report = DesignAuditor.shared.loadLatestAudit() {
                    await MainActor.run {
                        selectedReport = report
                        selectedRunNumber = report.runNumber
                    }
                }
            }
        }
    }

    private func loadRun(_ runNumber: Int) {
        Task {
            if let report = await AuditStore.shared.loadReport(runNumber: runNumber) {
                await MainActor.run {
                    selectedReport = report
                    selectedScreen = nil
                }
            } else {
                let report = DesignAuditor.shared.loadRun(runNumber)
                await MainActor.run {
                    selectedReport = report
                    selectedScreen = nil
                }
            }
        }
    }

    private func runAudit() {
        auditLogs = []
        screensCompleted = 0
        totalScreens = AppScreen.allCases.count
        currentScreen = ""
        auditStartTime = Date()
        isRunningAudit = true
        currentPhase = .analysis

        addLog("design-audit v1.0", type: .info)
        addLog("mode: \(includeScreenshots ? "full" : "analysis-only")", type: .info)

        Task {
            await MainActor.run {
                addLog("target: \(totalScreens) screens", type: .info)
                addLog("", type: .info)
            }

            var results: [ScreenAuditResult] = []

            for (index, screen) in AppScreen.allCases.enumerated() {
                await MainActor.run {
                    currentScreen = screen.title
                }

                let result = await DesignAuditor.shared.auditScreen(screen)
                results.append(result)

                await MainActor.run {
                    screensCompleted = index + 1
                    let score = result.overallScore
                    let logType = scoreToLogType(score)
                    let issueText = result.totalIssues > 0 ? " (\(result.totalIssues))" : ""
                    addLog("\(screen.title) \(score)%\(issueText)", type: logType, screen: screen)
                }
            }

            var report: FullAuditReport

            if includeScreenshots {
                await MainActor.run {
                    currentPhase = .screenshots
                    screensCompleted = 0
                    addLog("", type: .info)
                    addLog("── screenshots ──", type: .info)
                }

                var captured = 0
                var failed = 0

                report = await DesignAuditor.shared.finalizeAudit(results: results) { screen, success, path in
                    if success {
                        captured += 1
                        addLog("\(screen.title)", type: .screenshot, path: path, screen: screen)
                    } else {
                        failed += 1
                        addLog("\(screen.title) failed", type: .error, screen: screen)
                    }
                    screensCompleted += 1
                }

                await MainActor.run {
                    let summaryType: AuditLogEntry.LogType = failed == 0 ? .perfect : .caution
                    addLog("captured: \(captured)" + (failed > 0 ? " failed: \(failed)" : ""), type: summaryType)
                }
            } else {
                report = await DesignAuditor.shared.finalizeAuditWithoutScreenshots(results: results)
            }

            await MainActor.run {
                currentPhase = .complete
                addLog("", type: .info)
                addLog("── complete ──", type: .info)
                let gradeType = scoreToLogType(report.overallScore)
                addLog("grade: \(report.grade) (\(report.overallScore)%)", type: gradeType)
                let issueType: AuditLogEntry.LogType = report.totalIssues == 0 ? .perfect : .caution
                addLog("issues: \(report.totalIssues)", type: issueType)
            }

            try? await Task.sleep(for: .milliseconds(500))

            let updatedRuns = DesignAuditor.shared.listAllRuns()

            await MainActor.run {
                selectedReport = report
                availableRuns = updatedRuns
                if let runNumber = report.runNumber {
                    selectedRunNumber = runNumber
                    logRunNumber = runNumber  // Save which run the logs belong to
                }
            }
        }
    }

    // MARK: - Helpers

    private func logTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func addLog(_ message: String, type: AuditLogEntry.LogType = .info, path: String? = nil, screen: AppScreen? = nil) {
        let entry = AuditLogEntry(timestamp: Date(), message: message, type: type, clickablePath: path, screen: screen)
        auditLogs.append(entry)
    }

    private func scoreToLogType(_ score: Int) -> AuditLogEntry.LogType {
        switch score {
        case 100: return .perfect
        case 90..<100: return .good
        case 60..<90: return .caution
        default: return .poor
        }
    }

    private func viewLogsForRun(_ runNumber: Int) {
        // Only show logs if they exist for this run (currently only in memory)
        if logRunNumber == runNumber && !auditLogs.isEmpty {
            isViewingLogs = true
        } else {
            // Could show an alert that logs aren't available
            // For now, just show the current logs if any exist
            if !auditLogs.isEmpty {
                isViewingLogs = true
            }
        }
    }

    private func closeLogsView() {
        isRunningAudit = false
        isViewingLogs = false
    }
}

#endif
