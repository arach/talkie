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
    let initiallyExpanded: Bool

    /// Initialize with custom content and optional debug info (matches original API)
    init(
        initiallyExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> CustomContent,
        debugInfo: @escaping () -> [String: String] = { [:] }
    ) {
        self.customContent = content()
        self.debugInfo = debugInfo
        self.initiallyExpanded = initiallyExpanded
    }

    var body: some View {
        DebugToolbar(
            title: "DEV",
            icon: "ant.fill",
            sections: buildSections(),
            actions: [],
            initiallyExpanded: initiallyExpanded,
            onCopy: { buildCopyText() }
        ) {
            customContent
        }
    }

    private func buildSections() -> [DebugKit.DebugSection] {
        var sections: [DebugKit.DebugSection] = []

        // Custom state section only
        let info = debugInfo()
        if !info.isEmpty {
            let rows = info.keys.sorted().map { key in
                (key, info[key] ?? "-")
            }
            sections.append(DebugKit.DebugSection("STATE", rows))
        }

        return sections
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
    init(initiallyExpanded: Bool = false) {
        self.init(initiallyExpanded: initiallyExpanded, content: { EmptyView() }, debugInfo: { [:] })
    }
}

// MARK: - Legacy Alias (for compatibility)
typealias DebugToolbarOverlay<Content: View> = TalkieDebugToolbar<Content>

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
                .foregroundColor(Theme.current.foregroundSecondary)

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
            .cornerRadius(CornerRadius.xs)
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
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text(info[key] ?? "-")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.current.foreground)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(index % 2 == 0 ? Theme.current.surfaceAlternate : Color.clear)
            }
        }
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.xs)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Context-Specific Content

/// Debug content for the main memo list view - minimal, just data inspection
struct ListViewDebugContent: View {
    @State private var showSQLiteViewer = false
    @State private var isRunningBenchmark = false
    @State private var benchmarkResult: String?
    @State private var isRunningPipelineBenchmark = false
    @State private var pipelineBenchmarkResult: String?
    @State private var useCalendarWidget = SettingsManager.shared.useCalendarWidget
    @State private var sandboxMode = SettingsManager.shared.sandboxMode
    @State private var showRestartAlert = false

