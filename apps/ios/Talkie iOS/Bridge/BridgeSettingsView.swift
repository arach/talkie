//
//  BridgeSettingsView.swift
//  Talkie iOS
//
//  Dedicated Mac Bridge connection management view for Settings
//

import SwiftUI
import TalkieMobileKit

struct BridgeSettingsView: View {
    private var bridgeManager = BridgeManager.shared
    @State private var nearbyBrowser = NearbyMacBrowser.shared
    @State private var showingQRScanner = false
    @State private var showUnpairConfirmation = false
    @State private var isReconnecting = false
    @State private var pairingNearbyMacID: String?
    @State private var pendingRemovalMacID: String?
    @State private var pendingRemovalMacName = "this Mac"
    @State private var switchingMacID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Connection Status Card
                    connectionStatusCard

                    nearbyMacsSection

                    remoteAccessSection

                    if bridgeManager.hasPairedMacs {
                        pairedMacsSection
                    }

                    // Actions (when paired and not actively connecting)
                    if bridgeManager.isPaired && bridgeManager.status != .connecting {
                        actionsSection
                    }

                    // Connection Info (when connected)
                    if bridgeManager.status == .connected {
                        connectionInfoSection
                        doneButton
                    }

                    // Troubleshooting (when disconnected or error)
                    if bridgeManager.isPaired && (bridgeManager.status == .disconnected || bridgeManager.status == .error) {
                        troubleshootingSection
                    }

