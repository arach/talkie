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

    /// On-demand JSON inspector toggle. When the overflow menu's
    /// "View as JSON" item flips this to true the transcript section
    /// renders the JSON payload; otherwise the body reads as the normal
    /// editorial document. Replaces the persistent TEXT/JSON tab pair.
    var showJSON: Binding<Bool>? = nil

    var onToggleEdit: () -> Void = {}
    var onCancelEdit: () -> Void = {}
    var onSaveEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onOpenInCompose: (() -> Void)? = nil
    /// Memo-only — when set, surfaces a "Continue" chip in the inline
    /// action row. Migrated out of the transcript-card's bottom overlay,
    /// which was clipping the label and leaving a stranded red dot.
    var onContinueMemo: (() -> Void)? = nil
    var isDirty: Bool = false
    var showSavedBadge: Bool = false
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
    // Mirrors design/studio/components/studies/MacMemoDetail.tsx but
    // with a touch more breathing room than the studio numbers. Extra
    // pre-toolbar space gives the slug clearance from the chrome bar's
    // Talkie pill; extra masthead bottom puts air between the byline
    // and the body so the title block reads as a distinct beat.
    private enum MastheadLayout {
        static let horizontalPadding: CGFloat = 36
        static let topPadding: CGFloat = 28
        static let bottomPadding: CGFloat = 36
        // Toolbar carries only the catalog number now (actions moved
        // inline beneath the byline) — its breathing budget can shrink.
        static let toolbarTopPadding: CGFloat = 16
        static let toolbarBottomPadding: CGFloat = 6
    }

    // MARK: - Toolbar slug

    @ViewBuilder
    private var toolbarSlug: some View {
        HStack(alignment: .center, spacing: 12) {
            // Catalog-number only at the top. Editorial actions
            // (Copy / Share / Export / ⋯) migrated to an inline row
            // beneath the byline so the document context owns them.
            Text(sequenceLabel)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(2.2)
                .foregroundColor(sequenceTint)

            Spacer(minLength: 8)

            if isEditing {
                editingActions
            }
        }
        .padding(.horizontal, MastheadLayout.horizontalPadding)
        .padding(.top, MastheadLayout.toolbarTopPadding)
        .padding(.bottom, MastheadLayout.toolbarBottomPadding)
    }

    /// Sequence label tint by item type. Adds a quiet identifier color
    /// to the catalog number so M-/D-/N-/C- read distinctly without
    /// adding chrome. Matches the kind-letter tints used in the Library
    /// list rows.
    private var sequenceTint: Color {
        ThemedScopeAccent.kind(for: recording.type)
    }

    private var hairline: some View {
        ThemedScopeRule(.section)
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
            if !isEditing {
                inlineActionRow
                    .padding(.top, 14)
            }
        }
    }

    /// Editorial standfirst — the lead paragraph promoted out of the
    /// body and into the masthead area, so the page has a magazine deck
    /// reading between headline and byline. Studio mock's body lead
    /// becomes the masthead's standfirst here.
    ///
    /// For long memos (>400 words) the standfirst is skipped entirely:
    /// the body will chunk and render the full transcript with proper
    /// paragraph breaks, and we don't want the masthead to swallow the
    /// whole wall of text via the "no-newline → whole-blob" fallback.
    private var leadParagraph: String? {
        guard recording.wordCount <= 400 else { return nil }
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
            .foregroundColor(ThemedScopeAccent.brass)

        // Softened from full foreground to 0.78 so the standfirst reads
        // as editorial prose, not bolded headline weight. Combined with
        // the slightly wider line spacing it breathes.
        let prose = Text(lead)
            .font(standfirstFont)
            .foregroundColor(Theme.current.foreground.opacity(0.78))
            .tracking(-0.1)

        return (cue + prose)
            .lineSpacing(9)
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
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("· \(recording.type.displayName.uppercased())")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.62))

            ThemedScopeRule(.subtle)

            // Editorial italic instead of mono — adds magazine cadence
            // between the structural eyebrow and the serif headline below.
            Text(eyebrowDate(recording.createdAt))
                .font(eyebrowItalicFont)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.70))

            saveStatusChip
                .animation(.easeInOut(duration: 0.2), value: isDirty)
                .animation(.easeInOut(duration: 0.2), value: showSavedBadge)
        }
    }

    /// Tiny save-state chip near the title. `Saving…` while there are
    /// unsaved local edits; flips to `✓ Saved` for ~1.5s after a write
    /// commits, then clears. Empty otherwise — so the eyebrow only grows
    /// in length when there's actual saving activity to surface.
    @ViewBuilder
    private var saveStatusChip: some View {
        if isDirty {
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.current.foregroundMuted)
                    .frame(width: 5, height: 5)
                Text("SAVING…")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
            .transition(.opacity)
        } else if showSavedBadge {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                Text("SAVED")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundColor(Color.green.opacity(0.82))
            .transition(.opacity)
        } else {
            EmptyView()
        }
    }

    /// Italic Newsreader at the eyebrow size. Falls back to the system
    /// serif italic if Newsreader-Italic isn't loaded.
    private var eyebrowItalicFont: Font {
        for name in ["Newsreader-Italic", "Newsreader-RegularItalic"] {
            #if os(macOS)
            if NSFont(name: name, size: 12) != nil {
                return .custom(name, size: 12)
            }
            #endif
        }
        return .system(size: 12, weight: .regular, design: .serif).italic()
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
                .tracking(1.8)
                .foregroundColor(Theme.current.foreground.opacity(0.78))

            if recording.duration > 0 {
                bylineDot
                Text(formatDuration(recording.duration))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Theme.current.foreground.opacity(0.78))
                    .monospacedDigit()
            }

            // Word count — adds a useful piece of context to the byline
            // without expanding the line beyond mono caps. Falls back to
            // the duration-only byline for items with no text.
            if recording.wordCount > 0 {
                bylineDot
                Text("\(recording.wordCount) WORDS")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Theme.current.foreground.opacity(0.78))
                    .monospacedDigit()
            }
        }
        .padding(.top, 6)
    }

    private var bylineDot: some View {
        Text("·")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundColor(Theme.current.foregroundSecondary.opacity(0.48))
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
        // Legacy in-toolbar action group — kept here only so the
        // editing-actions branch can fall back to it if needed.
        // The reading-mode inline action row is `inlineActionRow`.
        HStack(spacing: 4) { EmptyView() }
    }

    /// Inline action row beneath the byline. Replaces the COPY · SHARE
    /// · EXPORT · ⋯ cluster that used to hang in the top-right of the
    /// pane. Reads as "tools for the document just identified above,"
    /// not corner chrome. Copy is the primary action (amber); the rest
    /// are secondary mono chips; ⋯ overflow holds Edit / Change Type /
    /// Delete / Copy ID / View as JSON.
    @ViewBuilder
    private var inlineActionRow: some View {
        // Pared row (2026-05-21): the Continue affordance lives as a
        // centered standalone CTA above the bottom delete row now (it's
        // the primary "add more to this memo" intent, not a peer of
        // Copy/Share/Export). The JSON toggle migrated onto the
        // transcript card itself so the affordance sits where its effect
        // lives. `onContinueMemo` and `showJSON` remain on the API for
        // call-site compatibility but no longer render here.
        HStack(spacing: 8) {
            inlineActionButton(label: copied ? "COPIED" : "COPY",
                               icon: "doc.on.doc",
                               isPrimary: true,
                               action: copyTranscript)
            inlineActionButton(label: "Share",
                               icon: "square.and.arrow.up",
                               action: shareRecording)
            inlineActionButton(label: "Export",
                               icon: "arrow.down.doc",
                               action: exportRecording)
            // JSON lives here in the top action row — it's a view of the
            // whole payload (a peer of Copy/Share/Export), not a
            // transcript-section affordance.
            if let showJSON {
                jsonToggleChip(showJSON: showJSON)
            }
            Spacer(minLength: 8)
            overflowMenu
        }
    }

    /// Continue-memo chip — replaces the stranded red dot that used to
    /// float between sections. Red-tinted to stay recognizable as "this
    /// continues the recording" without mimicking the primary amber.
    @ViewBuilder
    private func continueChip(action: @escaping () -> Void) -> some View {
        let active = hoveredLabel == "Continue"
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                Text("CONTINUE")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundColor(active ? Color.red : Color.red.opacity(0.85))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.red.opacity(active ? 0.14 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.red.opacity(active ? 0.45 : 0.28), lineWidth: 0.5)
                    )
            )
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLabel = hovering ? "Continue" : (hoveredLabel == "Continue" ? nil : hoveredLabel)
            NSCursor.pointingHand.set(); if !hovering { NSCursor.arrow.set() }
        }
        .help("Continue this memo")
    }

    /// View-as-JSON toggle — promoted out of the overflow menu so the
    /// state is visible at a glance and one click away. Becomes the
    /// active/lit state when JSON view is on, so the chip itself
    /// reflects which mode the body is in.
    @ViewBuilder
    private func jsonToggleChip(showJSON: Binding<Bool>) -> some View {
        let on = showJSON.wrappedValue
        let active = hoveredLabel == "JSON"
        Button {
            showJSON.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "doc.text" : "curlybraces")
                    .font(.system(size: 11, weight: .regular))
                Text(on ? "TEXT" : "JSON")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundColor(
                on
                    ? ThemedScopeAccent.brass
                    : (active ? Theme.current.foreground : Theme.current.foregroundSecondary)
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(on
                        ? ThemedScopeAccent.brass.opacity(0.10)
                        : (active ? Theme.current.foreground.opacity(0.06) : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(
                                on
                                    ? ThemedScopeAccent.brass.opacity(0.45)
                                    : (active ? Theme.current.foreground.opacity(0.16) : Theme.current.foreground.opacity(0.10)),
                                lineWidth: 0.5
                            )
                    )
            )
            .animation(.easeOut(duration: 0.12), value: active)
            .animation(.easeOut(duration: 0.12), value: on)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLabel = hovering ? "JSON" : (hoveredLabel == "JSON" ? nil : hoveredLabel)
            NSCursor.pointingHand.set(); if !hovering { NSCursor.arrow.set() }
        }
        .help(on ? "View as text" : "View as JSON")
    }

    /// Single inline action chip. Mono caps label + SF Symbol glyph,
    /// hover background, primary tinted amber.
    @ViewBuilder
    private func inlineActionButton(
        label: String,
        icon: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let active = hoveredLabel == label
        let amber = ThemedScopeAccent.amber
        let brass = ThemedScopeAccent.brass
        let fg: Color = {
            if isPrimary { return active ? amber : brass }
            return active ? Theme.current.foreground : Theme.current.foregroundSecondary
        }()
        let bg: Color = {
            if isPrimary { return active ? amber.opacity(0.14) : amber.opacity(0.07) }
            return active ? Theme.current.foreground.opacity(0.06) : Color.clear
        }()
        let border: Color = {
            if isPrimary { return active ? amber.opacity(0.55) : amber.opacity(0.32) }
            return active ? Theme.current.foreground.opacity(0.16) : Theme.current.foreground.opacity(0.10)
        }()

        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isPrimary ? .semibold : .regular))
                Text(label.uppercased())
                    .font(.system(size: 9.5,
                                  weight: isPrimary ? .semibold : .medium,
                                  design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundColor(fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(border, lineWidth: 0.5)
                    )
            )
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLabel = hovering ? label : (hoveredLabel == label ? nil : hoveredLabel)
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .help(label)
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

            // View as JSON promoted out of the overflow menu and into
            // the inline action row as `jsonToggleChip` — kept here as a
            // keyboard-menu fallback only would just re-bloat the
            // overflow, so dropped.

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
        // Dictations don't carry a user-set title. Derive a short
        // headline from the first sentence of the transcript so the
        // title doesn't repeat the eyebrow's "TODAY · 12:16 AM" stamp.
        // Falls back to the timestamp only when there's no text yet.
        if recording.isDictation {
            if let text = recording.text,
               let derived = deriveDictationHeadline(from: text) {
                return derived
            }
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

    /// First-sentence headline derivation for dictations. Cuts at the
    /// first sentence terminator, capped at ~9 words, trims trailing
    /// punctuation. Returns nil if the transcript is empty / unusable.
    private func deriveDictationHeadline(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // First sentence: take up to the first . ! ? (excluding trailing
        // ellipses we'll trim later).
        let terminators: Set<Character> = [".", "!", "?"]
        var firstSentence = trimmed
        if let idx = trimmed.firstIndex(where: { terminators.contains($0) }) {
            firstSentence = String(trimmed[..<idx])
        }

        // Cap at 9 words so the headline fits one line at 34pt serif.
        let words = firstSentence.split(separator: " ").prefix(9)
        guard !words.isEmpty else { return nil }
        var headline = words.joined(separator: " ")

        // Trim hanging conjunctions / fragments at the end.
        let hanging: Set<String> = ["and", "but", "or", "so", "if", "when", "to", "of", "the", "a", "an"]
        while let last = headline.split(separator: " ").last,
              hanging.contains(last.lowercased()) {
            headline = headline
                .split(separator: " ")
                .dropLast()
                .joined(separator: " ")
        }

        // Add an ellipsis if we truncated the source.
        let originalWordCount = trimmed.split(separator: " ").count
        if originalWordCount > 9 && !headline.hasSuffix("…") {
            headline += "…"
        }

        return headline.isEmpty ? nil : headline
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
        ThemedScopeRule(.subtle, axis: .vertical)
            .frame(height: 12)
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
