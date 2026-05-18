//
//  ScopeStatsScreen.swift
//  Talkie macOS
//
//  Cream-phosphor Stats — the surface most natively suited to the
//  instrument-panel aesthetic. Big phosphor numbers in dark bichromatic
//  bays, chrome headers/footers, graticule textures, channel-labeled
//  signal tables. Every section a different instrument readout on the
//  same console.
//
//  Only mounted when SettingsManager.shared.isScopeTheme is true.
//  AppNavigation branches on theme and renders the existing StatsScreen
//  for every other theme.
//

import SwiftUI
import TalkieKit

// MARK: - Scope display fonts
// Cormorant Garamond is the homepage's `--font-display-modern`. Falls
// back to system serif if the font isn't installed.
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

// MARK: - ScopeStatsScreen

struct ScopeStatsScreen: View {
    /// Callback when user wants to navigate to all dictations
    var onSelectDictation: ((Dictation?) -> Void)?

    private let dictationStore = DictationStore.shared

    /// All numbers the screen renders live on `StatsCache.shared` —
    /// the cache pulls them in detached background tasks at most once
    /// per hour (or on demand). Reading the singleton's properties
    /// directly subscribes this view to updates via the Observation
    /// framework, so the numbers appear as soon as the first refresh
    /// lands without any local @State plumbing.
    @Bindable private var cache = StatsCache.shared

    private var todayCount: Int        { cache.todayDictations }
    private var weekCount: Int         { cache.weekDictations }
    private var totalWords: Int        { cache.totalWords }
    private var streak: Int            { cache.streak }
    private var totalDictations: Int   { cache.totalDictations }
    private var topApps: [TopApp]      { cache.topApps }
    private var deviceStorageBytes: Int64 { cache.deviceStorageBytes }
    private var workflowRunsCount: Int { cache.workflowRunsCount }
    private var activityData: [DayActivity] { cache.activityData }
    private var maxDayCount: Int       { cache.maxDayCount }
    private var sparklineCounts: [Int] { cache.sparklineCounts }

