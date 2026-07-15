//
//  iOSSettingsView.swift
//  Talkie macOS
//
//  Unified iOS connectivity settings.
//  Combines iCloud sync, Mac Bridge, terminal access, and paired device management.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import TalkieKit

struct iOSSettingsView: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var settings = SettingsManager.shared
    @State private var showingQRSheet = false
    @State private var showingPhonePairingGuide = false
    @State private var isRefreshing = false

    var body: some View {
        @Bindable var settings = settings
        SettingsPageContainer {
            HStack {
                SettingsPageHeader(
                    icon: "iphone",
                    title: "Devices",
                    subtitle: "Manage iCloud sync, Mac Bridge, paired devices, and terminal access."
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
                    // iCloud Sync
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue)
                            .frame(width: 3, height: 14)
                        Text("ICLOUD SYNC")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Spacer()
                    }
                    iCloudSyncSection(enabled: $settings.iCloudSyncEnabled)
                }
                .settingsSectionCard(padding: Spacing.md)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.purple)
                            .frame(width: 3, height: 14)
                        Text("MAC BRIDGE")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Spacer()
                    }
                    DeviceSetupSection(
                        bridgeStatus: bridgeManager.bridgeStatus,
                        tailscaleStatus: bridgeManager.tailscaleStatus,
                        pairedDeviceCount: bridgeManager.pairedDevices.count,
                        devices: bridgeManager.pairedDevices,
                        pendingPairings: bridgeManager.pendingPairings,
                        shortcutModeRequested: settings.companionShortcutModeEnabled,
                        onShowQR: { showingQRSheet = true },
                        onOpenTerminalGuide: { showingPhonePairingGuide = true },
                        onApprovePairing: { id in Task { await bridgeManager.approvePairing(id) } },
                        onRejectPairing: { id in Task { await bridgeManager.rejectPairing(id) } },
                        onRemoveDevice: { id in Task { await bridgeManager.removeDevice(id) } }
                    )
                }
                .settingsSectionCard(padding: Spacing.md)

                // Info footer
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Use Mac Bridge as one unified place to turn the bridge on, add devices, and manage what each paired device can do.")
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
        .sheet(isPresented: $showingPhonePairingGuide) {
            SSHPhonePairingGuideSheet()
        }
        .onChange(of: showingQRSheet) { _, isShowing in
            guard !isShowing else { return }
            refresh()
        }
        .onAppear {
            refresh()
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

// MARK: - Connection Overview Section

private struct ConnectionStatusSection: View {
    let iCloudEnabled: Bool
    let bridgeStatus: BridgeManager.BridgeStatus
    let deviceCount: Int

    private var enabledFeatures: [EnabledFeature] {
        var features: [EnabledFeature] = []
        if iCloudEnabled {
            features.append(EnabledFeature(
                icon: "icloud.fill",
                title: "iCloud Sync",
                description: "Memos sync across your Apple devices",
                color: .green
            ))
        }
        if bridgeStatus == .running {
            features.append(EnabledFeature(
                icon: "bolt.fill",
                title: "Mac Bridge",
                description: "Live Mac features are available",
                color: .green
            ))
        }
        return features
    }

    private var availableUpgrades: [FeatureUpsell] {
        var upgrades: [FeatureUpsell] = []
                if !iCloudEnabled {
                    upgrades.append(FeatureUpsell(
                        icon: "icloud",
                        title: "Enable iCloud Sync",
                        benefit: "Keep your memos backed up and synced across all your Apple devices",
                        action: "Enable below"
                    ))
                }
        if bridgeStatus != .running && deviceCount == 0 {
            upgrades.append(FeatureUpsell(
                icon: "bolt",
                title: "Mac Bridge",
                benefit: "Run Claude Code sessions, send messages to Mac, and more",
                action: "Comes on automatically"
            ))
        }
        return upgrades
    }

    struct EnabledFeature {
        let icon: String
        let title: String
        let description: String
        let color: Color
    }

    struct FeatureUpsell {
        let icon: String
        let title: String
        let benefit: String
        let action: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("CONNECTION OVERVIEW")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(spacing: 8) {
                // Show enabled features first (positive framing)
                ForEach(enabledFeatures, id: \.title) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 16))
                            .foregroundColor(feature.color)
                            .frame(width: 32, height: 32)
                            .background(feature.color.opacity(0.15))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)
                            Text(feature.description)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                    .padding(10)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                }

                // Show upsells for disabled features (gentle, helpful)
                ForEach(availableUpgrades, id: \.title) { upsell in
                    HStack(spacing: 12) {
                        Image(systemName: upsell.icon)
                            .font(.system(size: 16))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.current.foregroundSecondary.opacity(0.1))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(upsell.title)
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Text(upsell.benefit)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.8))
                                .lineLimit(2)
                        }

                        Spacer()

                        Text(upsell.action)
                            .font(.system(size: 9))
                            .foregroundColor(.blue.opacity(0.8))
                    }
                    .padding(10)
                    .background(Theme.current.surface1.opacity(0.5))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - iCloud Sync Section

