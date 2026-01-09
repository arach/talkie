//
//  ServerSettingsView.swift
//  Talkie macOS
//
//  Settings view for TalkieServer - the unified server process running Bridge + Gateway modules
//

import SwiftUI
import TalkieKit

struct ServerSettingsView: View {
    @State private var bridgeManager = BridgeManager.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "server.rack",
                title: "TALKIE SERVER",
                subtitle: "Local server providing Bridge and Gateway modules."
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                // Tailscale Status (required for server)
                TailscaleStatusSection(status: bridgeManager.tailscaleStatus)

                Divider()

                // Server Process Status
                ServerProcessSection(
                    status: bridgeManager.bridgeStatus,
                    errorMessage: bridgeManager.errorMessage,
                    tailscaleReady: bridgeManager.tailscaleStatus.isReady,
                    onStart: { Task { await bridgeManager.startBridge() } },
                    onStop: { Task { await bridgeManager.stopBridge() } },
                    onRestart: { Task { await bridgeManager.restartBridge() } }
                )

                // Loaded Modules
                if bridgeManager.bridgeStatus == .running {
                    Divider()
                    LoadedModulesSection()

                    Divider()
                    ServerLogsSection()
                }

                Divider()
                    .padding(.vertical, 4)

                // Info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("TalkieServer runs Bridge (iOS connectivity) and Gateway (external APIs) as modules. Both require Tailscale for secure networking.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .onAppear {
            bridgeManager.checkStatus()
        }
    }
}

// MARK: - Server Process Section

private struct ServerProcessSection: View {
    let status: BridgeManager.BridgeStatus
    let errorMessage: String?
    let tailscaleReady: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("PROCESS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 12) {
                // Status indicator
                Image(systemName: status.icon)
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)
                    .frame(width: 40, height: 40)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.rawValue)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(statusDescription)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                // Controls
                HStack(spacing: 8) {
                    if status == .running {
                        Button(action: onRestart) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(Theme.current.fontXS)
                                Text("RESTART")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: onStop) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(Theme.current.fontXS)
                                Text("STOP")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    } else if status == .stopped {
                        Button(action: onStart) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(Theme.current.fontXS)
                                Text("START")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!tailscaleReady)
                    } else if status == .error {
                        Button(action: onRestart) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(Theme.current.fontXS)
                                Text("FORCE RESTART")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    } else if status == .starting {
                        BrailleSpinner(speed: 0.08)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)
        }
    }

    private var statusColor: Color {
        switch status {
        case .stopped: return .gray
        case .starting: return .orange
        case .running: return .green
        case .error: return .red
        }
    }

    private var statusDescription: String {
        switch status {
        case .stopped: return "Server is not running"
        case .starting: return "Starting server..."
        case .running: return "Port 8765 • Bridge + Gateway loaded"
        case .error: return errorMessage ?? "Server encountered an error"
        }
    }
}

// MARK: - Loaded Modules Section

private struct LoadedModulesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("LOADED MODULES")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 8) {
                // Bridge Module
                ModuleCard(
                    name: "Bridge",
                    icon: "iphone.gen3.radiowaves.left.and.right",
                    description: "iOS connectivity",
                    isLoaded: true
                )

                // Gateway Module
                ModuleCard(
                    name: "Gateway",
                    icon: "arrow.up.arrow.down.circle",
                    description: "External APIs",
                    isLoaded: true
                )
            }
        }
    }
}

private struct ModuleCard: View {
    let name: String
    let icon: String
    let description: String
    let isLoaded: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isLoaded ? .green : .gray)
                .frame(width: 28, height: 28)
                .background((isLoaded ? Color.green : Color.gray).opacity(0.15))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text(description)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            Image(systemName: isLoaded ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 12))
                .foregroundColor(isLoaded ? .green : .gray)
        }
        .padding(10)
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }
}

// MARK: - Tailscale Status Section (copied from BridgeSettingsView)

