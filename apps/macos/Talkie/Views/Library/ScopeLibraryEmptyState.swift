//
//  ScopeLibraryEmptyState.swift
//  Talkie
//
//  The Library "no selection" detail pane. Replaces the generic
//  "NO SELECTION" placeholder with an editorial composition that
//  honors the canvas. Studio source of truth:
//    design/studio/app/mac-library-empty/page.tsx (★ Combined variant)
//
//  Two vertical sections share the canvas:
//
//    TOP    — TODAY
//             eyebrow · serif date headline · italic byline ·
//             hairline · today's memos as a 3-col index
//
//    BOTTOM — EARLIER THIS WEEK
//             eyebrow + italic byline ·
//             hairline · 5-col rows (date / time / scope / title / duration)
//
//  Today's memos are filtered out of the Earlier section so the page
//  doesn't repeat itself. Both sections share the same primitives —
//  the page is composable: add a "Pinned" section above Today, or a
//  Pullquote interstitial, by inserting another `<section>` of the
//  same shape.
//

import SwiftUI
import TalkieKit

struct ScopeLibraryEmptyState: View {
    let recordings: [TalkieObject]
    var onSelectRecording: (UUID) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                todaySection
                    .padding(.bottom, 40)

                Rectangle()
                    .fill(ScopeInk.faint.opacity(0.18))
                    .frame(height: 0.5)
                    .padding(.bottom, 36)

                weekSection
                    .padding(.bottom, 56)

                Rectangle()
                    .fill(ScopeInk.faint.opacity(0.18))
                    .frame(height: 0.5)

                footer
                    .padding(.top, 14)
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Today section

