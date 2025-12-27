//
//  LogViewer.swift
//  TalkieLive
//
//  Unified logging: writes to os.log + in-memory + file for cross-app viewing
//  Logs visible in Talkie's SystemLogsView
//

import SwiftUI
import OSLog
import TalkieKit

// MARK: - Log Entry

struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: OSLogEntryLog.Level
    let category: String
    let message: String
    let detail: String?

    init(id: UUID = UUID(), timestamp: Date, level: OSLogEntryLog.Level, category: String, message: String, detail: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.detail = detail
    }

    var eventType: EventType {
        EventType(rawValue: category) ?? .system
    }
}

// MARK: - App Logger (Unified logging - os.log + in-memory)

@MainActor
final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 500
    private let subsystem = "jdi.talkie.live"

    private var loggers: [String: Logger] = [:]

    /// File writer for cross-app log viewing in Talkie
    private let fileWriter = TalkieLogFileWriter(source: .talkieLive)

    private init() {}

    private func logger(for category: String) -> Logger {
        if let existing = loggers[category] {
            return existing
        }
        let new = Logger(subsystem: subsystem, category: category)
        loggers[category] = new
        return new
    }

    /// Log a message - logs to console, in-memory, AND file for cross-app viewing
    /// Warnings and errors use critical mode (immediate flush) with file:line context
    func log(_ category: EventType, _ message: String, detail: String? = nil, level: OSLogEntryLog.Level = .info, file: String = #file, line: Int = #line) {
        let fullMessage = detail != nil ? "\(message): \(detail!)" : message

        // Log to console (visible in Xcode debugger and Console.app)
        let timestamp = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(2)))
        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let levelStr = switch level {
        case .debug: "[DEBUG]"
        case .info: "[INFO]"
        case .notice: "[NOTICE]"
        case .error: "[ERROR]"
        case .fault: "[FAULT]"
        default: "[LOG]"
        }
        let logLine = "[\(timestamp)] \(levelStr) [\(category.rawValue)] \(fullMessage) ← \(filename):\(line)"
        NSLog("%@", logLine)

        // Write to file for cross-app viewing in Talkie
        // Warnings and errors use critical mode (immediate flush) with file:line context
        let logType = mapEventType(category)
        let isCritical = level == .notice || level == .error || level == .fault
        let writeMode: LogWriteMode = isCritical ? .critical : .bestEffort

        // Add file:line context to warnings and errors for debugging
        let fileDetail: String?
        if isCritical {
            let baseDetail = detail ?? ""
            fileDetail = baseDetail.isEmpty ? "[\(filename):\(line)]" : "\(baseDetail) [\(filename):\(line)]"
        } else {
            fileDetail = detail
        }

        fileWriter.log(logType, message, detail: fileDetail, mode: writeMode)

        // Keep in-memory copy (newest first)
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category.rawValue,
            message: message,
            detail: detail
        )
        entries.insert(entry, at: 0)

        // Trim if needed
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    /// Map local EventType to TalkieKit's LogEventType
    private func mapEventType(_ type: EventType) -> LogEventType {
        switch type {
        case .system: return .system
        case .audio: return .record
        case .transcription: return .transcribe
        case .database: return .system
        case .file: return .system
        case .error: return .error
        case .ui: return .system
        case .performance: return .system  // Performance logs use system category
        }
    }

    func clear() {
        entries.removeAll()
    }
}

// MARK: - Log Viewer Console View

struct LogViewerConsole: View {
    @ObservedObject private var logger = AppLogger.shared
    @State private var filterType: EventType? = nil
    @State private var searchText = ""
    @State private var selection: Set<UUID> = []
    @State private var showSearch = false

