//
//  ScopeNotesScreen.swift
//  Talkie macOS
//
//  Notes as a distinct surface (not a Library filter). Renders a
//  two-column "Sheaf" grid of compact note cards — a wall of scraps
//  on cream paper. Each card carries the note's structural
//  particulars; tapping a card navigates to the detail surface.
//
//  Studio source of truth:
//    design/studio/app/mac-notes/page.tsx — Variant II (Sheaf).
//
//  Only mounted when SettingsManager.shared.isScopeTheme is true.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Scope display fonts
// Mirrors the helper used by other Scope surfaces. Cormorant Garamond
// is the studio's `--font-display-modern`; falls back to system serif.
// Display font lookup centralized in ScopeType.display(size:weight:) — see TalkieKit/UI/ScopeDesign.swift.

// MARK: - ScopeNotesScreen

struct ScopeNotesScreen: View {
    @Environment(SettingsManager.self) private var settings
    private var viewModel = RecordingsViewModel.shared

    private var notes: [TalkieObject] {
        viewModel.recordings
            .filter { $0.type == .note }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var totalWords: Int {
        notes.reduce(0) { $0 + $1.wordCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScopeTopBand(
                title: "Notes",
                chrome: chromeText
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow

                    if notes.isEmpty {
                        emptyState
                    } else {
                        sheafGrid
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
        .task {
            if viewModel.recordings.isEmpty {
                await viewModel.loadRecordings()
            }
        }
    }

    private var chromeText: String {
        if notes.isEmpty { return "READY" }
        return notes.count == 1 ? "1 NOTE" : "\(notes.count) NOTES"
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("· NOTES · SHEAF ·")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)

            Rectangle()
                .fill(ScopeInk.faint.opacity(0.16))
                .frame(height: 0.5)

            Text(headerByline)
                .font(ScopeType.display(size: 13).italic())
                .foregroundStyle(ScopeInk.faint)
        }
    }

    private var headerByline: String {
        if notes.isEmpty {
            return "showing examples · your notes will land here"
        }
        let nounWord = notes.count == 1 ? "entry" : "entries"
        let wordWord = totalWords == 1 ? "word" : "words"
        return "\(notes.count) \(nounWord) · \(totalWords) \(wordWord)"
    }

    // MARK: - Grid

    private var sheafGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 28),
                GridItem(.flexible(), spacing: 28),
            ],
            spacing: 22
        ) {
            ForEach(notes, id: \.id) { note in
                SheafCard(note: note, onTap: {
                    NavigationState.shared.navigateToMemo(note.id)
                })
            }
        }
    }

    // MARK: - Empty state — placeholder sheaf

    /// When there are no real notes, render the Sheaf with three example
    /// cards demonstrating Talkie's note content types: typed thought,
    /// voice + transcript, and pinned screenshot. The header byline
    /// frames them as examples so the user knows they're not real data.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 28),
                    GridItem(.flexible(), spacing: 28),
                ],
                spacing: 22
            ) {
                ForEach(Self.placeholderNotes) { ph in
                    PlaceholderSheafCard(note: ph)
                }
            }
            .padding(.top, 24)

            // Tail caption — a quiet bottom line that grounds the
            // placeholders. The chrome bar TALKIE pill is one entry
            // point; Compose drafts another; ⇧⌃⌥⌘S is the capture.
            HStack(spacing: 14) {
                Text("HOW NOTES GET HERE")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)

                Rectangle()
                    .fill(ScopeInk.faint.opacity(0.10))
                    .frame(height: 0.5)
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 10) {
                placeholderRoute(
                    glyph: "✎",
                    label: "Type or paste",
                    detail: "Compose anything in Compose. Save with ⌘S — it lands as a note."
                )
                placeholderRoute(
                    glyph: "♪",
                    label: "Dictate aloud",
                    detail: "Hold ⌃⇧⌘ D in Compose to dictate inline. Audio attaches alongside the transcript."
                )
                placeholderRoute(
                    glyph: "▢",
                    label: "Capture the screen",
                    detail: "Press ⇧⌃⌥⌘ S to capture a region or window. The screenshot files itself as a note."
                )
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func placeholderRoute(glyph: String, label: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(glyph)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.hex("9A6A22"))
                .frame(width: 20, alignment: .leading)

            Text(label)
                .font(ScopeType.display(size: 15, weight: .medium))
                .foregroundStyle(ScopeInk.primary)
                .frame(width: 160, alignment: .leading)

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.faint)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Placeholder data

    fileprivate struct PlaceholderNote: Identifiable {
        let id: String
        let title: String
        let dayLabel: String
        let timeLabel: String
        let body: String
        let voiceDuration: String?
        let hasImg: Bool
    }

    private static let placeholderNotes: [PlaceholderNote] = [
        .init(
            id: "ph1",
            title: "Build a tiny landing for the Beta",
            dayLabel: "TODAY",
            timeLabel: "9:14 AM",
            body: "Hero copy, three anchor links, footer with the terms link. Keep the whole thing under one scroll — anything below the fold gets ignored on first visit anyway.",
            voiceDuration: nil,
            hasImg: false
        ),
        .init(
            id: "ph2",
            title: "Pricing — yearly vs monthly",
            dayLabel: "YESTERDAY",
            timeLabel: "3:42 PM",
            body: "Yearly should bundle the team seats. Actually let me think out loud about this — the conversion lift on annual is real but only if the bundle isn't an obvious downgrade from buying monthly.",
            voiceDuration: "1:14",
            hasImg: false
        ),
        .init(
            id: "ph3",
            title: "Wireframe for the inspector pane",
            dayLabel: "MON",
            timeLabel: "11:58 AM",
            body: "Right column fixed at 220pt, content column takes the rest. Margin rail carries Filed / Runtime / Source; technical groups migrate over once the rail proves itself.",
            voiceDuration: nil,
            hasImg: true
        ),
    ]
}

