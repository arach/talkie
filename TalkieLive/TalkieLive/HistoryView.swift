//
//  HistoryView.swift
//  TalkieLive
//
//  Main window showing utterance history - matches macOS Talkie style
//

import SwiftUI
import TalkieServices
import Carbon.HIToolbox

// MARK: - Navigation

enum LiveNavigationSection: Hashable {
    case history
    case console
    case settings
}

// MARK: - Main Navigation View

struct LiveNavigationView: View {
    @ObservedObject private var store = UtteranceStore.shared
    @ObservedObject private var settings = LiveSettings.shared

    @State private var selectedSection: LiveNavigationSection? = .history
    @State private var selectedUtterance: Utterance?
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var filteredUtterances: [Utterance] {
        if searchText.isEmpty {
            return store.utterances
        }
        return store.utterances.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Sections that need full-width (no detail column)
    private var needsFullWidth: Bool {
        selectedSection == .console || selectedSection == .settings
    }

    var body: some View {
        VStack(spacing: 0) {
            if needsFullWidth {
                // Two-column layout for Console and Settings
                NavigationSplitView {
                    sidebarView
                        .frame(minWidth: 180, idealWidth: 200)
                } detail: {
                    fullWidthContentView
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // Three-column layout for History (list + detail)
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebarView
                        .frame(minWidth: 180, idealWidth: 200)
                } content: {
                    historyListView
                        .frame(minWidth: 260, idealWidth: 300)
                } detail: {
                    detailColumnView
                }
                .navigationSplitViewStyle(.balanced)
            }

            // Full-width status bar at bottom (includes its own top border)
            StatusBar()
        }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear {
            // Apply theme on launch
            LiveSettings.shared.applyTheme()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToConsole)) { _ in
            selectedSection = .console
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Navigation sections
            List(selection: $selectedSection) {
                Section(header: SectionHeader(title: "Library")) {
                    NavigationLink(value: LiveNavigationSection.history) {
                        SidebarRow(
                            icon: "sparkles",
                            title: "Past Lives",
                            count: store.utterances.count
                        )
                    }
                }
                .collapsible(false)

                Section(header: SectionHeader(title: "System")) {
                    NavigationLink(value: LiveNavigationSection.console) {
                        SidebarRow(
                            icon: "terminal",
                            title: "Console",
                            count: SystemEventManager.shared.events.filter { $0.type == .error }.count > 0
                                ? SystemEventManager.shared.events.filter { $0.type == .error }.count
                                : nil
                        )
                    }

                    NavigationLink(value: LiveNavigationSection.settings) {
                        SidebarRow(icon: "gearshape", title: "Settings")
                    }
                }
                .collapsible(false)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(Design.backgroundSecondary)
    }

    // MARK: - Full Width Content (for Console and Settings)

    @ViewBuilder
    private var fullWidthContentView: some View {
        switch selectedSection {
        case .console:
            consoleContentView
        case .settings:
            settingsContentView
        default:
            EmptyView()
        }
    }

    private var historyListView: some View {
        VStack(spacing: 0) {
            // Search
            SidebarSearchField(text: $searchText, placeholder: "Search transcripts...")

            Rectangle()
                .fill(Design.divider)
                .frame(height: 0.5)

            if filteredUtterances.isEmpty {
                emptyHistoryState
            } else {
                List(filteredUtterances, selection: $selectedUtterance) { utterance in
                    UtteranceRowView(utterance: utterance)
                        .tag(utterance)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            // Footer
            Rectangle()
                .fill(Design.divider)
                .frame(height: 0.5)

            HStack {
                Text("\(store.utterances.count) past \(store.utterances.count == 1 ? "life" : "lives")")
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
            Text("No Past Lives Yet")
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
        .background(Design.backgroundSecondary.opacity(0.5))
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
        .background(Design.backgroundSecondary.opacity(0.5))
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
        .background(Design.backgroundSecondary.opacity(0.5))
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

                    Text(appName)
                        .font(Design.fontXS)
                        .lineLimit(1)
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
                    MinimalHeader(utterance: utterance, copied: $copied, onCopy: copyToClipboard)

                    // Combined transcript + stats container
                    TranscriptContainer(utterance: utterance, showJSON: $showJSON)

                    // Info cards row
                    MinimalInfoCards(utterance: utterance)

                    // Audio asset
                    MinimalAudioCard(utterance: utterance)

                    // Process section
                    MinimalProcessSection(utterance: utterance)
                }
                .padding(24)
            }
        }
        .background(Design.background)
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
    @Binding var copied: Bool
    let onCopy: () -> Void

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

                // Actions: Copy + Export
                HStack(spacing: 8) {
                    GhostButton(icon: "doc.on.doc", label: "Copy", isActive: copied, accentColor: nil) {
                        onCopy()
                    }

                    GhostButton(icon: "square.and.arrow.up", label: "Export", isActive: false, accentColor: .cyan) {
                        // Export action
                    }
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
            // Top bar: Stats on left, Toggle + Token estimate on right
            HStack(alignment: .center) {
                // Left: Word and char counts
                HStack(spacing: 16) {
                    StatPill(label: "WORDS", value: "\(utterance.wordCount)")
                    StatPill(label: "CHARS", value: "\(utterance.characterCount)")
                }

                Spacer()

                // Right: Toggle + Token estimate
                HStack(spacing: 12) {
                    ContentToggle(showJSON: $showJSON)

                    // Token estimate (right aligned)
                    HStack(spacing: 4) {
                        Text("~\(tokenEstimate)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(Self.textPrimary)
                        Text("tokens")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Self.textMuted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Divider
            Rectangle()
                .fill(Color(white: 0.2))
                .frame(height: 1)

            // Transcript content
            HStack(spacing: 0) {
                // Left accent bar
                Rectangle()
                    .fill(showJSON ? Color.cyan.opacity(0.5) : Color(white: 0.35))
                    .frame(width: 3)

                // Text content - crisp rendering with proper font
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
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.18), lineWidth: 1)
        )
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(white: 0.45))

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.93))
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
            // Input source - purple
            if let appName = utterance.metadata.activeAppName {
                InfoCard(
                    label: "INPUT SOURCE",
                    icon: "chevron.left.forwardslash.chevron.right",
                    value: appName,
                    iconColor: .purple
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

            // Pipeline status - green icon, white text
            InfoCard(
                label: "PIPELINE",
                icon: "circle.fill",
                value: "SYNCED",
                iconColor: .green
            )
        }
    }

    private func formatDuration(_ d: Double) -> String {
        String(format: "%.2fs", d)
    }
}

private struct InfoCard: View {
    let label: String
    let icon: String
    let value: String
    var iconColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(white: 0.45))

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(iconColor)

                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.88))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.18), lineWidth: 1)
        )
    }
}

