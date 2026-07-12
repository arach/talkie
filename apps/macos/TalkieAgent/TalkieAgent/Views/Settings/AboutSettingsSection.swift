//
//  AboutSettingsSection.swift
//  TalkieAgent
//
//  About settings: version info, diagnostics, support
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - About Settings Section

struct AboutSettingsSection: View {
    @ObservedObject private var engineClient = EngineClient.shared
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var launchAgentStatus: LaunchAgentStatus = .checking

    // Report submission state
    @State private var showReportSheet = false
    @State private var reportDescription = ""
    @State private var reportState: ReportState = .idle

    fileprivate enum ReportState: Equatable {
        case idle
        case submitting
        case success(id: String)
        case error(message: String)
    }

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

    private var launchAgentLabel: String {
        TalkieEnvironment.current.liveBundleId
    }

    private var launchAgentPlistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    private enum LaunchAgentStatus {
        case checking
        case loaded
        case notLoaded
        case notInstalled

        var label: String {
            switch self {
            case .checking: return "Checking..."
            case .loaded: return "Loaded (KeepAlive)"
            case .notLoaded: return "Not Loaded"
            case .notInstalled: return "Not Installed"
            }
        }

        var color: Color {
            switch self {
            case .checking: return .secondary
            case .loaded: return SemanticColor.success
            case .notLoaded: return SemanticColor.warning
            case .notInstalled: return SemanticColor.error
            }
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
        for _ in 0..<8 {
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
                    AboutInfoRow(label: "Talkie Agent", value: "v\(appVersion) (\(buildNumber))")
                    AboutInfoRow(label: "Process ID", value: String(ProcessInfo.processInfo.processIdentifier), isMonospaced: true)
                    AboutInfoRow(label: "Bundle ID", value: bundleID, isMonospaced: true)
                    AboutInfoRow(label: "Build", value: buildTypeLabel, valueColor: buildTypeColor)

                    Divider()
                        .background(AgentTheme.border.opacity(0.5))

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
                            .foregroundColor(AgentTheme.textTertiary)
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

            // Launch Agent Status
            SettingsCard(title: "LAUNCH AGENT") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Status")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AgentTheme.textTertiary)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(launchAgentStatus.color)
                                .frame(width: 8, height: 8)
                            Text(launchAgentStatus.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(launchAgentStatus.color)
                        }
                    }

                    AboutInfoRow(label: "Label", value: launchAgentLabel, isMonospaced: true)
                }
            }
            .onAppear {
                checkLaunchAgentStatus()
            }

