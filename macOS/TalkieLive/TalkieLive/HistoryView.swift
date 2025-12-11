//
//  HistoryView.swift
//  TalkieLive
//
//  Main window showing utterance history - matches macOS Talkie style
//

import SwiftUI
import Carbon.HIToolbox

// MARK: - Navigation

enum LiveNavigationSection: Hashable {
    case home
    case history
    case console
    case settings
}

// MARK: - Main Navigation View

struct LiveNavigationView: View {
    @ObservedObject private var store = UtteranceStore.shared
    @ObservedObject private var settings = LiveSettings.shared

    @State private var selectedSection: LiveNavigationSection? = .home
    @State private var selectedUtterance: Utterance?
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isSidebarCollapsed: Bool = false
    @State private var isChevronHovered: Bool = false
    @State private var isChevronPressed: Bool = false
    @State private var appFilter: String? = nil  // Filter by app name

    private var filteredUtterances: [Utterance] {
        var result = store.utterances

        // Apply app filter
        if let appFilter = appFilter {
            result = result.filter { $0.metadata.activeAppName == appFilter }
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    /// Sections that need full-width (no detail column)
    private var needsFullWidth: Bool {
        selectedSection == .home || selectedSection == .console || selectedSection == .settings
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Sidebar - toggleable between icon-only and full labels
                // Use fixed width (min=max) to prevent sidebar from resizing when content column is dragged
                sidebarContent
                    .navigationSplitViewColumnWidth(
                        min: isSidebarCollapsed ? 56 : 180,
                        ideal: isSidebarCollapsed ? 56 : 180,
                        max: isSidebarCollapsed ? 56 : 180
                    )
            } content: {
                // Content column - shows list for history, minimal for full-width views
                if needsFullWidth {
                    // Minimal placeholder - content renders in detail column
                    Color.clear
                        .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
                } else {
                    historyListView
                        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
                }
            } detail: {
                // Detail column - shows utterance detail or full-width content
                if needsFullWidth {
                    fullWidthContentView
                } else {
                    detailColumnView
                }
            }
            .navigationSplitViewStyle(.prominentDetail)

            // Full-width status bar at bottom
            StatusBar()
        }
        .frame(minWidth: 700, minHeight: 500)
        .observeTheme()
        .onAppear {
            LiveSettings.shared.applyAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToConsole)) { _ in
            selectedSection = .console
        }
    }

    // MARK: - Sidebar Content (Collapsible)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // App branding header with collapse toggle
            sidebarHeader

            // Navigation list
            List(selection: $selectedSection) {
                Section {
                    sidebarItem(
                        section: .home,
                        icon: "house",
                        title: "Home"
                    )
                }

                Section(isSidebarCollapsed ? "" : "Library") {
                    sidebarItem(
                        section: .history,
                        icon: "sparkles",
                        title: "Echoes",
                        badge: store.utterances.count > 0 ? "\(store.utterances.count)" : nil,
                        badgeColor: .secondary
                    )
                }

                Section(isSidebarCollapsed ? "" : "System") {
                    let errorCount = SystemEventManager.shared.events.filter { $0.type == .error }.count
                    sidebarItem(
                        section: .console,
                        icon: "terminal",
                        title: "Console",
                        badge: errorCount > 0 ? "\(errorCount)" : nil,
                        badgeColor: .red
                    )

                    sidebarItem(
                        section: .settings,
                        icon: "gearshape",
                        title: "Settings"
                    )
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(TalkieTheme.secondaryBackground)
    }

    /// Sidebar header with app branding and collapse toggle
    private var sidebarHeader: some View {
        HStack {
            if isSidebarCollapsed {
                // Collapsed: show expand chevron centered
                chevronButton(icon: "chevron.right", help: "Expand Sidebar")
            } else {
                // Expanded: show app name and collapse button
                Text("TALKIE LIVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color(white: 0.45))

                Spacer()

                chevronButton(icon: "chevron.left", help: "Collapse Sidebar")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.horizontal, isSidebarCollapsed ? 0 : 12)
        .padding(.top, 8) // Clear traffic light buttons
    }

    /// Interactive chevron button with hover and press feedback
    private func chevronButton(icon: String, help: String) -> some View {
        Button(action: {
            // Haptic-like press feedback
            withAnimation(.easeOut(duration: 0.1)) {
                isChevronPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isChevronPressed = false
                toggleSidebarCollapse()
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isChevronHovered ? Color(white: 0.9) : Color(white: 0.5))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isChevronHovered ? Color(white: 0.2) : Color.clear)
                )
                .scaleEffect(isChevronPressed ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isChevronHovered = hovering
            }
        }
        .help(help)
    }

    private func toggleSidebarCollapse() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarCollapsed.toggle()
        }
    }

    /// Adaptive sidebar item - shows icon only when collapsed, full label when expanded
    @ViewBuilder
    private func sidebarItem(
        section: LiveNavigationSection,
        icon: String,
        title: String,
        badge: String? = nil,
        badgeColor: Color = .secondary
    ) -> some View {
        if isSidebarCollapsed {
            // Icon-only mode
            Image(systemName: icon)
                .frame(maxWidth: .infinity)
                .tag(section)
                .help(title) // Tooltip on hover
        } else {
            // Full label mode
            Label {
                HStack {
                    Text(title)
                    Spacer()
                    if let badge = badge {
                        Text(badge)
                            .font(.caption)
                            .foregroundColor(badgeColor)
                    }
                }
            } icon: {
                Image(systemName: icon)
            }
            .tag(section)
        }
    }

    // MARK: - Full Width Content (for Home, Console and Settings)

    @ViewBuilder
    private var fullWidthContentView: some View {
        switch selectedSection {
        case .home:
            HomeView(
                onSelectUtterance: { utterance in
                    // Navigate to history and select this utterance
                    selectedSection = .history
                    selectedUtterance = utterance
                },
                onSelectApp: { appName, _ in
                    // Navigate to history filtered by this app
                    appFilter = appName
                    selectedSection = .history
                    selectedUtterance = nil
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .console:
            consoleContentView
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TalkieTheme.surface)
        case .settings:
            settingsContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EmptyView()
        }
    }

    private var historyListView: some View {
        VStack(spacing: 0) {
            // Search
            SidebarSearchField(text: $searchText, placeholder: "Search transcripts...")

            // Active filter indicator
            if let appFilter = appFilter {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan)

                    Text("App: \(appFilter)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(white: 0.8))

                    Spacer()

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.appFilter = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.cyan.opacity(0.1))
            }

            Rectangle()
                .fill(Design.divider)
                .frame(height: 0.5)

            if filteredUtterances.isEmpty {
                emptyHistoryState
            } else {
                List(filteredUtterances, selection: $selectedUtterance) { utterance in
                    UtteranceRowView(utterance: utterance)
                        .tag(utterance)
                        .contextMenu {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(utterance.text, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                withAnimation {
                                    if selectedUtterance == utterance {
                                        selectedUtterance = nil
                                    }
                                    store.delete(utterance)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    // Clear selection if deleting selected item
                                    if selectedUtterance == utterance {
                                        selectedUtterance = nil
                                    }
                                    store.delete(utterance)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            // Footer
            Rectangle()
                .fill(Design.divider)
                .frame(height: 0.5)

            HStack {
                Text("\(store.utterances.count) \(store.utterances.count == 1 ? "echo" : "echoes")")
                    .font(Design.fontXS)
                    .foregroundColor(Design.foregroundMuted)

                Spacer()

                if !store.utterances.isEmpty {
                    Button("Clear All") {
                        store.clear()
                    }
                    .font(Design.fontXS)
                    .foregroundColor(.red.opacity(0.8))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Design.background)
    }

    private var settingsContentView: some View {
        EmbeddedSettingsView()
    }

    // MARK: - Console Content

    private var consoleContentView: some View {
        EmbeddedConsoleView()
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundColor(Design.foregroundMuted.opacity(0.5))
            Text("No Echoes Yet")
                .font(Design.fontBodyMedium)
                .foregroundColor(Design.foregroundSecondary)
            Text("Press \(LiveSettings.shared.hotkey.displayString) to start recording")
                .font(Design.fontSM)
                .foregroundColor(Design.foregroundMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumnView: some View {
        if selectedSection == .settings {
            settingsDetailPlaceholder
        } else if selectedSection == .console {
            consoleDetailPlaceholder
        } else if let utterance = selectedUtterance {
            UtteranceDetailView(utterance: utterance)
        } else {
            emptyDetailState
        }
    }

    private var settingsDetailPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 36))
                .foregroundColor(Design.foregroundMuted.opacity(0.3))
            Text("Configure TalkieLive settings")
                .font(Design.fontSM)
                .foregroundColor(Design.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TalkieTheme.surface)
    }

    private var consoleDetailPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundColor(Design.foregroundMuted.opacity(0.3))
            Text("System event logs")
                .font(Design.fontSM)
                .foregroundColor(Design.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TalkieTheme.surface)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 36))
                .foregroundColor(Design.foregroundMuted.opacity(0.3))
            Text("Select a past life")
                .font(Design.fontSM)
                .foregroundColor(Design.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TalkieTheme.surface)
    }
}

// MARK: - Utterance Row

struct UtteranceRowView: View {
    let utterance: Utterance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Preview text
            Text(utterance.text)
                .font(Design.fontBody)
                .foregroundColor(Design.foreground)
                .lineLimit(2)

            // Metadata
            HStack(spacing: 4) {
                if let duration = utterance.durationSeconds {
                    Text(formatDuration(duration))
                        .font(Design.fontXS)

                    Text("·")
                        .font(Design.fontXS)
                        .foregroundColor(Design.foregroundMuted)
                }

                Text(formatDate(utterance.timestamp))
                    .font(Design.fontXS)

                if let appName = utterance.metadata.activeAppName {
                    Text("·")
                        .font(Design.fontXS)
                        .foregroundColor(Design.foregroundMuted)

                    HStack(spacing: 4) {
                        if let bundleID = utterance.metadata.activeAppBundleID {
                            AppIconView(bundleIdentifier: bundleID, size: 12)
                                .frame(width: 12, height: 12)
                        }

                        Text(appName)
                            .font(Design.fontXS)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundColor(Design.foregroundSecondary)
        }
        .padding(.vertical, 6)
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return "Today, \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Utterance Detail

struct UtteranceDetailView: View {
    let utterance: Utterance
    @State private var copied = false
    @State private var showJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header: Date + actions
                    MinimalHeader(utterance: utterance)

                    // Combined transcript + stats container
                    TranscriptContainer(utterance: utterance, showJSON: $showJSON, copied: $copied, onCopy: copyToClipboard)

                    // Info cards row
                    MinimalInfoCards(utterance: utterance)

                    // Audio asset
                    MinimalAudioCard(utterance: utterance)

                    // Actions section
                    ActionsSection(utterance: utterance)
                }
                .padding(24)
            }
        }
        .background(Color(white: 0.04))  // Near black background
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(utterance.text, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }

    private func pasteText() {
        copyToClipboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Minimal Detail Components

private struct MinimalHeader: View {
    let utterance: Utterance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                // Date + time badge
                HStack(spacing: 8) {
                    Text(formatDate(utterance.timestamp))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Text(formatTime(utterance.timestamp))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(white: 0.2), lineWidth: 1)
                        )
                }

                Spacer()

                // Export action only (Copy moved to text area)
                GhostButton(icon: "square.and.arrow.up", label: "Export", isActive: false, accentColor: .cyan) {
                    // Export action
                }
            }

            // ID row
            Text("ID: T-\(utterance.id.uuidString.prefix(5).uppercased())")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.35))
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

