//
//  SSHTerminalView.swift
//  Talkie iOS
//
//  First-pass SSH terminal screen for iPhone and iPad.
//

import SwiftUI
import TalkieMobileKit
import UIKit

struct SSHTerminalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let initialSavedHost: SSHTerminalSavedHost?
    private let initialRoutePreference: TalkieNetworkRoute?
    private let initialOneShotStartupCommand: String?
    private let onClose: (() -> Void)?

    private static let startupCommandResetVersion = 8
    private static let legacyStartupCommand = "tmux new-session -A -s talkie"
    private static let pathAwareStartupCommand = #"export PATH="$HOME/bin:$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"; /opt/homebrew/bin/tmux new-session -A -s talkie"#
    private static let statusAwareStartupCommand = #"export PATH="$HOME/bin:$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"; /opt/homebrew/bin/tmux start-server; /opt/homebrew/bin/tmux set-option -g status off; /opt/homebrew/bin/tmux new-session -A -s talkie"#
    private static let previousDefaultStartupCommand = #"export PATH="$HOME/bin:$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"; /opt/homebrew/bin/tmux has-session -t talkie 2>/dev/null || /opt/homebrew/bin/tmux new-session -d -s talkie -c "$HOME" /bin/zsh -il; /opt/homebrew/bin/tmux set-option -t talkie status off >/dev/null 2>&1; /opt/homebrew/bin/tmux attach -t talkie"#
    private static let defaultStartupCommand = SSHTerminalStartupProfile.standardShell.startupCommand

    @AppStorage("sshTerminal.host") private var host = ""
    @AppStorage("sshTerminal.port") private var port = "22"
    @AppStorage("sshTerminal.username") private var username = ""
    @AppStorage("sshTerminal.startupCommand") private var startupCommand = Self.defaultStartupCommand
    @AppStorage("sshTerminal.startupCommandResetVersion") private var startupCommandResetVersion = 0
    @AppStorage("sshTerminal.startupProfile") private var startupProfileStorage = SSHTerminalStartupProfile.standardShell.rawValue
    @AppStorage("sshTerminal.primaryActionMode") private var primaryActionModeStorage = DockPrimaryActionMode.memo.rawValue
    @AppStorage("sshTerminal.renderer") private var terminalRendererStorage = SSHTerminalRenderer.ghostty.rawValue

    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    private let connectionManager = SSHTerminalConnectionManager.shared
    private let terminalRouter = SSHTerminalRouter.shared
    @State private var nearbyMacBrowser = NearbyMacBrowser.shared
    @State private var password = ""
    @State private var privateKeyPEM = SSHPrivateKeyStore().load() ?? ""
    @State private var savedHosts = SSHTerminalConnectionManager.shared.savedHosts
    @State private var session = SSHTerminalSession()
    @State private var showingRecordingView = false
    @State private var showingPrivateKey = false
    @State private var showingPrivateKeyScanner = false
    @State private var privateKeyImportMessage: String?
    @State private var terminalFocusRequestID = 0
    @State private var terminalDismissRequestID = 0
    @State private var terminalRefitRequestID = 0
    @State private var isTerminalKeyboardPresented = false
    @State private var terminalKeyboardHeight: CGFloat = 262
    @State private var showingConnectionDetails = true
    @State private var showingHostEditor = false
    @State private var pendingDeleteSavedHost: SSHTerminalSavedHost?
    @State private var showingCursorPad = false
    @State private var showingRendererLab = false
    @State private var rendererLabCaptureData: Data?
    @State private var rendererLabChunkRecords: [SSHTerminalOutputChunkRecord] = []
    @State private var accessoryRowMode: SSHAccessoryRowMode = .modifiers
    @State private var controlModifierState: SSHTerminalControlModifierState = .inactive
    @State private var shiftModifierState: SSHTerminalControlModifierState = .inactive
    @State private var cursorPadKnobOffset: CGSize = .zero
    @State private var cursorPadRepeatDirection: SSHTerminalCursorPadDirection?
    @State private var cursorPadRepeatTask: Task<Void, Never>?
    @State private var dockDictationState: InlineDictationController.State = .idle
    @State private var dockDictationError: String?
    @State private var pendingOneShotStartupCommand: String?
    @State private var pendingImportReview: PendingSSHImportReview?
    @State private var showingTroubleshootingLog = true
    @State private var copiedTroubleshootingReport = false
    @State private var didConsumeInitialSavedHost = false
    @State private var pendingRoutePreference: TalkieNetworkRoute?
    @State private var suppressPrimaryActionTap = false
    @State private var suppressSlashTap = false
    @State private var suppressDashTap = false
    @State private var suppressTildeTap = false
    @FocusState private var focusedField: Field?

    private let privateKeyStore = SSHPrivateKeyStore()
    @State private var dockDictationController = InlineDictationController()

    private enum Field {
        case host
        case port
        case username
        case password
    }

    private enum DockPrimaryActionMode: String {
        case memo
        case dictation
    }

    private enum SSHAccessoryRowMode {
        case modifiers
        case symbols
    }

    private struct SSHRouteCandidate: Equatable {
        let host: String
        let route: TalkieNetworkRoute

        var id: String {
            "\(route.displayName):\(host)"
        }

        var connectTimeoutSeconds: Int {
            switch route {
            case .localNetwork:
                return 2
            case .tailscale:
                return 6
            case .direct:
                return 8
            }
        }
    }

    init(
        initialSavedHost: SSHTerminalSavedHost? = nil,
        initialRoutePreference: TalkieNetworkRoute? = nil,
        initialOneShotStartupCommand: String? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.initialSavedHost = initialSavedHost
        self.initialRoutePreference = initialRoutePreference
        self.initialOneShotStartupCommand = initialOneShotStartupCommand
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                connectionChrome
                terminalSurface
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            "Delete Connection?",
            isPresented: Binding(
                get: { pendingDeleteSavedHost != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteSavedHost = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let pendingDeleteSavedHost else { return }
                delete(pendingDeleteSavedHost)
                self.pendingDeleteSavedHost = nil
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteSavedHost = nil
            }
        } message: {
            if let pendingDeleteSavedHost {
                Text("Remove \(pendingDeleteSavedHost.title) from your saved terminal destinations?")
            }
        }
        .onChange(of: session.status) {
            oldValue, newValue in
            handleSessionStatusChange(from: oldValue, to: newValue)
        }
        .onChange(of: showingHostEditor) { _, isPresented in
            if isPresented {
                terminalRouter.showEditor(savedHostID: currentSavedHost?.id)
            } else if session.status == .disconnected {
                terminalRouter.beginPresentation()
            }
        }
        .onChange(of: showingConnectionDetails) { _, _ in
            scheduleTerminalRefit(after: .milliseconds(240))
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: isTerminalKeyboardPresented) { _, _ in
            scheduleTerminalRefit(after: .milliseconds(160))
        }
        .onChange(of: terminalKeyboardHeight) { _, _ in
            scheduleTerminalRefit(after: .milliseconds(120))
        }
        .onChange(of: showingCursorPad) { _, _ in
            if !showingCursorPad {
                stopCursorPadRepeat(resetKnob: true)
            }
            scheduleTerminalRefit(after: .milliseconds(120))
        }
        .onChange(of: terminalRendererStorage) { _, _ in
            scheduleTerminalRefit(after: .milliseconds(80))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.status == .connected {
                sshBottomSystem
            }
        }
        .onAppear {
            AppLogger.ui.info("SSH terminal view appeared")
            terminalRouter.beginPresentation()
            terminalRendererStorage = SSHTerminalRenderer.ghostty.rawValue
            migrateStartupCommandIfNeeded()
            connectionManager.reload()
            refreshSavedHostsFromManager()
            refreshPrivateKeyFromStoreIfNeeded()
            configureDockDictationController()
            consumePendingSSHImportIfNeeded()
            consumeInitialSavedHostIfNeeded()
            if !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showingPrivateKey = true
            }
        }
        .onChange(of: deepLinkManager.pendingSSHImport) { _, _ in
            consumePendingSSHImportIfNeeded()
        }
        .fullScreenCover(isPresented: $showingPrivateKeyScanner) {
            SSHPrivateKeyQRCodeImportView { payload in
                queueImportReview(
                    payload: payload,
                    sourceDescription: reviewDescription(
                        for: payload,
                        source: "QR scan"
                    )
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingImportReview != nil },
            set: { isPresented in
                if !isPresented {
                    pendingImportReview = nil
                }
            }
        )) {
            if let pendingImportReview {
                SSHImportReviewSheet(
                    review: pendingImportReview,
                    keyAlreadyStored: !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onCancel: {
                        self.pendingImportReview = nil
                    },
                    onImport: { connectAfterImport, rememberConnection in
                        applyImportReview(
                            connectAfterImport: connectAfterImport,
                            rememberConnection: rememberConnection
                        )
                    }
                )
            }
        }
        .sheet(isPresented: $showingRecordingView) {
            RecordingView()
        }
        .sheet(isPresented: $showingHostEditor) {
            hostEditorSheet
        }
        .fullScreenCover(isPresented: $showingRendererLab) {
            NavigationStack {
                SSHTerminalGlyphLabView(
                    captureData: rendererLabCaptureData,
                    chunkRecords: rendererLabChunkRecords
                )
            }
        }
        .onDisappear {
            terminalRouter.markClosed()
            stopCursorPadRepeat(resetKnob: false)
            dockDictationController.cancel()
            if case .connected = session.status {
                saveCurrentHost()
            }
            persistPrivateKey()
            Task {
                await session.disconnect()
            }
        }
        .alert("Dictation Unavailable", isPresented: dockDictationErrorBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(dockDictationError ?? "")
        }
    }

    @ViewBuilder
    private var connectionChrome: some View {
        if session.status == .connected {
            if !isTerminalFocusedMode {
                connectedSessionCard
                    .padding(.top, Spacing.sm)
            }
        } else {
            VStack(spacing: Spacing.sm) {
                terminalScreenHeader

                if savedHosts.isEmpty {
                    firstConnectionCard
                } else if case .failed(let message) = session.status {
                    failedTroubleshootingCard(message: message)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                }
            }
        }
    }

    private var terminalScreenHeader: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: closeTerminal) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.surfaceSecondary)
                    .clipShape(.rect(cornerRadius: sshActionCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: sshActionCornerRadius, style: .continuous)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("Terminal")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer(minLength: 0)

            if session.status == .disconnected {
                terminalSecondaryActionButton("Scan", systemImage: "qrcode.viewfinder") {
                    showingPrivateKeyScanner = true
                }
                .accessibilityLabel("Scan SSH access QR code")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
    }

    private var firstConnectionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Get your terminal connected")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text("Scan the SSH access QR from Talkie for Mac, or add any SSH host manually if you want to use Talkie with a server that doesn’t run the Mac app.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                onboardingPoint(title: "Mac SSH access", detail: "Fastest path. Scan the SSH access QR from Talkie for Mac to add a one-tap terminal destination.")
                onboardingPoint(title: "Any SSH host", detail: "You can still add a host, username, and key manually for servers outside your Talkie devices.")
            }

            HStack(spacing: Spacing.sm) {
                terminalPrimaryActionButton(
                    "Scan SSH QR",
                    systemImage: "qrcode.viewfinder",
                    expands: true
                ) {
                    showingPrivateKeyScanner = true
                }

                terminalSecondaryActionButton("Manual") {
                    startNewHost()
                }
            }

            if case .failed(let message) = session.status {
                failedTroubleshootingCard(message: message)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: sshPanelCornerRadius))
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    private func reconnectErrorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.warning)
                .padding(.top, 1)

            Text(message)
                .font(.labelSmall)
                .foregroundStyle(Color.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.warning.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.warning.opacity(0.22), lineWidth: 1)
        }
    }

    private func failedTroubleshootingCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.warning)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Troubleshooting")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)

                    Text(message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.warning)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(troubleshootingSummary(message: message))
                        .font(.system(size: 12.5, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                troubleshootingMetaRow("Mode", value: session.launchModeLabel ?? selectedStartupProfile.title)

                if let launchCommandSummary = session.launchCommandSummary {
                    troubleshootingMetaRow("Start", value: launchCommandSummary)
                }

                if !session.endpointLabel.isEmpty {
                    troubleshootingMetaRow("Host", value: session.endpointLabel)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(troubleshootingSteps(message: message), id: \.self) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4.5, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.top, 6)

                        Text(step)
                            .font(.system(size: 12.5, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xs) {
                    terminalPrimaryActionButton("Retry", systemImage: "arrow.clockwise") {
                        connect()
                    }

                    if let fallbackProfile = troubleshootingFallbackProfile {
                        terminalSecondaryActionButton("Try \(fallbackProfile.title)") {
                            connectUsing(fallbackProfile)
                        }
                    }

                    terminalSecondaryActionButton("Config", systemImage: "slider.horizontal.3") {
                        showingHostEditor = true
                    }

                    terminalSecondaryActionButton(
                        copiedTroubleshootingReport ? "Copied" : "Copy Log",
                        systemImage: copiedTroubleshootingReport ? "checkmark" : "doc.on.doc"
                    ) {
                        copyTroubleshootingReport(message: message)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        terminalPrimaryActionButton("Retry", systemImage: "arrow.clockwise", expands: true) {
                            connect()
                        }

                        if let fallbackProfile = troubleshootingFallbackProfile {
                            terminalSecondaryActionButton("Try \(fallbackProfile.title)") {
                                connectUsing(fallbackProfile)
                            }
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        terminalSecondaryActionButton("Config", systemImage: "slider.horizontal.3") {
                            showingHostEditor = true
                        }

                        terminalSecondaryActionButton(
                            copiedTroubleshootingReport ? "Copied" : "Copy Log",
                            systemImage: copiedTroubleshootingReport ? "checkmark" : "doc.on.doc"
                        ) {
                            copyTroubleshootingReport(message: message)
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $showingTroubleshootingLog) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(session.recentDiagnostics.suffix(8))) { event in
                        HStack(alignment: .top, spacing: 6) {
                            Text(event.timestamp, format: .dateTime.hour().minute().second())
                                .foregroundStyle(Color.textTertiary)

                            Text(event.message)
                                .foregroundStyle(diagnosticColor(for: event.level))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Technical Log", systemImage: "terminal")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.warning.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.warning.opacity(0.22), lineWidth: 1)
        }
    }

    private var connectedSessionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                statusRow

                terminalSecondaryActionButton("Done") {
                    dismiss()
                }
            }

            HStack(spacing: Spacing.sm) {
                terminalSecondaryActionButton("Manage") {
                    showingHostEditor = true
                }

                terminalSecondaryActionButton("Disconnect") {
                    requestTerminalDismiss()
                    Task {
                        await session.disconnect()
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: sshPanelCornerRadius))
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }

    private func onboardingPoint(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Circle()
                .fill(Color.active.opacity(0.9))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.textTertiary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hasReusableCredential: Bool {
        !password.isEmpty || !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hostEditorSheet: some View {
        NavigationStack {
            ScrollView {
                hostEditorForm
            }
            .background(Color.surfacePrimary.ignoresSafeArea())
            .navigationTitle(currentSavedHost == nil ? "New Connection" : "Edit Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showingHostEditor = false
                    }
                }
            }
        }
    }

    private var hostEditorForm: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            statusRow

            if case .failed(let message) = session.status {
                failedTroubleshootingCard(message: message)
            }

            connectionFields

            HStack(spacing: Spacing.sm) {
                Button(action: connect) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: session.status == .connected ? "arrow.clockwise" : "terminal")
                        Text(session.status == .connected ? "Reconnect" : "Connect")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConnect)
                .accessibilityIdentifier("ssh.connect")

                Button(currentSavedHost == nil ? "Save Host" : "Update Host") {
                    saveCurrentHost()
                }
                .buttonStyle(.bordered)
                .disabled(!canSaveHost)
            }

            HStack(spacing: Spacing.sm) {
                if !password.isEmpty {
                    Button("Clear Password") {
                        password = ""
                    }
                    .buttonStyle(.bordered)
                }

                if !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Clear Key") {
                        privateKeyPEM = ""
                        privateKeyImportMessage = nil
                        privateKeyStore.delete()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let currentSavedHost {
                Button("Delete Connection", role: .destructive) {
                    pendingDeleteSavedHost = currentSavedHost
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.md)
        .padding(.bottom, Spacing.lg)
    }

    private var statusRow: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.headlineMedium)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityIdentifier("ssh.status.title")

                if case .failed(let message) = session.status {
                    Text(message)
                        .font(.labelSmall)
                        .foregroundStyle(Color.recording)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !session.endpointLabel.isEmpty {
                    Text(session.endpointLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                }

                if let trust = session.hostTrustMessage, let fingerprint = session.hostFingerprint {
                    Text("\(trust) · \(fingerprint)")
                        .font(.labelSmall)
                        .foregroundStyle(Color.textTertiary)
                }

                if session.status != .connected {
                    if let launchModeLabel = session.launchModeLabel {
                        Text("Mode · \(launchModeLabel)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                    }

                    if let launchCommandSummary = session.launchCommandSummary {
                        Text("Start · \(launchCommandSummary)")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !session.recentDiagnostics.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(session.recentDiagnostics.suffix(4))) { event in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                                        .foregroundStyle(Color.textTertiary)

                                    Text(event.message)
                                        .foregroundStyle(diagnosticColor(for: event.level))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }

            Spacer()
        }
    }

    private var connectionFields: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                field("Host", text: $host, field: .host)
                field("Port", text: $port, field: .port, keyboardType: .numbersAndPunctuation)
                    .frame(maxWidth: 88)
            }

            HStack(spacing: Spacing.sm) {
                field("Username", text: $username, field: .username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 10)
                    .background(Color.surfacePrimary)
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                    .accessibilityIdentifier("ssh.password")
            }

            DisclosureGroup(isExpanded: $showingPrivateKey) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    TextEditor(text: $privateKeyPEM)
                        .font(.system(size: 12, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.surfacePrimary)
                        .clipShape(.rect(cornerRadius: CornerRadius.sm))
                        .accessibilityIdentifier("ssh.privateKey")

                    HStack(spacing: Spacing.xs) {
                        Text("Supports unencrypted OpenSSH Ed25519 and PEM P256, P384, or P521 keys.")
                            .font(.labelSmall)
                            .foregroundStyle(Color.textTertiary)

                        Spacer(minLength: 0)

                        Button("Scan QR") {
                            focusedField = nil
                            showingPrivateKeyScanner = true
                        }
                        .buttonStyle(.bordered)

                        Button("Store Key") {
                            persistPrivateKey()
                            privateKeyImportMessage = "SSH key stored on this device."
                        }
                        .buttonStyle(.bordered)
                        .disabled(privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let privateKeyImportMessage {
                        Text(privateKeyImportMessage)
                            .font(.labelSmall)
                            .foregroundStyle(Color.success)
                    }
                }
                .padding(.top, Spacing.xs)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("Private Key")
                        .font(.bodySmall)
                        .foregroundStyle(Color.textPrimary)

                    Spacer(minLength: 0)

                    Button("Scan QR") {
                        focusedField = nil
                        showingPrivateKeyScanner = true
                    }
                    .buttonStyle(.bordered)

                    if !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("stored on device")
                            .font(.labelSmall)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Launch Style")
                        .font(.bodySmall)
                        .foregroundStyle(Color.textPrimary)

                    Spacer(minLength: 0)

                    Text(selectedStartupProfile.title)
                        .font(.labelSmall)
                        .foregroundStyle(Color.textTertiary)
                }

                Picker("Launch Style", selection: startupProfileBinding) {
                    ForEach(SSHTerminalStartupProfile.allCases, id: \.self) { profile in
                        Text(profile.shortTitle)
                            .tag(profile)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedStartupProfile.summary)
                    .font(.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var savedHostsSection: some View {
        if !savedHosts.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Saved Hosts")
                    .font(.labelSmall)
                    .foregroundStyle(Color.textTertiary)

                ForEach(savedHosts) { savedHost in
                    HStack(spacing: Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(savedHost.title)
                                .font(.bodyMedium)
                                .foregroundStyle(Color.textPrimary)

                            HStack(spacing: 4) {
                                Text("Last used")
                                Text(savedHost.lastUsedAt, style: .relative)
                            }
                            .font(.labelSmall)
                            .foregroundStyle(Color.textTertiary)
                        }

                        Spacer(minLength: 0)

                        Button("Use") {
                            apply(savedHost)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            delete(savedHost)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 10)
                    .background(Color.surfacePrimary)
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                }
            }
        }
    }

    private var terminalSurface: some View {
        VStack(spacing: 0) {
            if session.status == .connected {
                terminalHeaderBezel
            }

            terminalViewport

            if session.status == .connected {
                terminalStatusBezel
            }
        }
        .background(Color.black)
        .clipShape(terminalSurfaceShape)
        .overlay {
            terminalSurfaceShape
                .strokeBorder(Color.borderPrimary.opacity(0.92), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, terminalOuterHorizontalPadding)
        .padding(.top, isTerminalFocusedMode ? 6 : Spacing.sm)
        .padding(.bottom, isTerminalFocusedMode ? 0 : Spacing.md)
    }

    private var terminalViewport: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color.black)

            HStack(spacing: 0) {
                terminalRail

                Spacer(minLength: 0)

                terminalRail
            }

            VStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.borderPrimary.opacity(0.36),
                                Color.borderPrimary.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 1)

                Spacer(minLength: 0)
            }

            if session.status == .connected {
                SSHTerminalGhosttySurfaceView(
                    session: session,
                    focusRequestID: terminalFocusRequestID,
                    dismissRequestID: terminalDismissRequestID,
                    refitRequestID: terminalRefitRequestID
                ) {
                    requestTerminalFocus()
                }
                .padding(.horizontal, terminalViewportHorizontalInset)
                .padding(.top, terminalViewportTopInset)
                .padding(.bottom, terminalViewportBottomInset)
            } else {
                Group {
                    if terminalRouter.isSafeMode {
                        terminalSafeModeBoard
                    } else if let initialSavedHost, didConsumeInitialSavedHost || session.status == .connecting {
                        terminalFocusedLaunchBoard(initialSavedHost)
                    } else if savedHosts.isEmpty {
                        terminalPlaceholder
                    } else {
                        configuredTerminalBoard
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, terminalViewportHorizontalInset)
                .padding(.top, terminalViewportTopInset)
                .padding(.bottom, terminalViewportBottomInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            if session.status == .connected {
                VStack(alignment: .trailing, spacing: 8) {
                    if showingCursorPad {
                        sshFloatingCursorPad
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .padding(.trailing, terminalViewportHorizontalInset + 10)
                .padding(.bottom, terminalViewportBottomInset + 12)
            }
        }
    }

    private var terminalPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.28))

                Text("No terminals configured")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.44))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var configuredTerminalBoard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Configured terminals")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.58))

            configuredTerminalDeck
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func terminalFocusedLaunchBoard(_ savedHost: SSHTerminalSavedHost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(terminalFocusedLaunchTitle(for: savedHost))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .lineLimit(1)
                }

                Text(savedHost.title)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Routes · \(routeCascadeSummary(for: savedHost))")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            routePillRow(for: savedHost)

            if case .failed = session.status {
                HStack(spacing: Spacing.sm) {
                    terminalPrimaryActionButton("Retry", systemImage: "arrow.clockwise") {
                        connect(to: savedHost)
                    }

                    if routeCandidates(for: savedHost).contains(where: { $0.route == .tailscale }) {
                        terminalSecondaryActionButton("Tailscale", systemImage: "point.3.connected.trianglepath.dotted") {
                            connect(to: savedHost, preferredRoute: .tailscale)
                        }
                    }

                    terminalSecondaryActionButton("Config", systemImage: "slider.horizontal.3") {
                        apply(savedHost)
                    }
                }
            } else {
                Text("Talkie tries local network first, then Tailscale when available.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func terminalFocusedLaunchTitle(for savedHost: SSHTerminalSavedHost) -> String {
        switch session.status {
        case .connecting:
            "Opening \(savedHost.resolvedDeviceTitle)"
        case .failed:
            "Could not open \(savedHost.resolvedDeviceTitle)"
        case .disconnected:
            "Ready for \(savedHost.resolvedDeviceTitle)"
        case .connected:
            savedHost.resolvedDeviceTitle
        }
    }

    private func routePillRow(for savedHost: SSHTerminalSavedHost) -> some View {
        HStack(spacing: 7) {
            ForEach(routeCandidates(for: savedHost), id: \.id) { candidate in
                Text(routePillTitle(for: candidate))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.055))
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var terminalSafeModeBoard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.warning)

                    Text("Terminal Safe Mode")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.96))
                }

                Text("Talkie noticed repeated trouble opening terminal. This fallback keeps things simple so you can recover, reconnect, or clean up saved Macs.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Spacing.sm) {
                ForEach(savedHosts) { savedHost in
                    safeModeHostRow(savedHost)
                }
            }

            HStack(spacing: Spacing.sm) {
                terminalSecondaryActionButton("Scan", systemImage: "qrcode.viewfinder") {
                    focusedField = nil
                    showingPrivateKeyScanner = true
                }

                terminalSecondaryActionButton("Manual") {
                    startNewHost()
                }

                terminalPrimaryActionButton("Try Full View", systemImage: "sparkles") {
                    terminalRouter.exitSafeMode()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var configuredTerminalDeck: some View {
        let entries = configuredTerminalEntries

        return VStack(spacing: Spacing.sm) {
            if entries.count == 1, let primary = entries.first {
                configuredTerminalCard(
                    for: primary.savedHost,
                    card: primary.card,
                    featured: false,
                    compact: true
                )
                    .frame(maxWidth: 368, alignment: .leading)
            } else if let primary = entries.first {
                configuredTerminalCard(
                    for: primary.savedHost,
                    card: primary.card,
                    featured: true
                )
            }

            if entries.count > 1 {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(Array(entries.dropFirst().prefix(2)), id: \.savedHost.id) { entry in
                        configuredTerminalCard(
                            for: entry.savedHost,
                            card: entry.card,
                            featured: false
                        )
                    }
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    terminalEmptyPreviewActionCard(
                        title: "Pair another Mac",
                        systemImage: "qrcode.viewfinder"
                    ) {
                        focusedField = nil
                        showingPrivateKeyScanner = true
                    }

                    terminalEmptyPreviewActionCard(
                        title: "Add SSH host",
                        systemImage: "plus"
                    ) {
                        startNewHost()
                    }
                }
            }
        }
    }

    private var configuredTerminalEntries: [(savedHost: SSHTerminalSavedHost, card: SSHTerminalPreviewCardModel)] {
        Array(savedHosts.prefix(3).enumerated()).map { index, savedHost in
            (
                savedHost,
                SSHTerminalPreviewCardModel(
                    id: savedHost.id.uuidString,
                    title: savedHost.previewTitle,
                    subtitle: savedHost.previewSubtitle,
                    roleLabel: savedHost.startupProfile.shortTitle,
                    sourceLabel: savedHost.previewSourceLabel,
                    commandPreview: previewCommand(for: savedHost.startupProfile),
                    accent: accentColor(for: savedHost.startupProfile),
                    isPrimary: index == 0
                )
            )
        }
    }


    private func terminalPreviewCard(
        _ card: SSHTerminalPreviewCardModel,
        featured: Bool,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 9 : (featured ? 12 : 10)) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.recording.opacity(0.85))
                    .frame(width: 7, height: 7)
                Circle()
                    .fill(Color.warning.opacity(0.82))
                    .frame(width: 7, height: 7)
                Circle()
                    .fill(card.accent.opacity(0.88))
                    .frame(width: 7, height: 7)

                Text(card.chromeTitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)
            }
            .padding(.bottom, compact ? 0 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: featured ? 17.5 : (compact ? 15.5 : 14.5), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)

                Text(card.subtitle)
                    .font(.system(size: featured ? 11.75 : 11.25, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.54))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(card.commandPreview)
                .font(.system(size: featured ? 11.25 : (compact ? 10.75 : 10.5), design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(compact ? 13 : (featured ? 16 : 14))
        .frame(
            maxWidth: .infinity,
            minHeight: featured ? 144 : (compact ? 118 : 120),
            maxHeight: featured ? 144 : (compact ? 118 : 120),
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: featured ? sshPreviewFeaturedCornerRadius : sshPreviewCardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(featured ? 0.055 : 0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: featured ? sshPreviewFeaturedCornerRadius : sshPreviewCardCornerRadius, style: .continuous)
                .stroke(card.isPrimary ? card.accent.opacity(0.58) : Color.white.opacity(0.07), lineWidth: card.isPrimary ? 0.9 : 0.8)
        }
    }

    private func configuredTerminalCard(
        for savedHost: SSHTerminalSavedHost,
        card: SSHTerminalPreviewCardModel,
        featured: Bool,
        compact: Bool = false
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                connect(to: savedHost)
            } label: {
                terminalPreviewCard(card, featured: featured, compact: compact)
            }
            .buttonStyle(.plain)

            terminalPreviewAccessoryButton("Config", systemImage: "slider.horizontal.3") {
                apply(savedHost)
            }
            .padding(12)
        }
    }

    private func safeModeHostRow(_ savedHost: SSHTerminalSavedHost) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(savedHost.previewTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text(savedHost.previewSubtitle)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            terminalSecondaryActionButton("Config") {
                apply(savedHost)
            }

            terminalPrimaryActionButton("Open") {
                connect(to: savedHost)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: sshInlineCardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: sshInlineCardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func terminalEmptyPreviewCard(
        title: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.56))

            Spacer(minLength: 0)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: sshPreviewCardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay {
            RoundedRectangle(cornerRadius: sshPreviewCardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    private func terminalEmptyPreviewActionCard(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            terminalEmptyPreviewCard(
                title: title,
                systemImage: systemImage
            )
        }
        .buttonStyle(.plain)
    }

    private func terminalPreviewAccessoryButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))

                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.42))
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var sshPanelCornerRadius: CGFloat { 10 }

    private var sshInlineCardCornerRadius: CGFloat { 9 }

    private var sshActionCornerRadius: CGFloat { 10 }

    private var sshPreviewCardCornerRadius: CGFloat { 14 }

    private var sshPreviewFeaturedCornerRadius: CGFloat { 16 }

    private func terminalPrimaryActionButton(
        _ title: String,
        systemImage: String? = nil,
        expands: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, expands ? 16 : 14)
            .padding(.vertical, 11)
            .background(Color.active)
            .clipShape(.rect(cornerRadius: sshActionCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: sshActionCornerRadius, style: .continuous)
                    .stroke(Color.activeGlow.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func terminalSecondaryActionButton(
        _ title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.active)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Color.surfacePrimary)
            .clipShape(.rect(cornerRadius: sshActionCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: sshActionCornerRadius, style: .continuous)
                    .stroke(Color.borderPrimary.opacity(0.9), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func terminalInfoBadge(_ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))

            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.46))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
    }

    private func previewCommand(for profile: SSHTerminalStartupProfile) -> String {
        switch profile {
        case .standardShell:
            "zsh -l"
        case .talkieShell:
            "talkie-shell"
        case .talkieSession:
            "talkie-session"
        }
    }

    private func accentColor(for profile: SSHTerminalStartupProfile) -> Color {
        switch profile {
        case .standardShell:
            Color.white.opacity(0.42)
        case .talkieShell:
            .success
        case .talkieSession:
            .active
        }
    }

    private var terminalRail: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.borderPrimary.opacity(0.35),
                        Color.borderPrimary.opacity(0.08),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: terminalRailWidth)
            .allowsHitTesting(false)
    }

    private var terminalTopCapsules: some View {
        HStack(spacing: 6) {
            terminalChromeButton(color: .recording.opacity(0.82), accessibilityLabel: "Disconnect SSH session") {
                requestTerminalDismiss()
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingConnectionDetails = true
                    showingCursorPad = false
                }
                scheduleTerminalRefit(after: .milliseconds(80))
                Task {
                    await session.disconnect()
                }
            }

            terminalChromeButton(color: .warning.opacity(0.78), accessibilityLabel: "Toggle SSH details") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingConnectionDetails.toggle()
                }
            }

            terminalChromeButton(color: .success.opacity(0.82), accessibilityLabel: "Refit SSH terminal") {
                requestTerminalRefit()
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 4)
    }

    private func terminalChromeButton(
        color: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var terminalSurfaceShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: terminalSurfaceTopCornerRadius,
                bottomLeading: terminalSurfaceBottomCornerRadius,
                bottomTrailing: terminalSurfaceBottomCornerRadius,
                topTrailing: terminalSurfaceTopCornerRadius
            ),
            style: .continuous
        )
    }

    private var terminalHeaderBezel: some View {
        ZStack {
            Text(terminalConnectionSummary)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 48)

            HStack(spacing: 0) {
                terminalTopCapsules
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: terminalHeaderBezelCornerRadius, style: .continuous)
                .fill(Color.surfaceSecondary.opacity(0.16))
        )
        .overlay {
            RoundedRectangle(cornerRadius: terminalHeaderBezelCornerRadius, style: .continuous)
                .stroke(Color.borderPrimary.opacity(0.16), lineWidth: 1)
        }
        .padding(.horizontal, terminalHeaderBezelHorizontalInset)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var terminalStatusBezel: some View {
        Color.clear
            .frame(height: 4)
            .background(Color.surfaceSecondary.opacity(0.08))
    }

    private var sshBottomSystem: some View {
        VStack(spacing: 0) {
            sshTerminalAccessoryRow

            if isTerminalKeyboardPresented {
                SSHTerminalHostedKeyboardView(
                    session: session,
                    isPresented: $isTerminalKeyboardPresented,
                    preferredHeight: $terminalKeyboardHeight,
                    controlModifierState: $controlModifierState,
                    shiftModifierState: $shiftModifierState
                )
                .padding(.horizontal, sshHostedKeyboardHorizontalInset)
                .frame(height: terminalKeyboardHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            sshBottomDock
        }
        .background(Color.surfaceSecondary.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.borderPrimary.opacity(0.4))
                .frame(height: 1)
        }
    }

    private var sshTerminalAccessoryRow: some View {
        HStack(spacing: sshAccessoryClusterSpacing) {
            sshAccessoryLeadingCluster
            sshTrayJoystickToggleButton
            sshAccessoryTrailingCluster
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, sshAccessoryRowEdgeInset)
        .padding(.top, isTerminalKeyboardPresented ? 4 : 6)
        .padding(.bottom, isTerminalKeyboardPresented ? 0 : 8)
        .background(Color.clear)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    guard value.translation.height < -18 else { return }
                    requestTerminalFocus()
                }
        )
    }

    @ViewBuilder
    private var sshAccessoryLeadingCluster: some View {
        HStack(spacing: sshTrayKeySpacing) {
            if accessoryRowMode == .modifiers {
                sshTrayButton("⎋", accessibilityLabel: "Escape", fontSize: 14) {
                    session.send("\u{1B}")
                }

                sshTrayButton("⇥", accessibilityLabel: "Tab", fontSize: 15) {
                    if shiftModifierState.isActive {
                        session.send("\u{1B}[Z")
                        consumeShiftModifierIfNeeded()
                    } else {
                        sendTerminalInput("\t")
                    }
                }

                sshControlTrayButton
            } else {
                sshSlashTrayButton

                sshTrayButton("[", accessibilityLabel: "Left bracket", fontSize: 15) {
                    sendTerminalInput("[")
                }

                sshTrayButton("]", accessibilityLabel: "Right bracket", fontSize: 15) {
                    sendTerminalInput("]")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sshAccessoryTrailingCluster: some View {
        HStack(spacing: sshTrayKeySpacing) {
            if accessoryRowMode == .modifiers {
                sshTildeTrayButton

                sshProgrammerModeButton

                sshTrayButton("⌫", accessibilityLabel: "Backspace", fontSize: 15) {
                    session.send("\u{7F}")
                }
            } else {
                sshDashTrayButton

                sshTildeTrayButton

                sshAccessoryModeExitButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sshBottomDock: some View {
        HStack {
            sshDockButton(systemImage: "slider.horizontal.3") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingConnectionDetails.toggle()
                }
                scheduleTerminalRefit(after: .milliseconds(240))
            }

            Spacer(minLength: 0)

            primaryDockActionButton

            Spacer(minLength: 0)

            sshDockButton(systemImage: isTerminalKeyboardPresented ? "keyboard.chevron.compact.down" : "keyboard") {
                if isTerminalKeyboardPresented {
                    requestTerminalDismiss()
                } else {
                    requestTerminalFocus()
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.clear)
    }

    private var primaryDockActionButton: some View {
        Button {
            if suppressPrimaryActionTap {
                suppressPrimaryActionTap = false
                return
            }
            handlePrimaryDockActionTap()
        } label: {
            Image(systemName: primaryDockActionIconName)
                .font(.system(size: primaryDockActionIconSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(primaryDockActionColor)
                .clipShape(.circle)
                .shadow(color: primaryDockActionColor.opacity(0.28), radius: 14, y: 6)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(primaryDockActionBorderOpacity), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primaryDockActionAccessibilityLabel)
        .accessibilityHint(primaryDockActionAccessibilityHint)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard dockDictationState == .idle else { return }
                    suppressPrimaryActionTap = true
                    togglePrimaryDockActionMode()
                }
        )
    }

    private var sshTrayJoystickToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) {
                showingCursorPad.toggle()
            }
        }
        label: {
            ZStack {
                RoundedRectangle(cornerRadius: sshTrayKeyCornerRadius, style: .continuous)
                    .fill(showingCursorPad ? ConfiguratorDesign.selectionBorderColor.opacity(0.9) : sshTrayKeyBackgroundColor)

                RoundedRectangle(cornerRadius: sshTrayKeyCornerRadius, style: .continuous)
                    .stroke(
                        showingCursorPad
                        ? ConfiguratorDesign.selectionBorderColor.opacity(0.98)
                        : sshTrayKeyBorderColor,
                        lineWidth: 1
                    )

                VStack(spacing: 3) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))

                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .bold))

                        Circle()
                            .fill(Color.textTertiary.opacity(0.45))
                            .frame(width: 4, height: 4)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(showingCursorPad ? Color.white : Color.textPrimary)

                if showingCursorPad {
                    VStack {
                        HStack {
                            Spacer(minLength: 0)

                            Circle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 5, height: 5)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                }
            }
            .frame(width: sshTrayJoystickWidth, height: sshTrayKeyHeight)
            .shadow(
                color: showingCursorPad
                ? ConfiguratorDesign.selectionBorderColor.opacity(0.34)
                : sshTrayKeyShadowColor,
                radius: showingCursorPad ? 6 : 1.2,
                y: showingCursorPad ? 2 : 0.5
            )
        }
        .buttonStyle(.plain)
    }

    private var sshTrayCursorPad: some View {
        VStack(spacing: 4) {
            sshTrayCursorButton("chevron.up") {
                session.send("\u{1B}[A")
            }

            HStack(spacing: 4) {
                sshTrayCursorButton("chevron.left") {
                    session.send("\u{1B}[D")
                }

                Circle()
                    .fill(Color.textTertiary.opacity(0.35))
                    .frame(width: 10, height: 10)

                sshTrayCursorButton("chevron.right") {
                    session.send("\u{1B}[C")
                }
            }

            sshTrayCursorButton("chevron.down") {
                session.send("\u{1B}[B")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(sshTrayKeyBackgroundColor)
        .clipShape(.rect(cornerRadius: sshTrayKeyCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: sshTrayKeyCornerRadius, style: .continuous)
                .stroke(sshTrayKeyBorderColor, lineWidth: 1)
        }
        .shadow(color: sshTrayKeyShadowColor, radius: 1.2, y: 0.5)
    }

    private var sshFloatingCursorPad: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.78))

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            Circle()
                .stroke(Color.white.opacity(0.04), lineWidth: 16)
                .padding(26)

            ForEach(SSHTerminalCursorPadDirection.allCases, id: \.self) { direction in
                sshFloatingCursorButton(direction)
                    .offset(direction.buttonOffset(distance: sshFloatingCursorButtonDistance))
            }

            Circle()
                .fill(Color.textTertiary.opacity(0.12))
                .frame(width: 26, height: 26)

            Circle()
                .fill(Color.surfacePrimary.opacity(0.96))
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 12, height: 12)
                }
                .frame(width: sshFloatingCursorKnobSize, height: sshFloatingCursorKnobSize)
                .offset(cursorPadKnobOffset)
                .shadow(color: Color.black.opacity(0.22), radius: 8, y: 3)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateCursorPadKnobDrag(with: value.translation)
                        }
                        .onEnded { _ in
                            finishCursorPadKnobDrag()
                        }
                )
        }
        .frame(width: sshFloatingCursorPadDiameter, height: sshFloatingCursorPadDiameter)
        .shadow(color: Color.black.opacity(0.28), radius: 14, y: 8)
        .zIndex(8)
    }

    private func sshTrayButton(
        _ title: String,
        width: CGFloat? = nil,
        isActive: Bool = false,
        isLocked: Bool = false,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        fontSize: CGFloat = 12.5,
        action: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? Color.white : ConfiguratorDesign.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: width == nil ? .infinity : nil)
                    .frame(width: width, height: sshTrayKeyHeight)
                    .background(isActive ? ConfiguratorDesign.selectionBorderColor.opacity(0.88) : sshTrayKeyBackgroundColor)
                    .clipShape(.rect(cornerRadius: sshTrayKeyCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: sshTrayKeyCornerRadius, style: .continuous)
                            .stroke(isActive ? ConfiguratorDesign.selectionBorderColor.opacity(0.95) : sshTrayKeyBorderColor, lineWidth: 1)
                    }
                    .shadow(color: sshTrayKeyShadowColor, radius: 1.2, y: 0.5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel ?? title)
            .accessibilityHint(accessibilityHint ?? "")

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.textPrimary.opacity(0.9))
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                    .allowsHitTesting(false)
            }
        }
    }

    private var sshShiftTrayButton: some View {
        sshTrayButton(
            "⇧",
            isActive: shiftModifierState.isActive,
            isLocked: shiftModifierState.isLocked,
            accessibilityLabel: "Shift",
            accessibilityHint: "Double tap to lock Shift. Shift-Tab sends a reverse tab in the terminal.",
            fontSize: 16
        ) {
            withAnimation(.easeInOut(duration: 0.12)) {
                shiftModifierState = shiftModifierState == .armed ? .inactive : .armed
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        shiftModifierState = shiftModifierState == .locked ? .inactive : .locked
                    }
                }
        )
    }

    private var sshControlTrayButton: some View {
        sshTrayButton(
            "⌃",
            isActive: controlModifierState.isActive,
            isLocked: controlModifierState.isLocked,
            accessibilityLabel: "Control",
            accessibilityHint: "Double tap to lock Control for repeated shortcuts.",
            fontSize: 16
        ) {
            withAnimation(.easeInOut(duration: 0.12)) {
                controlModifierState = controlModifierState == .armed ? .inactive : .armed
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        controlModifierState = controlModifierState == .locked ? .inactive : .locked
                    }
                }
        )
    }

    private var sshProgrammerModeButton: some View {
        sshTrayButton(
            "[]",
            accessibilityLabel: "Programmer symbols",
            accessibilityHint: "Shows programmer symbols in the accessory row.",
            fontSize: 13
        ) {
            withAnimation(.easeInOut(duration: 0.16)) {
                accessoryRowMode = .symbols
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.16)) {
                        accessoryRowMode = .symbols
                    }
                }
        )
    }

    private var sshTildeTrayButton: some View {
        sshTrayButton(
            "~",
            accessibilityLabel: "Tilde",
            accessibilityHint: "Long press for backtick.",
            fontSize: 15
        ) {
            if suppressTildeTap {
                suppressTildeTap = false
                return
            }
            sendTerminalInput("~")
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    suppressTildeTap = true
                    sendTerminalInput("`")
                }
        )
    }

    private var sshSlashTrayButton: some View {
        sshTrayButton(
            "/",
            accessibilityLabel: "Slash",
            accessibilityHint: "Long press for backslash.",
            fontSize: 15
        ) {
            if suppressSlashTap {
                suppressSlashTap = false
                return
            }
            sendTerminalInput("/")
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    suppressSlashTap = true
                    sendTerminalInput("\\")
                }
        )
    }

    private var sshDashTrayButton: some View {
        sshTrayButton(
            "-",
            accessibilityLabel: "Hyphen",
            accessibilityHint: "Long press for underscore.",
            fontSize: 15
        ) {
            if suppressDashTap {
                suppressDashTap = false
                return
            }
            sendTerminalInput("-")
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    suppressDashTap = true
                    sendTerminalInput("_")
                }
        )
    }

    private var sshAccessoryModeExitButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                accessoryRowMode = .modifiers
            }
        } label: {
            Text("Back")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(ConfiguratorDesign.selectionBorderColor.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: sshTrayKeyHeight)
                .background(ConfiguratorDesign.selectionBorderColor.opacity(0.16))
                .clipShape(.rect(cornerRadius: sshTrayKeyCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: sshTrayKeyCornerRadius, style: .continuous)
                        .stroke(ConfiguratorDesign.selectionBorderColor.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: sshTrayKeyShadowColor, radius: 1.2, y: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return to modifier row")
        .accessibilityHint("Returns to the main accessory row.")
    }

    private var sshTrayKeyHeight: CGFloat { 36 }

    private var sshTrayJoystickWidth: CGFloat { 46 }

    private var sshTrayKeySpacing: CGFloat { 4 }

    private var sshAccessoryClusterSpacing: CGFloat { 6 }

    private var sshHostedKeyboardHorizontalInset: CGFloat { 10 }

    private var sshMinimalKeyboardSideInset: CGFloat { 5 }

    private var sshAccessoryRowEdgeInset: CGFloat {
        sshHostedKeyboardHorizontalInset + sshMinimalKeyboardSideInset
    }

    private var sshTrayKeyCornerRadius: CGFloat { 4 }

    private var isMinimalTerminalKeyboardLayout: Bool {
        isTerminalKeyboardPresented && terminalKeyboardHeight < 100
    }

    private var sshTrayKeyBackgroundColor: Color {
        ConfiguratorDesign.surfaceDark
    }

    private var sshTrayKeyBorderColor: Color {
        Color.white.opacity(0.06)
    }

    private var sshTrayKeyShadowColor: Color {
        Color.black.opacity(0.22)
    }

    private func sshTrayIconButton(_ systemImage: String, width: CGFloat = 48, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConfiguratorDesign.textPrimary)
                .frame(width: width, height: sshTrayKeyHeight)
                .background(sshTrayKeyBackgroundColor)
                .clipShape(.rect(cornerRadius: sshTrayKeyCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: sshTrayKeyCornerRadius, style: .continuous)
                        .stroke(sshTrayKeyBorderColor, lineWidth: 1)
                }
                .shadow(color: sshTrayKeyShadowColor, radius: 1.2, y: 0.5)
        }
        .buttonStyle(.plain)
    }

    private func sshTrayCursorButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ConfiguratorDesign.textPrimary)
                .frame(width: 24, height: 18)
                .background(ConfiguratorDesign.surfaceLight)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func sshFloatingCursorButton(_ direction: SSHTerminalCursorPadDirection) -> some View {
        Button {
            sendCursorMovement(direction)
        } label: {
            Image(systemName: direction.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(cursorPadRepeatDirection == direction ? Color.white : ConfiguratorDesign.textPrimary)
                .frame(width: sshFloatingCursorButtonSize, height: sshFloatingCursorButtonSize)
                .background(
                    cursorPadRepeatDirection == direction
                    ? ConfiguratorDesign.selectionBorderColor.opacity(0.9)
                    : ConfiguratorDesign.surfaceLight.opacity(0.95)
                )
                .clipShape(.circle)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func sshDockButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 46, height: 46)
                .background(Color.surfacePrimary.opacity(0.82))
                .clipShape(.circle)
                .overlay {
                    Circle()
                        .stroke(Color.borderPrimary.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (
            !password.isEmpty ||
            !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ) &&
        validPort != nil
    }

    private var canSaveHost: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        validPort != nil
    }

    private var isTerminalFocusedMode: Bool {
        session.status == .connected && !showingConnectionDetails
    }

    private var terminalConnectionSummary: String {
        let trimmedEndpoint = session.endpointLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            return "SSH"
        }

        if let portSeparator = trimmedEndpoint.lastIndex(of: ":"),
           trimmedEndpoint[trimmedEndpoint.index(after: portSeparator)...].allSatisfy(\.isNumber) {
            return String(trimmedEndpoint[..<portSeparator])
        }

        return trimmedEndpoint
    }

    private var primaryActionMode: DockPrimaryActionMode {
        get { DockPrimaryActionMode(rawValue: primaryActionModeStorage) ?? .memo }
        nonmutating set { primaryActionModeStorage = newValue.rawValue }
    }

    private var dockDictationErrorBinding: Binding<Bool> {
        Binding(
            get: { dockDictationError != nil },
            set: { isPresented in
                if !isPresented {
                    dockDictationError = nil
                }
            }
        )
    }

    private var primaryDockActionColor: Color {
        switch primaryActionMode {
        case .memo:
            return .recording
        case .dictation:
            switch dockDictationState {
            case .idle:
                return .active
            case .recording:
                return .activeGlow
            case .transcribing:
                return .warning
            }
        }
    }

    private var primaryDockActionIconName: String {
        switch primaryActionMode {
        case .memo:
            return "mic.fill"
        case .dictation:
            switch dockDictationState {
            case .idle:
                return "text.cursor"
            case .recording:
                return "stop.fill"
            case .transcribing:
                return "waveform"
            }
        }
    }

    private var primaryDockActionIconSize: CGFloat {
        primaryActionMode == .memo ? 24 : 22
    }

    private var primaryDockActionBorderOpacity: Double {
        primaryActionMode == .dictation && dockDictationState == .recording ? 0.55 : 0.18
    }

    private var primaryDockActionAccessibilityLabel: String {
        switch primaryActionMode {
        case .memo:
            return "Record memo"
        case .dictation:
            switch dockDictationState {
            case .idle:
                return "Start dictation"
            case .recording:
                return "Stop dictation"
            case .transcribing:
                return "Transcribing dictation"
            }
        }
    }

    private var primaryDockActionAccessibilityHint: String {
        let alternateMode = primaryActionMode == .memo ? "dictation" : "memo recording"
        return "Long press to switch to \(alternateMode) mode."
    }

    private var currentSavedHost: SSHTerminalSavedHost? {
        guard let portValue = validPort else { return nil }

        let normalizedHost = normalized(host)
        let normalizedUsername = normalized(username)
        return savedHosts.first {
            $0.normalizedHostCandidates.contains(normalizedHost) &&
            normalized($0.username) == normalizedUsername &&
            $0.port == portValue
        }
    }

    private var validPort: Int? {
        guard let portValue = Int(port), (1...65535).contains(portValue) else {
            return nil
        }

        return portValue
    }

    private var startupProfileBinding: Binding<SSHTerminalStartupProfile> {
        Binding(
            get: { selectedStartupProfile },
            set: { profile in
                startupProfileStorage = profile.rawValue
                startupCommand = profile.startupCommand
            }
        )
    }

    private var selectedStartupProfile: SSHTerminalStartupProfile {
        SSHTerminalStartupProfile(rawValue: startupProfileStorage) ?? .standardShell
    }

    private var resolvedStartupCommand: String? {
        let command: String
        if let currentSavedHost {
            command = currentSavedHost.resolvedStartupCommand(
                for: selectedStartupProfile,
                startupCommandOverride: startupCommand
            )
        } else {
            command = startupCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? selectedStartupProfile.startupCommand
                : startupCommand
        }
        let trimmedCommand = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCommand.isEmpty ? nil : trimmedCommand
    }

    private var statusTitle: String {
        switch session.status {
        case .disconnected:
            let hasHost = !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasUsername = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if !hasHost && !hasUsername {
                return "New Connection"
            }

            if canSaveHost {
                return "Ready"
            }

            return "Connection Details"
        case .connecting:
            return "Connecting…"
        case .connected:
            return "Connected"
        case .failed:
            return "Connection Failed"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .disconnected:
            canSaveHost ? .active : .textTertiary
        case .connecting:
            .warning
        case .connected:
            .success
        case .failed:
            .recording
        }
    }

    private func diagnosticColor(for level: SSHTerminalSession.DiagnosticEvent.Level) -> Color {
        switch level {
        case .info:
            return .textSecondary
        case .warning:
            return .warning
        case .error:
            return .recording
        }
    }

    private var troubleshootingFallbackProfile: SSHTerminalStartupProfile? {
        switch attemptedStartupProfile {
        case .talkieSession:
            .talkieShell
        case .talkieShell:
            .standardShell
        case .standardShell, nil:
            nil
        }
    }

    private var attemptedStartupProfile: SSHTerminalStartupProfile? {
        switch session.launchModeLabel {
        case SSHTerminalStartupProfile.standardShell.title:
            .standardShell
        case SSHTerminalStartupProfile.talkieShell.title:
            .talkieShell
        case SSHTerminalStartupProfile.talkieSession.title:
            .talkieSession
        default:
            nil
        }
    }

    private func troubleshootingSummary(message: String) -> String {
        let lowercased = message.localizedLowercase

        if lowercased.contains("host key") {
            return "This iPhone already trusts a different SSH identity for this address. That usually means the Mac, SSH host key, or target machine changed."
        }

        if lowercased.contains("authentication")
            || lowercased.contains("password")
            || lowercased.contains("private-key")
            || lowercased.contains("supported authentication") {
            return "The server rejected the credentials or the auth method. Double-check the user, key, password, and what this host allows."
        }

        if lowercased.contains("closed during startup")
            || lowercased.contains("exited during startup") {
            return "SSH reached the Mac, but the Talkie helper closed before an interactive shell stayed alive. This is usually the helper/runtime layer, not the network path."
        }

        if lowercased.contains("timed out")
            || lowercased.contains("unreachable")
            || lowercased.contains("refused")
            || lowercased.contains("closed before login") {
            return "The SSH path itself did not stay healthy enough to finish login. Host reachability, port, SSH service state, or network path are the likely problems."
        }

        return "Talkie captured the recent connection steps below so we can tell whether the failure happened during SSH login or after the helper launched."
    }

    private func troubleshootingSteps(message: String) -> [String] {
        let lowercased = message.localizedLowercase

        if lowercased.contains("host key") {
            return [
                "If this is the same Mac, open Config and remove the saved connection so Talkie can trust the new host key on the next connect.",
                "If this Mac recently changed SSH keys or was reinstalled, pair or save it again instead of retrying against the old identity."
            ]
        }

        if lowercased.contains("authentication")
            || lowercased.contains("password")
            || lowercased.contains("private-key")
            || lowercased.contains("supported authentication") {
            return [
                "Open Config and confirm the username plus whichever credential this host expects: password or private key.",
                "If Native works but T Shell or Tmux does not, the SSH login is fine and the problem is in the Talkie helper step after login."
            ]
        }

        if lowercased.contains("closed during startup")
            || lowercased.contains("exited during startup") {
            var steps = [
                "Retry once to confirm whether the helper crash was transient. The technical log below will show whether it died before or after the startup command ran."
            ]

            if let fallbackProfile = troubleshootingFallbackProfile {
                steps.append("If this keeps happening, try \(fallbackProfile.title). That tells us whether SSH itself is healthy while the Talkie-managed shell path is not.")
            }

            steps.append("If Native works and this mode does not, the Mac-side Talkie helper/runtime needs attention rather than the network or credentials.")
            return steps
        }

        if lowercased.contains("timed out")
            || lowercased.contains("unreachable")
            || lowercased.contains("refused")
            || lowercased.contains("closed before login") {
            return [
                "Check the host, port, and whether SSH is actually listening on the target Mac or server.",
                "If this is a paired Mac, confirm Tailscale is up and that the saved host still points to the right machine."
            ]
        }

        return [
            "Retry with the same mode first so we can compare the technical log.",
            "If the helper modes keep failing, switch to Native once to separate SSH problems from Talkie helper problems."
        ]
    }

    private func troubleshootingMetaRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(title) ·")
                .foregroundStyle(Color.textTertiary)

            Text(value)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
    }

    private func connect() {
        guard let portValue = validPort else {
            session.status = .failed(SSHClientError.invalidPort.localizedDescription)
            return
        }

        let requestedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedPassword = password
        let requestedPrivateKey = privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        let startupProfile = selectedStartupProfile
        let startupCommandForConnection = pendingOneShotStartupCommand ?? resolvedStartupCommand
        let startupCommandOverride = currentStartupCommandOverride
        let savedHost = currentSavedHost
        let routePreference = pendingRoutePreference
        pendingRoutePreference = nil
        focusedField = nil

        Task { @MainActor in
            let routeCandidates = await resolvedConnectionRoutes(
                requestedHost: requestedHost,
                savedHost: savedHost,
                preferredRoute: routePreference
            )
            await startConnectionCascade(
                routes: routeCandidates,
                portValue: portValue,
                username: requestedUsername,
                password: requestedPassword,
                privateKeyPEM: requestedPrivateKey,
                startupProfile: startupProfile,
                startupCommand: startupCommandForConnection,
                startupCommandOverride: startupCommandOverride,
                savedHost: savedHost
            )
        }
    }

    private func startConnectionCascade(
        routes: [SSHRouteCandidate],
        portValue: Int,
        username: String,
        password: String,
        privateKeyPEM: String,
        startupProfile: SSHTerminalStartupProfile,
        startupCommand: String?,
        startupCommandOverride: String?,
        savedHost: SSHTerminalSavedHost?
    ) async {
        guard !routes.isEmpty else {
            session.status = .failed("Enter a host and username.")
            return
        }

        for routeIndex in routes.indices {
            let route = routes[routeIndex]
            let isLastRoute = routeIndex == routes.index(before: routes.endIndex)
            let shouldStop = await attemptConnection(
                route: route,
                portValue: portValue,
                username: username,
                password: password,
                privateKeyPEM: privateKeyPEM,
                startupProfile: startupProfile,
                startupCommand: startupCommand,
                startupCommandOverride: startupCommandOverride,
                savedHost: savedHost
            )

            guard !shouldStop, !isLastRoute else {
                return
            }

            AppLogger.ui.info(
                "SSH route failed; trying next route",
                detail: "failed=\(route.host) next=\(routes[routeIndex + 1].host)"
            )
        }
    }

    private func attemptConnection(
        route: SSHRouteCandidate,
        portValue: Int,
        username: String,
        password: String,
        privateKeyPEM: String,
        startupProfile: SSHTerminalStartupProfile,
        startupCommand: String?,
        startupCommandOverride: String?,
        savedHost: SSHTerminalSavedHost?
    ) async -> Bool {
        let connectionHost = route.host
        AppLogger.ui.info(
            "SSH connect requested",
            detail: "host=\(connectionHost) route=\(route.route.displayName) username=\(username) port=\(portValue) profile=\(startupProfile.rawValue)"
        )

        if let savedHost,
           normalized(connectionHost) != savedHost.normalizedHost,
           !savedHost.normalizedHostCandidates.contains(normalized(connectionHost)) {
            savedHosts = connectionManager.addRouteAlias(connectionHost, to: savedHost)
            refreshSavedHostsFromManager()
        }

        let configuration = SSHTerminalConfiguration(
            host: connectionHost,
            port: portValue,
            username: username,
            password: password,
            privateKeyPEM: privateKeyPEM.isEmpty ? nil : privateKeyPEM,
            startupProfile: startupProfile,
            startupCommand: startupCommand,
            connectTimeoutSeconds: route.connectTimeoutSeconds
        )

        persistPrivateKey()
        terminalRouter.showConnecting(savedHostID: savedHost?.id ?? currentSavedHost?.id)
        connectionManager.markConnecting(
            host: connectionHost,
            port: portValue,
            username: username,
            startupProfile: startupProfile,
            startupCommandOverride: startupCommandOverride
        )

        let result = await session.connect(configuration: configuration)
        if case .failed(let message) = result {
            return !shouldTryNextRoute(after: message)
        }

        return true
    }

    private func resolvedConnectionRoutes(
        requestedHost: String,
        savedHost: SSHTerminalSavedHost?,
        preferredRoute: TalkieNetworkRoute? = nil
    ) async -> [SSHRouteCandidate] {
        let trimmedRequestedHost = requestedHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let savedHost else {
            return routeCandidates(from: [trimmedRequestedHost])
        }

        nearbyMacBrowser.start()
        defer {
            nearbyMacBrowser.stop()
        }
        if matchingNearbyMac(for: savedHost) == nil {
            try? await Task.sleep(for: .milliseconds(650))
        }

        var candidates: [SSHRouteCandidate] = []
        var seenHosts: Set<String> = []
        func appendCandidate(_ host: String?, route explicitRoute: TalkieNetworkRoute? = nil) {
            let trimmedHost = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalizedHost = normalized(trimmedHost)
            guard !trimmedHost.isEmpty, !seenHosts.contains(normalizedHost) else {
                return
            }

            seenHosts.insert(normalizedHost)
            candidates.append(
                SSHRouteCandidate(
                    host: trimmedHost,
                    route: explicitRoute ?? TalkieNetworkRouteClassifier.route(for: trimmedHost)
                )
            )
        }

        let nearbyMac = matchingNearbyMac(for: savedHost)
        if let nearbyMac {
            AppLogger.ui.info(
                "SSH route resolved over local network",
                detail: "device=\(savedHost.resolvedDeviceTitle) host=\(nearbyMac.connectionHost)"
            )
        }

        let storedHosts = [savedHost.host] + (savedHost.alternateHosts ?? [])
        for route in connectionRouteOrder(preferredRoute: preferredRoute) {
            if route == .localNetwork {
                appendCandidate(nearbyMac?.connectionHost, route: .localNetwork)
            }

            for host in storedHosts where TalkieNetworkRouteClassifier.route(for: host) == route {
                appendCandidate(host, route: route)
            }
        }
        appendCandidate(trimmedRequestedHost)

        AppLogger.ui.info(
            "SSH route cascade prepared",
            detail: "device=\(savedHost.resolvedDeviceTitle) routes=\(candidates.map { "\($0.route.displayName):\($0.host)" }.joined(separator: " -> "))"
        )
        return candidates
    }

    private func routeCandidates(from hosts: [String]) -> [SSHRouteCandidate] {
        var seenHosts: Set<String> = []
        var candidates: [SSHRouteCandidate] = []

        for host in hosts {
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedHost = normalized(trimmedHost)
            guard !trimmedHost.isEmpty, !seenHosts.contains(normalizedHost) else {
                continue
            }

            seenHosts.insert(normalizedHost)
            candidates.append(
                SSHRouteCandidate(
                    host: trimmedHost,
                    route: TalkieNetworkRouteClassifier.route(for: trimmedHost)
                )
            )
        }

        return candidates
    }

    private func routeCandidates(for savedHost: SSHTerminalSavedHost) -> [SSHRouteCandidate] {
        routeCandidates(from: [savedHost.host] + (savedHost.alternateHosts ?? []))
    }

    private func routeCascadeSummary(for savedHost: SSHTerminalSavedHost) -> String {
        let routes = orderedRoutes(for: routeCandidates(for: savedHost))
        guard !routes.isEmpty else {
            return "Direct"
        }

        return routes
            .map(\.displayName)
            .joined(separator: " -> ")
    }

    private func routePillTitle(for candidate: SSHRouteCandidate) -> String {
        let routeLabel: String
        switch candidate.route {
        case .localNetwork:
            routeLabel = "local"
        case .tailscale:
            routeLabel = "tailscale"
        case .direct:
            routeLabel = "direct"
        }

        return "\(routeLabel): \(candidate.host)"
    }

    private func orderedRoutes(for candidates: [SSHRouteCandidate]) -> [TalkieNetworkRoute] {
        let classicOrder: [TalkieNetworkRoute] = [.localNetwork, .tailscale, .direct]
        return classicOrder.filter { route in
            candidates.contains(where: { $0.route == route })
        }
    }

    private func connectionRouteOrder(preferredRoute: TalkieNetworkRoute?) -> [TalkieNetworkRoute] {
        let classicOrder: [TalkieNetworkRoute] = [.localNetwork, .tailscale, .direct]
        guard let preferredRoute else {
            return classicOrder
        }

        return [preferredRoute] + classicOrder.filter { $0 != preferredRoute }
    }

    private func shouldTryNextRoute(after message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("timed out") ||
            lowercasedMessage.contains("unreachable") ||
            lowercasedMessage.contains("refused") ||
            lowercasedMessage.contains("network") ||
            lowercasedMessage.contains("host") ||
            lowercasedMessage.contains("dns")
    }

    private func matchingNearbyMac(for savedHost: SSHTerminalSavedHost) -> NearbyMacBrowser.NearbyMac? {
        let hostCandidates = Set(savedHost.normalizedHostCandidates)
        let deviceCandidates = Set([
            savedHost.resolvedDeviceTitle,
            savedHost.trimmedDeviceLabel,
            savedHost.host,
        ].compactMap { value in
            normalizedNetworkIdentity(value)
        })

        return nearbyMacBrowser.macs.first { mac in
            let macHosts = [
                mac.connectionHost,
                mac.hostName,
            ].map { normalized($0) }
            if macHosts.contains(where: hostCandidates.contains) {
                return true
            }

            let macIdentities = [
                mac.name,
                mac.connectionHost,
                mac.hostName,
            ].compactMap { normalizedNetworkIdentity($0) }
            return macIdentities.contains(where: deviceCandidates.contains)
        }
    }

    private func normalizedNetworkIdentity(_ value: String?) -> String? {
        TalkieNetworkRouteClassifier.networkIdentity(from: value)
    }

    private func connectUsing(_ profile: SSHTerminalStartupProfile) {
        startupProfileStorage = profile.rawValue
        startupCommand = profile.startupCommand
        pendingOneShotStartupCommand = nil
        connect()
    }

    private func copyTroubleshootingReport(message: String) {
        let diagnostics = session.recentDiagnostics.suffix(8).map { event in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return "[\(formatter.string(from: event.timestamp))] \(event.level.rawValue.uppercased()) \(event.message)"
        }

        let lines = [
            "Talkie Terminal Troubleshooting",
            "Status: \(message)",
            "Mode: \(session.launchModeLabel ?? selectedStartupProfile.title)",
            "Start: \(session.launchCommandSummary ?? "login shell")",
            "Host: \(session.endpointLabel.isEmpty ? "\(username)@\(host):\(port)" : session.endpointLabel)",
            diagnostics.isEmpty ? nil : "Technical log:",
            diagnostics.isEmpty ? nil : diagnostics.joined(separator: "\n")
        ]
            .compactMap { $0 }

        UIPasteboard.general.string = lines.joined(separator: "\n")
        copiedTroubleshootingReport = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedTroubleshootingReport = false
        }
    }

    private func configureDockDictationController() {
        let stateBinding = $dockDictationState
        let errorBinding = $dockDictationError
        let activeSession = session

        dockDictationController.onStateChange = { state in
            stateBinding.wrappedValue = state
        }

        dockDictationController.onTranscript = { transcript in
            let normalized = transcript
                .replacingOccurrences(of: "\r\n", with: "\r")
                .replacingOccurrences(of: "\n", with: "\r")
            activeSession.send(normalized)
        }

        dockDictationController.onError = { message in
            errorBinding.wrappedValue = message
        }
    }

    private func migrateStartupCommandIfNeeded() {
        if startupCommandResetVersion < Self.startupCommandResetVersion {
            startupProfileStorage = SSHTerminalStartupProfile.inferredProfile(from: startupCommand).rawValue
            startupCommand = selectedStartupProfile.startupCommand
            startupCommandResetVersion = Self.startupCommandResetVersion
            connectionManager.reload()
            refreshSavedHostsFromManager()
            return
        }

        if SSHTerminalStartupProfile(rawValue: startupProfileStorage) == nil {
            startupProfileStorage = SSHTerminalStartupProfile.standardShell.rawValue
        }

        let trimmedCommand = startupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCommand.isEmpty
            || shouldResetStartupCommand(trimmedCommand)
            || SSHTerminalStartupProfile.normalizedStartupCommandOverride(
                trimmedCommand,
                for: selectedStartupProfile
            ) == nil
        {
            startupCommand = selectedStartupProfile.startupCommand
        }

        connectionManager.reload()
        refreshSavedHostsFromManager()
    }

    private func shouldResetStartupCommand(_ command: String) -> Bool {
        if command == Self.legacyStartupCommand
            || command == Self.pathAwareStartupCommand
            || command == Self.statusAwareStartupCommand
            || command == Self.previousDefaultStartupCommand {
            return true
        }

        let normalizedCommand = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedCommand == "claude"
            || normalizedCommand.hasPrefix("claude ")
            || normalizedCommand == "opencode"
            || normalizedCommand.hasPrefix("opencode ")
    }

    private func handlePrimaryDockActionTap() {
        switch primaryActionMode {
        case .memo:
            showingRecordingView = true
        case .dictation:
            guard session.status == .connected else {
                dockDictationError = "Connect to an SSH session before dictating into the terminal."
                return
            }

            switch dockDictationState {
            case .idle:
                Task { @MainActor in
                    await dockDictationController.start()
                }
            case .recording:
                dockDictationController.stop(insertTranscript: true)
            case .transcribing:
                break
            }
        }
    }

    private func togglePrimaryDockActionMode() {
        if dockDictationState != .idle {
            dockDictationController.cancel()
        }

        primaryActionMode = primaryActionMode == .memo ? .dictation : .memo
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        field: Field,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .submitLabel(field == .password ? .go : .next)
            .onSubmit {
                advanceFocus(after: field)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .background(Color.surfacePrimary)
            .clipShape(.rect(cornerRadius: CornerRadius.sm))
            .accessibilityIdentifier(accessibilityIdentifier(for: field))
    }

    private func advanceFocus(after field: Field) {
        switch field {
        case .host:
            focusedField = .port
        case .port:
            focusedField = .username
        case .username:
            focusedField = .password
        case .password:
            connect()
        }
    }

    private func accessibilityIdentifier(for field: Field) -> String {
        switch field {
        case .host:
            "ssh.host"
        case .port:
            "ssh.port"
        case .username:
            "ssh.username"
        case .password:
            "ssh.password"
        }
    }

    private func handleSessionStatusChange(
        from oldValue: SSHTerminalSession.Status,
        to newValue: SSHTerminalSession.Status
    ) {
        AppLogger.ui.info(
            "SSH session status changed",
            detail: "from=\(String(describing: oldValue)) to=\(String(describing: newValue))"
        )

        switch newValue {
        case .connected:
            terminalRouter.showSession(savedHostID: currentSavedHost?.id)
            pendingOneShotStartupCommand = nil
            copiedTroubleshootingReport = false
            saveCurrentHost()
            showingHostEditor = false
            withAnimation(.easeInOut(duration: 0.2)) {
                showingConnectionDetails = false
            }
            scheduleTerminalRefit(after: .milliseconds(260))
        case .disconnected, .connecting, .failed:
            if case .connected = oldValue {
                saveCurrentHost()
            }
            if case .failed = newValue {
                if case .failed(let message) = newValue {
                    terminalRouter.showError(message)
                }
                showingTroubleshootingLog = true
                copiedTroubleshootingReport = false
                pendingOneShotStartupCommand = nil
                connectionManager.clearActiveConnection()
            } else if case .disconnected = newValue {
                terminalRouter.beginPresentation()
                copiedTroubleshootingReport = false
                pendingOneShotStartupCommand = nil
                connectionManager.clearActiveConnection()
            } else if case .connecting = newValue {
                terminalRouter.showConnecting(savedHostID: currentSavedHost?.id)
                copiedTroubleshootingReport = false
            }
            isTerminalKeyboardPresented = false
            withAnimation(.easeInOut(duration: 0.2)) {
                showingConnectionDetails = true
            }
            scheduleTerminalRefit(after: .milliseconds(180))
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .background else { return }
        guard session.status != .disconnected else { return }

        AppLogger.ui.info("SSH terminal moved to background; ending live session deterministically")

        if case .connected = session.status {
            saveCurrentHost()
        }

        pendingOneShotStartupCommand = nil
        requestTerminalDismiss()
        showingCursorPad = false
        isTerminalKeyboardPresented = false

        Task {
            await session.disconnect()
        }
    }

    private func saveCurrentHost() {
        guard let portValue = validPort else {
            session.status = .failed(SSHClientError.invalidPort.localizedDescription)
            return
        }

        savedHosts = connectionManager.saveHost(
            host: host,
            port: portValue,
            username: username,
            startupProfile: selectedStartupProfile,
            startupCommandOverride: currentStartupCommandOverride
        )
    }

    private func apply(_ savedHost: SSHTerminalSavedHost) {
        AppLogger.ui.info(
            "Applying saved SSH host",
            detail: "host=\(savedHost.host) username=\(savedHost.username) profile=\(savedHost.startupProfile.rawValue)"
        )
        host = savedHost.host
        port = String(savedHost.port)
        username = savedHost.username
        let connectionStartupProfile = savedHost.connectionStartupProfile
        startupProfileStorage = connectionStartupProfile.rawValue
        startupCommand = savedHost.resolvedStartupCommand(
            for: connectionStartupProfile,
            startupCommandOverride: savedHost.startupCommandOverride
        )
        pendingOneShotStartupCommand = nil
        password = ""
        showingHostEditor = true
        terminalRouter.showEditor(savedHostID: savedHost.id)
        focusedField = .password

        Task {
            await session.disconnect()
        }
    }

    private func connect(
        to savedHost: SSHTerminalSavedHost,
        preferredRoute: TalkieNetworkRoute? = nil,
        oneShotStartupCommand: String? = nil
    ) {
        AppLogger.ui.info(
            "Connecting to saved SSH host",
            detail: "host=\(savedHost.host) username=\(savedHost.username) profile=\(savedHost.startupProfile.rawValue) preferredRoute=\(preferredRoute?.displayName ?? "classic")"
        )
        refreshPrivateKeyFromStoreIfNeeded()
        host = savedHost.host
        port = String(savedHost.port)
        username = savedHost.username
        let connectionStartupProfile = savedHost.connectionStartupProfile
        startupProfileStorage = connectionStartupProfile.rawValue
        startupCommand = savedHost.resolvedStartupCommand(
            for: connectionStartupProfile,
            startupCommandOverride: savedHost.startupCommandOverride
        )
        let trimmedOneShotCommand = oneShotStartupCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pendingOneShotStartupCommand = trimmedOneShotCommand.isEmpty ? nil : trimmedOneShotCommand
        pendingRoutePreference = preferredRoute

        guard hasReusableCredential else {
            showingHostEditor = true
            terminalRouter.showEditor(savedHostID: savedHost.id)
            focusedField = .password
            return
        }

        showingHostEditor = false
        connect()
    }

    private func startNewHost() {
        AppLogger.ui.info("Starting brand new SSH host flow")
        host = ""
        port = "22"
        username = ""
        password = ""
        privateKeyPEM = ""
        privateKeyImportMessage = nil
        showingPrivateKey = false
        startupProfileStorage = SSHTerminalStartupProfile.standardShell.rawValue
        startupCommand = SSHTerminalStartupProfile.standardShell.startupCommand
        pendingOneShotStartupCommand = nil
        showingHostEditor = true
        terminalRouter.showEditor(savedHostID: nil)
        focusedField = .host
    }

    private func delete(_ savedHost: SSHTerminalSavedHost) {
        let isCurrentHost = currentSavedHost?.id == savedHost.id
        let shouldDisconnect = isCurrentHost && session.status == .connected

        savedHosts = connectionManager.delete(savedHost)

        if isCurrentHost {
            host = ""
            port = "22"
            username = ""
            password = ""
            startupProfileStorage = SSHTerminalStartupProfile.standardShell.rawValue
            startupCommand = SSHTerminalStartupProfile.standardShell.startupCommand
            pendingOneShotStartupCommand = nil
            showingHostEditor = false
        }

        if shouldDisconnect {
            requestTerminalDismiss()
            Task {
                await session.disconnect()
            }
        }
    }

    private func persistPrivateKey() {
        privateKeyStore.save(privateKeyPEM)
    }

    private func refreshPrivateKeyFromStoreIfNeeded() {
        guard privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let storedPrivateKey = privateKeyStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !storedPrivateKey.isEmpty else {
            return
        }

        privateKeyPEM = storedPrivateKey
    }

    private var currentStartupCommandOverride: String? {
        let command = startupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultCommand = selectedStartupProfile.startupCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !command.isEmpty, command != defaultCommand else {
            return nil
        }

        return command
    }

    private func consumePendingSSHImportIfNeeded() {
        guard let pendingImport = deepLinkManager.consumePendingSSHImport() else {
            return
        }

        queueImportReview(
            payload: pendingImport.payload,
            sourceDescription: pendingImport.sourceDescription
        )
    }

    private func queueImportReview(
        payload: SSHPrivateKeyQRCodePayload,
        sourceDescription: String
    ) {
        pendingImportReview = PendingSSHImportReview(
            payload: payload,
            sourceDescription: sourceDescription,
            connectAfterImport: payload.connection?.shouldAutoConnect == true,
            rememberConnection: payload.connection != nil
        )
    }

    private func applyImportReview(
        connectAfterImport: Bool,
        rememberConnection: Bool
    ) {
        guard let pendingImportReview else {
            return
        }

        let payload = pendingImportReview.payload
        let privateKey = payload.normalizedPrivateKey
        privateKeyPEM = privateKey
        persistPrivateKey()

        privateKeyImportMessage = importedMessage(
            for: payload,
            source: pendingImportReview.sourceDescription.localizedCaseInsensitiveContains("pairing link")
                ? "pairing link"
                : "QR"
        )
        showingPrivateKey = true
        self.pendingImportReview = nil

        guard let connection = payload.connection,
              !connection.normalizedHost.isEmpty,
              !connection.normalizedUsername.isEmpty else {
            AppLogger.ui.info("SSH import applied as key-only payload")
            return
        }

        host = connection.normalizedHost
        port = String(connection.port)
        username = connection.normalizedUsername
        startupProfileStorage = connection.startupProfile.rawValue
        startupCommand = connection.startupProfile.startupCommand
        pendingOneShotStartupCommand = connection.resolvedStartupCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? connection.resolvedStartupCommand
            : nil
        password = ""
        showingHostEditor = false
        focusedField = nil

        if rememberConnection {
            savedHosts = connectionManager.saveHost(
                host: connection.normalizedHost,
                port: connection.port,
                username: connection.normalizedUsername,
                startupProfile: connection.startupProfile,
                startupCommandOverride: connection.resolvedStartupCommand,
                deviceLabel: payload.label,
                alternateHosts: connection.normalizedAlternateHosts
            )
            refreshSavedHostsFromManager()
        } else {
            connectionManager.reload()
            refreshSavedHostsFromManager()
        }

        AppLogger.ui.info(
            "Applied reviewed SSH import",
            detail: "host=\(connection.normalizedHost) username=\(connection.normalizedUsername) profile=\(connection.startupProfile.rawValue) connectAfterImport=\(connectAfterImport) rememberConnection=\(rememberConnection)"
        )

        guard connectAfterImport else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            connect()
        }
    }

    private func requestTerminalFocus() {
        focusedField = nil
        withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) {
            isTerminalKeyboardPresented = true
        }
        terminalFocusRequestID += 1
        scheduleTerminalRefit(after: .milliseconds(160))
    }

    private func requestTerminalDismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isTerminalKeyboardPresented = false
        }
        terminalDismissRequestID += 1
        scheduleTerminalRefit(after: .milliseconds(160))
    }

    private func closeTerminal() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func refreshSavedHostsFromManager() {
        savedHosts = connectionManager.savedHosts
    }

    private func consumeInitialSavedHostIfNeeded() {
        guard session.status == .disconnected else { return }
        if !didConsumeInitialSavedHost, let initialSavedHost {
            didConsumeInitialSavedHost = true
            AppLogger.ui.info(
                "Consuming initial SSH saved host",
                detail: "host=\(initialSavedHost.host) username=\(initialSavedHost.username) profile=\(initialSavedHost.startupProfile.rawValue) preferredRoute=\(initialRoutePreference?.displayName ?? "classic")"
            )
            connect(
                to: initialSavedHost,
                preferredRoute: initialRoutePreference,
                oneShotStartupCommand: initialOneShotStartupCommand
            )
            return
        }

        consumePendingResumeIfNeeded()
    }

    private func consumePendingResumeIfNeeded() {
        guard session.status == .disconnected else { return }
        guard let pendingSavedHost = connectionManager.consumePendingResumeHost() else { return }
        AppLogger.ui.info(
            "Consuming pending SSH resume",
            detail: "host=\(pendingSavedHost.host) username=\(pendingSavedHost.username) profile=\(pendingSavedHost.startupProfile.rawValue)"
        )
        connect(to: pendingSavedHost)
    }

    private func consumeShiftModifierIfNeeded() {
        guard shiftModifierState.consumesAfterUse else { return }
        shiftModifierState = .inactive
    }

    private func consumeControlModifierIfNeeded() {
        guard controlModifierState.consumesAfterUse else { return }
        controlModifierState = .inactive
    }

    private func sendTerminalInput(_ text: String) {
        guard let resolved = SSHTerminalInputTranslator.resolvedInput(
            for: text,
            controlModifierState: controlModifierState,
            shiftModifierState: shiftModifierState
        ) else {
            return
        }

        session.send(resolved.payload)

        if resolved.consumedControl {
            consumeControlModifierIfNeeded()
        }

        if resolved.consumedShift {
            consumeShiftModifierIfNeeded()
        }
    }

    private func sendCursorMovement(_ direction: SSHTerminalCursorPadDirection) {
        session.send(direction.escapeSequence)
    }

    private func updateCursorPadKnobDrag(with translation: CGSize) {
        let clampedOffset = clampedCursorPadOffset(for: translation)
        cursorPadKnobOffset = clampedOffset
        updateCursorPadRepeat(for: dominantCursorPadDirection(for: clampedOffset))
    }

    private func finishCursorPadKnobDrag() {
        stopCursorPadRepeat(resetKnob: true)
    }

    private func updateCursorPadRepeat(for direction: SSHTerminalCursorPadDirection?) {
        guard cursorPadRepeatDirection != direction else { return }

        cursorPadRepeatTask?.cancel()
        cursorPadRepeatTask = nil
        cursorPadRepeatDirection = direction

        guard let direction else { return }

        sendCursorMovement(direction)
        cursorPadRepeatTask = Task { @MainActor in
            try? await Task.sleep(for: sshFloatingCursorRepeatInitialDelay)
            while !Task.isCancelled {
                sendCursorMovement(direction)
                try? await Task.sleep(for: sshFloatingCursorRepeatInterval)
            }
        }
    }

    private func stopCursorPadRepeat(resetKnob: Bool) {
        cursorPadRepeatTask?.cancel()
        cursorPadRepeatTask = nil
        cursorPadRepeatDirection = nil

        guard resetKnob else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
            cursorPadKnobOffset = .zero
        }
    }

    private func dominantCursorPadDirection(for offset: CGSize) -> SSHTerminalCursorPadDirection? {
        let horizontalMagnitude = abs(offset.width)
        let verticalMagnitude = abs(offset.height)
        guard max(horizontalMagnitude, verticalMagnitude) >= sshFloatingCursorActivationDistance else {
            return nil
        }

        if horizontalMagnitude > verticalMagnitude {
            return offset.width >= 0 ? .right : .left
        }

        return offset.height >= 0 ? .down : .up
    }

    private func clampedCursorPadOffset(for translation: CGSize) -> CGSize {
        let magnitude = hypot(translation.width, translation.height)
        guard magnitude > sshFloatingCursorDragLimit else { return translation }

        let scale = sshFloatingCursorDragLimit / magnitude
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }

    private func requestTerminalRefit() {
        terminalRefitRequestID += 1
    }

    private func scheduleTerminalRefit(after delay: Duration) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            requestTerminalRefit()
        }
    }

    private var terminalRenderer: SSHTerminalRenderer {
        get { SSHTerminalRenderer(rawValue: terminalRendererStorage) ?? .ghostty }
        nonmutating set { terminalRendererStorage = newValue.rawValue }
    }

    private var terminalOuterHorizontalPadding: CGFloat {
        if terminalRenderer == .ghostty {
            return isTerminalFocusedMode ? 4 : 8
        }
        return isTerminalFocusedMode ? 8 : 12
    }

    private var terminalViewportHorizontalInset: CGFloat {
        terminalRenderer == .ghostty ? 4 : 8
    }

    private var terminalViewportTopInset: CGFloat {
        terminalRenderer == .ghostty ? 6 : 8
    }

    private var terminalViewportBottomInset: CGFloat {
        terminalRenderer == .ghostty ? 4 : 6
    }

    private var terminalSurfaceTopCornerRadius: CGFloat {
        isTerminalFocusedMode ? 10 : 9
    }

    private var terminalSurfaceBottomCornerRadius: CGFloat {
        isTerminalFocusedMode ? 8 : 7
    }

    private var terminalHeaderBezelHorizontalInset: CGFloat { 8 }

    private var terminalHeaderBezelCornerRadius: CGFloat { 6 }

    private var sshFloatingCursorPadDiameter: CGFloat { 122 }

    private var sshFloatingCursorButtonSize: CGFloat { 36 }

    private var sshFloatingCursorKnobSize: CGFloat { 44 }

    private var sshFloatingCursorButtonDistance: CGFloat { 36 }

    private var sshFloatingCursorDragLimit: CGFloat { 26 }

    private var sshFloatingCursorActivationDistance: CGFloat { 14 }

    private var sshFloatingCursorRepeatInitialDelay: Duration { .milliseconds(220) }

    private var sshFloatingCursorRepeatInterval: Duration { .milliseconds(75) }

    private var terminalRailWidth: CGFloat {
        terminalRenderer == .ghostty ? 2 : 4
    }

    private func pasteClipboardIntoTerminal() {
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            return
        }

        let normalizedText = clipboardText
            .replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")

        session.send(normalizedText)
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func reviewDescription(
        for payload: SSHPrivateKeyQRCodePayload,
        source: String
    ) -> String {
        let trimmedLabel = payload.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLabel.map { "Review \($0) from \(source) before importing." }
            ?? "Review the SSH import from \(source) before saving anything."
    }

    private func importedMessage(
        for payload: SSHPrivateKeyQRCodePayload,
        source: String
    ) -> String {
        let trimmedLabel = payload.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLabel.map { "Imported \($0) from \(source)." }
            ?? "SSH key imported from \(source)."
    }
}