private struct iCloudSyncSection: View {
    @Binding var enabled: Bool
    @State private var syncStatus = SyncStatusManager.shared
    @State private var talkieData = TalkieData.shared
    @State private var showingSyncHistory = false
    @State private var selectedSyncEventID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "icloud")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("ICLOUD SYNC")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                // Health indicator
                if enabled {
                    healthBadge
                }
            }

            // Main status row
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 20))
                    .foregroundColor(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)
                    Text(statusDescription)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)

            // Sync details when enabled
            if enabled {
                SyncDetailsView(
                    syncStatus: syncStatus,
                    inventory: talkieData.inventory,
                    onShowHistory: { event in
                        selectedSyncEventID = event?.id
                        showingSyncHistory = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingSyncHistory) {
            SyncPanelSheet(initialEventID: selectedSyncEventID)
        }
    }

    // MARK: - Computed Properties

    private var statusIcon: String {
        if !enabled { return "icloud.slash" }
        switch syncStatus.state {
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "icloud.fill"
        case .error: return "exclamationmark.icloud"
        case .idle: return "icloud"
        }
    }

    private var statusColor: Color {
        if !enabled { return .gray }
        switch syncStatus.state {
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        case .idle: return .blue
        }
    }

    private var statusTitle: String {
        if !enabled { return "Sync Disabled" }
        switch syncStatus.state {
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .error: return "Sync Error"
        case .idle: return "Sync Enabled"
        }
    }

    private var statusDescription: String {
        if !enabled { return "Memos stored locally only" }
        switch syncStatus.state {
        case .syncing: return "Updating with iCloud..."
        case .synced: return "Last sync: \(syncStatus.lastSyncAgo)"
        case .error(let msg): return msg
        case .idle:
            if let _ = syncStatus.lastSyncDate {
                return "Last sync: \(syncStatus.lastSyncAgo)"
            }
            return "Memos sync across your Apple devices"
        }
    }

    @ViewBuilder
    private var healthBadge: some View {
        let inventory = talkieData.inventory
        let isHealthy = inventory?.isHealthy ?? true
        let pendingCount = inventory?.pendingSync ?? 0

        HStack(spacing: 3) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 8))
            if !isHealthy && pendingCount > 0 {
                Text("\(pendingCount) Pending")
                    .font(.system(size: 9, weight: .medium))
            } else {
                Text(isHealthy ? "Healthy" : "Needs Sync")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundColor(isHealthy ? .green : .orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isHealthy ? Color.green : Color.orange).opacity(0.15))
        .cornerRadius(4)
    }
}

private struct DeviceSetupSection: View {
    let bridgeStatus: BridgeManager.BridgeStatus
    let tailscaleStatus: BridgeManager.TailscaleStatus
    let pairedDeviceCount: Int
    let devices: [BridgeManager.PairedDevice]
    let pendingPairings: [BridgeManager.PendingPairing]
    let shortcutModeRequested: Bool
    let onShowQR: () -> Void
    let onOpenTerminalGuide: () -> Void
    let onApprovePairing: (String) -> Void
    let onRejectPairing: (String) -> Void
    let onRemoveDevice: (String) -> Void

    @State private var bridgeManager = BridgeManager.shared
    @State private var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bridgeControlRow

            devicesHeaderRow

            if !pendingPairings.isEmpty {
                PendingPairingsSection(
                    pairings: pendingPairings,
                    onApprove: onApprovePairing,
                    onReject: onRejectPairing
                )
            }

            if devices.isEmpty {
                emptyState
            } else {
                ForEach(devices) { device in
                    DeviceSetupCard(
                        device: device,
                        shortcutModeRequested: shortcutModeRequested,
                        onOpenTerminalGuide: onOpenTerminalGuide,
                        onRemoveDevice: { onRemoveDevice(device.id) }
                    )
                }
            }
        }
    }

    private var bridgeControlRow: some View {
        HStack(spacing: 12) {
            Image(systemName: bridgeIcon)
                .font(.system(size: 18))
                .foregroundColor(bridgeTint)
                .frame(width: 36, height: 36)
                .background(bridgeTint.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Mac Bridge")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(bridgeStateLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(bridgeStateColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(bridgeStateColor.opacity(0.12))
                        .cornerRadius(5)
                }
                Text(bridgeDescription)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !tailscaleStatus.isReady && bridgeStatus == .stopped {
                Button(action: openTailscale) {
                    Text("SETUP")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else if bridgeStatus == .starting {
                BrailleSpinner(speed: 0.08)
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .frame(width: 40)
            } else {
                Toggle("", isOn: bridgeEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!tailscaleStatus.isReady && bridgeStatus == .stopped)
            }
        }
        .padding(12)
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }

    private var devicesHeaderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Paired Devices")
                .font(Theme.current.fontXSMedium)
                .foregroundColor(Theme.current.foregroundSecondary)

            if pairedDeviceCount > 0 {
                Text("\(pairedDeviceCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.current.surface1)
                    .cornerRadius(6)
            }

            if let lastPublishedSummary {
                Text(lastPublishedSummary)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.85))
            }

            Spacer()

            Button(action: { settings.publishDeviceSettingsNow() }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(canPublishDeviceConfig ? .green : Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background((canPublishDeviceConfig ? Color.green : Theme.current.foregroundSecondary).opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!canPublishDeviceConfig)
            .help(publishButtonHelp)

            Button(action: onShowQR) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(bridgeStatus == .running ? .blue : Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background((bridgeStatus == .running ? Color.blue : Theme.current.foregroundSecondary).opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(bridgeStatus != .running)
            .help(bridgeStatus == .running ? "Add a device" : "Turn on Mac Bridge to add a device")
        }
    }

    private var canPublishDeviceConfig: Bool {
        bridgeStatus == .running && pairedDeviceCount > 0
    }

    private var lastPublishedSummary: String? {
        guard pairedDeviceCount > 0,
              let publishedAt = settings.lastDeviceSettingsPublishedAt else {
            return nil
        }
        return "Pushed \(TalkieDate.relativeCompact(publishedAt))"
    }

    private var publishButtonHelp: String {
        if !canPublishDeviceConfig {
            if pairedDeviceCount == 0 {
                return "Pair a device first, then push the current device config."
            }
            return "Turn on Mac Bridge first."
        }

        return "Push the current device config so connected devices pick up the latest board on their next bridge refresh."
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 18))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.current.foregroundSecondary.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text("No Devices Paired Yet")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text(emptyDescription)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }

    private var pairingDescription: String {
        if bridgeStatus == .running {
            if devices.isEmpty {
                return "Show the Mac Bridge QR to pair your first iPhone or iPad."
            }
            return "Show the Mac Bridge QR only when you want to add another device."
        }

        return "Turn on Mac Bridge first, then show the pairing QR for devices you want to add."
    }

    private var emptyDescription: String {
        if bridgeStatus == .running {
            return "Mac Bridge is on. Use the plus button above to connect your first device."
        }
        return "Turn on Mac Bridge first. Once it is on, you can add devices here."
    }

    private var bridgeStateLabel: String {
        switch bridgeStatus {
        case .running:
            return "ON"
        case .starting:
            return "STARTING"
        case .stopped:
            return "OFF"
        case .error:
            return "ERROR"
        }
    }

    private var bridgeStateColor: Color {
        switch bridgeStatus {
        case .running:
            return .green
        case .starting:
            return .orange
        case .stopped:
            return Theme.current.foregroundSecondary
        case .error:
            return .red
        }
    }

    private var bridgeEnabledBinding: Binding<Bool> {
        Binding(
            get: { bridgeStatus == .running || bridgeStatus == .starting },
            set: { newValue in
                Task {
                    if newValue {
                        await bridgeManager.startBridge()
                    } else {
                        await bridgeManager.stopBridge()
                    }
                }
            }
        )
    }

    private var bridgeIcon: String {
        switch bridgeStatus {
        case .running: return "bolt.fill"
        case .starting: return "bolt"
        case .stopped:
            return tailscaleStatus.isReady ? "bolt.slash" : "network.slash"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var bridgeTint: Color {
        switch bridgeStatus {
        case .running: return .green
        case .starting: return .orange
        case .stopped:
            return tailscaleStatus.isReady ? Theme.current.foregroundSecondary : .orange
        case .error: return .red
        }
    }

    private var bridgeDescription: String {
        switch bridgeStatus {
        case .running:
            if pairedDeviceCount == 0 {
                return "Mac Bridge is on and ready for your first paired device."
            }
            let noun = pairedDeviceCount == 1 ? "device" : "devices"
            return "Mac Bridge is on for \(pairedDeviceCount) paired \(noun). Add or manage devices below."
        case .starting:
            return "Starting Talkie Server..."
        case .stopped:
            if !tailscaleStatus.isReady {
                return tailscaleStatus.message
            }
            return "Turn this on so your paired devices can reach this Mac."
        case .error:
            return bridgeManager.errorMessage ?? "Server encountered an error"
        }
    }

    private func openTailscale() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macos")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macsys") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        if let downloadURL = URL(string: "https://tailscale.com/download/mac") {
            NSWorkspace.shared.open(downloadURL)
        }
    }

}