private struct GhostButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    var accentColor: Color? = nil
    let action: () -> Void

    @State private var isHovered = false

    private var textColor: Color {
        if isActive { return .green }
        if let accent = accentColor {
            return isHovered ? accent : Color(white: 0.65)
        }
        return isHovered ? Color(white: 0.9) : Color(white: 0.65)
    }

    private var borderColor: Color {
        if isActive { return Color.green.opacity(0.4) }
        if isHovered {
            return accentColor?.opacity(0.4) ?? Color(white: 0.35)
        }
        return Color(white: 0.22)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isActive ? "checkmark" : icon)
                    .font(.system(size: 10))
                Text(isActive ? "Copied" : label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? Color(white: 0.12) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ContentToggle: View {
    @Binding var showJSON: Bool

    var body: some View {
        HStack(spacing: 0) {
            ToggleSegment(label: "Text", isSelected: !showJSON) {
                showJSON = false
            }
            ToggleSegment(label: "JSON", isSelected: showJSON) {
                showJSON = true
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.12))
        )
    }
}

private struct ToggleSegment: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: label == "Text" ? "text.alignleft" : "curlybraces")
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : Color(white: 0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color(white: 0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Combined Transcript Container (Stats + Text in one bordered container)

private struct TranscriptContainer: View {
    let utterance: Utterance
    @Binding var showJSON: Bool
    @Binding var copied: Bool
    let onCopy: () -> Void

    @State private var isHovered = false
    @State private var isCopyHovered = false

    // Crisp text colors - solid grays instead of opacity
    private static let textPrimary = Color(white: 0.93)
    private static let textSecondary = Color(white: 0.7)
    private static let textMuted = Color(white: 0.45)

    private var tokenEstimate: Int {
        // Rough estimate: ~4 chars per token
        utterance.characterCount / 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Transcript content with copy button overlay
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    // Left accent bar
                    Rectangle()
                        .fill(showJSON ? Color.cyan.opacity(0.5) : Color(white: 0.3))
                        .frame(width: 3)

                    // Text content
                    if showJSON {
                        JSONContentView(utterance: utterance)
                    } else {
                        Text(utterance.text)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Self.textPrimary)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .padding(.trailing, 36)
                    }
                }

                // Copy button inside text area
                if isHovered || copied {
                    Button(action: onCopy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(copied ? .green : (isCopyHovered ? .white : Color(white: 0.5)))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isCopyHovered ? Color(white: 0.15) : Color.clear)
                    )
                    .onHover { isCopyHovered = $0 }
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .animation(.easeOut(duration: 0.15), value: isCopyHovered)
                }
            }

            // Bottom bar: Stats left, Toggle center, Tokens right
            HStack(alignment: .center) {
                HStack(spacing: 16) {
                    StatPill(label: "WORDS", value: "\(utterance.wordCount)")
                    StatPill(label: "CHARS", value: "\(utterance.characterCount)")
                }

                Spacer()

                ContentToggle(showJSON: $showJSON)

                Spacer()

                StatPill(label: "TOKENS", value: "~\(tokenEstimate)", color: .cyan)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.04))
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color?.opacity(0.6) ?? Color(white: 0.45))

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color ?? Color(white: 0.93))
        }
    }
}

