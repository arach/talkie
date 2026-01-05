//
//  SessionListView.swift
//  Talkie iOS
//
//  List of active Claude Code sessions from Mac
//

import SwiftUI

struct SessionListView: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var isRefreshing = false
    @State private var isDeepSyncing = false
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var selectedWindow: WindowCapture?
    @State private var sessionsMeta: SessionsMeta?
    @State private var showUnpairConfirmation = false
    @State private var showMacDetails = false

    var body: some View {
        Group {
            switch bridgeManager.status {
            case .connected:
                connectedView
            case .connecting:
                connectingView
            case .disconnected, .error:
                // If paired but disconnected, show connecting (we're about to auto-connect)
                if bridgeManager.isPaired {
                    connectingView
                } else {
                    disconnectedView
                }
            }
        }
        .onAppear {
            if bridgeManager.isPaired && bridgeManager.status == .disconnected {
                Task {
                    await bridgeManager.connect()
                }
            }
        }
        .alert("Unpair from Mac?", isPresented: $showUnpairConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unpair", role: .destructive) {
                bridgeManager.unpair()
            }
        } message: {
            Text("This will remove all pairing data. You'll need to scan the QR code again to reconnect.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("TALKIE")
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("with Claude")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var connectedView: some View {
        VStack(spacing: 0) {
            // Sessions list (scrollable)
            sessionsList

            // Mac status bar - sticky footer
            macStatusFooter
        }
    }

    private var macStatusFooter: some View {
        VStack(spacing: 0) {
            // Expanded panel (slides up from footer)
            if showMacDetails {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Full hostname with refresh
                    HStack {
                        Text("HOST")
                            .font(.techLabelSmall)
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text(bridgeManager.pairedMacName ?? "Unknown")
                            .font(.monoSmall)
                            .foregroundColor(.textSecondary)

                        // Quick refresh button
                        Button(action: {
                            Task {
                                isRefreshing = true
                                await refreshSessions(deepSync: false)
                                isRefreshing = false
                            }
                        }) {
                            if isRefreshing {
                                BrailleSpinner(speed: 0.06, color: .brandAccent)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRefreshing || isDeepSyncing)
                    }

                    // Last sync
                    if let meta = sessionsMeta, let syncedAt = meta.syncedAt {
                        HStack {
                            Text("SYNCED")
                                .font(.techLabelSmall)
                                .foregroundColor(.textTertiary)
                            Spacer()
                            Text(formatRelativeTime(syncedAt))
                                .font(.monoSmall)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Divider()
                        .padding(.vertical, Spacing.xxs)

                    // Action buttons
                    HStack(spacing: Spacing.xs) {
                        BridgeActionButton(
                            icon: "arrow.trianglehead.2.clockwise",
                            label: "Deep Sync",
                            color: .brandAccent,
                            isLoading: isDeepSyncing
                        ) {
                            Task {
                                isDeepSyncing = true
                                await refreshSessions(deepSync: true)
                                isDeepSyncing = false
                            }
                        }
                        .disabled(isDeepSyncing || isRefreshing)

                        BridgeActionButton(
                            icon: "wifi.slash",
                            label: "Disconnect",
                            color: .textSecondary
                        ) {
                            bridgeManager.disconnect()
                        }

                        BridgeActionButton(
                            icon: "xmark.circle",
                            label: "Unpair",
                            color: .recording
                        ) {
                            showUnpairConfirmation = true
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.surfaceSecondary)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main footer bar (collapsed)
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showMacDetails.toggle() } }) {
                HStack(spacing: Spacing.sm) {
                    // Connection status
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Connected")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Text(truncatedMacName)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Spacer()

                    // Expand indicator (refresh only in expanded view)
                    Image(systemName: showMacDetails ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(.plain)
            .background(Color.surfacePrimary)
            .overlay(
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.3))
                    .frame(height: 0.5),
                alignment: .top
            )
        }
    }

    private var sessionsList: some View {
        List {
            // Sessions
            Section {
                if bridgeManager.sessions.isEmpty {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(.secondary)
                        Text("No active sessions")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(bridgeManager.sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRow(session: session)
                        }
                    }
                }
            }

            // Terminal Windows (Screenshots)
            Section("Terminal Windows") {
                if let error = captureError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if bridgeManager.windowCaptures.isEmpty {
                    HStack {
                        Image(systemName: "macwindow")
                            .foregroundColor(.secondary)
                        Text("No windows captured")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)

                    Button(action: captureWindows) {
                        if isCapturing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Capturing...")
                            }
                        } else {
                            Label("Capture Windows", systemImage: "camera")
                        }
                    }
                    .disabled(isCapturing)
                } else {
                    // Grid of window thumbnails
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(bridgeManager.windowCaptures) { capture in
                            WindowThumbnailCell(capture: capture)
                                .onTapGesture {
                                    selectedWindow = capture
                                }
                        }
                    }
                    .padding(.vertical, 8)

                    Button(action: captureWindows) {
                        if isCapturing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Refreshing...")
                            }
                        } else {
                            Label("Refresh Screenshots", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isCapturing)
                }
            }

        }
        .refreshable {
            await refreshSessions(deepSync: false)
            await bridgeManager.refreshWindowCaptures()
        }
        .sheet(item: $selectedWindow) { window in
            WindowDetailSheet(capture: window)
        }
    }

    // MARK: - Computed

    private var truncatedMacName: String {
        guard let fullName = bridgeManager.pairedMacName else { return "Mac" }
        // Show first part before .tail or first 20 chars
        if let tailRange = fullName.range(of: ".tail") {
            return String(fullName[..<tailRange.lowerBound])
        }
        if fullName.count > 20 {
            return String(fullName.prefix(20)) + "…"
        }
        return fullName
    }

    // MARK: - Actions

    private func refreshSessions(deepSync: Bool) async {
        do {
            let response = try await bridgeManager.client.sessions(deepSync: deepSync)
            await MainActor.run {
                bridgeManager.sessions = response.sessions
                sessionsMeta = response.meta
            }
        } catch {
            // Handle error silently for now, bridgeManager handles connection state
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

    private func captureWindows() {
        isCapturing = true
        captureError = nil
        Task {
            do {
                try await bridgeManager.refreshWindowCapturesWithError()
            } catch {
                captureError = error.localizedDescription
            }
            isCapturing = false
        }
    }

    private var connectingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Animated connection indicator
            ConnectingAnimation()

            VStack(spacing: Spacing.xs) {
                Text("Connecting to Mac")
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)

                if let macName = bridgeManager.pairedMacName {
                    Text(macName)
                        .font(.monoSmall)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.surfacePrimary)
    }

    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "desktopcomputer")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            if bridgeManager.isPaired {
                // Has pairing but disconnected
                VStack(spacing: 8) {
                    Text("Mac Disconnected")
                        .font(.headline)

                    if let error = bridgeManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Button("Reconnect") {
                    Task {
                        await bridgeManager.connect()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    showUnpairConfirmation = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Unpair Mac")
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(.top, 8)
            } else {
                // No pairing
                VStack(spacing: 8) {
                    Text("Connect to Mac")
                        .font(.headline)

                    Text("View Claude Code sessions from your Mac remotely")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                NavigationLink(destination: QRScannerView()) {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Connecting Animation

struct ConnectingAnimation: View {
    @State private var pulse = false
    @State private var wave1 = false
    @State private var wave2 = false
    @State private var wave3 = false

    var body: some View {
        ZStack {
            // Outer waves
            Circle()
                .stroke(Color.brandAccent.opacity(0.15), lineWidth: 2)
                .frame(width: 120, height: 120)
                .scaleEffect(wave3 ? 1.0 : 0.5)
                .opacity(wave3 ? 0 : 0.8)

            Circle()
                .stroke(Color.brandAccent.opacity(0.25), lineWidth: 2)
                .frame(width: 90, height: 90)
                .scaleEffect(wave2 ? 1.0 : 0.5)
                .opacity(wave2 ? 0 : 0.8)

            Circle()
                .stroke(Color.brandAccent.opacity(0.4), lineWidth: 2)
                .frame(width: 60, height: 60)
                .scaleEffect(wave1 ? 1.0 : 0.5)
                .opacity(wave1 ? 0 : 0.8)

            // Center icon
            ZStack {
                Circle()
                    .fill(Color.brandAccent.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulse ? 1.05 : 0.95)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.brandAccent)
            }
        }
        .onAppear {
            // Staggered wave animations
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                wave1 = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    wave2 = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    wave3 = true
                }
            }
            // Center pulse
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Session Summary Cache (Background AI)

/// Manages background AI summary generation with low priority
@MainActor
class SessionSummaryCache: ObservableObject {
    static let shared = SessionSummaryCache()

    @Published private(set) var summaries: [String: String] = [:]
    private var pendingSessionIds: Set<String> = []

    private init() {}

    func getSummary(for sessionId: String) -> String? {
        return summaries[sessionId]
    }

    /// Queue a session for background summary generation
    func queueSummary(for session: ClaudeSession) {
        let sessionId = session.id

        // Skip if already cached or pending
        guard summaries[sessionId] == nil, !pendingSessionIds.contains(sessionId) else {
            return
        }

        pendingSessionIds.insert(sessionId)

        // Fire and forget - truly background, low priority
        Task.detached(priority: .background) { [sessionId] in
            await Self.generateSummaryInBackground(sessionId: sessionId)
        }
    }

    private static func generateSummaryInBackground(sessionId: String) async {
        // Check AI availability
        let aiService = await OnDeviceAIService.shared
        let isAvailable = await aiService.isAvailable

        print("[SessionSummary] Attempting summary for \(sessionId), AI available: \(isAvailable)")

        guard isAvailable else {
            print("[SessionSummary] AI not available, skipping")
            await MainActor.run {
                shared.pendingSessionIds.remove(sessionId)
            }
            return
        }

        do {
            // Small delay to not compete with UI
            try await Task.sleep(nanoseconds: 500_000_000)

            // Fetch messages
            print("[SessionSummary] Fetching messages...")
            let messages = try await BridgeManager.shared.getMessages(sessionId: sessionId)
            print("[SessionSummary] Got \(messages.count) messages")

            guard !messages.isEmpty else {
                print("[SessionSummary] No messages, skipping")
                await MainActor.run {
                    shared.pendingSessionIds.remove(sessionId)
                }
                return
            }

            // Generate summary (this is the slow part)
            print("[SessionSummary] Generating AI summary...")
            let summary = try await aiService.summarizeSession(messages: messages)
            print("[SessionSummary] Generated: \(summary)")

            // Update cache on main thread
            await MainActor.run {
                shared.summaries[sessionId] = summary
                shared.pendingSessionIds.remove(sessionId)
                print("[SessionSummary] Cached summary for \(sessionId)")
            }
        } catch {
            print("[SessionSummary] Error: \(error)")
            await MainActor.run {
                shared.pendingSessionIds.remove(sessionId)
            }
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: ClaudeSession
    @ObservedObject private var summaryCache = SessionSummaryCache.shared

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Live indicator dot
            Circle()
                .fill(session.isLive ? Color.success : Color.tactical500.opacity(0.3))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // Project name + message count
                HStack(spacing: Spacing.xs) {
                    Text(session.project)
                        .font(.monoMedium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text("·")
                        .foregroundColor(.textTertiary)

                    Text("\(session.messageCount)")
                        .font(.monoSmall)
                        .foregroundColor(.textTertiary)
                }

                // AI Summary (appears when ready) or fallback
                Text(summaryCache.getSummary(for: session.id) ?? generateQuickSummary())
                    .font(.labelSmall)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Compact time
            Text(compactTime)
                .font(.techLabelSmall)
                .foregroundColor(.textTertiary)
        }
        .padding(.vertical, Spacing.xxs)
        .onAppear {
            // Queue for background processing - doesn't block anything
            summaryCache.queueSummary(for: session)
        }
    }

    private var compactTime: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: session.lastSeen) else { return "" }
        let interval = Date().timeIntervalSince(date)

        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }

    private func generateQuickSummary() -> String {
        if session.isLive {
            return "Active session"
        } else if session.messageCount > 50 {
            return "Long conversation"
        } else if session.messageCount > 10 {
            return "Ongoing work"
        } else {
            return "Quick task"
        }
    }
}

// MARK: - Bridge Action Button

struct BridgeActionButton: View {
    let icon: String
    let label: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPressed = false
                }
                action()
            }
        }) {
            VStack(spacing: Spacing.xxs) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(label)
                    .font(.techLabelSmall)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
            .background(color.opacity(isPressed ? 0.15 : 0.08))
            .cornerRadius(CornerRadius.sm)
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window Thumbnail Cell

struct WindowThumbnailCell: View {
    let capture: WindowCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Screenshot
            Group {
                if let imageData = capture.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 90)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 90)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            // Window title
            Text(capture.title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Window Detail Sheet

struct WindowDetailSheet: View {
    let capture: WindowCapture
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Full-size screenshot
                    if let imageData = capture.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                    }

                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        MetadataRow(label: "Window ID", value: "\(capture.windowID)")
                        MetadataRow(label: "Bundle ID", value: capture.bundleId)
                        MetadataRow(label: "Title", value: capture.title)
                        if let imageData = capture.imageData {
                            MetadataRow(label: "Image Size", value: "\(imageData.count / 1024) KB")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle(capture.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationView {
        SessionListView()
    }
}
