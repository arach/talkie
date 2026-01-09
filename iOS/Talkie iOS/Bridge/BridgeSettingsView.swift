//
//  BridgeSettingsView.swift
//  Talkie iOS
//
//  Dedicated Mac Bridge connection management view for Settings
//

import SwiftUI

struct BridgeSettingsView: View {
    private var bridgeManager = BridgeManager.shared
    @State private var showingQRScanner = false
    @State private var showUnpairConfirmation = false
    @State private var isReconnecting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Connection Status Card
                    connectionStatusCard

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
                    if !bridgeManager.isPaired {
                        pairSection
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
        .alert("Unpair from Mac?", isPresented: $showUnpairConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unpair", role: .destructive) {
                bridgeManager.unpair()
            }
        } message: {
            Text("This will remove the pairing. Scan the QR code again to reconnect.")
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

                if let macName = bridgeManager.pairedMacName {
                    Text(macName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textSecondary)
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
        case .disconnected: return bridgeManager.isPaired ? "Disconnected" : "Not Paired"
        case .error: return "Connection Failed"
        }
    }

    private var totalSessionCount: Int {
        bridgeManager.projectPaths.reduce(0) { $0 + $1.sessions.count }
    }

    // MARK: - Actions Section

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
                    title: "Unpair from Mac",
                    color: .recording
                ) {
                    showUnpairConfirmation = true
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
                InfoRow(label: "Mac", value: bridgeManager.pairedMacName ?? "Unknown")
                if bridgeManager.status == .connected {
                    Divider().background(Color.borderPrimary)
                    InfoRow(label: "Connection", value: "via Tailscale")
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
            Text("Connect to your Mac to view and interact with Claude Code sessions remotely.")
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

            // Tailscale requirement hint
            HStack(spacing: Spacing.xs) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text("Requires Tailscale on both devices")
                    .font(.system(size: 11))
            }
            .foregroundColor(.textTertiary)
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
                TroubleshootingRow(text: "Tailscale running on both devices")
                Divider().background(Color.borderPrimary)
                TroubleshootingRow(text: "Both devices on same Tailscale network")
                Divider().background(Color.borderPrimary)
                TroubleshootingRow(text: "TalkieBridge running on Mac")
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
    NavigationView {
        BridgeSettingsView()
    }
}
