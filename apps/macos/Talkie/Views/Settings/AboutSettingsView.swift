//
//  AboutSettingsView.swift
//  Talkie macOS
//
//  Combined app info, version, and permissions view
//  Consolidates: Debug Info + Permissions
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct AboutSettingsView: View {
    private let permissionsManager = PermissionsManager.shared
    private let settings = SettingsManager.shared
    private var memosVM: MemosViewModel { MemosViewModel.shared }

    @State private var showCopiedToast = false

    private var environment: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var systemInfo: String {
        let processInfo = ProcessInfo.processInfo
        return "macOS \(processInfo.operatingSystemVersionString)"
    }

    private var chipInfo: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    private var grantedPermissionsCount: Int {
        return [
            permissionsManager.microphoneStatus == .granted,
            permissionsManager.accessibilityStatus == .granted
        ].filter { $0 }.count
    }

    private var totalPermissionsCount: Int {
        2
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "info.circle",
                title: "ABOUT",
                subtitle: "App information, system details, and permissions."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // App Info Section
                appInfoSection

                // Update Section
                updateSection

                // System Section
                systemSection

                // Permissions Section
                permissionsSection

                // Agent Permissions Section (queried via XPC)
                agentPermissionsSection

                // Support Section
                supportSection
            }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                copiedToast
            }
        }
        .onAppear {
            log.debug("AboutSettingsView appeared")
        }
    }

    // MARK: - App Info Section

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: .cyan)

                Text("APP INFORMATION")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                // Environment badge
                Text(environment.uppercased())
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(environment == "Development" ? Color.orange : Color.green)
                    .cornerRadius(CornerRadius.xs)
            }

            VStack(spacing: Spacing.sm) {
                infoRow(label: "Version", value: "\(version) (\(build))", icon: "number")
                infoRow(label: "Bundle ID", value: bundleID, icon: "app.badge")
                infoRow(label: "Settings Config", value: settings.settingsConfigurationPath, icon: "slider.horizontal.3")
                infoRow(label: "Workflow Config", value: settings.workflowControlPlaneConfigPath, icon: "wand.and.stars")
                infoRow(label: "Context Rules Config", value: ContextRuleStore.shared.displayPath, icon: "app.badge.checkmark")
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Update Section

    @ObservedObject private var updateChecker = UpdateChecker.shared

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: updateChecker.availableUpdate != nil ? .orange : .green)

                Text("UPDATES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if updateChecker.isChecking {
                    BrailleSpinner(size: 10)
                } else if let update = updateChecker.availableUpdate {
                    Text("v\(update.version) available")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.orange)
                }
            }

            if let update = updateChecker.availableUpdate {
                // Update available
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if !update.releaseNotes.isEmpty {
                        Text(String(update.releaseNotes.prefix(200)) + (update.releaseNotes.count > 200 ? "..." : ""))
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .lineLimit(3)
                    }

                    HStack(spacing: Spacing.sm) {
                        Button("Download Update") {
                            updateChecker.downloadUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("View Release") {
                            updateChecker.viewReleasePage()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button("Skip") {
                            updateChecker.skipCurrentUpdate()
                        }
                        .buttonStyle(.plain)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
            } else {
                // Up to date or checking
                HStack(spacing: Spacing.sm) {
                    if !updateChecker.isChecking {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.green)
                        Text("You're up to date")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Button {
                        Task { await updateChecker.check() }
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            Text("Check Now")
                                .font(Theme.current.fontXS)
                        }
                        .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(updateChecker.isChecking)
                }
            }

            if let error = updateChecker.lastError {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: .purple)

                Text("SYSTEM")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }

            VStack(spacing: Spacing.sm) {
                infoRow(label: "Operating System", value: systemInfo, icon: "desktopcomputer")
                infoRow(label: "Processor", value: chipInfo, icon: "cpu")
                infoRow(label: "Voice Memos", value: "\(memosVM.totalCount)", icon: "doc.text")
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: grantedPermissionsCount == totalPermissionsCount ? .green : .orange)

                Text("PERMISSIONS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                HStack(spacing: Spacing.xxs) {
                    Circle()
                        .fill(grantedPermissionsCount == totalPermissionsCount ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text("\(grantedPermissionsCount)/\(totalPermissionsCount) GRANTED")
                        .font(.techLabelSmall)
                        .foregroundColor(grantedPermissionsCount == totalPermissionsCount ? .green : .orange)
                }
            }

            VStack(spacing: Spacing.sm) {
                SettingsPermissionRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    description: "Voice memos and recordings",
                    status: permissionsManager.microphoneStatus,
                    onRequest: {
                        if permissionsManager.microphoneStatus == .notDetermined {
                            permissionsManager.requestMicrophonePermission()
                        } else {
                            permissionsManager.openMicrophoneSettings()
                        }
                    }
                )

                SettingsPermissionRow(
                    icon: "accessibility",
                    name: "Accessibility",
                    description: "Auto-paste after dictation",
                    status: permissionsManager.accessibilityStatus,
                    onRequest: {
                        permissionsManager.requestAccessibilityPermission()
                    }
                )

            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Agent Permissions Section

    private var agentState: AgentServiceState { ServiceManager.shared.live }

    private var agentHasPermissionSnapshot: Bool {
        agentState.hasMicrophonePermission != nil || agentState.hasAccessibilityPermission != nil
    }

    private var agentPermissionStatus: (mic: PermissionStatus, ax: PermissionStatus) {
        let mic: PermissionStatus = agentState.hasMicrophonePermission.map { $0 ? .granted : .denied } ?? .unknown
        let ax: PermissionStatus = agentState.hasAccessibilityPermission.map { $0 ? .granted : .denied } ?? .unknown
        return (mic, ax)
    }

    private var agentGrantedCount: Int {
        let s = agentPermissionStatus
        return (s.mic == .granted ? 1 : 0) + (s.ax == .granted ? 1 : 0)
    }

    private var agentPermissionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: agentAccentColor)

                Text("AGENT PERMISSIONS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                HStack(spacing: Spacing.xxs) {
                    Circle()
                        .fill(agentAccentColor)
                        .frame(width: 6, height: 6)
                    Text(agentStatusLabel)
                        .font(.techLabelSmall)
                        .foregroundColor(agentAccentColor)
                }
            }

            if agentState.isXPCConnected || agentHasPermissionSnapshot {
                let s = agentPermissionStatus
                VStack(spacing: Spacing.sm) {
                    SettingsPermissionRow(
                        icon: "mic.fill",
                        name: "Microphone",
                        description: "Hotkey recording and live dictation",
                        status: s.mic,
                        onRequest: { permissionsManager.requestAgentMicrophonePermission() }
                    )

                    SettingsPermissionRow(
                        icon: "accessibility",
                        name: "Accessibility",
                        description: "Direct text insertion after transcription",
                        status: s.ax,
                        onRequest: { permissionsManager.requestAgentAccessibilityPermission() }
                    )

                    if !agentState.isXPCConnected {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(agentSnapshotDetail)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Spacer()
                            if !agentState.isRunning {
                                Button("Launch Agent") {
                                    ServiceManager.shared.launchLive(resolvingConflicts: true)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.xs)
                    }
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text("Talkie Agent permissions will appear here when the helper is available. This section no longer follows transient connection churn.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Spacer()
                    if !agentState.isRunning {
                        Button("Launch Agent") {
                            ServiceManager.shared.launchLive(resolvingConflicts: true)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.xs)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var agentAccentColor: Color {
        if agentState.isXPCConnected {
            return agentGrantedCount == 2 ? .green : .orange
        }
        if agentHasPermissionSnapshot {
            return Theme.current.foregroundMuted
        }
        return .gray
    }

    private var agentStatusLabel: String {
        if agentState.isXPCConnected {
            return "\(agentGrantedCount)/2 GRANTED"
        }
        if agentHasPermissionSnapshot {
            return "LAST KNOWN"
        }
        return agentState.isRunning ? "STARTING" : "UNAVAILABLE"
    }

    private var agentSnapshotDetail: String {
        if let lastCheck = agentState.lastPermissionCheck {
            return "Showing the last known Agent permission snapshot from \(TalkieDate.relativeCompact(lastCheck))."
        }
        return "Showing the last known Agent permission snapshot."
    }

    // MARK: - Support Section

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: .blue)

                Text("SUPPORT")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    copyDebugInfo()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                        Text("Copy Debug Info")
                            .font(Theme.current.fontSMMedium)
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Theme.current.divider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Helpers

    private func sectionAccent(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 3, height: 14)
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foregroundMuted)
                .frame(width: 20)

            Text(label)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)

            Spacer()

            Text(value)
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foreground)
                .textSelection(.enabled)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func copyDebugInfo() {
        let info = """
        Talkie Debug Info
        =================
        Version: \(version) (\(build))
        Bundle ID: \(bundleID)
        Environment: \(environment)
        Settings Config: \(settings.settingsConfigurationPath)
        Workflow Config: \(settings.workflowControlPlaneConfigPath)
        Context Rules Config: \(ContextRuleStore.shared.displayPath)

        System
        ------
        OS: \(systemInfo)
        Processor: \(chipInfo)

        Permissions
        -----------
        Microphone: \(permissionsManager.microphoneStatus.displayName)
        Accessibility: \(permissionsManager.accessibilityStatus.displayName)

        Data
        ----
        Voice Memos: \(memosVM.totalCount)
        Last Sync: \(SyncStatusManager.shared.lastSyncAgo)
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)

        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }

    private var copiedToast: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Debug info copied to clipboard")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
        .cornerRadius(CornerRadius.md)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.bottom, Spacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Preview

#Preview {
    AboutSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 600, height: 700)
}
