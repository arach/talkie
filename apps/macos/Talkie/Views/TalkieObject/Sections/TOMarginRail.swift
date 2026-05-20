//
//  TOMarginRail.swift
//  Talkie
//
//  Right-margin metadata aside for the memo detail surface. Rendered
//  as a peer of `detailContent` at the `TalkieView.scrollContent` level,
//  not buried inside `DocumentBody` — so the rail is present even when
//  the body has nothing to say (short single-paragraph memos, notes
//  with no transcript yet).
//
//  The rail is the structural particulars of the document — Filed,
//  Runtime, Source. Technical particulars (model, peak, timings,
//  cwd / captured-in app) deliberately stay out for now; they'll
//  migrate over once this rail proves itself.
//
//  Mirrors the existing `metadataAside` typography in
//  `TOSharedComponents.swift` so the two registers feel cut from the
//  same paper.
//

import SwiftUI
import TalkieKit

struct TOMarginRail: View {
    let recording: TalkieObject

    /// Standard rail width. 220pt mirrors the existing `metadataAside`
    /// fixed-width column.
    static let preferredWidth: CGFloat = 220

    /// Width below which the rail collapses entirely. Tracking the
    /// gate here so `TalkieView.scrollContent` can read it and decide
    /// whether to render the rail.
    static let collapseBelow: CGFloat = 920

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(groups.enumerated()), id: \.offset) { gi, group in
                groupView(group: group, isLast: gi == groups.count - 1)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Groups

    private var groups: [DocumentMetadataGroup] {
        var out: [DocumentMetadataGroup] = []

        // Filed — when the document came into being.
        var filed: [DocumentMetadataRow] = []
        filed.append(.init(label: "created", value: formatDate(recording.createdAt)))
        if let modified = recording.lastModified, !isSameMinute(modified, recording.createdAt) {
            filed.append(.init(label: "modified", value: formatRelative(modified)))
        }
        if !filed.isEmpty {
            out.append(.init(title: "Filed", rows: filed))
        }

        // Runtime — what the document costs to play and read.
        var runtime: [DocumentMetadataRow] = []
        if recording.duration > 0 {
            runtime.append(.init(label: "duration", value: formatDuration(recording.duration)))
        }
        let words = recording.wordCount
        if words > 0 {
            runtime.append(.init(label: "words", value: "\(words)"))
        }
        if !runtime.isEmpty {
            out.append(.init(title: "Runtime", rows: runtime))
        }

        // Source — where the document came from.
        var source: [DocumentMetadataRow] = []
        source.append(.init(label: "device", value: recording.source.displayName))
        if let appName = recording.metadata?.app?.name, !appName.isEmpty {
            source.append(.init(label: "app", value: appName))
        }
        if !source.isEmpty {
            out.append(.init(title: "Source", rows: source))
        }

        return out
    }

    // MARK: - Group rendering (mirrors `metadataAside` in TOSharedComponents)

    @ViewBuilder
    private func groupView(group: DocumentMetadataGroup, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· \(group.title.uppercased())")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2.2)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.55))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label.lowercased())
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .tracking(1.6)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(0.60))
                        Spacer(minLength: 8)
                        Text(row.value)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(
                                row.accent
                                    ? Color.hex("9A6A22")
                                    : Theme.current.foreground
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            if !isLast {
                Rectangle()
                    .fill(Theme.current.foreground.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Formatters

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM, h:mm a"
        return fmt.string(from: date)
    }

    private func formatRelative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 {
            let m = Int(interval / 60)
            return "\(m)m ago"
        }
        if interval < 86_400 {
            let h = Int(interval / 3600)
            return "\(h)h ago"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        return fmt.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func isSameMinute(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 60
    }
}
