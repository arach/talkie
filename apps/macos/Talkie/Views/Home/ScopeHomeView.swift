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

import AppKit
import SwiftUI
import TalkieKit

// Display + mono font lookups centralized in `ScopeType` (TalkieKit/UI/ScopeDesign.swift).

struct ScopeHomeView: View {
    @Environment(\.chromeBarHeader) private var chromeBarHeader

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
    // Default to CARBON so the top instrument continues the dark Scope
    // chassis instead of reverting to a light insert.
    @AppStorage("scopeAgentBay.scheme")    private var bayScheme: String = BayScheme.carbon.rawValue
    @AppStorage("scopeAgentBay.migratedDefaultCarbon") private var didMigrateBayDefaultToCarbon: Bool = false
    // Migration fallback: users with deprecated stored values
    // (graphite/pewter/ash/stone — dropped 2026-05-17) decode to nil
    // and should land on the Scope canonical, not the original amber.
    private var currentScheme: BayScheme { BayScheme(rawValue: bayScheme) ?? .carbon }

    @State private var memosStore = MemosViewModel.shared
    @State private var dictationStore = DictationStore.shared
    @State private var recordingsVM = RecordingsViewModel.shared
    @State private var workflowExecutor = WorkflowExecutor.shared
    @State private var screenshotTray = ScreenshotTray.shared
    @State private var clipTray = ClipTray.shared
    @State private var selectionTray = SelectionTray.shared
    // In-window markup takeover target (vs. the old floating panel).
    @State private var markupURL: URL?

