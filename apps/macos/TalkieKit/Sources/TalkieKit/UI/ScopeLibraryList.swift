//
//  ScopeLibraryList.swift
//  TalkieKit
//
//  Shared Scope-styled library presentation. Talkie's Library list and
//  companion surfaces (TalkieAgent's Library page) render TalkieObject
//  rows through the same components so the channel-tagged editorial
//  look stays a single source of truth:
//
//    ScopeLibraryRow          — channel letter, title, chrome line,
//                               time-ago + memo sparkline
//    ScopeLibraryDateBucket   — Today / Yesterday / This week / month
//    ScopeLibraryBucketHeader — eyebrow section header with count
//    ScopeLibraryList         — simple bucketed table for companion
//                               surfaces that don't carry Talkie's
//                               filters, pagination, or inspector
//

import SwiftUI
import AppKit

// MARK: - Date bucket

/// Section-header buckets for library lists. Items are grouped into
/// these buckets in date-descending order; oldest items fall into a
/// month bucket so the list stays tractable for big archives.
public enum ScopeLibraryDateBucket: Hashable {
    case today
    case yesterday
    case thisWeek
    case month(year: Int, month: Int)

    public var label: String {
        switch self {
        case .today: return "TODAY"
        case .yesterday: return "YESTERDAY"
        case .thisWeek: return "THIS WEEK"
        case .month(let y, let m):
            let df = DateFormatter()
            df.dateFormat = "MMM yyyy"
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = 1
            let date = Calendar.current.date(from: comps) ?? Date()
            return df.string(from: date).uppercased()
        }
    }

    public static func bucket(for date: Date, now: Date = Date()) -> ScopeLibraryDateBucket {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        // "This week" = within the last 7 days, not in today / yesterday
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return .thisWeek
        }
        let comps = cal.dateComponents([.year, .month], from: date)
        return .month(year: comps.year ?? 2026, month: comps.month ?? 1)
    }

    public struct Group {
        public let bucket: ScopeLibraryDateBucket
        public let items: [TalkieObject]

        public init(bucket: ScopeLibraryDateBucket, items: [TalkieObject]) {
            self.bucket = bucket
            self.items = items
        }
    }

    /// Group `items` by bucket, preserving the incoming (date-descending)
    /// order both across buckets and within each bucket.
    public static func grouped(_ items: [TalkieObject], now: Date = Date()) -> [Group] {
        var order: [ScopeLibraryDateBucket] = []
        var map: [ScopeLibraryDateBucket: [TalkieObject]] = [:]
        for item in items {
            let bucket = Self.bucket(for: item.createdAt, now: now)
            if map[bucket] == nil {
                order.append(bucket)
                map[bucket] = []
            }
            map[bucket]?.append(item)
        }
        return order.map { Group(bucket: $0, items: map[$0] ?? []) }
    }
}

// MARK: - Bucket header

/// Eyebrow section header for a date bucket: "· TODAY" with the
/// bucket's item count on the trailing edge, faint divider underneath.
public struct ScopeLibraryBucketHeader: View {
    public let bucket: ScopeLibraryDateBucket
    public let count: Int

    public init(bucket: ScopeLibraryDateBucket, count: Int) {
        self.bucket = bucket
        self.count = count
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("· \(bucket.label)")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.muted)
            Spacer()
            Text("\(count)")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
        }
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            ScopeDivider(color: ScopeEdge.faint).padding(.horizontal, 32)
        }
    }
}

// MARK: - Row

/// Compact channel-tagged signal row. The heart of the library: leading
/// channel label (M / D / N / C), title in sans, chrome metadata line,
/// and a right-side detail block (sparkline for memos w/ duration, else
/// word count / time).
public struct ScopeLibraryRow: View {
    public let recording: TalkieObject
    public let isSelected: Bool
    /// 1-9 while ⌘ is held and this row is in the first nine slots.
    /// Nil otherwise — no badge is rendered.
    public let shortcutNumber: Int?
    public let onSelect: () -> Void

    @State private var isHovered = false

    public init(
        recording: TalkieObject,
        isSelected: Bool,
        shortcutNumber: Int? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.recording = recording
        self.isSelected = isSelected
        self.shortcutNumber = shortcutNumber
        self.onSelect = onSelect
    }