private struct JSONContentView: View {
    let utterance: Utterance

    var body: some View {
        let json = """
        {
          "id": "\(utterance.id.uuidString)",
          "text": "\(utterance.text.prefix(50))...",
          "timestamp": "\(ISO8601DateFormatter().string(from: utterance.timestamp))",
          "words": \(utterance.wordCount),
          "chars": \(utterance.characterCount),
          "model": "\(utterance.metadata.whisperModel ?? "unknown")"
        }
        """

        Text(json)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(Color(white: 0.75))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }
}

private struct MinimalInfoCards: View {
    let utterance: Utterance

    var body: some View {
        HStack(spacing: 12) {
            // Input source - purple (with app icon)
            if let appName = utterance.metadata.activeAppName {
                InfoCard(
                    label: "INPUT SOURCE",
                    icon: "chevron.left.forwardslash.chevron.right",
                    value: appName,
                    iconColor: .purple,
                    appBundleID: utterance.metadata.activeAppBundleID
                )
            }

            // Model config - blue
            if let model = utterance.metadata.whisperModel {
                InfoCard(
                    label: "MODEL CONFIG",
                    icon: "cpu",
                    value: model,
                    iconColor: .blue
                )
            }

            // Duration - orange
            if let duration = utterance.durationSeconds {
                InfoCard(
                    label: "DURATION",
                    icon: "clock",
                    value: formatDuration(duration),
                    iconColor: .orange
                )
            }

            // Transcription time - green (shows processing speed)
            if let transcriptionMs = utterance.metadata.transcriptionDurationMs {
                InfoCard(
                    label: "TRANSCRIBED",
                    icon: "bolt",
                    value: formatTranscriptionTime(transcriptionMs),
                    iconColor: .green
                )
            }
        }
    }

    private func formatDuration(_ d: Double) -> String {
        String(format: "%.2fs", d)
    }

    private func formatTranscriptionTime(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }
}

