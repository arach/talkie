//
//  SessionListView.swift
//  Talkie iOS
//
//  List of active Claude Code sessions from Mac
//

import SwiftUI

struct SessionListView: View {
    private var bridgeManager = BridgeManager.shared
    @State private var isRefreshing = false
    @State private var isDeepSyncing = false
    @State private var sessionsMeta: SessionsMeta?
    @State private var showUnpairConfirmation = false
    @State private var showMacDetails = false
    @State private var hasLoadedInitialData = false  // Track if we've ever loaded data

    var body: some View {
        Group {
            switch bridgeManager.status {
            case .connected:
                connectedView
            case .connecting:
                connectingView
            case .error:
                // Show error state with retry option
                disconnectedView
            case .disconnected:
                // If paired but disconnected, auto-connect is about to happen
                if bridgeManager.isPaired {
                    connectingView
                } else {
                    disconnectedView
                }
            }
        }
        .onAppear {
            if bridgeManager.shouldConnect {
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
        .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TalkieNavigationHeader(subtitle: "Claude")
            }
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                DebugToolbarButton(
                    content: {
                        BridgeDebugContent(bridgeManager: bridgeManager)
                    },
                    debugInfo: {
                        [
                            "View": "SessionList",
                            "Status": bridgeManager.status.description,
                            "Projects": "\(bridgeManager.projectPaths.count)",
                            "Sessions": "\(bridgeManager.sessions.count)",
                            "HasData": hasLoadedInitialData ? "Yes" : "No"
                        ]
                    }
                )
            }
            #endif
        }
    }

    private var connectedView: some View {
        ZStack {
            // Background extends under nav bar
            Color.surfacePrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sessions list (scrollable)
                sessionsList

                // Mac status bar - sticky footer
                macStatusFooter
            }
        }
        .onAppear {
            // Trigger initial data load when first connected
            if !hasLoadedInitialData {
                Task {
                    isRefreshing = true
                    await refreshSessions(deepSync: false)
                    isRefreshing = false
                }
            }
        }
    }

    private var macStatusFooter: some View {
        VStack(spacing: 0) {
            // Expanded panel (slides up from footer)
            if showMacDetails {
                VStack(alignment: .leading, spacing: Spacing.md) {
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
                .padding(.vertical, Spacing.xs)
                .background(Color.surfaceSecondary)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main footer bar (collapsed)
            VStack(spacing: 0) {
                // Top divider with spacing
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.3))
                    .frame(height: 1)
                    .padding(.bottom, Spacing.xs)

                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showMacDetails.toggle() } }) {
                HStack(alignment: .center, spacing: Spacing.xs) {
                    // Connection status - indented to avoid corner curve
                    HStack(alignment: .center, spacing: Spacing.xs) {
                        // Computer icon
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)

                        // Device name (Mac Mini) - primary focus
                        Text(truncatedMacName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textPrimary)

                        // Connection status dot on the right
                        Circle()
                            .fill(Color.success)
                            .frame(width: 6, height: 6)
                    }
                    .padding(.leading, Spacing.sm)

                        Spacer()

                        // Live session count
                        if liveSessionCount > 0 {
                 
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.success)
                                    .frame(width: 5, height: 5)
                                Text("\(liveSessionCount) live")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.success)
                            }
                            .padding(.trailing, Spacing.xs)
                        } else {
                            Text("no active")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.textTertiary)
                                .padding(.trailing, Spacing.xs)
                        }

                        // Expand indicator - aligned with project chevrons
                        Image(systemName: showMacDetails ? "chevron.down" : "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 12)
                            .padding(.trailing, Spacing.xs)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                }
                .buttonStyle(.plain)
            }
            .background(Color.surfacePrimary)
        }
    }

    private var sessionsList: some View {
        List {
            // Cold state: Initial loading (no data yet)
            if !hasLoadedInitialData && (isRefreshing || isDeepSyncing) {
                Section {
                    VStack(spacing: Spacing.md) {
                        BrailleSpinner(speed: 0.06, color: .brandAccent)
                            .scaleEffect(1.5)
                        Text("Loading sessions...")
                            .font(.monoSmall)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                    .listRowBackground(Color.clear)
                }
            } else {
                // Warm state: Show refresh indicator at top (already have data)
                if isRefreshing || isDeepSyncing {
                    Section {
                        HStack {
                            Spacer()
                            BrailleSpinner(speed: 0.06, color: .brandAccent)
                            Text("syncing")
                                .font(.techLabelSmall)
                                .foregroundColor(.textTertiary)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                // Projects with sessions (grouped view)
                if !bridgeManager.projectPaths.isEmpty {
                    ForEach(Array(bridgeManager.projectPaths.enumerated()), id: \.element.id) { index, projectPath in
                        ProjectPathSection(projectPath: projectPath, index: index)
                            .padding(.top, index == 0 ? Spacing.md : 0)
                    }
                } else if bridgeManager.sessions.isEmpty {
                    // True empty state (only after we've tried loading)
                    if hasLoadedInitialData {
                        Section {
                            VStack(spacing: Spacing.lg) {
                                Spacer()
                                    .frame(height: Spacing.xl)

                                Image(systemName: "terminal")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundColor(.textTertiary)

                                VStack(spacing: Spacing.xs) {
                                    Text("No Claude Sessions")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.textPrimary)

                                    Text("Start a Claude Code session on your Mac to see it here")
                                        .font(.system(size: 14))
                                        .foregroundColor(.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, Spacing.lg)
                                }

                                if let meta = sessionsMeta, let syncedAt = meta.syncedAt {
                                    Text("Last checked \(formatRelativeTime(syncedAt))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                        .padding(.top, Spacing.xs)
                                }

                                Button(action: {
                                    Task {
                                        isRefreshing = true
                                        await refreshSessions(deepSync: true)
                                        isRefreshing = false
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        if isRefreshing {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Text("Check Again")
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.active)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.sm)
                                    .background(Color.active.opacity(0.1))
                                    .cornerRadius(CornerRadius.sm)
                                }
                                .buttonStyle(.plain)
                                .disabled(isRefreshing)
                                .padding(.top, Spacing.sm)

                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    // Fallback: flat sessions list
                    Section {
                        ForEach(bridgeManager.sessions) { session in
                            NavigationLink(destination: SessionDetailView(session: session)) {
                                SessionRow(session: session)
                            }
                        }
                    }
                }
            }

        }
        .scrollContentBackground(.hidden)
        .background(Color.surfaceSecondary)
        .background {
            // Hide default refresh spinner - find and hide UIRefreshControl
            RefreshControlHider()
        }
        .refreshable {
            isRefreshing = true
            await refreshSessions(deepSync: false)
            await bridgeManager.refreshWindowCaptures()
            isRefreshing = false
        }
        .onAppear {
            // Also use appearance proxy as fallback
            UIRefreshControl.appearance().tintColor = .clear
        }
    }

    // MARK: - Computed

    private var liveSessionCount: Int {
        bridgeManager.projectPaths.reduce(0) { total, project in
            total + project.sessions.filter { $0.isLive }.count
        }
    }

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
            // Fetch both paths (grouped) and sessions (flat) in parallel
            async let pathsResponse = bridgeManager.client.paths(deepSync: deepSync)
            async let sessionsResponse = bridgeManager.client.sessions(deepSync: deepSync)

            let (paths, sessions) = try await (pathsResponse, sessionsResponse)

            await MainActor.run {
                bridgeManager.projectPaths = paths.paths
                bridgeManager.sessions = sessions.sessions
                sessionsMeta = sessions.meta
                hasLoadedInitialData = true  // Mark that we've loaded data at least once
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
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                if bridgeManager.isPaired {
                    // Has pairing but disconnected
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.textTertiary)

                    VStack(spacing: Spacing.xs) {
                        Text("Mac Disconnected")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.textPrimary)

                        if let error = bridgeManager.errorMessage {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.lg)
                        } else {
                            Text("Unable to reach your Mac")
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }

                        // Show retry status
                        if bridgeManager.retryCount > 0 && bridgeManager.retryCount < 3 {
                            Text("Retrying... (\(bridgeManager.retryCount)/3)")
                                .font(.system(size: 12))
                                .foregroundColor(.warning)
                                .padding(.top, Spacing.xxs)
                        }
                    }

                    Button(action: {
                        Task {
                            await bridgeManager.retry()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reconnect")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.active)
                        .cornerRadius(CornerRadius.sm)
                    }
                    .buttonStyle(.plain)
                    .disabled(bridgeManager.status == .connecting)
                    .padding(.top, Spacing.sm)

                    Button(action: { showUnpairConfirmation = true }) {
                        Text("Unpair Mac")
                            .font(.system(size: 13))
                            .foregroundColor(.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Spacing.sm)

                } else {
                    // No pairing - first time setup
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.textTertiary)

                    VStack(spacing: Spacing.xs) {
                        Text("Connect to Your Mac")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.textPrimary)

                        Text("View and interact with Claude Code sessions running on your Mac")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.lg)
                    }

                    NavigationLink(destination: QRScannerView()) {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode.viewfinder")
                            Text("Scan QR Code")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.active)
                        .cornerRadius(CornerRadius.sm)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Spacing.sm)

                    // Hint about Tailscale
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("Requires Tailscale on both devices")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.textTertiary)
                    .padding(.top, Spacing.md)
                }

                Spacer()
            }
            .padding(Spacing.md)
        }
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
    
    private var isRecent: Bool {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: session.lastSeen) else { return false }
        return Date().timeIntervalSince(date) < 3600 // Within last hour
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
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
                HStack(spacing: Spacing.xxs) {
                    Text(summaryCache.getSummary(for: session.id) ?? generateQuickSummary())
                        .font(.labelSmall)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    
                    // Recent tag for recent sessions
                    if isRecent {
                        Text("recent")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.textTertiary.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
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

// MARK: - Project Path Section (Grouped Sessions)

struct ProjectPathSection: View {
    let projectPath: ProjectPath
    let index: Int  // For determining default expanded state
    @State private var isExpanded: Bool
    @State private var showAll = false

    private let maxVisibleSessions = 3

    init(projectPath: ProjectPath, index: Int) {
        self.projectPath = projectPath
        self.index = index
        // Start expanded for first 2 projects only
        self._isExpanded = State(initialValue: index < 2)
    }

    private var visibleSessions: [PathSession] {
        // Deduplicate sessions by ID (keep first occurrence)
        let uniqueSessions = projectPath.sessions.reduce(into: [String: PathSession]()) { dict, session in
            if dict[session.id] == nil {
                dict[session.id] = session
            }
        }.values.sorted { session1, session2 in
            // Sort live sessions first, then by lastSeen descending (most recent first)
            if session1.isLive != session2.isLive {
                return session1.isLive
            }
            let formatter = ISO8601DateFormatter()
            let date1 = formatter.date(from: session1.lastSeen) ?? Date.distantPast
            let date2 = formatter.date(from: session2.lastSeen) ?? Date.distantPast
            return date1 > date2
        }

        if showAll || uniqueSessions.count <= maxVisibleSessions {
            return Array(uniqueSessions)
        }
        return Array(uniqueSessions.prefix(maxVisibleSessions))
    }
    
    private var uniqueSessionCount: Int {
        Set(projectPath.sessions.map { $0.id }).count
    }

    private var hasMoreSessions: Bool {
        uniqueSessionCount > maxVisibleSessions && !showAll
    }

    var body: some View {
        Section {
            if isExpanded {
                // Sessions (limited or all)
                ForEach(visibleSessions) { session in
                    NavigationLink(destination: SessionDetailViewByPath(sessionId: session.id, projectPath: projectPath)) {
                        PathSessionRow(session: session)
                    }
                }

                // "Show more" row
                if hasMoreSessions {
                    Button(action: { withAnimation { showAll = true } }) {
                        HStack {
                            Text("Show \(uniqueSessionCount - maxVisibleSessions) more...")
                                .font(.system(size: 12))
                                .foregroundColor(.brandAccent)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: Spacing.xs) {
                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 12)

                    // Project name
                    Text(projectPath.name.uppercased())
                        .font(.techLabel)
                        .tracking(1)
                        .foregroundColor(.textPrimary)

                    // Session count
                    Text("(\(uniqueSessionCount))")
                        .font(.techLabelSmall)
                        .foregroundColor(.textTertiary)

                    Spacer()

                    // Last active time
                    Text(compactTime(from: projectPath.lastSeen))
                        .font(.techLabelSmall)
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func compactTime(from isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return "" }
        let interval = Date().timeIntervalSince(date)

        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - Path Session Row (Compact - Single Line)

struct PathSessionRow: View {
    let session: PathSession

    private var lastSeenDate: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: session.lastSeen)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            // Live/inactive indicator
            Circle()
                .fill(session.isLive ? Color.success : Color.textTertiary.opacity(0.3))
                .frame(width: 5, height: 5)
                .padding(.top, 2)  // Align with first line of text

            // Content - two lines
            VStack(alignment: .leading, spacing: 1) {
                // Primary line: preview text + date
                HStack(spacing: 0) {
                    Text(previewText)
                        .font(.system(size: 12))
                        .foregroundColor(session.isLive ? .textPrimary : .textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: Spacing.sm)

                    Text(compactTimestamp)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }

                // Secondary line: message count with icon
                HStack(spacing: 3) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary.opacity(0.7))
                    Text("\(session.messageCount)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(.vertical, 2)  // Tighter: reduced from 4 to 2
    }

    private var previewText: String {
        // Priority: lastMessage > title > session ID
        if let preview = session.lastMessage, !preview.isEmpty {
            // Take first line only, trim whitespace
            let firstLine = preview.components(separatedBy: .newlines).first ?? preview
            return firstLine.trimmingCharacters(in: .whitespaces)
        }
        if let title = session.title, !title.isEmpty {
            return title
        }
        return String(session.id.prefix(12)) + "..."
    }

    private var compactTimestamp: String {
        guard let date = lastSeenDate else { return "" }
        let interval = Date().timeIntervalSince(date)

        // Very recent: "now"
        if interval < 60 { return "now" }

        // Within an hour: "5m"
        if interval < 3600 { return "\(Int(interval / 60))m" }

        // Today: show time "3:45 PM"
        if Calendar.current.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }

        // Yesterday
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }

        // Within a week: "3d"
        if interval < 604800 {
            return "\(Int(interval / 86400))d"
        }

        // Older: short date
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Session Detail View by Path (for grouped sessions)

struct SessionDetailViewByPath: View {
    let sessionId: String
    let projectPath: ProjectPath

    var body: some View {
        // Create a ClaudeSession from PathSession for the existing detail view
        let session = ClaudeSession(
            id: sessionId,
            folderName: projectPath.folderName,
            project: projectPath.name,
            projectPath: projectPath.path,
            isLive: projectPath.sessions.first(where: { $0.id == sessionId })?.isLive ?? false,
            lastSeen: projectPath.sessions.first(where: { $0.id == sessionId })?.lastSeen ?? "",
            messageCount: projectPath.sessions.first(where: { $0.id == sessionId })?.messageCount ?? 0
        )
        SessionDetailView(session: session)
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
            // Screenshot - preserve natural aspect ratio
            Group {
                if let imageData = capture.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 120)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 80)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderPrimary, lineWidth: 1)
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

// MARK: - Refresh Control Hider

struct RefreshControlHider: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Find and hide refresh control by traversing the view hierarchy
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                findAndHideRefreshControl(in: window)
            }
        }
    }
    
    private func findAndHideRefreshControl(in view: UIView) {
        // Check if this is a scroll view with a refresh control
        if let scrollView = view as? UIScrollView {
            if let refreshControl = scrollView.refreshControl {
                refreshControl.tintColor = .clear
                refreshControl.backgroundColor = .clear
            }
        }

        // Recursively search subviews
        view.subviews.forEach { findAndHideRefreshControl(in: $0) }
    }
}

#if DEBUG
// MARK: - Bridge Debug Content

struct BridgeDebugContent: View {
    let bridgeManager: BridgeManager
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var selectedWindow: WindowCapture?

    var body: some View {
        VStack(spacing: 10) {
            DebugSection(title: "BRIDGE") {
                VStack(spacing: 4) {
                    DebugActionButton(icon: "arrow.clockwise", label: "Force Refresh") {
                        Task {
                            await bridgeManager.connect()
                        }
                    }
                    DebugActionButton(icon: "wifi.slash", label: "Disconnect") {
                        bridgeManager.disconnect()
                    }
                }
            }

            DebugSection(title: "WINDOWS") {
                VStack(spacing: 4) {
                    // Window count
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary)
                        Text("\(bridgeManager.windowCaptures.count) captured")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.textSecondary)
                        Spacer()
                    }

                    if let error = captureError {
                        Text(error)
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                            .lineLimit(2)
                    }

                    DebugActionButton(
                        icon: isCapturing ? "hourglass" : "camera",
                        label: isCapturing ? "Capturing..." : "Capture Windows"
                    ) {
                        captureWindows()
                    }
                    .disabled(isCapturing)
                }
            }
        }
        .sheet(item: $selectedWindow) { window in
            WindowDetailSheet(capture: window)
        }
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
}

extension BridgeManager.ConnectionStatus {
    var description: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
}
#endif

#Preview {
    NavigationView {
        SessionListView()
    }
}
