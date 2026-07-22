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

import Combine
import Observation
import SwiftUI

@MainActor
final class ConnectionCenterStore: ObservableObject {
    @Published var rows: [Row]
    @Published private(set) var currentStatuses: [Row.Kind: Row.Status] = [:]

    private let iCloudStatus = iCloudStatusManager.shared
    private let appSettings = TalkieAppSettings.shared
    private let bridgeManager = BridgeManager.shared
    private var cancellables = Set<AnyCancellable>()

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
        self.rows = []
        rebuildRows()
        bindUpdates()
        trackObservationBackedState()
    }

    func status(for kind: Row.Kind) -> Row.Status {
        currentStatuses[kind] ?? Self.status(
            for: kind,
            iCloudStatus: iCloudStatus.status,
            iCloudSyncEnabled: appSettings.iCloudSyncEnabled,
            bridgeIsPaired: bridgeManager.isPaired,
            bridgeStatus: bridgeManager.status,
            bridgePairingNeedsRefresh: bridgeManager.pairingNeedsRefresh
        )
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        appSettings.iCloudSyncEnabled = enabled
        rebuildRows()
    }

    private func bindUpdates() {
        iCloudStatus.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildRows() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: .bridgeDidConnect))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildRows() }
            .store(in: &cancellables)
    }

    private func trackObservationBackedState() {
        withObservationTracking {
            _ = appSettings.iCloudSyncEnabled
            _ = bridgeManager.isPaired
            _ = bridgeManager.status
            _ = bridgeManager.pairingNeedsRefresh
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.rebuildRows()
                self?.trackObservationBackedState()
            }
        }
    }

    private func rebuildRows() {
        let statuses = Dictionary(
            uniqueKeysWithValues: Row.Kind.allCases.map { kind in
                (kind, Self.status(
                    for: kind,
                    iCloudStatus: iCloudStatus.status,
                    iCloudSyncEnabled: appSettings.iCloudSyncEnabled,
                    bridgeIsPaired: bridgeManager.isPaired,
                    bridgeStatus: bridgeManager.status,
                    bridgePairingNeedsRefresh: bridgeManager.pairingNeedsRefresh
                ))
            }
        )

        currentStatuses = statuses
        rows = Row.Kind.allCases.map { kind in
            Row(
                id: kind,
                kind: kind,
                title: kind.title,
                description: kind.description,
                icon: kind.icon,
                status: statuses[kind] ?? .notAvailable
            )
        }
    }

    private static func status(
        for kind: Row.Kind,
        iCloudStatus: iCloudStatus,
        iCloudSyncEnabled: Bool,
        bridgeIsPaired: Bool,
        bridgeStatus: BridgeManager.ConnectionStatus,
        bridgePairingNeedsRefresh: Bool
    ) -> Row.Status {
        switch kind {
        case .local:
            return .active
        case .iCloud:
            switch iCloudStatus {
            case .available:
                return iCloudSyncEnabled ? .connected : .disabled
            case .noAccount:
                return .notSignedIn
            case .checking:
                return .syncing(count: 0)
            default:
                return .notAvailable
            }
        case .macBridge:
            guard bridgeIsPaired else { return .notSetUp }
            if bridgePairingNeedsRefresh {
                return .error("Re-pair required")
            }
            switch bridgeStatus {
            case .connected:
                return .connected
            case .connecting:
                return .syncing(count: 0)
            case .disconnected, .error:
                return .error("Disconnected")
            }
        }
    }
}

private extension ConnectionCenterStore.Row.Kind {
    var title: String {
        switch self {
        case .local: return "Local Storage"
        case .iCloud: return "iCloud"
        case .macBridge: return "Mac Bridge"
        }
    }

    var description: String {
        switch self {
        case .local: return "Your memos on this device"
        case .iCloud: return "Sync across Apple devices"
        case .macBridge: return "Connect to Talkie on Mac"
        }
    }

    var icon: String {
        switch self {
        case .local: return "iphone"
        case .iCloud: return "icloud"
        case .macBridge: return "desktopcomputer"
        }
    }
}

