//
//  ConsoleView.swift
//  TalkieKit
//
//  Reusable console view component with filtering, search, and color-coded logs
//

import SwiftUI

// MARK: - Console View

/// A reusable console view for displaying logs with filtering and search
public struct ConsoleView: View {
    /// The log entries to display
    @Binding public var entries: [ConsoleEntry]

    /// Available categories for filtering (extracted from entries if nil)
    public var categories: [String]?

    /// Theme configuration
    public var theme: ConsoleTheme

    /// Title shown in header
    public var title: String

    /// Version string shown in header
    public var version: String?

    /// Whether to show the live indicator
    public var showLiveIndicator: Bool

    /// Callback when clear is pressed
    public var onClear: (() -> Void)?

    /// Callback when pop-out is pressed
    public var onPopOut: (() -> Void)?

    /// Callback when close is pressed
    public var onClose: (() -> Void)?

    /// Callback to open logs folder
    public var onOpenLogs: (() -> Void)?

    // State
    @State private var autoScroll = true
    @State private var filterLevel: ConsoleLogLevel? = nil
    @State private var filterCategory: String? = nil
    @State private var searchQuery = ""

    public init(
        entries: Binding<[ConsoleEntry]>,
        categories: [String]? = nil,
        theme: ConsoleTheme = .dark,
        title: String = "CONSOLE",
        version: String? = nil,
        showLiveIndicator: Bool = true,
        onClear: (() -> Void)? = nil,
        onPopOut: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onOpenLogs: (() -> Void)? = nil
    ) {
        self._entries = entries
        self.categories = categories
        self.theme = theme
        self.title = title
        self.version = version
        self.showLiveIndicator = showLiveIndicator
        self.onClear = onClear
        self.onPopOut = onPopOut
        self.onClose = onClose
        self.onOpenLogs = onOpenLogs
    }

    private var filteredEntries: [ConsoleEntry] {
        var result = entries

        // Apply level filter
        if let level = filterLevel {
            result = result.filter { $0.level == level }
        }

        // Apply category filter
        if let category = filterCategory {
            result = result.filter { $0.category == category }
        }

        // Apply search filter
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter {
                $0.message.lowercased().contains(query) ||
                ($0.detail?.lowercased().contains(query) ?? false) ||
                $0.category.lowercased().contains(query)
            }
        }

