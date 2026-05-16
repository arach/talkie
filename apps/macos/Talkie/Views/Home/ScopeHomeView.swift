//
//  ScopeHomeView.swift
//  Talkie macOS
//
//  Cream-phosphor Home that mirrors the usetalkie.com homepage
//  vocabulary: eyebrow + serif headline, instrument-bay capture cards
//  with channel tags, a dark agent-handoff panel embedded in the cream
//  surface, and a signal-table activity list.
//
//  Only mounted when SettingsManager.shared.isScopeTheme is true —
//  HomeScreen branches on theme and renders the existing grid view
//  for every other theme.
//

import SwiftUI
import TalkieKit

// MARK: - Scope display fonts
// Cormorant Garamond is the homepage's `--font-display-modern`. We mirror
// the same weights/sizes here. Tries a few PostScript name variants
// because Catharsis fonts ship slight naming differences across builds;
// falls back to system serif if none resolve.
private enum ScopeFont {
    private static let regularCandidates = [
        "CormorantGaramond-Regular",
        "Cormorant Garamond",
        "CormorantGaramond",
    ]
    private static let mediumCandidates = [
        "CormorantGaramond-Medium",
        "Cormorant Garamond Medium",
    ]

    static func display(size: CGFloat, medium: Bool = false) -> Font {
        for name in (medium ? mediumCandidates : regularCandidates) {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: medium ? .medium : .regular, design: .serif)
    }
}

struct ScopeHomeView: View {
    let unifiedActivity: [UnifiedActivityItem]
    let todayMemos: Int
    let todayDictations: Int
    let totalWords: Int
    let streak: Int

    var onStartRecording: () -> Void = {}
    var onOpenLibrary: () -> Void = {}
    var onOpenItem: (UnifiedActivityItem) -> Void = { _ in }

    private var todayTotal: Int { todayMemos + todayDictations }

