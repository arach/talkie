//
//  ScopeNoteDetailView.swift
//  Talkie
//
//  Editorial detail surface for a single Note. Used by ScopeLibraryView
//  when the selected item's type is .note, replacing TalkieView (which
//  carries audio chrome that doesn't apply to notes).
//
//  Studio source of truth:
//    design/studio/components/studies/MacNoteDetail.tsx
//
//  Composition: toolbar → eyebrow + serif title + mono byline →
//  comfortable body measure with marginal rule → right margin column
//  (provenance + tags) → attachment rail at the foot (replaces the
//  player rail).
//
//  Palette: PEARL (#F5F8FA pane) on FROST (#F9FBFC canvas). Cool tones,
//  less cream than the warm family. Amber stays as the single accent.
//

import SwiftUI
import TalkieKit

// MARK: - Local tokens (warm cream family — consistent with the rest of Scope)

private enum NoteToken {
    static let page       = Color.hex("FBFBFA") // cream canvas
    static let pane       = Color.hex("FAF7EF") // pane interior
    static let chrome     = Color.hex("F4F1EA") // chrome / divider bar
    static let rail       = Color.hex("F2EDDE") // bottom attachment rail
    static let ink        = Color.hex("2A2620")
    static let inkFaint   = Color(red: 42/255, green: 38/255, blue: 32/255).opacity(0.55)
    static let inkFainter = Color(red: 42/255, green: 38/255, blue: 32/255).opacity(0.32)
    static let inkRule    = Color(red: 42/255, green: 38/255, blue: 32/255).opacity(0.16)
    static let inkRuleS   = Color(red: 42/255, green: 38/255, blue: 32/255).opacity(0.10)
    static let edge       = Color.hex("E0DCD3")
    static let ruleSoft   = Color.hex("ECE7DD")
    static let amber      = Color.hex("C47D1C")
    static let brass      = Color.hex("9A6A22")
    static let noteTint   = Color.hex("6B7A75")
    static let captureTint = Color.hex("5A7A86")
}

// MARK: - Typography helpers

private enum NoteFont {
    static func display(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight, design: .serif)
    }
    static func displayItalic(size: CGFloat) -> Font {
        Font.system(size: size, weight: .regular, design: .serif).italic()
    }
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - View

struct ScopeNoteDetailView: View {
    let note: TalkieObject

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Margin column scales with width — 220pt at narrow, up to 300pt wide.
            let marginWidth: CGFloat = max(200, min(300, width * 0.18))
            let bodyPad: CGFloat = width < 1300 ? 56 : (width * 0.06)
            let proseMax: CGFloat = min(720, width - marginWidth - bodyPad * 2 - 40)