    private var channelLetter: String {
        switch recording.type {
        case .memo: return "M"
        case .dictation: return "D"
        case .note: return "N"
        case .capture: return "C"
        case .selection: return "S"
        case .segment: return "·"
        }
    }

    private var channelColor: Color {
        switch recording.type {
        case .memo: return ScopeKind.memo
        case .dictation: return ScopeKind.dict
        case .note: return ScopeKind.note
        case .capture, .selection: return ScopeKind.capture
        default: return ScopeInk.subtle
        }
    }

    private var rowTitle: String {
        if let title = recording.title, !title.isEmpty { return title }

        // Captures: name the source app or capture mode rather than
        // falling through to a generic "(untitled)".
        if recording.type == .capture {
            if let app = recording.appContext?.name, !app.isEmpty {
                return "\(app) capture"
            }
            if let shot = recording.screenshots.first {
                let mode = shot.captureMode.capitalized
                return "\(mode) capture"
            }
            if let clip = recording.clips.first {
                if let app = clip.appName, !app.isEmpty {
                    return "\(app) capture"
                }
                let mode = (clip.captureMode ?? "video").capitalized
                return "\(mode) capture"
            }
            if let context = recording.visualContexts.first {
                if let app = context.appName, !app.isEmpty {
                    return "\(app) capture"
                }
                return "\(context.captureMode.capitalized) capture"
            }
        }

        // Text-bearing items: first sentence reads better than the dumb
        // 80-char prefix from `transcriptPreview`.
        if let text = recording.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return Self.firstSentence(of: text, limit: 80)
        }

        // Recording without a transcript yet — type + duration is more
        // informative than the literal "(untitled)".
        if recording.duration > 0 {
            let kind = recording.type.rawValue.capitalized
            return "\(kind) · \(formatDuration(recording.duration))"
        }

