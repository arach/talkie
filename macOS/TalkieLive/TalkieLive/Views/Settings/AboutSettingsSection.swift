//
//  AboutSettingsSection.swift
//  TalkieLive
//
//  About settings: version info, diagnostics, support
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - About Settings Section

struct AboutSettingsSection: View {
    @ObservedObject private var engineClient = EngineClient.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var appPath: String {
        Bundle.main.bundlePath
    }

    private var isProductionRelease: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    private var isInstalledLocation: Bool {
        appPath.hasPrefix("/Applications")
    }

    private var buildTypeLabel: String {
        if isProductionRelease && isInstalledLocation {
            return "Production"
        } else if isProductionRelease {
            return "Release"
        } else {
            return "Debug"
        }
    }

    private var buildTypeColor: Color {
        if isProductionRelease && isInstalledLocation {
            return SemanticColor.success
        } else {
            return SemanticColor.warning
        }
    }

    /// Git branch (debug builds only, reads from working tree)
    private var gitBranch: String? {
        #if DEBUG
        // Find .git directory by walking up from bundle location
        guard let gitDir = Self.findGitDirectory() else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        task.currentDirectoryURL = gitDir

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !branch.isEmpty {
                return branch
            }
        } catch {}
        return nil
        #else
        return nil
        #endif
    }

    /// Walk up from bundle location to find .git directory
    private static func findGitDirectory() -> URL? {
        var url = Bundle.main.bundleURL
        for _ in 0..<8 {  // Walk up max 8 levels (DerivedData can be deep)
            url = url.deletingLastPathComponent()
            let gitPath = url.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitPath.path) {
                return url
            }
        }
        return nil
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "info.circle",
                title: "ABOUT",
                subtitle: "Version information and system diagnostics."
            )
        } content: {
            // App Info (consolidated)
            SettingsCard(title: "APPLICATION") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    AboutInfoRow(label: "Talkie Live", value: "v\(appVersion) (\(buildNumber))")
                    AboutInfoRow(label: "Process ID", value: String(ProcessInfo.processInfo.processIdentifier), isMonospaced: true)
                    AboutInfoRow(label: "Bundle ID", value: bundleID, isMonospaced: true)
                    AboutInfoRow(label: "Build", value: buildTypeLabel, valueColor: buildTypeColor)

                    Divider()
                        .background(TalkieTheme.border.opacity(0.5))

                    AboutInfoRow(label: "Path", value: appPath, isMonospaced: true, canCopy: true)
                    AboutInfoRow(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                }
            }

            // Engine Status
            SettingsCard(title: "TALKIE ENGINE") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Status")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TalkieTheme.textTertiary)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(engineClient.isConnected ? SemanticColor.success : SemanticColor.error)
                                .frame(width: 8, height: 8)
                            Text(engineClient.isConnected ? "Connected" : "Not Running")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(engineClient.isConnected ? SemanticColor.success : SemanticColor.error)
                        }
                    }

                    if engineClient.isConnected, let status = engineClient.status {
                        AboutInfoRow(label: "Engine PID", value: String(status.pid), isMonospaced: true)
                        AboutInfoRow(label: "Bundle", value: status.bundleId, isMonospaced: true)
                    }
                }
            }

            // Support
            SettingsCard(title: "SUPPORT") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("If you need help or want to report an issue, please include the information above.")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }

                    Button(action: copyDiagnostics) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10))
                            Text("Copy Diagnostics")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func copyDiagnostics() {
        var diagnostics = """
        Talkie Live Diagnostics
        =======================
        Version: \(appVersion) (\(buildNumber))
        PID: \(ProcessInfo.processInfo.processIdentifier)
        Bundle ID: \(bundleID)
        Build: \(buildTypeLabel)
        Path: \(appPath)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)

        TalkieEngine:
        """

        if engineClient.isConnected, let status = engineClient.status {
            diagnostics += """

            Status: Connected
            Engine PID: \(status.pid)
            Engine Bundle: \(status.bundleId)
            """
        } else {
            diagnostics += "\nStatus: Not Connected"
            if let error = engineClient.lastError {
                diagnostics += "\nLast Error: \(error)"
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }
}

// MARK: - About Info Row

struct AboutInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .white
    var isMonospaced: Bool = false
    var canCopy: Bool = false

    @State private var showCopied = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)
            Spacer()
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: isMonospaced ? .monospaced : .default))
                    .foregroundColor(valueColor.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if canCopy {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            showCopied = false
                        }
                    }) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(showCopied ? SemanticColor.success : TalkieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
