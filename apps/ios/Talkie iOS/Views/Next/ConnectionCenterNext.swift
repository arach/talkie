//
//  ConnectionCenterNext.swift
//  Talkie iOS
//
//  Phase 3+ paint shell — Mac bridge / connection center. Shows the
//  current connection state, paired devices, sync indicator, ICE/
//  STUN status if applicable. Donor is ConnectionCenterView (350
//  lines); this is the rebuilt frame.
//

import SwiftUI

@MainActor
final class ConnectionCenterStore: ObservableObject {
    @Published var connection: ConnectionDisplay

    struct ConnectionDisplay {
        let state: State
        let pairedDeviceName: String?
        let lastSyncLabel: String
        let bytesPerSec: String?
        let latencyMS: Int?

        enum State {
            case connected, paired, searching, offline
            var label: String {
                switch self {
                case .connected: return "Connected"
                case .paired:    return "Paired · idle"
                case .searching: return "Searching"
                case .offline:   return "Offline"
                }
            }
            var glyph: String {
                switch self {
                case .connected: return "antenna.radiowaves.left.and.right"
                case .paired:    return "link"
                case .searching: return "arrow.clockwise"
                case .offline:   return "antenna.radiowaves.left.and.right.slash"
                }
            }
        }
    }

    init() {
        self.connection = Self.mockConnection
    }

    static let mockConnection = ConnectionDisplay(
        state: .connected,
        pairedDeviceName: "Art's MacBook Pro",
        lastSyncLabel: "Just now",
        bytesPerSec: "14 KB/s",
        latencyMS: 42
    )
}

struct ConnectionCenterNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var store = ConnectionCenterStore()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusHero
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    if let device = store.connection.pairedDeviceName {
                        deviceCard(device)
                            .padding(.horizontal, 12)
                    }

                    metricsCard
                        .padding(.horizontal, 12)

                    actionButtons
                        .padding(.horizontal, 12)

                    Spacer(minLength: 80)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

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

            Text("Connection")
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

    private var statusHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(theme.currentTheme.chrome.accentTint)
                    .frame(width: 88, height: 88)
                Circle()
                    .strokeBorder(theme.currentTheme.chrome.accentStrong, lineWidth: 2)
                    .frame(width: 88, height: 88)
                    .shadow(color: theme.currentTheme.chrome.accentGlow,
                            radius: theme.currentTheme.chrome.glowRadius * 2)
                Image(systemName: store.connection.state.glyph)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }

            VStack(spacing: 4) {
                Text(store.connection.state.label)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .tracking(-0.3)

                Text("· LAST SYNC · \(store.connection.lastSyncLabel.uppercased())")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func deviceCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· PAIRED DEVICE")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                Image(systemName: "macbook")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("macOS · Talkie 2.5.20")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.textTertiary)
                }

                Spacer()

                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
        }
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· LINK")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                metricRow(label: "Throughput", value: store.connection.bytesPerSec ?? "—")
                divider
                metricRow(label: "Latency",    value: store.connection.latencyMS.map { "\($0) ms" } ?? "—")
                divider
                metricRow(label: "Transport",  value: "WebRTC · DTLS")
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeSubtle)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
            .padding(.leading, 14)
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.uppercase)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            secondaryButton(label: "Pair new", systemImage: "plus") { /* TODO */ }
            secondaryButton(label: "Disconnect", systemImage: "xmark") { /* TODO */ }
        }
    }

    private func secondaryButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(theme.colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }
}