            // Permissions (read-only glance; click-through to grant flow)
            SettingsCard(title: "PERMISSIONS") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(PermissionType.allCases) { permission in
                        AboutPermissionRow(
                            permission: permission,
                            status: permissionManager.status(for: permission),
                            onTap: { permissionManager.handleRequest(for: permission) }
                        )
                    }
                }
            }
            .onAppear {
                permissionManager.refreshAll()
            }

            // Support
            SettingsCard(title: "SUPPORT") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("If you need help or want to report an issue, please include the information above.")
                            .font(.system(size: 10))
                            .foregroundColor(AgentTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }

                    HStack(spacing: Spacing.sm) {
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

                        Button(action: { showReportSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 10))
                                Text("Submit Report")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(CornerRadius.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $showReportSheet) {
                ReportSubmissionSheet(
                    description: $reportDescription,
                    state: $reportState,
                    onSubmit: submitReport,
                    onDismiss: {
                        showReportSheet = false
                        // Reset state after dismissal
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            reportDescription = ""
                            reportState = .idle
                        }
                    }
                )
            }
        }
    }

    private func copyDiagnostics() {
        var diagnostics = """
        Talkie Agent Diagnostics
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

    private func submitReport() {
        reportState = .submitting

        Task {
            do {
                let description = reportDescription.isEmpty ? nil : reportDescription
                let response = try await TalkieReporter.shared.submit(source: .live, userDescription: description)

                await MainActor.run {
                    if response.success, let id = response.id {
                        reportState = .success(id: id)
                    } else {
                        reportState = .error(message: response.error ?? "Unknown error")
                    }
                }
            } catch {
                await MainActor.run {
                    reportState = .error(message: error.localizedDescription)
                }
            }
        }
    }

    private func checkLaunchAgentStatus() {
        // Check if plist exists
        guard FileManager.default.fileExists(atPath: launchAgentPlistPath) else {
            launchAgentStatus = .notInstalled
            return
        }

        // Check if loaded using launchctl list
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", launchAgentLabel]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                launchAgentStatus = .loaded
            } else {
                launchAgentStatus = .notLoaded
            }
        } catch {
            launchAgentStatus = .notLoaded
        }
    }

}

// MARK: - About Permission Row

struct AboutPermissionRow: View {
    let permission: PermissionType
    let status: PermissionStatus
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: permission.icon)
                .font(.system(size: 11))
                .foregroundColor(AgentTheme.textSecondary)
                .frame(width: 16, alignment: .center)

            Text(permission.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AgentTheme.textTertiary)

            if !permission.isRequired {
                Text("Optional")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(AgentTheme.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.05))
                    )
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(status.color)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AgentTheme.textMuted.opacity(isHovered ? 1.0 : 0.4))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onTap)
        .help(permission.description)
    }
}

// MARK: - About Info Row

struct AboutInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = AgentTheme.textPrimary
    var isMonospaced: Bool = false
    var canCopy: Bool = false

    @State private var showCopied = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AgentTheme.textTertiary)
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
                            .foregroundColor(showCopied ? SemanticColor.success : AgentTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Report Submission Sheet

private struct ReportSubmissionSheet: View {
    @Binding var description: String
    @Binding var state: AboutSettingsSection.ReportState
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Submit Report")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AgentTheme.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AgentTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Divider()
                .background(AgentTheme.border)

            // Content
            VStack(alignment: .leading, spacing: Spacing.md) {
                switch state {
                case .idle, .submitting:
                    idleContent
                case .success(let id):
                    successContent(id: id)
                case .error(let message):
                    errorContent(message: message)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(width: 360)
        .background(AgentTheme.surface)
    }

    @ViewBuilder
    private var idleContent: some View {
        Text("This will send diagnostic information to help troubleshoot issues. No personal data is included.")
            .font(.system(size: 11))
            .foregroundColor(AgentTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("What's happening? (optional)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AgentTheme.textTertiary)

            TextEditor(text: $description)
                .font(.system(size: 11))
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .background(AgentTheme.surfaceCard)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(AgentTheme.border, lineWidth: 1)
                )
        }

        HStack {
            Spacer()
            Button(action: onDismiss) {
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AgentTheme.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(AgentTheme.surfaceCard)
                    .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)

            Button(action: onSubmit) {
                HStack(spacing: 6) {
                    if state == .submitting {
                        BrailleSpinner(size: 12)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                    }
                    Text(state == .submitting ? "Sending..." : "Send Report")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.orange)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
            .disabled(state == .submitting)
        }
    }

    @ViewBuilder
    private func successContent(id: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(SemanticColor.success)

            Text("Report Submitted")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AgentTheme.textPrimary)

            Text("Reference ID:")
                .font(.system(size: 10))
                .foregroundColor(AgentTheme.textTertiary)

            HStack(spacing: 6) {
                Text(id)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(AgentTheme.textPrimary)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(id, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(AgentTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(AgentTheme.surfaceCard)
            .cornerRadius(CornerRadius.sm)

            Text("Include this ID if you contact support.")
                .font(.system(size: 10))
                .foregroundColor(AgentTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)

        HStack {
            Spacer()
            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(SemanticColor.success)
                    .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func errorContent(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(SemanticColor.error)

            Text("Submission Failed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AgentTheme.textPrimary)

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(AgentTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)

        HStack {
            Spacer()
            Button(action: onDismiss) {
                Text("Close")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AgentTheme.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(AgentTheme.surfaceCard)
                    .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)

            Button(action: onSubmit) {
                Text("Try Again")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.orange)
                    .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
        }
    }
}
