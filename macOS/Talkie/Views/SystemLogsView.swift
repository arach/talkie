//
//  SystemLogsView.swift
//  Talkie macOS
//
//  Live activity logs viewer with tactical dark theme
//  Events persist to log files and logs viewer reads from them
//

import SwiftUI
import Combine
import os

private let fileLogger = Logger(subsystem: "jdi.talkie.core", category: "LogFile")

// MARK: - System Event Model

enum SystemEventSource: String, CaseIterable {
    case talkie = "Talkie"
    case talkieLive = "TalkieLive"
    case talkieEngine = "Engine"
    case bridge = "Bridge"

    var color: Color {
        switch self {
        case .talkie: return Color(red: 0.4, green: 0.7, blue: 1.0) // Blue
        case .talkieLive: return Color(red: 0.7, green: 0.5, blue: 1.0) // Purple
        case .talkieEngine: return Color(red: 1.0, green: 0.6, blue: 0.3) // Orange
        case .bridge: return Color(red: 0.3, green: 0.8, blue: 0.7) // Teal
        }
    }

    var icon: String {
        switch self {
        case .talkie: return "app.fill"
        case .talkieLive: return "menubar.rectangle"
        case .talkieEngine: return "gearshape.fill"
        case .bridge: return "network"
        }
    }
}

enum SystemEventType: String, CaseIterable {
    case sync = "SYNC"
    case record = "RECORD"
    case transcribe = "WHISPER"
    case workflow = "WORKFLOW"
    case error = "ERROR"
    case system = "SYSTEM"