private struct DeviceSetupCard: View {
    let device: BridgeManager.PairedDevice
    let shortcutModeRequested: Bool
    let onOpenTerminalGuide: () -> Void
    let onRemoveDevice: () -> Void

    @State private var showingRemoveConfirmation = false

    private var setupState: BridgeManager.PairedDevice.SetupState? { device.setupState }

    private var shortcutOptedIn: Bool {
        setupState?.followComputerShortcutMode == true
    }

    private var shortcutSurfaceActive: Bool {
        setupState?.companionSurfaceActive == true
    }

    private var terminalImported: Bool {
        setupState?.terminalImported == true
    }

    private var primaryActionTitle: String? {
        if !terminalImported {
            return "SET UP TERMINAL"
        }
        return nil
    }

    private var nextStepTitle: String {
        if !shortcutModeRequested {
            return "Next: turn on Shortcut Keyboard in Dictation"
        }
        if !shortcutOptedIn {
            return "Next: turn on Follow Mac Shortcut Keyboard on \(device.name)"
        }
        if !terminalImported {
            return "Next: scan the terminal QR on \(device.name)"
        }
        return "\(device.name) is fully set up"
    }

    private var nextStepDescription: String {
        if !shortcutModeRequested {
            return "Turn on Shortcut Keyboard in Settings > Dictation so connected devices can follow the board authored on this Mac."
        }
        if !shortcutOptedIn {
            return "Mac Bridge is ready, but this device has not opted into the Mac-authored shortcut keyboard yet."
        }
        if !terminalImported {
            return "Mac Bridge and the shortcut keyboard are ready. Terminal access is the only remaining setup step for this device."
        }

        return "Bridge pairing, shortcut keyboard, and terminal access are all ready for this device."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "ipad.and.iphone")
                    .font(.system(size: 18))
                    .foregroundColor(.cyan)
                    .frame(width: 36, height: 36)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(nextStepTitle)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if let reportedAt = setupState?.reportedAt,
                       let date = TalkieDate.fromISO8601(reportedAt) {
                        Text("Reported \(TalkieDate.relativeCompact(date))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(0.8))
                    }
                }

                Spacer()

                if let primaryActionTitle {
                    Button(action: onOpenTerminalGuide) {
                        Text(primaryActionTitle)
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(nextStepDescription)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                SetupChecklistRow(
                    title: "Mac Bridge paired",
                    detail: "This device can use live Mac features.",
                    state: .done
                )
                SetupChecklistRow(
                    title: "Shortcut keyboard ready",
                    detail: shortcutModeDetail,
                    state: shortcutModeState
                )
                SetupChecklistRow(
                    title: "Terminal access imported",
                    detail: terminalDetail,
                    state: terminalState
                )
            }
            .padding(10)
            .background(Theme.current.background.opacity(0.35))
            .cornerRadius(8)

            HStack {
                Spacer()

                Button(action: { showingRemoveConfirmation = true }) {
                    Text("REMOVE BRIDGE PAIRING")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.current.surface1)
        .cornerRadius(10)
        .alert("Remove Bridge Pairing?", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove Pairing", role: .destructive) {
                onRemoveDevice()
            }
        } message: {
            Text("This revokes Mac Bridge trust for \(device.name). Terminal SSH keys already imported on the iPhone are separate and are not removed by this action.")
        }
    }

    private var shortcutModeState: SetupChecklistRow.State {
        if !shortcutModeRequested {
            return .pending
        }
        if shortcutOptedIn {
            return .done
        }
        return .pending
    }

    private var terminalState: SetupChecklistRow.State {
        terminalImported ? .done : .pending
    }

