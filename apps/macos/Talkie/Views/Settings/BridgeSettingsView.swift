//
//  BridgeSettingsView.swift
//  Talkie macOS
//
//  Settings view for managing TalkieBridge (iOS connectivity)
//

import AppKit
import SwiftUI
import CloudKit
import CryptoKit
import CoreImage.CIFilterBuiltins
import TalkieKit

private let bridgeSettingsLog = Log(.system)

struct BridgeSettingsView: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var showingQRSheet = false
    @State private var isRefreshing = false
    @State private var showingInstallConfirmation = false

    var body: some View {
        SettingsPageContainer {
            HStack {
                SettingsPageHeader(
                    icon: "iphone.gen3.radiowaves.left.and.right",
                    title: "iOS BRIDGE",
                    subtitle: "Connect your iPhone to view Claude Code sessions remotely."
                )
                Spacer()
                Button(action: refresh) {
                    Group {
                        if isRefreshing {
                            BrailleSpinner(speed: 0.08)
                                .font(.system(size: 12))
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                // Prerequisites Check (show if something is missing)
                if let prereqs = bridgeManager.prerequisiteStatus, !prereqs.isReady {
                    PrerequisiteStatusSection(
                        status: prereqs,
                        isInstalling: bridgeManager.isInstallingDependencies,
                        onInstallDependencies: { showingInstallConfirmation = true },
                        onOpenBridgeDocs: { bridgeManager.openBridgeSetupDocs() },
                        onOpenTailscaleDocs: { bridgeManager.openTailscaleSetupDocs() }
                    )

                    Divider()
                }

                // Tailscale Status
                TailscaleStatusSection(status: bridgeManager.tailscaleStatus)

                Divider()

                // Bridge Server Status
                BridgeServerSection(
                    status: bridgeManager.bridgeStatus,
                    onStart: { Task { await bridgeManager.enableAndStartBridge() } },
                    onStop: { Task { await bridgeManager.stopBridge() } },
                    onRestart: { Task { await bridgeManager.restartBridge() } },
                    onShowQR: { showingQRSheet = true }
                )

                Divider()

                SSHAccessSection()

                Divider()

                WorkflowControlPlaneSection()

                // Pending Pairings
                if !bridgeManager.pendingPairings.isEmpty {
                    Divider()
                    PendingPairingsSection(
                        pairings: bridgeManager.pendingPairings,
                        onApprove: { id in Task { await bridgeManager.approvePairing(id) } },
                        onReject: { id in Task { await bridgeManager.rejectPairing(id) } }
                    )
                }

                // Paired Devices
                if !bridgeManager.pairedDevices.isEmpty {
                    Divider()
                    PairedDevicesSection(devices: bridgeManager.pairedDevices)
                }

                // Logs (show when bridge is running)
                if bridgeManager.bridgeStatus == .running {
                    Divider()
                    BridgeLogsSection()

                    Divider()
                    BridgeMessageQueueSection()
                }

                Divider()
                    .padding(.vertical, 4)

                // Info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("The iOS Bridge accepts nearby local-network devices and trusted Tailscale devices. Sensitive actions still require Talkie pairing and request signing.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .sheet(isPresented: $showingQRSheet) {
            QRCodeSheet()
        }
        .onChange(of: showingQRSheet) { _, isShowing in
            guard !isShowing else { return }
            bridgeManager.checkStatus()
        }
        .alert("Install Dependencies", isPresented: $showingInstallConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Install") {
                Task {
                    let result = await bridgeManager.installDependencies()
                    if case .success = result {
                        // Dependencies installed, status will update automatically
                    }
                }
            }
        } message: {
            Text("This will run 'bun install' to download the required packages for TalkieServer:\n\n• elysia (HTTP server)\n• @elysiajs/cors (cross-origin handling)\n• tweetnacl (encryption)\n\nThese packages are installed locally and don't affect your system.")
        }
        .onAppear {
            bridgeManager.checkStatus()
        }
    }

    private func refresh() {
        isRefreshing = true
        bridgeManager.checkStatus()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            isRefreshing = false
        }
    }
}

private struct WorkflowControlPlaneSection: View {
    @State private var settings = SettingsManager.shared
    @State private var auth = AuthManager.shared
    @State private var workflowControlPlane = WorkflowControlPlaneService.shared

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("LIVE WORKFLOWS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text(workflowControlPlane.state.rawValue.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(4)
            }

            Text("Let this Mac register with your Talkie account and claim queued live workflows. When it is idle, it only checks in every \(idlePollIntervalLabel).")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $settings.workflowControlPlaneEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Workflow Executor")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text("This Mac can register itself as an executor and claim eligible workflow runs for your account.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(.teal)
            .padding(10)
            .background(Theme.current.surface1)
            .cornerRadius(8)

            if settings.workflowControlPlaneEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Button(action: { applyConfiguration(reason: "manual_refresh") }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9))
                                Text("WAKE NOW")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.teal.opacity(0.12))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!auth.isSignedIn)

                        Text(auth.isSignedIn ? "Executor is ready to check for queued runs." : "Sign into Talkie on this Mac to arm the executor.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        statusRow(title: "Account", value: auth.isSignedIn ? (auth.user?.email ?? "Signed In") : "Signed Out")
                        statusRow(title: "Device ID", value: settings.workflowControlPlaneDeviceId)
                        statusRow(title: "Idle Poll", value: idlePollIntervalLabel)
                        statusRow(title: "Config", value: settings.workflowControlPlaneConfigPath)
                        statusRow(title: "Last Poll", value: lastPollLabel)

                        if let activeRunId = workflowControlPlane.activeRunId {
                            statusRow(title: "Active Run", value: activeRunId)
                        }

                        if let activeWorkflowName = workflowControlPlane.activeWorkflowName {
                            statusRow(title: "Workflow", value: activeWorkflowName)
                        }
                    }
                    .padding(10)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)

                    if let lastErrorMessage = workflowControlPlane.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(Theme.current.fontXS)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .onAppear {
            settings.reloadWorkflowControlPlaneConfiguration()
            applyConfiguration(reason: "settings_appear")
        }
        .onChange(of: settings.workflowControlPlaneEnabled) { _, _ in
            applyConfiguration(reason: "settings_toggle")
        }
    }

    private var statusColor: Color {
        switch workflowControlPlane.state {
        case .disabled:
            return .gray
        case .signedOut:
            return .orange
        case .armed, .polling:
            return .blue
        case .executing:
            return .green
        case .error:
            return .red
        }
    }

    private var idlePollIntervalLabel: String {
        let intervalSeconds = max(60, settings.workflowControlPlaneIdlePollInterval)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = intervalSeconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: intervalSeconds) ?? "\(Int(intervalSeconds))s"
    }

    private var lastPollLabel: String {
        guard let lastPollAt = workflowControlPlane.lastPollAt else {
            return "Never"
        }
        return lastPollAt.formatted(date: .omitted, time: .shortened)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.current.foreground)
                .textSelection(.enabled)
        }
    }

    private func applyConfiguration(reason: String) {
        workflowControlPlane.stop(reason: "settings_update")

        guard settings.workflowControlPlaneEnabled else {
            workflowControlPlane.wake(reason: reason)
            return
        }

        workflowControlPlane.startIfNeeded()
        workflowControlPlane.wake(reason: reason)
    }
}

// MARK: - Prerequisite Status Section

