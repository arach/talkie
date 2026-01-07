//
//  ClaudeView.swift
//  Talkie
//
//  Full-bleed Claude Code session browser.
//  View sessions, messages, and metadata from ~/.claude/projects/
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Models

struct ClaudeSession: Codable, Identifiable, Hashable {
    let id: String
    let folderName: String
    let project: String
    let projectPath: String
    let isLive: Bool
    let lastSeen: String
    let messageCount: Int

    var lastSeenDate: Date? {
        ISO8601DateFormatter().date(from: lastSeen)
    }
}

struct ClaudeMessage: Codable, Identifiable {
    var id: String { "\(timestamp)-\(role)" }
    let role: String
    let content: String
    let timestamp: String
}

struct SessionMetadata: Codable {
    let session: SessionInfo
    let files: [FileInfo]
    let entries: [EntryInfo]
    let stats: MetadataStats

    struct SessionInfo: Codable {
        let id: String
        let project: String
        let projectPath: String
        let folderName: String
        let isLive: Bool
        let lastSeen: String
    }

    struct FileInfo: Codable, Identifiable {
        var id: String { name }
        let name: String
        let path: String
        let sizeBytes: Int
        let modifiedAt: String
        let isSession: Bool
    }

    struct EntryInfo: Codable, Identifiable {
        var id: Int { index }
        let index: Int
        let type: String
        let timestamp: String?
        let sessionId: String?
        let cwd: String?
        let summary: String?
        let keys: [String]
        let sizeBytes: Int
    }

    struct MetadataStats: Codable {
        let totalEntries: Int
        let entryTypes: [String: Int]
        let firstEntry: String?
        let lastEntry: String?
        let fileSizeBytes: Int
    }
}

// MARK: - Live Context Models (from session-contexts.json)

struct LiveDictationRecord: Codable, Identifiable {
    let id: String
    let text: String
    let app: String
    let bundleId: String
    let windowTitle: String
    let timestamp: Date
}

struct LiveSessionContext: Codable {
    let app: String
    let bundleId: String
    let windowTitle: String
    let pid: Int32?
    let workingDirectory: String?
    let timestamp: Date
    var apps: [String]?
    var dictations: [LiveDictationRecord]?
}

struct LiveContextMap: Codable {
    var sessions: [String: LiveSessionContext]
    var lastUpdated: Date
}

// MARK: - Main View

struct ClaudeView: View {
    @State private var sessions: [ClaudeSession] = []
    @State private var selectedSession: ClaudeSession?
    @State private var messages: [ClaudeMessage] = []
    @State private var metadata: SessionMetadata?
    @State private var liveContext: LiveSessionContext?

    @State private var isLoading = false
    @State private var selectedTab: Tab = .messages

    @State private var composeText = ""
    @State private var isSending = false
    @State private var queue = MessageQueue.shared

    // JSON Viewer
    @State private var viewingFile: SessionMetadata.FileInfo?

    enum Tab: String, CaseIterable {
        case messages = "Messages"
        case live = "Live"
        case metadata = "Metadata"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            TalkieViewHeader(
                subtitle: "with Claude",
                debugInfo: {
                    [
                        "Sessions": "\(sessions.count)",
                        "Selected": selectedSession?.project ?? "none"
                    ]
                }
            )

            // Content
            HStack(spacing: 0) {
                // Left: Session list
                sessionList
                    .frame(width: 240)

                Divider()

                // Right: Detail
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.current.background)
        .onAppear {
            loadSessions()
        }
        .sheet(item: $viewingFile) { file in
            JSONViewerSheet(file: file)
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SESSIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: loadSessions) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // List
            if sessions.isEmpty && !isLoading {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Theme.current.surface1)
    }