            VStack(spacing: 0) {
                // Top toolbar removed — actions migrated to the side
                // rail (marginColumn) where they sit alongside provenance
                // and stats. The eyebrow inside the body column carries
                // the sequence + channel that the toolbar used to show.
                HStack(alignment: .top, spacing: 0) {
                    bodyColumn(bodyPad: bodyPad, proseMax: max(400, proseMax))
                    marginColumn(width: marginWidth)
                }
                attachmentRail(bodyPad: bodyPad)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(NoteToken.pane)
        }
    }

    // MARK: - Computed display data

    private var sequence: String {
        "N-" + String(abs(note.id.hashValue) % 10000).leftPadded(to: 4, with: "0")
    }

    private var channelLabel: String {
        "CH-04 · NOTE"
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = .current
        if Calendar.current.isDateInToday(note.createdAt) { return "Today" }
        if Calendar.current.isDateInYesterday(note.createdAt) { return "Yesterday" }
        f.dateFormat = "MMM d"
        return f.string(from: note.createdAt)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: note.createdAt)
    }

    private var bylineText: String {
        let words = note.wordCount
        let screenshots = note.screenshots.count
        let parts: [String] = [
            "\(words) word\(words == 1 ? "" : "s")",
            "\(screenshots) attachment\(screenshots == 1 ? "" : "s")",
            "edited \(dateLabel.lowercased()) · \(timeLabel)"
        ]
        return parts.joined(separator: " · ")
    }

    private var bodyParagraphs: [String] {
        let raw = note.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            return ["(empty note — add content to start)"]
        }
        return raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Sections


    @ViewBuilder
    private func bodyColumn(bodyPad: CGFloat, proseMax: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow — sequence + channel on the left, date/time on
            // the right. Replaces the old top toolbar's identity strip.
            HStack(spacing: 10) {
                Text(sequence)
                    .font(NoteFont.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(NoteToken.noteTint)
                Text("· \(channelLabel)")
                    .font(NoteFont.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(NoteToken.inkFaint)
                Rectangle().fill(NoteToken.inkRuleS).frame(height: 0.5)
                Text("\(dateLabel) · \(timeLabel)")
                    .font(NoteFont.mono(size: 9))
                    .tracking(1.8)
                    .foregroundStyle(NoteToken.inkFaint)
            }

            // Title
            Text(note.displayTitle)
                .font(NoteFont.display(size: 26, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(NoteToken.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            // Byline
            Text(bylineText)
                .font(NoteFont.mono(size: 10))
                .tracking(1.6)
                .foregroundStyle(NoteToken.inkFaint)
                .padding(.top, 6)

            // Body — measure-capped. System sans (SF Pro) at regular
            // weight throughout. The earlier serif lead read heavy on
            // macOS rendering; switching to sans with more line spacing
            // gives the note body the airier feel intentional notes
            // want — closer to a notebook page than a printed article.
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 13.5, weight: .regular, design: .default))
                        .foregroundStyle(NoteToken.ink.opacity(0.88))
                        .lineSpacing(7)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: proseMax, alignment: .leading)
            .overlay(alignment: .leading) {
                // Marginal rule — like a printed page's gutter. Softer
                // now that the prose itself is lighter.
                Rectangle()
                    .fill(NoteToken.noteTint.opacity(0.22))
                    .frame(width: 1)
                    .offset(x: -16)
            }
            .padding(.top, 28)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, bodyPad)
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func marginColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            actionsBlock
            metaBlock(
                title: "Provenance",
                rows: [
                    ("created", "\(dateLabel) · \(timeLabel)", false),
                    ("source", note.source.displayName, false),
                ]
            )
            if note.wordCount > 0 {
                metaBlock(
                    title: "Stats",
                    rows: [
                        ("words", "\(note.wordCount)", true),
                        ("attachments", "\(note.screenshots.count)", false),
                    ]
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 20)
        .padding(.trailing, 32)
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(width: width, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle().fill(NoteToken.inkRuleS).frame(width: 1)
        }
    }

    @ViewBuilder
    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("· ACTIONS")
                .font(NoteFont.mono(size: 8.5, weight: .semibold))
                .tracking(2.8)
                .foregroundStyle(NoteToken.inkFaint)
                .padding(.bottom, 4)
            NoteRailAction(label: "Edit",   icon: "pencil",                 isPrimary: true, action: {})
            NoteRailAction(label: "Star",   icon: "star",                   action: {})
            NoteRailAction(label: "Pin",    icon: "pin",                    action: {})
            NoteRailAction(label: "Share",  icon: "square.and.arrow.up",    action: {})
            NoteRailAction(label: "Export", icon: "arrow.down.doc",         action: {})
            Rectangle().fill(NoteToken.inkRuleS).frame(height: 0.5)
                .padding(.vertical, 4)
            NoteRailAction(label: "More",   icon: "ellipsis",               action: {})
        }
    }

    @ViewBuilder
    private func metaBlock(title: String, rows: [(String, String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· \(title.uppercased())")
                .font(NoteFont.mono(size: 8.5, weight: .semibold))
                .tracking(2.8)
                .foregroundStyle(NoteToken.inkFaint)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .font(NoteFont.mono(size: 9))
                            .tracking(1.4)
                            .foregroundStyle(NoteToken.inkFaint)
                        Spacer()
                        Text(row.1)
                            .font(NoteFont.mono(size: 10))
                            .tracking(0.6)
                            .foregroundStyle(row.2 ? NoteToken.brass : NoteToken.ink)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentRail(bodyPad: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Text("· ATTACHMENTS")
                    .font(NoteFont.mono(size: 9, weight: .semibold))
                    .tracking(2.8)
                    .foregroundStyle(NoteToken.inkFaint)
                Text("\(note.screenshots.count)")
                    .font(NoteFont.mono(size: 9))
                    .foregroundStyle(NoteToken.inkFaint)
            }
            if note.screenshots.isEmpty {
                Text("none yet")
                    .font(NoteFont.displayItalic(size: 11))
                    .foregroundStyle(NoteToken.inkFainter)
            } else {
                ForEach(Array(note.screenshots.prefix(6).enumerated()), id: \.offset) { _, ss in
                    attachmentChip(filename: ss.filename, meta: "\(ss.width ?? 0)×\(ss.height ?? 0)")
                }
            }
            Spacer()
            Button(action: {}) {
                Text("+ ADD")
                    .font(NoteFont.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(NoteToken.noteTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(NoteToken.inkRule, lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, bodyPad)
        .padding(.vertical, 14)
        .background(
            Rectangle().fill(NoteToken.rail)
                .overlay(Rectangle().fill(NoteToken.inkRuleS).frame(height: 1), alignment: .top)
        )
    }

    @ViewBuilder
    private func attachmentChip(filename: String, meta: String) -> some View {
        HStack(spacing: 8) {
            Text("▢")
                .font(NoteFont.mono(size: 11))
                .foregroundStyle(NoteToken.captureTint)
            VStack(alignment: .leading, spacing: 1) {
                Text(filename)
                    .font(.system(size: 11))
                    .foregroundStyle(NoteToken.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(meta.uppercased())
                    .font(NoteFont.mono(size: 8.5))
                    .tracking(1.4)
                    .foregroundStyle(NoteToken.inkFaint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(NoteToken.captureTint.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(NoteToken.captureTint.opacity(0.28), lineWidth: 0.5)
                )
        )
        .frame(maxWidth: 220)
    }
}

// MARK: - Side-rail action row
//
// Full-width row in the margin column. Icon + label, hover background.
// Primary action (Edit) gets an amber accent so the most common action
// reads first.

private struct NoteRailAction: View {
    let label: String
    let icon: String
    var isPrimary: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
                    .frame(width: 14, alignment: .center)
                Text(label)
                    .font(.system(size: 12, weight: isPrimary ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0; if hovered { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var foregroundColor: Color {
        if isPrimary { return hovered ? NoteToken.amber : NoteToken.brass }
        if hovered { return NoteToken.ink }
        return NoteToken.inkFaint
    }

    private var backgroundFill: Color {
        if isPrimary {
            return hovered ? NoteToken.amber.opacity(0.14) : NoteToken.amber.opacity(0.07)
        }
        return hovered ? NoteToken.inkRuleS : Color.clear
    }
}

// MARK: - String helper

private extension String {
    func leftPadded(to length: Int, with pad: Character) -> String {
        guard count < length else { return self }
        return String(repeating: pad, count: length - count) + self
    }
}