    @ViewBuilder
    private var todaySection: some View {
        let memos = todaysMemos
        let runtime = memos.reduce(0) { $0 + $1.duration }
        let words = memos.reduce(0) { $0 + $1.wordCount }

        VStack(alignment: .leading, spacing: 0) {
            // No top eyebrow — chrome bar's nav strip can encroach into
            // this area on hover and the headline + italic byline below
            // already anchor the section. Day-of-week lives in the byline.
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text(headlineDate(Date()))
                    .font(ScopeType.display(size: 56))
                    .tracking(-1.0)
                    .foregroundStyle(Color.primary)

                Text(memos.isEmpty
                    ? "\(dayOfWeek(Date())) · awaiting the day's first item"
                    : "\(dayOfWeek(Date())) · \(memos.count) item\(memos.count == 1 ? "" : "s") · \(formatDuration(runtime)) elapsed · \(words) word\(words == 1 ? "" : "s")")
                    .font(ScopeType.display(size: 17).italic())
                    .foregroundStyle(ScopeInk.faint)
            }

            DaySignalStrip(recordings: memos)
                .padding(.top, 20)

            Rectangle()
                .fill(ScopeInk.faint.opacity(0.14))
                .frame(height: 0.5)
                .padding(.top, 18)

            if memos.isEmpty {
                Text("press the Talkie pill or ⌘N to record")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(ScopeInk.subtle)
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 0) {
                    ForEach(memos, id: \.id) { memo in
                        TodayRow(memo: memo, onTap: { onSelectRecording(memo.id) })
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Earlier this week section

    @ViewBuilder
    private var weekSection: some View {
        let memos = earlierThisWeekMemos
        let runtime = memos.reduce(0) { $0 + $1.duration }
        let words = memos.reduce(0) { $0 + $1.wordCount }

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("· EARLIER THIS WEEK ·")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)

                Spacer()

                if !memos.isEmpty {
                    Text("\(memos.count) item\(memos.count == 1 ? "" : "s") · \(words) word\(words == 1 ? "" : "s") · \(formatDuration(runtime))")
                        .font(ScopeType.display(size: 14).italic())
                        .foregroundStyle(ScopeInk.faint)
                }
            }

            Rectangle()
                .fill(ScopeInk.faint.opacity(0.14))
                .frame(height: 0.5)
                .padding(.top, 14)

            if memos.isEmpty {
                Text("nothing yet this week")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(ScopeInk.subtle)
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 0) {
                    ForEach(memos, id: \.id) { memo in
                        WeekRow(memo: memo, onTap: { onSelectRecording(memo.id) })
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("LIBRARY INDEX")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)

            Spacer()

            let weekTotal = todaysMemos.count + earlierThisWeekMemos.count
            let weekWords = (todaysMemos + earlierThisWeekMemos).reduce(0) { $0 + $1.wordCount }
            let weekRuntime = (todaysMemos + earlierThisWeekMemos).reduce(0) { $0 + $1.duration }

            if weekTotal > 0 {
                Text("\(weekWords) word\(weekWords == 1 ? "" : "s") THIS WEEK · \(formatDuration(weekRuntime)) elapsed")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
        }
    }

    // MARK: - Data filters

    private var todaysMemos: [TalkieObject] {
        let cal = Calendar.current
        return recordings
            .filter { cal.isDateInToday($0.createdAt) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Earlier-this-week = within the last 7 days AND not today.
    private var earlierThisWeekMemos: [TalkieObject] {
        let cal = Calendar.current
        let now = Date()
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: now) else { return [] }
        return recordings
            .filter { !cal.isDateInToday($0.createdAt) && $0.createdAt >= weekAgo }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Formatters

    private func headlineDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        return fmt.string(from: date)
    }

    private func dayOfWeek(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return fmt.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Rows

private struct DaySignalStrip: View {
    let recordings: [TalkieObject]

    var body: some View {
        HStack(spacing: 0) {
            SignalCell(label: "VOICE", value: "\(voiceCount)", detail: formatDuration(runtime))
            SignalCell(label: "CAPTURES", value: "\(captureCount)", detail: "\(mediaCount) media")
            SignalCell(label: "WORDS", value: "\(wordCount)", detail: "\(textCount) text")
            SignalCell(label: "SOURCES", value: "\(sourceCount)", detail: primarySource)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ScopeInk.faint.opacity(0.12))
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ScopeInk.faint.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    private var voiceCount: Int {
        recordings.filter { $0.duration > 0 || $0.isDictation || $0.isMemo }.count
    }

    private var captureCount: Int {
        recordings.filter { $0.type == .capture || $0.type == .selection }.count
    }

    private var mediaCount: Int {
        recordings.reduce(0) { partial, item in
            partial + item.screenshots.count + item.clips.count + item.visualContexts.count + item.attachments.count
        }
    }

    private var wordCount: Int {
        recordings.reduce(0) { $0 + $1.wordCount }
    }

    private var textCount: Int {
        recordings.filter { ($0.text?.isEmpty == false) || $0.wordCount > 0 }.count
    }

    private var runtime: Double {
        recordings.reduce(0) { $0 + $1.duration }
    }

    private var sourceCount: Int {
        Set(recordings.map(\.source)).count
    }

    private var primarySource: String {
        let grouped = Dictionary(grouping: recordings, by: \.source)
        guard let source = grouped.max(by: { $0.value.count < $1.value.count })?.key else {
            return "none"
        }
        return source.displayName.lowercased()
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let h = total / 3_600
        let m = total % 3_600 / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

private struct SignalCell: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(ScopeType.display(size: 21, weight: .medium))
                    .foregroundStyle(ScopeInk.primary)
                    .monospacedDigit()
                Text(detail)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ScopeInk.faint.opacity(0.10))
                .frame(width: 0.5)
        }
    }
}

private struct OverviewTypeMark: View {
    let item: TalkieObject

    private var kindColor: Color {
        switch item.type {
        case .memo: return ScopeKind.memo
        case .dictation, .segment: return ScopeKind.dict
        case .note: return ScopeKind.note
        case .capture, .selection: return ScopeKind.capture
        }
    }

    private var media: CaptureMediaAsset? {
        CaptureMediaFileResolver.primaryMedia(for: item)
    }

    private var attachment: RecordingAttachment? {
        item.attachments.first
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(ScopeCanvas.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(ScopeEdge.normal, lineWidth: 0.55)
                )

            markBody
                .padding(.horizontal, 5)
                .padding(.vertical, 5)
        }
        .frame(width: 42, height: 28)
        .shadow(color: ScopeInk.primary.opacity(0.05), radius: 2, y: 1)
    }

    @ViewBuilder
    private var markBody: some View {
        if let media {
            Image(systemName: media.isVideo ? "play.rectangle.fill" : "photo")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kindColor.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if item.duration > 0 || item.isDictation || item.hasAudio || attachment?.kind == .audio {
            OverviewWaveform(seed: item.id.uuidString.hashValue, color: kindColor)
        } else if let attachment {
            Image(systemName: attachment.kind.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kindColor.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: item.type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kindColor.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct OverviewWaveform: View {
    let seed: Int
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: UInt64(bitPattern: Int64(seed)))
            let barCount = 9
            let gap: CGFloat = 1.4
            let barWidth = (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            for index in 0..<barCount {
                let x = CGFloat(index) * (barWidth + gap)
                let unit = CGFloat(rng.nextUnit())
                let height = max(4, size.height * (0.22 + unit * 0.70))
                let y = (size.height - height) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                ctx.fill(path, with: .color(color.opacity(index % 3 == 0 ? 0.85 : 0.58)))
            }
        }
        .allowsHitTesting(false)
    }

    private struct SplitMix {
        var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0xDEADBEEF : seed
        }

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

private struct TodayRow: View {
    let memo: TalkieObject
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                Text(timeOfDay(memo.createdAt))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 62, alignment: .leading)
                    .monospacedDigit()

                OverviewTypeMark(item: memo)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle)
                        .font(ScopeType.display(size: 17))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(metaLine)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.normal)
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(trailingMetric)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 52, alignment: .trailing)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 11)
            .background(
                Rectangle()
                    .fill(hovered ? ScopeAmber.tintSubtle : Color.clear)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ScopeInk.faint.opacity(0.10))
                    .frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .modifier(CaptureRowDragModifier(fileURL: primaryScreenshotURL))
    }

    private var rowTitle: String {
        if let title = memo.title, !title.isEmpty { return title }
        if let preview = memo.transcriptPreview, !preview.isEmpty { return preview }
        return "Untitled \(memo.type.displayName)"
    }

    private var primaryScreenshotURL: URL? {
        CaptureMediaFileResolver.primaryMedia(for: memo)?.url
    }

    private var metaLine: String {
        var parts = [memo.type.displayName.uppercased()]
        if let appName = memo.appContext?.name, !appName.isEmpty {
            parts.append(appName.uppercased())
        } else {
            parts.append(memo.source.displayName.uppercased())
        }
        if memo.wordCount > 0 { parts.append("\(memo.wordCount)W") }
        if memo.attachments.count > 0 { parts.append("\(memo.attachments.count) ATT") }
        return parts.joined(separator: " · ")
    }

    private var trailingMetric: String {
        if memo.duration > 0 { return formatDuration(memo.duration) }
        if memo.wordCount > 0 { return "\(memo.wordCount)W" }
        if memo.attachments.count > 0 { return "\(memo.attachments.count)F" }
        return "—"
    }

    private func timeOfDay(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct WeekRow: View {
    let memo: TalkieObject
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                // Datetime — stacked day-of-week / time-of-day in a tight
                // monospace brick. Replaces the 220pt three-column header
                // (day · time · TYPE) so the title gets the real estate.
                VStack(alignment: .leading, spacing: 1) {
                    Text(dayLabel(memo.createdAt))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(ScopeInk.faint)
                    Text(timeOfDay(memo.createdAt))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.2)
                        .foregroundStyle(ScopeInk.subtle)
                        .monospacedDigit()
                }
                .frame(width: 48, alignment: .leading)

                OverviewTypeMark(item: memo)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle)
                        .font(ScopeType.display(size: 18))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(metaLine)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.normal)
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(trailingMetric)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 11)
            .background(
                Rectangle()
                    .fill(hovered ? ScopeAmber.tintSubtle : Color.clear)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ScopeInk.faint.opacity(0.10))
                    .frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .modifier(CaptureRowDragModifier(fileURL: primaryScreenshotURL))
    }

    private var rowTitle: String {
        if let title = memo.title, !title.isEmpty { return title }
        if let preview = memo.transcriptPreview, !preview.isEmpty { return preview }
        return "Untitled \(memo.type.displayName)"
    }

    private var primaryScreenshotURL: URL? {
        CaptureMediaFileResolver.primaryMedia(for: memo)?.url
    }

    private var metaLine: String {
        var parts = [memo.type.displayName.uppercased()]
        if let appName = memo.appContext?.name, !appName.isEmpty {
            parts.append(appName.uppercased())
        } else {
            parts.append(memo.source.displayName.uppercased())
        }
        if memo.wordCount > 0 { parts.append("\(memo.wordCount)W") }
        if memo.attachments.count > 0 { parts.append("\(memo.attachments.count) ATT") }
        if memo.wasRefined { parts.append("REFINED") }
        if memo.wasPromoted { parts.append("PROMOTED") }
        return parts.joined(separator: " · ")
    }

    private var trailingMetric: String {
        if memo.duration > 0 { return formatDuration(memo.duration) }
        if memo.wordCount > 0 { return "\(memo.wordCount)W" }
        if memo.attachments.count > 0 { return "\(memo.attachments.count)F" }
        return "—"
    }

    private func dayLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d"
        return fmt.string(from: date)
    }

    private func timeOfDay(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mma"
        return fmt.string(from: date).lowercased()
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// Display font lookup centralized in ScopeType.display(size:weight:) — see TalkieKit/UI/ScopeDesign.swift.
