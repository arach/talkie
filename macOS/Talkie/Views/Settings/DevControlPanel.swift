//
//  DevControlPanel.swift
//  Talkie
//
//  Development control panel for managing multiple service instances
//  Only available in DEBUG builds
//

import SwiftUI
import TalkieKit

struct DevControlPanelView: View {
    private let serviceManager = ServiceManager.shared
    @Environment(EngineClient.self) private var engineClient

    @State private var autoRefresh = true
    @State private var refreshTimer: Timer?
    @State private var logs: [LogEntry] = []

    // External Data Auditor
    @State private var auditor = ExternalDataAuditor()
    @State private var showingAuditResults = false

    // TTS Test
    @State private var ttsTestText = "Hello! Talkie can now speak."
    @State private var isSynthesizing = false
    @State private var ttsIsLoaded = false
    @State private var isUnloadingTTS = false
    @State private var engineMemoryMB: Double = 0
    @State private var memoryBeforeTTS: Double? = nil

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: LogLevel

        enum LogLevel {
            case info, success, error

            var color: Color {
                switch self {
                case .info: return .secondary
                case .success: return .green
                case .error: return .red
                }
            }
        }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "hammer.fill",
                title: "DEV CONTROL PANEL",
                subtitle: "Manage multiple service instances during development"
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Connection Status
                connectionStatusSection

                Divider()

                // TalkieEngine Instances
                serviceSection(
                    title: "TalkieEngine Instances",
                    processes: serviceManager.engineProcesses,
                    serviceName: "TalkieEngine",
                    connectedPID: engineClient.status?.pid
                )

                Divider()

                // TalkieLive Instances
                serviceSection(
                    title: "TalkieLive Instances",
                    processes: serviceManager.liveProcesses,
                    serviceName: "TalkieLive",
                    connectedPID: serviceManager.live.processId ?? discoveredLivePID
                )

                Divider()

                // Quick Actions
                quickActionsSection

                Divider()

                // TTS Test
                ttsTestSection

                Divider()

                // External Data Audit
                externalDataAuditSection

