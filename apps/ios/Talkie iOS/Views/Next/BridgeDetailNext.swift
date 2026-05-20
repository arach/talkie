//
//  BridgeDetailNext.swift
//  Talkie iOS
//
//  STUB — Phase-1 placeholder. To be implemented by a dedicated
//  Codex stream:
//    - Replace the legacy `BridgeSettingsView` sheet (the last donor
//      surface alive in the new system, opened from
//      `ConnectionCenterNext`'s Mac Bridge row).
//    - Live status from `BridgeManager` (already published).
//    - Pairing flow: nearby Mac discovery via `NearbyMacBrowser`,
//      QR-pair flow via `SSHPrivateKeyQRCodePayload`.
//    - Session list (saved hosts) → row links into `TerminalNext`.
//    - Visual: SettingsNext-style sections (status header + action
//      rows), TalkieTypeStyle tokens.
//    - After this lands, `BridgeSettingsView`, `SessionListView`,
//      `SessionDetailView`, `DebugToolbar` (if no other callers)
//      can be retired — final donor cleanup.
//

import SwiftUI

struct BridgeDetailNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var nearbyBrowser = NearbyMacBrowser.shared
    @State private var savedHosts: [SSHTerminalSavedHost] = []
    @State private var showingQRPairing = false
    @State private var showingForgetConfirmation = false
    @State private var pairingNearbyMacID: String?
    @State private var isReconnecting = false

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider()
                    .background(theme.currentTheme.chrome.edgeFaint)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        statusSection
                        pairingSection
                        sessionsSection
                        actionsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task {
            savedHosts = SSHTerminalSavedHostStore().load()
            nearbyBrowser.start()
            if bridgeManager.status == .connected {
                await bridgeManager.refreshSessions()
            }
        }
        .onDisappear {
            nearbyBrowser.stop()
        }
        .fullScreenCover(isPresented: $showingQRPairing, onDismiss: reloadSavedHosts) {
            SSHPrivateKeyQRCodeImportView { _ in
                reloadSavedHosts()
            }
        }
        .alert("Forget Mac Bridge pairing?", isPresented: $showingForgetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Forget", role: .destructive) {
                bridgeManager.unpair()
                reloadSavedHosts()
            }
        } message: {
            Text("This removes the saved Mac pairing from this iPhone. Pair again with a nearby Mac or QR code to reconnect.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("TALKIE · MAC BRIDGE")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

            Button(action: { AppShellRouter.shared.openConnectionCenter() }) {
                Text("CLOSE")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(height: 28)
                    .padding(.horizontal, 10)
                    .background(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Sections

    private var statusSection: some View {
        section("STATUS") {
            field("State", statusTitle, hint: activeMacHint)
            field("Last seen", lastSeenText, hint: bridgeManager.activeRouteDescription)

            if let errorMessage = bridgeManager.errorMessage,
               bridgeManager.status == .error || bridgeManager.awaitingPairingApproval {
                field("Notice", errorMessage)
            }

            metricStrip(
                title: "LINK HEALTH",
                metrics: [
                    ("RTT", linkRTT),
                    ("SENT", sentMetric),
                    ("QUEUED", queuedMetric)
                ]
            )
        }
    }

    private var pairingSection: some View {
        section("PAIRING") {
            actionRow("Scan QR pair code", value: "OPEN", tone: .accent) {
                showingQRPairing = true
            }

            if nearbyBrowser.macs.isEmpty {
                passiveRow(
                    "Nearby Macs",
                    value: nearbyBrowser.errorMessage ?? (nearbyBrowser.isBrowsing ? "Searching" : "Idle"),
                    hint: "Talkie for Mac advertises on your local network"
                )
            } else {
                ForEach(nearbyBrowser.macs) { mac in
                    actionRow(
                        mac.name,
                        value: nearbyActionLabel(for: mac),
                        tone: bridgeManager.pairedHostname == mac.connectionHost ? .neutral : .accent
                    ) {
                        pair(mac)
                    }
                    .disabled(pairingNearbyMacID != nil)
                }
            }
        }
    }

    private var sessionsSection: some View {
        section("SESSIONS") {
            if savedHosts.isEmpty {
                passiveRow("Saved hosts", value: "None", hint: "Scan an SSH access QR to add a terminal")
            } else {
                ForEach(savedHosts) { host in
                    actionRow(host.previewTitle, value: "OPEN", tone: .accent) {
                        AppShellRouter.shared.openTerminal()
                    } hint: {
                        host.previewSubtitle
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        section("ACTIONS") {
            actionRow("Re-pair Mac", value: "OPEN", tone: .neutral) {
                showingQRPairing = true
            }

            actionRow(
                bridgeManager.status == .connected ? "Disconnect" : reconnectTitle,
                value: bridgeManager.status == .connected ? "RUN" : "TRY",
                tone: bridgeManager.status == .connected ? .neutral : .accent
            ) {
                if bridgeManager.status == .connected {
                    bridgeManager.disconnect()
                } else {
                    reconnect()
                }
            }
            .disabled(isReconnecting || bridgeManager.status == .connecting)

            actionRow("Forget pair", value: "RUN", tone: .warn) {
                showingForgetConfirmation = true
            }
            .disabled(!bridgeManager.hasPairedMacs)
        }
    }

    // MARK: - Row primitives

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .overlay(alignment: .bottom) {
                    hairline
                }

            content()
        }
    }

    private func field(_ label: String, _ value: String, hint: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)
                .layoutPriority(2)

            if let hint, !hint.isEmpty {
                Text("· \(hint)")
                    .talkieType(.hint)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Text(value)
                .talkieType(.fieldValue)
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            hairline
        }
    }

    private func passiveRow(_ label: String, value: String, hint: String? = nil) -> some View {
        field(label, value, hint: hint)
    }

    private enum ActionTone { case neutral, accent, warn }

    private func actionRow(
        _ label: String,
        value: String,
        tone: ActionTone,
        action: @escaping () -> Void,
        hint: () -> String? = { nil }
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let hint = hint(), !hint.isEmpty {
                    Text("· \(hint)")
                        .talkieType(.hint)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Text(value)
                    .talkieType(.chipLabel)
                    .foregroundStyle(actionColor(tone))
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                hairline
            }
        }
        .buttonStyle(.plain)
    }

    private func metricStrip(title: String, metrics: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
            }
            .frame(height: 32)
            .overlay(alignment: .bottom) {
                hairline
            }

            HStack(spacing: 0) {
                ForEach(metrics.indices, id: \.self) { idx in
                    VStack(spacing: 4) {
                        Text(metrics[idx].0)
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                        Text(metrics[idx].1)
                            .talkieType(.instrumentReadoutSmall)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)

                    if idx < metrics.count - 1 {
                        Rectangle()
                            .fill(theme.currentTheme.chrome.edgeFaint)
                            .frame(width: theme.currentTheme.chrome.hairlineWidth)
                            .padding(.vertical, 10)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                hairline
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
    }

    private func actionColor(_ tone: ActionTone) -> Color {
        switch tone {
        case .neutral: return theme.colors.textTertiary
        case .accent: return theme.currentTheme.chrome.accent
        case .warn: return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
    }

    // MARK: - State mapping

    private var statusTitle: String {
        if bridgeManager.awaitingPairingApproval {
            return "Pending approval"
        }

        switch bridgeManager.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return bridgeManager.hasPairedMacs ? "Disconnected" : "Not paired"
        case .error: return "Connection failed"
        }
    }

    private var activeMacHint: String? {
        bridgeManager.pairedMacDisplayName ?? bridgeManager.pairedHostname
    }

    private var lastSeenText: String {
        guard let date = lastSeenDate else { return "Never" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var lastSeenDate: Date? {
        if let date = bridgeManager.lastSuccessfulContactAt {
            return date
        }

        guard let timestamp = bridgeManager.activePairedMac?.lastSuccessfulContactAt,
              timestamp > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }

    private var linkRTT: String {
        bridgeManager.status == .connected ? "Live" : "—"
    }

    private var sentMetric: String {
        let count = bridgeManager.sessions.count
        return count == 0 ? "—" : "\(count)"
    }

    private var queuedMetric: String {
        bridgeManager.awaitingPairingApproval ? "1" : "0"
    }

    private var reconnectTitle: String {
        if isReconnecting || bridgeManager.status == .connecting {
            return "Reconnecting"
        }

        return "Reconnect"
    }

    private func nearbyActionLabel(for mac: NearbyMacBrowser.NearbyMac) -> String {
        if pairingNearbyMacID == mac.id {
            return "PAIRING"
        }

        if bridgeManager.pairedHostname == mac.connectionHost {
            return "PAIRED"
        }

        return "PAIR"
    }

    private func reloadSavedHosts() {
        savedHosts = SSHTerminalSavedHostStore().load()
    }

    private func pair(_ mac: NearbyMacBrowser.NearbyMac) {
        guard pairingNearbyMacID == nil else { return }
        pairingNearbyMacID = mac.id
        Task {
            _ = await bridgeManager.processNearbyMac(mac)
            pairingNearbyMacID = nil
            reloadSavedHosts()
        }
    }

    private func reconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true
        Task {
            await bridgeManager.retry()
            isReconnecting = false
        }
    }
}
