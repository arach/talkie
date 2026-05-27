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
                    ? "\(dayOfWeek(Date())) · awaiting the day's first memo"
                    : "\(dayOfWeek(Date())) · \(memos.count) memo\(memos.count == 1 ? "" : "s") · \(formatDuration(runtime)) elapsed · \(words) word\(words == 1 ? "" : "s")")
                    .font(ScopeType.display(size: 17).italic())
                    .foregroundStyle(ScopeInk.faint)
            }

            Rectangle()
                .fill(ScopeInk.faint.opacity(0.14))
                .frame(height: 0.5)
                .padding(.top, 24)

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
                    Text("\(memos.count) memo\(memos.count == 1 ? "" : "s") · \(words) word\(words == 1 ? "" : "s") · \(formatDuration(runtime))")
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
            Text("TAP A MEMO · ⌘N TO RECORD")
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

private struct TodayRow: View {
    let memo: TalkieObject
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(timeOfDay(memo.createdAt))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 86, alignment: .leading)
                    .monospacedDigit()

                Text(rowTitle)
                    .font(ScopeType.display(size: 17))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(formatDuration(memo.duration))
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
        guard let filename = memo.screenshots.first?.filename else { return nil }
        return ScreenshotStorage.screenshotsDirectory.appendingPathComponent(filename)
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
            HStack(alignment: .center, spacing: 10) {
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

                // Type icon — color-keyed glyph replaces the "DICTATION"
                // text label. Same channel-color palette ScopeLibraryRow
                // uses for the letter tag.
                Image(systemName: memo.type.icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(typeColor)
                    .frame(width: 22, height: 22, alignment: .center)

                // Title + inline sub-object badges (refined, promoted,
                // attachments). Title is the row's emphasis.
                HStack(spacing: 6) {
                    Text(rowTitle)
                        .font(ScopeType.display(size: 18))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if memo.wasRefined {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundStyle(ScopeAmber.solid.opacity(0.7))
                    }
                    if memo.wasPromoted {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(ScopeAmber.solid.opacity(0.7))
                    }
                    if memo.attachments.count > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 9))
                            Text("\(memo.attachments.count)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                        }
                        .foregroundStyle(ScopeInk.faint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(formatDuration(memo.duration))
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
        guard let filename = memo.screenshots.first?.filename else { return nil }
        return ScreenshotStorage.screenshotsDirectory.appendingPathComponent(filename)
    }

    private var typeColor: Color {
        switch memo.type {
        case .memo: return ScopeKind.memo
        case .dictation: return ScopeKind.dict
        case .note: return ScopeKind.note
        case .capture, .selection: return ScopeKind.capture
        default: return ScopeInk.subtle
        }
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
