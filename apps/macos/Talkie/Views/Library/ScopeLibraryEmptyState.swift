//
//  ScopeLibraryEmptyState.swift
//  Talkie
//
//  The Library "no-selection" detail pane.
//
//  Earlier this pane reprinted the rail: today's items + this-week's
//  items as two agendas — a second list of the same rows already in the
//  sidebar, with no new context. The studio reframe (design/studio →
//  /mac-library-empty, "Overview" variant) replaced that with a pane
//  that does what the rail CAN'T:
//
//    · Frontispiece   — monumental date + a one-line read of the day.
//    · Activity strip — a quiet sparkline of the day's shape (the rail
//                       has no sense of when you were active).
//    · Distribution   — the mix: channels when the day spans more than
//                       one, otherwise top sources (which apps).
//    · Highlights     — 2–3 *curated* cards (freshest capture w/ a real
//                       thumbnail, longest dictation, a recent note),
//                       never all N rows.
//
//  Everything derives from the passed-in `recordings`, which is the
//  list's *visible* (scope-filtered) set — so ALL / Captures-only /
//  Memos-only adapt for free: a captures-only day has one channel, so
//  the distribution shows sources, and the highlights are all captures.
//
//  When the scope has no items, the pane shows the genuine zero-state —
//  a quiet, inviting canvas — instead of a sad placeholder.
//

import SwiftUI
import AppKit
import ImageIO
import TalkieKit

struct ScopeLibraryEmptyState: View {
    let recordings: [TalkieObject]
    var filter: RecordingTypeFilter = .all
    var onSelectRecording: (UUID) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                Group {
                    if recordings.isEmpty {
                        EmptyInvite(filter: filter)
                            .frame(maxWidth: .infinity, minHeight: max(360, geo.size.height - 8))
                    } else {
                        OverviewDigest(
                            items: dayItems,
                            day: dayDate,
                            isToday: Calendar.current.isDateInToday(dayDate),
                            filter: filter,
                            libraryCount: recordings.count,
                            width: geo.size.width,
                            onSelect: onSelectRecording
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Day selection
    // Summarize the most recent day that has activity (today when it has
    // items). A single day keeps the activity strip honest and the
    // frontispiece focused.

    private var dayBuckets: [(day: Date, items: [TalkieObject])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: recordings) { cal.startOfDay(for: $0.createdAt) }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    private var dayDate: Date { dayBuckets.first?.day ?? Date() }
    private var dayItems: [TalkieObject] { dayBuckets.first?.items ?? [] }
}

// MARK: - Item classification

private enum ItemKind { case capture, voice, note }

private func kind(of item: TalkieObject) -> ItemKind {
    switch item.type {
    case .capture, .selection: return .capture
    case .note: return .note
    default:
        if item.duration > 0 || item.isDictation || item.isMemo || item.hasAudio { return .voice }
        return .note
    }
}

private func sourceLabel(_ item: TalkieObject) -> String {
    if let app = item.appContext?.name, !app.isEmpty { return app }
    return item.source.displayName
}

// MARK: - Overview digest

private struct OverviewDigest: View {
    let items: [TalkieObject]
    let day: Date
    let isToday: Bool
    let filter: RecordingTypeFilter
    let libraryCount: Int
    let width: CGFloat
    let onSelect: (UUID) -> Void

    private var padX: CGFloat { width < 560 ? 28 : 56 }
    private var highlightContentWidth: CGFloat { max(0, width - (padX * 2)) }
    private var highlightColumns: Int {
        if highlightContentWidth >= 540 { return 3 }
        if highlightContentWidth >= 350 { return 2 }
        return 1
    }
    private var highlightCardWidth: CGFloat {
        let gaps = CGFloat(max(0, highlightColumns - 1)) * 16
        let distributedWidth = (highlightContentWidth - gaps) / CGFloat(highlightColumns)
        return min(230, distributedWidth)
    }

    private var captureCount: Int { items.filter { kind(of: $0) == .capture }.count }
    private var voiceCount: Int { items.filter { kind(of: $0) == .voice }.count }
    private var noteCount: Int { items.filter { kind(of: $0) == .note }.count }

    private var channels: [(label: String, count: Int, tint: Color)] {
        [
            ("Captures", captureCount, ScopeKind.capture),
            ("Voice", voiceCount, ScopeKind.dict),
            ("Notes", noteCount, ScopeKind.note),
        ].filter { $0.count > 0 }
    }
    private var multiChannel: Bool { channels.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            frontispiece

            ActivityStrip(items: items)
                .padding(.top, 24)

            distribution
                .padding(.top, 26)

            highlights
                .padding(.top, 30)

            Spacer(minLength: 28)

            footer
                .padding(.top, 8)
        }
        .padding(.horizontal, padX)
        .padding(.vertical, 44)
    }

    // ── Frontispiece ────────────────────────────────────────────────

    private var frontispiece: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(headlineDate(day))
                .font(ScopeType.display(size: 52))
                .tracking(-1.0)
                .foregroundStyle(Color.primary)
            Text(byline)
                .font(ScopeType.display(size: 16).italic())
                .foregroundStyle(ScopeInk.faint)
            Spacer(minLength: 0)
        }
    }