private struct TailscaleStatusSection: View {
    let status: BridgeManager.TailscaleStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "network")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("TAILSCALE")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)
                    .frame(width: 40, height: 40)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(status.message)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                actionButton
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)
        }
    }

    private var statusIcon: String {
        switch status {
        case .notInstalled: return "xmark.circle.fill"
        case .notRunning: return "pause.circle.fill"
        case .needsLogin: return "person.crop.circle.badge.exclamationmark"
        case .offline: return "wifi.slash"
        case .noPeers: return "checkmark.circle.fill"
        case .ready: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .notInstalled, .notRunning: return .red
        case .needsLogin, .offline: return .orange
        case .noPeers, .ready: return .green
        }
    }

    private var statusTitle: String {
        switch status {
        case .notInstalled: return "Not Installed"
        case .notRunning: return "Not Running"
        case .needsLogin: return "Login Required"
        case .offline: return "Offline"
        case .noPeers: return "Connected"
        case .ready: return "Ready"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .notInstalled:
            Button(action: openTailscaleDownload) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(Theme.current.fontXS)
                    Text("INSTALL")
                        .font(Theme.current.fontXSMedium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .notRunning:
            Button(action: openTailscale) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(Theme.current.fontXS)
                    Text("OPEN")
                        .font(Theme.current.fontXSMedium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .needsLogin(let authUrl):
            Button(action: { openAuthUrl(authUrl) }) {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(Theme.current.fontXS)
                    Text("LOGIN")
                        .font(Theme.current.fontXSMedium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .offline:
            EmptyView()

        case .noPeers:
            Text("Set up Tailscale on iPhone")
                .font(Theme.current.fontXS)
                .foregroundColor(.orange)

        case .ready:
            EmptyView()
        }
    }

    private func openTailscaleDownload() {
        if let url = URL(string: "https://tailscale.com/download/mac") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openTailscale() {
        let tailscaleURL = URL(fileURLWithPath: "/Applications/Tailscale.app")
        NSWorkspace.shared.openApplication(at: tailscaleURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openAuthUrl(_ authUrl: String?) {
        if let urlString = authUrl, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            openTailscale()
        }
    }
}

// MARK: - Server Logs Section

private struct ServerLogsSection: View {
    @State private var logEntries: [ServerLogEntry] = []
    @State private var isAutoRefresh = true
    @State private var showDevLogs = false
    @State private var commandKeyHeld = false
    @State private var expandedEntries: Set<UUID> = []
    @State private var eventMonitor: Any?

    private let mainLogFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Talkie/Bridge/bridge.log")
    private let devLogFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Talkie/Bridge/bridge.dev.log")
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("LOGS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Toggle(isOn: $showDevLogs) {
                    Text("API")
                        .font(.system(size: 9, weight: .medium))
                }
                .toggleStyle(.button)
                .controlSize(.mini)
                .help("Show API response logs")

                Toggle("Auto", isOn: $isAutoRefresh)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()

                Button(action: loadLogs) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundSecondary)
            }

            if !logEntries.isEmpty && logEntries.contains(where: { $0.jsonDetail != nil }) {
                HStack(spacing: 4) {
                    Image(systemName: "command")
                        .font(.system(size: 8))
                    Text("Hold to expand all JSON")
                        .font(.system(size: 9))
                }
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if logEntries.isEmpty {
                        Text("No logs yet...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(logEntries) { entry in
                                ServerLogEntryRow(
                                    entry: entry,
                                    isExpanded: commandKeyHeld || expandedEntries.contains(entry.id),
                                    onToggle: {
                                        if expandedEntries.contains(entry.id) {
                                            expandedEntries.remove(entry.id)
                                        } else {
                                            expandedEntries.insert(entry.id)
                                        }
                                    }
                                )
                            }
                        }
                        .id("logBottom")
                    }
                }
                .frame(height: 180)
                .padding(8)
                .background(Color.black.opacity(0.8))
                .cornerRadius(6)
                .onChange(of: logEntries.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            loadLogs()
            setupCommandKeyMonitor()
        }
        .onDisappear {
            removeCommandKeyMonitor()
        }
        .onChange(of: showDevLogs) { _, _ in
            loadLogs()
        }
        .onReceive(timer) { _ in
            if isAutoRefresh {
                loadLogs()
            }
        }
    }

    private func setupCommandKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            commandKeyHeld = event.modifierFlags.contains(.command)
            return event
        }
    }

    private func removeCommandKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func loadLogs() {
        let logFile = showDevLogs ? devLogFile : mainLogFile
        do {
            let content = try String(contentsOf: logFile, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").suffix(100)
            logEntries = lines.compactMap { parseLine($0) }
        } catch {
            logEntries = []
        }
    }

    private func parseLine(_ line: String) -> ServerLogEntry? {
        guard !line.isEmpty else { return nil }

        let pattern = #"\[([^\]]+)\] \[([^\]]+)\] (.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return ServerLogEntry(timestamp: "", level: "INFO", message: line, jsonDetail: nil)
        }

        let timestamp = String(line[Range(match.range(at: 1), in: line)!])
        let level = String(line[Range(match.range(at: 2), in: line)!])
        let message = String(line[Range(match.range(at: 3), in: line)!])

        var jsonDetail: String? = nil
        if message.contains("[API Response]"), let arrowIndex = message.range(of: "→") {
            let jsonPart = String(message[arrowIndex.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let data = jsonPart.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                jsonDetail = prettyString
            } else {
                jsonDetail = jsonPart
            }
        }

        let displayTime = formatTime(timestamp)
        return ServerLogEntry(timestamp: displayTime, level: level, message: message, jsonDetail: jsonDetail)
    }

    private func formatTime(_ iso: String) -> String {
        if let tIndex = iso.firstIndex(of: "T"),
           let dotIndex = iso.firstIndex(of: ".") {
            return String(iso[iso.index(after: tIndex)..<dotIndex])
        }
        return iso
    }
}

private struct ServerLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let level: String
    let message: String
    let jsonDetail: String?

    var levelColor: Color {
        switch level {
        case "ERROR": return .red
        case "WARN": return .orange
        case "DEBUG": return .purple
        case "REQ": return .blue
        default: return .green
        }
    }
}

private struct ServerLogEntryRow: View {
    let entry: ServerLogEntry
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if entry.jsonDetail != nil {
                    Button(action: onToggle) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 10)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 10)
                }

                Text(entry.timestamp)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Text(entry.level)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(entry.levelColor)
                    .padding(.horizontal, 3)
                    .background(entry.levelColor.opacity(0.2))
                    .cornerRadius(2)

                Text(truncatedMessage)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()
            }

            if isExpanded, let json = entry.jsonDetail {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(json)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.green.opacity(0.9))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 150)
                .padding(6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
                .padding(.leading, 14)
            }
        }
        .padding(.vertical, 1)
    }

    private var truncatedMessage: String {
        if entry.jsonDetail != nil {
            if let arrowIndex = entry.message.range(of: "→") {
                return String(entry.message[..<arrowIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return entry.message
    }
}

// MARK: - Preview

#Preview {
    ServerSettingsView()
        .frame(width: 500, height: 700)
        .padding()
}
