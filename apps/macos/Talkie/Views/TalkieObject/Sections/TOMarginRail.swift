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
    /// whether to render the rail. Lowered from 920 → 720 so the
    /// technical rail surfaces on more window sizes (the data is the
    /// whole point of the rail; collapsing too eagerly hides it).
    static let collapseBelow: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(groups.enumerated()), id: \.offset) { gi, group in
                groupView(group: group, isLast: gi == groups.count - 1)
            }
        }
        .padding(.top, Self.eyebrowAlignmentInset)
    }

    /// Drop the rail so its first `· SOURCE` kicker lines up with the
    /// masthead eyebrow (`· DICTATION`) rather than the catalog slug at
    /// the very top of the content column — the two `· LABEL` mono
    /// kickers share a baseline and read as one register. Derived from
    /// TOHeaderSection.MastheadLayout: toolbarTop(16) + slug line(~13) +
    /// toolbarBottom(6) + hairline(1) + masthead top(28).
    static let eyebrowAlignmentInset: CGFloat = 64

    /// Whether the rail has any groups to render for this recording.
    /// `TalkieView.scrollContent` reads this to skip reserving the
    /// 220pt column (and its 40pt gap + hairline rule) when the rail
    /// would otherwise render empty — single-paragraph memos with no
    /// technical metadata don't need the side gutter.
    static func hasContent(for recording: TalkieObject) -> Bool {
        !TOMarginRail(recording: recording).groups.isEmpty
    }

    // MARK: - Groups
    //
    // The rail's job is to surface particulars that aren't elsewhere on
    // the page. The previous "Filed / Runtime / Source" set was pure
    // duplication — `created` was already in the eyebrow's date stamp,
    // `duration` and `words` were already in the byline, and `device`
    // was already in the byline's leading slug. Three sections of
    // "things you just read."
    //
    // The rail now carries technical particulars only: the engine that
    // produced the transcript, performance timing, and dictation-context
    // (cwd, captured-in app) when it differs from the source. When
    // nothing technical is known, the rail returns no groups and renders
    // nothing — the column just becomes whitespace.

    private var groups: [DocumentMetadataGroup] {
        var out: [DocumentMetadataGroup] = []

        // Filed — when the document was last touched. The `created`
        // row was dropped because the eyebrow already shows the date
        // stamp; this group only renders when there's a real edit
        // history beyond the original capture.
        if let modified = recording.lastModified,
           !isSameMinute(modified, recording.createdAt) {
            out.append(.init(
                title: "Filed",
                rows: [.init(label: "last", value: formatRelative(modified))]
            ))
        }

        // Runtime (duration / words) deliberately not in the rail —
        // the byline beneath the headline already carries
        // `MAC · 0:13 · 20 WORDS`. Rendering them in the rail too was
        // pure duplication (user flagged 2026-05-21). The rail now
        // earns its column only with particulars the byline can't
        // carry: model, peak, timings, cwd.

        // Source — where the document came from. Skip the device row
        // when the byline already says it (which it does in the
        // editorial masthead). App name still gets through when it's
        // distinct; shortened to avoid mid-truncation in the rail.
        var source: [DocumentMetadataRow] = []
        if let appName = recording.metadata?.app?.name,
           !appName.isEmpty,
           appName.caseInsensitiveCompare(recording.source.displayName) != .orderedSame {
            source.append(.init(label: "app", value: shortenAppName(appName)))
        }
        if !source.isEmpty {
            out.append(.init(title: "Source", rows: source))
        }

        // Transcription — the engine + signal quality, only when known.
        var transcription: [DocumentMetadataRow] = []
        if let model = recording.transcriptionModel, !model.isEmpty {
            transcription.append(.init(label: "model", value: prettyModel(model), accent: true))
        }
        if let peak = recording.metadata?.audio?.peakAmplitude {
            transcription.append(.init(label: "peak", value: formatAmplitude(peak)))
        }
        if !transcription.isEmpty {
            out.append(.init(title: "Transcription", rows: transcription))
        }

        // Timing — turnaround particulars when available. Labels
        // shortened ("end-to-end" → "e2e") so values get full claim
        // on the rail's width budget.
        var timing: [DocumentMetadataRow] = []
        if let endToEnd = recording.metadata?.performance?.endToEndMs {
            timing.append(.init(label: "e2e", value: formatMs(endToEnd)))
        }
        if let inApp = recording.metadata?.performance?.inAppMs {
            timing.append(.init(label: "in-app", value: formatMs(inApp)))
        }
        if !timing.isEmpty {
            out.append(.init(title: "Timing", rows: timing))
        }

        // Context — dictation-specific particulars (cwd) when present.
        if let cwd = recording.metadata?.context?.terminalWorkingDir, !cwd.isEmpty {
            out.append(.init(
                title: "Context",
                rows: [.init(label: "cwd", value: shortPath(cwd))]
            ))
        }

        // Timing markers belong in the left marginal rule alongside
        // paragraphs (see DocumentBody.documentColumn), not on the
        // right rail — they read as "where am I in the audio" cues
        // anchored to the text, not as technical metadata.

        return out
    }

    // MARK: - Technical formatters

    private func prettyModel(_ raw: String) -> String {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return raw }
        let family = parts[0].prefix(1).uppercased() + parts[0].dropFirst()
        let variant = parts[1]
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "distil-whisper_distil-", with: "")
            .replacingOccurrences(of: "_", with: " ")
        return "\(family) \(variant)"
    }

    private func formatAmplitude(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.2f s", Double(ms) / 1000.0)
    }

    private func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        let collapsed = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        if collapsed.count <= 28 { return collapsed }
        return "…" + collapsed.suffix(26)
    }

    /// Common-app shortener. Keeps the rail readable when the captured
    /// app is something like "Visual Studio Code" or "Google Chrome".
    private func shortenAppName(_ name: String) -> String {
        let lookup: [String: String] = [
            "visual studio code": "VS Code",
            "google chrome": "Chrome",
            "microsoft edge": "Edge",
            "chatgpt desktop": "ChatGPT",
            "claude desktop": "Claude",
            "iterm2": "iTerm2",
            "warp terminal": "Warp",
        ]
        if let mapped = lookup[name.lowercased()] { return mapped }
        return name
    }

    // MARK: - Group rendering (mirrors `metadataAside` in TOSharedComponents)

    @ViewBuilder
    private func groupView(group: DocumentMetadataGroup, isLast: Bool) -> some View {
        // Group title leads the eye (semibold, slightly darker); row
        // labels read as secondary captions softer than the title.
        // Spacing tightened — was loose given 10/11pt mono.
        VStack(alignment: .leading, spacing: 7) {
            Text("· \(group.title.uppercased())")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.65))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                    rowView(row: row)
                }
            }

            // Inter-group hairline dropped — relying on the 18pt
            // group spacing alone reads cleaner than a near-invisible
            // 0.08-opacity rule that mostly added noise. The `isLast`
            // gate stays in the signature so callers can opt back in.
            if !isLast {
                Color.clear.frame(height: 0)
            }
        }
    }

    /// One row in a group. Long values (cwd paths, multi-word model
    /// names) shift to a stacked layout so middle-truncation never
    /// eats meaningful content; short values stay on the same line as
    /// the label for scanability.
    @ViewBuilder
    private func rowView(row: DocumentMetadataRow) -> some View {
        if shouldStack(row: row) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label.lowercased())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.50))
                Text(row.value)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(
                        row.accent
                            ? ThemedScopeAccent.brass
                            : Theme.current.foreground.opacity(0.82)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.label.lowercased())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.50))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 10)
                Text(row.value)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(
                        row.accent
                            ? ThemedScopeAccent.brass
                            : Theme.current.foreground.opacity(0.82)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// Heuristic: stack the label + value vertically when the value is
    /// too long to fit comfortably alongside its label at 220pt rail
    /// width. Paths (`cwd`) and long model strings benefit; short
    /// numerics stay inline.
    private func shouldStack(row: DocumentMetadataRow) -> Bool {
        if row.label.lowercased() == "cwd" { return true }
        return row.value.count > 16
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
