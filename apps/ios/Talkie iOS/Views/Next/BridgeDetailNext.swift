//
//  BridgeDetailNext.swift
//  Talkie iOS
//
//  Unified Next bridge detail surface.
//
//  Replaces the legacy `BridgeSettingsView` entry point with live
//  `BridgeManager` status, nearby Mac discovery, QR pairing, saved
//  terminal sessions, and SettingsNext-style action rows. Session
//  message history remains a separate donor gap tracked by the C5
//  parity audit.
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
                    VStack(alignment: .leading, spacing: 18) {
                        if !bridgeManager.hasPairedMacs {
                            MacCoachCard(
                                nearbyCount: nearbyBrowser.macs.count,
                                isSearching: nearbyBrowser.isBrowsing,
                                onScan: { showingQRPairing = true }
                            )
                        } else {
                            PairingPhaseBanner(phase: currentPhase)
                        }

                        if let errorMessage = bridgeManager.errorMessage,
                           bridgeManager.status == .error {
                            ErrorBanner(message: errorMessage) { reconnect() }
                        }

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

    // MARK: - Pairing phase derivation

    /// Derives the current pairing phase from BridgeManager + local
    /// UI state. The banner uses this to highlight the active step
    /// and mark previous steps as done.
    private var currentPhase: PairingPhase {
        if bridgeManager.status == .error {
            return .error
        }
        if bridgeManager.status == .connected {
            return .connected
        }
        if bridgeManager.awaitingPairingApproval || bridgeManager.status == .connecting {
            return .handshake
        }
        if pairingNearbyMacID != nil || showingQRPairing {
            return .pair
        }
        return .discover
    }
}

// MARK: - Pairing phase banner

private enum PairingPhase: Int, CaseIterable {
    case discover, pair, handshake, connected, error

    var label: String {
        switch self {
        case .discover:  return "DISCOVER"
        case .pair:      return "PAIR"
        case .handshake: return "HANDSHAKE"
        case .connected: return "LINKED"
        case .error:     return "ERROR"
        }
    }

    var icon: String {
        switch self {
        case .discover:  return "antenna.radiowaves.left.and.right"
        case .pair:      return "qrcode"
        case .handshake: return "key.horizontal"
        case .connected: return "checkmark.circle.fill"
        case .error:     return "exclamationmark.triangle.fill"
        }
    }
}

private struct PairingPhaseBanner: View {
    let phase: PairingPhase
    @ObservedObject private var theme = ThemeManager.shared

    private static let progression: [PairingPhase] = [.discover, .pair, .handshake, .connected]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("· FLOW")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Text(activeLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(activeColor)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 0) {
                ForEach(Array(Self.progression.enumerated()), id: \.offset) { idx, step in
                    PhaseChip(label: step.label,
                              icon: step.icon,
                              state: chipState(for: step))
                    if idx < Self.progression.count - 1 {
                        connector(beforeIndex: idx)
                    }
                }
            }
        }
    }

    private var activeLabel: String {
        phase == .error ? "Error — tap retry below" : phase.label
    }

    private var activeColor: Color {
        switch phase {
        case .error:     return Color(red: 0.85, green: 0.46, blue: 0.34)
        case .connected: return Color(red: 0.36, green: 0.74, blue: 0.50)
        default:         return theme.currentTheme.chrome.accent
        }
    }

    private func chipState(for step: PairingPhase) -> PhaseChip.State {
        if phase == .error { return step.rawValue < activeIndex ? .done : .pending }
        if step.rawValue < activeIndex { return .done }
        if step.rawValue == activeIndex { return .active }
        return .pending
    }

    private func connector(beforeIndex idx: Int) -> some View {
        let isDone = idx < activeIndex
        return Rectangle()
            .fill(isDone
                  ? Color(red: 0.36, green: 0.74, blue: 0.50).opacity(0.7)
                  : theme.currentTheme.chrome.edgeFaint)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private var activeIndex: Int {
        switch phase {
        case .discover:  return 0
        case .pair:      return 1
        case .handshake: return 2
        case .connected: return 3
        case .error:     return 2  // error sits at the handshake step
        }
    }
}

private struct PhaseChip: View {
    enum State { case pending, active, done }

    let label: String
    let icon: String
    let state: State

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .strokeBorder(stroke,
                                          lineWidth: state == .active ? 1.5 : theme.currentTheme.chrome.hairlineWidth)
                    )
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(glyphColor)
            }
            Text(label)
                .talkieType(.channelLabelTiny)
                .foregroundStyle(labelColor)
        }
    }

    private var fill: Color {
        switch state {
        case .pending: return Color.clear
        case .active:  return theme.currentTheme.chrome.accent.opacity(0.12)
        case .done:    return Color(red: 0.36, green: 0.74, blue: 0.50).opacity(0.18)
        }
    }

    private var stroke: Color {
        switch state {
        case .pending: return theme.currentTheme.chrome.edgeFaint
        case .active:  return theme.currentTheme.chrome.accent
        case .done:    return Color(red: 0.36, green: 0.74, blue: 0.50)
        }
    }

    private var glyphColor: Color {
        switch state {
        case .pending: return theme.colors.textTertiary
        case .active:  return theme.currentTheme.chrome.accent
        case .done:    return Color(red: 0.36, green: 0.74, blue: 0.50)
        }
    }

    private var labelColor: Color {
        switch state {
        case .active: return theme.colors.textPrimary
        default:      return theme.colors.textTertiary
        }
    }
}

// MARK: - Mac availability coach (empty state)

/// Onboarding card shown when no Mac has ever been paired.
/// Walks the user through what to do on the Mac side and offers a
/// QR fallback. Auto-dismisses once a pair lands (caller branches on
/// `bridgeManager.hasPairedMacs`).
private struct MacCoachCard: View {
    let nearbyCount: Int
    let isSearching: Bool
    let onScan: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                Text("· NO MAC YET")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Text(searchLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(searchColor)
            }

            Text("Pair a Mac to mirror your captures, run the bridge terminal, and keep the dictation pipeline warm across devices.")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                step(index: 1, title: "Open Talkie on your Mac", body: "macOS app must be running with bridge mode on.")
                step(index: 2, title: "Stay on the same network", body: "iPhone and Mac on the same Wi-Fi / hotspot.")
                step(index: 3, title: "Tap a nearby Mac below — or scan a QR", body: "Pairing handshake happens in seconds.")
            }

            HStack(spacing: 10) {
                Button(action: onScan) {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 12, weight: .medium))
                        Text("Scan QR pair code")
                            .talkieType(.fieldLabel)
                    }
                    .foregroundStyle(theme.colors.cardBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.35),
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private var searchLabel: String {
        if nearbyCount > 0 { return "\(nearbyCount) NEARBY" }
        return isSearching ? "SEARCHING" : "IDLE"
    }

    private var searchColor: Color {
        if nearbyCount > 0 {
            return Color(red: 0.36, green: 0.74, blue: 0.50)
        }
        return isSearching ? theme.currentTheme.chrome.accent : theme.colors.textTertiary
    }

    private func step(index: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.5),
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    .frame(width: 22, height: 22)
                Text("\(index)")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(body)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Error banner

private struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Connection error")
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(message)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: onRetry) {
                Text("RETRY")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.6),
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.45),
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}