private struct InfoCard: View {
    let label: String
    let icon: String
    let value: String
    var iconColor: Color = .white
    var appBundleID: String? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isHovered ? Color(white: 0.6) : Color(white: 0.45))

            HStack(spacing: 6) {
                if let bundleID = appBundleID {
                    AppIconView(bundleIdentifier: bundleID, size: 14)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(isHovered ? iconColor : iconColor.opacity(0.8))
                }

                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isHovered ? Color(white: 0.95) : Color(white: 0.88))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color(white: 0.09) : Color(white: 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? iconColor.opacity(0.3) : Color(white: 0.12), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct MinimalAudioCard: View {
    let utterance: Utterance
    @ObservedObject private var playback = AudioPlaybackManager.shared
    @State private var isHovering = false
    @State private var isPlayButtonHovered = false

    private var isThisPlaying: Bool {
        playback.currentAudioID == utterance.id.uuidString && playback.isPlaying
    }

    private var isThisLoaded: Bool {
        playback.currentAudioID == utterance.id.uuidString
    }

    private var displayProgress: Double {
        isThisLoaded ? playback.progress : 0
    }

    private var displayCurrentTime: TimeInterval {
        isThisLoaded ? playback.currentTime : 0
    }

    private var totalDuration: TimeInterval {
        utterance.durationSeconds ?? 0
    }

    private var hasAudio: Bool {
        utterance.metadata.hasAudio
    }

    /// Short ID for display (last 8 chars of filename before extension)
    private var shortFileId: String {
        guard let url = utterance.metadata.audioURL else { return "—" }
        let filename = url.deletingPathExtension().lastPathComponent
        if filename.count > 8 {
            return String(filename.suffix(8))
        }
        return filename
    }

    private var fullFilename: String {
        utterance.metadata.audioURL?.deletingPathExtension().lastPathComponent ?? "No audio"
    }

    private var fileSize: String {
        guard let url = utterance.metadata.audioURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main playback row
            HStack(spacing: 12) {
                // Play button with hover effect
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(playButtonBackground)
                            .frame(width: 36, height: 36)

                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(playButtonForeground)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!hasAudio)
                .onHover { isPlayButtonHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isPlayButtonHovered)

                // Waveform + timeline (fills available space)
                VStack(spacing: 6) {
                    MinimalWaveformBars(progress: displayProgress, isPlaying: isThisPlaying)
                        .frame(height: 32)

                    // Time row - aligned with waveform edges
                    HStack {
                        Text(formatTime(displayCurrentTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))

                        Spacer()

                        Text(formatTime(totalDuration))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.35))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Divider
            Rectangle()
                .fill(Color(white: 0.12))
                .frame(height: 1)

            // File info row - Cmd+click to reveal
            HStack {
                // File ID (truncated, full on hover)
                Text(isHovering ? fullFilename : shortFileId)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: isHovering ? 0.7 : 0.4))
                    .lineLimit(1)
                    .animation(.easeOut(duration: 0.15), value: isHovering)

                Spacer()

                // File size
                if !fileSize.isEmpty {
                    Text(fileSize)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.35))
                }

                // Cmd+click hint on hover
                if isHovering && hasAudio {
                    Text("⌘ click to reveal")
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                // Check for Cmd key
                if NSEvent.modifierFlags.contains(.command) && hasAudio {
                    revealInFinder()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    private var playButtonBackground: Color {
        if !hasAudio { return Color(white: 0.08) }
        if isThisPlaying { return Color.accentColor.opacity(0.25) }
        if isPlayButtonHovered { return Color(white: 0.18) }
        return Color(white: 0.12)
    }

    private var playButtonForeground: Color {
        if !hasAudio { return Color(white: 0.3) }
        if isThisPlaying { return .white }
        if isPlayButtonHovered { return .white }
        return Color(white: 0.85)
    }

    private func togglePlayback() {
        guard let url = utterance.metadata.audioURL else { return }
        playback.togglePlayPause(url: url, id: utterance.id.uuidString)
    }

    private func revealInFinder() {
        guard let url = utterance.metadata.audioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Minimal Waveform Bars

private struct MinimalWaveformBars: View {
    let progress: Double
    var isPlaying: Bool = false

    // Pre-computed bar heights for consistency (seeded pseudo-random)
    private static let barHeights: [Double] = {
        var heights: [Double] = []
        for i in 0..<40 {
            let seed = Double(i) * 1.618
            let h = 0.3 + sin(seed * 2.5) * 0.25 + cos(seed * 1.3) * 0.2
            heights.append(max(0.15, min(1.0, h)))
        }
        return heights
    }()

    private static let barCount: Int = 40

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !isPlaying)) { timeline in
            WaveformBarsContent(
                progress: progress,
                isPlaying: isPlaying,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
        }
    }
}

private struct WaveformBarsContent: View {
    let progress: Double
    let isPlaying: Bool
    let time: TimeInterval

    private static let barHeights: [Double] = {
        var heights: [Double] = []
        for i in 0..<40 {
            let seed = Double(i) * 1.618
            let h = 0.3 + sin(seed * 2.5) * 0.25 + cos(seed * 1.3) * 0.2
            heights.append(max(0.15, min(1.0, h)))
        }
        return heights
    }()

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<Self.barHeights.count, id: \.self) { i in
                    WaveformBar(
                        index: i,
                        totalBars: Self.barHeights.count,
                        baseHeight: Self.barHeights[i],
                        progress: progress,
                        isPlaying: isPlaying,
                        time: time,
                        containerHeight: geo.size.height
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WaveformBar: View {
    let index: Int
    let totalBars: Int
    let baseHeight: Double
    let progress: Double
    let isPlaying: Bool
    let time: TimeInterval
    let containerHeight: CGFloat

    private var barProgress: Double {
        Double(index) / Double(totalBars)
    }

    private var isPast: Bool {
        barProgress < progress
    }

    private var isCurrent: Bool {
        abs(barProgress - progress) < (1.0 / Double(totalBars))
    }

    private var animatedHeight: Double {
        if isPlaying && isPast {
            return baseHeight + sin(time * 4 + Double(index) * 0.5) * 0.1
        }
        return baseHeight
    }

    private var barColor: Color {
        if isCurrent {
            return Color(white: 0.95)
        } else if isPast {
            return Color(white: 0.65)
        } else {
            return Color(white: 0.25)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(barColor)
            .frame(width: 3, height: containerHeight * max(0.15, animatedHeight))
    }
}

private struct ActionsSection: View {
    let utterance: Utterance

    // Grid columns adapt to available width
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIONS")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(white: 0.45))

            LazyVGrid(columns: columns, spacing: 10) {
                ActionCard(
                    icon: "waveform.badge.magnifyingglass",
                    title: "Enhance Audio",
                    subtitle: "Pro model",
                    color: .cyan
                )

                ActionCard(
                    icon: "arrow.up.doc",
                    title: "Promote to Memo",
                    subtitle: "Full features",
                    color: .green
                )

                ActionCard(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    subtitle: "Export",
                    color: .blue
                )

                ActionCard(
                    icon: "ellipsis",
                    title: "More",
                    subtitle: "Options",
                    color: .gray
                )
            }
        }
    }
}

private struct ActionCard: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var color: Color = .white

    @State private var isHovered = false

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isHovered ? color : Color(white: 0.55))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHovered ? color.opacity(0.12) : Color(white: 0.1))
                    )

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isHovered ? Color(white: 0.93) : Color(white: 0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 8))
                            .foregroundColor(isHovered ? color.opacity(0.7) : Color(white: 0.4))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color(white: 0.08) : Color(white: 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? color.opacity(0.3) : Color(white: 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Transcription Info Card (Context + Metadata)

private struct TranscriptionInfoCard: View {
    let utterance: Utterance

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Row 1: Source context
            HStack(spacing: Spacing.lg) {
                // Source app
                if let appName = utterance.metadata.activeAppName {
                    InfoPill(
                        icon: "app.fill",
                        label: "Source",
                        value: appName,
                        color: .blue
                    )
                }

                // Window
                if let windowTitle = utterance.metadata.activeWindowTitle, !windowTitle.isEmpty {
                    InfoPill(
                        icon: "macwindow",
                        label: "Window",
                        value: String(windowTitle.prefix(25)),
                        color: .purple
                    )
                }

                Spacer()
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Row 2: Transcription metadata
            HStack(spacing: Spacing.lg) {
                // Model
                if let model = utterance.metadata.whisperModel {
                    InfoPill(
                        icon: "cpu",
                        label: "Model",
                        value: model.capitalized,
                        color: .cyan
                    )
                }

                // Duration
                if let duration = utterance.durationSeconds {
                    InfoPill(
                        icon: "clock",
                        label: "Duration",
                        value: formatDuration(duration),
                        color: .orange
                    )
                }

                // Transcription time
                if let transcriptionMs = utterance.metadata.transcriptionDurationMs {
                    InfoPill(
                        icon: "bolt",
                        label: "Processed",
                        value: formatTranscriptionTime(transcriptionMs),
                        color: .green
                    )
                }

                // Routing
                if let routingMode = utterance.metadata.routingMode {
                    InfoPill(
                        icon: routingMode == "paste" ? "doc.on.clipboard" : "clipboard",
                        label: "Routing",
                        value: routingMode == "paste" ? "Paste" : "Clipboard",
                        color: .pink
                    )
                }

                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatTranscriptionTime(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }
}

private struct InfoPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color.opacity(0.8))

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .textCase(.uppercase)

                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.08))
        )
    }
}