    // ⌘-hold quick-jump. While Command is held, badges fade in over the
    // section links (⌘M/⌘D/⌘C/⌘N → that library) and recent rows (⌘1–9 →
    // open). Mirrors the library's filter-tab / list-row idiom.
    @State private var cmdHeld = false
    @State private var cmdEventMonitor: Any?

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
                }
                .padding(.horizontal, 32)
                // Top padding clears the universal ScopeTopBand (44pt
                // tall, offset by 4pt) plus enough breathing room that
                // the agent panel's RUNNING strip doesn't crowd the
                // band's bottom rule. Was 8pt — felt clipped under the
                // band.
                .padding(.top, ScopeTopBandLayout.height + ScopeTopBandLayout.topInset + 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
        .environment(\.cmdHeld, cmdHeld)
        .background(cmdShortcutBindings)
        .onAppear {
            migrateDefaultBaySchemeIfNeeded()
            startCmdMonitor()
        }
        .onDisappear { stopCmdMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            resetCmdHeld()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            resetCmdHeld()
        }
        .captureMarkupHost(url: $markupURL)
        .task {
            // Home has no chrome-bar title — the TALKIE pill + the rail's
            // highlighted home icon carry identity, and word/streak chrome
            // lives in the AGENT card below. Clear so a stale title from
            // a sibling page (e.g. Library) doesn't leak in.
            chromeBarHeader.clear()
            await memosStore.loadStats()
            await workflowExecutor.refreshHomeHistory()
            if recordingsVM.recordings.isEmpty {
                await recordingsVM.loadRecordings()
            }
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

    private func migrateDefaultBaySchemeIfNeeded() {
        guard !didMigrateBayDefaultToCarbon else { return }
        if bayScheme == BayScheme.chiffon.rawValue {
            bayScheme = BayScheme.carbon.rawValue
        }
        didMigrateBayDefaultToCarbon = true
    }

    /// Streak + word count promoted to inline chrome — the longer
    /// subhead copy lives in the agent-bay panel below.
    private var heroTrailing: String {
        let totalWordsStr = totalWords > 1000
            ? "\(totalWords / 1000)K WORDS"
            : "\(totalWords) WORDS"
        if streak > 1 {
            // Was "\(streak)-DAY STREAK …" — the hyphen glued the count
            // to its unit and read tighter than the parallel "X WORDS"
            // form. Now reads "15 DAY STREAK · 200 WORDS".
            return "\(streak) DAY STREAK · \(totalWordsStr)"
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
                    onTap: triggerDictation
                )
                CaptureModeCard(
                    glyph: .crosshair,
                    eyebrow: "Capture",
                    channel: "CH-03",
                    state: captureStateTray,
                    action: "CAPTURE",
                    hint: "⌃⇧⌘ S",
                    onTap: triggerCapture
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
                        count: countLabel(todayCount(recentMemos), "today"),
                        libraryLabel: "ALL MEMOS",
                        onLibrary: { NavigationState.shared.navigate(to: .recordings) },
                        rows: recentMemos.prefix(3).enumerated().map { idx, obj in
                            RecentRow(
                                id: obj.id,
                                glyph: "●",
                                line: rowLine(for: obj),
                                body: nil,
                                meta: durationLabel(obj.duration),
                                when: whenLabel(obj.createdAt),
                                onTap: { NavigationState.shared.navigate(to: .recordings, params: ["recordingId": obj.id.uuidString]) },
                                menuActions: memoMenuActions(for: obj),
                                shortcutNumber: shortcutNumber(base: memoShortcutBase, index: idx)
                            )
                        },
                        emptyCTA: RecentCTA(
                            glyph: "●",
                            label: "Start a memo",
                            kbd: ["⌃", "⇧", "⌘", "M"],
                            onTap: onStartRecording
                        ),
                        shortcutLetter: "M"
                    ),
                    RecentSection(
                        id: "dictations",
                        eyebrow: "Dictations",
                        count: countLabel(todayCount(recentDictations), "today"),
                        libraryLabel: "ALL DICTATIONS",
                        onLibrary: { NavigationState.shared.navigate(to: .dictations) },
                        rows: recentDictations.prefix(3).enumerated().map { idx, obj in
                            RecentRow(
                                id: obj.id,
                                glyph: "○",
                                line: rowLine(for: obj),
                                body: nil,
                                meta: wordCountLabel(obj.text),
                                when: whenLabel(obj.createdAt),
                                onTap: { NavigationState.shared.navigate(to: .dictations, params: ["recordingId": obj.id.uuidString]) },
                                menuActions: dictationMenuActions(for: obj),
                                shortcutNumber: shortcutNumber(base: dictationShortcutBase, index: idx)
                            )
                        },
                        emptyCTA: RecentCTA(
                            glyph: "○",
                            label: "Dictate",
                            kbd: ["⌃", "⇧", "⌘", "D"],
                            onTap: triggerDictation
                        ),
                        shortcutLetter: "D"
                    ),
                ],
                contentSections: [
                    RecentSection(
                        id: "captures",
                        eyebrow: "Captures",
                        count: countLabel(todayCount(recentCaptures), "today"),
                        libraryLabel: "ALL CAPTURES",
                        onLibrary: { NavigationState.shared.navigate(to: .screenshots) },
                        secondaryLabel: "OPEN TRAY",
                        onSecondary: { TrayViewer.shared.show() },
                        rows: recentCaptures.prefix(3).enumerated().map { idx, item in
                            RecentRow(
                                id: item.id,
                                glyph: "◫",
                                line: item.line,
                                body: nil,
                                meta: item.meta,
                                when: whenLabel(item.date),
                                onTap: { openRecentCapture(item) },
                                menuActions: captureMenuActions(for: item),
                                shortcutNumber: shortcutNumber(base: captureShortcutBase, index: idx)
                            )
                        },
                        emptyCTA: RecentCTA(
                            glyph: "◫",
                            label: "Capture screen",
                            kbd: ["⌃", "⇧", "⌘", "S"],
                            onTap: triggerCapture
                        ),
                        shortcutLetter: "C"
                    ),
                    RecentSection(
                        id: "notes",
                        eyebrow: "Notes",
                        count: countLabel(recentNotes.count, "this week"),
                        libraryLabel: "ALL NOTES",
                        onLibrary: { NavigationState.shared.navigate(to: .notes) },
                        rows: recentNotes.prefix(3).enumerated().map { idx, obj in
                            RecentRow(
                                id: obj.id,
                                glyph: "¶",
                                line: noteTitle(for: obj),
                                body: noteBodyExcerpt(for: obj),
                                meta: "",
                                when: whenLabel(obj.createdAt),
                                // Route via the Library so the inspector
                                // swap (recording.type == .note →
                                // ScopeNoteDetailView) actually fires.
                                // `.notes` lands on the Sheaf grid and
                                // ignores recordingId.
                                onTap: { NavigationState.shared.navigate(to: .recordings, params: ["recordingId": obj.id.uuidString]) },
                                menuActions: noteMenuActions(for: obj),
                                shortcutNumber: shortcutNumber(base: noteShortcutBase, index: idx)
                            )
                        },
                        emptyCTA: RecentCTA(
                            glyph: "¶",
                            label: "Write a note",
                            kbd: ["⌃", "⇧", "⌘", "N"],
                            onTap: triggerNewNote
                        ),
                        shortcutLetter: "N"
                    ),
                ]
            )
        }
    }

    // MARK: - Capture / dictation / note triggers
    //
    // These mirror the keyboard-shortcut path so home-screen CTAs and
    // hotkeys converge on the same code, avoiding state drift. (Audit #2:
    // these used to be `onTap: {}` — kind of the worst impression a new
    // user could get clicking around the home screen.)

    // MARK: - ⌘-hold quick-jump
    //
    // Held-Command reveals badges (rendered in RecentTwoPane via the
    // `cmdHeld` environment value) and the hidden buttons below bind the
    // matching keys. Section letters jump to a library; ⌘1–9 open the Nth
    // recent row in the same column-major order the badges number them.

    /// 1-based badge offset for each section's first row. Rows past the
    /// 9th get no badge (`shortcutNumber` returns nil).
    private var memoShortcutBase: Int { 0 }
    private var dictationShortcutBase: Int { min(recentMemos.count, 3) }
    private var captureShortcutBase: Int { dictationShortcutBase + min(recentDictations.count, 3) }
    private var noteShortcutBase: Int { captureShortcutBase + min(recentCaptures.count, 3) }

    private func shortcutNumber(base: Int, index: Int) -> Int? {
        let n = base + index + 1
        return n <= 9 ? n : nil
    }

    /// Recent-row tap actions flattened in the same order the badges
    /// number them (Memos → Dictations → Captures → Notes, ≤3 each),
    /// capped at 9 so ⌘1–9 line up with what's on screen.
    private var orderedRecentTapActions: [() -> Void] {
        var actions: [() -> Void] = []
        for obj in recentMemos.prefix(3) {
            let id = obj.id
            actions.append { NavigationState.shared.navigate(to: .recordings, params: ["recordingId": id.uuidString]) }
        }
        for obj in recentDictations.prefix(3) {
            let id = obj.id
            actions.append { NavigationState.shared.navigate(to: .dictations, params: ["recordingId": id.uuidString]) }
        }
        for item in recentCaptures.prefix(3) {
            actions.append { openRecentCapture(item) }
        }
        for obj in recentNotes.prefix(3) {
            let id = obj.id
            actions.append { NavigationState.shared.navigate(to: .recordings, params: ["recordingId": id.uuidString]) }
        }
        return Array(actions.prefix(9))
    }

    private func openRecentItem(at position: Int) {
        let actions = orderedRecentTapActions
        guard position >= 1, position <= actions.count else { return }
        actions[position - 1]()
    }

    /// Always-active hidden buttons backing the ⌘ shortcuts. The badges
    /// are purely visual; these do the work. Mounted via `.background`.
    @ViewBuilder
    private var cmdShortcutBindings: some View {
        Group {
            Button("") { NavigationState.shared.navigate(to: .recordings) }
                .keyboardShortcut("m", modifiers: [.command])
            Button("") { NavigationState.shared.navigate(to: .dictations) }
                .keyboardShortcut("d", modifiers: [.command])
            Button("") { NavigationState.shared.navigate(to: .screenshots) }
                .keyboardShortcut("c", modifiers: [.command])
            Button("") { NavigationState.shared.navigate(to: .notes) }
                .keyboardShortcut("n", modifiers: [.command])
            ForEach(1...9, id: \.self) { n in
                Button("") { openRecentItem(at: n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [.command])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func startCmdMonitor() {
        stopCmdMonitor()
        cmdHeld = NSEvent.modifierFlags.contains(.command)
        cmdEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let isHeld = event.modifierFlags.contains(.command)
            if isHeld != cmdHeld {
                withAnimation(.easeOut(duration: 0.12)) { cmdHeld = isHeld }
            }
            return event
        }
    }

    private func stopCmdMonitor() {
        if let monitor = cmdEventMonitor {
            NSEvent.removeMonitor(monitor)
            cmdEventMonitor = nil
        }
        cmdHeld = false
    }

    private func resetCmdHeld() {
        guard cmdHeld else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            cmdHeld = false
        }
    }

    /// Toggle the live dictation pipeline. Same path as ⌃⇧⌘D.
    private func triggerDictation() {
        ServiceManager.shared.live.toggleRecording()
    }

    /// Fire a region-mode standalone capture via AppDelegate's executeCapture,
    /// which is the same pipeline used by the hotkey-driven shortcut.
    private func triggerCapture() {
        Task { @MainActor in
            guard let delegate = NSApp.delegate as? AppDelegate else { return }
            _ = await delegate.executeCapture(mode: .region)
        }
    }

    /// Create a blank note row, save it, then deep-link into the library
    /// detail (which mounts ScopeNoteDetailView in edit-ready state).
    private func triggerNewNote() {
        Task { @MainActor in
            let id = UUID()
            let note = TalkieObject.newNote(id: id, text: "")
            do {
                let repository = TalkieObjectRepository()
                try await repository.saveRecording(note)
                await RecordingsViewModel.shared.loadRecordings()
                NavigationState.shared.navigate(to: .recordings, params: ["recordingId": id.uuidString])
            } catch {
                TalkieConsole.info("⚠️ ScopeHomeView: failed to create note: \(error)")
            }
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

    /// How many of `items` were created today. The Voice / Content
    /// section labels say "X today" — they meant today specifically,
    /// not all-time. Without this filter the label was rendering
    /// "49 today" when the user had 49 dictations total but only 8
    /// from today, and rows were collapsing to the CTA when the
    /// all-time count happened to be 0 even though the user clearly
    /// had older items.
    private func todayCount(_ items: [TalkieObject]) -> Int {
        let cal = Calendar.current
        return items.filter { cal.isDateInToday($0.createdAt) }.count
    }
    private func todayCount(_ items: [TrayItem]) -> Int {
        let cal = Calendar.current
        return items.filter { cal.isDateInToday($0.capturedAt) }.count
    }
    private var recentTrayItems: [TrayItem] {
        TrayItem.allItems().sorted { $0.capturedAt > $1.capturedAt }
    }

    /// Unified screenshot-capture stream for Home. Keep this scoped to
    /// screenshots: still-in-tray `ScreenshotTray` items and saved
    /// `.capture` objects. It intentionally excludes text selections,
    /// camera clips, standalone notes, and iPhone/watch imports.
    private struct RecentCapture: Identifiable {
        enum Source {
            case tray
            case savedCapture
        }

        let id: UUID
        let line: String
        let meta: String
        let date: Date
        let source: Source
        /// On-disk PNG path — tray.tempURL for in-flight tray items,
        /// the ScreenshotStorage path for saved captures. Drives the
        /// preview / annotate / quick-copy actions for both sources.
        let fileURL: URL?
    }

    private var recentCaptures: [RecentCapture] {
        var out: [RecentCapture] = []

        // Screenshot tray items still in flight. Clips and selected text
        // stay available in TrayViewer, but Home's Captures list stays
        // screenshot-specific.
        for item in screenshotTray.items {
            out.append(RecentCapture(
                id: item.id,
                line: trayLine(for: item),
                meta: screenshotMeta(width: item.width, height: item.height),
                date: item.capturedAt,
                source: .tray,
                fileURL: item.tempURL
            ))
        }

        // Saved capture objects created from screenshots. Do not pull
        // screenshots attached to notes/memos or imports from synced
        // phone/watch content into the Home Captures rail.
        for obj in recordingsVM.recordings where obj.type == .capture && obj.deletedAt == nil && !obj.screenshots.isEmpty {
            for ss in obj.screenshots {
                let label = ss.windowTitle ?? ss.appName ?? obj.title ?? "Screenshot"
                let url = ScreenshotStorage.screenshotsDirectory
                    .appendingPathComponent(ss.filename)
                out.append(RecentCapture(
                    id: stableUUID(from: "rec-\(ss.filename)"),
                    line: label,
                    meta: screenshotMeta(width: ss.width, height: ss.height),
                    date: obj.createdAt,
                    source: .savedCapture,
                    fileURL: url
                ))
            }
        }

        return out.sorted { $0.date > $1.date }
    }

    private func openRecentCapture(_ item: RecentCapture) {
        switch item.source {
        case .tray:
            TrayViewer.shared.show()
        case .savedCapture:
            NavigationState.shared.navigate(to: .screenshots)
        }
    }

    /// Deterministic UUID derived from a string — used so the rec-screenshot
    /// rows keep stable identity across rerenders without colliding with
    /// TrayItem.id (which is itself a UUID).
    private func stableUUID(from string: String) -> UUID {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let uuidString = String(format: "00000000-0000-4000-8000-%012llX", hash & 0x0000_FFFF_FFFF_FFFF)
        return UUID(uuidString: uuidString) ?? UUID()
    }

    private func todayCount(_ items: [RecentCapture]) -> Int {
        let cal = Calendar.current
        return items.filter { cal.isDateInToday($0.date) }.count
    }

    // MARK: Right-click menus
    //
    // Each builder returns the actions for a Recent row's context menu.
    // Kept close to the data-binding call sites so the available actions
    // stay obvious next to where the row is constructed. Mirrors the
    // existing context menus in `HomeScreen.swift` (MemoActivityRow /
    // DictationActivityRow) so behavior is identical when the standard
    // theme home is showing the same items.

    private func memoMenuActions(for obj: TalkieObject) -> [RecentMenuItem] {
        [
            RecentMenuItem(label: "Open", systemImage: "arrow.up.right.square", role: nil) {
                NavigationState.shared.navigate(to: .recordings, params: ["recordingId": obj.id.uuidString])
            },
            RecentMenuItem(label: "Copy Text", systemImage: "doc.on.doc", role: nil) {
                Self.copyToPasteboard(obj.text)
            },
            RecentMenuItem(label: "Share…", systemImage: "square.and.arrow.up", role: nil) {
                Self.share(string: obj.text)
            },
            .divider,
            RecentMenuItem(label: "Delete", systemImage: "trash", role: .destructive) {
                Task { await RecordingsViewModel.shared.softDeleteRecording(obj) }
            },
        ]
    }

    private func dictationMenuActions(for obj: TalkieObject) -> [RecentMenuItem] {
        [
            RecentMenuItem(label: "Open", systemImage: "arrow.up.right.square", role: nil) {
                NavigationState.shared.navigate(to: .dictations, params: ["recordingId": obj.id.uuidString])
            },
            RecentMenuItem(label: "Copy Text", systemImage: "doc.on.doc", role: nil) {
                Self.copyToPasteboard(obj.text)
            },
            RecentMenuItem(label: "Promote to Memo", systemImage: "arrow.up.doc", role: nil) {
                Task {
                    _ = try? await TalkieObjectRepository().promoteToMemo(id: obj.id)
                    DictationStore.shared.refresh()
                }
            },
            RecentMenuItem(label: "Share…", systemImage: "square.and.arrow.up", role: nil) {
                Self.share(string: obj.text)
            },
            .divider,
            RecentMenuItem(label: "Delete", systemImage: "trash", role: .destructive) {
                Task { await RecordingsViewModel.shared.hardDeleteRecording(obj) }
            },
        ]
    }

    private func noteMenuActions(for obj: TalkieObject) -> [RecentMenuItem] {
        [
            RecentMenuItem(label: "Open", systemImage: "arrow.up.right.square", role: nil) {
                NavigationState.shared.navigate(to: .recordings, params: ["recordingId": obj.id.uuidString])
            },
            RecentMenuItem(label: "Copy Text", systemImage: "doc.on.doc", role: nil) {
                Self.copyToPasteboard(obj.text)
            },
            .divider,
            RecentMenuItem(label: "Delete", systemImage: "trash", role: .destructive) {
                Task { await RecordingsViewModel.shared.softDeleteRecording(obj) }
            },
        ]
    }

    private func captureMenuActions(for item: RecentCapture) -> [RecentMenuItem] {
        guard let url = item.fileURL else { return [] }
        return [
            RecentMenuItem(label: "Open in Screenshots", systemImage: "photo.on.rectangle", role: nil) {
                NavigationState.shared.navigate(to: .screenshots)
            },
            RecentMenuItem(label: "Preview", systemImage: "eye", role: nil) {
                NSWorkspace.shared.open(url)
            },
            RecentMenuItem(label: "Annotate", systemImage: "pencil.tip.crop.circle", role: nil) {
                CaptureMarkupCoordinator.shared.openAgentOwnedSession(imageURL: url)
            },
            RecentMenuItem(label: "Quick Copy", systemImage: "doc.on.doc", role: nil) {
                Self.copyImage(at: url)
            },
        ]
    }

    private static func copyToPasteboard(_ text: String?) {
        let value = text ?? ""
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static func share(string: String?) {
        let value = string ?? ""
        guard !value.isEmpty else { return }
        let picker = NSSharingServicePicker(items: [value])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private static func copyImage(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
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
    private func trayLine(for item: TrayScreenshot) -> String {
        if let appName = item.appName, !appName.isEmpty { return appName }
        if let windowTitle = item.windowTitle, !windowTitle.isEmpty { return windowTitle }
        if let displayName = item.displayName, !displayName.isEmpty { return displayName }
        switch item.mode {
        case .region: return "crop"
        case .fullscreen: return "fullscreen"
        case .window: return "macwindow"
        }
    }
    private func screenshotMeta(width: Int?, height: Int?) -> String {
        let widthLabel = width.map(String.init) ?? "?"
        let heightLabel = height.map(String.init) ?? "?"
        return "\(widthLabel)×\(heightLabel)"
    }
    private func screenshotMeta(width: Int, height: Int) -> String {
        screenshotMeta(width: Optional(width), height: Optional(height))
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
    // actionHelpers + featureAgentConsole). Now demoted to borderless
    // rule-separated rows on the canvas so Bay + Recent keep the only
    // card weight on the page.
    //
    // Console data remains stubbed until an active ConsoleRegistry lands.

    private var routinesStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Routines")
            HStack(alignment: .top, spacing: 0) {
                RoutinesPanel(
                    title: "Workflows",
                    trailing: workflowRunsTodayText,
                    rows: workflowRunRows,
                    footer: "MANAGE WORKFLOWS",
                    accent: ScopeBrass.solid,
                    onTitleTap: { NavigationState.shared.navigate(to: .workflows) }
                )
                ScopeRule(.subtle, axis: .vertical)
                    .padding(.vertical, 14)
                RoutinesPanel(
                    title: "Console",
                    trailing: "2 tabs",
                    rows: consoleRows,
                    footer: "OPEN CONSOLE",
                    accent: ScopeAmber.solid,
                    onTitleTap: { NavigationState.shared.navigate(to: .systemConsole) }
                )
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ScopeCanvas.pane)
                    LinearGradient(
                        colors: [
                            ScopeAmber.tintSubtle,
                            Color.clear,
                            Color.black.opacity(0.015)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            )
            .scopeCardBorder(cornerRadius: 6, emphasis: .muted)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ScopeAmber.solid.opacity(0.10))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
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
                trailing: workflowRunTimeText(run.runDate),
                onSelect: {
                    NavigationState.shared.navigate(
                        to: .workflows,
                        params: ["workflowId": run.workflowId.uuidString]
                    )
                }
            )
        }

        if rows.isEmpty {
            return [.init(
                leading: .hollow,
                label: "Ready",
                trailing: "",
                onSelect: { NavigationState.shared.navigate(to: .workflows) }
            )]
        }

        return rows
    }

    private var consoleRows: [RoutinesPanel.Row] {
        [
            .init(
                leading: .filled, label: "iTerm2", trailing: "ACTIVE",
                onSelect: { NavigationState.shared.navigate(to: .systemConsole) }
            ),
            .init(
                leading: .filled, label: "Codex",  trailing: "IDLE",
                onSelect: { NavigationState.shared.navigate(to: .systemConsole) }
            ),
            .init(
                leading: .hollow, label: "Claude", trailing: "OFF",
                onSelect: { NavigationState.shared.navigate(to: .systemConsole) }
            ),
        ]
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

    // Tips row — compact borderless instrument labels for common actions.
    //
    // Same outer shape as the Recent panes and Routines strip
    // (`scopeCardBorder` + cornerRadius 6) so the column reads as a
    // coherent stack of card-shaped sections. Interior stays flat — no
    // gradient, no top rule — to match the "knowledge bay" tone rather
    // than the active "instrument bay" treatment used above.
    private var discoveryRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Tips")
            HStack(alignment: .top, spacing: 0) {
                DidYouKnowCard(
                    glyph: .voiceEdit,
                    marker: "01",
                    hook: "Compose edits",
                    detail: "Voice instructions revise text and show inline diffs before you accept.",
                    action: "Learn",
                    onOpen: { NavigationState.shared.navigateToLearn(articleID: "compose-diffs") }
                )
                ScopeRule(.section, axis: .vertical)
                    .padding(.vertical, 14)
                DidYouKnowCard(
                    glyph: .smartActions,
                    marker: "02",
                    hook: "Hyper keys",
                    detail: "Talkie's chord layer opens capture, tray, paste, and recording tools.",
                    action: "Learn",
                    onOpen: { NavigationState.shared.navigateToLearn(articleID: "hyper-keys") }
                )
                ScopeRule(.section, axis: .vertical)
                    .padding(.vertical, 14)
                DidYouKnowCard(
                    glyph: .tray,
                    marker: "03",
                    hook: "Tray Shelf",
                    detail: "Screenshots and clips collect beside the current recording for reuse.",
                    action: "Learn",
                    onOpen: { NavigationState.shared.navigateToLearn(articleID: "tray-shelf") }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ScopeCanvas.pane)
            )
            .scopeCardBorder(cornerRadius: 6, emphasis: .muted)
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
            // Header rule — uses scheme.edge (tinted to the panel's
            // chassis color) at the canonical 1pt thickness.
            Rectangle()
                .fill(scheme.edge)
                .frame(height: 1)
                .padding(.horizontal, 16)
        }
    }

    private func panelBody(scheme: BayScheme) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statTile(scheme: scheme, seed: 0, value: ScopeType.statCount(todayMemos),    label: "MEMOS · TODAY")
                tileDivider(scheme: scheme)
                statTile(scheme: scheme, seed: 1, value: ScopeType.statCount(todayDictations), label: "DICTATIONS · TODAY")
                tileDivider(scheme: scheme)
                statTile(
                    scheme: scheme,
                    seed: 2,
                    value: ScopeType.statCount(streak),
                    label: "DAY STREAK",
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
        // Vertical tile divider — uses ScopeRule with the scheme's own
        // edge color overlaid for surfaces that need scheme tinting
        // (the bay's stripTopFill is darker than a cream panel, so we
        // keep using scheme.edge here instead of switching to the
        // generic cool-ink rule). The thickness is canonicalized via
        // the rule's standard 1pt.
        Rectangle()
            .fill(scheme.edge)
            .frame(width: 1)
            .padding(.vertical, 18)
    }

    private func statTile(scheme: BayScheme, seed: Int, value: String, label: String, extra: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ScopeType.display(size: bayCompact ? 26 : 34))
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
                        bayScheme = BayScheme.carbon.rawValue
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
                                ScopeRule(.row)
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
                    HomeHoverChrome(style: .scopeCaptureCard(cornerRadius: 6))
                }
            )
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(ScopeBrass.solid)
            Text("→")
                .font(.system(size: 11))
                .foregroundStyle(ScopeBrass.solid)
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
            .background(HomeHoverChrome(style: .scopeSignalRow()))
        }
        .buttonStyle(.plain)
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

// MARK: - Routines panel
//
// Borderless row block with header rail (title + trailing chrome), a
// short list of rows, and a footer link. Used for both Workflows and
// Console quick-entries in the Routines strip.

private struct RoutinesPanel: View {
    enum Dot { case filled, hollow }
    struct Row {
        let leading: Dot
        let label: String
        let trailing: String
        var onSelect: (() -> Void)? = nil
    }

    let title: String
    let trailing: String
    let rows: [Row]
    let footer: String
    let accent: Color
    var onTitleTap: (() -> Void)? = nil

    @State private var footerHovered = false
    @State private var hoveredRowIndex: Int? = nil
    @State private var titleHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onTitleTap?()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        PhosphorDot(color: accent.opacity(0.72), size: 4)
                        Text(title)
                            .font(ScopeType.display(size: 15, weight: .medium))
                            .foregroundStyle(titleHovered ? accent : ScopeInk.primary)
                    }
                    Spacer()
                    Text(trailing.uppercased())
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                }
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onTitleTap == nil)
            .onHover { titleHovered = $0 && onTitleTap != nil }
            .overlay(alignment: .bottom) {
                ScopeRule(.section)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    // Row + trailing rule wrapped in a VStack so the
                    // conditional view has a stable layout slot.
                    VStack(spacing: 0) {
                        Button {
                            row.onSelect?()
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(row.leading == .filled ? accent : Color.clear)
                                    .overlay(
                                        Circle().stroke(accent.opacity(0.88), lineWidth: row.leading == .hollow ? 1 : 0)
                                    )
                                    .shadow(color: row.leading == .filled ? accent.opacity(0.22) : .clear, radius: 2)
                                    .frame(width: 5, height: 5)
                                Text(row.label)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(hoveredRowIndex == idx ? accent : ScopeInk.primary)
                                Spacer()
                                Text(row.trailing.uppercased())
                                    .font(ScopeType.chrome)
                                    .tracking(ScopeType.Tracking.wide)
                                    .foregroundStyle(ScopeInk.subtle)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7.5)
                            .background(
                                hoveredRowIndex == idx
                                ? accent.opacity(0.05)
                                : Color.clear
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(row.onSelect == nil)
                        .onHover { hover in
                            if row.onSelect != nil {
                                hoveredRowIndex = hover ? idx : (hoveredRowIndex == idx ? nil : hoveredRowIndex)
                            }
                        }

                        if idx < rows.count - 1 {
                            ScopeRule(.row)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }

            ScopeRule(.section)
                .padding(.horizontal, 16)

            Button {
                if footer == "OPEN CONSOLE" {
                    NavigationState.shared.navigate(to: .systemConsole)
                } else {
                    NavigationState.shared.navigate(to: .workflows)
                }
            } label: {
                HStack(spacing: 4) {
                    Spacer()
                    Text(footer)
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                    Text("→")
                        .font(.system(size: 11))
                }
                .foregroundStyle(footerHovered ? ScopeAmber.solid : ScopeBrass.solid)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(footerHovered ? ScopeAmber.tintSubtle : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { footerHovered = $0 }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.16), value: footerHovered)
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
