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

// MARK: - ⌘-hold environment
//
// While the user holds Command, quick-jump badges fade in over the
// section "ALL …" links (⌘M/⌘D/⌘C/⌘N) and the recent rows (⌘1–9). The
// held state is published from ScopeHomeView through the environment so
// every descendant row/link can react without threading a flag through
// each initializer.
private struct CmdHeldKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var cmdHeld: Bool {
        get { self[CmdHeldKey.self] }
        set { self[CmdHeldKey.self] = newValue }
    }
}

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
    let menuActions: [RecentMenuItem]
    /// 1–9 quick-open number shown while ⌘ is held; nil past the 9th row.
    let shortcutNumber: Int?

    init(
        id: UUID,
        glyph: String,
        line: String,
        body: String?,
        meta: String,
        when: String,
        onTap: @escaping () -> Void,
        menuActions: [RecentMenuItem] = [],
        shortcutNumber: Int? = nil
    ) {
        self.id = id
        self.glyph = glyph
        self.line = line
        self.body = body
        self.meta = meta
        self.when = when
        self.onTap = onTap
        self.menuActions = menuActions
        self.shortcutNumber = shortcutNumber
    }
}

/// Right-click action on a `RecentRow`. `label == ""` renders as a divider so
/// callers can group destructive actions visually without a second type.
struct RecentMenuItem: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
    let role: ButtonRole?
    let handler: () -> Void

    static let divider = RecentMenuItem(label: "", systemImage: "", role: nil, handler: {})

    var isDivider: Bool { label.isEmpty }
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
    let secondaryLabel: String?
    let onSecondary: (() -> Void)?
    let rows: [RecentRow]
    let emptyCTA: RecentCTA
    /// Letter shown in the ⌘-hold badge on the "ALL …" link (⌘+letter
    /// jumps to this section's library). nil → no quick-jump.
    let shortcutLetter: String?

    init(
        id: String,
        eyebrow: String,
        count: String,
        libraryLabel: String,
        onLibrary: @escaping () -> Void,
        secondaryLabel: String? = nil,
        onSecondary: (() -> Void)? = nil,
        rows: [RecentRow],
        emptyCTA: RecentCTA,
        shortcutLetter: String? = nil
    ) {
        self.id = id
        self.eyebrow = eyebrow
        self.count = count
        self.libraryLabel = libraryLabel
        self.onLibrary = onLibrary
        self.secondaryLabel = secondaryLabel
        self.onSecondary = onSecondary
        self.rows = rows
        self.emptyCTA = emptyCTA
        self.shortcutLetter = shortcutLetter
    }
}

// MARK: - Tokens

private enum RecentPaneTokens {
    static let voiceTint   = ScopeBrass.solid
    static let contentTint = ScopeKind.note
    static let cardBg      = ScopeCanvas.pane
    static let hoverBg     = ScopeCanvas.paneHover
}

private extension HomeHoverChromeStyle {
    static func recentPaneRow() -> HomeHoverChromeStyle {
        HomeHoverChromeStyle(
            cornerRadius: 0,
            hoverFill: NSColor(RecentPaneTokens.hoverBg)
        )
    }
}

// MARK: - ⌘ glyph badge
//
// Small ⌘+key chip that fades in while Command is held. Mirrors the
// library's quick-jump badge so the idiom reads identically across the
// app. Purely visual — the actual key binding lives in ScopeHomeView.
private struct CmdGlyphBadge: View {
    let key: String