// MARK: - Transcript Card

private struct TranscriptCard: View {
    let text: String
    let onCopy: () -> Void
    let copied: Bool

    @State private var isHoveringCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content area - clean, readable
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.95))
                .textSelection(.enabled)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)

            // Bottom bar with quick copy
            HStack {
                // Word/char count
                HStack(spacing: Spacing.md) {
                    Label("\(text.split(separator: " ").count) words", systemImage: "text.word.spacing")
                    Label("\(text.count) chars", systemImage: "character.cursor.ibeam")
                }
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))

                Spacer()

                // Quick copy button
                Button(action: onCopy) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(copied ? .green : (isHoveringCopy ? .white : .white.opacity(0.5)))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(copied ? Color.green.opacity(0.15) : (isHoveringCopy ? Color.white.opacity(0.1) : Color.clear))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringCopy = $0 }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(Color.white.opacity(0.02))
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Waveform Card

private struct WaveformCard: View {
    let utterance: Utterance
    @ObservedObject private var playback = AudioPlaybackManager.shared

    private var isThisPlaying: Bool {
        playback.currentAudioID == utterance.id.uuidString && playback.isPlaying
    }

    private var isThisLoaded: Bool {
        playback.currentAudioID == utterance.id.uuidString
    }

    private var displayProgress: Double {
        isThisLoaded ? playback.progress : 0
    }

    private var displayCurrentTime: TimeInterval {
        isThisLoaded ? playback.currentTime : 0
    }

    private var hasAudio: Bool {
        utterance.metadata.hasAudio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("AUDIO", systemImage: "waveform")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                if hasAudio {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.6))
                } else {
                    Text("No audio file")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }

                if let duration = utterance.durationSeconds {
                    Text(formatDuration(duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Waveform visualization
            WaveformVisualization(progress: displayProgress, isPlaying: isThisPlaying)
                .frame(height: 48)

            // Playback controls
            HStack(spacing: Spacing.md) {
                // Play button
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(hasAudio ? Color.accentColor : Color.white.opacity(0.1))

                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(hasAudio ? .white : .white.opacity(0.3))
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!hasAudio)

                // Progress slider
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * displayProgress)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if hasAudio && isThisLoaded {
                                    let newProgress = max(0, min(1, value.location.x / geo.size.width))
                                    playback.seek(to: newProgress)
                                }
                            }
                    )
                }
                .frame(height: 4)

                // Time display
                Text("\(formatDuration(displayCurrentTime)) / \(formatDuration(utterance.durationSeconds ?? 0))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            // File info row
            if let audioURL = utterance.metadata.audioURL {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.3))

                    Text(audioURL.lastPathComponent)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(action: { revealInFinder(audioURL) }) {
                        Text("Reveal")
                            .font(.system(size: 8))
                            .foregroundColor(.accentColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func togglePlayback() {
        guard let url = utterance.metadata.audioURL else { return }
        playback.togglePlayPause(url: url, id: utterance.id.uuidString)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Waveform Visualization

private struct WaveformVisualization: View {
    let progress: Double
    var isPlaying: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let barCount = 60
                let barWidth: CGFloat = 2
                let gap: CGFloat = 2
                let totalWidth = CGFloat(barCount) * (barWidth + gap)
                let startX = (size.width - totalWidth) / 2

                for i in 0..<barCount {
                    let seed = Double(i) * 1.618
                    let time = timeline.date.timeIntervalSinceReferenceDate

                    // Generate pseudo-random but consistent heights
                    let baseHeight = 0.3 + sin(seed * 2.5) * 0.2 + cos(seed * 1.3) * 0.15

                    // Animate only when playing
                    let animatedHeight: Double
                    if isPlaying {
                        animatedHeight = baseHeight + sin(time * 3 + seed) * 0.15
                    } else {
                        animatedHeight = baseHeight
                    }

                    let barHeight = max(4, CGFloat(animatedHeight) * size.height * 0.8)
                    let x = startX + CGFloat(i) * (barWidth + gap)
                    let y = (size.height - barHeight) / 2

                    let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

                    let progressPoint = CGFloat(i) / CGFloat(barCount)
                    let opacity = progressPoint < progress ? 0.8 : 0.25

                    context.fill(
                        RoundedRectangle(cornerRadius: 1).path(in: barRect),
                        with: .color(.accentColor.opacity(opacity))
                    )
                }
            }
        }
    }
}

