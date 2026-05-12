//
//  LogsScreen.swift
//  Talkie macOS
//
//  Live activity logs viewer with tactical dark theme
//  Events persist to log files and logs viewer reads from them
//

import SwiftUI
import Combine
import os

private let fileLogger = Logger(subsystem: "to.talkie.app.mac", category: "LogFile")

// Cached ISO8601 formatter for performance
private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

// MARK: - System Event Model

enum SystemEventSource: String, CaseIterable {
    case talkie = "Talkie"
    case talkieLive = "TalkieAgent"
    case talkieSync = "TalkieSync"

    /// Legacy raw value mapping so old log lines with "Engine" source still parse.
    init?(rawValue: String) {
        switch rawValue {
        case "Talkie": self = .talkie
        case "TalkieAgent": self = .talkieLive
        case "Engine": self = .talkieLive  // Engine logs now attributed to Agent
        case "TalkieSync": self = .talkieSync
        default: return nil
        }
    }

    var chipLabel: String {
        switch self {
        case .talkie: return "TALKIE"
        case .talkieLive: return "AGENT"
        case .talkieSync: return "SYNC"
        }
    }

    var color: Color {
        switch self {
        case .talkie: return Color(red: 0.4, green: 0.7, blue: 1.0)
        case .talkieLive: return Color(red: 0.7, green: 0.5, blue: 1.0)
        case .talkieSync: return Color(red: 0.4, green: 0.8, blue: 0.4)
        }
    }

    var icon: String {
        switch self {
        case .talkie: return "app.fill"
        case .talkieLive: return "menubar.rectangle"
        case .talkieSync: return "arrow.triangle.2.circlepath"
        }
    }

    var logDirectoryName: String {
        switch self {
        case .talkie: return "Talkie"
        case .talkieLive: return "TalkieAgent"
        case .talkieSync: return "TalkieSync"
        }
    }
}

enum SystemEventType: String, CaseIterable {
    case sync = "SYNC"
    case record = "RECORD"
    case transcribe = "TRANSCRIPTION"
    case workflow = "WORKFLOW"
    case error = "ERROR"
    case system = "SYSTEM"

    var chipLabel: String {
        switch self {
        case .sync: return "SYNC"
        case .record: return "RECORD"
        case .transcribe: return "STT"
        case .workflow: return "WORKFLOW"
        case .error: return "ERROR"
        case .system: return "SYSTEM"
        }
    }

    var color: Color {
        switch self {
        case .sync: return Color(red: 0.4, green: 0.8, blue: 0.4)
        case .record: return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .transcribe: return Color(red: 0.7, green: 0.5, blue: 1.0)
        case .workflow: return Color(red: 1.0, green: 0.7, blue: 0.3)
        case .error: return Color(red: 1.0, green: 0.4, blue: 0.4)
        case .system: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

struct SystemEvent: Identifiable {
    let id: UUID
    let timestamp: Date
    let source: SystemEventSource
    let type: SystemEventType
    let message: String
    let detail: String?

    init(source: SystemEventSource = .talkie, type: SystemEventType, message: String, detail: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.type = type
        self.message = message
        self.detail = detail
    }

    init(id: UUID, timestamp: Date, source: SystemEventSource, type: SystemEventType, message: String, detail: String?) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.type = type
        self.message = message
        self.detail = detail
    }

    /// Serialize to log file format
    func toLogLine() -> String {
        let ts = timestamp.iso8601
        let escapedMessage = message.contains("|") ? message.replacing("|", with: "\\|") : message
        let escapedDetail: String
        if let detail {
            escapedDetail = detail.contains("|") ? detail.replacing("|", with: "\\|") : detail
        } else {
            escapedDetail = ""
        }
        return "\(ts)|\(source.rawValue)|\(type.rawValue)|\(escapedMessage)|\(escapedDetail)"
    }

    /// Parse from log file format
    static func fromLogLine(_ line: String) -> SystemEvent? {
        let parts = line.components(separatedBy: "|")

        // New format: timestamp|source|type|message|detail (5 parts)
        if parts.count >= 4 {
            guard let timestamp = iso8601Formatter.date(from: parts[0]) else { return nil }

            // Check if this is new format (has source field)
            if let source = SystemEventSource(rawValue: parts[1]),
               let type = SystemEventType(rawValue: parts[2]) {
                // New format
                let message = parts[3].replacing("\\|", with: "|")
                let detail = parts.count > 4 && !parts[4].isEmpty
                    ? parts[4].replacing("\\|", with: "|")
                    : nil
                return SystemEvent(id: UUID(), timestamp: timestamp, source: source, type: type, message: message, detail: detail)
            } else if let type = SystemEventType(rawValue: parts[1]) {
                // Old format (backwards compatibility): timestamp|type|message|detail
                let message = parts[2].replacing("\\|", with: "|")
                let detail = parts.count > 3 && !parts[3].isEmpty
                    ? parts[3].replacing("\\|", with: "|")
                    : nil
                return SystemEvent(id: UUID(), timestamp: timestamp, source: .talkie, type: type, message: message, detail: detail)
            }
        }

        return nil
    }
}

// MARK: - Log File Manager

class LogFileManager {
    static let shared = LogFileManager()

    private let fileManager = FileManager.default
    private var currentFileHandle: FileHandle?
    private var currentLogDate: String?
    private let queue = DispatchQueue(label: "to.talkie.app.logfile", qos: .utility)
    private let readChunkSize = 64 * 1024
    private let maxTailReadBytes = 4 * 1024 * 1024

    private var logsDirectory: URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Talkie/logs", isDirectory: true)
        }
        return appSupport.appendingPathComponent("Talkie/logs", isDirectory: true)
    }