private struct PendingSSHImportReview: Identifiable, Equatable {
    let id = UUID()
    let payload: SSHPrivateKeyQRCodePayload
    let sourceDescription: String
    var connectAfterImport: Bool
    var rememberConnection: Bool

    var connection: SSHPrivateKeyQRCodePayload.Connection? {
        guard let connection = payload.connection,
              !connection.normalizedHost.isEmpty,
              !connection.normalizedUsername.isEmpty else {
            return nil
        }

        return connection
    }
}

private struct SSHImportReviewSheet: View {
    let review: PendingSSHImportReview
    let keyAlreadyStored: Bool
    let onCancel: () -> Void
    let onImport: (_ connectAfterImport: Bool, _ rememberConnection: Bool) -> Void

    @State private var connectAfterImport: Bool
    @State private var rememberConnection: Bool

    init(
        review: PendingSSHImportReview,
        keyAlreadyStored: Bool,
        onCancel: @escaping () -> Void,
        onImport: @escaping (_ connectAfterImport: Bool, _ rememberConnection: Bool) -> Void
    ) {
        self.review = review
        self.keyAlreadyStored = keyAlreadyStored
        self.onCancel = onCancel
        self.onImport = onImport
        _connectAfterImport = State(initialValue: review.connectAfterImport)
        _rememberConnection = State(initialValue: review.rememberConnection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Import") {
                    Text(review.sourceDescription)
                        .foregroundStyle(.secondary)

                    if let label = review.payload.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !label.isEmpty {
                        LabeledContent("Device", value: label)
                    }

                    LabeledContent("Private Key", value: keyAlreadyStored ? "Replace stored key" : "Save new key")
                }

                if let connection = review.connection {
                    Section("Connection") {
                        LabeledContent("Host", value: connection.normalizedHost)
                        LabeledContent("Port", value: "\(connection.port)")
                        LabeledContent("Username", value: connection.normalizedUsername)
                        LabeledContent("Mode", value: connection.startupProfile.title)
                        LabeledContent("Startup", value: startupSummary(for: connection))
                    }

                    Section("After Import") {
                        Toggle("Remember this connection", isOn: $rememberConnection)
                        Toggle("Connect right away", isOn: $connectAfterImport)
                    }
                }
            }
            .navigationTitle("Review SSH Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(review.connection == nil ? "Import Key" : "Import") {
                        onImport(connectAfterImport, rememberConnection)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func startupSummary(for connection: SSHPrivateKeyQRCodePayload.Connection) -> String {
        let trimmedCommand = connection.resolvedStartupCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCommand.isEmpty else {
            return "login shell"
        }

        if trimmedCommand.contains(".talkie-shell/bin/talkie-shell") {
            return "talkie-shell helper"
        }

        if trimmedCommand.contains(".talkie-shell/bin/talkie-session") {
            return "talkie-session helper"
        }

        if trimmedCommand.contains(".talkie-shell/bin/talkie-enter") {
            return "talkie-enter helper"
        }

        if trimmedCommand.contains("TALKIE_NATIVE_SESSION")
            || trimmedCommand.contains("talkie-native-${TALKIE_SURFACE:-phone}") {
            return "native reusable shell"
        }

        let preview = trimmedCommand.prefix(96)
        return preview.count == trimmedCommand.count ? String(preview) : "\(preview)…"
    }
}

private struct SSHTerminalPreviewCardModel: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let roleLabel: String
    let sourceLabel: String
    let commandPreview: String
    let accent: Color
    let isPrimary: Bool

    var chromeTitle: String {
        switch sourceLabel.lowercased() {
        case "paired mac":
            return "Talkie SSH"
        case "ssh host":
            return "Native SSH"
        case "talkie shell":
            return "Talkie Shell"
        case "talkie session":
            return "Talkie Session"
        default:
            return "Terminal"
        }
    }

    var secondaryLine: String {
        if subtitle.isEmpty {
            return commandPreview
        }

        return "\(subtitle) • \(commandPreview)"
    }
}

#Preview {
    NavigationStack {
        SSHTerminalView()
    }
}