    private var filteredEntries: [LogEntry] {
        var result = logger.entries

        if let type = filterType {
            result = result.filter { $0.category == type.rawValue }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                ($0.detail?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack(alignment: .topTrailing) {
                logList
                copyOverlay
            }
            Divider()
            statusBar
        }
        .background(TalkieTheme.surface)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSearch.toggle()
                        if !showSearch { searchText = "" }
                    }
                    return nil
                }
                return event
            }
        }
    }

    // MARK: - Copy Overlay

    private var copyOverlay: some View {
        Group {
            if !selection.isEmpty {
                Button(action: copySelected) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy \(selection.count)")
                            .font(.labelSmall)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
                .padding(Spacing.sm)
            }
        }
    }

    private func copySelected() {
        let text = selectedEntries.map { formatEntry($0) }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            // Filter pills row with inline search
            HStack(spacing: 6) {
                filterPill(nil, "All", color: TalkieTheme.textSecondary)
                filterPill(.error, "Errors", color: EventType.error.color)
                filterPill(.system, "System", color: EventType.system.color)
                filterPill(.transcription, "Trans", color: EventType.transcription.color)
                filterPill(.audio, "Audio", color: EventType.audio.color)
                filterPill(.database, "DB", color: EventType.database.color)
                filterPill(.file, "File", color: EventType.file.color)
                filterPill(.ui, "UI", color: EventType.ui.color)

                Spacer()

                // Entry count badge
                Text("\(filteredEntries.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(TalkieTheme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TalkieTheme.surfaceCard)
                    .cornerRadius(CornerRadius.xs)

                // Inline search
                inlineSearch
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(TalkieTheme.surfaceElevated)
    }

    private var inlineSearch: some View {
        HStack(spacing: 6) {
            if showSearch {
                HStack(spacing: 4) {
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.monoSmall)
                        .frame(width: 120)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(TalkieTheme.surfaceCard)
                .cornerRadius(CornerRadius.sm)
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSearch.toggle()
                    if !showSearch { searchText = "" }
                }
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(showSearch ? TalkieTheme.accent : TalkieTheme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Search (⌘F)")
        }
    }

    private func filterPill(_ type: EventType?, _ label: String, color: Color) -> some View {
        let isSelected = filterType == type
        return Button(action: { filterType = type }) {
            Text(label)
                .font(.monoXSmall)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isSelected ? color.opacity(0.25) : color.opacity(0.08))
                )
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log List

    private var logList: some View {
        Table(filteredEntries, selection: $selection) {
            TableColumn("Time") { entry in
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.monoXSmall)
                    .foregroundColor(TalkieTheme.textMuted)
            }
            .width(65)

            TableColumn("Type") { entry in
                HStack(spacing: 3) {
                    Image(systemName: entry.eventType.icon)
                        .font(.system(size: 8))
                    Text(entry.category)
                        .font(.monoXSmall)
                }
                .foregroundColor(entry.eventType.color)
            }
            .width(90)

            TableColumn("Message") { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.message)
                        .font(.monoSmall)
                        .foregroundColor(TalkieTheme.textPrimary)
                    if let detail = entry.detail {
                        Text(detail)
                            .font(.monoXSmall)
                            .foregroundColor(TalkieTheme.textMuted)
                    }
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .copyable(selectedEntries.map { formatEntry($0) })
    }

    private var selectedEntries: [LogEntry] {
        filteredEntries.filter { selection.contains($0.id) }
    }

    private func formatEntry(_ entry: LogEntry) -> String {
        let time = Self.timeFormatter.string(from: entry.timestamp)
        let detail = entry.detail.map { " — \($0)" } ?? ""
        return "[\(time)] [\(entry.category)] \(entry.message)\(detail)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: Spacing.md) {
            // Error count indicator
            let errorCount = logger.entries.filter { $0.level == .error || $0.level == .fault }.count
            if errorCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(SemanticColor.error)
                        .frame(width: 5, height: 5)
                    Text("\(errorCount)")
                        .font(.monoXSmall)
                        .foregroundColor(SemanticColor.error.opacity(0.8))
                }
            }

            Spacer()

            // Full History button
            Button(action: openConsoleApp) {
                HStack(spacing: 4) {
                    Image(nsImage: consoleAppIcon)
                        .resizable()
                        .frame(width: 12, height: 12)
                    Text("Full History")
                        .font(.monoXSmall)
                }
                .foregroundColor(TalkieTheme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Open Console.app for persistent log history")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(TalkieTheme.surfaceElevated)
    }

    // MARK: - Console.app

    private var consoleAppIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) ?? NSImage()
    }

    private func openConsoleApp() {
        // Open Console.app with predicate for our subsystem
        let script = """
        tell application "Console"
            activate
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }

        // Also copy the filter predicate to clipboard for easy use
        let predicate = "subsystem == \"jdi.talkie.live\""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(predicate, forType: .string)
    }
}

