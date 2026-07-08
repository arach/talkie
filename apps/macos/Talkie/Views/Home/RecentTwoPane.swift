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

enum RecentRowMedia {
    case waveform(seed: Int, strength: Double)
    case thumbnail(URL)
}

struct RecentRow: Identifiable {
    let id: UUID
    let glyph: String
    let line: String
    let body: String?
    let media: RecentRowMedia?
    let meta: String
    let secondaryMeta: String?
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
        media: RecentRowMedia? = nil,
        meta: String,
        secondaryMeta: String? = nil,
        when: String,
        onTap: @escaping () -> Void,
        menuActions: [RecentMenuItem] = [],
        shortcutNumber: Int? = nil
    ) {
        self.id = id
        self.glyph = glyph
        self.line = line
        self.body = body
        self.media = media
        self.meta = meta
        self.secondaryMeta = secondaryMeta
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
    let detail: String?
    let onTap: () -> Void

    init(
        glyph: String,
        label: String,
        kbd: [String],
        detail: String? = nil,
        onTap: @escaping () -> Void
    ) {
        self.glyph = glyph
        self.label = label
        self.kbd = kbd
        self.detail = detail
        self.onTap = onTap
    }
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
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
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

// MARK: - Header link
//
// "ALL MEMOS →" style trailing link. Idle it sits at whatever ink the
// section hands it; on hover it lifts to brass — the page's standing
// quiet-action color — instead of a fill, so header chrome stays flat.
private struct RecentHeaderLink: View {
    let label: String
    let idleColor: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("\(label) →")
                .font(RecentFont.mono(size: 8, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(isHovered ? ScopeBrass.solid : idleColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
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
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(RecentPaneTokens.cardBg)
        )
        // Clip before the border: the header cap band and row hover
        // fills are square rectangles that would otherwise poke past
        // the rounded corners.
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        // Whisper-level cap band (the library's bgSunk idiom) so the
        // Voice / Content headers read as the card's cap, not another
        // row. Appearance-agnostic: primary ink darkens light panes,
        // lightens dark ones.
        .background(ScopeInk.primary.opacity(0.02))
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
                // The middot carries the section's tint; the label sits
                // one ink step above the count so the eyebrow anchors
                // the sub-band instead of blending into its metadata.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("·")
                        .foregroundStyle(tint.opacity(0.85))
                    Text(section.eyebrow.uppercased())
                        .foregroundStyle(ScopeInk.muted)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
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
                        RecentHeaderLink(
                            label: secondaryLabel,
                            idleColor: tint.opacity(0.86),
                            action: onSecondary
                        )
                    }
                    RecentHeaderLink(
                        label: section.libraryLabel,
                        idleColor: ScopeInk.faint,
                        action: section.onLibrary
                    )
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
                EmptyCTARow(cta: section.emptyCTA, tint: tint, sectionID: section.id)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var showBadge: Bool { cmdHeld && row.shortcutNumber != nil }

    var body: some View {
        Button(action: row.onTap) {
            rowContent
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .background(isHovered ? rowHoverFill : Color.clear)
            // Leading tick on hover — the ScopeRule(.action) idiom at
            // whisper strength. Marks the active row without lifting
            // or darkening it.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(tint.opacity(isHovered ? 0.55 : 0))
                    .frame(width: 2)
                    .padding(.vertical, 5)
            }
        }
        .buttonStyle(.plain)
        .overlay(ScopeRule(.subtle), alignment: .top)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .modifier(RecentRowContextMenu(actions: row.menuActions))
    }

    @ViewBuilder
    private var rowContent: some View {
        switch row.media {
        case .waveform(let seed, let strength):
            audioRow(seed: seed, strength: strength)
        default:
            compactRow
        }
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 10) {
            marker
            if case .thumbnail(let url) = row.media {
                RecentCaptureThumbnail(url: url, tint: tint)
                    .frame(width: 66, height: 38)
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
            inlineMeta
        }
    }

    private func audioRow(seed: Int, strength: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            playMarker
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    RecentWaveformLine(seed: seed, strength: strength, tint: tint)
                        .frame(height: 18)
                    if !row.meta.isEmpty {
                        Text(row.meta.uppercased())
                            .font(RecentFont.mono(size: 9, weight: .medium))
                            .tracking(1.6)
                            .foregroundStyle(ScopeInk.faint)
                            .frame(minWidth: 42, alignment: .trailing)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.line)
                        .font(RecentFont.display(size: 13))
                        .italic()
                        .foregroundStyle(ScopeInk.dim)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let secondaryMeta = row.secondaryMeta, !secondaryMeta.isEmpty {
                        Text(secondaryMeta.uppercased())
                            .font(RecentFont.mono(size: 8.5, weight: .medium))
                            .tracking(1.5)
                            .foregroundStyle(ScopeInk.faint)
                    }
                    Text(row.when.uppercased())
                        .font(.system(size: 8.5, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(ScopeInk.subtle)
                }
            }
        }
    }

    private var marker: some View {
        Text(row.glyph)
            .font(RecentFont.mono(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .opacity(showBadge ? 0 : 1)
            .frame(width: 14)
            .overlay {
                if showBadge, let n = row.shortcutNumber {
                    CmdGlyphBadge(key: "\(n)").fixedSize()
                }
            }
    }

    private var playMarker: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.88), lineWidth: 1)
            Image(systemName: "play.fill")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(tint)
                .offset(x: 0.5)
        }
        .frame(width: 18, height: 18)
        .opacity(showBadge ? 0 : 1)
        .overlay {
            if showBadge, let n = row.shortcutNumber {
                CmdGlyphBadge(key: "\(n)").fixedSize()
            }
        }
    }

    private var inlineMeta: some View {
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

    private var verticalPadding: CGFloat {
        if case .waveform = row.media { return 8 }
        return row.media == nil ? 8 : 6
    }

    private var rowHoverFill: Color {
        colorScheme == .dark
            ? ScopeAmber.tintSubtle
            : ScopeAmber.solid.opacity(0.055)
    }
}