    private var byline: String {
        let dow = isToday ? "Today" : dayOfWeek(day)
        let onlyCaptures = captureCount > 0 && voiceCount == 0 && noteCount == 0
        let onlyVoice = voiceCount > 0 && captureCount == 0 && noteCount == 0
        let onlyNotes = noteCount > 0 && captureCount == 0 && voiceCount == 0

        if onlyCaptures {
            let apps = Set(items.map(sourceLabel)).count
            return "\(dow) · \(captureCount) capture\(plural(captureCount)) · \(apps) app\(plural(apps))"
        }
        if onlyVoice {
            let runtime = items.reduce(0) { $0 + $1.duration }
            let words = items.reduce(0) { $0 + $1.wordCount }
            return "\(dow) · \(voiceCount) recording\(plural(voiceCount)) · \(durationLong(runtime)) · \(words) word\(plural(words))"
        }
        if onlyNotes {
            let words = items.reduce(0) { $0 + $1.wordCount }
            return "\(dow) · \(noteCount) note\(plural(noteCount)) · \(words) word\(plural(words))"
        }
        return "\(dow) · \(items.count) items across \(channels.count) channels"
    }

    // ── Distribution ────────────────────────────────────────────────

    @ViewBuilder
    private var distribution: some View {
        if multiChannel {
            HStack(alignment: .top, spacing: 40) {
                channelsBlock
                sourcesBlock(limit: 3)
            }
        } else {
            sourcesBlock(limit: 5)
        }
    }

