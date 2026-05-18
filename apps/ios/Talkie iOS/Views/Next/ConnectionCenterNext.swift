//
//  ConnectionCenterNext.swift
//  Talkie iOS
//
//  Faithful port of ConnectionCenterView (apps/ios/Talkie iOS/
//  Views/ConnectionCenterView.swift, 350 lines). Donor structure:
//
//  - Hero: `point.3.connected.trianglepath.dotted` icon, "Connection
//    Center" title, "Talkie works offline by default…" sub-copy.
//  - Body: three rows in sortOrder — Local / iCloud / Mac Bridge.
//    Each row: source icon (with status dot in bottom-right), title,
//    status display text, action chip on the right when connectable
//    (Set Up / Sign In / Enable / Manage).
//  - Footer: "Each connection is optional and additive." + "Your
//    memos are always stored locally first."
//
//  Status enum mirrors ConnectionRowStatus: active / connected /
//  syncing(count) / notSetUp / notSignedIn / notAvailable /
//  disabled / error(msg). Each maps to a status color (green /
//  gray / orange / red).
//

import SwiftUI

@MainActor
final class ConnectionCenterStore: ObservableObject {
    @Published var rows: [Row]

    struct Row: Identifiable {
        let id: Kind
        let kind: Kind
        let title: String
        let description: String
        let icon: String
        let status: Status

        enum Kind: String, CaseIterable { case local, iCloud, macBridge }

        enum Status: Equatable {
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
                case .active:                  return "Active"
                case .connected:               return "Connected"
                case .syncing(let count):      return count > 0 ? "Syncing \(count) memos" : "Syncing…"
                case .notSetUp:                return "Not set up"
                case .notSignedIn:             return "Not signed in"
                case .notAvailable:            return "Not available"
                case .disabled:                return "Disabled"
                case .error(let msg):          return msg
                }
            }

            var color: Color {
                switch self {
                case .active, .connected, .syncing: return .green
                case .notSetUp, .notAvailable:      return .gray
                case .notSignedIn, .disabled:       return .orange
                case .error:                        return .red
                }
            }

            var isConnected: Bool {
                switch self {
                case .active, .connected, .syncing: return true
                default: return false
                }
            }
        }
    }

    init() {
        self.rows = Self.mockRows
    }

    // Codex wires against iCloudStatusManager + TalkieAppSettings +
    // BridgeManager — same status-resolution logic the donor's
    // `status(for:)` function performs.

    static let mockRows: [Row] = [
        Row(id: .local, kind: .local,
            title: "Local Storage", description: "Your memos on this device",
            icon: "iphone", status: .active),
        Row(id: .iCloud, kind: .iCloud,
            title: "iCloud", description: "Sync across Apple devices",
            icon: "icloud", status: .notSignedIn),
        Row(id: .macBridge, kind: .macBridge,
            title: "Mac Bridge", description: "Connect to Talkie on Mac",
            icon: "desktopcomputer", status: .notSetUp),
    ]
}

struct ConnectionCenterNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store = ConnectionCenterStore()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    heroSection
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        ForEach(store.rows) { row in
                            ConnectionRowNext(row: row, onAction: { handleAction(row.kind) })
                        }
                    }
                    .padding(.horizontal, 12)

                    footerSection

                    Spacer(minLength: 60)
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Connections")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Color.clear.frame(width: 44, height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    // MARK: - Hero (matches donor's headerSection)

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Text("Connection Center")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)

            Text("Talkie works offline by default. Add connections to sync and access your memos across devices.")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Footer (matches donor)

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("Each connection is optional and additive.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textTertiary)
            Text("Your memos are always stored locally first.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.top, 14)
    }

    // MARK: - Actions

    private func handleAction(_ kind: ConnectionCenterStore.Row.Kind) {
        switch kind {
        case .local:
            // Always active; no action.
            break
        case .iCloud:
            // Donor opens Settings (UIApplication.openSettingsURLString)
            // when not signed in. Codex bridges the real flow.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .macBridge:
            // Donor pushes BridgeSettingsView. No Next port yet —
            // routing to Home as a soft fallback.
            AppShellRouter.shared.openHome()
        }
    }
}

// MARK: - Row

private struct ConnectionRowNext: View {
    let row: ConnectionCenterStore.Row
    let onAction: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: onAction) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: row.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(row.status.isConnected ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(row.status.color)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle().strokeBorder(theme.colors.cardBackground, lineWidth: 1.5)
                        )
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(row.status.displayText)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Spacer()

                if row.kind != .local && !row.status.isConnected, let label = actionLabel {
                    HStack(spacing: 4) {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                row.status.isConnected
                                    ? row.status.color.opacity(0.3)
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(row.kind == .local)
    }

    private var actionLabel: String? {
        switch row.status {
        case .notSetUp:    return "Set Up"
        case .notSignedIn: return "Sign In"
        case .disabled:    return "Enable"
        case .error:       return "Retry"
        default:           return nil
        }
    }
}
