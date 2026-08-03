//
//  ConnectionCenterNext.swift
//  Talkie iOS
//
//  Connection health and repair surface for local storage, iCloud,
//  saved Mac bridges, nearby endpoint changes, and Command Deck.
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
            bridgePairingNeedsRefresh: bridgeManager.pairingNeedsRefresh,
            bridgeErrorMessage: bridgeManager.errorMessage
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
            _ = bridgeManager.errorMessage
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
                    bridgePairingNeedsRefresh: bridgeManager.pairingNeedsRefresh,
                    bridgeErrorMessage: bridgeManager.errorMessage
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
        bridgePairingNeedsRefresh: Bool,
        bridgeErrorMessage: String?
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
                return .error(bridgeErrorMessage ?? "Disconnected")
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
    @State private var nearbyBrowser = NearbyMacBrowser.shared
    @StateObject private var store = ConnectionCenterStore()
    @State private var editingMac: BridgeManager.PairedMac?
    @State private var macPendingRemoval: BridgeManager.PairedMac?
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 20) {
                    introSection
                        .padding(.top, 4)

                    if connectionNetworkStatus != .ok {
                        NetworkStatusBanner(status: connectionNetworkStatus, onRetry: refreshConnections)
                            .padding(.horizontal, 12)
                    }

                    VStack(spacing: 8) {
                        ForEach(store.rows.filter { $0.kind != .macBridge }) { row in
                            ConnectionRowNext(row: row, onAction: { handleAction(row.kind) })
                        }
                    }
                    .padding(.horizontal, 12)

                    savedMacsSection
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
        .task {
            nearbyBrowser.start()
        }
        .onDisappear {
            nearbyBrowser.stop()
        }
        .sheet(item: $editingMac) { mac in
            BridgeEndpointEditor(mac: mac) { hostname, port in
                try await bridgeManager.updatePairedMacEndpoint(
                    id: mac.id,
                    hostname: hostname,
                    port: port
                )
            }
        }
        .alert(
            "Remove Mac connection?",
            isPresented: removalConfirmation,
            presenting: macPendingRemoval
        ) { mac in
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                bridgeManager.removePairedMac(id: mac.id)
            }
        } message: { mac in
            Text("This removes the saved connection to \(displayName(for: mac)) from this device. You can pair it again later.")
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

    // MARK: - Saved Macs

    private var savedMacsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Bridges")
                        .talkieType(.listTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(bridgeManager.pairedMacs.isEmpty
                         ? "No saved Mac connections"
                         : "Choose, repair, or remove a saved Mac")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Spacer(minLength: 8)

                Button(action: refreshConnections) {
                    Label(isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }

            if bridgeManager.pairedMacs.isEmpty {
                Button(action: openBridgeDetail) {
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer.and.arrow.down")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pair a Mac")
                                .talkieType(.listTitle)
                                .foregroundStyle(theme.colors.textPrimary)
                            Text(nearbyBrowser.isBrowsing ? "Searching nearby · QR pairing available" : "Nearby and QR pairing")
                                .talkieType(.fieldLabel)
                                .foregroundStyle(theme.colors.textSecondary)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                    }
                    .padding(12)
                    .background(connectionCardBackground(border: theme.currentTheme.chrome.edgeFaint))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(bridgeManager.pairedMacs) { mac in
                    savedMacRow(mac)
                }

                Button(action: openBridgeDetail) {
                    Label("Pair another Mac or view diagnostics", systemImage: "plus.circle")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func savedMacRow(_ mac: BridgeManager.PairedMac) -> some View {
        let isActive = bridgeManager.activePairedMacID == mac.id
        let nearbyUpdate = nearbyEndpointUpdate(for: mac)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    if isActive {
                        openBridgeDetail()
                    } else {
                        Task { await bridgeManager.activatePairedMac(id: mac.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 20))
                                .foregroundStyle(isActive ? activeMacColor : theme.colors.textTertiary)
                                .frame(width: 32, height: 32)
                            Circle()
                                .fill(isActive ? activeMacColor : theme.colors.textTertiary)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(theme.colors.cardBackground, lineWidth: 1.5))
                                .offset(x: 2, y: 2)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName(for: mac))
                                .talkieType(.listTitle)
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)
                            Text(savedMacStatus(mac, isActive: isActive))
                                .talkieType(.fieldLabel)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                if isActive {
                    Text("ACTIVE")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(activeMacColor)
                }

                Menu {
                    if !isActive {
                        Button("Use This Mac", systemImage: "checkmark.circle") {
                            Task { await bridgeManager.activatePairedMac(id: mac.id) }
                        }
                    } else if bridgeManager.status != .connecting {
                        Button("Test Connection", systemImage: "arrow.clockwise") {
                            Task { await bridgeManager.retry() }
                        }
                    }

                    Button("Edit Host and Port", systemImage: "slider.horizontal.3") {
                        editingMac = mac
                    }
                    Button("View Diagnostics", systemImage: "stethoscope") {
                        if isActive {
                            openBridgeDetail()
                        } else {
                            Task {
                                await bridgeManager.activatePairedMac(id: mac.id)
                                openBridgeDetail()
                            }
                        }
                    }
                    Divider()
                    Button("Remove Connection", systemImage: "trash", role: .destructive) {
                        macPendingRemoval = mac
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 8)

            if let nearbyUpdate {
                Button {
                    Task {
                        try? await bridgeManager.updatePairedMacEndpoint(
                            id: mac.id,
                            hostname: nearbyUpdate.connectionHost,
                            port: nearbyUpdate.port
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Nearby Mac now uses \(nearbyUpdate.connectionHost):\(nearbyUpdate.port)")
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text("UPDATE")
                            .talkieType(.channelLabelTiny)
                    }
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(theme.currentTheme.chrome.edgeFaint)
                            .frame(height: theme.currentTheme.chrome.hairlineWidth)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(connectionCardBackground(border: isActive ? activeMacColor.opacity(0.32) : theme.currentTheme.chrome.edgeFaint))
    }

    private func connectionCardBackground(border: Color) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(border, lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
    }

    private var activeMacColor: Color {
        switch bridgeManager.status {
        case .connected: return .green
        case .connecting: return theme.currentTheme.chrome.accent
        case .disconnected: return .orange
        case .error: return .red
        }
    }

    private func savedMacStatus(_ mac: BridgeManager.PairedMac, isActive: Bool) -> String {
        let endpoint = "\(mac.hostname):\(mac.port)"
        guard isActive else { return "Saved · \(endpoint)" }

        switch bridgeManager.status {
        case .connected:
            return "Connected · \(endpoint)"
        case .connecting:
            return "Testing \(endpoint)"
        case .disconnected:
            return "Disconnected · \(endpoint)"
        case .error:
            return bridgeManager.errorMessage ?? "Couldn’t reach \(endpoint)"
        }
    }

    private func displayName(for mac: BridgeManager.PairedMac) -> String {
        let name = mac.pairedMacName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? mac.hostname : name
    }

    private func nearbyEndpointUpdate(for mac: BridgeManager.PairedMac) -> NearbyMacBrowser.NearbyMac? {
        let storedHost = normalizedLookup(mac.hostname)
        let storedName = normalizedLookup(mac.pairedMacName)

        return nearbyBrowser.macs.first { nearby in
            let sameMac = normalizedLookup(nearby.connectionHost) == storedHost ||
                (!storedName.isEmpty && normalizedLookup(nearby.name) == storedName)
            return sameMac && (nearby.connectionHost != mac.hostname || nearby.port != mac.port)
        }
    }

    private func normalizedLookup(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private var removalConfirmation: Binding<Bool> {
        Binding(
            get: { macPendingRemoval != nil },
            set: { if !$0 { macPendingRemoval = nil } }
        )
    }

    private func refreshConnections() {
        guard !isRefreshing else { return }
        isRefreshing = true
        nearbyBrowser.refresh()
        Task {
            if bridgeManager.isPaired {
                await bridgeManager.retry()
            }
            isRefreshing = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.goBack() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Back")
                        .talkieType(.preview)
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Connection Manager")
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

    // MARK: - Introduction

    private var introSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("Review and repair connections")
                    .talkieType(.listTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Refresh status, update a Mac host or port, switch the active bridge, or remove connections you no longer use.")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

// MARK: - Endpoint editor

private struct BridgeEndpointEditor: View {
    let mac: BridgeManager.PairedMac
    let onSave: (String, Int) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hostname: String
    @State private var portText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        mac: BridgeManager.PairedMac,
        onSave: @escaping (String, Int) async throws -> Void
    ) {
        self.mac = mac
        self.onSave = onSave
        _hostname = State(initialValue: mac.hostname)
        _portText = State(initialValue: String(mac.port))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Hostname or IP address", text: $hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Mac hostname or IP address")

                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Mac bridge port")
                } header: {
                    Text(displayName)
                } footer: {
                    Text("Talkie keeps the existing device identity and encryption keys. Saving immediately tests the endpoint when this is the active Mac.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Testing…" : "Save") {
                        save()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var displayName: String {
        let name = mac.pairedMacName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Saved Mac" : name
    }

    private var parsedPort: Int? {
        Int(portText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isValid: Bool {
        let host = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace }) else { return false }
        guard let parsedPort else { return false }
        return (1...65_535).contains(parsedPort)
    }

    private func save() {
        guard let parsedPort, isValid else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await onSave(hostname, parsedPort)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
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