    private var shortcutModeDetail: String {
        if !shortcutModeRequested {
            return "This Mac is not currently publishing its shortcut keyboard to paired devices."
        }
        if shortcutSurfaceActive {
            return "This device is actively following the Mac's shortcut keyboard."
        }
        if shortcutOptedIn {
            return "This device opted in and will switch to the Mac-authored keyboard when Talkie is open and connected."
        }
        return "Turn on Follow Mac Shortcut Keyboard in Talkie on this device."
    }

    private var terminalDetail: String {
        if terminalImported, let host = setupState?.terminalHost, !host.isEmpty {
            return "Configured terminals already includes \(host)."
        }
        if terminalImported {
            return "Configured terminals already includes this Mac."
        }
        return "Scan the SSH terminal QR from this Mac to add it under Configured terminals."
    }
}

private struct SetupChecklistRow: View {
    enum State {
        case done
        case pending

        var symbol: String {
            switch self {
            case .done: return "checkmark.circle.fill"
            case .pending: return "circle"
            }
        }

        var label: String {
            switch self {
            case .done: return "DONE"
            case .pending: return "TO DO"
            }
        }
    }

    let title: String
    let detail: String
    let state: State

    private var stateTint: Color {
        switch state {
        case .done:
            return .green
        case .pending:
            return Theme.current.foregroundSecondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(stateTint)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(Theme.current.foreground)
                    Text(state.label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(stateTint)
                }

                Text(detail)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Sync Details View

private struct SyncDetailsView: View {
    let syncStatus: SyncStatusManager
    let inventory: DataInventory?
    let onShowHistory: (SyncEvent?) -> Void
    @Environment(CloudKitSyncManager.self) private var syncManager
    @State private var syncClient = SyncClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recent syncs header
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                // Nice button for full sync history
                Button(action: {
                    onShowHistory(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9))
                        Text("Sync History")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            // Recent syncs list (clickable rows)
            let recentEvents = Array(syncManager.syncHistory.prefix(5))
            if !recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(recentEvents) { event in
                        SyncActivityRow(event: event, onTap: {
                            onShowHistory(event)
                        })
                        if event.id != recentEvents.last?.id {
                            Divider()
                                .background(Theme.current.divider.opacity(0.5))
                        }
                    }
                }
                .background(Theme.current.background.opacity(0.5))
                .cornerRadius(6)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.7))
                    Text("No recent changes")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.background.opacity(0.5))
                .cornerRadius(6)
            }

            if !syncClient.activityLog.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Live Log")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Spacer()
                        Text("\(syncClient.activityLog.count) lines")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(0.8))
                    }

                    let preview = Array(syncClient.activityLog.suffix(3))
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(preview) { entry in
                            Text(entry.message)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.current.foreground.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.current.background.opacity(0.5))
                    .cornerRadius(6)
                }
            }
        }
        .padding(10)
        .background(Theme.current.surface1.opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - Sync Activity Row

private struct SyncActivityRow: View {
    let event: SyncEvent
    var onTap: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                // Time
                Text(formatTime(event.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                    .frame(width: 38, alignment: .leading)

                // Status icon with background
                Image(systemName: changeIcon)
                    .font(.system(size: 9))
                    .foregroundColor(changeColor)
                    .frame(width: 14, height: 14)
                    .background(changeColor.opacity(0.15))
                    .cornerRadius(CornerRadius.Raw.xs)

                // Description - more visible
                Text(description)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.current.foreground.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                // Item count badge
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(changeColor.opacity(0.8))
                        .cornerRadius(CornerRadius.Raw.sm)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(isHovering ? 0.6 : 0.3))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovering ? Theme.current.surface1.opacity(0.5) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }

    private var changeIcon: String {
        if event.status == .failed { return "xmark.circle.fill" }
        let added = event.details.filter { $0.changeType == .added }.count
        let deleted = event.details.filter { $0.changeType == .deleted }.count
        if deleted > 0 { return "minus.circle" }
        if added > 0 { return "plus.circle" }
        return "pencil.circle"
    }

    private var changeColor: Color {
        if event.status == .failed { return .red }
        let added = event.details.filter { $0.changeType == .added }.count
        let deleted = event.details.filter { $0.changeType == .deleted }.count
        if deleted > 0 { return .red }
        if added > 0 { return .green }
        return .blue
    }

    private var description: String {
        if let error = event.errorMessage, !error.isEmpty {
            return "Failed: \(error.prefix(30))"
        }

        // Single item - show title
        if event.details.count == 1, let detail = event.details.first {
            let title = detail.title.isEmpty ? "Untitled" : String(detail.title.prefix(25))
            switch detail.changeType {
            case .added: return "New: \(title)"
            case .modified: return "Updated: \(title)"
            case .deleted: return "Deleted: \(title)"
            }
        }

        // Multiple items
        let added = event.details.filter { $0.changeType == .added }.count
        let modified = event.details.filter { $0.changeType == .modified }.count
        let deleted = event.details.filter { $0.changeType == .deleted }.count

        var parts: [String] = []
        if added > 0 { parts.append("\(added) new") }
        if modified > 0 { parts.append("\(modified) updated") }
        if deleted > 0 { parts.append("\(deleted) deleted") }

        // If no details but event completed, show status-based message
        if parts.isEmpty {
            if event.itemCount > 0 {
                return "\(event.itemCount) item\(event.itemCount == 1 ? "" : "s") changed"
            }
            if let latest = event.activity.last?.message, !latest.isEmpty {
                return String(latest.prefix(32))
            }
            switch event.status {
            case .success: return "Sync completed"
            case .failed: return "Sync failed"
            case .partial: return "Partial sync"
            }
        }

        return parts.joined(separator: ", ")
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var badgeCount: Int {
        if !event.details.isEmpty {
            return event.details.count
        }
        return max(0, event.itemCount)
    }
}

// MARK: - Mac Bridge Section

private struct MacBridgeSection: View {
    let bridgeStatus: BridgeManager.BridgeStatus
    let tailscaleStatus: BridgeManager.TailscaleStatus
    let pairedDeviceCount: Int

    @State private var bridgeManager = BridgeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("MAC BRIDGE")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 20))
                        .foregroundColor(statusColor)
                        .frame(width: 36, height: 36)
                        .background(statusColor.opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text(statusDescription)
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
    }

    private var statusIcon: String {
        switch bridgeStatus {
        case .running: return "bolt.fill"
        case .starting: return "bolt"
        case .stopped:
            if !tailscaleStatus.isReady {
                return "network.slash"
            }
            return "bolt.slash"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch bridgeStatus {
        case .running: return .green
        case .starting: return .orange
        case .stopped: return .gray
        case .error: return .red
        }
    }

    private var statusTitle: String {
        switch bridgeStatus {
        case .running: return "Mac Bridge On"
        case .starting: return "Starting..."
        case .stopped: return tailscaleStatus.isReady ? "Mac Bridge Off" : "Tailscale Required"
        case .error: return "Error"
        }
    }

    private var statusDescription: String {
        switch bridgeStatus {
        case .running:
            if pairedDeviceCount == 0 {
                return "Mac Bridge is available. Pair devices from the section below."
            }
            let noun = pairedDeviceCount == 1 ? "device" : "devices"
            return "\(pairedDeviceCount) paired \(noun). Manage their setup in the section below."
        case .starting: return "Starting Talkie Server..."
        case .stopped:
            if !tailscaleStatus.isReady {
                return tailscaleStatus.message
            }
            return "Turn this on when you want paired devices to reach this Mac."
        case .error: return bridgeManager.errorMessage ?? "Server encountered an error"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch bridgeStatus {
        case .running:
            Button(action: { Task { await bridgeManager.stopBridge() } }) {
                Text("STOP")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .stopped:
            if !tailscaleStatus.isReady {
                Button(action: openTailscale) {
                    Text("SETUP")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else {
                EmptyView()
            }

        case .starting:
            BrailleSpinner(speed: 0.08)
                .font(.system(size: 12))
                .foregroundColor(.orange)

        case .error:
            Button(action: { Task { await bridgeManager.restartBridge() } }) {
                Text("RETRY")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    private func openTailscale() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macos")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macsys") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        if let downloadURL = URL(string: "https://tailscale.com/download/mac") {
            NSWorkspace.shared.open(downloadURL)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    let available: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(available ? .green : .gray)
                .frame(width: 16)
            Text(text)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
            Spacer()
            Image(systemName: available ? "checkmark" : "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(available ? .green : .gray)
        }
    }
}

private struct TerminalAccessSection: View {
    let pairedDeviceCount: Int
    let onOpenGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("SSH TERMINAL")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 12) {
                Image(systemName: "rectangle.and.terminal")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                    .frame(width: 36, height: 36)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add this Mac under Configured terminals")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)
                    Text(description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onOpenGuide) {
                    HStack(spacing: 4) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 10, weight: .semibold))
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
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.top, 1)

                Text("Bridge pairing and terminal access are separate. Use the terminal guide even if this same iPhone already appears under Mac Bridge devices.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Theme.current.surface1.opacity(0.5))
            .cornerRadius(6)
        }
    }

    private var description: String {
        if pairedDeviceCount > 0 {
            return "Your iPhone may already be paired for Mac Bridge. Scan the terminal QR separately so this Mac shows up in the iPhone terminal list."
        }

        return "Prepare the Talkie SSH key, enable Remote Login if needed, and scan the terminal QR in Talkie on your iPhone."
    }
}

// MARK: - Mac Bridge Devices Section

private struct BridgeDevicesSection: View {
    let devices: [BridgeManager.PairedDevice]
    let onRemoveDevice: (String) -> Void
    let onRemoveAll: () -> Void

    @State private var deviceToRemove: BridgeManager.PairedDevice?
    @State private var showRemoveAllConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("MAC BRIDGE DEVICES")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if !devices.isEmpty {
                    Text("(\(devices.count))")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                if devices.count > 1 {
                    Button(action: { showRemoveAllConfirm = true }) {
                        Text("Remove All")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }

            if devices.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No iPhones paired for Mac Bridge yet")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("Show the Mac Bridge QR above to connect an iPhone for live features.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()
                }
                .padding(10)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            } else {
                ForEach(devices) { device in
                    PairedDeviceRow(
                        device: device,
                        onRemove: { deviceToRemove = device }
                    )
                }
            }
        }
        .alert("Remove Device?", isPresented: .init(
            get: { deviceToRemove != nil },
            set: { if !$0 { deviceToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { deviceToRemove = nil }
            Button("Remove", role: .destructive) {
                if let device = deviceToRemove {
                    onRemoveDevice(device.id)
                }
                deviceToRemove = nil
            }
        } message: {
            if let device = deviceToRemove {
                Text("Remove \"\(device.name)\" from Mac Bridge devices? This iPhone will need to scan the Mac Bridge QR again to reconnect.")
            }
        }
        .alert("Remove All Devices?", isPresented: $showRemoveAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove All", role: .destructive) {
                onRemoveAll()
            }
        } message: {
            Text("Remove all \(devices.count) Mac Bridge devices? They will need to scan the Mac Bridge QR again to reconnect.")
        }
    }
}

private struct PairedDeviceRow: View {
    let device: BridgeManager.PairedDevice
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 20))
                .foregroundColor(statusColor)
                .frame(width: 36, height: 36)
                .background(statusColor.opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text("Trusted for Mac Bridge live features")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                HStack(spacing: 6) {
                    Text("Paired \(formatDate(device.pairedAt))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.85))

                    if let lastSeenText {
                        Circle()
                            .fill(Theme.current.foregroundSecondary.opacity(0.45))
                            .frame(width: 3, height: 3)

                        Text(lastSeenText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(0.85))
                    }
                }
            }

            Spacer()

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontSM)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            } else {
                Text(statusLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Theme.current.surface1)
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var lastSeenText: String? {
        guard let lastSeen = device.lastSeen,
              let date = TalkieDate.fromISO8601(lastSeen)
        else { return nil }
        return "Seen \(TalkieDate.relativeCompact(date))"
    }

    private var statusLabel: String {
        isRecentlySeen ? "ACTIVE" : "PAIRED"
    }

    private var statusColor: Color {
        isRecentlySeen ? .green : .blue
    }

    private var isRecentlySeen: Bool {
        guard let lastSeen = device.lastSeen,
              let date = TalkieDate.fromISO8601(lastSeen)
        else { return false }
        return Date().timeIntervalSince(date) < 300
    }

    private func formatDate(_ isoString: String) -> String {
        guard let date = TalkieDate.fromISO8601(isoString) else {
            return isoString
        }
        return TalkieDate.relativeCompact(date)
    }
}

// MARK: - Pending Pairings Section

private struct PendingPairingsSection: View {
    let pairings: [BridgeManager.PendingPairing]
    let onApprove: (String) -> Void
    let onReject: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.badge.plus")
                    .font(Theme.current.fontXS)
                    .foregroundStyle(Theme.current.accent)
                Text(pairings.count == 1 ? "Pairing request" : "Pairing requests")
                    .font(Theme.current.fontXSMedium)
                    .foregroundStyle(Theme.current.foregroundSecondary)
            }

            ForEach(pairings) { pairing in
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.current.accent)
                        .frame(width: 38, height: 38)
                        .background(Theme.current.accent.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(pairing.name)
                            .font(Theme.current.fontSMMedium)
                            .foregroundStyle(Theme.current.foreground)
                        Text("Requests access to Mac Bridge")
                            .font(Theme.current.fontXS)
                            .foregroundStyle(Theme.current.foregroundSecondary)
                    }

                    Spacer(minLength: 16)

                    HStack(spacing: 8) {
                        Button("Decline", role: .cancel) {
                            onReject(pairing.deviceId)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Approve") {
                            onApprove(pairing.deviceId)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Theme.current.accent)
                    }
                }
                .padding(12)
                .background(Theme.current.surface1)
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.current.borderSubtle, lineWidth: 1)
                }
            }
        }
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
                    if let image = generateQRCode(from: qrData) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .background(Color.white)
                            .cornerRadius(12)
                    }

                    Text("Scan in Talkie on iPhone to add Mac Bridge live features")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("This QR does not configure SSH terminal access.")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                .frame(width: 240, height: 120)
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
                .frame(width: 240)
            }
        }
        .padding(24)
        .frame(width: 300)
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

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}