private struct PrerequisiteStatusSection: View {
    let status: BridgeManager.PrerequisiteStatus
    let isInstalling: Bool
    let onInstallDependencies: () -> Void
    let onOpenBridgeDocs: () -> Void
    let onOpenTailscaleDocs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.orange)
                Text("SETUP REQUIRED")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(.orange)
            }

            // Status card
            VStack(alignment: .leading, spacing: 12) {
                // Missing items list
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(status.missingItems, id: \.self) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                            Text(item)
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foreground)
                        }
                    }
                }

                // Action buttons based on what's missing
                VStack(alignment: .leading, spacing: 8) {
                    // Bun not installed
                    if !status.bunInstalled {
                        HStack(spacing: 8) {
                            Button(action: openBunInstall) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(Theme.current.fontXS)
                                    Text("INSTALL BUN")
                                        .font(Theme.current.fontXSMedium)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button(action: onOpenBridgeDocs) {
                                Text("Learn more")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Dependencies not installed (but Bun is available)
                    if status.needsDependencyInstall {
                        HStack(spacing: 8) {
                            Button(action: onInstallDependencies) {
                                HStack(spacing: 4) {
                                    if isInstalling {
                                        BrailleSpinner(size: 10)
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(Theme.current.fontXS)
                                    }
                                    Text(isInstalling ? "INSTALLING..." : "INSTALL DEPENDENCIES")
                                        .font(Theme.current.fontXSMedium)
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(isInstalling)

                            Button(action: onOpenBridgeDocs) {
                                Text("What gets installed?")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Tailscale not installed
                    if !status.tailscaleInstalled {
                        HStack(spacing: 8) {
                            Button(action: openTailscaleDownload) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(Theme.current.fontXS)
                                    Text("INSTALL TAILSCALE")
                                        .font(Theme.current.fontXSMedium)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button(action: onOpenTailscaleDocs) {
                                Text("Setup guide")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func openBunInstall() {
        if let url = URL(string: "https://bun.sh") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openTailscaleDownload() {
        if let url = URL(string: "https://tailscale.com/download/mac") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Tailscale Status Section

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
                // Status indicator
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

                // Action button based on status
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
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macos")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macsys") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        openTailscaleDownload()
    }

    private func openAuthUrl(_ authUrl: String?) {
        if let urlString = authUrl, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            openTailscale()
        }
    }
}

// MARK: - Bridge Server Section

private struct BridgeServerSection: View {
    let status: BridgeManager.BridgeStatus
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onShowQR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("BRIDGE SERVER")
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
                        Button(action: onShowQR) {
                            HStack(spacing: 4) {
                                Image(systemName: "qrcode")
                                    .font(Theme.current.fontXS)
                                Text("PAIR")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

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
                    } else if status == .error {
                        // Force restart when in error state (kills stray processes)
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
        case .stopped: return "Bridge is not running"
        case .starting: return "Starting bridge server..."
        case .running: return "Listening on port 8765"
        case .error: return "Bridge encountered an error"
        }
    }
}

// MARK: - Pending Pairings Section

private struct PendingPairingsSection: View {
    let pairings: [BridgeManager.PendingPairing]
    let onApprove: (String) -> Void
    let onReject: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.orange)
                Text("PENDING PAIRINGS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(.orange)
            }

            ForEach(pairings) { pairing in
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pairing.name)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("Wants to connect")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Button(action: { onReject(pairing.deviceId) }) {
                            Image(systemName: "xmark")
                                .font(Theme.current.fontSM)
                                .foregroundColor(.red)
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { onApprove(pairing.deviceId) }) {
                            Image(systemName: "checkmark")
                                .font(Theme.current.fontSM)
                                .foregroundColor(.green)
                                .frame(width: 28, height: 28)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Mac Bridge Devices Section

private struct PairedDevicesSection: View {
    let devices: [BridgeManager.PairedDevice]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.green)
                Text("MAC BRIDGE DEVICES")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            ForEach(devices) { device in
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                        .frame(width: 36, height: 36)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("Paired \(formatDate(device.pairedAt))")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(Theme.current.fontSM)
                        .foregroundColor(.green)
                }
                .padding(10)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
        }
    }

    private func formatDate(_ isoString: String) -> String {
        guard let date = TalkieDate.fromISO8601(isoString) else {
            return isoString
        }
        return TalkieDate.relativeCompact(date)
    }
}

// MARK: - SSH Access Section

private struct SSHAccessSection: View {
    @State private var status = SSHKeyQRCodeProvisioner.Status.unconfigured
    @State private var remoteLoginStatus = SSHRemoteLoginStatus.unknown
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showingPairingGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "key.horizontal.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("TERMINAL ACCESS")
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

                    Text(statusMessage)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let fingerprint = status.fingerprint {
                        Text(fingerprint)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { showingPairingGuide = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "iphone.and.arrow.forward")
                                .font(Theme.current.fontXS)
                            Text("SET UP TERMINAL")
                                .font(Theme.current.fontXSMedium)
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button(action: refreshStatus) {
                        Group {
                            if isRefreshing {
                                BrailleSpinner(size: 10)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                            }
                        }
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    statusBadge(title: "KEY", isReady: status.hasKeyPair)
                    statusBadge(title: "AUTHORIZED", isReady: status.isAuthorized)
                    statusBadge(title: "REMOTE LOGIN", isReady: remoteLoginStatus.isEnabled)
                }

                Text("Talkie can create a dedicated SSH key, authorize it on this Mac, open the right Sharing panel, and give you a QR code to scan on your iPhone.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("SSH key: \(displayPath(status.keyURL))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.current.fontXS)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 4)
        }
        .task {
            ensureTalkieServerEnabledForPairing()
            refreshStatus()
        }
        .sheet(isPresented: $showingPairingGuide) {
            SSHPhonePairingGuideSheet()
        }
    }

    private var statusIcon: String {
        if status.isReady, remoteLoginStatus.isEnabled {
            return "checkmark.circle.fill"
        }
        if status.isReady || remoteLoginStatus.isEnabled {
            return "iphone.and.arrow.forward"
        }
        if status.hasKeyPair || status.isAuthorized {
            return "exclamationmark.triangle.fill"
        }
        return "key"
    }

    private var statusColor: Color {
        if status.isReady, remoteLoginStatus.isEnabled {
            return .green
        }
        if status.isReady || remoteLoginStatus.isEnabled {
            return .blue
        }
        if status.hasKeyPair || status.isAuthorized {
            return .orange
        }
        return .gray
    }

    private var statusTitle: String {
        if status.isReady, remoteLoginStatus.isEnabled {
            return "Ready to pair your iPhone"
        }
        if status.isReady {
            return "One last step on this Mac"
        }
        if status.hasKeyPair || status.isAuthorized || remoteLoginStatus.isEnabled {
            return "Pairing is in progress"
        }
        return "Not prepared yet"
    }

    private var statusMessage: String {
        if status.isReady, remoteLoginStatus.isEnabled {
            return "Your dedicated Talkie SSH key is ready, Remote Login is on, and the pairing guide can hand the key to your iPhone."
        }
        if status.isReady {
            return "The SSH key is ready. Open the pairing guide to jump straight to Remote Login and the QR import step."
        }
        if status.hasKeyPair {
            return "The key exists, but this Mac still needs the public key authorized or Remote Login enabled."
        }
        if remoteLoginStatus.isEnabled {
            return "Remote Login is already on. Open the pairing guide and let Talkie prepare the dedicated SSH identity."
        }
        return "Start the pairing guide to create the SSH identity, authorize it locally, and scan it into Talkie on iPhone."
    }

    @ViewBuilder
    private func statusBadge(title: String, isReady: Bool) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(isReady ? .green : .orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((isReady ? Color.green : Color.orange).opacity(0.12))
            .cornerRadius(4)
    }

    private func refreshStatus() {
        isRefreshing = true
        do {
            status = try SSHKeyQRCodeProvisioner.status()
            remoteLoginStatus = SSHRemoteLoginStatus.current()
            errorMessage = nil
        } catch {
            status = .unconfigured
            remoteLoginStatus = SSHRemoteLoginStatus.current()
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }

    private func ensureTalkieServerEnabledForPairing() {
        let settings = SettingsManager.shared
        guard !settings.talkieServerEnabled else { return }
        settings.talkieServerEnabled = true
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacing(FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

struct SSHPhonePairingGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var bridgeManager = BridgeManager.shared
    @State private var status = SSHKeyQRCodeProvisioner.Status.unconfigured
    @State private var remoteLoginStatus = SSHRemoteLoginStatus.unknown
    @State private var qrPayload: String?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var showingLargeQRCode = false
    @State private var qrRefreshTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                progressCard
                checklistCard
                securityNote
            }
            .padding(24)
        }
        .frame(width: 720, height: 780)
        .background(Theme.current.background)
        .task {
            await refreshPairingState()
        }
        .onChange(of: bridgeManager.tailscaleStatus) { _, _ in
            refreshStatus()
        }
        .sheet(isPresented: $showingLargeQRCode) {
            SSHKeyQRCodeSheet(
                payload: pairingImportLinkString,
                label: status.label,
                fingerprint: status.fingerprint,
                keyPath: displayPath(status.keyURL)
            )
        }
        .onDisappear {
            qrRefreshTask?.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set Up Terminal Access")
                    .font(.title2.weight(.semibold))

                Text("Use this 3-step checklist to prepare this Mac, turn on Remote Login, and import terminal access into Talkie on your iPhone.")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress")
                .font(Theme.current.fontXSMedium)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text(progressHeadline)
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foreground)

            Text(progressMessage)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: Double(macSetupCompletedSteps), total: 2)
                .tint(.blue)

            Text("\(macSetupCompletedSteps) of 2 Mac setup steps complete")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(14)
        .background(Theme.current.surface1)
        .cornerRadius(12)
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            checklistStepRow(
                number: 1,
                title: "Prepare this Mac",
                state: prepareStepState,
                summary: "Create the dedicated Talkie SSH key and authorize it in `~/.ssh/authorized_keys`."
            ) {
                HStack(spacing: 10) {
                    Button(action: prepareSSHAccess) {
                        HStack(spacing: 4) {
                            if isPreparing {
                                BrailleSpinner(size: 10)
                            } else {
                                Image(systemName: status.isReady ? "arrow.clockwise" : "wand.and.stars")
                                    .font(Theme.current.fontXS)
                            }
                            Text(isPreparing ? "PREPARING..." : (status.isReady ? "REFRESH ACCESS" : "PREPARE ACCESS"))
                                .font(Theme.current.fontXSMedium)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparing)

                    Button(action: refreshStatus) {
                        Text("Recheck")
                            .font(Theme.current.fontXSMedium)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparing)
                }

                DisclosureGroup("Technical details") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Private key: \(displayPath(status.keyURL))")
                        Text("Authorized keys: \(displayPath(status.authorizedKeysURL))")

                        if let fingerprint = status.fingerprint {
                            Text("Fingerprint: \(fingerprint)")
                                .textSelection(.enabled)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.top, 6)
                }
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
            }

            Divider()
                .padding(.leading, 40)

            checklistStepRow(
                number: 2,
                title: "Turn on Remote Login",
                state: remoteLoginStepState,
                summary: remoteLoginStatus.isEnabled
                    ? "Remote Login is already enabled on this Mac."
                    : "Open Sharing settings, then enable Remote Login in macOS."
            ) {
                HStack(spacing: 10) {
                    Button(action: openRemoteLoginSettings) {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape.2")
                                .font(Theme.current.fontXS)
                            Text("OPEN SHARING SETTINGS")
                                .font(Theme.current.fontXSMedium)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button(action: refreshStatus) {
                        Text("Recheck")
                            .font(Theme.current.fontXSMedium)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .padding(.leading, 40)

            checklistStepRow(
                number: 3,
                title: "On your iPhone, add terminal access",
                state: iphoneImportStepState,
                summary: iphoneImportSummary
            ) {
                if let pairingImportLinkString,
                   let qrImage = QRCodeImageFactory.makeImage(from: pairingImportLinkString, size: 280) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 280, height: 280)
                            .background(Color.white)
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Scan this on your iPhone to add this Mac under Configured terminals in Talkie.")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foreground)

                            Text("Talkie can route this automatically whether you scan from the SSH Terminal flow or a broader Talkie pairing surface.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(iphoneImportMessage)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if let fingerprint = status.fingerprint {
                                Text("Fingerprint: \(fingerprint)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .textSelection(.enabled)
                            }

                            Button(action: { showingLargeQRCode = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "viewfinder")
                                        .font(Theme.current.fontXS)
                                    Text("SHOW LARGE QR")
                                        .font(Theme.current.fontXSMedium)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("The QR appears here as soon as step 1 is finished.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
        }
        .padding(6)
        .background(Theme.current.surface1)
        .cornerRadius(12)
    }

    private var securityNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What Talkie does")
                .font(Theme.current.fontXSMedium)
                .foregroundColor(Theme.current.foreground)

            Text("Talkie uses a dedicated SSH key for the phone terminal instead of reusing your personal key. When iCloud is available, the pairing QR carries an encrypted enrollment blob that only your signed-in devices can unwrap. Without iCloud, pairing still works with the direct local QR path. Talkie still only adds the public key to `authorized_keys` on this Mac, and Remote Login stays under your control in macOS Settings.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.current.fontXS)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func checklistStepRow<Content: View>(
        number: Int,
        title: String,
        state: PairingChecklistState,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(state.tint.opacity(state == .upcoming ? 0.08 : 0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: state.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(state.tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(number). \(title)")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text(state.label.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(state.tint)
                    }

                    Text(summary)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            content()
        }
        .padding(14)
    }

    private var macSetupCompletedSteps: Int {
        (status.isReady ? 1 : 0) + (remoteLoginStatus.isEnabled ? 1 : 0)
    }

    private var progressHeadline: String {
        if !status.isReady {
            return "Next: prepare SSH access on this Mac"
        }
        if !remoteLoginStatus.isEnabled {
            return "Next: turn on Remote Login in macOS"
        }
        return "Mac setup is complete"
    }

    private var progressMessage: String {
        if !status.isReady {
            return "Talkie will create a dedicated SSH key for the phone terminal and authorize it on this Mac."
        }
        if !remoteLoginStatus.isEnabled {
            return "The key is ready. The last Mac step is enabling Remote Login in Sharing settings."
        }
        return "The Mac side is ready. The only thing left is importing this Mac into Talkie on your iPhone."
    }

    private var prepareStepState: PairingChecklistState {
        status.isReady ? .done : .current
    }

    private var remoteLoginStepState: PairingChecklistState {
        if !status.isReady { return .upcoming }
        return remoteLoginStatus.isEnabled ? .done : .current
    }

    private var iphoneImportStepState: PairingChecklistState {
        if !status.isReady || !remoteLoginStatus.isEnabled {
            return .upcoming
        }
        return .current
    }

    private var preferredPairingConnection: SSHKeyQRCodeProvisioner.ConnectionDetails? {
        guard let hostname = preferredSSHConnectionHost else {
            return nil
        }

        return SSHKeyQRCodeProvisioner.ConnectionDetails(
            host: hostname,
            port: 22,
            username: NSUserName(),
            startupProfileRawValue: "cleanShell",
            launcherModeRawValue: "pairedHome",
            autoConnect: true,
            alternateHosts: Array(preferredSSHConnectionHosts.dropFirst())
        )
    }

    private var preferredSSHConnectionHost: String? {
        preferredSSHConnectionHosts.first
    }

    private var preferredSSHConnectionHosts: [String] {
        var candidates: [String?] = []

        if bridgeManager.qrData?.isPairingReady == true {
            candidates.append(bridgeManager.qrData?.hostname)
        }

        candidates.append(localBonjourHostname)
        candidates.append(bridgeManager.tailscaleStatus.hostname)

        var seen: Set<String> = []
        var hosts: [String] = []
        for candidate in candidates {
            let host = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !host.isEmpty,
                  host != "localhost",
                  host != "127.0.0.1",
                  host != "::1",
                  !seen.contains(host.lowercased()) else {
                continue
            }
            seen.insert(host.lowercased())
            hosts.append(host)
        }

        return hosts
    }

    private var localBonjourHostname: String? {
        TalkieNetworkRouteClassifier.localBonjourHostname(from: Host.current().name)
    }

    private func connectionRouteDescription(for host: String) -> String {
        if TalkieNetworkRouteClassifier.isTailscaleHost(host) {
            return "Tailscale"
        }
        return "the local network"
    }

    private var iphoneImportSummary: String {
        if let connection = preferredPairingConnection {
            return "Scan this with your iPhone camera. Talkie will import the key, save \(connection.host), and connect over \(connectionRouteDescription(for: connection.host))."
        }

        return "Scan this with your iPhone camera or inside Talkie. The key will import now, and auto-connect becomes available once this Mac has a local or Tailscale hostname."
    }

    private var iphoneImportMessage: String {
        if let connection = preferredPairingConnection {
            return "If Talkie is already installed, the link opens the app, stores the key, saves \(connection.username)@\(connection.host), and connects you straight into your home terminal over \(connectionRouteDescription(for: connection.host))."
        }

        return "If Talkie is already installed, the link opens the app and stores the key automatically. Finish local or Tailscale setup on this Mac to make the first connection automatic too."
    }

    private func prepareSSHAccess() {
        Task { @MainActor in
            isPreparing = true
            errorMessage = nil

            defer {
                isPreparing = false
            }

            await bridgeManager.refreshNonNetworkStatusNow()

            do {
                ensureTalkieServerEnabledForPairing()
                let prepared = try await SSHKeyQRCodeProvisioner.prepare(connection: preferredPairingConnection)
                status = prepared.status
                remoteLoginStatus = SSHRemoteLoginStatus.current()
                qrPayload = prepared.payload
            } catch {
                errorMessage = error.localizedDescription
                refreshStatus()
            }
        }
    }

    private func refreshPairingState() async {
        await bridgeManager.refreshNonNetworkStatusNow()
        refreshStatus()
    }

    private func refreshStatus() {
        qrRefreshTask?.cancel()

        do {
            status = try SSHKeyQRCodeProvisioner.status()
            remoteLoginStatus = SSHRemoteLoginStatus.current()
            errorMessage = nil

            if status.isReady {
                refreshQRCodePayload()
            } else {
                qrPayload = nil
            }
        } catch {
            status = .unconfigured
            remoteLoginStatus = SSHRemoteLoginStatus.current()
            qrPayload = nil
            errorMessage = error.localizedDescription
        }
    }

    private func refreshQRCodePayload() {
        let connection = preferredPairingConnection
        qrRefreshTask = Task { @MainActor in
            do {
                let prepared = try await SSHKeyQRCodeProvisioner.prepare(connection: connection)
                guard !Task.isCancelled else { return }
                qrPayload = prepared.payload
            } catch {
                guard !Task.isCancelled else { return }
                qrPayload = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func ensureTalkieServerEnabledForPairing() {
        let settings = SettingsManager.shared
        guard !settings.talkieServerEnabled else { return }
        settings.talkieServerEnabled = true
    }

    private var pairingImportLinkString: String? {
        guard let qrPayload else { return nil }

        var components = URLComponents()
        components.scheme = "talkie"
        components.host = "ssh"
        components.path = "/import-key"
        components.queryItems = [
            URLQueryItem(name: "payload", value: qrPayload)
        ]
        return components.url?.absoluteString
    }

    private func openRemoteLoginSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.sharing?Services_RemoteLogin") {
            NSWorkspace.shared.open(url)
            return
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.SystemSettings") {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: settingsURL, configuration: configuration)
        }
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacing(FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

@MainActor
private enum PairingChecklistState: Equatable {
    case done
    case current
    case upcoming

    var label: String {
        switch self {
        case .done: return "Done"
        case .current: return "Do this now"
        case .upcoming: return "Later"
        }
    }

    var symbolName: String {
        switch self {
        case .done: return "checkmark"
        case .current: return "circle.fill"
        case .upcoming: return "circle"
        }
    }

    var tint: Color {
        switch self {
        case .done: return .green
        case .current: return .blue
        case .upcoming: return Theme.current.foregroundSecondary
        }
    }
}

private enum SSHRemoteLoginStatus {
    case enabled
    case disabled
    case unknown

    var isEnabled: Bool {
        if case .enabled = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .enabled:
            "On"
        case .disabled:
            "Off"
        case .unknown:
            "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .enabled:
            .green
        case .disabled:
            .orange
        case .unknown:
            .gray
        }
    }

    var message: String {
        switch self {
        case .enabled:
            return "Remote Login is already responding on port 22. You should be able to connect from your iPhone once the key is imported."
        case .disabled:
            return "Remote Login still needs to be turned on in macOS. We’ll open the exact Sharing page for you."
        case .unknown:
            return "Talkie couldn’t tell whether Remote Login is on. Open Sharing settings and confirm that Remote Login is enabled."
        }
    }

    static func current() -> Self {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-z", "localhost", "22"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? .enabled : .disabled
        } catch {
            return .unknown
        }
    }
}

private enum SSHKeyQRCodeProvisioner {
    struct ConnectionDetails: Encodable {
        let host: String
        let port: Int
        let username: String
        let startupProfileRawValue: String?
        let launcherModeRawValue: String?
        let autoConnect: Bool
        let alternateHosts: [String]
    }

    struct Status {
        let label: String
        let keyURL: URL
        let publicKeyURL: URL
        let authorizedKeysURL: URL
        let hasKeyPair: Bool
        let isAuthorized: Bool
        let fingerprint: String?

        static var unconfigured: Self {
            Self(
                label: SSHKeyQRCodeProvisioner.defaultLabel,
                keyURL: SSHKeyQRCodeProvisioner.keyURL,
                publicKeyURL: SSHKeyQRCodeProvisioner.publicKeyURL,
                authorizedKeysURL: SSHKeyQRCodeProvisioner.authorizedKeysURL,
                hasKeyPair: false,
                isAuthorized: false,
                fingerprint: nil
            )
        }

        var isReady: Bool {
            hasKeyPair && isAuthorized
        }
    }

    struct PreparedKey {
        let status: Status
        let payload: String
    }

    private static let keyFileName = "iphone-terminal-ed25519"
    private static let keyDirectory = URL.applicationSupportDirectory
        .appending(path: "Talkie")
        .appending(path: "SSH")
    fileprivate static let keyURL = keyDirectory.appending(path: keyFileName)
    fileprivate static let publicKeyURL = keyDirectory.appending(path: "\(keyFileName).pub")
    fileprivate static let authorizedKeysURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".ssh")
        .appending(path: "authorized_keys")
    private static let sshDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".ssh")
    private static let remoteHelperDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".talkie-shell")
    private static let remoteHelperBinDirectoryURL = remoteHelperDirectoryURL
        .appending(path: "bin")
    private static let remoteHelperRuntimeDirectoryURL = remoteHelperDirectoryURL
        .appending(path: "runtime")
    private static let remoteHelperRuntimeBinDirectoryURL = remoteHelperRuntimeDirectoryURL
        .appending(path: "bin")
    private static let remoteHelperShellURL = remoteHelperBinDirectoryURL
        .appending(path: "talkie-shell")
    private static let remoteHelperSessionURL = remoteHelperBinDirectoryURL
        .appending(path: "talkie-session")
    private static let remoteHelperLegacyCleanURL = remoteHelperBinDirectoryURL
        .appending(path: "talkie-clean")
    private static let remoteHelperLegacyContextURL = remoteHelperBinDirectoryURL
        .appending(path: "talkie-context")
    private static let remoteHelperEntryURL = remoteHelperBinDirectoryURL
        .appending(path: "talkie-enter")
    private static let remoteHelperMenuURL = remoteHelperBinDirectoryURL
        .appending(path: "talkie-home")
    private static let remoteHelperCompanionExecutableURL = remoteHelperRuntimeBinDirectoryURL
        .appending(path: "talkie-companion")
    private static let remoteHelperCompanionEntrypointURL = remoteHelperRuntimeDirectoryURL
        .appending(path: "lib")
        .appending(path: "node_modules")
        .appending(path: "@talkie")
        .appending(path: "companion")
        .appending(path: "src")
        .appending(path: "index.js")
    private static let remoteHelperShellPath = "$HOME/.talkie-shell/bin:$HOME/.talkie-shell/runtime/bin:$HOME/bin:$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
    private static let remoteHelperToolPath = "/Users/\(NSUserName())/bin:/Users/\(NSUserName())/.local/bin:/Users/\(NSUserName())/.opencode/bin:/Users/\(NSUserName())/.bun/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

    private static var companionPackageURL: URL {
        if let repoRoot = LocalCheckoutLocator.talkieRepositoryRootURL(compileTimeFilePath: #filePath) {
            return repoRoot.appending(path: "companion")
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        return sourceFile
            .deletingLastPathComponent() // BridgeSettingsView.swift -> Settings
            .deletingLastPathComponent() // Settings -> Views
            .deletingLastPathComponent() // Views -> Talkie
            .deletingLastPathComponent() // Talkie -> macOS
            .deletingLastPathComponent() // macOS -> repo root
            .appending(path: "companion")
    }

    fileprivate static var defaultLabel: String {
        "Talkie SSH for \(Host.current().localizedName ?? "This Mac")"
    }

    private static var remoteCompanionBootstrapSnippet: String {
        #"""
TALKIE_COMPANION="$HOME/.talkie-shell/runtime/bin/talkie-companion"
TALKIE_COMPANION_ENTRY="$HOME/.talkie-shell/runtime/lib/node_modules/@talkie/companion/src/index.js"
if [[ -x "$TALKIE_COMPANION" ]]; then
  exec "$TALKIE_COMPANION" __COMMAND__ "$@"
fi
if [[ -f "$TALKIE_COMPANION_ENTRY" ]]; then
  if command -v bun >/dev/null 2>&1; then
    exec "$(command -v bun)" "$TALKIE_COMPANION_ENTRY" __COMMAND__ "$@"
  fi
  if command -v node >/dev/null 2>&1; then
    exec "$(command -v node)" "$TALKIE_COMPANION_ENTRY" __COMMAND__ "$@"
  fi
fi
"""#
    }

    private struct QRPayload: Encodable {
        let `protocol`: String
        let label: String?
        let privateKey: String
        let connection: ConnectionDetails?
    }

    private struct EncryptedQRPayload: Encodable {
        let protocolVersion: String
        let wrapKeyRecordName: String
        let ciphertext: String

        enum CodingKeys: String, CodingKey {
            case protocolVersion = "p"
            case wrapKeyRecordName = "k"
            case ciphertext = "c"
        }
    }

    static func status() throws -> Status {
        let hasPrivateKey = FileManager.default.fileExists(atPath: keyURL.path)
        let hasPublicKey = FileManager.default.fileExists(atPath: publicKeyURL.path)
        let hasKeyPair = hasPrivateKey && hasPublicKey

        let publicKey = hasKeyPair ? try normalizedContents(of: publicKeyURL) : nil
        let isAuthorized = try publicKey.map(isAuthorized(publicKey:)) ?? false
        let fingerprint = hasKeyPair ? try fingerprint(for: publicKeyURL) : nil

        return Status(
            label: defaultLabel,
            keyURL: keyURL,
            publicKeyURL: publicKeyURL,
            authorizedKeysURL: authorizedKeysURL,
            hasKeyPair: hasKeyPair,
            isAuthorized: isAuthorized,
            fingerprint: fingerprint
        )
    }

    static func prepare(connection: ConnectionDetails? = nil) async throws -> PreparedKey {
        try ensureKeyPair()
        let publicKey = try normalizedContents(of: publicKeyURL)
        try ensureAuthorizedKey(publicKey)
        try ensureRemoteHelperInstalled()
        let privateKey = try normalizedContents(of: keyURL)
        let status = try status()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = QRPayload(
            protocol: "talkie-ssh-key-v2",
            label: status.label,
            privateKey: privateKey,
            connection: connection
        )
        let payloadData = try encoder.encode(payload)
        let payloadString: String

        do {
            let wrapKey = try await SSHTerminalPairingWrapKeyStore.shared.getOrCreateWrapKey()
            let sealedBox = try AES.GCM.seal(payloadData, using: SymmetricKey(data: wrapKey.keyData))
            guard let encryptedData = sealedBox.combined else {
                throw SSHKeyProvisioningError.invalidPayload
            }
            let encryptedPayload = EncryptedQRPayload(
                protocolVersion: "talkie-ssh-key-v3",
                wrapKeyRecordName: wrapKey.recordName,
                ciphertext: encryptedData.urlSafeBase64EncodedString()
            )
            let encryptedPayloadData = try encoder.encode(encryptedPayload)
            guard let encodedString = String(data: encryptedPayloadData, encoding: .utf8) else {
                throw SSHKeyProvisioningError.invalidPayload
            }

            payloadString = encodedString
            bridgeSettingsLog.info(
                "Prepared secure SSH pairing payload",
                detail: "record=\(wrapKey.recordName) host=\(connection?.host ?? "none") user=\(connection?.username ?? "none")"
            )
        } catch {
            guard let encodedString = String(data: payloadData, encoding: .utf8) else {
                throw SSHKeyProvisioningError.invalidPayload
            }

            payloadString = encodedString
            bridgeSettingsLog.warning("Falling back to direct SSH pairing payload: \(error.localizedDescription)")
        }

        return PreparedKey(status: status, payload: payloadString)
    }

    private static func ensureKeyPair() throws {
        try ensureDirectoryExists(at: keyDirectory, permissions: 0o700)

        let hasPrivateKey = FileManager.default.fileExists(atPath: keyURL.path)
        let hasPublicKey = FileManager.default.fileExists(atPath: publicKeyURL.path)

        if hasPrivateKey && hasPublicKey {
            try setPermissions(at: keyURL, permissions: 0o600)
            try setPermissions(at: publicKeyURL, permissions: 0o644)
            return
        }

        if hasPrivateKey || hasPublicKey {
            try? FileManager.default.removeItem(at: keyURL)
            try? FileManager.default.removeItem(at: publicKeyURL)
        }

        let comment = "talkie-iphone-\(sanitizedHostToken())"
        _ = try runProcess(
            executablePath: "/usr/bin/ssh-keygen",
            arguments: [
                "-q",
                "-t", "ed25519",
                "-N", "",
                "-C", comment,
                "-f", keyURL.path
            ]
        )

        try setPermissions(at: keyURL, permissions: 0o600)
        try setPermissions(at: publicKeyURL, permissions: 0o644)
    }

    private static func ensureRemoteHelperInstalled() throws {
        try ensureDirectoryExists(at: remoteHelperDirectoryURL, permissions: 0o700)
        try ensureDirectoryExists(at: remoteHelperBinDirectoryURL, permissions: 0o700)
        try ensureDirectoryExists(at: remoteHelperRuntimeDirectoryURL, permissions: 0o700)
        try? installRemoteCompanionIfAvailable()

        let shellScript = #"""
#!/bin/zsh
export PATH="\#(remoteHelperShellPath)"
[[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]] || export TERM="xterm-256color"
[[ -n "${COLORTERM:-}" ]] || export COLORTERM="truecolor"
export TALKIE_SURFACE="${TALKIE_SURFACE:-phone}"
\#(remoteCompanionBootstrapSnippet.replacingOccurrences(of: "__COMMAND__", with: "shell"))
printf '\r\n[Talkie] Remote companion is missing on this Mac. Opening a plain shell.\r\n'
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
"""#

        let sessionScript = #"""
#!/bin/zsh
export PATH="\#(remoteHelperShellPath)"
[[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]] || export TERM="xterm-256color"
[[ -n "${COLORTERM:-}" ]] || export COLORTERM="truecolor"
export TALKIE_SURFACE="${TALKIE_SURFACE:-phone}"
\#(remoteCompanionBootstrapSnippet.replacingOccurrences(of: "__COMMAND__", with: "session"))
printf '\r\n[Talkie] Remote companion is missing on this Mac. Opening a plain shell.\r\n'
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
"""#

        let legacyShellScript = #"""
#!/bin/zsh
HELPER="$HOME/.talkie-shell/bin/talkie-shell"
if [[ -x "$HELPER" ]]; then
  exec "$HELPER" "$@"
fi
printf '\r\n[Talkie] Talkie shell helper is missing on this Mac. Opening a plain shell.\r\n'
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
"""#

        let legacySessionScript = #"""
#!/bin/zsh
HELPER="$HOME/.talkie-shell/bin/talkie-session"
if [[ -x "$HELPER" ]]; then
  exec "$HELPER" "$@"
fi
printf '\r\n[Talkie] Talkie session helper is missing on this Mac. Opening a plain shell.\r\n'
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
"""#

        let entryScript = #"""
#!/bin/zsh
export PATH="\#(remoteHelperShellPath)"
[[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]] || export TERM="xterm-256color"
[[ -n "${COLORTERM:-}" ]] || export COLORTERM="truecolor"
export TALKIE_SURFACE="${TALKIE_SURFACE:-phone}"
\#(remoteCompanionBootstrapSnippet.replacingOccurrences(of: "__COMMAND__", with: "enter"))
printf '\r\n[Talkie] Remote companion is missing on this Mac. Opening a plain shell.\r\n'
ZSH_BIN="$(command -v zsh || printf '/bin/zsh')"
exec "$ZSH_BIN" -il
"""#

        let menuScript = #"""
#!/bin/zsh
export PATH="\#(remoteHelperShellPath)"
[[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]] || export TERM="xterm-256color"
[[ -n "${COLORTERM:-}" ]] || export COLORTERM="truecolor"
export TALKIE_SURFACE="${TALKIE_SURFACE:-phone}"
\#(remoteCompanionBootstrapSnippet.replacingOccurrences(of: "__COMMAND__", with: "menu"))

clear
HOST_LABEL="$(scutil --get ComputerName 2>/dev/null || hostname -s || printf 'your Mac')"
printf 'Welcome to %s\n' "$HOST_LABEL"
printf 'You are in %s\n\n' "$HOME"
printf '1. OpenCode\n'
printf '2. Claude Code\n'
printf '3. Shell\n\n'
printf 'Choose an option and press Return: '
IFS= read -r choice
case "$choice" in
  1)
    if command -v opencode >/dev/null 2>&1; then
      exec opencode
    fi
    printf '\nOpenCode is not installed. Staying in the shell.\n\n'
    ;;
  2)
    if command -v claude >/dev/null 2>&1; then
      exec claude
    fi
    printf '\nClaude Code is not installed. Staying in the shell.\n\n'
    ;;
  3|'')
    printf '\n'
    ;;
  *)
    printf '\nUnknown option. Staying in the shell.\n\n'
    ;;
esac
"""#

        try write(script: shellScript, to: remoteHelperShellURL)
        try write(script: sessionScript, to: remoteHelperSessionURL)
        try write(script: legacyShellScript, to: remoteHelperLegacyCleanURL)
        try write(script: legacySessionScript, to: remoteHelperLegacyContextURL)
        try write(script: entryScript, to: remoteHelperEntryURL)
        try write(script: menuScript, to: remoteHelperMenuURL)
        try setPermissions(at: remoteHelperShellURL, permissions: 0o755)
        try setPermissions(at: remoteHelperSessionURL, permissions: 0o755)
        try setPermissions(at: remoteHelperLegacyCleanURL, permissions: 0o755)
        try setPermissions(at: remoteHelperLegacyContextURL, permissions: 0o755)
        try setPermissions(at: remoteHelperEntryURL, permissions: 0o755)
        try setPermissions(at: remoteHelperMenuURL, permissions: 0o755)
    }

    private static func installRemoteCompanionIfAvailable() throws {
        let packageManifestURL = companionPackageURL.appending(path: "package.json")
        guard FileManager.default.fileExists(atPath: packageManifestURL.path) else {
            return
        }

        guard let npmPath = resolvedCommandPath(named: "npm") else {
            return
        }

        let nodePath = resolvedCommandPath(named: "node")
        let bunPath = resolvedCommandPath(named: "bun")
        let nodeDirectory = nodePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let npmDirectory = URL(fileURLWithPath: npmPath).deletingLastPathComponent().path
        let bunDirectory = bunPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }

        _ = try runProcess(
            executablePath: npmPath,
            arguments: [
                "install",
                "--foreground-scripts",
                "--no-audit",
                "--no-fund",
                "--force",
                "--global",
                "--prefix", remoteHelperRuntimeDirectoryURL.path,
                companionPackageURL.path
            ],
            environment: [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": [
                    bunDirectory,
                    nodeDirectory,
                    npmDirectory,
                    remoteHelperToolPath
                ]
                .compactMap { $0 }
                .joined(separator: ":")
            ]
        )

        guard FileManager.default.fileExists(atPath: remoteHelperCompanionEntrypointURL.path) else {
            return
        }

        if FileManager.default.fileExists(atPath: remoteHelperCompanionExecutableURL.path) {
            try? FileManager.default.removeItem(at: remoteHelperCompanionExecutableURL)
        }

        let bunLaunchLine = if let bunPath {
            #"if [[ -x "\#(bunPath)" ]]; then exec "\#(bunPath)" "\#(remoteHelperCompanionEntrypointURL.path)" "$@"; fi"#
        } else {
            ""
        }

        let wrapperScript = #"""
#!/bin/zsh
\#(bunLaunchLine)
\#(nodePath.map { #"if [[ -x "\#($0)" ]]; then exec "\#($0)" "\#(remoteHelperCompanionEntrypointURL.path)" "$@"; fi"# } ?? "")
printf '\r\n[Talkie] Remote companion runtime is missing on this Mac.\r\n'
exit 1
"""#

        try write(script: wrapperScript, to: remoteHelperCompanionExecutableURL)
        try setPermissions(at: remoteHelperCompanionExecutableURL, permissions: 0o755)
    }

    private static func ensureAuthorizedKey(_ publicKey: String) throws {
        try ensureDirectoryExists(at: sshDirectoryURL, permissions: 0o700)

        let normalizedPublicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var existingLines: [String] = []

        if FileManager.default.fileExists(atPath: authorizedKeysURL.path) {
            existingLines = try String(contentsOf: authorizedKeysURL, encoding: .utf8)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if !existingLines.contains(normalizedPublicKey) {
            existingLines.append(normalizedPublicKey)
            let updatedContents = existingLines.joined(separator: "\n") + "\n"
            try updatedContents.write(to: authorizedKeysURL, atomically: true, encoding: .utf8)
        }

        try setPermissions(at: authorizedKeysURL, permissions: 0o600)
    }

    private static func isAuthorized(publicKey: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: authorizedKeysURL.path) else {
            return false
        }

        let normalizedPublicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorizedLines = try String(contentsOf: authorizedKeysURL, encoding: .utf8)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return authorizedLines.contains(normalizedPublicKey)
    }

    private static func fingerprint(for publicKeyURL: URL) throws -> String {
        let output = try runProcess(
            executablePath: "/usr/bin/ssh-keygen",
            arguments: ["-lf", publicKeyURL.path]
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedContents(of url: URL) throws -> String {
        let contents = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !contents.isEmpty else {
            throw SSHKeyProvisioningError.emptyFile(url.lastPathComponent)
        }

        return contents
    }

    private static func resolvedCommandPath(named executableName: String) -> String? {
        let output = try? runProcess(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "command -v \(executableName) 2>/dev/null || true"]
        )
        let rawPath = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawPath, !rawPath.isEmpty else {
            return nil
        }
        let resolvedPath = URL(fileURLWithPath: rawPath)
            .resolvingSymlinksInPath()
            .path
        return resolvedPath.isEmpty ? rawPath : resolvedPath
    }

    private static func write(script: String, to url: URL) throws {
        try script.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw SSHKeyProvisioningError.commandFailed(
                executable: executablePath,
                message: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output
    }

    private static func ensureDirectoryExists(at url: URL, permissions: Int16) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try setPermissions(at: url, permissions: permissions)
    }

    private static func setPermissions(at url: URL, permissions: Int16) throws {
        try FileManager.default.setAttributes([.posixPermissions: Int(permissions)], ofItemAtPath: url.path)
    }

    private static func sanitizedHostToken() -> String {
        let raw = (Host.current().localizedName ?? "mac")
            .lowercased()
        let allowed = raw.map { character in
            if character.isLetter || character.isNumber {
                return String(character)
            }
            return "-"
        }
        let collapsed = allowed.joined()
            .replacing("--", with: "-")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private actor SSHTerminalPairingWrapKeyStore {
    struct ResolvedWrapKey {
        let recordName: String
        let keyData: Data
    }

    static let shared = SSHTerminalPairingWrapKeyStore()

    private let container = CKContainer(identifier: TalkieEnvironment.current.cloudKitContainerIdentifier)
    private let recordType = "TerminalPairingWrapKey"
    private let recordID = CKRecord.ID(recordName: "terminal-pairing-wrap-key-v1")
    private var cachedKeyData: Data?

    func getOrCreateWrapKey() async throws -> ResolvedWrapKey {
        if let cachedKeyData {
            return ResolvedWrapKey(recordName: recordID.recordName, keyData: cachedKeyData)
        }

        if let existingKeyData = try await fetchExistingKeyData() {
            cachedKeyData = existingKeyData
            return ResolvedWrapKey(recordName: recordID.recordName, keyData: existingKeyData)
        }

        let generatedKeyData = Data((0..<32).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["keyData"] = generatedKeyData as CKRecordValue
        record["schemaVersion"] = NSNumber(value: 1)

        do {
            let savedRecord = try await container.privateCloudDatabase.save(record)
            guard let keyData = savedRecord["keyData"] as? Data, keyData.count == 32 else {
                throw SSHKeyProvisioningError.wrapKeyUnavailable("Talkie couldn't save the secure pairing key.")
            }

            cachedKeyData = keyData
            bridgeSettingsLog.info("Created secure SSH pairing wrap key", detail: "record=\(recordID.recordName)")
            return ResolvedWrapKey(recordName: recordID.recordName, keyData: keyData)
        } catch {
            if let existingKeyData = try await fetchExistingKeyData() {
                cachedKeyData = existingKeyData
                return ResolvedWrapKey(recordName: recordID.recordName, keyData: existingKeyData)
            }

            bridgeSettingsLog.error("Failed to create secure SSH pairing wrap key: \(error.localizedDescription)")
            throw SSHKeyProvisioningError.wrapKeyUnavailable(
                "Talkie couldn't prepare secure terminal pairing. Make sure this Mac is signed into iCloud and try again."
            )
        }
    }

    private func fetchExistingKeyData() async throws -> Data? {
        do {
            let record = try await container.privateCloudDatabase.record(for: recordID)
            guard let keyData = record["keyData"] as? Data, keyData.count == 32 else {
                throw SSHKeyProvisioningError.wrapKeyUnavailable("Talkie found an invalid secure pairing key in iCloud.")
            }

            return keyData
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            bridgeSettingsLog.error("Failed to fetch secure SSH pairing wrap key: \(error.localizedDescription)")
            throw SSHKeyProvisioningError.wrapKeyUnavailable(
                "Talkie couldn't load secure terminal pairing. Make sure this Mac can reach iCloud and try again."
            )
        }
    }
}

private extension Data {
    func urlSafeBase64EncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum SSHKeyProvisioningError: LocalizedError {
    case emptyFile(String)
    case invalidPayload
    case wrapKeyUnavailable(String)
    case commandFailed(executable: String, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyFile(let name):
            return "\(name) was created, but it was empty."
        case .invalidPayload:
            return "The Talkie SSH QR payload could not be encoded."
        case .wrapKeyUnavailable(let message):
            return message
        case .commandFailed(let executable, let message):
            if message.isEmpty {
                return "\(URL(fileURLWithPath: executable).lastPathComponent) failed."
            }
            return message
        }
    }
}

// MARK: - Bridge Logs Section

/// Parsed log entry with optional JSON detail
private struct BridgeLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let level: String
    let message: String
    let jsonDetail: String?  // Extracted JSON if present

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

private struct BridgeLogsSection: View {
    @State private var logEntries: [BridgeLogEntry] = []
    @State private var isAutoRefresh = true
    @State private var showDevLogs = false  // Toggle between main and dev logs
    @State private var commandKeyHeld = false  // Expand all when Command held
    @State private var expandedEntries: Set<UUID> = []

    private let mainLogFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Talkie/Bridge/labs.log")
    private let devLogFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Talkie/Bridge/labs.dev.log")
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("BRIDGE LOGS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                // Dev logs toggle (shows API responses)
                Toggle(isOn: $showDevLogs) {
                    Text("API")
                        .font(.system(size: 9, weight: .medium))
                }
                .toggleStyle(.button)
                .controlSize(.mini)
                .help("Show API response logs (DEBUG level)")

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

            // Hint about Command key
            if !logEntries.isEmpty && logEntries.contains(where: { $0.jsonDetail != nil }) {
                HStack(spacing: 4) {
                    Image(systemName: "command")
                        .font(.system(size: 8))
                    Text("Hold ⌘ to expand all JSON")
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
                                BridgeLogEntryRow(
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

    // MARK: - Command Key Monitoring

    @State private var eventMonitor: Any?

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

    // MARK: - Log Parsing

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

    private func parseLine(_ line: String) -> BridgeLogEntry? {
        guard !line.isEmpty else { return nil }

        // Format: [ISO_TIMESTAMP] [LEVEL] message
        // e.g., [2024-01-08T10:30:00.000Z] [INFO] Labs sessions: 5
        let pattern = #"\[([^\]]+)\] \[([^\]]+)\] (.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            // Fallback for malformed lines
            return BridgeLogEntry(timestamp: "", level: "INFO", message: line, jsonDetail: nil)
        }

        let timestamp = String(line[Range(match.range(at: 1), in: line)!])
        let level = String(line[Range(match.range(at: 2), in: line)!])
        let message = String(line[Range(match.range(at: 3), in: line)!])

        // Extract JSON from API response logs
        // Format: [API Response] /path → {...}
        var jsonDetail: String? = nil
        if message.contains("[API Response]"), let arrowIndex = message.range(of: "→") {
            let jsonPart = String(message[arrowIndex.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let data = jsonPart.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                jsonDetail = prettyString
            } else {
                jsonDetail = jsonPart  // Show raw if can't prettify
            }
        }

        // Format timestamp for display (just time, not full ISO)
        let displayTime = formatTime(timestamp)

        return BridgeLogEntry(timestamp: displayTime, level: level, message: message, jsonDetail: jsonDetail)
    }

    private func formatTime(_ iso: String) -> String {
        // Extract just HH:MM:SS from ISO timestamp
        if let tIndex = iso.firstIndex(of: "T"),
           let dotIndex = iso.firstIndex(of: ".") {
            return String(iso[iso.index(after: tIndex)..<dotIndex])
        }
        return iso
    }
}

// MARK: - Log Entry Row

private struct BridgeLogEntryRow: View {
    let entry: BridgeLogEntry
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // Expand button if has JSON
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

                // Timestamp
                Text(entry.timestamp)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                // Level badge
                Text(entry.level)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(entry.levelColor)
                    .padding(.horizontal, 3)
                    .background(entry.levelColor.opacity(0.2))
                    .cornerRadius(2)

                // Message (truncated if has detail)
                Text(truncatedMessage)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()
            }

            // Expanded JSON detail
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
            // For API responses, just show the path
            if let arrowIndex = entry.message.range(of: "→") {
                return String(entry.message[..<arrowIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return entry.message
    }
}

// MARK: - QR Code Sheet

private struct QRCodeSheet: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var isRefreshing = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Pair iPhone for Mac Bridge")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let qrData = bridgeManager.qrData {
                VStack(spacing: 12) {
                    if qrData.isPairingReady, let image = generateQRCode(from: qrData) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 260, height: 260)
                            .background(Color.white)
                            .cornerRadius(12)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)

                            Text("This Bridge Isn’t Pairable Right Now")
                                .font(.headline)

                            Text(pairingReadinessMessage(for: qrData))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 260, height: 260)
                        .padding(16)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(12)
                    }

                    Text(qrData.isPairingReady
                         ? "Scan in Talkie on iPhone to add Mac Bridge live features"
                         : "Fix the bridge mode first, then reopen this QR sheet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if qrData.isPairingReady {
                        Text("This QR does not configure SSH terminal access.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Hostname:")
                                .foregroundColor(.secondary)
                            Text(qrData.hostname)
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text("Port:")
                                .foregroundColor(.secondary)
                            Text("\(qrData.port)")
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text("Mode:")
                                .foregroundColor(.secondary)
                            Text(qrData.mode.rawValue)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .font(.caption)
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            } else if isRefreshing {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing pairing QR...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(width: 260, height: 140)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                    Text("Bridge needs to be enabled first")
                        .font(.headline)
                    Text(bridgeManager.errorMessage ?? "Start the Mac Bridge, then Talkie can generate a pairing QR.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await bridgeManager.enableAndStartBridge() }
                    } label: {
                        Label("Enable Bridge", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(width: 280)
            }
        }
        .padding(24)
        .frame(width: 360)
        .task {
            isRefreshing = true
            await bridgeManager.checkStatusNow()
            isRefreshing = false
        }
    }

    private func generateQRCode(from data: BridgeManager.QRData) -> NSImage? {
        guard let jsonData = try? JSONEncoder().encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return QRCodeImageFactory.makeImage(from: jsonString)
    }

    private func pairingReadinessMessage(for qrData: BridgeManager.QRData) -> String {
        if qrData.mode == .localDev {
            return "This server is running in local dev mode and is advertising localhost. Stop the standalone dev bridge and restart the agent-managed bridge before pairing."
        }

        if qrData.hostname == "localhost" {
            return "This QR is advertising localhost, which only works on the Mac itself. Restart the bridge before pairing."
        }

        return "The bridge reported that it is not ready for device pairing."
    }
}

private struct SSHKeyQRCodeSheet: View {
    let payload: String?
    let label: String
    let fingerprint: String?
    let keyPath: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Import Terminal Access on iPhone")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let payload, let image = QRCodeImageFactory.makeImage(from: payload, size: 420) {
                VStack(spacing: 12) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 420, height: 420)
                        .background(Color.white)
                        .cornerRadius(12)

                    Text("Scan in Talkie on iPhone. The QR reader now routes SSH and other Talkie pairing codes automatically.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Label:")
                                .foregroundColor(.secondary)
                            Text(label)
                        }

                        if let fingerprint {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fingerprint:")
                                    .foregroundColor(.secondary)
                                Text(fingerprint)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Private key:")
                                .foregroundColor(.secondary)
                            Text(keyPath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .font(.caption)
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                Text("Unable to generate QR code")
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private enum QRCodeImageFactory {
    static func makeImage(from string: String, size: CGFloat = 200) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = max(size / outputImage.extent.width, size / outputImage.extent.height)
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

// MARK: - Bridge Message Queue Section (Troubleshooting)

private struct BridgeMessageQueueSection: View {
    @State private var queue = MessageQueue.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.arrow.left")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("MESSAGE QUEUE")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if !queue.messages.isEmpty {
                    Text("(\(queue.messages.count))")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                if !queue.messages.isEmpty {
                    Button("Clear") {
                        queue.clearAll()
                    }
                    .font(Theme.current.fontXS)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }

            // Status summary
            HStack(spacing: 16) {
                let failed = queue.messages.filter { $0.status == .failed }.count
                let pending = queue.messages.filter { $0.status == .pending || $0.status == .sending }.count
                let sent = queue.messages.filter { $0.status == .sent }.count

                if queue.messages.isEmpty {
                    Text("No messages received from iOS")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                } else {
                    if failed > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("\(failed) failed")
                        }
                        .font(Theme.current.fontXS)
                    }

                    if pending > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                            Text("\(pending) pending")
                        }
                        .font(Theme.current.fontXS)
                    }

                    if sent > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(sent) sent")
                        }
                        .font(Theme.current.fontXS)
                    }
                }

                Spacer()
            }
            .padding(10)
            .background(Theme.current.surface1)
            .cornerRadius(8)

            // Recent messages (last 5)
            if !queue.messages.isEmpty {
                VStack(spacing: 4) {
                    ForEach(queue.messages.prefix(5)) { message in
                        HStack(spacing: 8) {
                            // Status icon
                            Group {
                                switch message.status {
                                case .pending:
                                    Image(systemName: "clock")
                                        .foregroundColor(.orange)
                                case .sending:
                                    BrailleSpinner(size: 10)
                                case .sent:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                case .failed:
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .frame(width: 14)

                            // Session + text preview
                            VStack(alignment: .leading, spacing: 1) {
                                Text(message.sessionId.prefix(8) + "...")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                Text(message.text.prefix(50) + (message.text.count > 50 ? "..." : ""))
                                    .font(Theme.current.fontXS)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Error or time
                            if let error = message.lastError {
                                Text(error.prefix(20))
                                    .font(.system(size: 9))
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            } else {
                                Text(message.createdAt, style: .time)
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                        }
                        .padding(6)
                        .background(Theme.current.surface1.opacity(0.5))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BridgeSettingsView()
        .frame(width: 500, height: 600)
        .padding()
}