        return "(untitled)"
    }

    /// Returns the first sentence of `text`, or a soft-truncated prefix
    /// when no sentence boundary lands within `limit` characters. A
    /// sentence ends at `.`, `!`, or `?` followed by whitespace.
    private static func firstSentence(of text: String, limit: Int) -> String {
        let cleaned = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let enders: Set<Character> = [".", "!", "?"]
        var end: String.Index? = nil
        for i in cleaned.indices {
            if enders.contains(cleaned[i]) {
                let next = cleaned.index(after: i)
                if next == cleaned.endIndex || cleaned[next].isWhitespace {
                    end = next
                    break
                }
            }
        }

        if let e = end {
            let s = String(cleaned[..<e]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty && s.count <= limit { return s }
        }

        if cleaned.count <= limit { return cleaned }
        let truncated = String(cleaned.prefix(limit))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }

    /// Chrome metadata — type · source · duration · word count.
    private var chromeLine: String {
        var parts: [String] = []
        parts.append(recording.type.rawValue.uppercased())
        if let app = recording.appContext?.name, !app.isEmpty {
            parts.append(app.uppercased())
        } else {
            parts.append(recording.source.displayName.uppercased())
        }
        if recording.duration > 0 {
            parts.append(formatDuration(recording.duration))
        }
        if recording.wordCount > 0 {
            parts.append("\(recording.wordCount)W")
        }
        return parts.joined(separator: " · ")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "0:\(String(format: "%02d", secs))"
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                // Channel tag
                ChannelLabel(
                    channelLetter,
                    color: isSelected ? ScopeAmber.solid : channelColor,
                    strokeColor: isSelected ? ScopeAmber.solid.opacity(0.5) : ScopeEdge.normal
                )
                .frame(width: 26, alignment: .leading)

                if hasVisualPreview {
                    ScopeLibraryMediaThumbnail(recording: recording, isSelected: isSelected)
                }

                // Title + chrome
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(rowTitle)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? ScopeInk.primary : ScopeInk.dim)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if recording.wasRefined {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                                .foregroundStyle(ScopeAmber.solid.opacity(0.7))
                        }
                        if recording.wasPromoted {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(ScopeAmber.solid.opacity(0.7))
                        }
                    }

                    Text(chromeLine)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.normal)
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing: time-ago, plus a fixed-height trace slot. The
                // slot stays reserved (Color.clear) on non-memo rows so the
                // row height is identical across all filter types — the
                // list doesn't visually jolt when toggling between Memos
                // and Notes/Dictations.
                VStack(alignment: .trailing, spacing: 4) {
                    Text(timeAgo)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                    Group {
                        if recording.isMemo && recording.duration > 0 {
                            TraceSparkline(seed: recording.id.uuidString.hashValue)
                                .opacity(isHovered || isSelected ? 1.0 : 0.65)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 56, height: 10)
                }
                .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    ScopeAmber.tintSubtle
                } else if isHovered {
                    ScopeCanvas.canvasOverlay
                }
            }
            .overlay(alignment: .leading) {
                if isSelected || isHovered {
                    Rectangle()
                        .fill(isSelected ? ScopeAmber.solid : ScopeAmber.solid.opacity(0.4))
                        .frame(width: 2)
                }
            }
            .overlay(alignment: .trailing) {
                // ⌘-hold position badge. Lives in the right margin so
                // it doesn't fight the channel label on the left or
                // overlap the time-ago / sparkline in the trailing
                // slot. Fades with the caller's cmd-held animation.
                if let n = shortcutNumber {
                    CmdGlyphBadge(letter: "\(n)")
                        .padding(.trailing, 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .modifier(CaptureRowDragModifier(fileURL: primaryMediaURL))
    }

    private var timeAgo: String {
        ScopeLibraryRelativeTime.label(for: recording.createdAt).uppercased()
    }

    /// First visual media file on disk, if any. Captures (and notes /
    /// memos with media attached) drag as the file URL so the receiver
    /// sees a real file, not bitmap data. nil for audio/text-only rows.
    private var primaryMediaURL: URL? {
        CaptureMediaFileResolver.primaryMedia(for: recording)?.url
    }

    private var hasVisualPreview: Bool {
        CaptureMediaFileResolver.primaryMedia(for: recording) != nil
    }
}

private struct ScopeLibraryMediaThumbnail: View {
    let recording: TalkieObject
    let isSelected: Bool

    @State private var image: NSImage?

    private var media: CaptureMediaAsset? {
        CaptureMediaFileResolver.primaryMedia(for: recording)
    }

    private var taskID: String {
        media?.url.path ?? recording.id.uuidString
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ScopeCanvas.surface)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 28)
                    .clipped()
            } else {
                Image(systemName: media?.isVideo == true ? "play.rectangle" : "photo")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ScopeInk.faint)
            }

            if media?.isVideo == true {
                Circle()
                    .fill(.black.opacity(0.45))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .offset(x: 0.5)
                    )
            }
        }
        .frame(width: 36, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(isSelected ? ScopeAmber.solid.opacity(0.45) : ScopeEdge.normal, lineWidth: 0.5)
        )
        .shadow(color: ScopeInk.primary.opacity(isSelected ? 0.12 : 0.06), radius: 2, y: 1)
        .task(id: taskID) {
            await loadThumbnail()
        }
        .onDisappear {
            image = nil
        }
    }

    private func loadThumbnail() async {
        guard let media else {
            await MainActor.run { image = nil }
            return
        }

        let cacheKey = media.url.path
        if let cached = ScopeLibraryThumbnailCache.image(for: cacheKey) {
            await MainActor.run { image = cached }
            return
        }

        let thumbnail: NSImage?
        switch media {
        case .image(let url):
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: url)
            }.value
            thumbnail = data.flatMap(NSImage.init(data:))
        case .video(let url):
            thumbnail = await VideoFrameThumbnailer.thumbnailAsync(for: url, maxSize: 96)
        }

        guard !Task.isCancelled else { return }
        if let thumbnail {
            ScopeLibraryThumbnailCache.set(thumbnail, for: cacheKey)
        }
        await MainActor.run {
            image = thumbnail
        }
    }
}

@MainActor
private enum ScopeLibraryThumbnailCache {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        return cache
    }()

    static func image(for key: String) -> NSImage? {
        images.object(forKey: key as NSString)
    }

    static func set(_ image: NSImage, for key: String) {
        images.setObject(image, forKey: key as NSString)
    }
}

/// Conditionally adds `.onDrag` to a row when a file URL is available.
/// Avoids starting a drag gesture on rows that have no payload (audio-
/// only memos, dictations) — those drag visually but drop nothing,
/// which feels broken.
public struct CaptureRowDragModifier: ViewModifier {
    public let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public func body(content: Content) -> some View {
        if let url = fileURL {
            content.onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        } else {
            content
        }
    }
}