// MARK: - Sync History Sheet

private struct SyncEventDetailSheet: View {
    let event: SyncEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SyncEventDetailViewEmbedded(
            event: event,
            onBack: { dismiss() },
            onDone: { dismiss() },
            backLabel: "Close"
        )
    }
}

private struct SyncHistorySheet: View {
    var initialEvent: SyncEvent? = nil
    @Environment(\.dismiss) private var dismissSheet
    @State private var selectedEvent: SyncEvent? = nil
    @Environment(CloudKitSyncManager.self) private var syncManager

    var body: some View {
        Group {
            if let event = selectedEvent {
                SyncEventDetailViewEmbedded(
                    event: event,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedEvent = nil
                        }
                    },
                    onDone: { dismissSheet() }
                )
            } else {
                SyncHistoryViewWithNavigation(onSelectEvent: { event in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedEvent = event
                    }
                })
                .environment(CloudKitSyncManager.shared)
            }
        }
        .onAppear {
            if let initial = initialEvent {
                selectedEvent = initial
            }
        }
    }
}

// MARK: - Sync Event Detail View (Embedded)

struct SyncEventDetailViewEmbedded: View {
    let event: SyncEvent
    let onBack: () -> Void
    let onDone: () -> Void
    var backLabel: String = "Back"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text(backLabel)
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Event summary card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: event.status.icon)
                                .font(.system(size: 24))
                                .foregroundColor(event.status.color)
                                .frame(width: 40, height: 40)
                                .background(event.status.color.opacity(0.15))
                                .cornerRadius(10)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatDateTime(event.timestamp))
                                    .font(.system(size: 16, weight: .semibold))

                                HStack(spacing: 8) {
                                    Text(event.status.rawValue.capitalized)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(event.status.color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(event.status.color.opacity(0.15))
                                        .cornerRadius(4)

                                    if let mode = event.syncMode {
                                        Text(mode)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(mode == "incremental" ? .blue : .secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background((mode == "incremental" ? Color.blue : Color.secondary).opacity(0.12))
                                            .cornerRadius(4)
                                    }

                                    Text(itemCountLabel)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Theme.current.foregroundSecondary.opacity(0.12))
                                        .cornerRadius(4)

                                    if let duration = event.duration {
                                        Text(String(format: "%.1fs", duration))
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                    }
                                }
                            }

                            Spacer()
                        }

                        if let error = event.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }

                        if event.localCount != nil || event.remoteCount != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Snapshot")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                HStack(spacing: 8) {
                                    if let localCount = event.localCount {
                                        syncCountBadge(label: "Local", value: localCount, tint: .blue)
                                    }
                                    if let remoteCount = event.remoteCount {
                                        syncCountBadge(label: "Remote", value: remoteCount, tint: .purple)
                                    }
                                    if let driftCount {
                                        syncCountBadge(
                                            label: "Drift",
                                            value: driftCount,
                                            tint: driftCount == 0 ? .green : .orange
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)

                    // Sync stats breakdown
                    if let inserted = event.inserted {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Breakdown")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.current.foregroundSecondary)

                            HStack(spacing: 8) {
                                syncCountBadge(label: "Inserted", value: inserted, tint: .green)
                                if let updated = event.updated {
                                    syncCountBadge(label: "Updated", value: updated, tint: .blue)
                                }
                                if let deleted = event.deleted {
                                    syncCountBadge(label: "Deleted", value: deleted, tint: .red)
                                }
                                if let skipped = event.skipped {
                                    syncCountBadge(label: "Skipped", value: skipped, tint: .secondary)
                                }
                            }

                            if let fetchTimeMs = event.fetchTimeMs, let totalTimeMs = event.totalTimeMs {
                                HStack(spacing: 8) {
                                    syncCountBadge(label: "Fetch", value: fetchTimeMs, tint: .secondary, suffix: "ms")
                                    syncCountBadge(label: "Total", value: totalTimeMs, tint: .secondary, suffix: "ms")
                                }
                            }
                        }
                    }

                    // Records changed section
                    if !event.details.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Records Changed")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                Spacer()

                                Text("\(event.details.count) item\(event.details.count == 1 ? "" : "s")")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }

                            // Group by change type
                            let added = event.details.filter { $0.changeType == .added }
                            let modified = event.details.filter { $0.changeType == .modified }
                            let deleted = event.details.filter { $0.changeType == .deleted }

                            if !added.isEmpty {
                                EmbeddedChangeGroupSection(title: "Added", icon: "plus.circle.fill", color: .green, records: added)
                            }

                            if !modified.isEmpty {
                                EmbeddedChangeGroupSection(title: "Modified", icon: "pencil.circle.fill", color: .blue, records: modified)
                            }

                            if !deleted.isEmpty {
                                EmbeddedChangeGroupSection(title: "Deleted", icon: "minus.circle.fill", color: .red, records: deleted)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 32))
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Text("No per-record details available")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }

                    if !event.activity.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Run Activity")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                Spacer()

                                Text("\(event.activity.count) line\(event.activity.count == 1 ? "" : "s")")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }

                            VStack(spacing: 0) {
                                ForEach(event.activity) { entry in
                                    HStack(spacing: 8) {
                                        Text(formatActivityTime(entry.timestamp))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(Theme.current.foregroundSecondary.opacity(0.8))
                                            .frame(width: 42, alignment: .leading)

                                        Image(systemName: entry.level.icon)
                                            .font(.system(size: 9))
                                            .foregroundColor(entry.level.color)
                                            .frame(width: 12)

                                        Text(entry.message)
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.current.foreground)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)

                                    if entry.id != event.activity.last?.id {
                                        Divider()
                                            .padding(.leading, 10)
                                    }
                                }
                            }
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 400, idealWidth: 500, maxWidth: 700)
        .frame(minHeight: 350, idealHeight: 450, maxHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var driftCount: Int? {
        guard let localCount = event.localCount, let remoteCount = event.remoteCount else { return nil }
        return abs(localCount - remoteCount)
    }

    private var itemCountLabel: String {
        if let inserted = event.inserted, let updated = event.updated, let deleted = event.deleted {
            if inserted == 0 && updated == 0 && deleted == 0 {
                return "Up to date"
            }
            var parts: [String] = []
            if inserted > 0 { parts.append("+\(inserted) new") }
            if updated > 0 { parts.append("~\(updated) updated") }
            if deleted > 0 { parts.append("-\(deleted) deleted") }
            return parts.joined(separator: ", ")
        }
        return "\(event.itemCount) item\(event.itemCount == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func syncCountBadge(label: String, value: Int, tint: Color, suffix: String? = nil) -> some View {
        Text("\(label): \(value)\(suffix ?? "")")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(tint.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .cornerRadius(5)
    }

    private func formatActivityTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Embedded Change Group Section

private struct EmbeddedChangeGroupSection: View {
    let title: String
    let icon: String
    let color: Color
    let records: [SyncRecordDetail]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(color)
                Text("(\(records.count))")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(spacing: 0) {
                ForEach(records) { record in
                    HStack(spacing: 10) {
                        Text(record.recordType)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(recordTypeColor(record.recordType))
                            .cornerRadius(4)

                        Text(record.title.isEmpty ? "Untitled" : record.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        if let modDate = record.modificationDate {
                            Text(formatShortDate(modDate))
                                .font(.system(size: 10))
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                    if record.id != records.last?.id {
                        Divider()
                            .padding(.leading, 10)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
    }

    private func recordTypeColor(_ type: String) -> Color {
        switch type {
        case "VoiceMemo": return .blue
        case "Workflow": return .purple
        case "WorkflowStep": return .indigo
        case "TranscriptionSegment": return .teal
        default: return .gray
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Sync History View With Navigation

private struct SyncHistoryViewWithNavigation: View {
    var onSelectEvent: (SyncEvent) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudKitSyncManager.self) private var syncManager
    @State private var syncClient = SyncClient.shared

    @State private var pendingDeletions: [MemoModel] = []
    @State private var selectedDeletions: Set<UUID> = []
    @State private var isLoadingDeletions = false
    @State private var isSyncInitiating = false
    @State private var syncError: String?
    @State private var showActivityLog = true

    private let viewModel = MemosViewModel()
    private static let activityTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var isBusy: Bool {
        isSyncInitiating || syncClient.isSyncing || syncManager.isSyncing
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Manager")
                        .font(.system(size: 16, weight: .semibold))

                    if let lastSync = syncManager.lastSyncDate {
                        Text("Last synced \(formatRelativeTime(lastSync))")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }

                Spacer()

                // Sync Now button
                if isBusy {
                    HStack(spacing: 6) {
                        BrailleSpinner(size: 12)
                        Text(syncClient.syncStatusMessage.isEmpty ? "Syncing..." : syncClient.syncStatusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .lineLimit(1)
                    }

                    Button {
                        cancelSync()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Cancel sync")
                } else {
                    Button {
                        performSync()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }

                // Copy history button
                Button {
                    copyHistoryToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy sync history")

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if let syncError, !isBusy {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(syncError)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        self.syncError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
                Divider()
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Pending Deletions Section
                    if !pendingDeletions.isEmpty {
                        PendingDeletionsSection(
                            deletions: pendingDeletions,
                            selectedDeletions: $selectedDeletions,
                            onApprove: approveDeletions,
                            onRestore: restoreDeletions
                        )

                        Divider()
                            .padding(.vertical, 8)
                    }

                    // Live activity section (same source as status-bar sync panel)
                    if !syncClient.activityLog.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showActivityLog.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: showActivityLog ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                            .frame(width: 12)
                                        Text("Live Activity")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Text("\(syncClient.activityLog.count) line\(syncClient.activityLog.count == 1 ? "" : "s")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                Button {
                                    copyActivityToClipboard()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .help("Copy live activity")

                                Button {
                                    syncClient.activityLog.removeAll()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Clear live activity")
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            if showActivityLog {
                                let entries = Array(syncClient.activityLog.suffix(40))
                                VStack(spacing: 0) {
                                    ForEach(entries) { entry in
                                        SyncClientLogRow(
                                            entry: entry,
                                            timestampText: Self.activityTimeFormatter.string(from: entry.timestamp)
                                        )
                                        if entry.id != entries.last?.id {
                                            Divider()
                                                .padding(.leading, 12)
                                        }
                                    }
                                }
                                .background(Theme.current.background.opacity(0.5))
                                .cornerRadius(6)
                                .padding(.horizontal, 16)
                            }
                        }

                        Divider()
                            .padding(.vertical, 8)
                    }

                    // Sync History Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sync History")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        if syncManager.syncHistory.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 48))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                Text("No sync history yet")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            ForEach(syncManager.syncHistory) { event in
                                NavigableSyncEventRow(event: event, onSelect: onSelectEvent)
                                Divider()
                            }
                        }
                    }

                    // Dev Mode Troubleshooting Section (DEBUG builds only)
                    #if DEBUG
                    Divider()
                        .padding(.vertical, 8)

                    DevModeSyncSection(
                        syncManager: syncManager,
                        onForceBridge: {
                            syncManager.forceSyncToGRDB()
                        }
                    )
                    #endif
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 500, maxWidth: 700)
        .frame(minHeight: 350, idealHeight: 450, maxHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadPendingDeletions()
        }
    }

    private func loadPendingDeletions() async {
        isLoadingDeletions = true
        pendingDeletions = await viewModel.fetchPendingDeletions()
        isLoadingDeletions = false
    }

    private func approveDeletions() {
        let idsToDelete = selectedDeletions.isEmpty
            ? Set(pendingDeletions.map(\.id))
            : selectedDeletions

        Task {
            await viewModel.permanentlyDeleteMemos(idsToDelete)
            await loadPendingDeletions()
            selectedDeletions.removeAll()
        }
    }

    private func restoreDeletions() {
        let idsToRestore = selectedDeletions.isEmpty
            ? Set(pendingDeletions.map(\.id))
            : selectedDeletions

        Task {
            await viewModel.restoreMemos(idsToRestore)
            await loadPendingDeletions()
            selectedDeletions.removeAll()
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func performSync() {
        syncError = nil
        isSyncInitiating = true

        Task {
            do {
                try await syncClient.runSyncOnce(keepRunning: SettingsManager.shared.syncOnLaunch)
            } catch {
                syncError = error.localizedDescription
            }
            isSyncInitiating = false
        }
    }

    private func cancelSync() {
        Task {
            await syncClient.cancelSync()
            isSyncInitiating = false
        }
    }

    private func copyActivityToClipboard() {
        let lines: [String] = syncClient.activityLog.map { entry in
            let level: String
            switch entry.level {
            case .info: level = "info"
            case .success: level = "ok"
            case .warning: level = "warn"
            case .error: level = "error"
            }
            let time = Self.activityTimeFormatter.string(from: entry.timestamp)
            return "\(time) [\(level)] \(entry.message)"
        }
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyHistoryToClipboard() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        var text = "Sync History\n"
        text += "============\n\n"

        for event in syncManager.syncHistory {
            let status = event.status.rawValue.capitalized
            let time = dateFormatter.string(from: event.timestamp)
            let duration = event.duration.map { String(format: "%.1fs", $0) } ?? "-"

            text += "[\(status)] \(time)\n"
            text += "  Items: \(event.itemCount), Duration: \(duration)\n"

            if let error = event.errorMessage {
                text += "  Error: \(error)\n"
            }

            if !event.details.isEmpty {
                for detail in event.details {
                    text += "    • [\(detail.changeType.rawValue)] \(detail.recordType): \(detail.title)\n"
                }
            }

            if !event.activity.isEmpty {
                for entry in event.activity {
                    text += "    · [\(entry.level.rawValue.uppercased())] \(entry.message)\n"
                }
            }
            text += "\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct SyncClientLogRow: View {
    let entry: SyncActivityEntry
    let timestampText: String

    var body: some View {
        HStack(spacing: 8) {
            Text(timestampText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.8))
                .frame(width: 60, alignment: .leading)

            Image(systemName: entry.icon)
                .font(.system(size: 9))
                .foregroundColor(levelColor)
                .frame(width: 12)

            Text(entry.message)
                .font(.system(size: 12))
                .foregroundColor(Theme.current.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: return Theme.current.foregroundSecondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Navigable Sync Event Row

private struct NavigableSyncEventRow: View {
    let event: SyncEvent
    let onSelect: (SyncEvent) -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: { onSelect(event) }) {
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: event.status.icon)
                    .font(.system(size: 14))
                    .foregroundColor(event.status.color)
                    .frame(width: 20)

                // Timestamp
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTime(event.timestamp))
                        .font(.system(size: 12, weight: .medium))
                    Text(formatDate(event.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .frame(width: 80, alignment: .leading)

                // Summary
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(event.itemCount) item\(event.itemCount == 1 ? "" : "s")")
                            .font(.system(size: 12))

                        if let duration = event.duration {
                            Text("•")
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Text(String(format: "%.1fs", duration))
                                .font(.system(size: 11))
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }

                    if let error = event.errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(isHovering ? 0.8 : 0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.7) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .onHover { hovering in isHovering = hovering }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    iOSSettingsView()
        .frame(width: 500, height: 700)
        .padding()
}
