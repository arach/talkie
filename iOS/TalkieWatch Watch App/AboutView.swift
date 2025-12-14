//
//  AboutView.swift
//  TalkieWatch
//
//  Diagnostics and version info
//

import SwiftUI
import WatchKit

struct AboutView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @State private var showLogs = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var snapshotTime: String {
        guard let executableURL = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let modDate = attributes[.modificationDate] as? Date else {
            return "Unknown"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: modDate)
    }

    // Computed status properties
    private var pendingCount: Int {
        sessionManager.recentMemos.filter { $0.status == .sending }.count
    }

    private var allSynced: Bool {
        pendingCount == 0
    }

    private var systemHealthy: Bool {
        sessionManager.isReachable && allSynced
    }

    private var deviceMemory: String {
        let processInfo = ProcessInfo.processInfo
        let totalMemory = processInfo.physicalMemory
        let memoryMB = Double(totalMemory) / 1024 / 1024
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", memoryMB / 1024)
        }
        return String(format: "%.0f MB", memoryMB)
    }

    private var statusDetail: String {
        if systemHealthy {
            return "SYSTEMS NOMINAL"
        } else if !sessionManager.isReachable && pendingCount > 0 {
            return "QUEUED • AWAITING LINK"
        } else if !sessionManager.isReachable {
            return "LINK STANDBY"
        } else {
            return "TRANSMITTING \(pendingCount)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // System Status
                VStack(spacing: 6) {
                    // Header with checkmark/warning
                    HStack {
                        Text("STATUS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.3))

                        Spacer()

                        Image(systemName: systemHealthy ? "checkmark" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(systemHealthy ? .green : .orange)
                    }

                    // Status rows
                    StatusRow(
                        label: "iPhone",
                        value: sessionManager.isReachable ? "connected" : "waiting",
                        isGood: sessionManager.isReachable
                    )

                    StatusRow(
                        label: "Recordings",
                        value: allSynced ? "all sent" : "\(pendingCount) queued",
                        isGood: allSynced
                    )

                    StatusRow(
                        label: "Memory",
                        value: deviceMemory,
                        isGood: true
                    )
                }

                #if DEBUG
                Divider()
                    .padding(.vertical, 2)

                // Logs section (debug only - moved up)
                Button(action: { showLogs.toggle() }) {
                    HStack {
                        Text("LOGS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.3))
                        Spacer()
                        Image(systemName: showLogs ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)

                if showLogs {
                    LogsView()
                }
                #endif

                Divider()
                    .padding(.vertical, 4)

                // App info
                VStack(spacing: 4) {
                    Text("TALKIE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white)

                    Text("v\(appVersion)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                #if DEBUG
                // Build info (debug only)
                HStack(spacing: 6) {
                    Badge(text: "DEBUG", color: .orange)
                    Badge(text: snapshotTime, color: .blue)
                }
                #endif

                Divider()
                    .padding(.vertical, 4)

                // Device info
                VStack(spacing: 6) {
                    let device = WKInterfaceDevice.current()
                    DiagnosticRow(
                        icon: "applewatch",
                        label: "Model",
                        value: device.model,
                        color: .secondary
                    )

                    DiagnosticRow(
                        icon: "gear",
                        label: "watchOS",
                        value: device.systemVersion,
                        color: .secondary
                    )

                    DiagnosticRow(
                        icon: "doc.text",
                        label: "Recent",
                        value: "\(sessionManager.recentMemos.count) memos",
                        color: .secondary
                    )
                }
            }
            .padding()
        }
        .navigationTitle("About")
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Quick Record CTA (TalkieLive-style sliver)

struct QuickRecordCTA: View {
    let action: () -> Void
    @State private var isExpanded = false
    @State private var pulse = false

    var body: some View {
        Button(action: handleTap) {
            if isExpanded {
                // Expanded: show record button
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .scaleEffect(pulse ? 1.2 : 0.9)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true),
                            value: pulse
                        )

                    Text("GO")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.8))
                .clipShape(Capsule())
            } else {
                // Sliver: minimal gray bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 32, height: 3)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private func handleTap() {
        if isExpanded {
            // Second tap: start recording
            action()
            isExpanded = false
        } else {
            // First tap: expand
            isExpanded = true
            pulse = true

            // Auto-collapse after 3 seconds if not tapped
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    isExpanded = false
                    pulse = false
                }
            }
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    let label: String
    let value: String
    let isGood: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isGood ? Color.green : Color.orange)
                .frame(width: 4, height: 4)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(isGood ? .green : .orange)
        }
    }
}

// MARK: - Diagnostic Row

struct DiagnosticRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 16)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.4))

            Spacer()

            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Logs View

#if DEBUG
struct LogsView: View {
    @State private var logs: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if logs.isEmpty {
                Text("No logs yet")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                ForEach(logs.suffix(10), id: \.self) { log in
                    Text(log)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .onAppear {
            loadLogs()
        }
    }

    private func loadLogs() {
        // In a real implementation, this would read from WatchLogger
        logs = [
            "Session activated",
            "Reachable: true",
            "Ready for recording"
        ]
    }
}
#endif

#Preview {
    AboutView()
        .environmentObject(WatchSessionManager.shared)
}
