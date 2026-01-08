//
//  ConnectionCenterView.swift
//  Talkie iOS
//
//  Connection Center - unified view for managing all connectivity options
//  Progressive connectivity: Local → iCloud → Mac Bridge → Tailscale
//

import SwiftUI

// MARK: - Connection Types

enum ConnectionType: String, CaseIterable, Identifiable {
    case local = "local"
    case iCloud = "icloud"
    case macBridge = "bridge"
    case tailscale = "tailscale"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Local Storage"
        case .iCloud: return "iCloud"
        case .macBridge: return "Mac Bridge"
        case .tailscale: return "Tailscale"
        }
    }

    var subtitle: String {
        switch self {
        case .local: return "Your memos on this device"
        case .iCloud: return "Sync across Apple devices"
        case .macBridge: return "Connect to Talkie on Mac"
        case .tailscale: return "Remote access anywhere"
        }
    }

    var icon: String {
        switch self {
        case .local: return "iphone"
        case .iCloud: return "icloud"
        case .macBridge: return "desktopcomputer"
        case .tailscale: return "network"
        }
    }

    var sortOrder: Int {
        switch self {
        case .local: return 0
        case .iCloud: return 1
        case .macBridge: return 2
        case .tailscale: return 3
        }
    }
}

// MARK: - Connection Row Status (display status for Connection Center UI)

enum ConnectionRowStatus: Equatable {
    case active
    case connected
    case syncing(count: Int)
    case notSetUp
    case notSignedIn
    case notAvailable
    case disabled
    case error(String)

    var displayText: String {
        switch self {
        case .active: return "Active"
        case .connected: return "Connected"
        case .syncing(let count): return "Syncing \(count) memos"
        case .notSetUp: return "Not set up"
        case .notSignedIn: return "Not signed in"
        case .notAvailable: return "Not available"
        case .disabled: return "Disabled"
        case .error(let msg): return msg
        }
    }

    var color: Color {
        switch self {
        case .active, .connected, .syncing: return .green
        case .notSetUp, .notAvailable: return .gray
        case .notSignedIn, .disabled: return .orange
        case .error: return .red
        }
    }

    var isConnected: Bool {
        switch self {
        case .active, .connected, .syncing: return true
        default: return false
        }
    }
}

// MARK: - Connection Center View

struct ConnectionCenterView: View {
    // Load managers lazily on appear, not during init
    @State private var iCloudStatus: iCloudStatusManager?
    @State private var bridgeManager: BridgeManager?
    @State private var hasLoaded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                headerSection

                // Connection rows
                VStack(spacing: Spacing.sm) {
                    ForEach(ConnectionType.allCases.sorted { $0.sortOrder < $1.sortOrder }) { type in
                        ConnectionRowView(
                            type: type,
                            status: status(for: type),
                            action: { handleAction(for: type) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.md)

                // Footer explanation
                footerSection
            }
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.surfacePrimary)
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Load managers after view appears
            if !hasLoaded {
                iCloudStatus = iCloudStatusManager.shared
                bridgeManager = BridgeManager.shared
                hasLoaded = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.active)

            Text("Connection Center")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)

            Text("Talkie works offline by default. Add connections to sync and access your memos across devices.")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: Spacing.xs) {
            Text("Each connection is optional and additive.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)

            Text("Your memos are always stored locally first.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
        }
        .padding(.top, Spacing.lg)
    }

    // MARK: - Status Logic

    private func status(for type: ConnectionType) -> ConnectionRowStatus {
        switch type {
        case .local:
            return .active

        case .iCloud:
            guard let iCloudStatus = iCloudStatus else {
                // Show checking state while loading
                return .syncing(count: 0)
            }
            switch iCloudStatus.status {
            case .available:
                // Check if user has enabled iCloud sync
                let enabled = UserDefaults.standard.bool(forKey: "sync_icloud_enabled")
                if enabled {
                    return .connected
                } else {
                    return .disabled
                }
            case .noAccount:
                return .notSignedIn
            case .checking:
                return .syncing(count: 0)
            default:
                return .notAvailable
            }

        case .macBridge:
            guard let bridgeManager = bridgeManager else {
                // Show checking state while loading
                return .syncing(count: 0)
            }
            if bridgeManager.isPaired {
                switch bridgeManager.status {
                case .connected:
                    return .connected
                case .connecting:
                    return .syncing(count: 0)
                case .disconnected, .error:
                    return .error("Disconnected")
                }
            } else {
                return .notSetUp
            }

        case .tailscale:
            // TODO: Implement Tailscale detection
            return .notAvailable
        }
    }

    // MARK: - Actions

    private func handleAction(for type: ConnectionType) {
        switch type {
        case .local:
            // Local is always active, no action needed
            break

        case .iCloud:
            // Navigate to iCloud settings or toggle
            let currentStatus = status(for: .iCloud)
            if case .notSignedIn = currentStatus {
                // Open system settings
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }

        case .macBridge:
            // Navigation handled by NavigationLink in row
            break

        case .tailscale:
            // TODO: Open Tailscale or show setup instructions
            break
        }
    }
}

// MARK: - Connection Row View

struct ConnectionRowView: View {
    let type: ConnectionType
    let status: ConnectionRowStatus
    let action: () -> Void

    var body: some View {
        Group {
            if type == .macBridge {
                NavigationLink(destination: BridgeSettingsView()) {
                    rowContent
                }
            } else {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: Spacing.sm) {
            // Icon with status indicator
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(status.isConnected ? .active : .textTertiary)
                    .frame(width: 32, height: 32)

                // Status dot
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: 2)
            }

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(type.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textPrimary)

                Text(status.displayText)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Action indicator (only show when there's an action to take)
            if type != .local && !status.isConnected {
                if type == .macBridge || canSetUp(type) {
                    HStack(spacing: 4) {
                        Text(actionText(for: type))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.active)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.active)
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(status.isConnected ? status.color.opacity(0.3) : Color.borderPrimary, lineWidth: 0.5)
        )
    }

    private func canSetUp(_ type: ConnectionType) -> Bool {
        switch type {
        case .iCloud:
            return status == ConnectionRowStatus.notSignedIn
        case .macBridge:
            return status == ConnectionRowStatus.notSetUp
        case .tailscale:
            return false // Not implemented yet
        default:
            return false
        }
    }

    private func actionText(for type: ConnectionType) -> String {
        switch status {
        case .notSetUp:
            return "Set Up"
        case .notSignedIn:
            return "Sign In"
        case .disabled:
            return "Enable"
        default:
            return "Manage"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ConnectionCenterView()
    }
}