        return result
    }

    private var availableCategories: [String] {
        if let categories = categories {
            return categories
        }
        return Array(Set(entries.map { $0.category })).sorted()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            consoleHeader

            // Filter bar
            filterBar

            Divider()
                .background(theme.divider)

            // Log output
            consoleOutput

            // Status bar
            statusBar
        }
        .background(theme.background)
    }

    // MARK: - Header

    private var consoleHeader: some View {
        HStack(spacing: 8) {
            // Terminal icon
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundColor(theme.accentColor.opacity(0.7))

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(theme.foreground)

            if let version = version {
                Text(version)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.foregroundMuted)
            }

            Spacer()

            // Live indicator
            if showLiveIndicator {
                HStack(spacing: 4) {
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: theme.accentColor.opacity(0.5), radius: 3)

                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accentColor.opacity(0.8))
                }
            }

            // Clear button
            if let onClear = onClear {
                ConsoleButton(label: "CLEAR", theme: theme, action: onClear)
            }

            // Pop-out button
            if let onPopOut = onPopOut {
                ConsoleIconButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    theme: theme,
                    action: onPopOut
                )
                .help("Open in window")
            }

            // Close button
            if let onClose = onClose {
                ConsoleIconButton(
                    icon: "xmark",
                    theme: theme,
                    action: onClose
                )
                .help("Close console")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.backgroundSecondary)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            // Level filter chips
            levelFilterChip(nil, label: "ALL")
            ForEach(ConsoleLogLevel.allCases, id: \.self) { level in
                levelFilterChip(level, label: level.rawValue)
            }

            Spacer()

            // Category picker (if multiple categories)
            if availableCategories.count > 1 {
                Picker("", selection: $filterCategory) {
                    Text("All").tag(nil as String?)
                    ForEach(availableCategories, id: \.self) { category in
                        Text(category).tag(category as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(theme.foregroundMuted)

                TextField("Search...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.foreground)
                    .frame(width: 120)

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(theme.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.surface)
            .cornerRadius(4)

            Text("\(filteredEntries.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.foregroundMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.background)
    }

    private func levelFilterChip(_ level: ConsoleLogLevel?, label: String) -> some View {
        let isSelected = filterLevel == level
        let chipColor = level?.color ?? .white

        return Button(action: { filterLevel = level }) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? theme.background : chipColor.opacity(0.6))
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
                    ForEach(filteredEntries.reversed()) { entry in
                        ConsoleEntryRow(entry: entry, theme: theme)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: entries.count) {
                if autoScroll, let newest = filteredEntries.first {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newest.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if autoScroll, let newest = filteredEntries.first {
                    proxy.scrollTo(newest.id, anchor: .bottom)
                }
            }
        }
        .background(theme.background)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Open logs folder
            if let onOpenLogs = onOpenLogs {
                Button(action: onOpenLogs) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text("Open Logs")
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundColor(theme.foregroundMuted)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Entry count
            Text("\(entries.count) entries")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.foregroundMuted)

            // Auto-scroll toggle
            Button(action: { autoScroll.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 10))
                    Text("AUTO")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(autoScroll ? theme.accentColor : theme.foregroundMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.backgroundSecondary)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(theme.divider),
            alignment: .top
        )
    }
}

// MARK: - Console Entry Row

struct ConsoleEntryRow: View {
    let entry: ConsoleEntry
    let theme: ConsoleTheme

    @State private var isHovering = false
    @State private var isCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text(formatTime(entry.timestamp))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(theme.foregroundMuted)
                .frame(width: 55, alignment: .leading)

            // Level badge
            Text(entry.level.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(entry.level.color)
                .frame(width: 45, alignment: .leading)

            // Category
            Text(entry.category)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(theme.foregroundMuted)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)

            // Message
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(theme.foreground)
                    .lineLimit(2)
                    .textSelection(.enabled)

                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.foregroundMuted)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)

            // Copy button on hover
            if isHovering {
                Button(action: copyEntry) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(isCopied ? theme.accentColor : theme.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(isHovering ? theme.backgroundSecondary : Color.clear)
        .onHover { hovering in
            isHovering = hovering
            if !hovering { isCopied = false }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func copyEntry() {
        var text = "[\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        if let detail = entry.detail {
            text += " - \(detail)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isCopied = true
    }
}

// MARK: - Console Buttons

struct ConsoleButton: View {
    let label: String
    let theme: ConsoleTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.foregroundMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.surface)
                .cornerRadius(2)
        }
        .buttonStyle(.plain)
    }
}

struct ConsoleIconButton: View {
    let icon: String
    let theme: ConsoleTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(theme.foregroundMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.surface)
                .cornerRadius(2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State var entries: [ConsoleEntry] = [
            ConsoleEntry(level: .info, category: "Engine", message: "TalkieEngine started", detail: "PID: 12345"),
            ConsoleEntry(level: .debug, category: "XPC", message: "Connection established"),
            ConsoleEntry(level: .info, category: "Whisper", message: "Loading model: whisper-small"),
            ConsoleEntry(level: .warning, category: "Memory", message: "High memory usage detected", detail: "2.1 GB"),
            ConsoleEntry(level: .error, category: "Transcription", message: "Failed to transcribe audio", detail: "Model not loaded"),
            ConsoleEntry(level: .info, category: "Engine", message: "Transcription completed", detail: "Duration: 3.2s"),
        ]

        var body: some View {
            ConsoleView(
                entries: $entries,
                title: "ENGINE CONSOLE",
                version: "v1.0",
                onClear: { entries.removeAll() },
                onOpenLogs: { }
            )
        }
    }

    return PreviewWrapper()
        .frame(width: 700, height: 400)
}