                    // Pair Button (when not paired)
                    if !bridgeManager.hasPairedMacs {
                        pairSection
                    } else {
                        pairAnotherSection
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
        }
        .navigationTitle("Mac Bridge")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingQRScanner) {
            QRScannerView()
        }
        .task {
            nearbyBrowser.start()
        }
        .onDisappear {
            nearbyBrowser.stop()
        }
        .alert("Unpair from Mac?", isPresented: $showUnpairConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unpair", role: .destructive) {
                if let pendingRemovalMacID {
                    bridgeManager.removePairedMac(id: pendingRemovalMacID)
                    self.pendingRemovalMacID = nil
                    self.pendingRemovalMacName = "this Mac"
                } else {
                    bridgeManager.unpair()
                }
            }
        } message: {
            Text("This will remove the pairing for \(pendingRemovalMacName). Scan the QR code again to reconnect.")
        }
    }

    // MARK: - Connection Status Card

    private var connectionStatusCard: some View {
        VStack(spacing: Spacing.md) {
            // Status icon - different for each state
            statusIconView

            // Status text
            VStack(spacing: Spacing.xxs) {
                Text(statusTitle)
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)

                if bridgeManager.hasPairedMacs {
                    Text(activeMacName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textSecondary)

                    Text(pairedMacCountLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }

                if let error = bridgeManager.errorMessage, bridgeManager.status == .error {
                    Text(error)
                        .font(.labelSmall)
                        .foregroundColor(.recording)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.xxs)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(statusBackground)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .strokeBorder(statusBorderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIconView: some View {
        switch bridgeManager.status {
        case .connected:
            // Success state - animated checkmark
            ZStack {
                Circle()
                    .fill(Color.success.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.success)
            }

        case .connecting:
            // Connecting - centered spinner
            ZStack {
                Circle()
                    .fill(Color.brandAccent.opacity(0.1))
                    .frame(width: 80, height: 80)

                BrailleSpinner(size: 32, color: .brandAccent)
                    .frame(width: 32, height: 32)
            }
            .frame(width: 80, height: 80)

        case .disconnected:
            ZStack {
                Circle()
                    .fill(Color.textTertiary.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "wifi.slash")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.textTertiary)
            }

        case .error:
            ZStack {
                Circle()
                    .fill(Color.recording.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.recording)
            }
        }
    }

    private var statusBackground: Color {
        switch bridgeManager.status {
        case .connected:
            return Color.success.opacity(0.05)
        case .connecting:
            return Color.brandAccent.opacity(0.03)
        default:
            return Color.surfaceSecondary
        }
    }

    private var statusBorderColor: Color {
        switch bridgeManager.status {
        case .connected:
            return Color.success.opacity(0.3)
        case .connecting:
            return Color.brandAccent.opacity(0.2)
        case .error:
            return Color.recording.opacity(0.3)
        default:
            return Color.borderPrimary
        }
    }

    private var statusTitle: String {
        switch bridgeManager.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return bridgeManager.hasPairedMacs ? "Disconnected" : "Not Paired"
        case .error: return "Connection Failed"
        }
    }

    private var totalSessionCount: Int {
        bridgeManager.projectPaths.reduce(0) { $0 + $1.sessions.count }
    }

    private var pairedMacCountLabel: String {
        let count = bridgeManager.pairedMacs.count
        return count == 1 ? "1 paired Mac" : "\(count) paired Macs"
    }

    private var activeMacName: String {
        bridgeManager.pairedMacDisplayName ?? bridgeManager.pairedHostname ?? "Paired Mac"
    }

    // MARK: - Actions Section

    private var remoteAccessSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("REMOTE ACCESS")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            NavigationLink(destination: SSHTerminalView()) {
                SettingsNavigationRow(
                    icon: "rectangle.and.terminal",
                    title: "SSH Terminal",
                    detail: "Direct host access"
                )
            }
            .accessibilityIdentifier("bridge.sshTerminal")
        }
    }

    private var nearbyMacsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("NEARBY MACS")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            VStack(spacing: Spacing.xs) {
                if nearbyBrowser.macs.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        BrailleSpinner(size: 14, color: .textTertiary)
                            .frame(width: 22)
                        Text(nearbyBrowser.errorMessage ?? "Searching local network")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                        Spacer()
                    }
                    .padding(Spacing.md)
                    .background(Color.surfaceSecondary)
                    .cornerRadius(CornerRadius.sm)
                } else {
                    ForEach(nearbyBrowser.macs) { mac in
                        NearbyMacRow(
                            mac: mac,
                            isPairing: pairingNearbyMacID == mac.id,
                            isActive: bridgeManager.pairedHostname == mac.connectionHost,
                            onConnect: {
                                pairingNearbyMacID = mac.id
                                Task {
                                    _ = await bridgeManager.processNearbyMac(mac)
                                    pairingNearbyMacID = nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ACTIONS")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            VStack(spacing: Spacing.xs) {
                // Reconnect / Disconnect
                if bridgeManager.status == .connected {
                    SettingsActionRow(
                        icon: "wifi.slash",
                        title: "Disconnect",
                        color: .textSecondary
                    ) {
                        bridgeManager.disconnect()
                    }
                } else {
                    SettingsActionRow(
                        icon: "arrow.clockwise",
                        title: isReconnecting ? "Reconnecting..." : "Reconnect",
                        color: .brandAccent,
                        isLoading: isReconnecting || bridgeManager.status == .connecting
                    ) {
                        isReconnecting = true
                        Task {
                            await bridgeManager.retry()
                            isReconnecting = false
                        }
                    }
                    .disabled(bridgeManager.status == .connecting)
                }

                // View Sessions (when connected)
                if bridgeManager.status == .connected {
                    NavigationLink(destination: SessionListView()) {
                        HStack {
                            Image(systemName: "terminal")
                                .font(.system(size: 16))
                                .frame(width: 24)
                            Text("View Sessions")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            Text("\(totalSessionCount)")
                                .font(.monoSmall)
                                .foregroundColor(.textTertiary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        .foregroundColor(.textPrimary)
                        .padding(Spacing.md)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(CornerRadius.sm)
                    }
                }

                // Unpair
                SettingsActionRow(
                    icon: "xmark.circle",
                    title: bridgeManager.pairedMacs.count > 1 ? "Remove Active Mac" : "Unpair from Mac",
                    color: .recording
                ) {
                    pendingRemovalMacID = bridgeManager.activePairedMacID
                    pendingRemovalMacName = activeMacName
                    showUnpairConfirmation = true
                }
            }
        }
    }

    private var pairedMacsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PAIRED MACS")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            VStack(spacing: Spacing.xs) {
                ForEach(bridgeManager.pairedMacs) { pairedMac in
                    PairedMacRow(
                        pairedMac: pairedMac,
                        isActive: bridgeManager.activePairedMacID == pairedMac.id,
                        isConnected: bridgeManager.activePairedMacID == pairedMac.id && bridgeManager.status == .connected,
                        isSwitching: switchingMacID == pairedMac.id,
                        onSelect: {
                            guard bridgeManager.activePairedMacID != pairedMac.id else { return }
                            switchingMacID = pairedMac.id
                            Task {
                                await bridgeManager.activatePairedMac(id: pairedMac.id)
                                switchingMacID = nil
                            }
                        },
                        onRemove: {
                            pendingRemovalMacID = pairedMac.id
                            pendingRemovalMacName = pairedMac.pairedMacName.isEmpty ? pairedMac.hostname : pairedMac.pairedMacName
                            showUnpairConfirmation = true
                        }
                    )
                }
            }
        }
    }

    // MARK: - Connection Info Section

    private var connectionInfoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("CONNECTION INFO")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            VStack(spacing: 0) {
                InfoRow(label: "Status", value: bridgeManager.status.rawValue)
                Divider().background(Color.borderPrimary)
                InfoRow(label: "Active Mac", value: activeMacName)
                Divider().background(Color.borderPrimary)
                InfoRow(label: "Paired Macs", value: "\(bridgeManager.pairedMacs.count)")
                if bridgeManager.status == .connected {
                    Divider().background(Color.borderPrimary)
                    InfoRow(label: "Connection", value: bridgeManager.activeRouteDescription)
                    Divider().background(Color.borderPrimary)
                    InfoRow(label: "Projects", value: "\(bridgeManager.projectPaths.count)")
                    Divider().background(Color.borderPrimary)
                    InfoRow(label: "Sessions", value: "\(totalSessionCount)")
                }
                Divider().background(Color.borderPrimary)
                InfoRow(label: "Device ID", value: String(bridgeManager.deviceId.prefix(8)) + "...")
            }
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
        }
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: { dismiss() }) {
            HStack(spacing: Spacing.xs) {
                Text("Done")
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(Color.success)
            .cornerRadius(CornerRadius.sm)
        }
        .padding(.top, Spacing.md)
    }

    // MARK: - Pair Section

    private var pairSection: some View {
        VStack(spacing: Spacing.md) {
            Text("Connect to a nearby Mac or scan a Talkie pairing code.")
                .font(.bodySmall)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            Button(action: { showingQRScanner = true }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan QR Code")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.brandAccent)
                .cornerRadius(CornerRadius.sm)
            }

            HStack(spacing: Spacing.xs) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text("Uses local network first, Tailscale when available")
                    .font(.system(size: 11))
            }
            .foregroundColor(.textTertiary)
        }
    }

    private var pairAnotherSection: some View {
        VStack(spacing: Spacing.md) {
            Text("Scan another Talkie QR code to add one more Mac without replacing the ones you already paired.")
                .font(.bodySmall)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            Button(action: { showingQRScanner = true }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus.rectangle.on.folder")
                    Text("Pair Another Mac")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.brandAccent)
                .cornerRadius(CornerRadius.sm)
            }
        }
    }

    // MARK: - Troubleshooting Section

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TROUBLESHOOTING")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            VStack(spacing: 0) {
                TroubleshootingRow(text: "Both devices are on the same local network")
                Divider().background(Color.borderPrimary)
                TroubleshootingRow(text: "Local Network access is allowed for Talkie")
                Divider().background(Color.borderPrimary)
                TroubleshootingRow(text: "Mac Bridge is running on the Mac")
            }
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
        }
    }
}