    private func sessionRow(_ session: ClaudeSession) -> some View {
        let isSelected = selectedSession?.id == session.id

        return Button {
            selectedSession = session
            loadSessionDetail(session)
        } label: {
            HStack(spacing: 8) {
                // Live indicator
                Circle()
                    .fill(session.isLive ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(1)

                    Text(session.projectPath)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(session.messageCount)")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if session.isLive {
                        Text("LIVE")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(2)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.current.backgroundTertiary : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundColor(Theme.current.foregroundSecondary)
            Text("No sessions")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
            Text("Start Claude Code to see sessions")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        VStack(spacing: 0) {
            if let session = selectedSession {
                // Header with tabs
                detailHeader(session)

                Divider()

                // Content
                switch selectedTab {
                case .messages:
                    messagesPane
                    Divider()
                    composeBar
                case .live:
                    livePane
                case .metadata:
                    metadataPane
                }
            } else {
                noSelectionState
            }
        }
        .background(Theme.current.background)
    }

    private func detailHeader(_ session: ClaudeSession) -> some View {
        HStack(spacing: 12) {
            // Session info
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isLive ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)

                Text(session.project)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.current.foreground)

                Text(session.id.prefix(8) + "...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.current.backgroundSecondary)
    }

    private var noSelectionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundColor(Theme.current.foregroundSecondary)
            Text("Select a session")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Messages Pane

    private var messagesPane: some View {
        Group {
            if messages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Text("No messages")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { msg in
                                MessageRow(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(16)
                    }
                    .onAppear {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var composeBar: some View {
        HStack(spacing: 8) {
            TextField("Send to Claude...", text: $composeText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .background(Theme.current.surface1)
                .cornerRadius(8)
                .lineLimit(1...3)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(12)
        .background(Theme.current.backgroundSecondary)
    }

    // MARK: - Metadata Pane

    private var metadataPane: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > 700

            Group {
                if let meta = metadata {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Top row: Session + Stats + Entry Types (3-column on wide screens)
                            if isWide {
                                HStack(alignment: .top, spacing: 16) {
                                    // Session Info (2 slots)
                                    metadataSection("Session") {
                                        metadataRow("ID", meta.session.id)
                                        metadataRow("Project", meta.session.project)
                                        metadataRow("Path", meta.session.projectPath)
                                        metadataRow("Folder", meta.session.folderName)
                                        metadataRow("Status", meta.session.isLive ? "Live" : "Inactive")
                                    }
                                    .frame(maxWidth: .infinity)

                                    // Stats (1 slot)
                                    metadataSection("Statistics") {
                                        metadataStatRow("Entries", "\(meta.stats.totalEntries)")
                                        metadataStatRow("Size", formatBytes(meta.stats.fileSizeBytes))
                                        if let first = meta.stats.firstEntry {
                                            metadataStatRow("First", formatTimestamp(first))
                                        }
                                        if let last = meta.stats.lastEntry {
                                            metadataStatRow("Last", formatTimestamp(last))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)

                                    // Entry Types (1 slot) - as chips
                                    metadataSection("Entry Types") {
                                        entryTypeChips(meta.stats.entryTypes)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            } else {
                                // Narrow layout: stacked
                                metadataSection("Session") {
                                    metadataRow("ID", meta.session.id)
                                    metadataRow("Project", meta.session.project)
                                    metadataRow("Path", meta.session.projectPath)
                                    metadataRow("Folder", meta.session.folderName)
                                    metadataRow("Status", meta.session.isLive ? "Live" : "Inactive")
                                }

                                metadataSection("Statistics") {
                                    metadataStatRow("Entries", "\(meta.stats.totalEntries)")
                                    metadataStatRow("Size", formatBytes(meta.stats.fileSizeBytes))
                                    if let first = meta.stats.firstEntry {
                                        metadataStatRow("First", formatTimestamp(first))
                                    }
                                    if let last = meta.stats.lastEntry {
                                        metadataStatRow("Last", formatTimestamp(last))
                                    }
                                }

                                metadataSection("Entry Types") {
                                    entryTypeChips(meta.stats.entryTypes)
                                }
                            }

                            // Files with folder hierarchy
                            metadataSection("Files") {
                                filesHierarchy(meta.files)
                            }

                            // Recent Entries
                            metadataSection("Recent Entries") {
                                ForEach(meta.entries.suffix(15).reversed()) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("[\(entry.index)]")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Text(entry.type)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(colorForType(entry.type))
                                            Spacer()
                                            if let ts = entry.timestamp {
                                                Text(formatTimestamp(ts))
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        if let summary = entry.summary, !summary.isEmpty {
                                            Text(summary)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(.vertical, 3)
                                    if entry.index != meta.entries.suffix(15).reversed().last?.index {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading metadata...")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Entry Type Chips (prevents line-wrapping on long names)

    @ViewBuilder
    private func entryTypeChips(_ types: [String: Int]) -> some View {
        let sorted = types.sorted { $0.value > $1.value }
        FlowLayout(spacing: 6) {
            ForEach(sorted, id: \.key) { type, count in
                HStack(spacing: 4) {
                    Text(type)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorForType(type))
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colorForType(type).opacity(0.1))
                .cornerRadius(4)
            }
        }
    }

    // MARK: - Files Hierarchy (grouped by folder)

    @ViewBuilder
    private func filesHierarchy(_ files: [SessionMetadata.FileInfo]) -> some View {
        // Group files by their parent directory
        let grouped = Dictionary(grouping: files) { file -> String in
            let url = URL(fileURLWithPath: file.path)
            let dir = url.deletingLastPathComponent().lastPathComponent
            return dir.isEmpty ? "." : dir
        }
        let sortedDirs = grouped.keys.sorted()

        ForEach(sortedDirs, id: \.self) { dir in
            if let dirFiles = grouped[dir] {
                VStack(alignment: .leading, spacing: 4) {
                    // Folder header (only if not root)
                    if sortedDirs.count > 1 || dir != "." {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange.opacity(0.8))
                            Text(dir)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }

                    // Files in this folder
                    ForEach(dirFiles.sorted { $0.name < $1.name }) { file in
                        fileRow(file, indented: sortedDirs.count > 1 || dir != ".")
                    }
                }
            }
        }
    }

    private func fileRow(_ file: SessionMetadata.FileInfo, indented: Bool) -> some View {
        FileRowView(file: file, indented: indented) {
            viewingFile = file
        }
    }

    // MARK: - Stat row (compact, no fixed label width)

    private func metadataStatRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foreground)
        }
    }

    private func metadataSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.current.foregroundSecondary)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.current.surface1)
            .cornerRadius(8)
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.current.foreground)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Live Pane (from session-contexts.json)

    private var livePane: some View {
        Group {
            if let ctx = liveContext {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Current Terminal
                        metadataSection("Current Terminal") {
                            metadataRow("App", ctx.app)
                            metadataRow("Bundle", ctx.bundleId)
                            metadataRow("Window", ctx.windowTitle)
                            if let dir = ctx.workingDirectory {
                                metadataRow("CWD", dir)
                            }
                            if let pid = ctx.pid {
                                metadataRow("PID", "\(pid)")
                            }
                            metadataRow("Updated", formatDate(ctx.timestamp))
                        }

                        // Apps Used
                        if let apps = ctx.apps, !apps.isEmpty {
                            metadataSection("Apps Used") {
                                ForEach(apps, id: \.self) { app in
                                    HStack(spacing: 8) {
                                        Image(systemName: iconForApp(app))
                                            .font(.system(size: 12))
                                            .foregroundColor(.blue)
                                            .frame(width: 20)
                                        Text(app)
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        // Dictation History
                        if let dictations = ctx.dictations, !dictations.isEmpty {
                            metadataSection("Dictation History (\(dictations.count))") {
                                ForEach(dictations.suffix(20).reversed()) { dictation in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: iconForApp(dictation.app))
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                            Text(dictation.app)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.blue)
                                            Spacer()
                                            Text(formatDate(dictation.timestamp))
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        Text(dictation.text)
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.current.foreground)
                                            .lineLimit(3)
                                        if !dictation.windowTitle.isEmpty {
                                            Text(dictation.windowTitle)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    if dictation.id != dictations.suffix(20).reversed().last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Text("No Live Context")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Text("Dictate into this session's terminal to capture context")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func iconForApp(_ app: String) -> String {
        let lower = app.lowercased()
        if lower.contains("ghostty") { return "terminal" }
        if lower.contains("iterm") { return "terminal.fill" }
        if lower.contains("terminal") { return "terminal" }
        if lower.contains("warp") { return "bolt.fill" }
        if lower.contains("hyper") { return "sparkles" }
        return "app"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func loadSessions() {
        isLoading = true
        Task {
            do {
                let url = URL(string: "http://localhost:8765/sessions")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(SessionsResponse.self, from: data)
                sessions = response.sessions
            } catch {
                log.error("Failed to load sessions: \(error)")
            }
            isLoading = false
        }
    }

    private func loadSessionDetail(_ session: ClaudeSession) {
        // Load messages
        Task {
            do {
                let url = URL(string: "http://localhost:8765/sessions/\(session.id)/messages?limit=100")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(MessagesResponse.self, from: data)
                messages = response.messages
            } catch {
                log.error("Failed to load messages: \(error)")
                messages = []
            }
        }

        // Load metadata
        Task {
            do {
                let url = URL(string: "http://localhost:8765/sessions/\(session.id)/metadata")!
                let (data, _) = try await URLSession.shared.data(from: url)
                metadata = try JSONDecoder().decode(SessionMetadata.self, from: data)
            } catch {
                log.error("Failed to load metadata: \(error)")
                metadata = nil
            }
        }

        // Load live context from session-contexts.json
        loadLiveContext(for: session.id)
    }

    private func loadLiveContext(for sessionId: String) {
        // Read from TalkieLive's Application Support folder
        // ~/Library/Application Support/Talkie/.context/session-contexts.json
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            log.error("Could not find Application Support directory")
            liveContext = nil
            return
        }
        let contextFile = appSupport
            .appendingPathComponent("Talkie")
            .appendingPathComponent(".context")
            .appendingPathComponent("session-contexts.json")

        guard FileManager.default.fileExists(atPath: contextFile.path) else {
            log.debug("No session-contexts.json found")
            liveContext = nil
            return
        }

        do {
            let data = try Data(contentsOf: contextFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let contextMap = try decoder.decode(LiveContextMap.self, from: data)

            // Look up this session
            liveContext = contextMap.sessions[sessionId]

            if liveContext != nil {
                log.debug("Loaded live context for session \(sessionId)")
            } else {
                log.debug("No live context for session \(sessionId)")
            }
        } catch {
            log.error("Failed to load session-contexts.json: \(error)")
            liveContext = nil
        }
    }

    private func sendMessage() {
        guard let session = selectedSession else { return }
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        let messageId = queue.recordIncoming(
            sessionId: session.id,
            projectPath: session.projectPath,
            text: text,
            source: .localUI,
            metadata: ["project": session.project]
        )
        queue.updateStatus(messageId, status: .sending)
        let startTime = Date()

        Task {
            do {
                guard let xpc = ServiceManager.shared.live.xpcManager,
                      let proxy = xpc.remoteObjectProxy(errorHandler: { _ in }) else {
                    throw NSError(domain: "Claude", code: 1, userInfo: [NSLocalizedDescriptionKey: "TalkieLive not connected"])
                }

                let result = await withCheckedContinuation { (cont: CheckedContinuation<(Bool, String?), Never>) in
                    proxy.appendMessage(text, sessionId: session.id, projectPath: session.projectPath, submit: true) { success, err in
                        cont.resume(returning: (success, err))
                    }
                }

                let ms = Int(Date().timeIntervalSince(startTime) * 1000)
                if result.0 {
                    queue.updateStatus(messageId, status: .sent, xpcDurationMs: ms)
                    composeText = ""
                } else {
                    queue.updateStatus(messageId, status: .failed, error: result.1, xpcDurationMs: ms)
                }
            } catch {
                let ms = Int(Date().timeIntervalSince(startTime) * 1000)
                queue.updateStatus(messageId, status: .failed, error: error.localizedDescription, xpcDurationMs: ms)
            }
            isSending = false
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        return df.string(from: date)
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "user", "human": return .blue
        case "assistant": return .purple
        case "summary": return .orange
        case "tool_use", "tool_result": return .green
        default: return .secondary
        }
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ClaudeMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if !isUser {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                    }
                    Text(isUser ? "You" : "Claude")
                        .font(.system(size: 10, weight: .medium))
                    Text(formatTime(message.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(isUser ? .blue : .purple)

                Text(message.content)
                    .font(.system(size: 12))
                    .padding(10)
                    .background(isUser ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func formatTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: date)
    }
}

// MARK: - Response Types

private struct SessionsResponse: Codable {
    let sessions: [ClaudeSession]
}

private struct MessagesResponse: Codable {
    let messages: [ClaudeMessage]
}

// MARK: - File Row View (with hover state)

private struct FileRowView: View {
    let file: SessionMetadata.FileInfo
    let indented: Bool
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            if indented {
                Spacer().frame(width: 16)
            }
            Image(systemName: file.isSession ? "doc.fill" : "doc")
                .font(.system(size: 10))
                .foregroundColor(file.isSession ? .blue : .secondary)
            Text(file.name)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .foregroundColor(isHovered ? .accentColor : Theme.current.foreground)
                .underline(isHovered)
            Spacer()
            Text(formatBytes(file.sizeBytes))
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Reveal in Finder button (visible on hover)
            if isHovered {
                Button {
                    let url = URL(fileURLWithPath: file.path)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Reveal in Finder")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onOpen()
        }
        .help("Click to view • ⌘-click to reveal in Finder")
        .simultaneousGesture(
            TapGesture().modifiers(.command).onEnded {
                let url = URL(fileURLWithPath: file.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        )
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - JSON Viewer Sheet

private struct JSONViewerSheet: View {
    let file: SessionMetadata.FileInfo
    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""
    @State private var entries: [JSONEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedEntry: JSONEntry?
    @State private var searchText = ""

    struct JSONEntry: Identifiable, Hashable {
        let id: Int
        let raw: String
        let type: String?
        let timestamp: String?
        let preview: String

        // Hashable conformance (exclude parsed dict)
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: JSONEntry, rhs: JSONEntry) -> Bool {
            lhs.id == rhs.id
        }
    }

    var filteredEntries: [JSONEntry] {
        if searchText.isEmpty { return entries }
        return entries.filter { $0.raw.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(file.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 150)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            .background(Theme.current.backgroundSecondary)

            Divider()

            // Content
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if file.name.hasSuffix(".jsonl") {
                // JSONL: Show entries list with detail
                HSplitView {
                    // Entries list
                    List(filteredEntries, selection: $selectedEntry) { entry in
                        JSONEntryRow(entry: entry)
                            .tag(entry)
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 300)

                    // Detail
                    if let entry = selectedEntry {
                        JSONDetailView(entry: entry)
                    } else {
                        Text("Select an entry")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                // Regular JSON: Pretty print
                ScrollView {
                    Text(content)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Footer
            Divider()
            HStack {
                Text("\(entries.count) entries")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    let url = URL(fileURLWithPath: file.path)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
                } label: {
                    Label("Open in Editor", systemImage: "square.and.pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Theme.current.backgroundSecondary)
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear { loadFile() }
    }

    private func loadFile() {
        isLoading = true
        Task {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: file.path))

                if file.name.hasSuffix(".jsonl") {
                    // Parse JSONL
                    let lines = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
                    var parsed: [JSONEntry] = []

                    for (index, line) in lines.enumerated() {
                        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                        var entryType: String?
                        var timestamp: String?
                        var preview = String(line.prefix(100))

                        if let jsonData = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            entryType = json["type"] as? String
                            timestamp = json["timestamp"] as? String

                            // Build preview
                            if let type = entryType {
                                if type == "user" || type == "human", let msg = json["message"] as? [String: Any], let content = msg["content"] as? String {
                                    preview = String(content.prefix(80))
                                } else if type == "assistant", let msg = json["message"] as? [String: Any], let content = msg["content"] as? String {
                                    preview = String(content.prefix(80))
                                } else {
                                    preview = type
                                }
                            }
                        }

                        parsed.append(JSONEntry(
                            id: index,
                            raw: line,
                            type: entryType,
                            timestamp: timestamp,
                            preview: preview
                        ))
                    }

                    await MainActor.run {
                        entries = parsed
                        if let first = parsed.first {
                            selectedEntry = first
                        }
                        isLoading = false
                    }
                } else {
                    // Pretty print JSON
                    if let json = try? JSONSerialization.jsonObject(with: data),
                       let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        await MainActor.run {
                            content = prettyString
                            isLoading = false
                        }
                    } else {
                        await MainActor.run {
                            content = String(data: data, encoding: .utf8) ?? "Unable to decode"
                            isLoading = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - JSON Entry Row

private struct JSONEntryRow: View {
    let entry: JSONViewerSheet.JSONEntry

    private var typeColor: Color {
        switch entry.type {
        case "user", "human": return .blue
        case "assistant": return .purple
        case "summary": return .orange
        case "tool_use", "tool_result": return .green
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("[\(entry.id)]")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                if let type = entry.type {
                    Text(type)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(typeColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(typeColor.opacity(0.15))
                        .cornerRadius(3)
                }

                Spacer()

                if let ts = entry.timestamp {
                    Text(formatTimestamp(ts))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Text(entry.preview)
                .font(.system(size: 10))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: date)
    }
}

// MARK: - JSON Detail View

private struct JSONDetailView: View {
    let entry: JSONViewerSheet.JSONEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                if let type = entry.type {
                    HStack {
                        Text("Entry \(entry.id)")
                            .font(.system(size: 12, weight: .semibold))
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(type)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorForType(type))
                        if let ts = entry.timestamp {
                            Spacer()
                            Text(ts)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                }

                // Pretty-printed JSON
                if let prettyJSON = prettyPrint(entry.raw) {
                    Text(prettyJSON)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(entry.raw)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Theme.current.surface1)
    }

    private func prettyPrint(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "user", "human": return .blue
        case "assistant": return .purple
        case "summary": return .orange
        case "tool_use", "tool_result": return .green
        default: return .secondary
        }
    }
}

#Preview {
    ClaudeView()
        .frame(width: 900, height: 600)
}