    var body: some View {
        VStack(spacing: 10) {
            // Sandbox mode indicator (when active)
            if DatabaseManager.isUsingSandbox {
                HStack(spacing: 6) {
                    Image(systemName: "flask.fill")
                        .foregroundColor(.orange)
                    Text("SANDBOX MODE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(4)
            }

            DebugSection(title: "SANDBOX") {
                Toggle(isOn: $sandboxMode) {
                    HStack(spacing: 6) {
                        Image(systemName: "flask")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                            .frame(width: 14)
                        Text("Fresh User Mode")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: sandboxMode) { _, newValue in
                    SettingsManager.shared.sandboxMode = newValue
                    showRestartAlert = true
                }

                Text("Uses empty database to test onboarding")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                if DatabaseManager.isUsingSandbox {
                    DebugActionButton(icon: "trash", label: "Reset Sandbox", destructive: true) {
                        resetSandboxDatabase()
                    }
                }
            }

            DebugSection(title: "DATA") {
                DebugActionButton(icon: "cylinder.split.1x2", label: "SQLite Viewer") {
                    showSQLiteViewer = true
                }
            }

            DebugSection(title: "HOME") {
                // Grid preset picker
                GridPresetPicker()

                Toggle(isOn: $useCalendarWidget) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 14)
                        Text("Calendar Widget")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: useCalendarWidget) { _, newValue in
                    SettingsManager.shared.useCalendarWidget = newValue
                }

                // Debug info about apps
                let apps = AppsRuntime.shared.loadedApps
                let widgets = AppsRuntime.shared.widgetApps
                Text("Apps: \(apps.count), Widgets: \(widgets.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                if let cal = apps["calendar"] {
                    Text("Cal: \(cal.isEnabled ? "✓" : "✗") widget:\(cal.manifest.widget != nil ? "✓" : "✗")")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("Calendar app not found")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.red)
                }
            }


            DebugSection(title: "VOICE") {
                DebugActionButton(icon: "waveform.badge.magnifyingglass", label: isRunningBenchmark ? "Running..." : "Intent Benchmark") {
                    runVoiceIntentBenchmark()
                }
                .disabled(isRunningBenchmark)

                if let result = benchmarkResult {
                    Text(result)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                DebugActionButton(icon: "brain.head.profile", label: isRunningPipelineBenchmark ? "Running..." : "Pipeline Benchmark") {
                    runPipelineBenchmark()
                }
                .disabled(isRunningPipelineBenchmark)

                if let result = pipelineBenchmarkResult {
                    Text(result)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .sheet(isPresented: $showSQLiteViewer) {
            SQLiteViewer()
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                restartApp()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(sandboxMode
                 ? "Sandbox mode will activate after restart. Your real data is safe."
                 : "Normal mode will restore after restart.")
        }
    }

    private func resetSandboxDatabase() {
        // Delete sandbox database files
        try? FileManager.default.removeItem(at: DatabaseManager.sandboxFolderURL)
        showRestartAlert = true
    }

    private func restartApp() {
        // Relaunch the app
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        exit(0)
    }

    private func runVoiceIntentBenchmark() {
        isRunningBenchmark = true
        benchmarkResult = nil

        Task {
            let result = await VoiceIntentBenchmark.shared.runFullBenchmark()
            await VoiceIntentBenchmark.shared.printResults(result)

            await MainActor.run {
                benchmarkResult = "\(result.passRate) (\(result.passed)/\(result.totalCases))"
                isRunningBenchmark = false
            }
        }
    }

    private func runPipelineBenchmark() {
        isRunningPipelineBenchmark = true
        pipelineBenchmarkResult = nil

        Task {
            let result = await ClassifierPipelineBenchmark.shared.runFullBenchmark()
            await ClassifierPipelineBenchmark.shared.printResults(result)

            await MainActor.run {
                let hcPct = String(format: "%.0f", result.hcAccuracy * 100)
                let trainedPct = String(format: "%.0f", result.trainedHeadAccuracy * 100)
                let trainMs = String(format: "%.0f", result.trainingTimeMs)
                pipelineBenchmarkResult = "HC:\(hcPct)% | Trained:\(trainedPct)% | Train:\(trainMs)ms"
                isRunningPipelineBenchmark = false
            }
        }
    }
}

/// Alias for backwards compatibility
typealias MainDebugContent = ListViewDebugContent


/// Debug content for the memo detail view
/// Follows iOS pattern: view-specific actions → convenience → platform-wide utils
struct DetailViewDebugContent: View {
    let memo: MemoModel
    @State private var showingInspector = false
    private let repository = LocalRepository()

    var body: some View {
        VStack(spacing: 10) {
            // 1. Page-specific actions (memo operations)
            DebugSection(title: "MEMO") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "bolt.circle", label: "Re-run Auto-Run") {
                        Task {
                            // Reset autoProcessed flag via GRDB
                            var updatedMemo = memo
                            updatedMemo.autoProcessed = false
                            try? await repository.saveMemo(updatedMemo)
                            SystemEventManager.shared.logSync(.system, "Reset autoProcessed for re-run", detail: memo.displayTitle)
                            // Note: AutoRunProcessor will pick this up on next observation cycle
                        }
                    }
                    DebugActionButton(icon: "arrow.counterclockwise", label: "Reset autoProcessed") {
                        Task {
                            var updatedMemo = memo
                            updatedMemo.autoProcessed = false
                            try? await repository.saveMemo(updatedMemo)
                            SystemEventManager.shared.logSync(.system, "Reset autoProcessed", detail: memo.title ?? "Untitled")
                        }
                    }
                }
            }

            // 2. Data inspection
            DebugSection(title: "INSPECT") {
                DebugActionButton(icon: "tablecells", label: "MemoModel Data") {
                    showingInspector = true
                }
            }
        }
        .sheet(isPresented: $showingInspector) {
            MemoModelInspector(memo: memo)
        }
    }
}

/// Alias for backwards compatibility
typealias MemoDetailDebugContent = DetailViewDebugContent

// MARK: - Data Inspector

/// Data inspector for MemoModel (GRDB)
struct MemoModelInspector: View {
    let memo: MemoModel
    @Environment(\.dismiss) private var dismiss
    private let settings = SettingsManager.shared
    @State private var showCopied = false

