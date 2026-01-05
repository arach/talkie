//
//  MacView.swift
//  Talkie iOS
//
//  Primary view for Mac Bridge - shows Claude sessions with screenshots
//

import SwiftUI

struct MacView: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var isRefreshing = false
    @State private var selectedSession: ClaudeSession?
    @State private var showingQRScanner = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                Group {
                    switch bridgeManager.status {
                    case .connected:
                        connectedContentView
                    case .connecting:
                        connectingView
                    case .disconnected, .error:
                        disconnectedView
                    }
                }
            }
            .navigationTitle("MAC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(bridgeManager.status.color)
                                .frame(width: 6, height: 6)
                            Text("MAC")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(.textPrimary)
                        }
                        if let macName = bridgeManager.pairedMacName, bridgeManager.status == .connected {
                            Text(macName.uppercased())
                                .font(.techLabelSmall)
                                .tracking(1)
                                .foregroundColor(.textTertiary)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if bridgeManager.status == .connected {
                        Button(action: refreshAll) {
                            if isRefreshing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingQRScanner) {
            QRScannerView()
        }
        .sheet(item: $selectedSession) { session in
            NavigationView {
                SessionDetailView(session: session)
            }
        }
        .onAppear {
            if bridgeManager.isPaired && bridgeManager.status == .disconnected {
                Task {
                    await bridgeManager.connect()
                }
            }
        }
    }

    // MARK: - Connected View

    private var connectedContentView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Sessions Section
                sessionsSection

                // Terminal Windows Section
                if !bridgeManager.windowCaptures.isEmpty {
                    windowsSection
                }

                // Footer
                connectionFooter
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.md)
        }
        .refreshable {
            await refreshAllAsync()
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            HStack {
                Text("SESSIONS")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textTertiary)

                Spacer()

                Text("\(bridgeManager.sessions.count)")
                    .font(.techLabel)
                    .foregroundColor(.textTertiary)
            }

            if bridgeManager.sessions.isEmpty {
                emptySessionsCard
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(bridgeManager.sessions) { session in
                        SessionCard(session: session) {
                            selectedSession = session
                        }
                    }
                }
            }
        }
    }

    private var emptySessionsCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "terminal")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.textTertiary)

            VStack(spacing: Spacing.xs) {
                Text("NO ACTIVE SESSIONS")
                    .font(.techLabel)
                    .tracking(1)
                    .foregroundColor(.textSecondary)

                Text("Start Claude Code on your Mac")
                    .font(.bodySmall)
                    .foregroundColor(.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.md)
    }

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            HStack {
                Text("TERMINAL WINDOWS")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textTertiary)

                Spacer()

                Text("\(bridgeManager.windowCaptures.count)")
                    .font(.techLabel)
                    .foregroundColor(.textTertiary)
            }

            // Horizontal scrolling screenshots
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(bridgeManager.windowCaptures) { capture in
                        WindowThumbnail(capture: capture)
                    }
                }
            }
        }
    }

    private var connectionFooter: some View {
        VStack(spacing: Spacing.sm) {
            Divider()
                .background(Color.borderPrimary)

            HStack {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 14))
                    .foregroundColor(.success)

                Text(bridgeManager.pairedMacName ?? "Mac")
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)

                Spacer()

                Button(action: {
                    bridgeManager.disconnect()
                }) {
                    Text("Disconnect")
                        .font(.labelSmall)
                        .foregroundColor(.recording)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - Connecting View

    private var connectingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)

            Text("CONNECTING")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textSecondary)

            if let macName = bridgeManager.pairedMacName {
                Text(macName)
                    .font(.bodySmall)
                    .foregroundColor(.textTertiary)
            }

            Spacer()
        }
    }

    // MARK: - Disconnected View

    private var disconnectedView: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.surfaceSecondary)
                    .frame(width: 100, height: 100)

                Image(systemName: "desktopcomputer")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.textTertiary)
            }

            // Content
            VStack(spacing: Spacing.sm) {
                if bridgeManager.isPaired {
                    Text("MAC DISCONNECTED")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textPrimary)

                    if let error = bridgeManager.errorMessage {
                        Text(error)
                            .font(.bodySmall)
                            .foregroundColor(.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("CONNECT TO MAC")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textPrimary)

                    Text("View Claude Code sessions remotely via Tailscale")
                        .font(.bodySmall)
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }
            }

            // Action buttons
            VStack(spacing: Spacing.sm) {
                if bridgeManager.isPaired {
                    Button(action: {
                        Task {
                            await bridgeManager.connect()
                        }
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.clockwise")
                            Text("RECONNECT")
                        }
                        .font(.labelMedium)
                        .tracking(1)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.brandAccent)
                        .cornerRadius(CornerRadius.sm)
                    }

                    Button(action: {
                        bridgeManager.unpair()
                    }) {
                        Text("Unpair Mac")
                            .font(.labelSmall)
                            .foregroundColor(.recording)
                    }
                    .padding(.top, Spacing.xs)
                } else {
                    Button(action: {
                        showingQRScanner = true
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "qrcode.viewfinder")
                            Text("SCAN QR CODE")
                        }
                        .font(.labelMedium)
                        .tracking(1)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.brandAccent)
                        .cornerRadius(CornerRadius.sm)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func refreshAll() {
        isRefreshing = true
        Task {
            await refreshAllAsync()
            isRefreshing = false
        }
    }

    private func refreshAllAsync() async {
        await bridgeManager.refreshAll()
        await bridgeManager.refreshWindowCaptures()
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let session: ClaudeSession
    let onTap: () -> Void

    @State private var inputText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.xs) {
                            Text(session.project)
                                .font(.headlineMedium)
                                .foregroundColor(.textPrimary)

                            if session.isLive {
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.success)
                                    .cornerRadius(3)
                            }
                        }

                        HStack(spacing: Spacing.sm) {
                            Label("\(session.messageCount)", systemImage: "bubble.left.and.bubble.right")
                                .font(.monoSmall)
                                .foregroundColor(.textTertiary)

                            Text(formatRelativeTime(session.lastSeen))
                                .font(.monoSmall)
                                .foregroundColor(.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)

            // Compose bar (only for live sessions)
            if session.isLive {
                Divider()
                    .background(Color.borderPrimary)

                composeBar
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.md)
    }

    private var composeBar: some View {
        VStack(spacing: Spacing.xxs) {
            if let error = sendError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.recording)
            }

            HStack(spacing: Spacing.xs) {
                TextField("Send to Claude...", text: $inputText)
                    .font(.bodySmall)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .disabled(isSending)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Group {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                        }
                    }
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? .textTertiary : .brandAccent)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        sendError = nil

        Task {
            do {
                try await BridgeManager.shared.sendMessage(sessionId: session.id, text: text)
                inputText = ""
                sendError = nil
            } catch {
                sendError = error.localizedDescription
            }
            isSending = false
        }
    }

    private func formatRelativeTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Window Thumbnail

struct WindowThumbnail: View {
    let capture: WindowCapture

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Screenshot
            if let imageData = capture.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 130)
                    .clipped()
                    .cornerRadius(CornerRadius.sm)
            } else {
                Rectangle()
                    .fill(Color.surfaceTertiary)
                    .frame(width: 200, height: 130)
                    .cornerRadius(CornerRadius.sm)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.textTertiary)
                    }
            }

            // Title
            Text(capture.title)
                .font(.labelSmall)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview {
    MacView()
}
