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
    @ObservedObject private var monitor = TalkieServiceMonitor.shared
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
        .background(settings.tacticalBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .stroke(settings.tacticalBackground, lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TALKIE SERVICE")
                    .font(.techLabel)
                    .foregroundColor(.primary)

                Text(monitor.state.rawValue)
                    .font(.techLabelSmall)
                    .foregroundColor(statusColor)
            }

            Spacer()

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
        HStack(spacing: Spacing.xs) {
            if monitor.state == .running {
                Button(action: { monitor.restart() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(settings.fontSM)
                }
                .buttonStyle(.plain)
                .foregroundColor(.orange)
                .help("Restart Talkie Service")

                Button(action: { monitor.terminate() }) {
                    Image(systemName: "stop.fill")
                        .font(settings.fontSM)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Stop Talkie Service")
            } else if monitor.state == .stopped {
                Button(action: { monitor.launch() }) {
                    Image(systemName: "play.fill")
                        .font(settings.fontSM)
                }
                .buttonStyle(.plain)
                .foregroundColor(.green)
                .help("Start Talkie Service")
            }

            Button(action: { showLogs.toggle() }) {
                Image(systemName: showLogs ? "chevron.down" : "chevron.right")
                    .font(settings.fontXS)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help(showLogs ? "Hide logs" : "Show logs")
        }
    }

    // MARK: - Status Panel

    private var statusPanel: some View {
        HStack(spacing: Spacing.lg) {
            // PID
            statItem(
                label: "PID",
                value: monitor.processId.map { "\($0)" } ?? "—"
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
        .background(settings.surfaceAlternate.opacity(0.3))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(spacing: 0) {
            // Logs header
            HStack {
                Text("LOGS")
                    .font(.techLabelSmall)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(monitor.logs.count)")
                    .font(.monoXSmall)
                    .foregroundColor(.secondary)

                Button(action: { monitor.clearLogs() }) {
                    Image(systemName: "trash")
                        .font(settings.fontXS)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Clear logs")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(settings.surfaceAlternate.opacity(0.5))

            // Log list
            if monitor.logs.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No logs yet")
                        .font(settings.fontSM)
                        .foregroundColor(.secondary)

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
                    .foregroundColor(.secondary)
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Compact Status Badge

/// A compact badge for showing Talkie Service status in other views
struct TalkieServiceStatusBadge: View {
    @ObservedObject private var monitor = TalkieServiceMonitor.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text("Service")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.1))
        .cornerRadius(4)
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