private struct MinimalAudioCard: View {
    let utterance: Utterance
    @ObservedObject private var playback = AudioPlaybackManager.shared
    @State private var isHoveringAsset = false
    @State private var isHoveringWaveform = false

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

    /// Truncated filename: show "...{last-segment}" after the last dash
    private var truncatedFilename: String {
        guard let url = utterance.metadata.audioURL else { return "No audio" }
        let filename = url.deletingPathExtension().lastPathComponent
        // Find last dash and show portion after it
        if let lastDashIndex = filename.lastIndex(of: "-") {
            let suffix = String(filename[filename.index(after: lastDashIndex)...])
            return "…\(suffix)"
        }
        // Fallback: show last 8 chars
        if filename.count > 12 {
            return "…\(filename.suffix(8))"
        }
        return filename
    }

    private var fullFilename: String {
        utterance.metadata.audioURL?.lastPathComponent ?? "No audio"
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
        HStack(spacing: 0) {
            // Left column: Play button + current time (compact)
            VStack(spacing: 4) {
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(hasAudio ? Color(white: 0.15) : Color(white: 0.1))
                            .frame(width: 32, height: 32)

                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(hasAudio ? Color(white: 0.85) : Color(white: 0.35))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!hasAudio)

                // Current time under button
                Text(formatTime(displayCurrentTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
            }
            .frame(width: 44)

            // Center: Waveform (takes most space ~3:1 ratio)
            VStack(alignment: .leading, spacing: 4) {
                MinimalWaveformBars(progress: displayProgress, isPlaying: isThisPlaying)
                    .frame(height: 28)
                    .onHover { isHoveringWaveform = $0 }
                    .help("Duration: \(formatTime(totalDuration))")

                // Time markers row
                HStack {
                    Text("0:00")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(white: 0.35))

                    Spacer()

                    Text(formatTime(totalDuration))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(white: 0.35))
                }
            }
            .padding(.horizontal, 12)

            // Right column: Audio asset info (aligned with pipeline card width)
            VStack(alignment: .trailing, spacing: 4) {
                Text("AUDIO")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(white: 0.4))

                // Filename (truncated, expands on hover)
                Text(isHoveringAsset ? fullFilename : truncatedFilename)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isHoveringAsset ? Color(white: 0.88) : Color(white: 0.55))
                    .lineLimit(1)

                // File size
                if !fileSize.isEmpty {
                    Text(fileSize)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }

                // Reveal link
                if hasAudio {
                    Button(action: revealInFinder) {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text("Reveal")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(isHoveringAsset ? .cyan : Color(white: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 100, alignment: .trailing)
            .onHover { isHoveringAsset = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.18), lineWidth: 1)
        )
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

private struct MinimalProcessSection: View {
    let utterance: Utterance

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROCESS")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(white: 0.45))

            HStack(spacing: 12) {
                ProcessCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Enhance",
                    subtitle: "Upscale with Pro Model",
                    shortcut: "⌘ R"
                )

                ProcessCard(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Memo",
                    subtitle: "Convert to Talkie",
                    shortcut: "⌘ M"
                )
            }
        }
    }
}

private struct ProcessCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let shortcut: String

    @State private var isHovered = false

    var body: some View {
        Button(action: {}) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: 0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.93))

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.5))
                }

                Spacer()

                Text(shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color(white: 0.25) : Color(white: 0.18), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHovered ? Color(white: 0.08) : Color.clear)
                    )
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

    var body: some View {
        Button(action: {
            isRecording.toggle()
        }) {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press keys...")
                        .foregroundColor(.accentColor)
                } else {
                    Text(hotkey.displayString)
                }
            }
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.15) : Design.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    override var acceptsFirstResponder: Bool { isCapturing }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        // Ignore modifier-only keys
        let keyCode = UInt32(event.keyCode)
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
                ForEach(ThemePreset.allCases, id: \.rawValue) { preset in
                    themeButton(preset)
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

    private func themeButton(_ preset: ThemePreset) -> some View {
        let isActive = settings.currentPreset == preset

        return Button(action: { settings.applyPreset(preset) }) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(preset.previewColors.bg)
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(preset.previewColors.accent, lineWidth: 1)
                    )
                Text(preset.displayName)
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
                ForEach([AppTheme.system, .light, .dark, .midnight], id: \.rawValue) { mode in
                    appearanceModeButton(mode)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private func appearanceModeButton(_ mode: AppTheme) -> some View {
        let isSelected = settings.theme == mode

        return Button(action: { settings.theme = mode }) {
            VStack(spacing: 6) {
                Image(systemName: modeIcon(mode))
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

    private func modeIcon(_ mode: AppTheme) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .midnight: return "moon.stars"
        }
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