    /// Get logs directory for a specific source app
    private func logsDirectory(for source: SystemEventSource) -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Talkie/logs", isDirectory: true)
        }
        return appSupport.appendingPathComponent("\(source.logDirectoryName)/logs", isDirectory: true)
    }

    private init() {
        ensureLogsDirectory()
    }

    private func ensureLogsDirectory() {
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private static let logFileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func logFileName(for date: Date) -> String {
        "talkie-\(Self.logFileDateFormatter.string(from: date)).log"
    }

    private func logFilePath(for date: Date) -> URL {
        logsDirectory.appendingPathComponent(logFileName(for: date))
    }

    /// Append an event to today's log file
    func append(_ event: SystemEvent) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let today = Self.logFileDateFormatter.string(from: Date())

            // Rotate file handle if date changed
            if self.currentLogDate != today {
                self.currentFileHandle?.closeFile()
                self.currentFileHandle = nil
                self.currentLogDate = today
            }

            // Open file handle if needed
            if self.currentFileHandle == nil {
                let path = self.logFilePath(for: Date())
                if !self.fileManager.fileExists(atPath: path.path) {
                    self.fileManager.createFile(atPath: path.path, contents: nil)
                }
                self.currentFileHandle = try? FileHandle(forWritingTo: path)
                self.currentFileHandle?.seekToEndOfFile()
            }

            // Write the event
            let line = event.toLogLine() + "\n"
            if let data = line.data(using: .utf8) {
                self.currentFileHandle?.write(data)
            }
        }
    }

    /// Load events from a log file
    func loadEvents(from date: Date, limit: Int = 500) -> [SystemEvent] {
        loadEventsFromFile(logFilePath(for: date), limit: limit)
    }

    /// Load today's events
    func loadTodayEvents(limit: Int = 500) -> [SystemEvent] {
        loadEvents(from: Date(), limit: limit)
    }

    /// Load events from a specific source's log file
    func loadEventsFrom(source: SystemEventSource, date: Date, limit: Int = 500) -> [SystemEvent] {
        let sourcePath = logsDirectory(for: source).appendingPathComponent(logFileName(for: date))
        return loadEventsFromFile(sourcePath, limit: limit)
    }

    /// Load today's events from all sources or a specific source
    func loadTodayEventsFrom(sources: [SystemEventSource]?, limit: Int = 500) -> [SystemEvent] {
        let sourcesToLoad = sources ?? SystemEventSource.allCases
        var allEvents: [SystemEvent] = []

        for source in sourcesToLoad {
            let sourceEvents = loadEventsFrom(source: source, date: Date(), limit: limit)
            allEvents.append(contentsOf: sourceEvents)
        }

        // Sort by timestamp descending
        allEvents.sort { $0.timestamp > $1.timestamp }

        // Trim to limit
        if allEvents.count > limit {
            allEvents = Array(allEvents.prefix(limit))
        }

        return allEvents
    }

    /// Get list of available log files
    func availableLogFiles() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Get path to logs directory (for opening in Finder)
    func logsDirectoryPath() -> URL {
        logsDirectory
    }

    /// Clean up old log files (keep last N days)
    func cleanupOldLogs(keepDays: Int = 7) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()

        for file in availableLogFiles() {
            // Extract date from filename: talkie-2025-12-01.log
            let name = file.deletingPathExtension().lastPathComponent
            if let dateStr = name.components(separatedBy: "-").dropFirst().joined(separator: "-") as String?,
               let fileDate = Self.logFileDateFormatter.date(from: dateStr),
               fileDate < cutoff {
                try? fileManager.removeItem(at: file)
                fileLogger.info("Cleaned up old log: \(file.lastPathComponent)")
            }
        }
    }

    /// Load only the tail of a log file (most recent lines) to avoid whole-file reads.
    private func loadEventsFromFile(_ path: URL, limit: Int) -> [SystemEvent] {
        guard limit > 0 else { return [] }
        let lines = readLastLines(from: path, limit: limit)
        var events: [SystemEvent] = []
        events.reserveCapacity(min(limit, lines.count))

        for line in lines {
            guard let event = SystemEvent.fromLogLine(line) else { continue }
            events.append(event)
            if events.count >= limit { break }
        }
        return events
    }

    /// Reads recent lines by scanning file chunks backwards from EOF.
    /// Returns lines in newest-first order.
    private func readLastLines(from path: URL, limit: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: path) else { return [] }
        defer { try? handle.close() }

        guard let fileEnd = try? handle.seekToEnd(), fileEnd > 0 else {
            return []
        }

        var offset = fileEnd
        var scannedBytes: UInt64 = 0
        var newlineCount = 0
        var chunks: [Data] = []

        while offset > 0 && newlineCount <= limit && scannedBytes < UInt64(maxTailReadBytes) {
            let readSize = min(UInt64(readChunkSize), offset)
            offset -= readSize

            do {
                try handle.seek(toOffset: offset)
                let chunk = try handle.read(upToCount: Int(readSize)) ?? Data()
                if chunk.isEmpty { break }
                chunks.append(chunk)
                scannedBytes += UInt64(chunk.count)
                newlineCount += chunk.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
            } catch {
                break
            }
        }

        guard !chunks.isEmpty else { return [] }

        var combined = Data(capacity: Int(scannedBytes))
        for chunk in chunks.reversed() {
            combined.append(chunk)
        }

        let text = String(decoding: combined, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // If we stopped before the start of file, drop the first partial line.
        if offset > 0 && !lines.isEmpty {
            lines.removeFirst()
        }

        var recent: [String] = []
        recent.reserveCapacity(min(limit, lines.count))

        for line in lines.reversed() {
            var cleaned = line
            if cleaned.hasSuffix("\r") {
                cleaned.removeLast()
            }
            if cleaned.isEmpty { continue }
            recent.append(cleaned)
            if recent.count >= limit { break }
        }

        return recent
    }
}

