//
//  ConnectionCenterView.swift
//  Talkie macOS
//
//  Connection Center - unified view for managing all connectivity options
//  Progressive connectivity: Local → iCloud → iOS Bridge → Tailscale
//

import SwiftUI
import TalkieKit

// MARK: - Connection Types

enum ConnectionType: String, CaseIterable, Identifiable {
    case local = "local"
    case iCloud = "icloud"
    case iosBridge = "bridge"
    case tailscale = "tailscale"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Local Storage"
        case .iCloud: return "iCloud"
        case .iosBridge: return "iOS Bridge"
        case .tailscale: return "Tailscale"
        }
    }

    var subtitle: String {
        switch self {
        case .local: return "Your memos on this Mac"
        case .iCloud: return "Sync across Apple devices"
        case .iosBridge: return "Connect to Talkie on iPhone"
        case .tailscale: return "Remote access anywhere"
        }
    }

    var icon: String {
        switch self {
        case .local: return "externaldrive"
        case .iCloud: return "icloud"
        case .iosBridge: return "iphone.gen3.radiowaves.left.and.right"
        case .tailscale: return "network"
        }
    }

    var sortOrder: Int {
        switch self {
        case .local: return 0
        case .iCloud: return 1
        case .iosBridge: return 2
        case .tailscale: return 3
        }
    }

    /// Settings section to navigate to for configuration
    var settingsSection: SettingsSection? {
        switch self {
        case .local: return nil // Always active
        case .iCloud: return .iOS  // iCloud settings in iOS section
        case .iosBridge: return .iOS  // Bridge settings in iOS section
        case .tailscale: return nil // Shown in Bridge
        }
    }
}

// MARK: - Connection Row Status
// Note: Similar enum exists in iOS/Talkie iOS/Views/ConnectionCenterView.swift

enum ConnectionRowStatus: Equatable {
    case active
    case connected
    case syncing
    case notSetUp
    case notSignedIn
    case notAvailable
    case disabled
    case error(String)

    var displayText: String {
        switch self {
        case .active: return "Active"
        case .connected: return "Connected"
        case .syncing: return "Syncing"
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
    @AppStorage(SyncSettingsKey.iCloudEnabled) private var iCloudEnabled = true
    @State private var bridgeManager = BridgeManager.shared
    @Binding var selectedSection: SettingsSection

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "point.3.connected.trianglepath.dotted",
                title: "CONNECTIONS",
                subtitle: "Manage how Talkie syncs and connects across devices."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Connection overview
                Text("Talkie works offline by default. Add connections to sync and access your memos across devices.")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.bottom, Spacing.sm)

                // Connection rows
                VStack(spacing: Spacing.sm) {
                    ForEach(ConnectionType.allCases.sorted { $0.sortOrder < $1.sortOrder }) { type in
                        ConnectionRowView(
                            type: type,
                            status: status(for: type),
                            onNavigate: {
                                if let section = type.settingsSection {
                                    selectedSection = section
                                }
                            }
                        )
                    }
                }

                Divider()
                    .padding(.vertical, Spacing.sm)

                // Footer
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Each connection is optional and additive. Your memos are always stored locally first.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
        }
    }

    // MARK: - Status Logic

    private func status(for type: ConnectionType) -> ConnectionRowStatus {
        switch type {
        case .local:
            return .active

        case .iCloud:
            // Check CloudKit status - for now use AppStorage preference
            if iCloudEnabled {
                return .connected
            } else {
                return .disabled
            }

        case .iosBridge:
            // Check if any devices are paired
            if !bridgeManager.pairedDevices.isEmpty {
                // Check if bridge server is running
                if bridgeManager.bridgeStatus == .running {
                    return .connected
                } else {
                    return .error("Server stopped")
                }
            } else {
                return .notSetUp
            }

        case .tailscale:
            // Check Tailscale status
            switch bridgeManager.tailscaleStatus {
            case .ready:
                return .connected
            case .noPeers:
                return .connected // Connected but no peers
            case .offline:
                return .disabled
            case .notInstalled:
                return .notAvailable
            case .needsLogin:
                return .notSignedIn
            case .notRunning:
                return .disabled
            }
        }
    }
}

// MARK: - Connection Row View

struct ConnectionRowView: View {
    let type: ConnectionType
    let status: ConnectionRowStatus
    let onNavigate: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if type.settingsSection != nil {
                onNavigate()
            }
        }) {
            HStack(spacing: Spacing.sm) {
                // Icon with status indicator
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: type.icon)
                        .font(.system(size: 18))
                        .foregroundColor(status.isConnected ? Theme.current.accent : Theme.current.foregroundSecondary)
                        .frame(width: 28, height: 28)

                    // Status dot
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: 2)
                }

                // Title and subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.title)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(status.displayText)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                // Action indicator (only show when there's an action to take)
                if type != .local && !status.isConnected && type.settingsSection != nil {
                    HStack(spacing: 4) {
                        Text(actionText(for: type))
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(Theme.current.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.current.accent)
                    }
                }
            }
            .padding(Spacing.sm)
            .background(isHovered ? Theme.current.backgroundTertiary : Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(status.isConnected ? status.color.opacity(0.3) : Theme.current.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(type.settingsSection == nil && type != .local)
        .onHover { hovering in
            if type.settingsSection != nil {
                isHovered = hovering
            }
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
        case .notAvailable:
            return "Install"
        default:
            return "Manage"
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var section: SettingsSection = .connections
    ConnectionCenterView(selectedSection: $section)
        .frame(width: 400, height: 500)
}
