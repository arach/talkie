//
//  TerminalNext.swift
//  Talkie iOS
//
//  Next top-level SSH terminal surface. Owns the shell route for saved
//  hosts while preserving the existing SSHTerminalView flow for the
//  actual session UI.
//

import SwiftUI

struct TerminalNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var connectionManager = SSHTerminalConnectionManager.shared
    @State private var savedHosts: [SSHTerminalSavedHost]
    @State private var presentingHost: SSHTerminalSavedHost?
    @State private var showingKeyImporter = false
    @State private var importMessage: String?

    private let savedHostStore = SSHTerminalSavedHostStore()
    private let privateKeyStore = SSHPrivateKeyStore()

    init() {
        _savedHosts = State(initialValue: SSHTerminalSavedHostStore().load())
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

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
        }
        .onAppear(perform: refreshHosts)
        .sheet(item: $presentingHost, onDismiss: refreshHosts) { host in
            TerminalNextSessionSheet(host: host)
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

            Button(action: { AppShellRouter.shared.openHome() }) {
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

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Text("SAVED HOSTS")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)

            Spacer()

            Button(action: { showingKeyImporter = true }) {
                Text("ADD HOST")
                    .talkieType(.chipLabel)
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
        }
    }

    private func hostRow(_ host: SSHTerminalSavedHost) -> some View {
        Button {
            presentingHost = host
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
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
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(host.lastUsedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .talkieType(.timestamp)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        statusDot(for: host)
                        Text(host.previewSourceLabel)
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }

    private func statusDot(for host: SSHTerminalSavedHost) -> some View {
        let activeConnection = connectionManager.activeConnection
        let isActive = activeConnection?.deviceID == host.resolvedDeviceIdentifier || activeConnection?.hostTitle == host.title

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

                Text("Scan the SSH access QR from Talkie for Mac to add a terminal destination.")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: { showingKeyImporter = true }) {
                Text("ADD HOST")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.cardBackground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
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
    }
}


private struct TerminalNextSessionSheet: View {
    let host: SSHTerminalSavedHost

    init(host: SSHTerminalSavedHost) {
        self.host = host
        SSHTerminalConnectionManager.shared.requestResume(for: host)
    }

    var body: some View {
        NavigationStack {
            SSHTerminalView()
        }
    }
}