// MARK: - Stats Card

private struct StatsCard: View {
    let utterance: Utterance

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label("STATS", systemImage: "chart.bar")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.sm) {
                StatBox(
                    value: "\(utterance.wordCount)",
                    label: "Words",
                    icon: "text.word.spacing",
                    color: .blue
                )

                StatBox(
                    value: "\(utterance.characterCount)",
                    label: "Characters",
                    icon: "character.cursor.ibeam",
                    color: .purple
                )

                if let duration = utterance.durationSeconds {
                    StatBox(
                        value: formatDuration(duration),
                        label: "Duration",
                        icon: "clock",
                        color: .orange
                    )
                }

                if let transcriptionMs = utterance.metadata.transcriptionDurationMs {
                    StatBox(
                        value: formatTranscriptionTime(transcriptionMs),
                        label: "Transcription",
                        icon: "bolt",
                        color: .green
                    )
                }
            }

            // Additional stats row
            if utterance.metadata.whisperModel != nil || utterance.metadata.routingMode != nil {
                Divider().background(Color.white.opacity(0.1))

                HStack(spacing: Spacing.lg) {
                    if let model = utterance.metadata.whisperModel {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9))
                                .foregroundColor(.cyan.opacity(0.7))
                            Text("Model:")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                            Text(model)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    if let routingMode = utterance.metadata.routingMode {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 9))
                                .foregroundColor(.pink.opacity(0.7))
                            Text("Routing:")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                            Text(routingMode == "paste" ? "Paste" : "Clipboard")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatTranscriptionTime(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.2fs", seconds)
        }
    }
}

private struct StatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color.opacity(0.7))

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.08))
        )
    }
}

// MARK: - Quick Actions Card (replaces Smart Actions)

private struct SmartActionsCard: View {
    let utterance: Utterance
    @State private var hoveredAction: QuickActionKind? = nil
    @State private var actionFeedback: QuickActionKind? = nil

    // Map Utterance to LiveUtterance for database operations
    private var liveUtterance: LiveUtterance? {
        // Find matching LiveUtterance by timestamp and text
        PastLivesDatabase.recent(limit: 50).first { live in
            live.text == utterance.text &&
            abs(live.createdAt.timeIntervalSince(utterance.timestamp)) < 5
        }
    }

    private var promotionStatus: PromotionStatus {
        liveUtterance?.promotionStatus ?? .none
    }

    private var canPromote: Bool {
        liveUtterance?.canPromote ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with promotion status
            HStack {
                Label("QUICK ACTIONS", systemImage: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                // Show promotion status badge if promoted
                if promotionStatus != .none {
                    promotionStatusBadge
                }
            }

            // Primary actions row (most common)
            HStack(spacing: Spacing.sm) {
                QuickActionButton(
                    action: .copyToClipboard,
                    isHovered: hoveredAction == .copyToClipboard,
                    showFeedback: actionFeedback == .copyToClipboard,
                    onHover: { hoveredAction = $0 ? .copyToClipboard : nil },
                    onTap: { executeAction(.copyToClipboard) }
                )

                if canPromote {
                    QuickActionButton(
                        action: .promoteToMemo,
                        isHovered: hoveredAction == .promoteToMemo,
                        showFeedback: actionFeedback == .promoteToMemo,
                        onHover: { hoveredAction = $0 ? .promoteToMemo : nil },
                        onTap: { executeAction(.promoteToMemo) }
                    )

                    QuickActionButton(
                        action: .sendToClaude,
                        isHovered: hoveredAction == .sendToClaude,
                        showFeedback: actionFeedback == .sendToClaude,
                        onHover: { hoveredAction = $0 ? .sendToClaude : nil },
                        onTap: { executeAction(.sendToClaude) }
                    )
                }
            }

            // Secondary actions (overflow)
            if canPromote || utterance.metadata.hasAudio {
                Divider().background(Color.white.opacity(0.06))

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.xs) {
                    QuickActionButton(
                        action: .typeAgain,
                        isHovered: hoveredAction == .typeAgain,
                        showFeedback: actionFeedback == .typeAgain,
                        compact: true,
                        onHover: { hoveredAction = $0 ? .typeAgain : nil },
                        onTap: { executeAction(.typeAgain) }
                    )

                    if utterance.metadata.hasAudio {
                        QuickActionButton(
                            action: .retryTranscription,
                            isHovered: hoveredAction == .retryTranscription,
                            showFeedback: actionFeedback == .retryTranscription,
                            compact: true,
                            onHover: { hoveredAction = $0 ? .retryTranscription : nil },
                            onTap: { executeAction(.retryTranscription) }
                        )
                    }

                    if canPromote {
                        QuickActionButton(
                            action: .runWorkflow,
                            isHovered: hoveredAction == .runWorkflow,
                            showFeedback: actionFeedback == .runWorkflow,
                            compact: true,
                            onHover: { hoveredAction = $0 ? .runWorkflow : nil },
                            onTap: { executeAction(.runWorkflow) }
                        )

                        QuickActionButton(
                            action: .markIgnored,
                            isHovered: hoveredAction == .markIgnored,
                            showFeedback: actionFeedback == .markIgnored,
                            compact: true,
                            onHover: { hoveredAction = $0 ? .markIgnored : nil },
                            onTap: { executeAction(.markIgnored) }
                        )
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var promotionStatusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: promotionStatus.icon)
                .font(.system(size: 8))

            Text(promotionStatus.displayName)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(promotionStatusColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(promotionStatusColor.opacity(0.15))
        )
    }

    private var promotionStatusColor: Color {
        switch promotionStatus {
        case .none: return .white.opacity(0.3)
        case .memo: return .blue
        case .command: return .purple
        case .ignored: return .gray
        }
    }

    private func executeAction(_ action: QuickActionKind) {
        guard let live = liveUtterance else {
            // Fallback for legacy utterances without LiveUtterance
            if action == .copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(utterance.text, forType: .string)
                showFeedback(for: action)
            }
            return
        }

        // Show feedback
        showFeedback(for: action)

        // Execute action
        Task {
            await QuickActionRunner.shared.run(action, for: live)
        }
    }

    private func showFeedback(for action: QuickActionKind) {
        withAnimation(.easeOut(duration: 0.15)) {
            actionFeedback = action
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                actionFeedback = nil
            }
        }
    }
}