// MARK: - Event Manager

@MainActor
@Observable
class SystemEventManager {
    static let shared = SystemEventManager()

    var events: [SystemEvent] = []
    private let maxEventsInMemory = 200
    private let maxMessageLength = 220
    private let maxDetailLength = 900
    private let duplicateEventWindowSeconds: TimeInterval = 0.5
    private let syncNoChangesThrottleSeconds: TimeInterval = 30
    private let throttleSignatureRetentionSeconds: TimeInterval = 300
    private var hasLoadedHistory = false
    @ObservationIgnored private var lastEventSignature: String = ""
    @ObservationIgnored private var lastEventAt: Date = .distantPast
    @ObservationIgnored private var lastThrottledEventBySignature: [String: Date] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        StartupProfiler.shared.mark("singleton.SystemEventManager.start")

        setupObservers()

        // Initial boot event
        logSync(.system, "Console initialized", detail: "Talkie OS v1.0")

        // Defer cleanup to not block startup.
        // Historical log hydration is lazy and only happens when Logs UI is opened.
        Task.detached {
            LogFileManager.shared.cleanupOldLogs(keepDays: 7)
        }
        StartupProfiler.shared.mark("singleton.SystemEventManager.done")
    }

    private func loadHistoricalEvents(from sources: [SystemEventSource]? = nil) {
        let historical = LogFileManager.shared.loadTodayEventsFrom(sources: sources, limit: maxEventsInMemory)
        events = historical.map(compactEvent)
        hasLoadedHistory = true
    }

    /// Lazily hydrate today's log history when the Logs UI is shown.
    func ensureHistoryLoaded(from sources: [SystemEventSource]? = nil) {
        guard !hasLoadedHistory else { return }
        loadHistoricalEvents(from: sources)
    }

    /// Reload events from file (useful after clearing or for refresh)
    func reloadFromFile(from sources: [SystemEventSource]? = nil) {
        loadHistoricalEvents(from: sources)
    }

    func log(_ type: SystemEventType, _ message: String, detail: String? = nil) async {
        let event = SystemEvent(type: type, message: message, detail: detail)
        appendEvent(event)
    }

    /// Non-async version for synchronous contexts
    func logSync(_ type: SystemEventType, _ message: String, detail: String? = nil) {
        let event = SystemEvent(type: type, message: message, detail: detail)
        appendEvent(event)
    }

    private func appendEvent(_ event: SystemEvent) {
        guard !isImmediateDuplicate(event) else { return }
        guard !isThrottled(event) else { return }

        // Add to in-memory list
        events.insert(compactEvent(event), at: 0)

        // Trim in-memory events (file keeps everything)
        if events.count > maxEventsInMemory {
            events = Array(events.prefix(maxEventsInMemory))
        }

        // Persist to file
        LogFileManager.shared.append(event)
    }

    private func isImmediateDuplicate(_ event: SystemEvent) -> Bool {
        let signature = signature(for: event)
        let now = event.timestamp

        defer {
            lastEventSignature = signature
            lastEventAt = now
        }

        return signature == lastEventSignature &&
            now.timeIntervalSince(lastEventAt) < duplicateEventWindowSeconds
    }

    private func isThrottled(_ event: SystemEvent) -> Bool {
        guard let throttleSeconds = throttleWindow(for: event) else { return false }
        let signature = signature(for: event)
        let now = event.timestamp

        defer {
            lastThrottledEventBySignature[signature] = now
            pruneThrottledSignatures(olderThan: now.addingTimeInterval(-throttleSignatureRetentionSeconds))
        }

        guard let last = lastThrottledEventBySignature[signature] else { return false }
        return now.timeIntervalSince(last) < throttleSeconds
    }

    private func throttleWindow(for event: SystemEvent) -> TimeInterval? {
        // Sync completion with no remote changes can fire repeatedly while idle.
        if event.type == .sync, event.message == "Sync completed", event.detail == "No changes" {
            return syncNoChangesThrottleSeconds
        }
        return nil
    }

    private func pruneThrottledSignatures(olderThan cutoff: Date) {
        lastThrottledEventBySignature = lastThrottledEventBySignature.filter { $0.value >= cutoff }
    }

    private func signature(for event: SystemEvent) -> String {
        "\(event.source.rawValue)|\(event.type.rawValue)|\(event.message)|\(event.detail ?? "")"
    }

    private func setupObservers() {
        // Listen for sync started
        NotificationCenter.default.publisher(for: .talkieSyncStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.logSync(.sync, "Sync started", detail: "Fetching changes...")
            }
            .store(in: &cancellables)

        // Listen for sync completed
        NotificationCenter.default.publisher(for: .talkieSyncCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let changes = notification.userInfo?["changes"] as? Int ?? 0
                if changes > 0 {
                    self?.logSync(.sync, "Sync completed", detail: "\(changes) change(s) from iCloud")
                } else {
                    self?.logSync(.sync, "Sync completed", detail: "No changes")
                }
            }
            .store(in: &cancellables)

        // Listen for local saves
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>, !inserted.isEmpty {
                    self?.logSync(.system, "Data saved", detail: "\(inserted.count) object(s)")
                }
            }
            .store(in: &cancellables)
    }

    func clear() {
        events.removeAll()
        logSync(.system, "Console cleared")
    }

    private func compactEvent(_ event: SystemEvent) -> SystemEvent {
        SystemEvent(
            id: event.id,
            timestamp: event.timestamp,
            source: event.source,
            type: event.type,
            message: compact(event.message, max: maxMessageLength),
            detail: event.detail.map { compact($0, max: maxDetailLength) }
        )
    }

    private func compact(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }
}