// MARK: - Relative time

/// Compact time-ago for the row's trailing slot. Mirrors Talkie's
/// `RelativeTimeFormatter` output ("5m ago" / "Mon" / "Mar 4") so the
/// shared row reads identically in both apps.
private enum ScopeLibraryRelativeTime {
    static func label(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let interval = now.timeIntervalSince(date)

        if calendar.isDateInToday(date) {
            if interval < 3_600 {
                let minutes = max(1, Int(interval / 60))
                return "\(minutes)m ago"
            }
            return "\(Int(interval / 3_600))h ago"
        }

        if interval < 604_800 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }
}

// MARK: - TraceSparkline

/// Tiny deterministic sparkline drawn from a seed hash. Real audio
/// envelopes aren't reachable from the row context without an extra
/// async load, so this is a *signature* line — it's stable per memo
/// and looks like a trace, but doesn't claim to be the actual waveform.
private struct TraceSparkline: View {
    let seed: Int

    var body: some View {
        Canvas { ctx, size in
            let n = 18
            var rng = SplitMix(seed: UInt64(bitPattern: Int64(seed)))
            var path = Path()
            for i in 0..<n {
                let x = CGFloat(i) / CGFloat(n - 1) * size.width
                let amp = CGFloat(rng.nextUnit()) * 0.7 + 0.15  // 0.15…0.85
                let y = size.height * (1 - amp)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            ctx.stroke(path, with: .color(ScopeTrace.solid.opacity(0.55)), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }

    /// Tiny inline deterministic PRNG so the sparkline is stable per recording.
    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }
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

// MARK: - Cmd-hold glyph badge

/// Editorial cmd-hint chip rendered next to navigation targets while
/// the user holds ⌘. Reads as a small printer's tag on the Scope page:
/// cream substrate, ink letterform, amber ⌘ glyph as the accent dot.
/// Sits on top of whatever surface it's overlaid on; allowsHitTesting
/// is the caller's responsibility.
public struct CmdGlyphBadge: View {
    public let letter: String

    public init(letter: String) {
        self.letter = letter
    }

    public var body: some View {
        HStack(spacing: 1) {
            Text("⌘")
                .foregroundColor(ScopeAmber.solid)
            Text(letter)
                .foregroundColor(ScopeInk.primary)
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
    }
}

// MARK: - Simple bucketed list

/// Date-bucketed Scope library table for companion surfaces. Renders
/// the same bucket headers and channel-tagged rows as Talkie's Library
/// without the filters, pagination, ⌘-hold shortcuts, or inspector —
/// the "simple table" view of the shared recordings data.
public struct ScopeLibraryList: View {
    public let objects: [TalkieObject]
    public var selectedID: UUID?
    public var emptyTitle: String
    public var emptyDetail: String
    public var onSelect: ((TalkieObject) -> Void)?

    public init(
        objects: [TalkieObject],
        selectedID: UUID? = nil,
        emptyTitle: String = "NO RECORDINGS",
        emptyDetail: String = "Memos, dictations, notes, captures, and selections appear here.",
        onSelect: ((TalkieObject) -> Void)? = nil
    ) {
        self.objects = objects
        self.selectedID = selectedID
        self.emptyTitle = emptyTitle
        self.emptyDetail = emptyDetail
        self.onSelect = onSelect
    }

    public var body: some View {
        if objects.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ScopeLibraryDateBucket.grouped(objects), id: \.bucket) { group in
                        ScopeLibraryBucketHeader(bucket: group.bucket, count: group.items.count)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, object in
                            ScopeLibraryRow(
                                recording: object,
                                isSelected: selectedID == object.id,
                                onSelect: { onSelect?(object) }
                            )
                            .overlay(alignment: .top) {
                                if idx > 0 {
                                    ScopeRule(.row)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .background(ScopeCanvas.canvas)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(ScopeEdge.normal, lineWidth: 0.5)
                    .frame(width: 48, height: 48)
                PhosphorDot(color: ScopeAmber.solid.opacity(0.7), size: 8)
            }
            Text("· \(emptyTitle)")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            Text(emptyDetail)
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.subtle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
    }
}