// MARK: - Placeholder card

/// Visually identical to SheafCard but inert — no tap action, no
/// navigation, and a slightly lower body opacity so it reads as a
/// preview rather than your own data.
private struct PlaceholderSheafCard: View {
    let note: ScopeNotesScreen.PlaceholderNote
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Eyebrow
            HStack(spacing: 8) {
                Text(note.dayLabel)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(ScopeInk.faint.opacity(0.55))

                Text("·")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint.opacity(0.35))

                Text(note.timeLabel)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(ScopeInk.faint.opacity(0.55))
                    .monospacedDigit()

                if attachmentSummary != nil {
                    Text("·")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ScopeInk.faint.opacity(0.35))
                    Text(attachmentSummary!)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(Color.hex("9A6A22").opacity(0.85))
                }
            }

            // Title
            Text(note.title)
                .font(ScopeType.display(size: 17, weight: .medium))
                .foregroundStyle(ScopeInk.primary)
                .tracking(-0.2)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Body
            Text(note.body)
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.faint)
                .lineSpacing(2)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // Attachment row
            attachmentRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(hovered ? ScopeAmber.tintSubtle : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(ScopeInk.faint.opacity(0.10), lineWidth: 0.5)
        )
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder
    private var attachmentRow: some View {
        if note.voiceDuration != nil || note.hasImg {
            HStack(spacing: 6) {
                if let duration = note.voiceDuration {
                    chip(glyph: "♪", label: duration, accent: true)
                }
                if note.hasImg {
                    chip(glyph: nil, label: "IMG", accent: false)
                }
            }
        }
    }

    private func chip(glyph: String?, label: String, accent: Bool) -> some View {
        HStack(spacing: 4) {
            if let glyph {
                Text(glyph)
                    .font(.system(size: 9))
                    .foregroundStyle(accent ? ScopeAmber.solid : ScopeInk.subtle)
            }
            Text(label)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(ScopeInk.faint.opacity(0.75))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(ScopeCanvas.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(ScopeInk.faint.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var attachmentSummary: String? {
        var parts: [String] = []
        if note.voiceDuration != nil { parts.append("voice") }
        if note.hasImg { parts.append("img") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Sheaf card

private struct SheafCard: View {
    let note: TalkieObject
    let onTap: () -> Void

    @State private var hovered = false

    private static let cardCornerRadius: CGFloat = 3
    private static let cardMinHeight: CGFloat = 140

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                eyebrow
                title
                bodyExcerpt
                Spacer(minLength: 0)
                attachmentRow
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: Self.cardMinHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                    .fill(hovered ? ScopeAmber.tintSubtle : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                    .stroke(ScopeInk.faint.opacity(0.10), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    // MARK: - Pieces

    private var eyebrow: some View {
        HStack(spacing: 8) {
            Text(dateLabel)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(ScopeInk.faint.opacity(0.65))

            Text("·")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(ScopeInk.faint.opacity(0.45))

            Text(timeLabel)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(ScopeInk.faint.opacity(0.65))
                .monospacedDigit()

            if attachmentSummary != nil {
                Text("·")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint.opacity(0.45))
                Text(attachmentSummary!)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Color.hex("9A6A22"))
            }
        }
    }

    private var title: some View {
        Text(displayTitle)
            .font(ScopeType.display(size: 17, weight: .medium))
            .foregroundStyle(ScopeInk.primary)
            .tracking(-0.2)
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodyExcerpt: some View {
        Group {
            if let excerpt = bodyText, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: 12))
                    .foregroundStyle(ScopeInk.faint)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Empty note.")
                    .font(.system(size: 12).italic())
                    .foregroundStyle(ScopeInk.faint.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var attachmentRow: some View {
        if note.duration > 0 || hasScreenshots {
            HStack(spacing: 6) {
                if note.duration > 0 {
                    attachmentChip(
                        glyph: "♪",
                        label: formatDuration(note.duration),
                        accent: true
                    )
                }
                if hasScreenshots {
                    attachmentChip(
                        glyph: nil,
                        label: "IMG",
                        accent: false
                    )
                }
            }
        }
    }

    private func attachmentChip(glyph: String?, label: String, accent: Bool) -> some View {
        HStack(spacing: 4) {
            if let glyph {
                Text(glyph)
                    .font(.system(size: 9))
                    .foregroundStyle(accent ? ScopeAmber.solid : ScopeInk.subtle)
            }
            Text(label)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(ScopeInk.faint.opacity(0.75))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(ScopeCanvas.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(ScopeInk.faint.opacity(0.14), lineWidth: 0.5)
        )
    }

    // MARK: - Derived

    private var displayTitle: String {
        if let title = note.title, !title.isEmpty { return title }
        if let preview = note.transcriptPreview, !preview.isEmpty {
            return preview
        }
        return "Untitled note"
    }

    /// Body excerpt — when the title comes from `note.title`, use the
    /// transcript text as the body; when the title is already a preview
    /// of the text, fall back to the remainder.
    private var bodyText: String? {
        let raw = note.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        if let title = note.title, !title.isEmpty, !raw.hasPrefix(title) {
            return raw
        }
        // Title is null or matches start of text — drop the title-equivalent
        // first line so the excerpt doesn't repeat.
        let lines = raw.components(separatedBy: .newlines)
        let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? raw : rest
    }

    private var hasScreenshots: Bool {
        // Conservative — we don't have a screenshot count surfaced on
        // TalkieObject yet, so leave this false for now. Wired through
        // when the screenshot-attachment field lands.
        false
    }

    private var attachmentSummary: String? {
        var parts: [String] = []
        if note.duration > 0 {
            parts.append("voice")
        }
        if hasScreenshots {
            parts.append("img")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var dateLabel: String {
        let fmt = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(note.createdAt) {
            return "Today".uppercased()
        }
        if cal.isDateInYesterday(note.createdAt) {
            return "Yesterday".uppercased()
        }
        fmt.dateFormat = "EEE d"
        return fmt.string(from: note.createdAt).uppercased()
    }

    private var timeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: note.createdAt)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    ScopeNotesScreen()
        .environment(SettingsManager.shared)
        .frame(width: 1000, height: 800)
}