    var body: some View {
        VStack(spacing: 0) {
            ScopeTopBand(title: "Today", chrome: heroTrailing)

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    hero
                    captureModes
                    agentPanel
                    signalTable
                    ownershipStrip
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
    }

    // MARK: - Hero
    //
    // The top-row identity ("Today" + streak/word chrome) lives in the
    // universal `ScopeTopBand` above. The in-page hero now carries only
    // the editorial flourish: the big Cormorant capture count, no
    // duplicate eyebrow.

    private var hero: some View {
        ScopePageHero(
            eyebrow: nil,
            titleHead: heroTitleHead,
            titleTail: nil,
            trailing: nil,
            size: .expanded
        )
    }

    private var heroTitleHead: String {
        if todayTotal == 0 { return "No captures yet" }
        if todayTotal == 1 { return "1 capture" }
        return "\(todayTotal) captures"
    }

    /// Streak + word count promoted to inline chrome — the longer
    /// subhead copy lives in the agent-bay panel below.
    private var heroTrailing: String {
        let totalWordsStr = totalWords > 1000
            ? "\(totalWords / 1000)K WORDS"
            : "\(totalWords) WORDS"
        if streak > 1 {
            return "\(streak)-DAY STREAK · \(totalWordsStr)"
        }
        return totalWordsStr
    }

    // MARK: - Capture modes

    private var captureModes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Capture Modes")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ],
                spacing: 16
            ) {
                CaptureModeCard(
                    icon: "mic.fill",
                    eyebrow: "Memo",
                    channel: "CH-01",
                    title: "Catch it before it changes.",
                    copy: "Record what you’re thinking. The transcript lands here.",
                    action: onStartRecording
                )
                CaptureModeCard(
                    icon: "keyboard",
                    eyebrow: "Dictation",
                    channel: "CH-02",
                    title: "Speak straight into the work.",
                    copy: "Hotkey on Mac. Dictate into whatever app you’re already in.",
                    action: {}
                )
                CaptureModeCard(
                    icon: "camera.viewfinder",
                    eyebrow: "Capture",
                    channel: "CH-03",
                    title: "Pin the screen, not just the words.",
                    copy: "Hyper+S to grab the moment alongside what you say.",
                    action: {}
                )
            }
        }
    }

    // MARK: - Agent panel (dark instrument bay in the cream)

    private var agentPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Agent")
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ScopePanel.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ScopePanel.Edge.normal, lineWidth: 1)
                    )
                GraticuleBackground(pitch: 24, color: ScopePanel.traceFaint, opacity: 0.55)
                    .mask(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 0) {
                    panelHeader
                    panelBody
                    panelFooter
                }
            }
            .frame(height: 220)
            .shadow(color: .black.opacity(0.18), radius: 30, y: 18)
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopePanel.trace, size: 6)
            Text("RUNNING · AG-01 / TALKIE.AGENT")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text("LOCAL ONLY · NO TELEMETRY")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ScopePanel.Edge.faint).frame(height: 1)
        }
    }

    private var panelBody: some View {
        HStack(spacing: 0) {
            statTile(value: "\(todayMemos)",    label: "MEMOS · TODAY")
            tileDivider
            statTile(value: "\(todayDictations)", label: "DICTATIONS · TODAY")
            tileDivider
            statTile(value: streak > 0 ? "\(streak)d" : "0d", label: "STREAK")
            tileDivider
            statTile(value: wordsFormatted, label: "TOTAL WORDS")
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    private var tileDivider: some View {
        Rectangle()
            .fill(ScopePanel.Edge.faint)
            .frame(width: 1)
            .padding(.vertical, 18)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ScopeFont.display(size: 34))
                .foregroundStyle(ScopePanel.trace)
                .tracking(-0.5)
                .shadow(color: ScopePanel.traceGlow, radius: 4)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private var panelFooter: some View {
        HStack(spacing: 12) {
            Text("· TRIG · LIVE · SIGNAL PATH · LOCAL")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text(Date().formatted(date: .omitted, time: .shortened).uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(ScopePanel.Edge.faint).frame(height: 1)
        }
    }

    private var wordsFormatted: String {
        if totalWords >= 1000 {
            let k = Double(totalWords) / 1000
            return String(format: "%.1fk", k)
        }
        return "\(totalWords)"
    }

    // MARK: - Signal table (recent activity)

    private var signalTable: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Captures")
                Spacer()
                Button(action: onOpenLibrary) {
                    HStack(spacing: 4) {
                        Text("LIBRARY")
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                        Text("→")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(ScopeInk.faint)
                }
                .buttonStyle(.plain)
            }

            if unifiedActivity.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(unifiedActivity.prefix(6)) { item in
                        SignalRow(item: item, action: { onOpenItem(item) })
                            .overlay(alignment: .top) {
                                Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                            }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.faint, lineWidth: 1)
                )
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            PhosphorDot(color: ScopeAmber.solid.opacity(0.6), size: 5)
            Text("NO SIGNAL · WAITING FOR INPUT")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ScopeEdge.faint, lineWidth: 1)
        )
    }

    // MARK: - Ownership strip (small architectural footer)

    private var ownershipStrip: some View {
        HStack(spacing: 18) {
            ownershipNode(pin: "U1", label: "Your devices", detail: "local library")
            arrow
            ownershipNode(pin: "U2", label: "Your iCloud",  detail: "private sync")
            arrow
            ownershipNode(pin: "U3", label: "External models", detail: "opt-in · your keys", dim: true)
        }
        .padding(.top, 6)
    }

    private func ownershipNode(pin: String, label: String, detail: String, dim: Bool = false) -> some View {
        HStack(spacing: 10) {
            ChannelLabel(pin)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(dim ? ScopeInk.faint : ScopeInk.primary)
                Text(detail.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var arrow: some View {
        SignalPath(color: ScopeAmber.solid, width: 28)
    }
}

// MARK: - Capture mode card

private struct CaptureModeCard: View {
    let icon: String
    let eyebrow: String
    let channel: String
    let title: String
    let copy: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopeCanvas.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? ScopeEdge.strong : ScopeEdge.normal, lineWidth: 1)
                    )
                GraticuleBackground(pitch: 24, color: ScopeTrace.faint, opacity: 0.45)
                    .mask(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 10) {
                            iconBadge
                            Text(eyebrow.uppercased())
                                .font(ScopeType.channel)
                                .tracking(ScopeType.Tracking.wide)
                                .foregroundStyle(ScopeInk.faint)
                        }
                        Spacer()
                        Text(channel)
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.subtle)
                    }

                    Rectangle().fill(ScopeEdge.subtle).frame(height: 1)

                    Text(title)
                        .font(ScopeFont.display(size: 19))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .tracking(-0.3)

                    Text(copy)
                        .font(.system(size: 12))
                        .foregroundStyle(ScopeInk.muted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        Text("EXPLORE")
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.faint)
                        Text("→")
                            .font(.system(size: 11))
                            .foregroundStyle(ScopeInk.faint)
                    }
                }
                .padding(16)
            }
            .frame(minHeight: 200, alignment: .topLeading)
            .offset(y: isHovered ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ScopeAmber.tintSubtle)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.normal, lineWidth: 1)
            )
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 3, opacity: 0.32)
            )
    }
}

// MARK: - Signal row

private struct SignalRow: View {
    let item: UnifiedActivityItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ChannelLabel(item.type == .memo ? "M" : "D",
                             color: item.type == .memo ? ScopeAmber.solid : ScopeInk.muted,
                             strokeColor: ScopeEdge.normal)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.isEmpty ? "(untitled)" : item.title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(1)
                    if let preview = item.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundStyle(ScopeInk.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let app = item.appName, !app.isEmpty {
                    Text(app.uppercased())
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                }

                Text(item.date.formatted(date: .omitted, time: .shortened))
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isHovered ? ScopeCanvas.canvasAlt : Color.clear)
            .overlay(alignment: .leading) {
                if isHovered {
                    Rectangle().fill(ScopeAmber.solid).frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