// MARK: - Troubleshooting Row

private struct TroubleshootingRow: View {
    let text: String

    var body: some View {
        HStack {
            Image(systemName: "circle")
                .font(.system(size: 6))
                .foregroundColor(.textTertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Settings Action Row

private struct SettingsActionRow: View {
    let icon: String
    let title: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    BrailleSpinner(size: 16, color: color)
                        .frame(width: 24)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .frame(width: 24)
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
            .foregroundColor(color)
            .padding(Spacing.md)
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
        }
        .disabled(isLoading)
    }
}

private struct NearbyMacRow: View {
    let mac: NearbyMacBrowser.NearbyMac
    let isPairing: Bool
    let isActive: Bool
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.success.opacity(0.16) : Color.surfacePrimary)
                        .frame(width: 30, height: 30)

                    if isPairing {
                        BrailleSpinner(size: 12, color: .brandAccent)
                    } else {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isActive ? .success : .textPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mac.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.success)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.success.opacity(0.12))
                                .clipShape(.capsule)
                        }
                    }

                    Text("\(mac.connectionHost):\(mac.port) · \(mac.routeLabel)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isActive ? "checkmark.circle.fill" : "arrow.right.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isActive ? .success : .brandAccent)
            }
            .padding(Spacing.md)
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
        .disabled(isPairing)
    }
}

private struct PairedMacRow: View {
    let pairedMac: BridgeManager.PairedMac
    let isActive: Bool
    let isConnected: Bool
    let isSwitching: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    private var displayName: String {
        pairedMac.pairedMacName.isEmpty ? pairedMac.hostname : pairedMac.pairedMacName
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onSelect) {
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(isConnected ? Color.success.opacity(0.16) : Color.surfacePrimary)
                            .frame(width: 30, height: 30)

                        if isSwitching {
                            BrailleSpinner(size: 12, color: .brandAccent)
                        } else {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isActive ? .textPrimary : .textTertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)

                            if isActive {
                                Text(isConnected ? "LIVE" : "ACTIVE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(isConnected ? .success : .brandAccent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background((isConnected ? Color.success : Color.brandAccent).opacity(0.12))
                                    .clipShape(.capsule)
                            }
                        }

                        Text(pairedMac.hostname)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if !isActive {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                }
                .padding(Spacing.md)
                .background(Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)
            .disabled(isSwitching)

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.recording)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

#Preview {
    NavigationStack {
        BridgeSettingsView()
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let detail: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))

                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
        }
        .foregroundColor(.textPrimary)
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.sm)
    }
}
