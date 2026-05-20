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
    let totalWords: Int
    let streak: Int

    var onStartRecording: () -> Void = {}
    var onOpenLibrary: () -> Void = {}
    var onOpenItem: (UnifiedActivityItem) -> Void = { _ in }

    // MARK: - Agent bay treatments (independent, combinable)
    // Each AppStorage bool toggles one visual treatment on the agent
    // panel. Toggle chips live in `agentBayTreatmentStrip` (DEBUG +
    // Design Mode only). Default off → ships current austere look.
    @AppStorage("scopeAgentBay.lift")      private var bayLift: Bool = false
    @AppStorage("scopeAgentBay.sparkline") private var baySparkline: Bool = true
    @AppStorage("scopeAgentBay.waveform")  private var bayWaveform: Bool = false
    @AppStorage("scopeAgentBay.compact")   private var bayCompact: Bool = true
    @AppStorage("scopeAgentBay.bezel")     private var bayBezel: Bool = false
    @AppStorage("scopeAgentBay.heatmap")   private var bayHeatmap: Bool = false
    @AppStorage("scopeAgentBay.timeline")  private var bayTimeline: Bool = false
    @AppStorage("scopeAgentBay.brackets")  private var bayBrackets: Bool = false
    // Default to CHIFFON — the Scope theme's canonical bay per the
    // studio decision (2026-05-17). See BayScheme.canonical(for:) and
    // design/studio/app/mac-home/NOTES.md.
    @AppStorage("scopeAgentBay.scheme")    private var bayScheme: String = BayScheme.chiffon.rawValue
    // Migration fallback: users with deprecated stored values
    // (graphite/pewter/ash/stone — dropped 2026-05-17) decode to nil
    // and should land on the Scope canonical, not the original amber.
    private var currentScheme: BayScheme { BayScheme(rawValue: bayScheme) ?? .chiffon }

    @State private var memosStore = MemosViewModel.shared
    @State private var dictationStore = DictationStore.shared
    @State private var recordingsVM = RecordingsViewModel.shared
    @State private var workflowExecutor = WorkflowExecutor.shared
    @State private var screenshotTray = ScreenshotTray.shared
    @State private var clipTray = ClipTray.shared
    @State private var selectionTray = SelectionTray.shared

    private var todayMemos: Int { memosStore.todayCount }
    private var todayDictations: Int { dictationStore.todayCount }
    private var todayTotal: Int { todayMemos + todayDictations }
    private var trayItemCount: Int {
        _ = screenshotTray.items
        _ = clipTray.items
        _ = selectionTray.items
        return TrayItem.allItems().count
    }

    var body: some View {
        #if DEBUG
        let _ = FrameRateMonitor.shared.recordBodyAccess("ScopeHomeView")
        #endif
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    agentPanel
                    recentTwoPane
                    routinesStrip
                    discoveryRow
                    systemStatusRail
                    ownershipStrip
                }
                .padding(.horizontal, 32)
                .padding(.top, ScopeTopBandLayout.height + ScopeTopBandLayout.topInset + 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
        .task {
            ChromeBarHeader.shared.set(title: "Today", subtitle: heroTrailing)
            await memosStore.loadStats()
            await workflowExecutor.refreshHomeHistory()
            if recordingsVM.recordings.isEmpty {
                await recordingsVM.loadRecordings()
            }
        }
        .onChange(of: streak) { _, _ in
            ChromeBarHeader.shared.subtitle = heroTrailing
        }
        .onChange(of: totalWords) { _, _ in
            ChromeBarHeader.shared.subtitle = heroTrailing
        }
        .onDisappear {
            ChromeBarHeader.shared.clear()
        }
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
                    glyph: .dot,
                    eyebrow: "Memo",
                    channel: "CH-01",
                    state: captureStateMemo,
                    action: "START RECORDING",
                    hint: "·",
                    onTap: onStartRecording
                )
                CaptureModeCard(
                    glyph: .ring,
                    eyebrow: "Dictation",
                    channel: "CH-02",
                    state: captureStateDictation,
                    action: "DICTATE",
                    hint: "⌃⇧⌘ D",
                    onTap: {}
                )
                CaptureModeCard(
                    glyph: .crosshair,
                    eyebrow: "Capture",
                    channel: "CH-03",
                    state: captureStateTray,
                    action: "CAPTURE",
                    hint: "⌃⇧⌘ S",
                    onTap: {}
                )
            }
        }
    }

    /// State lines for the capture cards. Stays factual (counts /
    /// last-time) rather than editorial.
    private var captureStateMemo: String {
        if todayMemos == 0 { return "Ready" }
        if todayMemos == 1 { return "1 today" }
        return "\(todayMemos) today"
    }
    private var captureStateDictation: String {
        if todayDictations == 0 { return "Ready" }
        if todayDictations == 1 { return "1 today" }
        return "\(todayDictations) today"
    }
    private var captureStateTray: String {
        if trayItemCount == 0 { return "Hyper+S armed" }
        if trayItemCount == 1 { return "1 in tray" }
        return "\(trayItemCount) in tray"
    }

    // MARK: - Recent two-pane (Voice + Content)
    //
    // Ported from studio MacHome v4. Replaces the older mixed
    // signalTable + captureModes pair: each Recent sub-band has a
    // CTA-empty fallback ("● Start a memo · ⌃⇧⌘ M") that doubles as
    // the start-it action, so there's no separate Capture Modes row
    // duplicating the affordance.

    private var recentTwoPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Recent")
            RecentTwoPaneSection(
                voiceSections: [
                    RecentSection(
                        id: "memos",
                        eyebrow: "Memos",
                        count: countLabel(recentMemos.count, "today"),
                        libraryLabel: "ALL MEMOS",
                        onLibrary: { NavigationState.shared.navigate(to: .recordings) },
                        rows: recentMemos.prefix(3).map { obj in
                            RecentRow(
                                id: obj.id,
                                glyph: "●",
                                line: rowLine(for: obj),
                                body: nil,
                                meta: durationLabel(obj.duration),
                                when: whenLabel(obj.createdAt),
                                onTap: { NavigationState.shared.navigate(to: .recordings, params: ["recordingId": obj.id.uuidString]) }
                            )
                        },
                        emptyCTA: RecentCTA(
                            glyph: "●",
                            label: "Start a memo",
                            kbd: ["⌃", "⇧", "⌘", "M"],
                            onTap: onStartRecording
                        )
                    ),
                    RecentSection(
                        id: "dictations",
                        eyebrow: "Dictations",
                        count: countLabel(recentDictations.count, "today"),
                        libraryLabel: "ALL DICTATIONS",
                        onLibrary: { NavigationState.shared.navigate(to: .dictations) },
                        rows: recentDictations.prefix(3).map { obj in
                            RecentRow(
                                id: obj.id,
                                glyph: "○",
                                line: rowLine(for: obj),
                                body: nil,
                                meta: wordCountLabel(obj.text),
                                when: whenLabel(obj.createdAt),
                                onTap: { NavigationState.shared.navigate(to: .dictations, params: ["recordingId": obj.id.uuidString]) }
                            )
                        },
                        emptyCTA: RecentCTA(
                            glyph: "○",
                            label: "Dictate",
                            kbd: ["⌃", "⇧", "⌘", "D"],
                            onTap: {}
                        )
                    ),
                ],
                contentSections: [
                    RecentSection(
                        id: "captures",
                        eyebrow: "Captures",
                        count: countLabel(recentTrayItems.count, "today"),
                        libraryLabel: "ALL CAPTURES",
                        onLibrary: { NavigationState.shared.navigate(to: .screenshots) },
                        rows: recentTrayItems.prefix(3).map { item in
                            RecentRow(
                                id: item.id,
                                glyph: "▢",
                                line: trayLine(for: item),
                                body: nil,
                                meta: trayMeta(for: item),
                                when: whenLabel(item.capturedAt),
                                onTap: {}
                            )
                        },
                        emptyCTA: RecentCTA(
                            glyph: "▢",
                            label: "Capture screen",
                            kbd: ["⌃", "⇧", "⌘", "S"],
                            onTap: {}
                        )
                    ),
                    RecentSection(
                        id: "notes",
                        eyebrow: "Notes",
                        count: countLabel(recentNotes.count, "this week"),
                        libraryLabel: "ALL NOTES",
                        onLibrary: { NavigationState.shared.navigate(to: .notes) },
                        rows: recentNotes.prefix(3).map { obj in
                            RecentRow(
                                id: obj.id,
                                glyph: "¶",
                                line: noteTitle(for: obj),
                                body: noteBodyExcerpt(for: obj),
                                meta: "",
                                when: whenLabel(obj.createdAt),
                                onTap: { NavigationState.shared.navigate(to: .notes, params: ["recordingId": obj.id.uuidString]) }
                            )
                        },
                        emptyCTA: RecentCTA(
                            glyph: "¶",
                            label: "Write a note",
                            kbd: ["⌃", "⇧", "⌘", "N"],
                            onTap: {}
                        )
                    ),
                ]
            )
        }
    }

    // MARK: Recent data sources

    private var recentMemos: [TalkieObject] {
        recordingsVM.recordings
            .filter { $0.type == .memo && $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var recentDictations: [TalkieObject] {
        recordingsVM.recordings
            .filter { $0.type == .dictation && $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var recentNotes: [TalkieObject] {
        recordingsVM.recordings
            .filter { $0.type == .note && $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var recentTrayItems: [TrayItem] {
        TrayItem.allItems().sorted { $0.capturedAt > $1.capturedAt }
    }

    // MARK: Recent row helpers

    private func rowLine(for obj: TalkieObject) -> String {
        let text = (obj.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return obj.title ?? "Untitled" }
        return text
    }
    private func noteTitle(for obj: TalkieObject) -> String {
        if let title = obj.title, !title.isEmpty { return title }
        let text = (obj.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Untitled note" : firstLine
    }
    private func noteBodyExcerpt(for obj: TalkieObject) -> String? {
        let text = (obj.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count > 1 else { return nil }
        return String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func durationLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    private func wordCountLabel(_ text: String?) -> String {
        let words = (text ?? "").split { $0.isWhitespace }.count
        return "\(words) WORDS"
    }
    private func trayLine(for item: TrayItem) -> String {
        if let preview = item.previewText, !preview.isEmpty { return preview }
        if let context = item.contextLabel, !context.isEmpty { return context }
        return item.modeIcon
    }
    private func trayMeta(for item: TrayItem) -> String {
        if item.isText { return "TEXT" }
        return "\(item.width)×\(item.height)"
    }
    private func whenLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    private func countLabel(_ n: Int, _ suffix: String) -> String {
        if n == 0 { return "none \(suffix)" }
        return "\(n) \(suffix)"
    }

    // MARK: - Routines strip (Workflows · Console)
    //
    // RESTORED from the original HomeGrid taxonomy (actionWorkflows +
    // actionHelpers + featureAgentConsole). Two light panels on the
    // cream canvas so they read as cousins of the Capture Mode cards,
    // not as competing dark slabs with the bay.
    //
    // Console data remains stubbed until an active ConsoleRegistry lands.

    private var routinesStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Routines")
            HStack(spacing: 16) {
                RoutinesPanel(
                    title: "Workflows",
                    trailing: workflowRunsTodayText,
                    rows: workflowRunRows,
                    footer: "MANAGE WORKFLOWS"
                )
                RoutinesPanel(
                    title: "Console",
                    trailing: "2 tabs",
                    rows: [
                        .init(leading: .filled, label: "iTerm2", trailing: "ACTIVE"),
                        .init(leading: .filled, label: "Codex",  trailing: "IDLE"),
                        .init(leading: .hollow, label: "Claude", trailing: "OFF"),
                    ],
                    footer: "OPEN CONSOLE"
                )
            }
        }
    }

    private var workflowRunsTodayText: String {
        let count = workflowExecutor.homeSuccessfulRunsTodayCount
        if count == 1 { return "1 ran today" }
        return "\(count) ran today"
    }

    private var workflowRunRows: [RoutinesPanel.Row] {
        let rows = workflowExecutor.homeRecentSuccessfulRuns.prefix(3).map { run in
            RoutinesPanel.Row(
                leading: .filled,
                label: run.workflowName,
                trailing: workflowRunTimeText(run.runDate)
            )
        }

        if rows.isEmpty {
            return [.init(leading: .hollow, label: "Ready", trailing: "")]
        }

        return rows
    }

    private func workflowRunTimeText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Discovery row (Today · Shortcuts · Trending)
    //
    // RESTORED from widgetActivity + widgetShortcuts + widgetTrending.
    // Three discovery surfaces at the same density as the Capture Modes
    // row. Each widget gets a tailored visual so they read as distinct,
    // not as three flat lists.
    //
    // TODO: wire Today to Calendar/Reminders; Trending to a real
    // recurring-theme aggregator. Shortcuts is the only one mostly
    // real today (HotkeyManager registrations).

    private var discoveryRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Discovery")
            HStack(spacing: 16) {
                LearnWidget()
                ShortcutsWidget()
                TrendingWidget()
            }
        }
    }

    // MARK: - System status rail (scheme-aware)
    //
    // RESTORED from the systemStatus + devicesBridge cards. The rail
    // wears the same scheme as the bay above so the two read as the
    // top + bottom of one instrument body. On AMBER it's a gunmetal
    // recessed footer; on CHIFFON (Scope canonical) it's a barely-
    // there cream strip.
    //
    // AGENT / ICLOUD source launch-agent status; BRIDGE source is
    // the local XPC connection to TalkieAgent. UPDATES stays stubbed
    // until an updater source exists.

    private var systemStatusRail: some View {
        SystemStatusRail(scheme: currentScheme)
    }

    // MARK: - Agent panel (dark instrument bay in the cream)

    private var agentPanel: some View {
        let scheme = currentScheme
        return VStack(alignment: .leading, spacing: 14) {
            #if DEBUG
            agentBayTreatmentStrip
            #endif
            Eyebrow("Agent")
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(scheme.panelBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(scheme.edge, lineWidth: 0.5)
                    )

                if bayLift {
                    bayLiftOverlay(scheme: scheme)
                        .mask(RoundedRectangle(cornerRadius: 8))
                }

                GraticuleBackground(pitch: 28, color: scheme.traceFaint, opacity: 0.32)
                    .mask(RoundedRectangle(cornerRadius: 8))

                if bayWaveform {
                    BackgroundWaveform(scheme: scheme)
                        .padding(.horizontal, 16)
                        .padding(.top, 36)        // clear top strip
                        .padding(.bottom, 36)     // clear bottom strip
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 0) {
                    panelHeader(scheme: scheme)
                    panelBody(scheme: scheme)
                    panelFooter(scheme: scheme)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if bayBrackets {
                    BayCornerBrackets(color: scheme.edgeStrong)
                        .padding(.horizontal, 4)
                        .padding(.top, 32)
                        .padding(.bottom, 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if bayBezel {
                    BezelOverlay(scheme: scheme)
                }
            }
            .frame(height: bayCompact ? 150 : 220)
            // Trimmed from radius:30 / y:18 — the 60pt Gaussian kernel was
            // recomputing on every layout invalidation and dominating
            // scroll cost on this page. radius:12 / y:6 keeps the panel
            // reading as embedded without the offscreen blur tax.
            .compositingGroup()
            .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
        }
    }

    /// Treatment 1 — slate gradient lift + warm radial bloom behind stats.
    /// Sits above the flat bg fill and under the graticule so the grid
    /// still reads on top of the softer base.
    private func bayLiftOverlay(scheme: BayScheme) -> some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color.hex("1E2528"), location: 0.0),
                    .init(color: Color.hex("171C1F"), location: 0.45),
                    .init(color: Color.hex("0F1416"), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    scheme.trace.opacity(0.10),
                    scheme.trace.opacity(0.04),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 360
            )
            .blendMode(.plusLighter)
        }
    }

    private func panelHeader(scheme: BayScheme) -> some View {
        HStack(spacing: 8) {
            PhosphorDot(color: scheme.trace, size: 6)
            Text("RUNNING · AG-01 / TALKIE.AGENT")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(scheme.inkFaint)
            Spacer()
            Text("LOCAL ONLY · NO TELEMETRY")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(scheme.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(scheme.stripTopFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(scheme.edge)
                .frame(height: 0.5)
                .padding(.horizontal, 16)
        }
    }

    private func panelBody(scheme: BayScheme) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statTile(scheme: scheme, seed: 0, value: "\(todayMemos)",    label: "MEMOS · TODAY")
                tileDivider(scheme: scheme)
                statTile(scheme: scheme, seed: 1, value: "\(todayDictations)", label: "DICTATIONS · TODAY")
                tileDivider(scheme: scheme)
                statTile(
                    scheme: scheme,
                    seed: 2,
                    value: streak > 0 ? "\(streak)d" : "0d",
                    label: "STREAK",
                    extra: (bayHeatmap && !bayCompact) ? AnyView(ActivityHeatmap(scheme: scheme)) : nil
                )
                tileDivider(scheme: scheme)
                statTile(scheme: scheme, seed: 3, value: wordsFormatted, label: "TOTAL WORDS")
            }
            .frame(maxHeight: .infinity)

            if bayTimeline {
                TodayTimeline(scheme: scheme)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 16)
    }

    private func tileDivider(scheme: BayScheme) -> some View {
        Rectangle()
            .fill(scheme.edge)
            .frame(width: 0.5)
            .padding(.vertical, 18)
    }

    private func statTile(scheme: BayScheme, seed: Int, value: String, label: String, extra: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ScopeFont.display(size: bayCompact ? 26 : 34))
                .foregroundStyle(scheme.statInk)
                .tracking(-0.5)
                .shadow(color: scheme.traceGlow, radius: 4)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(scheme.inkFaint)
            if let extra {
                extra
                    .padding(.top, 4)
            } else if baySparkline {
                StatSparkline(seed: seed, scheme: scheme)
                    .frame(height: bayCompact ? 12 : 16)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private func panelFooter(scheme: BayScheme) -> some View {
        HStack(spacing: 12) {
            Text("· TRIG · LIVE · SIGNAL PATH · LOCAL")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(scheme.inkFaint)
            Spacer()
            Text(Date().formatted(date: .omitted, time: .shortened).uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(scheme.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(scheme.stripBottomFill)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(scheme.edge)
                .frame(height: 0.5)
                .padding(.horizontal, 16)
        }
    }

    private var wordsFormatted: String {
        if totalWords >= 1000 {
            let k = Double(totalWords) / 1000
            return String(format: "%.1fk", k)
        }
        return "\(totalWords)"
    }

    // MARK: - Treatment toggle strip (DEBUG + Design Mode only)
    //
    // Mirrors the Library readout switcher. Each chip toggles one
    // treatment independently so they can be auditioned in any
    // combination.
    #if DEBUG
    @ViewBuilder
    private var agentBayTreatmentStrip: some View {
        if DesignModeManager.shared.isEnabled {
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: treatment toggles (independent, combinable).
                HStack(spacing: 6) {
                    Text("· TREATMENTS")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopePanel.inkFaint)
                        .frame(width: 90, alignment: .leading)
                    bayChip("LIFT",      isOn: bayLift)      { bayLift.toggle() }
                    bayChip("SPARKLINE", isOn: baySparkline) { baySparkline.toggle() }
                    bayChip("WAVEFORM",  isOn: bayWaveform)  { bayWaveform.toggle() }
                    bayChip("COMPACT",   isOn: bayCompact)   { bayCompact.toggle() }
                    bayChip("BEZEL",     isOn: bayBezel)     { bayBezel.toggle() }
                    bayChip("HEATMAP",   isOn: bayHeatmap)   { bayHeatmap.toggle() }
                    bayChip("TIMELINE",  isOn: bayTimeline)  { bayTimeline.toggle() }
                    bayChip("BRACKETS",  isOn: bayBrackets)  { bayBrackets.toggle() }
                    Spacer(minLength: 0)
                    Button {
                        bayLift = false
                        baySparkline = true
                        bayWaveform = false
                        bayCompact = true
                        bayBezel = false
                        bayHeatmap = false
                        bayTimeline = false
                        bayBrackets = false
                        bayScheme = BayScheme.chiffon.rawValue
                    } label: {
                        Text("RESET")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(ScopePanel.inkSubtle)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }

                // Row 2: color scheme picker (mutually exclusive).
                HStack(spacing: 6) {
                    Text("· SCHEME")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopePanel.inkFaint)
                        .frame(width: 90, alignment: .leading)
                    ForEach(BayScheme.allCases, id: \.self) { option in
                        let raw = option.rawValue
                        let isActive = bayScheme == raw
                        Button {
                            bayScheme = raw
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(option.trace)
                                    .frame(width: 7, height: 7)
                                Text(option.displayName)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .tracking(0.8)
                                    .foregroundStyle(isActive ? ScopePanel.bg : ScopePanel.inkMuted)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isActive ? option.trace : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(
                                        isActive ? option.trace : ScopePanel.Edge.normal,
                                        lineWidth: 0.5
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ScopePanel.bg.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopePanel.Edge.normal, lineWidth: 0.5)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(currentScheme.trace.opacity(0.6))
                    .frame(width: 2)
            }
        }
    }

    private func bayChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(isOn ? ScopePanel.bg : ScopePanel.inkMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isOn ? currentScheme.trace : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            isOn ? currentScheme.trace : ScopePanel.Edge.normal,
                            lineWidth: 0.5
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
    #endif

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
                                Rectangle().fill(ScopeEdge.subtle).frame(height: 0.5)
                            }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.faint, lineWidth: 0.5)
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
                .stroke(ScopeEdge.faint, lineWidth: 0.5)
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

/// Capture mode card — three thin rows on a cream tile.
///
///   ▌ glyph    eyebrow                channel
///   ──────────────────────────────────────
///   state · single factual line
///   ──────────────────────────────────────
///   ACTION →                         hint
///
/// No editorial title or sub-copy. The card is the affordance; the
/// glyph + label + action + hint together communicate enough. Per the
/// no-marketing-copy preference (2026-05-17).
private struct CaptureModeCard: View {
    enum Glyph { case dot, ring, crosshair }

    let glyph: Glyph
    let eyebrow: String
    let channel: String
    let state: String
    let action: String
    let hint: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        #if DEBUG
        let _ = FrameRateMonitor.shared.recordBodyAccess("CaptureModeCard")
        #endif
        return Button(action: onTap) {
            VStack(spacing: 0) {
                identityRow
                Divider()
                    .frame(height: 0.5)
                    .overlay(ScopeEdge.subtle)
                stateRow
                Divider()
                    .frame(height: 0.5)
                    .overlay(ScopeEdge.subtle)
                actionRow
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ScopeCanvas.surface)
                    GraticuleBackground(pitch: 32, color: ScopeTrace.faint, opacity: 0.12)
                        .mask(RoundedRectangle(cornerRadius: 6))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? ScopeEdge.normal : ScopeEdge.faint, lineWidth: 0.5)
            )
            .offset(y: isHovered ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

    private var identityRow: some View {
        HStack(spacing: 10) {
            CaptureGlyph(kind: glyph)
                .frame(width: 22, height: 22)
            Text(eyebrow.uppercased())
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.primary)
            Spacer()
            Text(channel)
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var stateRow: some View {
        HStack {
            Text(state.uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 4) {
            Text(action)
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(isHovered ? ScopeAmber.solid : Color.hex("9A6A22"))
            Text("→")
                .font(.system(size: 11))
                .foregroundStyle(isHovered ? ScopeAmber.solid : Color.hex("9A6A22"))
            Spacer()
            Text(hint)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Per-card amber identity. Three distinct treatments so the cards
/// read as siblings, not clones. All within the amber/copper family
/// per the design language.
private struct CaptureGlyph: View {
    let kind: CaptureModeCard.Glyph

    var body: some View {
        switch kind {
        case .dot:
            ZStack {
                Circle()
                    .stroke(ScopeAmber.solid.opacity(0.18), lineWidth: 1)
                Circle()
                    .fill(ScopeAmber.solid)
                    .frame(width: 9, height: 9)
                    .shadow(color: ScopeAmber.solid.opacity(0.45), radius: 3)
            }
        case .ring:
            ZStack {
                Circle()
                    .stroke(ScopeAmber.solid, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(ScopeAmber.solid)
                    .frame(width: 3.5, height: 3.5)
            }
        case .crosshair:
            ZStack {
                CornerBracketsMark()
                    .stroke(ScopeAmber.solid, lineWidth: 1.2)
                Circle()
                    .fill(ScopeAmber.solid)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

/// Four corner L-marks inscribed in the glyph frame. Used by the
/// "Capture" mode glyph to evoke a viewfinder.
private struct CornerBracketsMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset: CGFloat = 1
        let len: CGFloat = 5
        let minX = rect.minX + inset, maxX = rect.maxX - inset
        let minY = rect.minY + inset, maxY = rect.maxY - inset
        // top-left
        p.move(to: CGPoint(x: minX, y: minY + len))
        p.addLine(to: CGPoint(x: minX, y: minY))
        p.addLine(to: CGPoint(x: minX + len, y: minY))
        // top-right
        p.move(to: CGPoint(x: maxX - len, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY + len))
        // bottom-left
        p.move(to: CGPoint(x: minX, y: maxY - len))
        p.addLine(to: CGPoint(x: minX, y: maxY))
        p.addLine(to: CGPoint(x: minX + len, y: maxY))
        // bottom-right
        p.move(to: CGPoint(x: maxX - len, y: maxY))
        p.addLine(to: CGPoint(x: maxX, y: maxY))
        p.addLine(to: CGPoint(x: maxX, y: maxY - len))
        return p
    }
}

// MARK: - Signal row

private struct SignalRow: View {
    let item: UnifiedActivityItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        #if DEBUG
        let _ = FrameRateMonitor.shared.recordBodyAccess("SignalRow")
        #endif
        return Button(action: action) {
            HStack(spacing: 14) {
                ChannelLabel(item.type == .memo ? "M" : "D",
                             color: item.type == .memo ? ScopeAmber.solid : ScopeInk.muted,
                             strokeColor: ScopeEdge.faint)
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

// MARK: - Agent bay treatment subviews

/// Treatment 2 — per-stat 7-day sparkline. Synthetic data seeded by
/// tile index so each tile reads distinct. Static path; cheap to draw.
private struct StatSparkline: View {
    let seed: Int
    let scheme: BayScheme

    var body: some View {
        GeometryReader { geo in
            let samples = StatSparkline.samples(seed: seed)
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                guard samples.count > 1 else { return }
                let step = w / CGFloat(samples.count - 1)
                for (i, v) in samples.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h - CGFloat(v) * h
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else      { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(scheme.trace.opacity(0.7), lineWidth: 1)
        }
    }

    /// Deterministic pseudo-7-day curve. Mixes a low-frequency sine
    /// with a hashed jitter so each seed is recognizably its own shape
    /// but still smooth.
    static func samples(seed: Int) -> [Double] {
        (0..<7).map { i in
            let phase = Double(seed) * 0.9
            let sine = sin(Double(i) * 0.85 + phase) * 0.3 + 0.55
            let jitter = Double((seed &* 31 &+ i &* 17) & 0xFF) / 255.0 * 0.18
            return min(0.95, max(0.08, sine + jitter - 0.09))
        }
    }
}

/// Treatment 3 — background waveform that runs full-width behind the
/// stats. Static, very low opacity; reads as ambient signal context,
/// not data viz.
private struct BackgroundWaveform: View {
    let scheme: BayScheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mid = h / 2
            Path { path in
                let n = 120
                for i in 0...n {
                    let t = Double(i) / Double(n)
                    let x = CGFloat(t) * w
                    // Two layered sines + deterministic jitter — feels
                    // organic without animating.
                    let a = sin(t * .pi * 6.0) * 0.35
                    let b = sin(t * .pi * 13.0 + 1.2) * 0.18
                    let j = sin(t * .pi * 31.0) * 0.06
                    let y = mid + CGFloat(a + b + j) * (h * 0.32)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else      { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(scheme.trace.opacity(0.18), lineWidth: 0.75)
        }
    }
}

// MARK: - Bay color schemes
//
// Each scheme swaps the phosphor / accent family inside the agent bay
// — the gunmetal bg + rails stay constant, so the bay always reads as
// "instrument bay sunk into cream desk" regardless of which tube color
// is fitted.

enum BayScheme: String, CaseIterable {
    // Aligned with `design/studio/lib/schemes.ts` as of 2026-05-17.
    // The intermediate gray gradient (graphite/pewter/ash/stone) was
    // dropped after the studio review — read as "filtered" rather
    // than designed. New light-mode canonicals from the studio's
    // light-touch sibling work:
    //
    //   Modern theme → PEARL    (cool family, canonical = lightest)
    //   Scope theme  → CHIFFON  (warm family, canonical = lightest)
    //
    // Sibling ladder within each family for fine-tuning bay presence.
    // AMBER kept as the reference for the original lit-electronics
    // identity. See design/studio/app/mac-home/NOTES.md for rationale.
    case amber       // Reference dark (original electronics bay)
    case pearl       // Modern canonical — cool lightest
    case porcelain   // Cool mid
    case aluminum    // Cool saturated
    case chiffon     // Scope canonical — warm lightest
    case vellum      // Warm mid
    case paper       // Warm saturated

    var displayName: String {
        switch self {
        case .amber:     return "AMBER"
        case .pearl:     return "PEARL"
        case .porcelain: return "PORCELAIN"
        case .aluminum:  return "ALUMINUM"
        case .chiffon:   return "CHIFFON"
        case .vellum:    return "VELLUM"
        case .paper:     return "PAPER"
        }
    }

    /// True when the surface is light enough to need dark text on it.
    /// Toggles glow off, switches stat numbers to graphite ink, and
    /// bumps edge contrast. All current non-AMBER schemes are light.
    var isLight: Bool { self != .amber }

    /// Canonical accent. Dark schemes use it as the phosphor for stat
    /// numbers + dot + sparkline; light schemes use it as the edge /
    /// sparkline accent only (stat numbers fall back to `statInk`).
    /// Cool-family accents pull slightly cooler (#D49236); warm-family
    /// stays at the canonical copper (#9A6A22). AMBER is the original
    /// phosphor.
    var trace: Color {
        switch self {
        case .amber:                              return Color.hex("E89A3C")
        case .pearl, .porcelain, .aluminum:       return Color.hex("D49236")
        case .chiffon, .vellum, .paper:           return Color.hex("9A6A22")
        }
    }

    /// Glow halo. Light schemes disable glow — printed surfaces don't
    /// emit light, so the halo would just look smudgy.
    var traceGlow: Color { isLight ? .clear : trace.opacity(0.50) }

    /// Background graticule tint — barely-there.
    var traceFaint: Color { trace.opacity(isLight ? 0.06 : 0.08) }

    /// Edge / divider color — same hue as trace, very low alpha.
    /// Lighter schemes need slightly more contrast to read.
    var edge: Color {
        switch self {
        case .amber:                 return trace.opacity(0.10)
        case .pearl, .chiffon:       return trace.opacity(0.10)   // lightest — kept restrained
        case .porcelain, .vellum:    return trace.opacity(0.12)
        case .aluminum, .paper:      return trace.opacity(0.18)   // most saturated of the light family
        }
    }

    /// Edge for crisper marks (corner brackets).
    var edgeStrong: Color {
        switch self {
        case .amber:                 return trace.opacity(0.28)
        case .pearl, .chiffon:       return trace.opacity(0.28)
        case .porcelain, .vellum:    return trace.opacity(0.34)
        case .aluminum, .paper:      return trace.opacity(0.40)
        }
    }

    /// Cell color for the activity heatmap. Intensity-scaled at call site.
    func cell(intensity: Double) -> Color {
        let base = isLight ? 0.12 : 0.10
        let span = isLight ? 0.55 : 0.60
        return trace.opacity(base + span * intensity)
    }

    // MARK: Surface tokens

    /// Bay panel base fill. Mirrors `--scheme-bg` from studio.
    var panelBg: Color {
        switch self {
        case .amber:      return Color.hex("14181A")
        case .pearl:      return Color.hex("F5F8FA")
        case .porcelain:  return Color.hex("EAEEF1")
        case .aluminum:   return Color.hex("D6DBE0")
        case .chiffon:    return Color.hex("FAF5E8")
        case .vellum:     return Color.hex("F4EFE0")
        case .paper:      return Color.hex("EEE7D6")
        }
    }

    /// Stat number color. Dark → phosphor; light → deep neutral ink
    /// tuned to the scheme's warmth.
    var statInk: Color {
        switch self {
        case .amber:                                    return trace
        case .pearl, .porcelain, .aluminum:             return Color.hex("2A2E32")   // cool charcoal
        case .chiffon, .vellum, .paper:                 return Color.hex("2A2520")   // warm espresso
        }
    }

    /// Chrome label color (status text, captions).
    var inkFaint: Color {
        switch self {
        case .amber:      return Color.hex("7A8B85")
        case .pearl:      return Color.hex("6E737B")
        case .porcelain:  return Color.hex("5C6168")
        case .aluminum:   return Color.hex("5C6168")
        case .chiffon:    return Color.hex("7B6E60")
        case .vellum:     return Color.hex("6B5D4F")
        case .paper:      return Color.hex("6B5D4F")
        }
    }

    /// Subtle chrome (timestamps, secondary metadata).
    var inkSubtle: Color {
        switch self {
        case .amber:      return Color.hex("6B7A75")
        case .pearl:      return Color.hex("8A8F96")
        case .porcelain:  return Color.hex("787D84")
        case .aluminum:   return Color.hex("4F545B")
        case .chiffon:    return Color.hex("928576")
        case .vellum:     return Color.hex("857664")
        case .paper:      return Color.hex("5C4F42")
        }
    }

    /// Top control rail — brushed cover. Tuned per scheme; lightest
    /// at top, darker into the body so the strip reads as a separate
    /// fabricated piece.
    var stripTopFill: LinearGradient {
        let stops: [(String, Double)] = {
            switch self {
            case .amber:
                return [("1F2426", 0.0), ("1A1F22", 0.35), ("0F1416", 1.0)]
            case .pearl:
                return [("FBFCFE", 0.0), ("F2F5F7", 0.60), ("E5E9ED", 1.0)]
            case .porcelain:
                return [("F2F5F7", 0.0), ("E8ECEF", 0.60), ("DCE0E4", 1.0)]
            case .aluminum:
                return [("DFE3E8", 0.0), ("D4D8DD", 0.60), ("C8CDD2", 1.0)]
            case .chiffon:
                return [("FDF8EB", 0.0), ("F5F0E2", 0.60), ("ECE7D6", 1.0)]
            case .vellum:
                return [("F8F3E5", 0.0), ("F0EBDB", 0.60), ("E8E2D0", 1.0)]
            case .paper:
                return [("F2ECDB", 0.0), ("EAE3D0", 0.60), ("E2DBC6", 1.0)]
            }
        }()
        return LinearGradient(
            stops: stops.map { .init(color: Color.hex($0.0), location: $0.1) },
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Bottom rail — recessed feel. Asymmetric with stripTop.
    var stripBottomFill: LinearGradient {
        let stops: [(String, Double)] = {
            switch self {
            case .amber:
                return [("0D1113", 0.0), ("161B1E", 0.55), ("1E2528", 1.0)]
            case .pearl:
                return [("ECEFF2", 0.0), ("F5F8FA", 0.55), ("FBFDFE", 1.0)]
            case .porcelain:
                return [("E0E4E8", 0.0), ("EAEEF1", 0.55), ("F0F3F6", 1.0)]
            case .aluminum:
                return [("CFD4D9", 0.0), ("D6DBE0", 0.55), ("DDE2E7", 1.0)]
            case .chiffon:
                return [("F0ECDE", 0.0), ("F8F3E6", 0.55), ("FDF9EC", 1.0)]
            case .vellum:
                return [("ECE6D6", 0.0), ("F4EFE0", 0.55), ("F9F4E6", 1.0)]
            case .paper:
                return [("E2DAC4", 0.0), ("EBE3CD", 0.55), ("F3ECD8", 1.0)]
            }
        }()
        return LinearGradient(
            stops: stops.map { .init(color: Color.hex($0.0), location: $0.1) },
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Theme bindings

    /// Canonical scheme for a given Talkie theme. Used by the bay's
    /// default state when no user-set value is stored.
    static func canonical(for theme: ThemePreset?) -> BayScheme {
        switch theme {
        case .scope:       return .chiffon
        // case .modern:   return .pearl     // future — when modern theme lands
        default:           return .amber
        }
    }
}

// MARK: - More agent bay treatments

/// Inner highlight (top) + inner shadow (bottom) so the bay reads as
/// physically sunk into the cream desk. Drawn as two thin gradient
/// rings inside the rounded rect. Light schemes use a much softer
/// shadow — a heavy black ring on cream paper reads as cheap chrome.
struct BezelOverlay: View {
    let scheme: BayScheme

    var body: some View {
        let highlightTop = scheme.isLight ? 0.45 : 0.10
        let highlightMid = scheme.isLight ? 0.10 : 0.02
        let shadowMid    = scheme.isLight ? 0.06 : 0.20
        let shadowBottom = scheme.isLight ? 0.14 : 0.45

        ZStack {
            // Top inner highlight — catches the light from above.
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlightTop),
                            Color.white.opacity(highlightMid),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)

            // Bottom inner shadow — recess cue.
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(shadowMid),
                            Color.black.opacity(shadowBottom)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(1.5)
        }
        .allowsHitTesting(false)
    }
}

/// 7-day phosphor heatmap. 7 columns × 5 rows of small cells; each
/// cell's opacity is seeded so the grid reads as a recent-activity
/// matrix without real data plumbing.
struct ActivityHeatmap: View {
    let scheme: BayScheme

    var body: some View {
        let cols = 7
        let rows = 5
        let cellSize: CGFloat = 8
        let gap: CGFloat = 2

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("LAST 7d")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(scheme.inkFaint)
                Spacer()
            }
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<cols, id: \.self) { c in
                            let intensity = ActivityHeatmap.intensity(row: r, col: c)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(scheme.cell(intensity: intensity))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
        .frame(width: CGFloat(cols) * cellSize + CGFloat(cols - 1) * gap, alignment: .leading)
    }

    static func intensity(row: Int, col: Int) -> Double {
        // Deterministic seeded intensity — diagonal-ish ramp w/ noise.
        let base = Double((col &* 23 &+ row &* 41 &+ 7) & 0xFF) / 255.0
        let bias = Double(col) / 7.0 * 0.4
        let v = base * 0.7 + bias
        return min(1.0, max(0.05, v))
    }
}

/// 24h tick ribbon. Each of 48 half-hour columns gets a vertical tick
/// whose height encodes synthetic activity density. Static.
struct TodayTimeline: View {
    let scheme: BayScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text("00").chromeLabel(color: scheme.inkSubtle)
                Spacer()
                Text("06").chromeLabel(color: scheme.inkSubtle)
                Spacer()
                Text("12").chromeLabel(color: scheme.inkSubtle)
                Spacer()
                Text("18").chromeLabel(color: scheme.inkSubtle)
                Spacer()
                Text("24").chromeLabel(color: scheme.inkSubtle)
            }
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(0..<48, id: \.self) { i in
                        let intensity = TodayTimeline.intensity(slot: i)
                        Rectangle()
                            .fill(scheme.trace.opacity(0.18 + 0.55 * intensity))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, geo.size.height * CGFloat(intensity)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 14)
        }
    }

    static func intensity(slot: Int) -> Double {
        // Bursty pattern: heavier mid-morning + evening, quiet overnight.
        let hour = Double(slot) / 2.0
        let morning = exp(-pow((hour - 10) / 3.0, 2)) * 0.75
        let evening = exp(-pow((hour - 20) / 2.5, 2)) * 0.55
        let jitter = Double((slot &* 53 &+ 11) & 0xFF) / 255.0 * 0.15
        return min(1.0, max(0.04, morning + evening + jitter * 0.4))
    }
}

private extension Text {
    func chromeLabel(color: Color) -> some View {
        self
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// Viewfinder-style L-shaped corner crops drawn inside the panel.
/// Inset slightly from the rounded edge so they read as crop marks,
/// not as a second border.
struct BayCornerBrackets: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 8
            let len: CGFloat = 10
            let w = geo.size.width
            let h = geo.size.height

            Path { p in
                // Top-left
                p.move(to: CGPoint(x: inset, y: inset + len))
                p.addLine(to: CGPoint(x: inset, y: inset))
                p.addLine(to: CGPoint(x: inset + len, y: inset))
                // Top-right
                p.move(to: CGPoint(x: w - inset - len, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset + len))
                // Bottom-left
                p.move(to: CGPoint(x: inset, y: h - inset - len))
                p.addLine(to: CGPoint(x: inset, y: h - inset))
                p.addLine(to: CGPoint(x: inset + len, y: h - inset))
                // Bottom-right
                p.move(to: CGPoint(x: w - inset - len, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset - len))
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Routines panel
//
// Light cream panel with header rail (title + trailing chrome), a
// short list of rows, and a footer link. Used for both Workflows and
// Console quick-entries in the Routines strip.

private struct RoutinesPanel: View {
    enum Dot { case filled, hollow }
    struct Row { let leading: Dot; let label: String; let trailing: String }

    let title: String
    let trailing: String
    let rows: [Row]
    let footer: String

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(ScopeFont.display(size: 14, medium: true))
                    .foregroundStyle(ScopeInk.primary)
                Spacer()
                Text(trailing.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ScopeEdge.subtle).frame(height: 0.5)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(row.leading == .filled ? Color.hex("9A6A22") : Color.clear)
                            .overlay(
                                Circle().stroke(Color.hex("9A6A22"), lineWidth: row.leading == .hollow ? 1 : 0)
                            )
                            .frame(width: 5, height: 5)
                        Text(row.label)
                            .font(.system(size: 12))
                            .foregroundStyle(ScopeInk.primary)
                        Spacer()
                        Text(row.trailing.uppercased())
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.subtle)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    if idx < rows.count - 1 {
                        Rectangle().fill(ScopeEdge.subtle).frame(height: 0.5)
                    }
                }
            }

            Rectangle().fill(ScopeEdge.subtle).frame(height: 0.5)

            HStack(spacing: 4) {
                Spacer()
                Text(footer)
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(isHovered ? ScopeAmber.solid : Color.hex("9A6A22"))
                Text("→")
                    .font(.system(size: 11))
                    .foregroundStyle(isHovered ? ScopeAmber.solid : Color.hex("9A6A22"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(ScopeCanvas.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? ScopeEdge.normal : ScopeEdge.faint, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

// MARK: - Discovery widgets

/// Today — small 24h timeline with event dots. Reads as a day-at-a-
/// glance map, not a list. Sample events for now.
// Learn widget — replaced the Today calendar. Surfaces a rotating
// "did you know" hook from the Learn screen's RecapCard vocabulary:
// eyebrow + serif hook + body + action. Reads as editorial discovery
// rather than a dashboard widget, lifting the midsection.
private struct LearnWidget: View {
    private struct Hook { let eyebrow: String; let hook: String; let detail: String; let action: String }
    private let hooks: [Hook] = [
        .init(
            eyebrow: "Voice edit",
            hook: "Talk back to a memo.",
            detail: "Hit ⌃⇧⌘ E during playback to dictate an edit in place.",
            action: "Try it"
        ),
        .init(
            eyebrow: "Smart actions",
            hook: "Fix grammar with a chip.",
            detail: "Compose has one-tap chips for grammar, concise, and tone.",
            action: "See compose"
        ),
        .init(
            eyebrow: "Tray",
            hook: "Hyper+S, anywhere.",
            detail: "Screenshots drain into your next memo unless you pin them.",
            action: "How it works"
        ),
    ]

    // Stable random pick per session — feels alive without flicker.
    @State private var pickIndex: Int = 0
    @State private var isHovered: Bool = false

    var body: some View {
        let hook = hooks[pickIndex % hooks.count]
        DiscoveryWidgetCard(title: "Learn", eyebrow: "Did you know") {
            Button(action: { NavigationState.shared.navigate(to: .liveDashboard) }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("· " + hook.eyebrow.uppercased())
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .tracking(2.4)
                        .foregroundStyle(Color.hex("9A6A22"))
                    Text(hook.hook)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .tracking(-0.2)
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(hook.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.faint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text(hook.action.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(2.2)
                        Text("→").font(.system(size: 10))
                    }
                    .foregroundStyle(isHovered ? Color.hex("7A521A") : Color.hex("9A6A22"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .onAppear {
                pickIndex = Int.random(in: 0..<hooks.count)
            }
        }
    }
}

// Legacy TodayWidget — dead from the Discovery row, kept for any
// callers we might have missed. Will be removed in a cleanup pass.
private struct TodayWidget: View {
    private struct Event { let hour: Double; let label: String }
    private let events: [Event] = [
        .init(hour: 9.5,  label: "09:30 · Design review"),
        .init(hour: 11.0, label: "11:00 · Standup"),
        .init(hour: 14.0, label: "14:00 · Bay polish merge"),
    ]

    var body: some View {
        DiscoveryWidgetCard(title: "Today", eyebrow: "Calendar") {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(ScopeEdge.faint)
                            .frame(height: 0.5)
                            .offset(y: 10)
                        ForEach([0, 4, 8, 12, 16, 20, 24], id: \.self) { h in
                            let x = CGFloat(h) / 24.0 * geo.size.width
                            VStack(spacing: 2) {
                                Rectangle()
                                    .fill(ScopeEdge.faint)
                                    .frame(width: 1, height: 4)
                                Text(String(format: "%02d", h))
                                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                    .tracking(0.6)
                                    .foregroundStyle(ScopeInk.subtle)
                            }
                            .offset(x: x - 6, y: 6)
                        }
                        ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                            let x = CGFloat(event.hour) / 24.0 * geo.size.width
                            Circle()
                                .fill(Color.hex("9A6A22"))
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle().stroke(ScopeCanvas.surface, lineWidth: 2)
                                )
                                .offset(x: x - 5, y: 5)
                        }
                    }
                }
                .frame(height: 26)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        HStack {
                            let parts = event.label.split(separator: " · ", maxSplits: 1).map(String.init)
                            Text(parts.first ?? event.label)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(ScopeInk.primary)
                            Spacer()
                            Text(parts.count > 1 ? parts[1] : "")
                                .font(.system(size: 11))
                                .foregroundStyle(ScopeInk.faint)
                        }
                    }
                }
            }
        }
    }
}

/// Shortcuts — proper key-cap glyphs grouped vertically.
private struct ShortcutsWidget: View {
    private struct Shortcut { let keys: [String]; let label: String }
    private let shortcuts: [Shortcut] = [
        .init(keys: ["⌃", "⇧", "⌘", "M"], label: "New Memo"),
        .init(keys: ["⌃", "⇧", "⌘", "D"], label: "Dictate"),
        .init(keys: ["⌃", "⇧", "⌘", "S"], label: "Capture screen"),
        .init(keys: ["⌃", "⇧", "⌘", "L"], label: "Library"),
    ]

    var body: some View {
        DiscoveryWidgetCard(title: "Shortcuts", eyebrow: "Keyboard") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, s in
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            ForEach(s.keys, id: \.self) { key in
                                Text(key)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ScopeInk.primary)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(ScopeCanvas.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(ScopeEdge.normal, lineWidth: 0.5)
                                    )
                            }
                        }
                        Text(s.label)
                            .font(.system(size: 11))
                            .foregroundStyle(ScopeInk.faint)
                        Spacer()
                    }
                }
            }
        }
    }
}

/// Trending — tag + horizontal bar + count. Mini histogram, not a list.
private struct TrendingWidget: View {
    private struct Trend { let tag: String; let count: Int }
    private let trends: [Trend] = [
        .init(tag: "Standups",       count: 8),
        .init(tag: "Compose drafts", count: 5),
        .init(tag: "Code review",    count: 3),
        .init(tag: "Design notes",   count: 2),
    ]
    private var maxCount: Int { trends.map(\.count).max() ?? 1 }

    var body: some View {
        DiscoveryWidgetCard(title: "Trending", eyebrow: "This week") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(trends.enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 10) {
                        Text(t.tag)
                            .font(.system(size: 11))
                            .foregroundStyle(ScopeInk.primary)
                            .frame(width: 110, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(ScopeEdge.faint)
                                Rectangle()
                                    .fill(Color.hex("9A6A22"))
                                    .frame(width: geo.size.width * CGFloat(t.count) / CGFloat(maxCount))
                            }
                        }
                        .frame(height: 6)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                        Text("\(t.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(ScopeInk.subtle)
                            .frame(width: 16, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Shared discovery widget chrome — title + trailing eyebrow + content.
/// Named `DiscoveryWidgetCard` to avoid colliding with `WidgetCard` in
/// `HomeWidgets.swift`, which serves the original (non-Scope) Home grid.
private struct DiscoveryWidgetCard<Content: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(ScopeFont.display(size: 13, medium: true))
                    .foregroundStyle(ScopeInk.primary)
                Spacer()
                Text(eyebrow.uppercased())
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ScopeEdge.subtle).frame(height: 0.5)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScopeCanvas.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ScopeEdge.faint, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - System status rail
//
// Scheme-aware footer rail. Inherits the bay's scheme so the bay and
// rail read as the two ends of the same instrument body, with the
// editorial light surfaces between them. On dark schemes (AMBER) it's
// a gunmetal recessed strip; on light (PEARL/CHIFFON/etc.) it's a
// barely-there chrome rail.

private struct SystemStatusRail: View {
    let scheme: BayScheme

    @State private var serviceManager = ServiceManager.shared

    var body: some View {
        let launchAgentInfos = serviceManager.launchAgentInfos
        let agentInfo = launchAgentInfo(named: "TalkieAgent", in: launchAgentInfos)
        let syncInfo = launchAgentInfo(named: "TalkieSync", in: launchAgentInfos)
        let _ = serviceManager.live.isRunning
        let _ = serviceManager.sync.isRunning

        return HStack(spacing: 18) {
            phosphor(label: "AGENT",   detail: agentDetail(agentInfo), state: launchAgentDotState(agentInfo))
            divider
            phosphor(label: "BRIDGE",  detail: bridgeDetail, state: bridgeDotState)
            divider
            phosphor(label: "ICLOUD",  detail: iCloudDetail(syncInfo), state: launchAgentDotState(syncInfo))
            divider
            phosphor(label: "UPDATES", detail: "CURRENT", state: .muted)
            Spacer()
            Text(uptimeChrome)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(scheme.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(scheme.stripBottomFill)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(scheme.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private enum DotState { case ok, warn, muted }

    private func launchAgentInfo(named displayName: String, in infos: [LaunchAgentInfo]) -> LaunchAgentInfo? {
        infos.first { $0.displayName == displayName }
    }

    private func agentDetail(_ info: LaunchAgentInfo?) -> String {
        "AG-01 · \(launchAgentStatusText(info, loadedText: "RUNNING"))"
    }

    private var bridgeDetail: String {
        serviceManager.live.isXPCConnected ? "LOCAL · CONNECTED" : "LOCAL · OFFLINE"
    }

    private func iCloudDetail(_ info: LaunchAgentInfo?) -> String {
        launchAgentStatusText(info, loadedText: "SYNCED")
    }

    private var bridgeDotState: DotState {
        serviceManager.live.isXPCConnected ? .ok : .warn
    }

    private func launchAgentStatusText(_ info: LaunchAgentInfo?, loadedText: String) -> String {
        guard let info, info.isInstalled else { return "NOT INSTALLED" }
        return info.isLoaded ? loadedText : "INSTALLED"
    }

    private func launchAgentDotState(_ info: LaunchAgentInfo?) -> DotState {
        switch info?.statusColor {
        case "green": return .ok
        case "orange": return .warn
        default: return .muted
        }
    }

    private func phosphor(label: String, detail: String, state: DotState) -> some View {
        HStack(spacing: 6) {
            let dotColor: Color = {
                switch state {
                case .ok:    return scheme.trace
                case .warn:  return Color.hex("C77F2E")
                case .muted: return scheme.inkSubtle
                }
            }()
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: scheme.isLight ? .clear : dotColor.opacity(0.55), radius: 3)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(scheme.inkFaint)
            Text(detail)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(scheme.inkSubtle)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(scheme.edge)
            .frame(width: 0.5, height: 12)
    }

    private var uptimeChrome: String {
        let uptime = CFAbsoluteTimeGetCurrent() - StartupProfiler.shared.processStart
        return "PID \(ProcessInfo.processInfo.processIdentifier) · UPTIME \(Self.uptimeText(uptime))"
    }

    private static func uptimeText(_ uptime: TimeInterval) -> String {
        let totalMinutes = max(0, Int(uptime / 60))
        if totalMinutes < 1 { return "0M" }
        if totalMinutes < 60 { return "\(totalMinutes)M" }

        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours < 24 {
            if minutes == 0 { return "\(totalHours)H" }
            return "\(totalHours)H \(minutes)M"
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        if hours == 0 { return "\(days)D" }
        return "\(days)D \(hours)H"
    }
}