private struct RecentWaveformLine: View {
    let seed: Int
    let strength: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            // Bar count adapts to the slot so the tape runs edge to
            // edge and the duration label reads as its counter. Pitch:
            // 5pt bars (7pt every 7th) + 3pt gap ≈ 8.3pt per bar —
            // floor keeps the last bar inside the slot.
            let barCount = max(18, Int((geo.size.width + 3) / 8.3))
            ZStack {
                Rectangle()
                    .fill(tint.opacity(0.18))
                    .frame(height: 1)
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(tint.opacity(idx % 5 == 0 ? 0.88 : 0.55))
                            .frame(
                                width: Self.blockWidth(index: idx),
                                height: max(3, geo.size.height * Self.sample(index: idx, seed: seed, strength: strength))
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private static func sample(index: Int, seed: Int, strength: Double) -> Double {
        let normalized = min(1.0, max(0.18, strength))
        let phase = Double(abs(seed % 997)) * 0.013
        let low = (sin(Double(index) * 0.66 + phase) + 1.0) * 0.25
        let high = (sin(Double(index) * 1.71 + phase * 2.3) + 1.0) * 0.17
        let shaped = 0.12 + low + high
        return min(0.88, max(0.16, shaped * (0.50 + normalized * 0.50)))
    }

    private static func blockWidth(index: Int) -> CGFloat {
        index % 7 == 0 ? 7 : 5
    }
}

private struct RecentCaptureThumbnail: View {
    let url: URL
    let tint: Color
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ZStack {
                        ScopeCanvas.surface
                        Image(systemName: "photo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ScopeInk.faint)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tint.opacity(0.40))
                    .frame(height: 1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(ScopeEdge.subtle, lineWidth: 0.5)
            )
            // Barely-there lift so the capture reads as a mounted
            // print on the pane, not a flat inline block.
            .shadow(color: ScopeInk.primary.opacity(0.08), radius: 1.5, y: 1)
        }
        .task(id: url) {
            if let cached = RecentThumbnailCache.image(for: url.path) {
                image = cached
                return
            }
            let thumbnail = await RecentThumbnailLoader.thumbnail(for: url, maxPixelSize: 176)
            guard !Task.isCancelled else { return }
            if let thumbnail {
                RecentThumbnailCache.set(thumbnail, for: url.path)
            }
            image = thumbnail
        }
    }
}

// MARK: - Thumbnail loading
//
// Rows re-render on hover, so thumbnails must stay off the render
// path — `NSImage(contentsOf:)` in `body` was re-decoding the full
// screenshot PNG on every hover flip. Compact mirror of the library
// list's loader: decode a downsampled CGImage off-main, cache by path.
// 176px max edge covers the 66×38pt slot at 2× with fill headroom.

@MainActor
private enum RecentThumbnailCache {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 24
        return cache
    }()

    static func image(for key: String) -> NSImage? {
        images.object(forKey: key as NSString)
    }

    static func set(_ image: NSImage, for key: String) {
        images.setObject(image, forKey: key as NSString)
    }
}

private enum RecentThumbnailLoader {
    static func thumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        let box = await Task.detached(priority: .utility) {
            SendableCGImageBox(decode(url: url, maxPixelSize: maxPixelSize))
        }.value
        guard let cgImage = box.image else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func decode(url: URL, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    private final class SendableCGImageBox: @unchecked Sendable {
        let image: CGImage?

        init(_ image: CGImage?) {
            self.image = image
        }
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
    let sectionID: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: cta.onTap) {
            content
            .padding(.horizontal, 14)
            .padding(.vertical, isRichAction ? 12 : 10)
            .background(isHovered ? hoverFill : Color.clear)
            // Same leading tick as populated rows — the CTA is a row
            // in the shared anatomy, so it hovers like one.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(tint.opacity(isHovered ? 0.55 : 0))
                    .frame(width: 2)
                    .padding(.vertical, 5)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .overlay(
            ScopeRule(.row),
            alignment: .top
        )
    }

    private var content: some View {
        HStack(alignment: isRichAction ? .center : .firstTextBaseline, spacing: 10) {
            if isRichAction {
                actionPreview
            } else {
                Text(cta.glyph)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: isRichAction ? 3 : 0) {
                HStack(spacing: 5) {
                    Text(cta.label.uppercased())
                        .font(RecentFont.mono(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(ScopeInk.primary)
                    Text("→")
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.faint)
                }
                if isRichAction, let detail = cta.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.faint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            if !cta.kbd.isEmpty {
                ShortcutChordBadge(keys: cta.kbd)
            }
        }
        .frame(minHeight: isRichAction ? 42 : 0, alignment: .center)
    }

    @ViewBuilder
    private var actionPreview: some View {
        switch sectionID {
        case "captures":
            CaptureActionGlyph(tint: tint)
                .frame(width: 52, height: 34)
        case "notes":
            NoteActionGlyph(tint: tint)
                .frame(width: 52, height: 34)
        default:
            Text(cta.glyph)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(tint)
                .frame(width: 18)
        }
    }

    private var isRichAction: Bool {
        sectionID == "captures" || sectionID == "notes"
    }

    private var hoverFill: Color {
        colorScheme == .dark
            ? ScopeAmber.tintSubtle
            : ScopeAmber.solid.opacity(0.045)
    }
}

private struct CaptureActionGlyph: View {
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ScopeCanvas.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(ScopeEdge.subtle, lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint.opacity(0.45))
                    .frame(width: 20, height: 4)
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(ScopeInk.primary.opacity(0.10))
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(ScopeInk.primary.opacity(0.06))
                }
            }
            .padding(6)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(tint.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: 18, height: 12)
                .padding(6)
        }
    }
}

private struct NoteActionGlyph: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(ScopeCanvas.surface)
            .overlay(
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<3, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(idx == 0 ? tint.opacity(0.55) : ScopeInk.primary.opacity(0.10))
                            .frame(width: idx == 2 ? 24 : 36, height: 3)
                    }
                }
                .padding(7),
                alignment: .leading
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(ScopeEdge.subtle, lineWidth: 0.5)
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
