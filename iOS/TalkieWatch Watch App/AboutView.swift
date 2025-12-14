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

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // App icon and name
                VStack(spacing: 4) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)

                    Text("Talkie")
                        .font(.system(size: 16, weight: .semibold))

                    Text("v\(appVersion) (\(buildNumber))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Build badges
                HStack(spacing: 6) {
                    Badge(
                        text: isDebugBuild ? "DEBUG" : "RELEASE",
                        color: isDebugBuild ? .orange : .green
                    )

                    #if DEBUG
                    Badge(text: "DEV", color: .blue)
                    #else
                    Badge(text: "PROD", color: .purple)
                    #endif
                }

                // Snapshot time
                VStack(spacing: 2) {
                    Text("Built")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(snapshotTime)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .padding(.top, 4)

                Divider()
                    .padding(.vertical, 4)

                // Diagnostics
                VStack(spacing: 8) {
                    DiagnosticRow(
                        icon: "iphone",
                        label: "iPhone",
                        value: sessionManager.isReachable ? "Connected" : "Not reachable",
                        color: sessionManager.isReachable ? .green : .orange
                    )

                    DiagnosticRow(
                        icon: "doc.text",
                        label: "Memos",
                        value: "\(sessionManager.recentMemos.count)",
                        color: .blue
                    )

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
                }

                #if DEBUG
                Divider()
                    .padding(.vertical, 4)

                // Logs section (debug only)
                Button(action: { showLogs.toggle() }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("View Logs")
                        Spacer()
                        Image(systemName: showLogs ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                if showLogs {
                    LogsView()
                }
                #endif
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

// MARK: - Diagnostic Row

struct DiagnosticRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
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
