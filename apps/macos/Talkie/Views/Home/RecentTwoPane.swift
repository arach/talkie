//
//  RecentTwoPane.swift
//  Talkie
//
//  Home's "Recent" section — two parallel panes:
//    Voice (Memos + Dictations) | Content (Captures + Notes)
//
//  Each pane stacks two typed sub-bands with shared row anatomy
//  (glyph + line + meta + when). Empty sub-bands render a CTA row
//  in the same anatomy so the section geometry doesn't shift
//  between "you have items" and "make your first item."
//
//  Studio source of truth:
//    design/studio/components/studies/MacHome.tsx (v4)
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Fonts
//
// Studio's `font-display` is Cormorant Garamond, `font-mono` is
// JetBrains Mono. Mirroring those here (with system fallbacks) so the
// SwiftUI surface reads the same as the web view.
private enum RecentFont {
    static func display(size: CGFloat, medium: Bool = false) -> Font {
        for name in (medium
                     ? ["CormorantGaramond-Medium", "Cormorant Garamond Medium"]
                     : ["CormorantGaramond-Regular", "Cormorant Garamond", "CormorantGaramond"]) {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: medium ? .medium : .regular, design: .serif)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let candidates: [String]
        switch weight {
        case .semibold, .bold:
            candidates = ["JetBrainsMono-SemiBold", "JetBrainsMono-Medium"]
        default:
            candidates = ["JetBrainsMono-Medium", "JetBrainsMono-Regular"]
        }
        for name in candidates {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Models

struct RecentRow: Identifiable {
    let id: UUID
    let glyph: String
    let line: String
    let body: String?
    let meta: String
    let when: String
    let onTap: () -> Void
}

struct RecentCTA {
    let glyph: String
    let label: String
    let kbd: [String]
    let onTap: () -> Void
}

struct RecentSection: Identifiable {
    let id: String
    let eyebrow: String
    let count: String
    let libraryLabel: String
    let onLibrary: () -> Void
    let rows: [RecentRow]
    let emptyCTA: RecentCTA
}

// MARK: - Tokens

private enum RecentPaneTokens {
    static let voiceTint   = ScopeBrass.solid
    static let contentTint = ScopeKind.note
    static let cardBg      = Color.white.opacity(0.40)
    static let hoverBg     = Color(red: 0.95, green: 0.95, blue: 0.94).opacity(0.5)
}

// MARK: - TwoPane container

struct RecentTwoPaneSection: View {
    let voiceSections: [RecentSection]
    let contentSections: [RecentSection]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RecentPane(
                label: "Voice",
                tint: RecentPaneTokens.voiceTint,
                sections: voiceSections
            )
            RecentPane(
                label: "Content",
                tint: RecentPaneTokens.contentTint,
                sections: contentSections
            )
        }
    }
}

// MARK: - Pane

private struct RecentPane: View {
    let label: String
    let tint: Color
    let sections: [RecentSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader
            ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                RecentSubBand(section: section, tint: tint, divided: idx > 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(RecentPaneTokens.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(ScopeEdge.normal, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
    }

    private var paneHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(RecentFont.display(size: 14, medium: true))
                .foregroundStyle(ScopeInk.primary)
            Spacer()
            Text("\(sections.reduce(0) { $0 + $1.rows.count }) items".uppercased())
                .font(RecentFont.mono(size: 9, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(ScopeInk.faint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(
            ScopeRule(.section),
            alignment: .bottom
        )
    }
}

// MARK: - SubBand

private struct RecentSubBand: View {
    let section: RecentSection
    let tint: Color
    let divided: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("· \(section.eyebrow.uppercased())")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(ScopeInk.faint)
                Text(section.count.uppercased())
                    .font(RecentFont.mono(size: 9, weight: .medium))
                    .tracking(1.8)
                    .foregroundStyle(ScopeInk.faint)
                Spacer()
                Button(action: section.onLibrary) {
                    Text("\(section.libraryLabel) →")
                        .font(RecentFont.mono(size: 8, weight: .semibold))
                        .tracking(2.0)
                        .foregroundStyle(ScopeInk.faint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if section.rows.isEmpty {
                EmptyCTARow(cta: section.emptyCTA, tint: tint)
            } else {
                ForEach(section.rows.prefix(3)) { row in
                    RecentRowView(row: row, tint: tint)
                }
            }
        }
        .overlay(
            Group {
                if divided {
                    ScopeRule(.row)
                }
            },
            alignment: .top
        )
    }
}

private struct RecentRowView: View {
    let row: RecentRow
    let tint: Color
    @State private var hovered = false

    var body: some View {
        Button(action: row.onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.glyph)
                    .font(RecentFont.mono(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.line)
                        .font(.system(size: 12))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(1)
                    if let body = row.body, !body.isEmpty {
                        Text(body)
                            .font(.system(size: 11))
                            .foregroundStyle(ScopeInk.faint)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if !row.meta.isEmpty {
                        Text(row.meta.uppercased())
                            .font(RecentFont.mono(size: 9, weight: .medium))
                            .tracking(1.6)
                            .foregroundStyle(ScopeInk.faint)
                    }
                    Text(row.when.uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(ScopeInk.subtle)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(hovered ? RecentPaneTokens.hoverBg : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .overlay(
            ScopeRule(.subtle),
            alignment: .top
        )
    }
}

private struct EmptyCTARow: View {
    let cta: RecentCTA
    let tint: Color
    @State private var hovered = false

    var body: some View {
        Button(action: cta.onTap) {
            HStack(spacing: 10) {
                Text(cta.glyph)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(tint)
                Text(cta.label.uppercased())
                    .font(RecentFont.mono(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(ScopeInk.primary)
                Text("→")
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeInk.faint)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(cta.kbd, id: \.self) { k in
                        Text(k)
                            .font(RecentFont.mono(size: 9, weight: .semibold))
                            .frame(minWidth: 14, minHeight: 14)
                            .padding(.horizontal, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(ScopeEdge.subtle, lineWidth: 0.5)
                                    )
                            )
                            .foregroundStyle(ScopeInk.faint)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(hovered ? RecentPaneTokens.hoverBg : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .overlay(
            ScopeRule(.row),
            alignment: .top
        )
    }
}
