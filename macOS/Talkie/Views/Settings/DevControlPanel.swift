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
    @State private var discovery = ProcessDiscovery.shared
    @Environment(EngineClient.self) private var engineClient
    @State private var liveMonitor = TalkieLiveStateMonitor.shared

    @State private var autoRefresh = true
    @State private var refreshTimer: Timer?
    @State private var logs: [LogEntry] = []

    // External Data Auditor
    @State private var auditor = ExternalDataAuditor()
    @State private var showingAuditResults = false

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
            VStack(alignment: .leading, spacing: 16) {
                // Connection Status
                connectionStatusSection

                Divider()

                // TalkieEngine Instances
                serviceSection(
                    title: "TalkieEngine Instances",
                    processes: discovery.engineProcesses,
                    serviceName: "TalkieEngine",
                    connectedPID: engineClient.status?.pid
                )

                Divider()

                // TalkieLive Instances
                serviceSection(
                    title: "TalkieLive Instances",
                    processes: discovery.liveProcesses,
                    serviceName: "TalkieLive",
                    connectedPID: liveMonitor.processId ?? discoveredLivePID
                )

                Divider()

                // Quick Actions
                quickActionsSection

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
            discovery.scan()
            startAutoRefresh()
            // Start monitoring to get live connection status and PID
            liveMonitor.startMonitoring()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - Connection Status

    /// Get the PID of the discovered Live process (fallback if liveMonitor.processId is nil)
    private var discoveredLivePID: Int32? {
        // If there's only one Live process, use it
        guard !discovery.liveProcesses.isEmpty else { return nil }

        // Try to match by environment first
        if let env = liveMonitor.connectedMode {
            if let matching = discovery.liveProcesses.first(where: { $0.environment == env }) {
                return matching.pid
            }
        }

        // Otherwise, just use the first one
        return discovery.liveProcesses.first?.pid
    }

    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE CONNECTIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
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
                    isConnected: liveMonitor.isRunning,
                    environment: liveMonitor.connectedMode,
                    pid: liveMonitor.processId ?? discoveredLivePID
                )
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func connectionBadge(title: String, isConnected: Bool, environment: TalkieEnvironment?, pid: Int32?) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    if let env = environment {
                        Text(env.displayName)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(envColor(env))
                    }

                    if let pid = pid {
                        Text(verbatim: "PID \(String(format: "%d", pid))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(8)
        .background(isConnected ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Service Section

    private func serviceSection(title: String, processes: [DiscoveredProcess], serviceName: String, connectedPID: Int32?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(processes.count) instance\(processes.count == 1 ? "" : "s")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if processes.isEmpty {
                Text("No instances found")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
            } else {
                VStack(spacing: 6) {
                    ForEach(processes) { process in
                        processRow(process: process, isConnected: process.pid == connectedPID)
                    }
                }
            }
        }
    }

    private func processRow(process: DiscoveredProcess, isConnected: Bool) -> some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(isConnected ? Color.green : (process.isDaemon ? Color.blue : Color.orange))
                .frame(width: 6, height: 6)

            // Process info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: "PID \(String(format: "%d", process.pid))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)

                    if let env = process.environment {
                        Text(env.displayName)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(envColor(env))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(envColor(env).opacity(0.2))
                            .cornerRadius(3)
                    }

                    Text(process.modeDescription)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(3)

                    if isConnected {
                        Text("CONNECTED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                if let xpcService = process.xpcService {
                    Text("XPC: \(xpcService)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                if let path = process.bundlePath {
                    Text(shortPath(path))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action buttons - different for daemon vs direct launch
            HStack(spacing: 6) {
                if process.isDaemon {
                    // Daemon: show stop/restart buttons
                    Button(action: {
                        stopDaemon(process)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text("Stop")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Stop daemon via launchctl")

                    Button(action: {
                        restartDaemon(process)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Restart")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Restart daemon via launchctl")
                } else {
                    // Direct launch: show kill button
                    Button(action: {
                        killProcess(process)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Terminate PID \(process.pid)")
                }
            }
        }
        .padding(8)
        .background(isConnected ? Color.green.opacity(0.05) : Color.secondary.opacity(0.03))
        .cornerRadius(6)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK ACTIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                // Refresh
                actionButton(
                    icon: "arrow.clockwise",
                    title: "Refresh",
                    description: "Scan for all running instances",
                    color: .blue
                ) {
                    discovery.scan()
                }

                // Kill all daemons
                actionButton(
                    icon: "trash.fill",
                    title: "Kill All Daemons",
                    description: "Stop all launchd-managed instances",
                    color: .orange
                ) {
                    let engineKilled = discovery.killAllDaemons(service: "TalkieEngine")
                    let liveKilled = discovery.killAllDaemons(service: "TalkieLive")
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
                    let engineKilled = discovery.killAllXcode(service: "TalkieEngine")
                    let liveKilled = discovery.killAllXcode(service: "TalkieLive")
                    let total = engineKilled + liveKilled
                    if total > 0 {
                        addLog("Terminated \(total) Xcode instance\(total == 1 ? "" : "s") (Engine: \(engineKilled), Live: \(liveKilled))", level: .success)
                    } else {
                        addLog("No Xcode instances found to terminate", level: .info)
                    }
                }

                // Auto-refresh toggle
                Toggle(isOn: $autoRefresh) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text("Auto-refresh every 3s")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
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

    private func actionButton(icon: String, title: String, description: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak discovery] _ in
            Task { @MainActor in
                discovery?.scan()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - External Data Audit Section

    private var externalDataAuditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXTERNAL DATA AUDIT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Last Audit:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)

                            Text(results.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)

                            Spacer()

                            if results.hasIssues {
                                Text("⚠️ Issues Found")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                            } else {
                                Text("✅ All Clear")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }

                        // Quick stats
                        HStack(spacing: 12) {
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
                                HStack(spacing: 4) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 10))
                                    Text("Clean Up Orphaned Files")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }

                        // View details button
                        Button(action: {
                            showingAuditResults = true
                        }) {
                            Text("View Full Report")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
        .sheet(isPresented: $showingAuditResults) {
            if let results = auditor.auditResults {
                AuditResultsView(results: results)
            }
        }
    }

    private func statView(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTIVITY LOG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { logs.removeAll() }) {
                    Text("Clear")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(logs.prefix(10)) { log in
                    HStack(spacing: 6) {
                        Text(timeString(log.timestamp))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                            .frame(width: 50, alignment: .leading)

                        Circle()
                            .fill(log.level.color)
                            .frame(width: 4, height: 4)

                        Text(log.message)
                            .font(.system(size: 10))
                            .foregroundColor(log.level.color)
                            .lineLimit(2)

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.03))
            .cornerRadius(6)
        }
    }

    // MARK: - Process Management

    private func killProcess(_ process: DiscoveredProcess) {
        let success = discovery.kill(pid: process.pid)

        if success {
            addLog("Terminated \(process.name) PID \(process.pid) (\(process.modeDescription))", level: .success)

            // Wait a moment for process to fully terminate before rescanning
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                discovery.scan()
            }
        } else {
            addLog("Failed to terminate PID \(process.pid)", level: .error)
        }
    }

    private func stopDaemon(_ process: DiscoveredProcess) {
        let success = discovery.stopDaemon(for: process)

        if success {
            addLog("Stopped \(process.name) daemon (\(process.environment?.rawValue ?? "unknown"))", level: .success)
        } else {
            addLog("Failed to stop \(process.name) daemon", level: .error)
        }
    }

    private func restartDaemon(_ process: DiscoveredProcess) {
        // Stop first
        let stopSuccess = discovery.stopDaemon(for: process)

        if stopSuccess {
            addLog("Stopped \(process.name) daemon", level: .info)

            // Wait a moment before starting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let startSuccess = discovery.startDaemon(for: process)

                if startSuccess {
                    addLog("Restarted \(process.name) daemon (\(process.environment?.rawValue ?? "unknown"))", level: .success)
                } else {
                    addLog("Failed to restart \(process.name) daemon", level: .error)
                }
            }
        } else {
            addLog("Failed to stop \(process.name) daemon for restart", level: .error)
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