                // Logs Section
                if !logs.isEmpty {
                    Divider()
                    logsSection
                }
            }
        }
        .onAppear {
            serviceManager.scan()
            startAutoRefresh()
            // Start monitoring to get live connection status and PID
            serviceManager.live.startMonitoring()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - Connection Status

    /// Get the PID of the discovered Live process (fallback if serviceManager.live.processId is nil)
    private var discoveredLivePID: Int32? {
        // If there's only one Live process, use it
        guard !serviceManager.liveProcesses.isEmpty else { return nil }

        // Try to match by environment first
        if let env = serviceManager.live.connectedMode {
            if let matching = serviceManager.liveProcesses.first(where: { $0.environment == env }) {
                return matching.pid
            }
        }

        // Otherwise, just use the first one
        return serviceManager.liveProcesses.first?.pid
    }

    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ACTIVE CONNECTIONS")
                .font(.techLabel)
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(spacing: Spacing.sm) {
                // Engine
                connectionBadge(
                    title: "Engine",
                    isConnected: engineClient.isConnected,
                    environment: engineClient.connectedMode?.environment,
                    pid: engineClient.status?.pid
                )

                // Live
                connectionBadge(
                    title: "Live",
                    isConnected: serviceManager.live.isRunning,
                    environment: serviceManager.live.connectedMode,
                    pid: serviceManager.live.processId ?? discoveredLivePID
                )
            }
        }
        .padding(Spacing.sm)
        .background(Color.secondary.opacity(Opacity.subtle))
        .cornerRadius(CornerRadius.sm)
    }

    private func connectionBadge(title: String, isConnected: Bool, environment: TalkieEnvironment?, pid: Int32?) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.labelSmall)
                    .foregroundColor(Theme.current.foreground)

                HStack(spacing: Spacing.xxs) {
                    if let env = environment {
                        Text(env.displayName)
                            .font(.techLabelSmall)
                            .foregroundColor(envColor(env))
                    }

                    if let pid = pid {
                        Text(verbatim: "PID \(String(format: "%d", pid))")
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding(Spacing.sm)
        .background(isConnected ? Color.green.opacity(Opacity.light) : Color.red.opacity(Opacity.light))
        .cornerRadius(CornerRadius.xs)
    }

    // MARK: - Service Section

    private func serviceSection(title: String, processes: [DiscoveredProcess], serviceName: String, connectedPID: Int32?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(title.uppercased())
                    .font(.techLabel)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text("\(processes.count) instance\(processes.count == 1 ? "" : "s")")
                    .font(.techLabelSmall)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            if processes.isEmpty {
                Text("No instances found")
                    .font(.labelSmall)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.lg)
                    .background(Color.secondary.opacity(Opacity.subtle))
                    .cornerRadius(CornerRadius.xs)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(processes) { process in
                        processRow(process: process, isConnected: process.pid == connectedPID)
                    }
                }
            }
        }
    }

    private func processRow(process: DiscoveredProcess, isConnected: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            // Status indicator
            Circle()
                .fill(isConnected ? Color.green : (process.isDaemon ? Color.blue : Color.orange))
                .frame(width: 6, height: 6)

            // Process info
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(verbatim: "PID \(String(format: "%d", process.pid))")
                        .font(.labelMedium)
                        .foregroundColor(Theme.current.foreground)

                    if let env = process.environment {
                        Text(env.displayName)
                            .font(.techLabelSmall)
                            .foregroundColor(envColor(env))
                            .padding(.horizontal, Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(envColor(env).opacity(Opacity.medium))
                            .cornerRadius(CornerRadius.xs)
                    }

                    Text(process.modeDescription)
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(Opacity.light))
                        .cornerRadius(CornerRadius.xs)

                    if isConnected {
                        Text("CONNECTED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(Opacity.medium))
                            .cornerRadius(CornerRadius.xs)
                    }
                }

                if let xpcService = process.xpcService {
                    Text("XPC: \(xpcService)")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                if let path = process.bundlePath {
                    Text(shortPath(path))
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundMuted.opacity(Opacity.prominent))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action buttons - different for daemon vs direct launch
            HStack(spacing: Spacing.xs) {
                if process.isDaemon {
                    // Daemon: show stop/restart buttons
                    Button(action: {
                        stopDaemon(process)
                    }) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "stop.fill")
                                .font(.labelSmall)
                            Text("Stop")
                                .font(.labelSmall)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.orange.opacity(Opacity.light))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                    .help("Stop daemon via launchctl")

                    Button(action: {
                        restartDaemon(process)
                    }) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "arrow.clockwise")
                                .font(.labelSmall)
                            Text("Restart")
                                .font(.labelSmall)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.blue.opacity(Opacity.light))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                    .help("Restart daemon via launchctl")
                } else {
                    // Direct launch: show kill button
                    Button(action: {
                        killProcess(process)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.bodyMedium)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Terminate PID \(process.pid)")
                }
            }
        }
        .padding(Spacing.sm)
        .background(isConnected ? Color.green.opacity(Opacity.subtle) : Color.secondary.opacity(Opacity.subtle))
        .cornerRadius(CornerRadius.xs)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("QUICK ACTIONS")
                .font(.techLabel)
                .foregroundColor(Theme.current.foregroundSecondary)

            VStack(spacing: Spacing.xs) {
                // Refresh
                actionButton(
                    icon: "arrow.clockwise",
                    title: "Refresh",
                    description: "Scan for all running instances",
                    color: .blue
                ) {
                    serviceManager.scan()
                }

                // Kill all daemons
                actionButton(
                    icon: "trash.fill",
                    title: "Kill All Daemons",
                    description: "Stop all launchd-managed instances",
                    color: .orange
                ) {
                    let engineKilled = serviceManager.killAllDaemons(service: "TalkieEngine")
                    let liveKilled = serviceManager.killAllDaemons(service: "TalkieLive")
                    let total = engineKilled + liveKilled
                    if total > 0 {
                        addLog("Terminated \(total) daemon instance\(total == 1 ? "" : "s") (Engine: \(engineKilled), Live: \(liveKilled))", level: .success)
                    } else {
                        addLog("No daemon instances found to terminate", level: .info)
                    }
                }

                // Kill all Xcode builds
                actionButton(
                    icon: "trash.fill",
                    title: "Kill All Xcode Builds",
                    description: "Stop all directly-launched instances",
                    color: .red
                ) {
                    let engineKilled = serviceManager.killAllXcode(service: "TalkieEngine")
                    let liveKilled = serviceManager.killAllXcode(service: "TalkieLive")
                    let total = engineKilled + liveKilled
                    if total > 0 {
                        addLog("Terminated \(total) Xcode instance\(total == 1 ? "" : "s") (Engine: \(engineKilled), Live: \(liveKilled))", level: .success)
                    } else {
                        addLog("No Xcode instances found to terminate", level: .info)
                    }
                }

                // Auto-refresh toggle
                Toggle(isOn: $autoRefresh) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "timer")
                            .font(.labelSmall)
                        Text("Auto-refresh every 3s")
                            .font(.labelSmall)
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                }
                .toggleStyle(.switch)
                .onChange(of: autoRefresh) { _, enabled in
                    if enabled {
                        startAutoRefresh()
                    } else {
                        stopAutoRefresh()
                    }
                }
            }
        }
    }

    // MARK: - TTS Test

    private var ttsTestSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("TTS TEST")
                    .font(.techLabel)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                // Engine memory display
                HStack(spacing: Spacing.sm) {
                    // Memory indicator
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "memorychip")
                            .font(.caption2)
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text("Engine: \(String(format: "%.0f", engineMemoryMB)) MB")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                        if let before = memoryBeforeTTS, ttsIsLoaded {
                            let delta = engineMemoryMB - before
                            Text("(+\(String(format: "%.0f", delta)))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(delta > 50 ? .orange : .green)
                        }
                    }

                    Divider()
                        .frame(height: 12)

                    // TTS Status indicator
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(ttsIsLoaded ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(ttsIsLoaded ? "TTS Loaded" : "TTS Unloaded")
                            .font(.caption2)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
            }

            VStack(spacing: Spacing.xs) {
                // Text input
                TextField("Text to speak...", text: $ttsTestText)
                    .textFieldStyle(.roundedBorder)
                    .font(.labelSmall)

                // Speak button
                HStack {
                    Button {
                        testTTS()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            if isSynthesizing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.labelSmall)
                            }
                            Text(isSynthesizing ? "Synthesizing..." : "Speak")
                                .font(.labelSmall)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSynthesizing || ttsTestText.isEmpty)

                    // Unload TTS button
                    Button {
                        unloadTTS()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            if isUnloadingTTS {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "memorychip")
                                    .font(.labelSmall)
                            }
                            Text(isUnloadingTTS ? "Unloading..." : "Unload Model")
                                .font(.labelSmall)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!ttsIsLoaded || isUnloadingTTS)

                    Spacer()

                    Text("OS manages memory via compression")
                        .font(.caption2)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
        }
        .onAppear {
            refreshTTSStatus()
            refreshEngineMemory()
            // Start memory polling
            startMemoryPolling()
        }
    }

    private func refreshTTSStatus() {
        Task {
            let (isLoaded, _) = await engineClient.getTTSStatus()
            await MainActor.run {
                ttsIsLoaded = isLoaded
            }
        }
    }

    private func refreshEngineMemory() {
        // Get Engine PID from status
        guard let status = engineClient.status, let pid = status.pid, pid > 0 else { return }

        // Get memory via shell
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "rss=", "-p", "\(pid)"]

            let pipe = Pipe()
            process.standardOutput = pipe

            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let rss = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let mb = rss / 1024.0
                await MainActor.run {
                    engineMemoryMB = mb
                }
            }
        }
    }

    private func startMemoryPolling() {
        // Poll memory every 2 seconds while this view is visible
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                refreshEngineMemory()
            }
        }
    }

    private func unloadTTS() {
        isUnloadingTTS = true
        let memoryBefore = engineMemoryMB
        addLog("TTS: Unloading model (current: \(String(format: "%.0f", memoryBefore)) MB)...", level: .info)

        Task {
            let success = await engineClient.unloadTTS()

            // Wait for memory to settle
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            refreshEngineMemory()

            // Wait a bit more for the refresh
            try? await Task.sleep(nanoseconds: 500_000_000)

            await MainActor.run {
                isUnloadingTTS = false
                if success {
                    ttsIsLoaded = false
                    let memoryAfter = engineMemoryMB
                    let freed = memoryBefore - memoryAfter
                    addLog("TTS: Unloaded! \(String(format: "%.0f", memoryBefore)) → \(String(format: "%.0f", memoryAfter)) MB (freed \(String(format: "%.0f", freed)) MB)", level: .success)
                    memoryBeforeTTS = nil
                } else {
                    addLog("TTS: Failed to unload model", level: .error)
                }
            }
        }
    }

    private func testTTS() {
        guard !ttsTestText.isEmpty else { return }
        isSynthesizing = true
        addLog("TTS: Synthesizing '\(ttsTestText.prefix(30))...'", level: .info)

        // Capture memory before TTS load (if not already loaded)
        if !ttsIsLoaded {
            memoryBeforeTTS = engineMemoryMB
            addLog("TTS: Memory before load: \(String(format: "%.0f", engineMemoryMB)) MB", level: .info)
        }

        // Track in PerformanceMonitor
        PerformanceMonitor.shared.startAction(type: "TTS", name: "Synthesize", context: "Kokoro")

        Task {
            let startTime = Date()
            do {
                let audioPath = try await engineClient.synthesize(
                    text: ttsTestText,
                    voiceId: "kokoro:default"
                )
                let elapsed = Date().timeIntervalSince(startTime)

                // Track TTS operation timing
                await MainActor.run {
                    PerformanceMonitor.shared.addOperation(category: .tts, name: "Kokoro synthesis", duration: elapsed)
                    PerformanceMonitor.shared.completeAction()
                }

                addLog("TTS: Synthesized in \(String(format: "%.2f", elapsed))s → \(URL(fileURLWithPath: audioPath).lastPathComponent)", level: .success)

                // Play the audio
                AudioPlaybackManager.shared.play(url: URL(fileURLWithPath: audioPath), id: "tts-test")
                addLog("TTS: Playing audio...", level: .success)

                // Refresh status and memory (model is now loaded)
                refreshTTSStatus()

                // Wait a moment for memory to settle, then refresh
                try? await Task.sleep(nanoseconds: 500_000_000)
                refreshEngineMemory()

            } catch {
                await MainActor.run {
                    PerformanceMonitor.shared.recordError(error.localizedDescription)
                }
                addLog("TTS Error: \(error.localizedDescription)", level: .error)
            }

            await MainActor.run {
                isSynthesizing = false
            }
        }
    }

    private func actionButton(icon: String, title: String, description: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.bodySmall)
                    .foregroundColor(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.labelSmall)
                        .foregroundColor(Theme.current.foreground)

                    Text(description)
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()
            }
            .padding(Spacing.sm)
            .background(Color.secondary.opacity(Opacity.subtle))
            .cornerRadius(CornerRadius.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func envColor(_ env: TalkieEnvironment) -> Color {
        switch env {
        case .production: return .green
        case .staging: return .orange
        case .dev: return .purple
        }
    }

    private func shortPath(_ path: String) -> String {
        // Show only last 2 components
        let components = path.split(separator: "/")
        if components.count > 2 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }

    private func startAutoRefresh() {
        guard autoRefresh else { return }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                ServiceManager.shared.scan()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - External Data Audit Section

    private var externalDataAuditSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("EXTERNAL DATA AUDIT")
                .font(.techLabel)
                .foregroundColor(Theme.current.foregroundSecondary)

            VStack(spacing: Spacing.xs) {
                // Run Audit
                actionButton(
                    icon: "magnifyingglass",
                    title: "Run External Data Audit",
                    description: "Scan for orphaned audio files and missing references",
                    color: .blue
                ) {
                    Task {
                        do {
                            addLog("Starting external data audit...", level: .info)
                            let results = try await auditor.performAudit()
                            addLog("Audit complete: \(results.coreDataOrphanedFiles.count) CoreData orphans, \(results.grdbOrphanedFiles.count) GRDB orphans", level: .success)
                            showingAuditResults = true
                        } catch {
                            addLog("Audit failed: \(error.localizedDescription)", level: .error)
                        }
                    }
                }

                // Show Results
                if let results = auditor.auditResults {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Last Audit:")
                                .font(.labelSmall)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Text(results.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.techLabelSmall)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Spacer()

                            if results.hasIssues {
                                Text("Issues Found")
                                    .font(.techLabelSmall)
                                    .foregroundColor(.orange)
                            } else {
                                Text("All Clear")
                                    .font(.techLabelSmall)
                                    .foregroundColor(.green)
                            }
                        }

                        // Quick stats
                        HStack(spacing: Spacing.sm) {
                            statView(
                                label: "CoreData Orphans",
                                value: "\(results.coreDataOrphanedFiles.count)",
                                color: results.coreDataOrphanedFiles.isEmpty ? .green : .orange
                            )

                            statView(
                                label: "GRDB Orphans",
                                value: "\(results.grdbOrphanedFiles.count)",
                                color: results.grdbOrphanedFiles.isEmpty ? .green : .orange
                            )

                            statView(
                                label: "Total Storage",
                                value: ByteCountFormatter.string(fromByteCount: results.totalStorageBytes, countStyle: .file),
                                color: .blue
                            )
                        }

                        // Cleanup button
                        if results.hasIssues {
                            Button(action: {
                                Task {
                                    do {
                                        addLog("Cleaning up orphaned files...", level: .info)
                                        let (cdDeleted, grdbDeleted, bytesFreed) = try await auditor.cleanupOrphanedFiles()
                                        addLog("Cleanup complete: Deleted \(cdDeleted + grdbDeleted) files, freed \(ByteCountFormatter.string(fromByteCount: bytesFreed, countStyle: .file))", level: .success)
                                        // Re-run audit
                                        _ = try await auditor.performAudit()
                                    } catch {
                                        addLog("Cleanup failed: \(error.localizedDescription)", level: .error)
                                    }
                                }
                            }) {
                                HStack(spacing: Spacing.xxs) {
                                    Image(systemName: "trash.fill")
                                        .font(.labelSmall)
                                    Text("Clean Up Orphaned Files")
                                        .font(.labelSmall)
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xxs)
                                .background(Color.orange.opacity(Opacity.light))
                                .cornerRadius(CornerRadius.xs)
                            }
                            .buttonStyle(.plain)
                        }

                        // View details button
                        Button(action: {
                            showingAuditResults = true
                        }) {
                            Text("View Full Report")
                                .font(.techLabelSmall)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Spacing.sm)
                    .background(Color.secondary.opacity(Opacity.subtle))
                    .cornerRadius(CornerRadius.xs)
                }
            }
        }
        .sheet(isPresented: $showingAuditResults) {
            if let results = auditor.auditResults {
                AuditResultsView(results: results, auditor: auditor)
            }
        }
    }

    private func statView(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(.system(size: 8, weight: .regular))
                .foregroundColor(Theme.current.foregroundSecondary)
            Text(value)
                .font(.labelMedium)
                .foregroundColor(color)
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("ACTIVITY LOG")
                    .font(.techLabel)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button(action: { logs.removeAll() }) {
                    Text("Clear")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(logs.prefix(10)) { log in
                    HStack(spacing: Spacing.xs) {
                        Text(timeString(log.timestamp))
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .frame(width: 50, alignment: .leading)

                        Circle()
                            .fill(log.level.color)
                            .frame(width: 4, height: 4)

                        Text(log.message)
                            .font(.labelSmall)
                            .foregroundColor(log.level.color)
                            .lineLimit(2)

                        Spacer()
                    }
                    .padding(.vertical, Spacing.xxs)
                }
            }
            .padding(Spacing.sm)
            .background(Color.secondary.opacity(Opacity.subtle))
            .cornerRadius(CornerRadius.xs)
        }
    }

    // MARK: - Process Management

    private func killProcess(_ process: DiscoveredProcess) {
        let success = serviceManager.kill(pid: process.pid)

        if success {
            addLog("Terminated \(process.name) PID \(process.pid) (\(process.modeDescription))", level: .success)

            // Wait a moment for process to fully terminate before rescanning
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                serviceManager.scan()
            }
        } else {
            addLog("Failed to terminate PID \(process.pid)", level: .error)
        }
    }

    private func stopDaemon(_ process: DiscoveredProcess) {
        let success = serviceManager.stopDaemon(for: process)

        if success {
            addLog("Stopped \(process.name) daemon (\(process.environment?.rawValue ?? "unknown"))", level: .success)
        } else {
            addLog("Failed to stop \(process.name) daemon", level: .error)
        }
    }

    private func restartDaemon(_ process: DiscoveredProcess) {
        // Use launchctl kickstart -k for atomic restart
        let success = serviceManager.restartDaemon(for: process)

        if success {
            addLog("Restarted \(process.name) daemon (\(process.environment?.rawValue ?? "unknown"))", level: .success)
        } else {
            addLog("Failed to restart \(process.name) daemon", level: .error)
        }
    }

    private func addLog(_ message: String, level: LogEntry.LogLevel) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        logs.insert(entry, at: 0)

        // Keep only last 50 entries
        if logs.count > 50 {
            logs = Array(logs.prefix(50))
        }

        NSLog("[DevControl] \(message)")
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    DevControlPanelView()
        .frame(width: 600, height: 700)
}
#endif