// MARK: - Console View

struct LogsScreen: View {
    @Environment(SystemEventManager.self) private var eventManager
    @State private var autoScroll = true
    @AppStorage("logs.filterSource") private var filterSourceRaw: String = ""
    @AppStorage("logs.filterType") private var filterTypeRaw: String = ""
    @AppStorage("logs.searchQuery") private var searchQuery = ""
    @State private var selectedEventId: UUID? = nil
    @State private var showCopiedFeedback = false
    @State private var isSearchExpanded = false

    private var filterSource: SystemEventSource? {
        get { filterSourceRaw.isEmpty ? nil : SystemEventSource(rawValue: filterSourceRaw) }
        nonmutating set { filterSourceRaw = newValue?.rawValue ?? "" }
    }

    private var filterType: SystemEventType? {
        get { filterTypeRaw.isEmpty ? nil : SystemEventType(rawValue: filterTypeRaw) }
        nonmutating set { filterTypeRaw = newValue?.rawValue ?? "" }
    }

    /// Optional callback to pop the console into the main window
    var onPopOut: (() -> Void)? = nil

    /// Optional callback to close/navigate away from the console
    var onClose: (() -> Void)? = nil

    private var bgColor: Color { Theme.current.background }
    private var borderColor: Color { Theme.current.divider }
    private let subtleGreen = Color(red: 0.4, green: 0.8, blue: 0.4)

