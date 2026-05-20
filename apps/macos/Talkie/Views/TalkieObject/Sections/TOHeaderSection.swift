//
//  TOHeaderSection.swift
//  Talkie
//
//  Editorial masthead for a TalkieObject detail pane.
//  Eyebrow row (· TYPE ····· DATE) → serif headline → mono byline
//  (provenance · duration). Replaces the dashboard-style metric pills
//  + four-column metadata grid the older detail header carried.
//
//  Deeper technical metadata (model, confidence, perf timings, audio
//  peaks, file paths) belongs in the right-margin metadata column —
//  see design/studio/components/studies/MacMemoDetail.tsx for the
//  canonical composition.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct TOHeaderSection: View {
    let recording: TalkieObject
    let settings: SettingsManager

    var isEditing: Bool = false
    var isAlwaysEditable: Bool = false
    @Binding var editedTitle: String
    @FocusState.Binding var titleFieldFocused: Bool

    var onToggleEdit: () -> Void = {}
    var onCancelEdit: () -> Void = {}
    var onSaveEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onOpenInCompose: (() -> Void)? = nil
    var isDirty: Bool = false
    var onTitleChange: (() -> Void)? = nil

    private let repository = TalkieObjectRepository()

    /// Tracks which tool button (if any) is currently hovered. Drives the
    /// idle → ink contrast jump that the studio's `ToolButton` does on
    /// hover; the Swift port previously collapsed both states into a
    /// single dim foreground, which is why the buttons read as faint
    /// chrome instead of interactive controls.
    @State private var hoveredLabel: String? = nil
    @State private var overflowHovered: Bool = false

    /// Briefly flips the Copy chip to "COPIED" after a successful copy,
    /// then reverts. Mirrors the studio's `studioCopyButton` pattern.
    @State private var copied: Bool = false

    // MARK: - Body
    //
    // Composition (studio MacMemoDetail.tsx — one-to-one):
    //   Toolbar (printer's slug) — sequence · type ……… Star · Pin · Share · Export · ⋯
    //   Hairline
    //   Masthead — eyebrow row · serif headline 34pt · byline (provenance · duration)

    var body: some View {
        if isAlwaysEditable {
            // Notes: no title header — the NoteComposeCard first line IS the title.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                toolbarSlug
                hairline
                masthead
                    .padding(.horizontal, MastheadLayout.horizontalPadding)
                    .padding(.top, MastheadLayout.topPadding)
                    .padding(.bottom, MastheadLayout.bottomPadding)
            }
        }
    }

    // MARK: - Layout constants
    //
    // Mirrors design/studio/components/studies/MacMemoDetail.tsx
    // `px-9` (36px horizontal), `pt-8 pb-6` (32 top / 24 bottom on masthead),
    // `px-9 py-3` (36 horizontal / 12 vertical on toolbar).
    private enum MastheadLayout {
        static let horizontalPadding: CGFloat = 36
        static let topPadding: CGFloat = 32
        static let bottomPadding: CGFloat = 24
        static let toolbarVerticalPadding: CGFloat = 10
    }

    // MARK: - Toolbar slug

    @ViewBuilder
    private var toolbarSlug: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(sequenceLabel)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2.0)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.55))

            Text("· \(recording.type.displayName.uppercased())")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.55))

            Spacer(minLength: 8)

            if isEditing {
                editingActions
            } else {
                readingActions
            }
        }
        .padding(.horizontal, MastheadLayout.horizontalPadding)
        .padding(.vertical, MastheadLayout.toolbarVerticalPadding)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.current.foreground.opacity(0.10))
            .frame(height: 0.5)
    }

    /// "M-CB0B" / "D-3792" — type letter prefix + first four hex chars
    /// of the UUID. Reads like a catalog number without exposing the
    /// full UUID.
    private var sequenceLabel: String {
        let prefix: String
        switch recording.type {
        case .memo:      prefix = "M"
        case .dictation: prefix = "D"
        case .note:      prefix = "N"
        case .capture:   prefix = "C"
        case .segment:   prefix = "S"
        case .selection: prefix = "X"
        }
        let head = String(recording.id.uuidString.prefix(4))
        return "\(prefix)-\(head)"
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
                .padding(.bottom, 8)
            headlineView
            if !isEditing, let lead = leadParagraph {
                standfirstView(lead)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            } else {
                Color.clear.frame(height: 12)
            }
            bylineRow
        }
    }

    /// Editorial standfirst — the lead paragraph promoted out of the
    /// body and into the masthead area, so the page has a magazine deck
    /// reading between headline and byline. Studio mock's body lead
    /// becomes the masthead's standfirst here.
    private var leadParagraph: String? {
        guard let text = recording.text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // First paragraph by double-newline, falling back to first
        // newline-bounded chunk, then to the whole string.
        let byDouble = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let first = byDouble.first { return first }
        let bySingle = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return bySingle.first ?? trimmed
    }

    private func standfirstView(_ lead: String) -> some View {
        let cue = Text("0:00 · ")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .tracking(2.0)
            .foregroundColor(Color.hex("9A6A22"))

        let prose = Text(lead)
            .font(standfirstFont)
            .foregroundColor(Theme.current.foreground)
            .tracking(-0.1)

        return (cue + prose)
            .lineSpacing(8)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var standfirstFont: Font {
        for name in ["Newsreader-Regular", "Newsreader"] {
            #if os(macOS)
            if NSFont(name: name, size: 18) != nil {
                return .custom(name, size: 18)
            }
            #endif
        }
        return .system(size: 18, weight: .regular, design: .serif)
    }

    // MARK: - Eyebrow

    private var eyebrowRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("· \(recording.type.displayName.uppercased())")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2.0)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.60))

            Rectangle()
                .fill(Theme.current.foreground.opacity(0.12))
                .frame(height: 0.5)

            Text(eyebrowDate(recording.createdAt))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2.0)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.60))
        }
    }

    // MARK: - Headline

    private var headlineView: some View {
        Group {
            if isEditing {
                TextField("Title", text: $editedTitle)
                    .font(serifHeadlineFont)
                    .foregroundColor(Theme.current.foreground)
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .onChange(of: editedTitle) { _, _ in onTitleChange?() }
            } else {
                Text(headerTitle)
                    .font(serifHeadlineFont)
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .tracking(-0.6)            // ~ -0.018em at 34pt
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private var serifHeadlineFont: Font {
        // Prefer Newsreader (bundled in Resources/Fonts) so the headline
        // matches the studio mock literally. SwiftUI's `.serif` design
        // would otherwise resolve to New York at this size.
        for name in ["Newsreader-Medium", "Newsreader-Regular", "Newsreader"] {
            #if os(macOS)
            if NSFont(name: name, size: 34) != nil {
                return .custom(name, size: 34)
            }
            #endif
        }
        return .system(size: 34, weight: .medium, design: .serif)
    }

    // MARK: - Byline

    private var bylineRow: some View {
        HStack(spacing: 8) {
            Text(recording.source.displayName.uppercased())
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Theme.current.foreground)

            if recording.duration > 0 {
                Text("·")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.55))
                Text(formatDuration(recording.duration))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Theme.current.foreground)
                    .monospacedDigit()
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Toolbar Actions

    @ViewBuilder
    private var editingActions: some View {
        HStack(spacing: 8) {
            Button("Cancel") { onCancelEdit() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Theme.current.foregroundSecondary)

            Button("Save") { onSaveEdit() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isDirty)
        }
    }

    @ViewBuilder
    private var readingActions: some View {
        HStack(spacing: 4) {
            toolButton(label: copied ? "COPIED" : "COPY") {
                copyTranscript()
            }
            toolButton(label: "Share") {
                shareRecording()
            }
            toolButton(label: "Export") {
                exportRecording()
            }
            Rectangle()
                .fill(Theme.current.foreground.opacity(0.16))
                .frame(width: 0.5, height: 12)
                .padding(.horizontal, 4)
            overflowMenu
        }
    }

    /// Studio toolbar button — mono-cased, no background.
    /// Idle = `foregroundSecondary` at full opacity; hover = `foreground`
    /// with the weight bumped from `.regular` to `.medium`. The contrast
    /// jump is the affordance; the studio's `ToolButton` does exactly
    /// this on `:hover`.
    private func toolButton(label: String, action: @escaping () -> Void) -> some View {
        let active = hoveredLabel == label
        return Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: active ? .medium : .regular, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(active ? Theme.current.foreground : Theme.current.foregroundSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .animation(.easeOut(duration: 0.12), value: active)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredLabel = isHovering ? label : (hoveredLabel == label ? nil : hoveredLabel)
        }
        .help(label)
    }

    /// Copies the recording's text to the pasteboard and briefly flips
    /// the chip to "COPIED" so the action reads as confirmed.
    private func copyTranscript() {
        guard let text = recording.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeOut(duration: 0.12)) {
            copied = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeOut(duration: 0.18)) {
                copied = false
            }
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button(action: onToggleEdit) { Label("Edit", systemImage: "pencil") }

            Menu("Change Type") {
                ForEach(TalkieObjectType.allCases, id: \.self) { newType in
                    Button {
                        changeType(to: newType)
                    } label: {
                        Label(newType.displayName, systemImage: newType.icon)
                    }
                    .disabled(recording.type == newType)
                }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(recording.id.uuidString, forType: .string)
            } label: {
                Label("Copy ID", systemImage: "number")
            }

            if let onOpenInCompose {
                Button(action: onOpenInCompose) {
                    Label("Open in Compose", systemImage: "square.and.pencil")
                }
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Text("⋯")
                .font(.system(size: 13, weight: overflowHovered ? .medium : .regular))
                .foregroundColor(overflowHovered ? Theme.current.foreground : Theme.current.foregroundSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .animation(.easeOut(duration: 0.12), value: overflowHovered)
        }
        .menuStyle(.borderlessButton)
        .onHover { overflowHovered = $0 }
        .fixedSize()
    }

    // MARK: - Share / Export

    private func shareRecording() {
        guard let text = recording.text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func exportRecording() {
        guard let text = recording.text, !text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (recording.title ?? recording.id.uuidString.prefix(8).description) + ".txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Computed

    private var headerTitle: String {
        if recording.isDictation {
            return formatDateProminent(recording.createdAt)
        }

        if let title = recording.title, !title.isEmpty {
            return title
        }

        switch recording.type {
        case .note:
            return "Untitled Note"
        case .memo:
            return "Untitled Memo"
        case .segment:
            return "Untitled Segment"
        case .dictation:
            return formatDateProminent(recording.createdAt)
        case .selection:
            return formatDateProminent(recording.createdAt)
        case .capture:
            return "Untitled Capture"
        }
    }

    // MARK: - Actions

    private func changeType(to newType: TalkieObjectType) {
        guard newType != recording.type else { return }
        Task {
            do {
                var updated = recording
                updated.type = newType
                updated.lastModified = Date()

                switch (recording.type, newType) {
                case (.note, .memo), (.dictation, .memo):
                    updated.promotedAt = Date()
                    updated.cloudSyncedAt = nil
                case (.memo, .note), (.memo, .dictation):
                    updated.cloudSyncedAt = nil
                default:
                    break
                }

                try await repository.saveRecording(updated)
                await RecordingsViewModel.shared.loadRecordings()
                log.info("Changed recording \(recording.id) type from \(recording.type.rawValue) to \(newType.rawValue)")
            } catch {
                log.error("Failed to change type: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Formatting

    /// Eyebrow date — "TODAY · 10:58 AM", "YESTERDAY · 4:32 PM", "MAY 18 · 9:14 AM",
    /// uppercase to read as caps chrome rather than prose.
    private func eyebrowDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        let prefix: String
        if calendar.isDateInToday(date) {
            prefix = "TODAY"
        } else if calendar.isDateInYesterday(date) {
            prefix = "YESTERDAY"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEE"
            prefix = formatter.string(from: date).uppercased()
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d"
            prefix = formatter.string(from: date).uppercased()
        } else {
            formatter.dateFormat = "MMM d, yyyy"
            prefix = formatter.string(from: date).uppercased()
        }
        formatter.dateFormat = "h:mm a"
        return "\(prefix) · \(formatter.string(from: date).uppercased())"
    }

    /// Headline / title fallback — same logic as before, used when the
    /// recording has no user-set title.
    private func formatDateProminent(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday at' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE 'at' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        }

        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Metadata Row

/// Structured metadata cells aligned with the secondary band (filter bar height).
/// Each cell is a discrete chip showing one facet of the recording's identity.
struct TOMetadataRow: View {
    let recording: TalkieObject
    let settings: SettingsManager

    @State private var copiedRefID = false

    private var typeColor: Color {
        switch recording.type {
        case .memo: .blue
        case .dictation: .cyan
        case .note: .orange
        case .segment: .gray
        case .selection: .teal
        case .capture: .pink
        }
    }

    private var sourceIcon: String {
        switch recording.source {
        case .mac: "desktopcomputer"
        case .iphone: "iphone"
        case .watch: "applewatch"
        case .live: "mic.fill"
        }
    }

    private var sourceLabel: String {
        recording.source.displayName
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Type cell
            metadataCell {
                HStack(spacing: 4) {
                    Image(systemName: recording.type.icon)
                    Text(recording.type.displayName)
                }
                .foregroundColor(typeColor)
            }

            cellDivider

            // Source cell
            metadataCell {
                HStack(spacing: 4) {
                    Image(systemName: sourceIcon)
                    Text(sourceLabel)
                }
            }

            cellDivider

            // Date cell
            metadataCell {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(formatDate(recording.createdAt))
                }
            }

            // Duration cell — only for types with audio, not notes
            if !recording.isNote && recording.duration > 0 {
                cellDivider

                metadataCell {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDuration(recording.duration))
                            .monospacedDigit()
                    }
                }
            }

            // Word count cell
            if recording.wordCount > 0 {
                cellDivider

                metadataCell {
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                        Text("\(recording.wordCount) words")
                    }
                }
            }

            cellDivider

            // Ref cell — truncated UUID, click to copy full ID
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(recording.id.uuidString, forType: .string)
                copiedRefID = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedRefID = false }
            } label: {
                metadataCell {
                    HStack(spacing: 4) {
                        Image(systemName: copiedRefID ? "checkmark" : "number")
                        Text(recording.id.uuidString.prefix(8).lowercased())
                            .monospaced()
                    }
                    .foregroundColor(copiedRefID ? .green : Theme.current.foregroundMuted)
                }
            }
            .buttonStyle(.plain)
            .help("Copy full ID")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: RecordingsHeaderLayout.secondaryBandHeight)
    }

    // MARK: - Cell Components

    private func metadataCell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(settings.fontXS)
            .foregroundColor(Theme.current.foregroundSecondary)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Theme.current.foregroundMuted.opacity(0.3))
            .frame(width: BorderWidth.thin, height: 12)
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today,' h:mm a"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday,' h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d, h:mm a"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }

        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