    var body: some View {
        HStack(spacing: 1) {
            Text("⌘").foregroundColor(ScopeAmber.solid)
            Text(key).foregroundColor(ScopeInk.primary)
        }
        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ScopeCanvas.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(ScopeEdge.normal, lineWidth: 0.5)
        )
        .shadow(color: ScopeInk.primary.opacity(0.10), radius: 2, y: 1)
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
        .allowsHitTesting(false)
    }
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
        .scopeCardBorder(cornerRadius: 6)
        .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
    }

    private var paneHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(RecentFont.display(size: 14, medium: true))
                .foregroundStyle(ScopeInk.primary)
            Spacer()
            // Pluralize correctly — "1 ITEM" not "1 ITEMS".
            let itemCount = sections.reduce(0) { $0 + $1.rows.count }
            Text("\(itemCount) \(itemCount == 1 ? "item" : "items")".uppercased())
                .font(RecentFont.mono(size: 9, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(ScopeInk.faint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(ScopeRule(.section), alignment: .bottom)
    }
}

// MARK: - SubBand

private struct RecentSubBand: View {
    let section: RecentSection
    let tint: Color
    let divided: Bool
    @Environment(\.cmdHeld) private var cmdHeld

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
                // Trailing link cluster (optional secondary + library
                // link). The ⌘ badge floats just left of the whole cluster
                // into the empty Spacer gap — anchored to the cluster's
                // leading and shifted out by its own width, so nothing
                // reflows and it never collides with the secondary link.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let secondaryLabel = section.secondaryLabel, let onSecondary = section.onSecondary {
                        Button(action: onSecondary) {
                            Text("\(secondaryLabel) →")
                                .font(RecentFont.mono(size: 8, weight: .semibold))
                                .tracking(2.0)
                                .foregroundStyle(tint.opacity(0.86))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: section.onLibrary) {
                        Text("\(section.libraryLabel) →")
                            .font(RecentFont.mono(size: 8, weight: .semibold))
                            .tracking(2.0)
                            .foregroundStyle(ScopeInk.faint)
                    }
                    .buttonStyle(.plain)
                }
                .overlay(alignment: .leading) {
                    if cmdHeld, let letter = section.shortcutLetter {
                        CmdGlyphBadge(key: letter)
                            .fixedSize()
                            .alignmentGuide(.leading) { dims in dims.width + 6 }
                    }
                }
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
    @Environment(\.cmdHeld) private var cmdHeld

    private var showBadge: Bool { cmdHeld && row.shortcutNumber != nil }

    var body: some View {
        Button(action: row.onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // ⌘ held: the ⌘N quick-open badge floats *over* the row
                // marker as an overlay — the glyph fades under it so the
                // row text never reflows (badge is wider than the glyph).
                Text(row.glyph)
                    .font(RecentFont.mono(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .opacity(showBadge ? 0 : 1)
                    .overlay {
                        if showBadge, let n = row.shortcutNumber {
                            CmdGlyphBadge(key: "\(n)").fixedSize()
                        }
                    }
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
                // Meta + when inline — was a two-line VStack which wasted
                // vertical space. "73 WORDS · 12:35 PM" on one line reads
                // cleaner and matches how the bottom rows of other
                // surfaces (Library row, sheaf card) present their meta.
                HStack(spacing: 6) {
                    if !row.meta.isEmpty {
                        Text(row.meta.uppercased())
                            .font(RecentFont.mono(size: 9, weight: .medium))
                            .tracking(1.6)
                            .foregroundStyle(ScopeInk.faint)
                        Text("·")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                    }
                    Text(row.when.uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(ScopeInk.subtle)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(HomeHoverChrome(style: .recentPaneRow()))
        }
        .buttonStyle(.plain)
        .overlay(ScopeRule(.subtle), alignment: .top)
        .modifier(RecentRowContextMenu(actions: row.menuActions))
    }
}

private struct RecentRowContextMenu: ViewModifier {
    let actions: [RecentMenuItem]

    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(actions) { item in
                    if item.isDivider {
                        Divider()
                    } else {
                        Button(role: item.role, action: item.handler) {
                            Label(item.label, systemImage: item.systemImage)
                        }
                    }
                }
            }
        }
    }
}

private struct EmptyCTARow: View {
    let cta: RecentCTA
    let tint: Color

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
                if !cta.kbd.isEmpty {
                    ShortcutChordBadge(keys: cta.kbd)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(HomeHoverChrome(style: .recentPaneRow()))
        }
        .buttonStyle(.plain)
        .overlay(
            ScopeRule(.row),
            alignment: .top
        )
    }
}

private struct ShortcutChordBadge: View {
    let keys: [String]

    var body: some View {
        Text(keys.joined(separator: " "))
            .font(RecentFont.mono(size: 8.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(ScopeInk.subtle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ScopeInk.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(ScopeAmber.solid.opacity(0.16), lineWidth: 0.5)
            )
            .fixedSize()
    }
}