    var filteredEvents: [SystemEvent] {
        var events = eventManager.events

        // Apply source filter
        if let filter = filterSource {
            events = events.filter { $0.source == filter }
        }

        // Apply type filter
        if let filter = filterType {
            events = events.filter { $0.type == filter }
        }

        // Apply search filter
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            events = events.filter {
                $0.message.lowercased().contains(query) ||
                ($0.detail?.lowercased().contains(query) ?? false) ||
                $0.type.rawValue.lowercased().contains(query) ||
                $0.source.rawValue.lowercased().contains(query)
            }
        }

        return events
    }

    var body: some View {
        TalkiePage("Logs", style: .full) {
            VStack(spacing: 0) {
                // Header
                consoleHeader

                // Two-column: services sidebar + log content
                HStack(spacing: 0) {
                    // Left: Services list
                    servicesSidebar

                    // Right: Log console bezel
                    VStack(spacing: 0) {
                        // Type filter & search bar
                        filterBar

                        Divider()
                            .background(borderColor)

                        // Log output
                        consoleOutput

                        // Status bar
                        statusBar
                    }
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .strokeBorder(Theme.current.border, lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, PageLayout.horizontalPadding)
                .padding(.bottom, PageLayout.horizontalPadding)
            }
            .background(bgColor)
        }
    }

    // MARK: - Header

    private var consoleHeader: some View {
        PageHeaderBar {
            Spacer()

            if let onPopOut = onPopOut {
                Button(action: onPopOut) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
                .help("Open in main window")
            }

            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
                .help("Close console")
            }
        }
    }

    // MARK: - Services Sidebar

    private var servicesSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SERVICES")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            // All sources
            serviceRow(nil, label: "All", icon: "square.stack.3d.up")

            ForEach(SystemEventSource.allCases, id: \.self) { source in
                serviceRow(source, label: source.chipLabel, icon: source.icon)
            }

            Spacer()
        }
        .frame(width: 120)
        .padding(.vertical, Spacing.xs)
    }

    private func serviceRow(_ source: SystemEventSource?, label: String, icon: String) -> some View {
        let isSelected = filterSource == source

        return Button {
            filterSource = source
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(source?.color ?? Theme.current.foregroundSecondary)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Spacer()
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Theme.current.surface1 : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Bar (type filters + search)

    private var filterBar: some View {
        HStack(spacing: 8) {
            // Type filters
            HStack(spacing: 4) {
                filterChip(nil, label: "ALL")
                ForEach(SystemEventType.allCases, id: \.self) { type in
                    filterChip(type, label: type.chipLabel)
                }
            }

            Spacer()

            // Search — collapsed icon or expanded field
            if isSearchExpanded || !searchQuery.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundMuted)

                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.current.foreground)
                        .frame(width: 180)

                    Button(action: {
                        searchQuery = ""
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isSearchExpanded = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.current.surface1)
                .cornerRadius(4)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSearchExpanded = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(bgColor)
    }

    private func filterChip(_ type: SystemEventType?, label: String) -> some View {
        let isSelected = filterType == type
        let chipColor = type?.color ?? .white

        return Button(action: { filterType = type }) {
            Text(label)
                .font(Theme.current.fontXSBold)
                .foregroundColor(isSelected ? bgColor : chipColor.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? chipColor : chipColor.opacity(0.1))
                .cornerRadius(2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Console Output

    @State private var isHoveringLogArea = false

    private var consoleOutput: some View {
        LogTextView(
            events: filteredEvents.reversed(),
            autoScroll: autoScroll
        )
        .overlay(alignment: .topTrailing) {
            if isHoveringLogArea && !filteredEvents.isEmpty {
                HStack(spacing: 4) {
                    Button(action: copyAllLogs) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(showCopiedFeedback ? subtleGreen : Theme.current.foreground)
                    }
                    .buttonStyle(.plain)
                    .help("Copy all visible logs")
                }
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding(8)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringLogArea = hovering
            }
        }
        .onAppear {
            eventManager.ensureHistoryLoaded(from: filterSource.map { [$0] })
        }
        .onChange(of: filterSourceRaw) { _, _ in
            if let source = filterSource {
                eventManager.reloadFromFile(from: [source])
            } else {
                eventManager.reloadFromFile(from: nil)
            }
        }
        .background(bgColor)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Log file info
            Button(action: openLogsFolder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text("Open Logs")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(Theme.current.foregroundMuted)
            }
            .buttonStyle(.plain)

            Spacer()

            // Clear logs
            Button(action: { eventManager.clear() }) {
                HStack(spacing: 3) {
                    Image(systemName: "trash")
                        .font(Theme.current.fontXS)
                    Text("CLEAR")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(Theme.current.foregroundMuted)
            }
            .buttonStyle(.plain)

            // Auto-scroll toggle
            Button(action: { autoScroll.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(Theme.current.fontXS)
                    Text("AUTO")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(autoScroll ? subtleGreen : Theme.current.foregroundMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.current.backgroundSecondary)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(borderColor),
            alignment: .top
        )
    }

    // MARK: - Actions

    private func openLogsFolder() {
        let url = LogFileManager.shared.logsDirectoryPath()
        NSWorkspace.shared.open(url)
    }

    private func copyAllLogs() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        let text = filteredEvents.reversed().map { event in
            var line = "[\(formatter.string(from: event.timestamp))] [\(event.source.rawValue)] [\(event.type.rawValue)] \(event.message)"
            if let detail = event.detail {
                line += " — \(detail)"
            }
            return line
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Show feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopiedFeedback = false
            }
        }
    }

    private func copyEvent(_ event: SystemEvent) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var text = "[\(formatter.string(from: event.timestamp))] [\(event.source.rawValue)] [\(event.type.rawValue)] \(event.message)"
        if let detail = event.detail {
            text += "\n  Detail: \(detail)"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Log Text View (NSTextView for multi-row selection)

private struct LogTextView: NSViewRepresentable {
    let events: [SystemEvent]
    let autoScroll: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(Theme.current.background)
        textView.textContainerInset = NSSize(width: 10, height: 4)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }

        // Only rebuild attributed string when events actually change
        let newCount = events.count
        let newLastID = events.last?.id
        if newCount == coordinator.lastEventCount && newLastID == coordinator.lastEventID {
            return
        }
        coordinator.lastEventCount = newCount
        coordinator.lastEventID = newLastID

        textView.backgroundColor = NSColor(Theme.current.background)
        let attributed = buildAttributedString()
        textView.textStorage?.setAttributedString(attributed)

        if autoScroll {
            DispatchQueue.main.async {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var lastEventCount = 0
        var lastEventID: UUID?
    }

    private func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .light)
        let monoSmall = NSFont.monospacedSystemFont(ofSize: 9, weight: .light)
        let monoBold = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let mutedColor = NSColor(Theme.current.foregroundMuted)
        let fgColor = NSColor(Theme.current.foreground)
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 4

        for event in events {
            // Timestamp
            let time = Self.timeFormatter.string(from: event.timestamp)
            result.append(NSAttributedString(string: time + "  ", attributes: [
                .font: monoSmall,
                .foregroundColor: mutedColor,
                .paragraphStyle: pStyle,
            ]))

            // Source
            result.append(NSAttributedString(string: event.source.rawValue, attributes: [
                .font: monoSmall,
                .foregroundColor: NSColor(event.source.color),
                .paragraphStyle: pStyle,
            ]))
            result.append(NSAttributedString(string: "  ", attributes: [.font: monoSmall]))

            // Type badge
            let typeStr = event.type.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
            result.append(NSAttributedString(string: typeStr, attributes: [
                .font: monoBold,
                .foregroundColor: NSColor(event.type.color),
                .paragraphStyle: pStyle,
            ]))

            // Message
            result.append(NSAttributedString(string: event.message, attributes: [
                .font: mono,
                .foregroundColor: fgColor,
                .paragraphStyle: pStyle,
            ]))

            // Detail (inline, dimmed)
            if let detail = event.detail {
                result.append(NSAttributedString(string: " — " + detail, attributes: [
                    .font: monoSmall,
                    .foregroundColor: mutedColor,
                    .paragraphStyle: pStyle,
                ]))
            }

            result.append(NSAttributedString(string: "\n", attributes: [.font: mono]))
        }

        return result
    }
}

// MARK: - Console Event Row (legacy, kept for reference)

struct ConsoleEventRow: View {
    let event: SystemEvent
    var onCopy: ((SystemEvent) -> Void)? = nil

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var showCopied = false

    private var bgColor: Color { Theme.current.background }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(alignment: .top, spacing: 6) {
                // Timestamp (compact)
                Text(formatTime(event.timestamp))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .frame(width: 52, alignment: .leading)

                // Source indicator (icon)
                Image(systemName: event.source.icon)
                    .font(.system(size: 8))
                    .foregroundColor(event.source.color)
                    .frame(width: 14, alignment: .center)
                    .help(event.source.rawValue)

                // Type badge (compact)
                Text(event.type.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(event.type.color)
                    .frame(width: 60, alignment: .leading)

                // Message (takes remaining space)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.message)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(isExpanded ? nil : 2)
                        .textSelection(.enabled)

                    if let detail = event.detail, !isExpanded {
                        Text(detail)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)

                // Expand/copy controls on hover
                if isHovering {
                    HStack(spacing: 4) {
                        if event.detail != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }
                            .buttonStyle(.plain)
                            .help(isExpanded ? "Collapse detail" : "Expand detail")
                        }

                        Button(action: copyToClipboard) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundColor(showCopied ? Color(red: 0.4, green: 0.8, blue: 0.4) : Theme.current.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)

            // Expanded detail view
            if isExpanded, let detail = event.detail {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .background(Theme.current.divider)
                    Text("Detail:")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.current.foreground)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .padding(.leading, 52 + 14 + 60 + 18) // Align with message
            }
        }
        .background(isHovering || isExpanded ? Theme.current.backgroundSecondary : Color.clear)
        .onHover { hovering in isHovering = hovering }
        .contextMenu {
            Button("Copy Log Entry") {
                copyToClipboard()
            }
            if event.detail != nil {
                Button(isExpanded ? "Collapse Detail" : "Expand Detail") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            }
        }
    }

    private func copyToClipboard() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var text = "[\(formatter.string(from: event.timestamp))] [\(event.source.rawValue)] [\(event.type.rawValue)] \(event.message)"
        if let detail = event.detail {
            text += "\n  Detail: \(detail)"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Show feedback
        withAnimation(.easeInOut(duration: 0.15)) {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopied = false
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    LogsScreen()
        .frame(width: 600, height: 400)
}

// MARK: - Backwards Compatibility Alias
typealias SystemLogsView = LogsScreen
