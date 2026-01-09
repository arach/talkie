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
                        onShowQR: { showingQRSheet = true }
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

                    Text("iCloud syncs your memos automatically. Real-time features (like Claude Code sessions) require the Talkie Server running with Tailscale.")
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

// MARK: - Connection Status Section

private struct ConnectionStatusSection: View {
    let iCloudEnabled: Bool
    let bridgeStatus: BridgeManager.BridgeStatus
    let deviceCount: Int

    private var overallStatus: OverallStatus {
        let cloudOK = iCloudEnabled
        let realtimeOK = bridgeStatus == .running

        if cloudOK && realtimeOK {
            return .fullyConnected
        } else if cloudOK && !realtimeOK {
            return .cloudOnly
        } else if !cloudOK && realtimeOK {
            return .realtimeOnly
        } else {
            return .disconnected
        }
    }

    enum OverallStatus {
        case fullyConnected
        case cloudOnly
        case realtimeOnly
        case disconnected

        var icon: String {
            switch self {
            case .fullyConnected: return "checkmark.circle.fill"
            case .cloudOnly, .realtimeOnly: return "exclamationmark.circle.fill"
            case .disconnected: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .fullyConnected: return .green
            case .cloudOnly, .realtimeOnly: return .orange
            case .disconnected: return .red
            }
        }

        var title: String {
            switch self {
            case .fullyConnected: return "Fully Connected"
            case .cloudOnly: return "iCloud Only"
            case .realtimeOnly: return "Real-time Only"
            case .disconnected: return "Not Connected"
            }
        }

        var description: String {
            switch self {
            case .fullyConnected: return "Memos sync and real-time features available"
            case .cloudOnly: return "Memos sync, but real-time features unavailable"
            case .realtimeOnly: return "Real-time features work, but memos don't sync"
            case .disconnected: return "Enable iCloud or start server to connect"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("CONNECTION STATUS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 12) {
                Image(systemName: overallStatus.icon)
                    .font(.system(size: 28))
                    .foregroundColor(overallStatus.color)
                    .frame(width: 44, height: 44)
                    .background(overallStatus.color.opacity(0.15))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(overallStatus.title)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(overallStatus.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                // Quick status indicators
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: iCloudEnabled ? "checkmark" : "xmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("iCloud")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(iCloudEnabled ? .green : .gray)

                    HStack(spacing: 4) {
                        Image(systemName: bridgeStatus == .running ? "checkmark" : "xmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("Real-time")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(bridgeStatus == .running ? .green : .gray)
                }
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Summary line: "246 memos • Last sync 9:02 PM [History >]"
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                    Text("\(inventory?.local ?? 0) memos")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Theme.current.foregroundSecondary)

                Text(" • ")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))

                if let lastSync = syncStatus.lastSyncDate {
                    Text("Last sync \(formatTime(lastSync))")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundSecondary)
                } else {
                    Text("Never synced")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                }

                Spacer()

                Button(action: onShowHistory) {
                    HStack(spacing: 3) {
                        Text("History")
                            .font(.system(size: 9, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }

            // Recent activity (now filtered to meaningful changes only)
            let recentEvents = Array(syncManager.syncHistory.prefix(5))
            if !recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(recentEvents) { event in
                        SyncActivityRow(event: event)
                    }
                }
                .padding(8)
                .background(Theme.current.background.opacity(0.5))
                .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Theme.current.surface1.opacity(0.5))
        .cornerRadius(6)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Sync Activity Row

private struct SyncActivityRow: View {
    let event: SyncEvent

    var body: some View {
        HStack(spacing: 6) {
            Text(formatTime(event.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))

            Image(systemName: changeIcon)
                .font(.system(size: 7))
                .foregroundColor(changeColor)

            Text(description)
                .font(.system(size: 9))
                .foregroundColor(Theme.current.foregroundSecondary)
                .lineLimit(1)

            Spacer()
        }
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
                Text("REAL-TIME FEATURES")
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
        case .running: return "Server running on port 8765"
        case .starting: return "Starting Talkie Server..."
        case .stopped:
            if !tailscaleStatus.isReady {
                return tailscaleStatus.message
            }
            return "Start server to enable real-time features"
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SyncHistoryView()
            .environment(CloudKitSyncManager.shared)
            .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Preview

#Preview {
    iOSSettingsView()
        .frame(width: 500, height: 700)
        .padding()
}