private struct QuickActionButton: View {
    let action: QuickActionKind
    let isHovered: Bool
    var showFeedback: Bool = false
    var compact: Bool = false
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    private var actionColor: Color {
        switch action {
        case .copyToClipboard: return .blue
        case .typeAgain: return .orange
        case .retryTranscription: return .cyan
        case .promoteToMemo: return .green
        case .createResearchMemo: return .teal
        case .sendToClaude: return .purple
        case .runWorkflow: return .pink
        case .markIgnored: return .gray
        }
    }

    var body: some View {
        Button(action: onTap) {
            if compact {
                compactContent
            } else {
                fullContent
            }
        }
        .buttonStyle(.plain)
        .onHover { onHover($0) }
    }

    private var fullContent: some View {
        HStack(spacing: 10) {
            Image(systemName: showFeedback ? "checkmark" : action.icon)
                .font(.system(size: 14))
                .foregroundColor(showFeedback ? .green : actionColor.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(showFeedback ? Color.green.opacity(0.15) : actionColor.opacity(0.1))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(showFeedback ? "Done!" : action.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(showFeedback ? .green : .white.opacity(0.9))

                    if let shortcut = action.shortcut, !showFeedback {
                        Text(shortcut)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                Text(actionDescription)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(showFeedback ? Color.green.opacity(0.1) : (isHovered ? actionColor.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(showFeedback ? Color.green.opacity(0.3) : (isHovered ? actionColor.opacity(0.3) : Color.white.opacity(0.05)), lineWidth: 1)
        )
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            Image(systemName: showFeedback ? "checkmark" : action.icon)
                .font(.system(size: 10))
                .foregroundColor(showFeedback ? .green : actionColor.opacity(0.7))

            Text(showFeedback ? "Done" : action.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(showFeedback ? .green : .white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(showFeedback ? Color.green.opacity(0.1) : (isHovered ? actionColor.opacity(0.08) : Color.white.opacity(0.03)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(showFeedback ? Color.green.opacity(0.2) : (isHovered ? actionColor.opacity(0.2) : Color.clear), lineWidth: 1)
        )
    }

    private var actionDescription: String {
        switch action {
        case .copyToClipboard: return "Copy text to clipboard"
        case .typeAgain: return "Type into active app"
        case .retryTranscription: return "Re-transcribe audio"
        case .promoteToMemo: return "Save as Talkie memo"
        case .createResearchMemo: return "Create research memo"
        case .sendToClaude: return "Send to Claude"
        case .runWorkflow: return "Run a workflow"
        case .markIgnored: return "Don't show again"
        }
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderRow: View {
    @ObservedObject var settings: LiveSettings
    @State private var isRecording = false

    var body: some View {
        LabeledContent("Shortcut") {
            HotkeyRecorderButton(
                hotkey: $settings.hotkey,
                isRecording: $isRecording
            )
        }
    }
}

struct HotkeyRecorderButton: View {
    @Binding var hotkey: HotkeyConfig
    @Binding var isRecording: Bool
    var showReset: Bool = true

    @State private var isHovered = false
    @State private var isCancelHovered = false
    @State private var isResetHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Main button
            Button(action: {
                isRecording.toggle()
            }) {
                HStack(spacing: 6) {
                    Text(isRecording ? "Press keys..." : hotkey.displayString)
                        .foregroundColor(.accentColor)

                    // Cancel X button when recording
                    if isRecording {
                        Button(action: {
                            isRecording = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(isCancelHovered ? .white : .accentColor.opacity(0.6))
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle()
                                        .fill(isCancelHovered ? Color.accentColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { isCancelHovered = $0 }
                    }
                }
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(isRecording ? 0.2 : (isHovered ? 0.18 : 0.12)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Reset button (only when not recording and not default)
            if showReset && !isRecording && hotkey != .default {
                Button(action: {
                    hotkey = .default
                    NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                }) {
                    Text("Reset")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isResetHovered ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isResetHovered ? Color.white.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isResetHovered = $0 }
            }
        }
        .background(
            HotkeyRecorderNSView(isRecording: $isRecording, hotkey: $hotkey)
                .frame(width: 0, height: 0)
        )
    }
}

// NSView wrapper for capturing key events
struct HotkeyRecorderNSView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: HotkeyConfig

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyCapture = { keyCode, modifiers in
            DispatchQueue.main.async {
                hotkey = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
                isRecording = false

                // Notify AppDelegate to re-register hotkey
                NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
            }
        }
        view.onCancel = {
            DispatchQueue.main.async {
                isRecording = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.isCapturing = isRecording
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

class KeyCaptureView: NSView {
    var isCapturing = false
    var onKeyCapture: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { isCapturing }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt32(event.keyCode)

        // Escape key (53) cancels recording
        if keyCode == 53 {
            onCancel?()
            return
        }

        // Ignore modifier-only keys
        if keyCode == 55 || keyCode == 56 || keyCode == 58 || keyCode == 59 ||
           keyCode == 54 || keyCode == 57 || keyCode == 60 || keyCode == 61 ||
           keyCode == 62 || keyCode == 63 {
            return
        }

        // Build Carbon modifiers
        var carbonModifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if event.modifierFlags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if event.modifierFlags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if event.modifierFlags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        onKeyCapture?(keyCode, carbonModifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't call super - swallow modifier changes
    }
}

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
}

// MARK: - Collapsed Navigation Button

struct CollapsedNavButton: View {
    let icon: String
    var isSelected: Bool = false
    var badge: Int? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : (isHovered ? Color(white: 0.8) : Color(white: 0.5)))
                    .frame(width: 36, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color(white: 0.15) : Color.clear))
                    )

                if let badge = badge, badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sound Picker Row

struct SoundPickerRow: View {
    let label: String
    @Binding var sound: TalkieSound

    var body: some View {
        HStack {
            Picker(label, selection: $sound) {
                ForEach(TalkieSound.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.menu)

            Button(action: {
                SoundManager.shared.preview(sound)
            }) {
                Image(systemName: "speaker.wave.2")
                    .font(Design.fontXS)
            }
            .buttonStyle(.plain)
            .foregroundColor(Design.foregroundSecondary)
            .disabled(sound == .none)
        }
    }
}

// MARK: - Storage Info Row

struct StorageInfoRow: View {
    @State private var storageSize = AudioStorage.formattedStorageSize()
    @State private var pastLivesCount = PastLivesDatabase.count()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Storage")
                    .font(Design.fontSM)
                Text("\(pastLivesCount) recordings • \(storageSize)")
                    .font(Design.fontXS)
                    .foregroundColor(Design.foregroundSecondary)
            }

            Spacer()

            Button("Clear All") {
                PastLivesDatabase.deleteAll()
                refreshStats()
            }
            .font(Design.fontXS)
            .buttonStyle(.tiny)
            .foregroundColor(.red.opacity(0.8))
        }
        .onAppear {
            refreshStats()
        }
    }

    private func refreshStats() {
        storageSize = AudioStorage.formattedStorageSize()
        pastLivesCount = PastLivesDatabase.count()
    }
}

// MARK: - Appearance Settings Content (Talkie macOS style)

struct AppearanceSettingsContent: View {
    @ObservedObject var settings: LiveSettings

    // Tactical dark colors
    private let bgColor = Color(red: 0.06, green: 0.06, blue: 0.08)
    private let surfaceColor = Color(red: 0.1, green: 0.1, blue: 0.12)
    private let borderColor = Color(red: 0.15, green: 0.15, blue: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Quick Themes
            quickThemesSection

            // Appearance Mode
            appearanceModeSection

            // Accent Color
            accentColorSection

            // Font Size
            fontSizeSection
        }
    }

    // MARK: - Quick Themes

    private var quickThemesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK THEMES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            // Live preview
            themePreviewPanel

            // Theme buttons
            HStack(spacing: 6) {
                ForEach(VisualTheme.allCases, id: \.rawValue) { theme in
                    themeButton(theme)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private var themePreviewPanel: some View {
        HStack(spacing: 0) {
            // Mini sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("LIVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.bottom, 4)

                ForEach(["History", "Console", "Settings"], id: \.self) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item == "History" ? "clock" : (item == "Console" ? "terminal" : "gearshape"))
                            .font(.system(size: 8))
                            .foregroundColor(item == "History" ? settings.accentColor.color : .white.opacity(0.4))
                        Text(item)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(item == "History" ? .white.opacity(0.9) : .white.opacity(0.5))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item == "History" ? settings.accentColor.color.opacity(0.2) : Color.clear)
                    .cornerRadius(3)
                }
            }
            .padding(8)
            .frame(width: 90)
            .background(bgColor)

            Rectangle()
                .fill(borderColor)
                .frame(width: 0.5)

            // Content area
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("TIMESTAMP")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 60, alignment: .leading)
                    Text("TEXT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.03))

                // Sample rows
                ForEach(0..<3, id: \.self) { i in
                    HStack {
                        Text(["12:34", "12:31", "12:28"][i])
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 60, alignment: .leading)
                        Text(["Quick memo...", "Meeting notes...", "Recording..."][i])
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(i == 0 ? settings.accentColor.color.opacity(0.15) : Color.clear)
                }
            }
            .background(bgColor)
        }
        .frame(height: 80)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private func themeButton(_ theme: VisualTheme) -> some View {
        let isActive = settings.visualTheme == theme

        return Button(action: { settings.applyVisualTheme(theme) }) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.previewColors.bg)
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(theme.previewColors.accent, lineWidth: 1)
                    )
                Text(theme.displayName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isActive ? settings.accentColor.color.opacity(0.15) : Color.white.opacity(0.05))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? settings.accentColor.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Appearance Mode

    private var appearanceModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPEARANCE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    appearanceModeButton(mode)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private func appearanceModeButton(_ mode: AppearanceMode) -> some View {
        let isSelected = settings.appearanceMode == mode

        return Button(action: { settings.appearanceMode = mode }) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? settings.accentColor.color : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? settings.accentColor.color.opacity(0.15) : Color.white.opacity(0.05))
                    .cornerRadius(8)

                Text(mode.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accent Color

    private var accentColorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACCENT COLOR")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], spacing: 6) {
                ForEach(AccentColorOption.allCases, id: \.rawValue) { color in
                    accentColorButton(color)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private func accentColorButton(_ colorOption: AccentColorOption) -> some View {
        let isSelected = settings.accentColor == colorOption

        return Button(action: { settings.accentColor = colorOption }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(colorOption.color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )

                Text(colorOption.displayName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? colorOption.color.opacity(0.15) : Color.white.opacity(0.03))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? colorOption.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Font Size

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FONT SIZE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(FontSize.allCases, id: \.rawValue) { size in
                    fontSizeButton(size)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private func fontSizeButton(_ size: FontSize) -> some View {
        let isSelected = settings.fontSize == size

        return Button(action: { settings.fontSize = size }) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(size: size == .small ? 12 : (size == .medium ? 14 : 16)))
                    .foregroundColor(isSelected ? settings.accentColor.color : .secondary)

                Text(size.displayName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? settings.accentColor.color.opacity(0.15) : Color.white.opacity(0.03))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? settings.accentColor.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LiveNavigationView()
}