    private var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d yyyy"
        return f.string(from: Date()).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScopeTopBand(title: "Recordings", chrome: heroTrailing)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    sparklineStrip
                    instrumentBay
                    splitRow
                    recentDictationsTable
                    ownershipFooter
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
        .task {
            // Cache-first: paints instantly with whatever values the
            // shared cache already holds; triggers a background
            // refresh only if the data is stale (>1h old). All heavy
            // work — including the FileManager enumeration that used
            // to block main for tens of seconds — runs detached.
            cache.refreshIfStale()
            dictationStore.refresh()
        }
    }

    // MARK: - Hero
    //
    // The top-row identity ("Recordings" + words/streak chrome) lives in
    // the universal `ScopeTopBand` above. The in-page hero now carries
    // only the editorial flourish: the big Cormorant dictation count.

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
        if totalDictations == 0 { return "No dictations yet" }
        if totalDictations == 1 { return "1 dictation" }
        return "\(formatNumber(totalDictations)) dictations"
    }

    private var heroTrailing: String {
        let words = wordsFormatted(totalWords)
        let streakStr = streak > 1 ? "\(streak)-DAY STREAK"
            : streak == 1 ? "1-DAY STREAK"
            : nil
        if let streakStr {
            return "\(words) WORDS · \(streakStr) · LAST 30 DAYS"
        }
        return "\(words) WORDS · LAST 30 DAYS"
    }

    // MARK: - Sparkline strip (full bleed mono trace)

    private var sparklineStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ChannelLabel("CH-T")
                Text("WORDS / DAY · LAST 30")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                Spacer()
                Text(sparklinePeakLabel)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(ScopeCanvas.surface)
                    .overlay(
                        Rectangle()
                            .stroke(ScopeEdge.faint, lineWidth: 1)
                    )

                GraticuleBackground(pitch: 16, color: ScopeTrace.faint, opacity: 0.32)
                    .allowsHitTesting(false)

                SparklinePath(values: sparklineCounts)
                    .stroke(ScopeAmber.solid, lineWidth: 1.2)
                    .shadow(color: ScopeAmber.glow, radius: 3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
            }
            .frame(height: 64)
        }
    }

    private var sparklinePeakLabel: String {
        guard let peak = sparklineCounts.max(), peak > 0 else { return "NO SIGNAL" }
        return "PEAK · \(peak)"
    }

    // MARK: - Instrument bay (the dark bichromatic centerpiece)

    private var instrumentBay: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Live Readout")
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 240)
            .shadow(color: .black.opacity(0.20), radius: 30, y: 18)
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopePanel.trace, size: 6)
            Text("LIVE READOUT · ST-01 / DICTATION.STATS")
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
        .background(ScopePanel.stripTop)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ScopePanel.Edge.faint)
                .frame(height: 1)
                .padding(.horizontal, 16)
        }
    }

    private var panelBody: some View {
        HStack(spacing: 0) {
            statTile(value: wordsFormatted(totalWords), label: "TOTAL WORDS", pin: "T1")
            tileDivider
            statTile(value: formatNumber(totalDictations), label: "DICTATIONS · ALL TIME", pin: "T2")
            tileDivider
            statTile(value: "\(todayCount)", label: "TODAY", pin: "T3")
            tileDivider
            statTile(value: "\(weekCount)", label: "LAST 7 DAYS", pin: "T4")
            tileDivider
            statTile(value: streak > 0 ? "\(streak)d" : "0d", label: "STREAK", pin: "T5")
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

    private func statTile(value: String, label: String, pin: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(pin)
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopePanel.inkSubtle)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(ScopePanel.Edge.faint, lineWidth: 0.5)
                    )
                Spacer()
            }
            Text(value)
                .font(ScopeFont.display(size: 50))
                .foregroundStyle(ScopePanel.trace)
                .tracking(-0.8)
                .shadow(color: ScopePanel.traceGlow, radius: 5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
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
        .background(ScopePanel.stripBottom)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ScopePanel.Edge.faint)
                .frame(height: 1)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Split row: heatmap + top apps

    private var splitRow: some View {
        HStack(alignment: .top, spacing: 16) {
            heatmapBay
                .frame(maxWidth: .infinity, alignment: .topLeading)
            topAppsBay
                .frame(width: 320, alignment: .topLeading)
        }
    }

    // MARK: - Heatmap (cream surface, amber-toned cells)

    private var heatmapBay: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("Activity")
                Spacer()
                Text("13 WEEKS · LOCAL")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ScopeCanvas.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ScopeEdge.faint, lineWidth: 1)
                    )

                if activityData.isEmpty {
                    HStack(spacing: 10) {
                        PhosphorDot(color: ScopeAmber.solid.opacity(0.5), size: 5)
                        Text("NO ACTIVITY · 13 WEEKS")
                            .font(ScopeType.eyebrow)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.faint)
                    }
                    .padding(20)
                } else {
                    heatmapGrid
                        .padding(16)
                }
            }
        }
    }

    private var heatmapGrid: some View {
        // Group days into 13 weeks (columns)
        let weeks = Dictionary(grouping: activityData.enumerated().map { ($0.offset, $0.element) }) {
            $0.0 / 7
        }
        let sortedWeeks = weeks.keys.sorted()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(sortedWeeks, id: \.self) { weekIdx in
                    VStack(spacing: 3) {
                        let days = (weeks[weekIdx] ?? []).map { $0.1 }
                        ForEach(0..<7, id: \.self) { row in
                            if row < days.count {
                                heatmapCell(days[row])
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("LESS")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                ForEach(0..<5) { level in
                    Rectangle()
                        .fill(amberCell(level: level))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Rectangle()
                                .stroke(ScopeEdge.subtle, lineWidth: 0.5)
                        )
                }
                Text("MORE")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func heatmapCell(_ day: DayActivity) -> some View {
        let levelIdx = activityLevelIndex(day)
        return Rectangle()
            .fill(amberCell(level: levelIdx))
            .frame(width: 12, height: 12)
            .overlay(
                Rectangle()
                    .stroke(ScopeEdge.subtle, lineWidth: 0.5)
            )
            .help(heatmapTooltip(day))
    }

    private func activityLevelIndex(_ day: DayActivity) -> Int {
        switch day.level {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .max: return 4
        }
    }

    private func amberCell(level: Int) -> Color {
        switch level {
        case 0: return ScopeAmber.tintSubtle
        case 1: return ScopeAmber.solid.opacity(0.22)
        case 2: return ScopeAmber.solid.opacity(0.45)
        case 3: return ScopeAmber.solid.opacity(0.70)
        default: return ScopeAmber.solid
        }
    }

    private func heatmapTooltip(_ day: DayActivity) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let dateStr = f.string(from: day.date)
        if day.count == 0 { return "\(dateStr) · no activity" }
        return "\(dateStr) · \(day.count) dictation\(day.count == 1 ? "" : "s")"
    }

    // MARK: - Top apps (channel-labeled bar rows)

    private var topAppsBay: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("Top Apps")
                Spacer()
                Text("BY COUNT")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            VStack(spacing: 0) {
                if topApps.isEmpty {
                    HStack(spacing: 10) {
                        PhosphorDot(color: ScopeAmber.solid.opacity(0.5), size: 5)
                        Text("NO APPS LOGGED")
                            .font(ScopeType.eyebrow)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.faint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 20)
                } else {
                    let maxCount = topApps.map { $0.count }.max() ?? 1
                    ForEach(Array(topApps.enumerated()), id: \.offset) { idx, app in
                        TopAppBarRow(
                            channel: String(format: "A-%02d", idx + 1),
                            name: app.name,
                            bundleID: app.bundleID,
                            count: app.count,
                            maxCount: maxCount
                        )
                        .overlay(alignment: .top) {
                            if idx > 0 {
                                Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                            }
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.faint, lineWidth: 1)
            )
        }
    }

    // MARK: - Recent dictations table

    private var recentDictationsTable: some View {
        let recent = Array(dictationStore.dictations.prefix(6))

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Recent Captures")
                Spacer()
                Button {
                    onSelectDictation?(nil)
                } label: {
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

            if recent.isEmpty {
                HStack(spacing: 10) {
                    PhosphorDot(color: ScopeAmber.solid.opacity(0.6), size: 5)
                    Text("NO CAPTURES YET")
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
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { idx, dictation in
                        DictationSignalRow(
                            channel: String(format: "D-%02d", idx + 1),
                            dictation: dictation,
                            action: { onSelectDictation?(dictation) }
                        )
                        .overlay(alignment: .top) {
                            if idx > 0 {
                                Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                            }
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

    // MARK: - Ownership footer (storage + workflow)

    private var ownershipFooter: some View {
        HStack(spacing: 18) {
            footerNode(pin: "S1", label: "Audio on disk", detail: formatBytes(deviceStorageBytes))
            arrow
            footerNode(pin: "S2", label: "Actions ran", detail: formatNumber(workflowRunsCount))
            arrow
            footerNode(pin: "S3", label: "Storage", detail: "Local · GRDB", dim: true)
        }
        .padding(.top, 6)
    }

    private func footerNode(pin: String, label: String, detail: String, dim: Bool = false) -> some View {
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

    // MARK: - Formatting

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000)
        }
        return "\(n)"
    }

    private func wordsFormatted(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Sparkline path

private struct SparklinePath: Shape {
    let values: [Int]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let maxVal = max(values.max() ?? 1, 1)
        let stepX = rect.width / CGFloat(values.count - 1)

        for (i, v) in values.enumerated() {
            let x = CGFloat(i) * stepX
            let ratio = CGFloat(v) / CGFloat(maxVal)
            let y = rect.height - (ratio * rect.height)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// MARK: - Top app bar row (horizontal amber bar fill)

private struct TopAppBarRow: View {
    let channel: String
    let name: String
    let bundleID: String?
    let count: Int
    let maxCount: Int

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ChannelLabel(channel)
                .frame(width: 38, alignment: .leading)
            appIcon
                .frame(width: 16, height: 16)
            Text(displayName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(ScopeInk.primary)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.normal)
                .foregroundStyle(ScopeInk.faint)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(alignment: .leading) {
            GeometryReader { geo in
                Rectangle()
                    .fill(ScopeAmber.solid.opacity(isHovered ? 0.18 : 0.12))
                    .frame(width: barWidth(in: geo.size.width))
            }
        }
        .onHover { isHovered = $0 }
    }

    private var displayName: String {
        name.isEmpty ? "(unknown)" : name
    }

    private func barWidth(in total: CGFloat) -> CGFloat {
        guard maxCount > 0 else { return 0 }
        let ratio = CGFloat(count) / CGFloat(maxCount)
        return max(2, total * ratio)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let bundleID = bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 11))
                .foregroundStyle(ScopeInk.subtle)
        }
    }
}

// MARK: - Dictation signal row (recent table)

private struct DictationSignalRow: View {
    let channel: String
    let dictation: Dictation
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ChannelLabel(channel, color: ScopeAmber.solid, strokeColor: ScopeEdge.normal)
                    .frame(width: 42, alignment: .leading)

                Text(dictation.text.isEmpty ? "(silent)" : dictation.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ScopeInk.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let app = dictation.metadata.activeAppName, !app.isEmpty {
                    Text(app.uppercased())
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .trailing)
                }

                Text(dictation.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 60, alignment: .trailing)
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