    var color: Color {
        switch self {
        case .sync: return Color(red: 0.4, green: 0.8, blue: 0.4) // Soft green
        case .record: return Color(red: 0.4, green: 0.6, blue: 1.0) // Soft blue
        case .transcribe: return Color(red: 0.7, green: 0.5, blue: 1.0) // Soft purple
        case .workflow: return Color(red: 1.0, green: 0.7, blue: 0.3) // Amber
        case .error: return Color(red: 1.0, green: 0.4, blue: 0.4) // Soft red
        case .system: return Color(red: 0.5, green: 0.5, blue: 0.5) // Gray
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
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = isoFormatter.string(from: timestamp)
        let escapedMessage = message.replacingOccurrences(of: "|", with: "\\|")
        let escapedDetail = detail?.replacingOccurrences(of: "|", with: "\\|") ?? ""
        return "\(ts)|\(source.rawValue)|\(type.rawValue)|\(escapedMessage)|\(escapedDetail)"
    }

    /// Parse from log file format
    static func fromLogLine(_ line: String) -> SystemEvent? {
        let parts = line.components(separatedBy: "|")

        // New format: timestamp|source|type|message|detail (5 parts)
        if parts.count >= 4 {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            guard let timestamp = isoFormatter.date(from: parts[0]) else { return nil }

            // Check if this is new format (has source field)
            if let source = SystemEventSource(rawValue: parts[1]),
               let type = SystemEventType(rawValue: parts[2]) {
                // New format
                let message = parts[3].replacingOccurrences(of: "\\|", with: "|")
                let detail = parts.count > 4 && !parts[4].isEmpty
                    ? parts[4].replacingOccurrences(of: "\\|", with: "|")
                    : nil
                return SystemEvent(id: UUID(), timestamp: timestamp, source: source, type: type, message: message, detail: detail)
            } else if let type = SystemEventType(rawValue: parts[1]) {
                // Old format (backwards compatibility): timestamp|type|message|detail
                let message = parts[2].replacingOccurrences(of: "\\|", with: "|")
                let detail = parts.count > 3 && !parts[3].isEmpty
                    ? parts[3].replacingOccurrences(of: "\\|", with: "|")
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
    private let queue = DispatchQueue(label: "jdi.talkie.logfile", qos: .utility)

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

        switch source {
        case .talkie:
            return appSupport.appendingPathComponent("Talkie/logs", isDirectory: true)
        case .talkieLive:
            return appSupport.appendingPathComponent("TalkieLive/logs", isDirectory: true)
        case .talkieEngine:
            return appSupport.appendingPathComponent("TalkieEngine/logs", isDirectory: true)
        case .bridge:
            // Bridge logs are stored in Talkie/Bridge/ (not a logs subdirectory)
            return appSupport.appendingPathComponent("Talkie/Bridge", isDirectory: true)
        }
    }

    private init() {
        ensureLogsDirectory()
    }

    private func ensureLogsDirectory() {
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private func logFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "talkie-\(formatter.string(from: date)).log"
    }

    private func logFilePath(for date: Date) -> URL {
        logsDirectory.appendingPathComponent(logFileName(for: date))
    }

    /// Append an event to today's log file
    func append(_ event: SystemEvent) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let today = dateFormatter.string(from: Date())

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
        let path = logFilePath(for: date)
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var events: [SystemEvent] = []

        // Read from end to get most recent first, up to limit
        for line in lines.reversed() {
            guard !line.isEmpty, let event = SystemEvent.fromLogLine(line) else { continue }
            events.append(event)
            if events.count >= limit { break }
        }

        return events
    }

    /// Load today's events
    func loadTodayEvents(limit: Int = 500) -> [SystemEvent] {
        loadEvents(from: Date(), limit: limit)
    }

    /// Load events from a specific source's log file
    func loadEventsFrom(source: SystemEventSource, date: Date, limit: Int = 500) -> [SystemEvent] {
        // Bridge uses a different log format and filename
        if source == .bridge {
            return loadBridgeEvents(limit: limit)
        }

        let sourcePath = logsDirectory(for: source).appendingPathComponent(logFileName(for: date))
        guard let content = try? String(contentsOf: sourcePath, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var events: [SystemEvent] = []

        // Read from end to get most recent first, up to limit
        for line in lines.reversed() {
            guard !line.isEmpty, let event = SystemEvent.fromLogLine(line) else { continue }
            events.append(event)
            if events.count >= limit { break }
        }

        return events
    }

    /// Load events from Bridge's bridge.log (different format)
    private func loadBridgeEvents(limit: Int = 500) -> [SystemEvent] {
        let logFile = logsDirectory(for: .bridge).appendingPathComponent("bridge.log")
        guard let content = try? String(contentsOf: logFile, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var events: [SystemEvent] = []

        // Bridge log format: [ISO_TIMESTAMP] [LEVEL] message
        // e.g., [2024-01-08T10:30:00.000Z] [INFO] Labs sessions: 5
        let pattern = #"\[([^\]]+)\] \[([^\]]+)\] (.+)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for line in lines.reversed() {
            guard !line.isEmpty else { continue }

            if let regex = regex,
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               match.numberOfRanges >= 4 {
                let timestampStr = String(line[Range(match.range(at: 1), in: line)!])
                let level = String(line[Range(match.range(at: 2), in: line)!])
                let message = String(line[Range(match.range(at: 3), in: line)!])

                // Parse ISO timestamp
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let timestamp = isoFormatter.date(from: timestampStr) ?? Date()

                // Map Bridge log levels to SystemEventType
                let eventType: SystemEventType = switch level {
                case "ERROR": .error
                case "WARN": .error
                case "DEBUG": .system
                case "REQ": .sync
                default: .system
                }

                let event = SystemEvent(
                    id: UUID(),
                    timestamp: timestamp,
                    source: .bridge,
                    type: eventType,
                    message: message,
                    detail: nil
                )
                events.append(event)
                if events.count >= limit { break }
            }
        }

        return events
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for file in availableLogFiles() {
            // Extract date from filename: talkie-2025-12-01.log
            let name = file.deletingPathExtension().lastPathComponent
            if let dateStr = name.components(separatedBy: "-").dropFirst().joined(separator: "-") as String?,
               let fileDate = formatter.date(from: dateStr),
               fileDate < cutoff {
                try? fileManager.removeItem(at: file)
                fileLogger.info("Cleaned up old log: \(file.lastPathComponent)")
            }
        }
    }
}

// MARK: - Event Manager

@MainActor
@Observable
class SystemEventManager {
    static let shared = SystemEventManager()

    var events: [SystemEvent] = []
    private let maxEventsInMemory = 500

    private var cancellables = Set<AnyCancellable>()

    private init() {
        StartupProfiler.shared.mark("singleton.SystemEventManager.start")

        setupObservers()

        // Initial boot event
        logSync(.system, "Console initialized", detail: "Talkie OS v1.0")

        // Defer log loading and cleanup to not block startup
        Task.detached { [weak self] in
            LogFileManager.shared.cleanupOldLogs(keepDays: 7)

            // Load historical events after startup
            let historical = LogFileManager.shared.loadTodayEventsFrom(sources: nil, limit: 500)
            await MainActor.run {
                self?.events.append(contentsOf: historical)
            }
        }
        StartupProfiler.shared.mark("singleton.SystemEventManager.done")
    }

    private func loadHistoricalEvents(from sources: [SystemEventSource]? = nil) {
        let historical = LogFileManager.shared.loadTodayEventsFrom(sources: sources, limit: maxEventsInMemory)
        events = historical
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
        // Add to in-memory list
        events.insert(event, at: 0)

        // Trim in-memory events (file keeps everything)
        if events.count > maxEventsInMemory {
            events = Array(events.prefix(maxEventsInMemory))
        }

        // Persist to file
        LogFileManager.shared.append(event)
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
}

// MARK: - Console View

struct SystemLogsView: View {
    @Environment(SystemEventManager.self) private var eventManager
    @State private var autoScroll = true
    @State private var filterSource: SystemEventSource? = nil
    @State private var filterType: SystemEventType? = nil
    @State private var searchQuery = ""
    @State private var selectedEventId: UUID? = nil
    @State private var showCopiedFeedback = false

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
        VStack(spacing: 0) {
            // Header
            consoleHeader

            // Filter & search bar
            filterBar

            Divider()
                .background(borderColor)

            // Log output
            consoleOutput

            // Status bar
            statusBar
        }
        .background(bgColor)
    }

    // MARK: - Header

    private var consoleHeader: some View {
        HStack(spacing: 8) {
            // Terminal icon
            Image(systemName: "terminal")
                .font(Theme.current.fontXS)
                .foregroundColor(subtleGreen.opacity(0.7))

            Text("SYSTEM LOGS")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            // Live indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(subtleGreen)
                    .frame(width: 5, height: 5)
                    .shadow(color: subtleGreen.opacity(0.5), radius: 3)

                Text("LIVE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(subtleGreen.opacity(0.8))
            }

            // Copy All button
            Button(action: copyAllLogs) {
                HStack(spacing: 3) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    Text(showCopiedFeedback ? "COPIED" : "COPY ALL")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(showCopiedFeedback ? subtleGreen : Theme.current.foregroundMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.current.surface1)
                .cornerRadius(2)
            }
            .buttonStyle(.plain)
            .help("Copy all visible logs to clipboard (⌘C)")

            // Clear button
            Button(action: { eventManager.clear() }) {
                Text("CLEAR")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.current.surface1)
                    .cornerRadius(2)
            }
            .buttonStyle(.plain)

            // Pop-out button (only shown when in popover mode)
            if let onPopOut = onPopOut {
                Button(action: onPopOut) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.current.surface1)
                        .cornerRadius(2)
                }
                .buttonStyle(.plain)
                .help("Open in main window")
            }

            // Close button (only shown when in main window mode)
            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.current.surface1)
                        .cornerRadius(2)
                }
                .buttonStyle(.plain)
                .help("Close console")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.current.backgroundSecondary)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Top row: Source selection (visually distinct - larger, segmented style)
            HStack(spacing: 4) {
                sourceFilterChip(nil, label: "ALL LOGS")
                sourceFilterChip(.talkie, label: "TALKIE")
                sourceFilterChip(.talkieLive, label: "LIVE")
                sourceFilterChip(.talkieEngine, label: "ENGINE")
                sourceFilterChip(.bridge, label: "BRIDGE")

                Spacer()

                // Event count
                Text("\(filteredEvents.count)")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Bottom row: Type filters + search
            HStack(spacing: 6) {
                Text("FILTER")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundMuted.opacity(0.6))

                filterChip(nil, label: "ALL")
                filterChip(.sync, label: "SYNC")
                filterChip(.record, label: "RECORD")
                filterChip(.transcribe, label: "WHISPER")
                filterChip(.workflow, label: "WORKFLOW")
                filterChip(.error, label: "ERROR")

                Spacer()

                // Search field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundMuted)

                    TextField("Search...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.current.foreground)
                        .frame(width: 120)

                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.xs)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(bgColor)
    }

    private func sourceFilterChip(_ source: SystemEventSource?, label: String) -> some View {
        let isSelected = filterSource == source
        let chipColor = source?.color ?? .white

        return Button(action: { filterSource = source }) {
            HStack(spacing: 4) {
                if let source = source {
                    Image(systemName: source.icon)
                        .font(.system(size: 9, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.3)
            }
            .foregroundColor(isSelected ? .white : chipColor.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isSelected ? chipColor.opacity(0.85) : chipColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .stroke(isSelected ? chipColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
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

    private var consoleOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEvents.reversed()) { event in
                        ConsoleEventRow(event: event)
                            .id(event.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: eventManager.events.count) {
                // filteredEvents is newest-first, reversed() makes it oldest-first for display
                // So the newest event (first in array) appears at bottom after reverse
                if autoScroll, let newestEvent = filteredEvents.first {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newestEvent.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // Scroll to bottom on appear (tail mode)
                if autoScroll, let newestEvent = filteredEvents.first {
                    proxy.scrollTo(newestEvent.id, anchor: .bottom)
                }
            }
            .onChange(of: filterSource) { _, newSource in
                // Reload events from log files when source filter changes
                if let source = newSource {
                    // Load only this source's logs
                    eventManager.reloadFromFile(from: [source])
                } else {
                    // Load all sources
                    eventManager.reloadFromFile(from: nil)
                }
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

// MARK: - Console Event Row

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

                    if let detail = event.detail, !isExpanded {
                        Text(detail)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Copy button on hover
                if isHovering {
                    Button(action: copyToClipboard) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(showCopied ? Color(red: 0.4, green: 0.8, blue: 0.4) : Theme.current.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
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
        .onTapGesture {
            if event.detail != nil {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
        }
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
    SystemLogsView()
        .frame(width: 600, height: 400)
}