    private var attributes: [(name: String, value: String, type: String)] {
        [
            ("id", memo.id.uuidString, "UUID"),
            ("createdAt", formatDate(memo.createdAt), "Date"),
            ("lastModified", formatDate(memo.lastModified), "Date"),
            ("title", memo.title ?? "nil", "String?"),
            ("duration", String(format: "%.2f", memo.duration), "Double"),
            ("sortOrder", String(memo.sortOrder), "Int"),
            ("transcription", memo.transcription?.prefix(50).description ?? "nil", "String?"),
            ("notes", memo.notes?.prefix(50).description ?? "nil", "String?"),
            ("summary", memo.summary?.prefix(50).description ?? "nil", "String?"),
            ("tasks", memo.tasks?.prefix(50).description ?? "nil", "String?"),
            ("reminders", memo.reminders?.prefix(50).description ?? "nil", "String?"),
            ("audioFilePath", memo.audioFilePath ?? "nil", "String?"),
            ("waveformData", (memo.waveformData?.count ?? 0).description + " bytes", "Data?"),
            ("isTranscribing", memo.isTranscribing ? "true" : "false", "Bool"),
            ("isProcessingSummary", memo.isProcessingSummary ? "true" : "false", "Bool"),
            ("isProcessingTasks", memo.isProcessingTasks ? "true" : "false", "Bool"),
            ("isProcessingReminders", memo.isProcessingReminders ? "true" : "false", "Bool"),
            ("autoProcessed", memo.autoProcessed ? "true" : "false", "Bool"),
            ("originDeviceId", memo.originDeviceId ?? "nil", "String?"),
            ("macReceivedAt", memo.macReceivedAt.map { formatDate($0) } ?? "nil", "Date?"),
            ("cloudSyncedAt", memo.cloudSyncedAt.map { formatDate($0) } ?? "nil", "Date?"),
            ("deletedAt", memo.deletedAt.map { formatDate($0) } ?? "nil", "Date?"),
            ("pendingWorkflowIds", memo.pendingWorkflowIds ?? "nil", "String?"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MemoModel")
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
                    inspectorSection("MEMO") {
                        inspectorRow("ID", String(memo.id.uuidString.prefix(8)))
                        inspectorRow("Created", formatDate(memo.createdAt))
                        inspectorRow("Modified", formatDate(memo.lastModified))
                    }

                    // Attributes
                    inspectorSection("ATTRIBUTES (\(attributes.count))") {
                        ForEach(attributes, id: \.name) { attr in
                            inspectorRow(attr.name, attr.value, typeHint: attr.type)
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
                .foregroundColor(Theme.current.foregroundSecondary)

            VStack(spacing: 0) {
                content()
            }
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.xs)
        }
    }

    private func inspectorRow(_ label: String, _ value: String, typeHint: String? = nil) -> some View {
        HStack(alignment: .top) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func copyAllData() {
        var lines: [String] = []
        lines.append("=== MEMOMODEL ===")
        lines.append("ID: \(memo.id.uuidString)")
        lines.append("")
        lines.append("ATTRIBUTES")
        for attr in attributes {
            lines.append("  \(attr.name): \(attr.value)")
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

// MARK: - Grid Preset Picker (for Debug Toolbar)

/// Compact picker for switching HomeScreen grid presets
struct GridPresetPicker: View {
    @ObservedObject private var presetManager = HomeGridPresetManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.purple)
                    .frame(width: 14)

                Text("Grid Preset")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))

                Spacer()

                Picker("", selection: $presetManager.activePreset) {
                    ForEach(HomeGridPreset.allCases) { preset in
                        Text(preset.rawValue)
                            .tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .controlSize(.small)
            }

            Text(presetManager.activePreset.description)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }
}

#endif