    private var channelsBlock: some View {
        let maxCount = max(1, channels.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("· CHANNELS")
            VStack(alignment: .leading, spacing: 9) {
                ForEach(channels, id: \.label) { ch in
                    HStack(spacing: 10) {
                        Text(ch.label.uppercased())
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.normal)
                            .foregroundStyle(ScopeInk.muted)
                            .frame(width: 64, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ScopeInk.faint.opacity(0.12))
                                Capsule().fill(ch.tint.opacity(0.65))
                                    .frame(width: max(3, g.size.width * CGFloat(ch.count) / CGFloat(maxCount)))
                            }
                        }
                        .frame(height: 6)
                        Text("\(ch.count)")
                            .font(ScopeType.display(size: 15, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(ScopeInk.primary)
                            .frame(width: 26, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourcesBlock(limit: Int) -> some View {
        let sources = topSources(limit: limit)
        return VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("· TOP SOURCES")
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(sources.enumerated()), id: \.offset) { _, src in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(ScopeInk.faint.opacity(0.55))
                            .frame(width: 6, height: 6)
                        Text(src.name.uppercased())
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.normal)
                            .foregroundStyle(ScopeInk.muted)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(src.count)")
                            .font(ScopeType.display(size: 15, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(ScopeInk.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func topSources(limit: Int) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for it in items { counts[sourceLabel(it), default: 0] += 1 }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { (name: $0.key, count: $0.value) }
    }

    // ── Highlights ──────────────────────────────────────────────────

    private var highlights: some View {
        let picks = Array(curatedHighlights().prefix(highlightColumns))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                sectionEyebrow("· HIGHLIGHTS")
                Text("what stood out — not everything")
                    .font(ScopeType.display(size: 12).italic())
                    .foregroundStyle(ScopeInk.faint)
                Rectangle().fill(ScopeInk.faint.opacity(0.12)).frame(height: 0.5)
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(picks, id: \.item.id) { pick in
                    HighlightCard(item: pick.item, eyebrow: pick.eyebrow, onTap: { onSelect(pick.item.id) })
                        .frame(width: highlightCardWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Curated, kind-appropriate highlights. Superlatives first (longest
    /// dictation / freshest capture / recent note), then fill from the
    /// dominant kind so a single-channel day still shows three real cards.
    private func curatedHighlights() -> [(item: TalkieObject, eyebrow: String)] {
        let captures = items.filter { kind(of: $0) == .capture }.sorted { $0.createdAt > $1.createdAt }
        let voice = items.filter { kind(of: $0) == .voice }.sorted { $0.duration > $1.duration }
        let notes = items.filter { kind(of: $0) == .note }
            .sorted { ($0.wasPromoted ? 1 : 0, $0.createdAt) > ($1.wasPromoted ? 1 : 0, $1.createdAt) }

        var out: [(TalkieObject, String)] = []
        var seen = Set<UUID>()
        func add(_ item: TalkieObject?, _ eyebrow: String) {
            guard let item, !seen.contains(item.id) else { return }
            out.append((item, eyebrow)); seen.insert(item.id)
        }

        add(voice.first, voice.first?.isMemo == true ? "LONGEST MEMO" : "LONGEST DICTATION")
        add(captures.first, "FRESHEST CAPTURE")
        add(notes.first, notes.first?.wasPromoted == true ? "PROMOTED NOTE" : "RECENT NOTE")

        // Fill from the dominant kind (e.g. a captures-only day → 3 shots).
        let dominant = [captures, voice, notes].max { $0.count < $1.count } ?? []
        for item in dominant where out.count < 3 {
            add(item, sourceLabel(item).uppercased())
        }
        return out
    }

    // ── Footer ──────────────────────────────────────────────────────

    private var footer: some View {
        HStack {
            sectionEyebrow("· LIBRARY")
            Spacer()
            Text("\(libraryCount) item\(plural(libraryCount)) in view")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(ScopeInk.faint.opacity(0.14)).frame(height: 0.5).offset(y: -12)
        }
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(ScopeType.eyebrow)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(ScopeInk.faint)
    }
}

// MARK: - Activity strip
// A quiet sparkline of the day's shape: faint bars per active hour on a
// hairline baseline. No box, no accent — deliberately not an instrument.

private struct ActivityStrip: View {
    let items: [TalkieObject]

    private var buckets: [Int] {
        var b = Array(repeating: 0, count: 24)
        let cal = Calendar.current
        for it in items {
            let h = cal.component(.hour, from: it.createdAt)
            if (0..<24).contains(h) { b[h] += 1 }
        }
        return b
    }

    private var busiestLabel: String {
        let b = buckets
        guard let peak = b.indices.max(by: { b[$0] < b[$1] }), b[peak] > 0 else { return "" }
        return "busiest \(hourAMPM(peak))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("· ACTIVITY")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
                if !busiestLabel.isEmpty {
                    Text(busiestLabel)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(ScopeInk.subtle)
                }
            }

            Canvas { ctx, size in
                let baseY = size.height
                let cellW = size.width / 24
                // baseline
                ctx.fill(Path(CGRect(x: 0, y: baseY - 0.5, width: size.width, height: 0.5)),
                         with: .color(ScopeInk.faint.opacity(0.30)))
                // noon tick
                ctx.fill(Path(CGRect(x: size.width / 2 - 0.25, y: baseY - 4, width: 0.5, height: 4)),
                         with: .color(ScopeInk.subtle))
                // bars
                let b = buckets
                let maxV = max(1, b.max() ?? 1)
                for h in 0..<24 where b[h] > 0 {
                    let frac = CGFloat(b[h]) / CGFloat(maxV)
                    let barH = 6 + frac * 14
                    let x = cellW * CGFloat(h) + cellW / 2 - 1.5
                    let rect = CGRect(x: x, y: baseY - barH, width: 3, height: barH)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(ScopeInk.faint))
                }
            }
            .frame(height: 22)

            HStack {
                Text("12 AM")
                Spacer()
                Text("NOON")
                Spacer()
                Text("11 PM")
            }
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(ScopeInk.subtle)
        }
    }

    private func hourAMPM(_ h: Int) -> String {
        let am = h < 12
        let hr = h % 12 == 0 ? 12 : h % 12
        return "\(hr) \(am ? "AM" : "PM")"
    }
}

// MARK: - Highlight card

private struct HighlightCard: View {
    let item: TalkieObject
    let eyebrow: String
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                media
                    .aspectRatio(2, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(eyebrow)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(ScopeBrass.deep)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(timeOfDay(item.createdAt))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                    }
                    Text(title)
                        .font(ScopeType.display(size: 15))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metaLine)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.normal)
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered ? ScopeAmber.tintSubtle : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .modifier(CaptureRowDragModifier(fileURL: draggableURL))
    }

    @ViewBuilder
    private var media: some View {
        if let asset = CaptureMediaFileResolver.primaryMedia(for: item) {
            OverviewCaptureThumb(media: asset)
        } else if kind(of: item) == .voice {
            PaperTile(content: .waveform(seed: item.id.uuidString.hashValue))
        } else {
            PaperTile(content: .lines)
        }
    }

    private var draggableURL: URL? {
        CaptureMediaFileResolver.primaryMedia(for: item)?.url
    }

    private var title: String {
        if let t = item.title, !t.isEmpty { return t }
        if let p = item.transcriptPreview, !p.isEmpty { return p }
        return "Untitled \(item.type.displayName)"
    }

    private var metaLine: String {
        var parts = [item.type.displayName.uppercased(), sourceLabel(item).uppercased()]
        switch kind(of: item) {
        case .capture:
            break // source + kind carry it; the thumbnail is the content
        case .voice:
            if item.duration > 0 { parts.append(durationShort(item.duration)) }
            if item.wordCount > 0 { parts.append("\(item.wordCount)W") }
        case .note:
            if item.wordCount > 0 { parts.append("\(item.wordCount)W") }
        }
        return parts.joined(separator: " · ")
    }

    private func timeOfDay(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Capture thumbnail (real screenshot, async + cached)

private struct OverviewCaptureThumb: View {
    let media: CaptureMediaAsset
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(ScopeCanvas.canvasAlt)

            if let image {
                Image(nsImage: image)
                    .interpolation(.medium)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                Image(systemName: media.isVideo ? "play.rectangle" : "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ScopeInk.subtle)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(ScopeEdge.normal, lineWidth: 0.6)
        )
        .overlay(alignment: .topTrailing) {
            if media.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 1)
                    .padding(6)
            }
        }
        .shadow(color: ScopeInk.primary.opacity(0.08), radius: 3, y: 1.5)
        .task(id: media.url.path) { await load() }
    }

    private func load() async {
        let key = media.url.path as NSString
        if let cached = overviewThumbCache.object(forKey: key) {
            image = cached; return
        }
        let loaded: NSImage?
        switch media {
        case .image(let url):
            loaded = await downsampleImage(url, maxPixel: 480)
        case .video(let url):
            loaded = await VideoFrameThumbnailer.thumbnailAsync(for: url, maxSize: 480)
        }
        guard !Task.isCancelled else { return }
        if let loaded { overviewThumbCache.setObject(loaded, forKey: key) }
        image = loaded
    }
}

private let overviewThumbCache: NSCache<NSString, NSImage> = {
    let c = NSCache<NSString, NSImage>()
    c.countLimit = 60
    return c
}()

private func downsampleImage(_ url: URL, maxPixel: Int) async -> NSImage? {
    await Task.detached(priority: .utility) { () -> NSImage? in
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }.value
}

// MARK: - Paper tile (non-visual highlight stand-in)

private struct PaperTile: View {
    enum Content { case waveform(seed: Int), lines }
    let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(ScopeCanvas.surface)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(ScopeEdge.normal, lineWidth: 0.6)

            switch content {
            case .waveform(let seed):
                OverviewWaveform(seed: seed, color: ScopeKind.dict)
                    .frame(height: 28)
                    .padding(.horizontal, 22)
            case .lines:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([0.68, 0.92, 0.80, 0.54], id: \.self) { w in
                        Capsule().fill(ScopeInk.faint.opacity(0.22))
                            .frame(width: nil, height: 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .scaleEffect(x: w, anchor: .leading)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

private struct OverviewWaveform: View {
    let seed: Int
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: UInt64(bitPattern: Int64(seed)))
            let barCount = 22
            let gap: CGFloat = 2
            let barWidth = (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            for index in 0..<barCount {
                let x = CGFloat(index) * (barWidth + gap)
                let unit = CGFloat(rng.nextUnit())
                let height = max(4, size.height * (0.22 + unit * 0.70))
                let y = (size.height - height) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                ctx.fill(path, with: .color(color.opacity(index % 3 == 0 ? 0.8 : 0.5)))
            }
        }
        .allowsHitTesting(false)
    }

    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
        mutating func nextUnit() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
    }
}

// MARK: - Empty invite (true zero-state)

private struct EmptyInvite: View {
    let filter: RecordingTypeFilter

    private var noun: String {
        switch filter {
        case .all: return ""
        case .memos: return "memos"
        case .dictations: return "dictations"
        case .captures: return "captures"
        case .notes: return "notes"
        }
    }

    private var headline: String {
        noun.isEmpty ? "Nothing here yet." : "No \(noun) yet."
    }

    private var subtitle: String {
        switch filter {
        case .all: return "Your memos, dictations, notes, and captures will collect here as you go."
        case .captures: return "Screenshots and clips you take will collect here."
        case .notes: return "Notes you write or promote will collect here."
        default: return "Recordings you make will collect here."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("· LIBRARY")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)

            // Tape at rest — the signature held quiet.
            ZStack {
                Rectangle()
                    .fill(ScopeAmber.solid.opacity(0.45))
                    .frame(width: 220, height: 1.5)
                Circle()
                    .fill(ScopeCanvas.canvas)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(ScopeBrass.deep, lineWidth: 1.5))
            }
            .frame(height: 30)
            .padding(.top, 26)
            .padding(.bottom, 30)

            Text(headline)
                .font(ScopeType.display(size: 40, weight: .medium))
                .tracking(-0.5)
                .foregroundStyle(Color.primary)

            Text(subtitle)
                .font(ScopeType.display(size: 16).italic())
                .foregroundStyle(ScopeInk.faint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 12)

            HStack(spacing: 12) {
                StartChip(glyph: "largecircle.fill.circle", label: "Record", hint: "⌘N", primary: true)
                StartChip(glyph: "square.dashed", label: "Capture", hint: "⇧⌘4", primary: false)
            }
            .padding(.top, 30)

            Text("OR PRESS THE TALKIE PILL ANYTIME")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(ScopeInk.subtle)
                .padding(.top, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

private struct StartChip: View {
    let glyph: String
    let label: String
    let hint: String
    let primary: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(primary ? ScopeBrass.deep : ScopeInk.faint)
            Text(label)
                .font(ScopeType.display(size: 15))
                .foregroundStyle(Color.primary)
            Text(hint)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(primary ? ScopeAmber.tint : ScopeCanvas.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(primary ? ScopeAmber.solid.opacity(0.28) : ScopeEdge.normal, lineWidth: 0.6)
        )
    }
}

// MARK: - Shared formatters

private func plural(_ n: Int) -> String { n == 1 ? "" : "s" }

private func headlineDate(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "d MMM"
    return f.string(from: date)
}

private func dayOfWeek(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "EEEE"
    return f.string(from: date)
}

private func durationShort(_ seconds: Double) -> String {
    let total = max(Int(seconds.rounded()), 0)
    return String(format: "%d:%02d", total / 60, total % 60)
}

private func durationLong(_ seconds: Double) -> String {
    let total = max(Int(seconds.rounded()), 0)
    let h = total / 3_600, m = total % 3_600 / 60, s = total % 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m \(s)s" }
    return "\(s)s"
}

// Display font lookup centralized in ScopeType.display(size:weight:) — see TalkieKit/UI/ScopeDesign.swift.
