//
//  TerminalNext.swift
//  Talkie iOS
//
//  Next top-level SSH terminal surface. Owns the shell route for saved
//  hosts while preserving the existing SSHTerminalView flow for the
//  actual session UI.
//

import SwiftUI
import TalkieMobileKit

struct TerminalNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var connectionManager = SSHTerminalConnectionManager.shared
    @State private var savedHosts: [SSHTerminalSavedHost]
    @State private var liveSessions: [TerminalNextLiveSession] = []
    @State private var selectedSessionID: UUID?
    @State private var showingKeyImporter = false
    @State private var isImportingFromMac = false
    @State private var importMessage: String?

    private let savedHostStore = SSHTerminalSavedHostStore()
    private let privateKeyStore = SSHPrivateKeyStore()

    init() {
        _savedHosts = State(initialValue: SSHTerminalSavedHostStore().load())
    }

    private var selectedSession: TerminalNextLiveSession? {
        guard let selectedSessionID else { return nil }
        return liveSessions.first(where: { $0.id == selectedSessionID })
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            if let selectedSession {
                VStack(spacing: 0) {
                    liveSessionStrip

                    TerminalNextSessionPane(
                        liveSession: selectedSession,
                        didConsumeInitialHost: didConsumeInitialHostBinding(for: selectedSession),
                        onClose: {
                            closeLiveSession(selectedSession)
                        },
                        onShowSessions: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                selectedSessionID = nil
                            }
                            refreshHosts()
                        },
                        onConnectionIDChange: { connectionID in
                            selectedSession.activeConnectionID = connectionID
                        }
                    )
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    header

                    liveSessionStrip

                    Rectangle()
                        .fill(theme.currentTheme.chrome.edgeFaint)
                        .frame(height: theme.currentTheme.chrome.hairlineWidth)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            panelHeader

                            if savedHosts.isEmpty {
                                emptyState
                                    .padding(.top, 42)
                            } else {
                                hostList
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 96)
                    }
                    .scrollIndicators(.hidden)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: selectedSessionID)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: liveSessions.count)
        .onAppear {
            refreshHosts()
            consumePendingSSHImportIfNeeded()
        }
        .onChange(of: deepLinkManager.pendingSSHImport) { _, _ in
            consumePendingSSHImportIfNeeded()
        }
        .fullScreenCover(isPresented: $showingKeyImporter, onDismiss: refreshHosts) {
            SSHPrivateKeyQRCodeImportView { payload in
                handleImport(payload)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("TALKIE · TERMINAL")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

            addHostControl

            Button(action: closeTerminalSurface) {
                Image(systemName: "xmark")
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Terminal")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var liveSessionStrip: some View {
        if !liveSessions.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(liveSessions) { liveSession in
                        liveSessionChip(liveSession)
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            selectedSessionID = nil
                        }
                        refreshHosts()
                    } label: {
                        Label("New", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.colors.textPrimary)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(theme.colors.cardBackground)
                            .clipShape(.capsule)
                            .overlay {
                                Capsule()
                                    .stroke(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create terminal session")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .background(theme.colors.background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
            }
        }
    }

    private func liveSessionChip(_ liveSession: TerminalNextLiveSession) -> some View {
        let isSelected = selectedSessionID == liveSession.id

        return HStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    selectedSessionID = liveSession.id
                }
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(sessionStatusColor(liveSession.session.status))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(liveSession.host.previewTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(sessionStatusLabel(liveSession.session.status))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected ? theme.colors.cardBackground.opacity(0.72) : theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? theme.colors.cardBackground : theme.colors.textPrimary)
                .padding(.leading, 10)
                .padding(.trailing, 7)
                .frame(height: 36)
                .background(isSelected ? theme.colors.textPrimary : theme.colors.cardBackground)
                .clipShape(.capsule)
                .overlay {
                    Capsule()
                        .stroke(
                            isSelected ? theme.colors.textPrimary.opacity(0.18) : theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch to \(liveSession.host.previewTitle)")

            Button {
                closeLiveSession(liveSession)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? theme.colors.cardBackground.opacity(0.8) : theme.colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? theme.colors.textPrimary.opacity(0.14) : theme.currentTheme.chrome.edgeFaint.opacity(0.7))
                    .clipShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(liveSession.host.previewTitle)")
        }
        .padding(.trailing, 2)
    }

    @ViewBuilder
    private var addHostControl: some View {
        if bridgeManager.hasPairedMacs {
            Menu {
                Button {
                    importFromPairedMac()
                } label: {
                    Label("From Paired Mac", systemImage: "desktopcomputer.and.arrow.down")
                }
                .disabled(isImportingFromMac)

                Button {
                    showingKeyImporter = true
                } label: {
                    Label("Scan SSH QR", systemImage: "qrcode.viewfinder")
                }
            } label: {
                addHostIcon
            }
            .accessibilityLabel("Add terminal host")
        } else {
            Button(action: { showingKeyImporter = true }) {
                addHostIcon
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add terminal host")
        }
    }

    private var addHostIcon: some View {
        Image(systemName: "plus")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.currentTheme.chrome.accent)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(theme.currentTheme.chrome.accent.opacity(0.10))
                    .overlay(
                        Circle()
                            .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.28),
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Text("SAVED HOSTS")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)

            Spacer()

            if let bridgeLogHost {
                Button(action: { openBridgeLog(for: bridgeLogHost) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .accessibilityHidden(true)
                        Text("LOGS")
                            .talkieType(.chipLabel)
                    }
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .buttonStyle(.plain)
            }

            if bridgeManager.hasPairedMacs {
                Button(action: importFromPairedMac) {
                    Text(isImportingFromMac ? "CONNECTING" : "FROM MAC")
                        .talkieType(.chipLabel)
                        .foregroundStyle(isImportingFromMac ? theme.colors.textTertiary : theme.currentTheme.chrome.accent)
                }
                .buttonStyle(.plain)
                .disabled(isImportingFromMac)
            }

            Button(action: { showingKeyImporter = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .accessibilityHidden(true)
                    Text("ADD HOST")
                        .talkieType(.chipLabel)
                }
                .foregroundStyle(theme.currentTheme.chrome.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }

    // MARK: - Content

    private var hostList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let importMessage {
                Text(importMessage)
                    .talkieType(.hint)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(height: 32, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(theme.currentTheme.chrome.edgeFaint)
                            .frame(height: theme.currentTheme.chrome.hairlineWidth)
                    }
            }

            ForEach(savedHosts) { host in
                hostRow(host)
            }

            addHostRow
        }
    }

    private var addHostRow: some View {
        Button(action: { showingKeyImporter = true }) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add another host")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(bridgeManager.hasPairedMacs ? "Scan an SSH QR, or use the + menu for paired Mac import" : "Scan an SSH access QR from Talkie for Mac")
                        .talkieType(.hint)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 10)

                Text("ADD")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
        .accessibilityLabel("Add another terminal host")
    }

    private func hostRow(_ host: SSHTerminalSavedHost) -> some View {
        HStack(spacing: 10) {
            Button {
                openHost(host)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(host.previewTitle)
                            .talkieType(.fieldLabel)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(host.previewSubtitle)
                            .talkieType(.hint)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("Routes · \(routeCascadeSummary(for: host))")
                            .talkieType(.hint)
                            .foregroundStyle(theme.colors.textTertiary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 10)

            HStack(spacing: 5) {
                statusDot(for: host)
                Text(host.previewSourceLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
            }

            routeMenu(for: host)
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }

    private func routeMenu(for host: SSHTerminalSavedHost) -> some View {
        Menu {
            Button {
                openHost(host)
            } label: {
                Label("Classic Cascade", systemImage: "arrow.triangle.branch")
            }

            Button {
                openBridgeLog(for: host)
            } label: {
                Label("Tail Bridge + Agent Logs", systemImage: "doc.text.magnifyingglass")
            }

            ForEach(routeOptions(for: host)) { option in
                Button {
                    openHost(host, preferredRoute: option.route)
                } label: {
                    Label("Prefer \(option.route.displayName)", systemImage: option.systemImage)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Terminal route options")
    }

    private func statusDot(for host: SSHTerminalSavedHost) -> some View {
        let isActive = connectionManager.activeConnection(for: host) != nil

        return Circle()
            .fill(isActive ? theme.currentTheme.chrome.accent : theme.colors.textTertiary.opacity(0.35))
            .frame(width: 6, height: 6)
            .accessibilityLabel(isActive ? "Active terminal" : "Saved terminal")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .foregroundStyle(theme.colors.textTertiary.opacity(0.7))
                .frame(width: 42, height: 42)

            VStack(spacing: 6) {
                Text("No saved hosts")
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)

                Text(emptyStateMessage)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if bridgeManager.hasPairedMacs {
                    Button(action: importFromPairedMac) {
                        Text(isImportingFromMac ? "CONNECTING" : "USE PAIRED MAC")
                            .talkieType(.chipLabel)
                            .foregroundStyle(theme.colors.cardBackground)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(theme.currentTheme.chrome.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(isImportingFromMac)
                }

                Button(action: { showingKeyImporter = true }) {
                    Text(bridgeManager.hasPairedMacs ? "SCAN QR" : "ADD HOST")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay {
                            Capsule()
                                .stroke(theme.currentTheme.chrome.accent.opacity(0.55), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }

            if let importMessage {
                Text(importMessage)
                    .talkieType(.hint)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private var emptyStateMessage: String {
        if bridgeManager.hasPairedMacs {
            return "Use your paired Mac on Wi-Fi to prepare terminal access, or scan the SSH access QR as a fallback."
        }

        return "Scan the SSH access QR from Talkie for Mac to add a terminal destination."
    }

    private var bridgeLogHost: SSHTerminalSavedHost? {
        savedHosts.first(where: \.isTalkieManagedTerminalHost) ?? savedHosts.first
    }

    private func didConsumeInitialHostBinding(for liveSession: TerminalNextLiveSession) -> Binding<Bool> {
        Binding(
            get: { liveSession.didConsumeInitialHost },
            set: { liveSession.didConsumeInitialHost = $0 }
        )
    }

    private func sessionStatusColor(_ status: SSHTerminalSession.Status) -> Color {
        switch status {
        case .connected:
            return theme.colors.success
        case .connecting:
            return .warning
        case .failed:
            return .recording
        case .disconnected:
            return theme.colors.textTertiary.opacity(0.58)
        }
    }

    private func sessionStatusLabel(_ status: SSHTerminalSession.Status) -> String {
        switch status {
        case .connected:
            return "Live"
        case .connecting:
            return "Opening"
        case .failed:
            return "Needs attention"
        case .disconnected:
            return "Idle"
        }
    }

    private func closeLiveSession(_ liveSession: TerminalNextLiveSession) {
        if let activeConnectionID = liveSession.activeConnectionID {
            connectionManager.clearActiveConnection(id: activeConnectionID)
        }

        Task { @MainActor in
            await liveSession.session.disconnect()
        }

        let wasSelected = selectedSessionID == liveSession.id
        liveSessions.removeAll { $0.id == liveSession.id }

        if wasSelected {
            selectedSessionID = liveSessions.last?.id
        }

        refreshHosts()
    }

    private func closeAllLiveSessions() {
        let sessions = liveSessions
        liveSessions.removeAll()
        selectedSessionID = nil
        connectionManager.clearAllActiveConnections()

        Task { @MainActor in
            for liveSession in sessions {
                await liveSession.session.disconnect()
            }
        }
    }

    private func closeTerminalSurface() {
        closeAllLiveSessions()
        AppShellRouter.shared.openHome()
    }

    // MARK: - Data

    private func refreshHosts() {
        connectionManager.reload()
        savedHosts = savedHostStore.load()
    }

    private func handleImport(_ payload: SSHPrivateKeyQRCodePayload) {
        privateKeyStore.save(payload.normalizedPrivateKey)

        guard let connection = payload.connection,
              !connection.normalizedHost.isEmpty,
              !connection.normalizedUsername.isEmpty else {
            importMessage = "SSH key imported"
            refreshHosts()
            return
        }

        savedHosts = connectionManager.saveHost(
            host: connection.normalizedHost,
            port: connection.port,
            username: connection.normalizedUsername,
            startupProfile: connection.startupProfile,
            startupCommandOverride: connection.resolvedStartupCommand,
            deviceLabel: payload.label,
            alternateHosts: connection.normalizedAlternateHosts
        )
        importMessage = "Added \(payload.label ?? connection.normalizedHost)"

        if connection.shouldAutoConnect,
           let savedHost = savedHost(matching: connection) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                openHost(savedHost)
            }
        }
    }

    private func importFromPairedMac() {
        guard !isImportingFromMac else { return }

        isImportingFromMac = true
        importMessage = "Preparing terminal access from paired Mac..."

        Task { @MainActor in
            defer { isImportingFromMac = false }

            do {
                let payload = try await bridgeManager.terminalAccessPayload()
                handleImport(payload)
            } catch {
                importMessage = terminalAccessImportMessage(for: error)
            }
        }
    }

    private func terminalAccessImportMessage(for error: Error) -> String {
        if let bridgeError = error as? BridgeError {
            switch bridgeError {
            case .notConfigured:
                return "Pair this iPhone with your Mac first."
            case .connectionFailed:
                return "Could not reach your paired Mac on this network."
            case .httpError(let code):
                return "Mac returned HTTP \(code) while preparing terminal access."
            case .invalidResponse:
                return "Mac returned an invalid terminal access payload."
            case .pairingRejected:
                return "This iPhone is not approved by the Mac."
            case .messageFailed(let reason):
                return reason
            case .encryptionDowngrade:
                return "The Mac offered an unencrypted connection after previously using encryption. Refused for safety — reconnect on a trusted network."
            }
        }

        return SSHErrorFormatter.message(for: error)
    }

    private func consumePendingSSHImportIfNeeded() {
        guard let pendingImport = deepLinkManager.consumePendingSSHImport() else {
            return
        }

        handleImport(pendingImport.payload)
    }

    private func savedHost(matching connection: SSHPrivateKeyQRCodePayload.Connection) -> SSHTerminalSavedHost? {
        let host = connection.normalizedHost.lowercased()
        let username = connection.normalizedUsername.lowercased()
        return savedHosts.first { savedHost in
            savedHost.normalizedHost == host &&
                savedHost.normalizedUsername == username &&
                savedHost.port == connection.port
        } ?? savedHosts.first
    }

    private func openHost(
        _ host: SSHTerminalSavedHost,
        preferredRoute: TalkieNetworkRoute? = nil
    ) {
        let liveSession = TerminalNextLiveSession(
            host: host,
            preferredRoute: preferredRoute,
            oneShotStartupCommand: nil
        )
        liveSessions.append(liveSession)
        selectedSessionID = liveSession.id
    }

    private func openBridgeLog(
        for host: SSHTerminalSavedHost,
        preferredRoute: TalkieNetworkRoute? = nil
    ) {
        let liveSession = TerminalNextLiveSession(
            host: host,
            preferredRoute: preferredRoute,
            oneShotStartupCommand: SSHTerminalStartupProfile.bridgeLogTailCommand()
        )
        liveSessions.append(liveSession)
        selectedSessionID = liveSession.id
    }

    private func routeOptions(for host: SSHTerminalSavedHost) -> [TerminalNextRouteOption] {
        let routes = routeCandidates(for: host).map(\.route)
        var seen: [TalkieNetworkRoute] = []

        for route in routes where !seen.contains(route) {
            seen.append(route)
        }

        return seen.map { TerminalNextRouteOption(route: $0) }
    }

    private func routeCascadeSummary(for host: SSHTerminalSavedHost) -> String {
        let routes = orderedRoutes(for: routeCandidates(for: host))
        guard !routes.isEmpty else {
            return "Direct"
        }

        return routes
            .map(\.displayName)
            .joined(separator: " -> ")
    }

    private func routeCandidates(for host: SSHTerminalSavedHost) -> [(host: String, route: TalkieNetworkRoute)] {
        let rawHosts = [host.host] + (host.alternateHosts ?? [])
        var seenHosts: Set<String> = []
        var candidates: [(host: String, route: TalkieNetworkRoute)] = []

        for rawHost in rawHosts {
            let trimmedHost = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedHost = trimmedHost.lowercased()
            guard !trimmedHost.isEmpty, !seenHosts.contains(normalizedHost) else {
                continue
            }

            seenHosts.insert(normalizedHost)
            candidates.append((
                host: trimmedHost,
                route: TalkieNetworkRouteClassifier.route(for: trimmedHost)
            ))
        }

        return candidates
    }

    private func orderedRoutes(for candidates: [(host: String, route: TalkieNetworkRoute)]) -> [TalkieNetworkRoute] {
        let classicOrder: [TalkieNetworkRoute] = [.localNetwork, .tailscale, .direct]
        return classicOrder.filter { route in
            candidates.contains(where: { $0.route == route })
        }
    }
}

@MainActor
private final class TerminalNextLiveSession: Identifiable {
    let id = UUID()
    let host: SSHTerminalSavedHost
    let preferredRoute: TalkieNetworkRoute?
    let oneShotStartupCommand: String?
    let session = SSHTerminalSession()
    var didConsumeInitialHost = false
    var activeConnectionID: String?

    init(
        host: SSHTerminalSavedHost,
        preferredRoute: TalkieNetworkRoute?,
        oneShotStartupCommand: String?
    ) {
        self.host = host
        self.preferredRoute = preferredRoute
        self.oneShotStartupCommand = oneShotStartupCommand
    }
}

private struct TerminalNextRouteOption: Identifiable {
    let route: TalkieNetworkRoute

    var id: String {
        route.displayName
    }

    var systemImage: String {
        switch route {
        case .localNetwork:
            "wifi"
        case .tailscale:
            "point.3.connected.trianglepath.dotted"
        case .direct:
            "network"
        }
    }
}

private struct TerminalNextSessionPane: View {
    let liveSession: TerminalNextLiveSession
    let didConsumeInitialHost: Binding<Bool>
    let onClose: () -> Void
    let onShowSessions: () -> Void
    let onConnectionIDChange: (String?) -> Void

    var body: some View {
        SSHTerminalView(
            initialSavedHost: liveSession.host,
            initialRoutePreference: liveSession.preferredRoute,
            initialOneShotStartupCommand: liveSession.oneShotStartupCommand,
            externalSession: liveSession.session,
            disconnectOnDisappear: false,
            didConsumeInitialSavedHost: didConsumeInitialHost,
            onClose: onClose,
            onShowSessions: onShowSessions,
            onConnectionIDChange: onConnectionIDChange
        )
    }
}
