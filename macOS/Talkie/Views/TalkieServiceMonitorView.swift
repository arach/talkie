//
//  TalkieServiceMonitorView.swift
//  Talkie macOS
//
//  Displays TalkieEngine (Talkie Service) status and logs.
//  The Talkie Service is the background XPC service that handles
//  transcription via Whisper models.
//

import SwiftUI

struct TalkieServiceMonitorView: View {
    private let monitor = ServiceManager.shared.engine
    private let settings = SettingsManager.shared

    @State private var showLogs = true
    @State private var logFilter: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header

            Divider()
                .opacity(0.5)

            // Status panel
            statusPanel

            Divider()
                .opacity(0.5)

            // Logs section
            if showLogs {
                logsSection
            }
        }
        .background(Theme.current.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            // Icon with status indicator
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Theme.current.background, lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TALKIE SERVICE")
                    .font(.techLabel)
                    .foregroundColor(Theme.current.foreground)

                Text(monitor.state.rawValue)
                    .font(.techLabelSmall)
                    .foregroundColor(statusColor)
            }

            Spacer()

            // Quick Open button
            Button(action: openInFinder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                    Text("Quick Open")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Theme.current.foregroundSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.current.surface1.opacity(0.5))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Open TalkieEngine.app in Finder")

            // Control buttons
            controlButtons
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Theme.current.surface1)
    }

    private var statusColor: Color {
        switch monitor.state {
        case .running: return .green
        case .stopped: return .red
        case .launching, .terminating: return .orange
        case .unknown: return .gray
        }
    }

    private var controlButtons: some View {
        HStack(spacing: Spacing.sm) {
            if monitor.state == .running {
                // Restart button
                Button(action: { Task { await monitor.restart() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                        Text("Restart")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Restart Talkie Service")

                // Stop button
                Button(action: { monitor.terminate() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text("Stop")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Stop Talkie Service")
            } else if monitor.state == .stopped {
                // Start button
                Button(action: { Task { await monitor.launch() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text("Start")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Start Talkie Service")
            }

            Divider()
                .frame(height: 16)

            // Logs toggle
            Button(action: { showLogs.toggle() }) {
                Image(systemName: showLogs ? "chevron.down" : "chevron.right")
                    .font(settings.fontXS)
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.current.foregroundSecondary)
            .help(showLogs ? "Hide logs" : "Show logs")
        }
    }

    private func openInFinder() {
        // Open TalkieEngine.app in Finder
        let appPath = "/Applications/TalkieEngine.app"
        if FileManager.default.fileExists(atPath: appPath) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appPath)
        } else {
            // Try to find it in the build products
            let debugPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            NSWorkspace.shared.open(debugPath)
        }
    }

    // MARK: - Status Panel

    private var statusPanel: some View {
        HStack(spacing: Spacing.lg) {
            // PID
            statItem(
                label: "PID",
                value: monitor.processId.map { String(format: "%d", $0) } ?? "—"
            )

            Divider()
                .frame(height: 30)

            // CPU
            statItem(
                label: "CPU",
                value: String(format: "%.1f%%", monitor.cpuUsage)
            )

            Divider()
                .frame(height: 30)

            // Memory
            statItem(
                label: "MEM",
                value: monitor.formattedMemory
            )

            Divider()
                .frame(height: 30)

            // Uptime
            statItem(
                label: "UPTIME",
                value: monitor.state == .running ? monitor.formattedUptime : "—"
            )

            Spacer()

            // Error indicator
            if let error = monitor.lastError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(settings.fontXS)
                        .foregroundColor(.red)

                    Text(error)
                        .font(settings.fontXS)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.surfaceAlternate.opacity(0.3))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.current.foreground)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(spacing: 0) {
            // Logs header
            HStack {
                Text("LOGS")
                    .font(.techLabelSmall)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text("\(monitor.logs.count)")
                    .font(.monoXSmall)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Button(action: { monitor.clearLogs() }) {
                    Image(systemName: "trash")
                        .font(settings.fontXS)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundSecondary)
                .help("Clear logs")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(Theme.current.surfaceAlternate.opacity(0.5))

            // Log list
            if monitor.logs.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No logs yet")
                        .font(settings.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if monitor.state != .running {
                        Text("Start Talkie Service to see logs")
                            .font(settings.fontXS)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, Spacing.xl)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(monitor.logs) { entry in
                            TalkieServiceLogRow(entry: entry)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
    }
}

// MARK: - Log Row

struct TalkieServiceLogRow: View {
    let entry: TalkieServiceLogEntry
    private let settings = SettingsManager.shared

    // Static cached formatter - avoid recreating on every render
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    @State private var isExpanded = false

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .fault: return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: Spacing.xs) {
                // Timestamp
                Text(formatTime(entry.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 70, alignment: .leading)

                // Level badge
                Text(entry.level.rawValue)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(levelColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(levelColor.opacity(0.15))
                    .cornerRadius(3)

                // Category
                Text(entry.category)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(1)

                // Message
                Text(entry.message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(entry.level == .error || entry.level == .fault ? levelColor : .primary.opacity(0.9))
                    .lineLimit(isExpanded ? nil : 1)

                Spacer()
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}

// MARK: - Compact Status Badge

/// A compact badge for showing Talkie Service status in other views
struct TalkieServiceStatusBadge: View {
    private let monitor = ServiceManager.shared.engine

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text("Service")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.1))
        .cornerRadius(CornerRadius.xs)
        .onAppear {
            // One-time check without starting full monitoring
            monitor.refreshState()
        }
    }

    private var statusColor: Color {
        switch monitor.state {
        case .running: return .green
        case .stopped: return .red
        case .launching, .terminating: return .orange
        case .unknown: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    TalkieServiceMonitorView()
        .frame(width: 500, height: 600)
}
