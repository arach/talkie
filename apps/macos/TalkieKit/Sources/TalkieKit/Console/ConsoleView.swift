//
//  ConsoleView.swift
//  TalkieKit
//
//  Reusable console view component with filtering, search, and color-coded logs
//

import SwiftUI
import TalkieCore

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
    @State private var copiedAll = false

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

    /// Copy every currently-visible (filtered) line to the pasteboard.
    private func copyAll() {
        let text = filteredEntries.map(Self.formatLine).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copiedAll = false
        }
    }

    private static func formatLine(_ entry: ConsoleEntry) -> String {
        let time = TalkieDate.consoleTime(entry.timestamp)
        let detail = entry.detail.map { " — \($0)" } ?? ""
        return "[\(time)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)" + detail
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

            if let onOpenLogs = onOpenLogs {
                Button(action: onOpenLogs) {
                    HStack(spacing: 4) {
                        Text("Open Logs")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(theme.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.accentColor.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Open logs")
            }

            // Copy-all button — grabs every visible (filtered) line at once.
            if !filteredEntries.isEmpty {
                ConsoleIconButton(
                    icon: copiedAll ? "checkmark" : "doc.on.doc",
                    theme: theme,
                    action: copyAll
                )
                .help("Copy all visible logs")
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
        VStack(spacing: 6) {
            // Row 1 — level filter chips + search + count
            HStack(spacing: 6) {
                levelFilterChip(nil, label: "ALL")
                ForEach(ConsoleLogLevel.allCases, id: \.self) { level in
                    levelFilterChip(level, label: level.rawValue)
                }

                Spacer()

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

            // Row 2 — subsystem/category navigation as scannable chips (was a
            // menu dropdown). Scrolls horizontally when categories overflow.
            if availableCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        categoryChip(nil, label: "ALL")
                        ForEach(availableCategories, id: \.self) { category in
                            categoryChip(category, label: category)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.background)
    }

    private func categoryChip(_ category: String?, label: String) -> some View {
        let isSelected = filterCategory == category
        return Button(action: { filterCategory = category }) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(isSelected ? theme.background : theme.foregroundMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isSelected ? theme.foreground.opacity(0.85) : theme.surface)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }

    private func levelFilterChip(_ level: ConsoleLogLevel?, label: String) -> some View {
        let isSelected = filterLevel == level
        let chipColor = level?.color ?? theme.accentColor

        return Button(action: { filterLevel = level }) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(chipColor.opacity(isSelected ? 0.95 : 0.65))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(chipColor.opacity(isSelected ? 0.18 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(isSelected ? chipColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
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
            // Entry count
            Text("\(entries.count) entries")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.foregroundMuted)

            Spacer()

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? theme.backgroundSecondary : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if !hovering { isCopied = false }
        }
    }

    private func formatTime(_ date: Date) -> String {
        TalkieDate.consoleTime(date)
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
