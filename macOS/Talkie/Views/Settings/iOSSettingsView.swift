//
//  iOSSettingsView.swift
//  Talkie macOS
//
//  Unified iOS connectivity settings - the user-centric "it just works" view.
//  Combines iCloud sync status + Bridge real-time features + device pairing.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import TalkieKit

struct iOSSettingsView: View {
    @State private var bridgeManager = BridgeManager.shared
    @AppStorage(SyncSettingsKey.iCloudEnabled) private var iCloudEnabled = true
    @State private var showingQRSheet = false
    @State private var isRefreshing = false

    var body: some View {
        SettingsPageContainer {
            HStack {
                SettingsPageHeader(
                    icon: "iphone",
                    title: "iOS",
                    subtitle: "Connect your iPhone to Talkie."
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
                // Overall Connection Status
                ConnectionStatusSection(
                    iCloudEnabled: iCloudEnabled,
                    bridgeStatus: bridgeManager.bridgeStatus,
                    deviceCount: bridgeManager.pairedDevices.count
                )

                Divider()

                // iCloud Sync
                iCloudSyncSection(enabled: $iCloudEnabled)

                Divider()

                // Real-time Features
                RealTimeFeaturesSection(
                    bridgeStatus: bridgeManager.bridgeStatus,
                    tailscaleStatus: bridgeManager.tailscaleStatus,
                    onShowQR: { showingQRSheet = true }
                )

                // Paired Devices
                if !bridgeManager.pairedDevices.isEmpty || bridgeManager.bridgeStatus == .running {
                    Divider()
                    PairedDevicesSection(
                        devices: bridgeManager.pairedDevices,
                        serverRunning: bridgeManager.bridgeStatus == .running,
                        onShowQR: { showingQRSheet = true },
                        onRemoveDevice: { id in Task { await bridgeManager.removeDevice(id) } },
                        onRemoveAll: { Task { await bridgeManager.removeAllDevices() } }
                    )
                }

                // Pending Pairings
                if !bridgeManager.pendingPairings.isEmpty {
                    Divider()
                    PendingPairingsSection(
                        pairings: bridgeManager.pendingPairings,
                        onApprove: { id in Task { await bridgeManager.approvePairing(id) } },
                        onReject: { id in Task { await bridgeManager.rejectPairing(id) } }
                    )
                }

                Divider()
                    .padding(.vertical, 4)

                // Info footer
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("iCloud syncs your memos across Apple devices. Direct Mac Connection enables real-time features like Claude Code sessions via Tailscale.")
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
            QRCodeSheet(qrData: bridgeManager.qrData)
        }
        .onAppear {
            bridgeManager.checkStatus()
        }
    }

    private func refresh() {
        isRefreshing = true
        bridgeManager.checkStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
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
                title: "Direct Mac Connection",
                description: "Real-time features available",
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
        if bridgeStatus != .running {
            upgrades.append(FeatureUpsell(
                icon: "bolt",
                title: "Direct Mac Connection",
                benefit: "Run Claude Code sessions, send messages to Mac, and more",
                action: "Start server below"
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
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)

            // Sync details when enabled
            if enabled {
                SyncDetailsView(
                    syncStatus: syncStatus,
                    inventory: talkieData.inventory,
                    onShowHistory: { showingSyncHistory = true }
                )
            }
        }
        .sheet(isPresented: $showingSyncHistory) {
            SyncHistorySheet()
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
        let isHealthy = talkieData.inventory?.isHealthy ?? true
        HStack(spacing: 3) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 8))
            Text(isHealthy ? "Healthy" : "Needs Sync")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(isHealthy ? .green : .orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isHealthy ? Color.green : Color.orange).opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Sync Details View

private struct SyncDetailsView: View {
    let syncStatus: SyncStatusManager
    let inventory: DataInventory?
    let onShowHistory: () -> Void
    @State private var syncManager = CloudKitSyncManager.shared
    @State private var showingSyncHistory = false
    @State private var selectedEvent: SyncEvent? = nil

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
                    selectedEvent = nil
                    showingSyncHistory = true
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
                            selectedEvent = event
                            showingSyncHistory = true
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
        }
        .padding(10)
        .background(Theme.current.surface1.opacity(0.5))
        .cornerRadius(6)
        .sheet(isPresented: $showingSyncHistory) {
            SyncHistorySheet(initialEvent: selectedEvent)
        }
    }
}

// MARK: - Sync Activity Row

private struct SyncActivityRow: View {
    let event: SyncEvent
    var onTap: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 6) {
                Text(formatTime(event.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.6))

                Image(systemName: changeIcon)
                    .font(.system(size: 8))
                    .foregroundColor(changeColor)

                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(1)

                Spacer()

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
        return parts.joined(separator: ", ")
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Real-time Features Section

private struct RealTimeFeaturesSection: View {
    let bridgeStatus: BridgeManager.BridgeStatus
    let tailscaleStatus: BridgeManager.TailscaleStatus
    let onShowQR: () -> Void

    @State private var bridgeManager = BridgeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("DIRECT MAC CONNECTION")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            VStack(spacing: 8) {
                // Status row
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

                    // Action button
                    actionButton
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)

                // Feature list when running
                if bridgeStatus == .running {
                    VStack(alignment: .leading, spacing: 6) {
                        FeatureRow(icon: "terminal", text: "Claude Code sessions", available: true)
                        FeatureRow(icon: "message", text: "Send messages to Mac", available: true)
                        FeatureRow(icon: "eye", text: "View active windows", available: true)
                    }
                    .padding(10)
                    .background(Theme.current.surface1.opacity(0.5))
                    .cornerRadius(6)
                }
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
        case .running: return "Available"
        case .starting: return "Starting..."
        case .stopped:
            if !tailscaleStatus.isReady {
                return "Tailscale Required"
            }
            return "Not Running"
        case .error: return "Error"
        }
    }

    private var statusDescription: String {
        switch bridgeStatus {
        case .running: return "Connected via Tailscale"
        case .starting: return "Starting Talkie Server..."
        case .stopped:
            if !tailscaleStatus.isReady {
                return tailscaleStatus.message
            }
            return "Start server to connect directly to Mac"
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
            if tailscaleStatus.isReady {
                Button(action: { Task { await bridgeManager.startBridge() } }) {
                    Text("START")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else {
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
        let tailscaleURL = URL(fileURLWithPath: "/Applications/Tailscale.app")
        NSWorkspace.shared.openApplication(at: tailscaleURL, configuration: NSWorkspace.OpenConfiguration())
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

// MARK: - Paired Devices Section

private struct PairedDevicesSection: View {
    let devices: [BridgeManager.PairedDevice]
    let serverRunning: Bool
    let onShowQR: () -> Void
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
                Text("PAIRED DEVICES")
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

                if serverRunning {
                    Button(action: onShowQR) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("PAIR")
                                .font(Theme.current.fontXSMedium)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
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
                        Text("No devices paired")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text(serverRunning
                             ? "Tap Pair to connect an iPhone"
                             : "Start server to pair devices")
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
                Text("Remove \"\(device.name)\" from paired devices? They will need to scan the QR code again to reconnect.")
            }
        }
        .alert("Remove All Devices?", isPresented: $showRemoveAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove All", role: .destructive) {
                onRemoveAll()
            }
        } message: {
            Text("Remove all \(devices.count) paired devices? They will need to scan the QR code again to reconnect.")
        }
    }
}

private struct PairedDeviceRow: View {
    let device: BridgeManager.PairedDevice
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
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

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontSM)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.current.fontSM)
                    .foregroundColor(.green)
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

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
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
                Text("PAIRING REQUESTS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(.orange)
            }

            ForEach(pairings) { pairing in
                HStack(spacing: 12) {
                    Image(systemName: "iphone.badge.plus")
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

// MARK: - QR Code Sheet

private struct QRCodeSheet: View {
    let qrData: BridgeManager.QRData?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Pair iPhone")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let qrData = qrData {
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

                    Text("Scan with Talkie on iPhone")
                        .font(.subheadline)
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
            } else {
                Text("Unable to generate QR code")
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 300)
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

private struct SyncHistorySheet: View {
    var initialEvent: SyncEvent? = nil
    @Environment(\.dismiss) private var dismissSheet
    @State private var selectedEvent: SyncEvent? = nil
    @State private var syncManager = CloudKitSyncManager.shared

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

private struct SyncEventDetailViewEmbedded: View {
    let event: SyncEvent
    let onBack: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Back")
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
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)

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
                            Text("No record details available")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
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

    @State private var pendingDeletions: [MemoModel] = []
    @State private var selectedDeletions: Set<UUID> = []
    @State private var isLoadingDeletions = false

    private let viewModel = MemosViewModel()

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
                if syncManager.isSyncing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Syncing...")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                } else {
                    Button {
                        syncManager.syncNow()
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
            text += "\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