struct ConnectionCenterNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared
    @ObservedObject private var reachability = NetworkReachability.shared
    @State private var bridgeManager = BridgeManager.shared
    @StateObject private var store = ConnectionCenterStore()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    heroSection
                        .padding(.top, 8)

                    if connectionNetworkStatus != .ok {
                        NetworkStatusBanner(status: connectionNetworkStatus, onRetry: openBridgeDetail)
                            .padding(.horizontal, 12)
                    }

                    VStack(spacing: 8) {
                        ForEach(store.rows) { row in
                            ConnectionRowNext(row: row, onAction: { handleAction(row.kind) })
                        }
                    }
                    .padding(.horizontal, 12)

                    deckRemoteCard
                        .padding(.horizontal, 12)

                    footerSection

                    Spacer(minLength: 60)
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var connectionNetworkStatus: NetworkStatus {
        let bridgeStatus = store.status(for: .macBridge)
        if reachability.status == .offline,
           case .error = bridgeStatus {
            return .offline
        }

        if case .error(let message) = bridgeStatus {
            return .requestFailed(message: "Mac Bridge: \(message)")
        }

        return .ok
    }

    private func openBridgeDetail() {
        AppShellRouter.shared.openBridgeDetail()
    }

    private var deckRemoteCard: some View {
        Button(action: openDeckRemote) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(deckRemoteColor)
                        .frame(width: 32, height: 32)

                    Circle()
                        .fill(deckRemoteColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle().strokeBorder(theme.colors.cardBackground, lineWidth: 1.5)
                        )
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Command Deck")
                        .talkieType(.listTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(deckRemoteStatus)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text(deckRemoteActionTitle)
                        .talkieType(.fieldLabel)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(theme.currentTheme.chrome.accent)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                bridgeManager.isPaired
                                    ? deckRemoteColor.opacity(0.3)
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Command Deck")
        .accessibilityHint(
            bridgeManager.isPaired && !bridgeManager.pairingNeedsRefresh
                ? "Opens the Mac remote"
                : "Opens Mac pairing"
        )
    }

    private func openDeckRemote() {
        if bridgeManager.isPaired && !bridgeManager.pairingNeedsRefresh {
            AppShellRouter.shared.openDeck()
        } else {
            openBridgeDetail()
        }
    }

    private var deckRemoteActionTitle: String {
        if bridgeManager.pairingNeedsRefresh {
            return "Re-pair Mac"
        }
        return bridgeManager.isPaired ? "Open" : "Pair Mac"
    }

    private var deckRemoteStatus: String {
        if !bridgeManager.isPaired {
            return "Pair a Mac to use it as a remote"
        }

        let mac = bridgeManager.pairedMacDisplayName ?? bridgeManager.pairedHostname ?? "paired Mac"
        if let board = deck.board, !board.spaces.isEmpty {
            return "\(mac) · \(board.spaces.count) deck \(board.spaces.count == 1 ? "space" : "spaces")"
        }

        switch bridgeManager.status {
        case .connected:
            return "\(mac) connected · waiting for deck"
        case .connecting:
            return "\(mac) connecting"
        case .disconnected:
            return "\(mac) offline"
        case .error:
            return bridgeManager.errorMessage ?? "\(mac) unavailable"
        }
    }

    private var deckRemoteColor: Color {
        if !bridgeManager.isPaired {
            return theme.colors.textTertiary
        }
        if let board = deck.board, !board.spaces.isEmpty {
            return theme.currentTheme.chrome.accent
        }
        switch bridgeManager.status {
        case .connected:
            return Color(red: 0.36, green: 0.74, blue: 0.50)
        case .connecting:
            return theme.currentTheme.chrome.accent
        case .disconnected:
            return .orange.opacity(0.9)
        case .error:
            return .red.opacity(0.85)
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
                        .talkieType(.preview)
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Connections")
                .talkieType(.headlineSecondary)
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
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Text("Talkie works offline by default. Add connections to sync and access your memos across devices.")
                .talkieType(.preview)
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
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Text("Your memos are always stored locally first.")
                .talkieType(.fieldLabel)
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
            switch store.status(for: .iCloud) {
            case .notSignedIn:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            case .disabled:
                store.setICloudSyncEnabled(true)
            case .connected:
                store.setICloudSyncEnabled(false)
            default:
                break
            }
        case .macBridge:
            openBridgeDetail()
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
                        .talkieType(.listTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(row.status.displayText)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Spacer()

                if row.kind != .local && !row.status.isConnected, let label = actionLabel {
                    HStack(spacing: 4) {
                        Text(label)
                            .talkieType(.fieldLabel)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
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
