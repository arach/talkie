//
//  ScopeLibraryView.swift
//  Talkie macOS
//
//  Scope Library — the user's primary list of voice content
//  (memos, dictations, notes, captures). Cool-gray document surface
//  with channel-tagged rows, date-bucketed section headers, and an
//  editorial inspector column.
//
//  Only mounted when SettingsManager.shared.isScopeTheme is true.
//  AppNavigation branches on theme and renders RecordingsScreen() for
//  every other theme. Accepts the same initial type filter so it can
//  serve as Library for memos / dictations / notes / unified.
//

import SwiftUI
import TalkieKit
import AppKit

// MARK: - Scope display fonts

// (Removed local `ScopeFont` enum — unused, and Cormorant lookup is
// now centralized in `ScopeType.display(size:weight:)` (TalkieKit).
// Other Scope surfaces that still defined their own copies have been
// migrated to the same single source so resolution doesn't drift.)

// MARK: - ScopeLibraryView
//
// Date buckets, the channel-tagged row, the ⌘-badge chip, and the
// capture drag modifier all live in TalkieKit (ScopeLibraryList.swift)
// so companion surfaces (TalkieAgent's Library page) render the exact
// same presentation. This view keeps what's Talkie-only: semantic
// filters, search, pagination, ⌘-hold shortcuts, and the inspector.

struct ScopeLibraryView: View {
    @Environment(\.navigationState) private var navigationState
    private static let compactThreshold: CGFloat = 880

    /// Initial type filter — set by navigation to open with a specific tab.
    var initialTypeFilter: RecordingTypeFilter

    init(initialTypeFilter: RecordingTypeFilter = .all) {
        self.initialTypeFilter = initialTypeFilter
    }

    private var viewModel = RecordingsViewModel.shared
    private let liveState = ServiceManager.shared.live
    @State private var selectedRecordingIDs: Set<UUID> = []
    @State private var searchText: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var typeFilter: RecordingTypeFilter = .all
    @State private var suppressFilterReload = false
    @State private var pendingScrollID: UUID?
    @FocusState private var searchFieldFocused: Bool
    @State private var isCompactLayout = false
    @State private var showingCompactInspector = false

    /// Show the recording overlay (start a new memo).
    @State private var showingRecordingView = false

    /// User-resizable width of the list column. Drags on the divider
    /// between list + inspector persist this value so the chosen
    /// proportion survives navigation and relaunch.
    @AppStorage("scopeLibrary.listColumnWidth")
    private var listColumnWidth: Double = 520

    /// Last picked type filter. Survives relaunch so coming back to
    /// the library lands on whatever the user was last looking at.
    /// `initialTypeFilter` (set by deep-link navigation) overrides
    /// this on appearance, since the caller is asking for a specific tab.
    @AppStorage("scopeLibrary.lastTypeFilter")
    private var persistedTypeFilterRaw: String = RecordingTypeFilter.all.rawValue

    // MARK: Cmd-hold shortcut overlay
    //
    // Holding ⌘ while the library is on screen fades in glyph badges on
    // the filter chips (⌘M / ⌘D / ⌘C / ⌘N) and on the first nine list
    // rows (⌘1-⌘9). The bindings themselves are always live — ⌘ is
    // purely the revealer. Releasing ⌘ hides the badges.

    /// True while the ⌘ key is held. Driven by a local NSEvent monitor
    /// installed on view appear.
    @State private var cmdHeld: Bool = false

    /// The NSEvent monitor token, retained so it can be torn down when
    /// the library is no longer on screen.
    @State private var cmdEventMonitor: Any?

    private var selectedRecording: TalkieObject? {
        guard selectedRecordingIDs.count == 1, let id = selectedRecordingIDs.first else { return nil }
        return viewModel.recordings.first { $0.id == id }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let compact = geo.size.width < Self.compactThreshold

                ZStack {
                    if compact {
                        listColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LibrarySplitLayout(
                            committedListWidth: $listColumnWidth,
                            availableWidth: geo.size.width,
                            minListWidth: 460,
                            inspectorMinWidth: 280,
                            list: { listColumn },
                            inspector: { inspectorColumn }
                        )
                    }

                    if compact, showingCompactInspector {
                        CompactInspectorSlideSheet(
                            availableSize: geo.size,
                            onDismiss: { closeCompactInspector() },
                            content: { inspectorColumn }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: geo.size.width < 620 ? .bottom : .trailing)
                                    .combined(with: .opacity),
                                removal: .move(edge: geo.size.width < 620 ? .bottom : .trailing)
                                    .combined(with: .opacity)
                            )
                        )
                        .zIndex(5)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: showingCompactInspector)
                .onAppear { updateCompactLayout(compact) }
                .onChange(of: compact) { _, newValue in
                    updateCompactLayout(newValue)
                }
            }

            if showingRecordingView {
                RecordingOverlay(
                    controller: MemoRecordingController.shared,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingRecordingView = false
                        }
                        Task { await viewModel.loadRecordings() }
                    },
                    onMemoCreated: { memoId in
                        await viewModel.refresh()
                        selectRecording(memoId)
                    },
                    onNewRecording: { /* stay in overlay */ }
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
        .animation(.easeInOut(duration: 0.2), value: showingRecordingView)
        .task {
            // Pick the initial filter:
            //   1. Explicit deep-link (`initialTypeFilter != .all`) wins
            //   2. Otherwise restore the user's last picked filter
            //   3. Otherwise `.all`
            let restored = RecordingTypeFilter(rawValue: persistedTypeFilterRaw) ?? .all
            let desired = initialTypeFilter != .all ? initialTypeFilter : restored
            if desired != .all {
                suppressFilterReload = true
                typeFilter = desired
                viewModel.filterState.select(desired.semanticFilter)
            }
            await viewModel.loadWithSemanticFilters()
            // Consume pending navigation params — when the home (or
            // anywhere else) navigates to .recordings with a target
            // item identifier, we select that recording so the
            // inspector opens straight to the detail surface instead
            // of dropping the user on the unfiltered list.
            consumePendingNavigationParams()
        }
        .onChange(of: navigationState.params) { _, _ in
            // A subsequent tap from elsewhere (e.g. the home Captures
            // section while we're already on the Library) needs to
            // re-select. `.task` only fires on first appearance.
            consumePendingNavigationParams()
        }
        .onChange(of: typeFilter) { _, newValue in
            persistedTypeFilterRaw = newValue.rawValue
            if suppressFilterReload {
                suppressFilterReload = false
                return
            }
            Task { await viewModel.toggleSemanticFilter(newValue.semanticFilter) }
        }
        .onChange(of: viewModel.recordings.map(\.id)) { _, _ in
            reconcileSelectionWithVisibleRecordings()
        }
        .onChange(of: selectedRecordingIDs) { _, newValue in
            if newValue.isEmpty || newValue.count > 1 {
                closeCompactInspector()
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled {
                    viewModel.filterState.searchQuery = newValue
                    await viewModel.loadWithSemanticFilters()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ShowRecordingView"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showingRecordingView = true }
        }
        .background(cmdShortcutBindings)
        .onAppear { startCmdMonitor() }
        .onDisappear { stopCmdMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            resetCmdHeld()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            resetCmdHeld()
        }
    }

    // MARK: - Cmd-hold shortcuts

    /// Hidden ⌘+key buttons. The bindings are always live while the
    /// library is on screen; the `cmdHeld` overlay just makes them
    /// discoverable. Mirrors the pattern used by `deleteHotkey`.
    @ViewBuilder
    private var cmdShortcutBindings: some View {
        Group {
            Button("") { typeFilter = .memos }
                .keyboardShortcut("m", modifiers: [.command])
            Button("") { typeFilter = .dictations }
                .keyboardShortcut("d", modifiers: [.command])
            Button("") { typeFilter = .captures }
                .keyboardShortcut("c", modifiers: [.command])
            // ⌘N is now File > New Window globally; the Notes filter
            // loses its cmd-hold shortcut (it's still reachable via
            // the chip itself or the bare-letter N nav binding).
            ForEach(1...9, id: \.self) { n in
                Button("") { openItemAtPosition(n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [.command])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    /// Map of recording id → 1-based position for the first nine items
    /// in the currently-displayed list. Used both for badge rendering
    /// (`shortcutBadge` on rows) and to resolve ⌘N → recording.
    private var firstNineShortcuts: [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (idx, recording) in viewModel.recordings.prefix(9).enumerated() {
            map[recording.id] = idx + 1
        }
        return map
    }

    /// ⌘N action — selects the Nth visible item so the inspector opens
    /// straight to it.
    private func openItemAtPosition(_ n: Int) {
        let items = Array(viewModel.recordings.prefix(9))
        guard items.indices.contains(n - 1) else { return }
        let recording = items[n - 1]
        selectRecording(recording.id)
        pendingScrollID = recording.id
    }

    private func updateCompactLayout(_ compact: Bool) {
        isCompactLayout = compact
        if !compact {
            closeCompactInspector()
        }
    }

    private func selectRecording(_ id: UUID, revealInspector: Bool = true) {
        selectedRecordingIDs = [id]
        guard revealInspector, isCompactLayout else { return }
        showingCompactInspector = true
    }

    private func clearSelection() {
        selectedRecordingIDs.removeAll()
        closeCompactInspector()
    }

    private func closeCompactInspector() {
        guard showingCompactInspector else { return }
        showingCompactInspector = false
    }

    private func startCmdMonitor() {
        stopCmdMonitor()
        cmdHeld = NSEvent.modifierFlags.contains(.command)
        // `addLocalMonitorForEvents` fires for events delivered to our
        // own app, so we don't track ⌘ presses while the user is in
        // another window. Lightweight enough to leave installed.
        cmdEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let isHeld = event.modifierFlags.contains(.command)
            if isHeld != cmdHeld {
                withAnimation(.easeOut(duration: 0.12)) {
                    cmdHeld = isHeld
                }
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

    // MARK: - List column

    private var listColumn: some View {
        VStack(spacing: 0) {
            topComponent
            if viewModel.isLoading && viewModel.recordings.isEmpty {
                loadingState
            } else if viewModel.recordings.isEmpty {
                emptyState
            } else {
                recordingsList
            }
            footerBar
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(deleteHotkey)
    }

    /// Invisible button bound to ⌘⌫. macOS expects Cmd+Backspace to
    /// delete the selected list item; everywhere else we lean on the
    /// rail/menu Delete, but for keyboard-driven users this is the
    /// missing affordance. Soft delete + undo toast is wired by
    /// RecordingsViewModel.deleteRecording.
    private var deleteHotkey: some View {
        Button {
            for id in selectedRecordingIDs {
                if let record = viewModel.recordings.first(where: { $0.id == id }) {
                    Task { await viewModel.deleteRecording(record) }
                }
            }
            clearSelection()
        } label: {
            EmptyView()
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(selectedRecordingIDs.isEmpty)
        .hidden()
    }

    private var newRecordingButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingRecordingView = true
            }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ScopeAmber.solid)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ScopeAmber.tintSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeAmber.solid.opacity(0.30), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("New recording")
    }

    // MARK: - Filter ribbon
    //
    // The library's primary selector + at-a-glance count. Each pill
    // pairs the type label with its current count, so the user gets
    // both the filter affordance and the metric in one component —
    // no separate stat strip needed.

    private struct FilterCounts {
        let all: Int
        let memos: Int
        let dictations: Int
        let captures: Int
        let notes: Int

        func count(for option: RecordingTypeFilter) -> Int {
            switch option {
            case .all:        return all
            case .memos:      return memos
            case .dictations: return dictations
            case .captures:   return captures
            case .notes:      return notes
            }
        }
    }

    /// Read the navigation `params` and apply any target-item selection
    /// so the inspector opens to a specific recording instead of leaving
    /// the user on the bare list. Accepts both `recordingId` (the home
    /// convention) and `selectedID` (the legacy RecordingsScreen
    /// convention) so existing call sites keep working.
    private func consumePendingNavigationParams() {
        var consumedKeys: [String] = []
        let params = navigationState.params

        var resolved: UUID? = nil
        if let uuid = params["recordingId"] as? UUID {
            resolved = uuid
            consumedKeys.append("recordingId")
        } else if let uuidString = params["recordingId"] as? String,
                  let uuid = UUID(uuidString: uuidString) {
            resolved = uuid
            consumedKeys.append("recordingId")
        } else if let uuid = params["selectedID"] as? UUID {
            resolved = uuid
            consumedKeys.append("selectedID")
        }

        if let id = resolved {
            selectRecording(id)
        }

        for key in consumedKeys {
            navigationState.params.removeValue(forKey: key)
        }
    }

    /// Keep the inspector attached to a visible row after async GRDB
    /// observation updates land. Filter/search changes install the
    /// observation first; the actual row list arrives later.
    private func reconcileSelectionWithVisibleRecordings() {
        guard !selectedRecordingIDs.isEmpty else { return }

        let visibleIds = Set(viewModel.recordings.map(\.id))
        let stillVisible = selectedRecordingIDs.intersection(visibleIds)

        if stillVisible.isEmpty, let first = viewModel.recordings.first {
            selectRecording(first.id, revealInspector: false)
        } else if stillVisible.count != selectedRecordingIDs.count {
            selectedRecordingIDs = stillVisible
        }
    }

    private func filterCounts() -> FilterCounts {
        var memos = 0, dictations = 0, notes = 0, captures = 0
        for r in viewModel.recordings {
            switch r.type {
            case .memo:      memos += 1
            case .dictation: dictations += 1
            case .note:      notes += 1
            case .capture:   captures += 1
            default: break
            }
        }
        return FilterCounts(
            all: memos + dictations + notes + captures,
            memos: memos,
            dictations: dictations,
            captures: captures,
            notes: notes
        )
    }

    /// Library list header — the universal `ScopeTopBand` (serif title
    /// baseline-locked to the sidebar wordmark, mono count chrome, and a
    /// trailing controls slot holding the search field + new-recording
    /// mic) with the full-width filter-pill row docked beneath it.
    ///
    /// This replaces the old bespoke masthead so the Dictations / Library
    /// screen matches every other Scope surface (Models, Screenshots).
    /// The filter pills stay as their own full-width row because they
    /// carry the ⌘-hold glyph badges and an underline-selected treatment
    /// that doesn't compress into the inline trailing slot — same call
    /// ScreenshotsScreen makes for controls that don't fit inline.
    @ViewBuilder
    private var topComponent: some View {
        VStack(spacing: 8) {
            ScopeTopBand(
                title: titleForCurrentFilter,
                chrome: headerChromeLine,
                trailing: { headerControls }
            )
            filterRow
                .padding(.horizontal, 32)
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            ScopeRule(.section)
        }
    }

    /// Count + recency line shown as mono caps in the band's chrome slot
    /// (e.g. "33 MEMOS · 7D"). Mirrors the old `metaForCurrentFilter`
    /// but names the active type so the band reads on its own.
    private var headerChromeLine: String {
        let counts = filterCounts()
        let n = counts.count(for: typeFilter)
        let noun = typeFilter == .all ? "ITEMS" : titleForCurrentFilter.uppercased()
        return "\(n) \(noun) · 7D"
    }

    /// Band trailing slot — the search field and the new-recording mic,
    /// the two controls that read fine inline next to the title.
    private var headerControls: some View {
        HStack(spacing: 8) {
            searchField
                .frame(maxWidth: 200)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(ScopeEdge.faint, lineWidth: 0.5)
                )
            newRecordingButton
        }
    }

    /// "Library" when no specific filter is active; otherwise the
    /// filter's name (Memos / Dictations / Notes / Captures).
    private var titleForCurrentFilter: String {
        switch typeFilter {
        case .all:        return "Library"
        case .memos:      return "Memos"
        case .dictations: return "Dictations"
        case .notes:      return "Notes"
        case .captures:   return "Captures"
        }
    }

    private var filterRow: some View {
        let counts = filterCounts()
        return HStack(spacing: 0) {
            ForEach(RecordingTypeFilter.allCases, id: \.self) { option in
                filterPill(option, count: counts.count(for: option))
            }
            Spacer(minLength: 8)
        }
    }

    private func filterPill(_ option: RecordingTypeFilter, count: Int) -> some View {
        let isSelected = typeFilter == option
        return Button {
            typeFilter = option
        } label: {
            HStack(spacing: 5) {
                Text(option.label.uppercased())
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.8)
                    // Keep the label on one line at its intrinsic width — the
                    // HStack otherwise compresses the longest pill
                    // ("DICTATIONS") until its trailing letter wraps.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(
                        isSelected
                            ? ScopeInk.primary
                            : ScopeInk.faint
                    )
                Text("\(count)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(
                        isSelected
                            ? ScopeAmber.solid.opacity(0.75)
                            : ScopeInk.subtle
                    )
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? ScopeAmber.solid : Color.clear)
                    .frame(height: 1)
            }
            .overlay(alignment: .topTrailing) {
                // ⌘-hold badge. `All` deliberately has no shortcut (⌘A
                // is the standard Select All binding); everywhere else
                // the chip gets a ⌘+letter glyph that fades in while
                // the user holds the command key.
                if cmdHeld, let letter = option.cmdShortcutLetter {
                    CmdGlyphBadge(letter: letter)
                        .offset(x: 8, y: -6)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The text-field + magnifier + clear-button — shared by every
    /// variant so search styling stays consistent regardless of which
    /// filter treatment is in use.
    private var searchField: some View {
        HStack(spacing: 8) {
            // Mono-cased glyph instead of SF Symbol magnifier — reads as
            // editorial chrome, matches studio LibraryListGutter search.
            Text("⌕")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(ScopeInk.faint)
            TextField("Search the library…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(ScopeInk.dim)
                .focused($searchFieldFocused)
                .onReceive(NotificationCenter.default.publisher(for: .focusLibrarySearch)) { _ in
                    searchFieldFocused = true
                }
                .onKeyPress(.escape) {
                    if !searchText.isEmpty {
                        searchText = ""
                        return .handled
                    }
                    return .ignored
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Text("×")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(ScopeInk.subtle)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Filter ribbon — Patch Bay (brass LED dots, no container)

    // MARK: - Recordings list

    private var recordingsList: some View {
        // Bucket the recordings so we can render section headers as eyebrows.
        let groups = ScopeLibraryDateBucket.grouped(viewModel.recordings)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(groups, id: \.bucket) { group in
                        ScopeLibraryBucketHeader(bucket: group.bucket, count: group.items.count)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, recording in
                            ScopeLibraryRow(
                                recording: recording,
                                isSelected: selectedRecordingIDs.contains(recording.id),
                                shortcutNumber: cmdHeld ? firstNineShortcuts[recording.id] : nil,
                                onSelect: { selectRecording(recording.id) }
                            )
                            .id(recording.id)
                            .overlay(alignment: .top) {
                                if idx > 0 {
                                    ScopeRule(.row)
                                }
                            }
                        }
                    }

                    paginationFooter
                }
            }
            .onChange(of: pendingScrollID) { _, id in
                guard let id else { return }
                pendingScrollID = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if viewModel.isLoading && !viewModel.recordings.isEmpty {
            HStack(spacing: 8) {
                PhosphorDot(color: ScopeInk.faint, size: 5)
                Text("LOADING MORE")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
        } else if viewModel.hasMorePages {
            Button {
                Task { await viewModel.loadNextPage() }
            } label: {
                HStack(spacing: 8) {
                    PhosphorDot(color: ScopeInk.faint, size: 5)
                    Text("LOAD MORE")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                    Text("\(viewModel.displayedCount) / \(viewModel.totalCount)")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint.opacity(0.7))
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        // Skeleton rows that mirror the real list layout (channel
        // letter, title slug, meta block). Reads as "library is
        // arriving" rather than the blank slate it used to be.
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                ScopeLibraryRowSkeleton()
                ThemedScopeRule(.row)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading library")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(ScopeEdge.normal, lineWidth: 0.5)
                    .frame(width: 48, height: 48)
                PhosphorDot(color: ScopeAmber.solid.opacity(0.7), size: 8)
            }
            Text("· NO RECORDINGS")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            Text(emptyStateSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.subtle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateSubtitle: String {
        if !searchText.isEmpty { return "No matches for \"\(searchText)\"." }
        return "No items in this view."
    }


    // MARK: - Footer bar

    private var footerBar: some View {
        HStack(spacing: 12) {
            Text("· \(viewModel.displayedCount) / \(viewModel.totalCount) SHOWN")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
            Spacer()
            if selectedRecordingIDs.count > 0 {
                Text("· \(selectedRecordingIDs.count) SELECTED")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            ScopeRule(.section)
        }
    }

    // MARK: - Inspector column

    private var inspectorColumn: some View {
        // The readout "bay" (dashboard-style stats card with phosphor
        // chrome) has been removed — it competed with the editorial
        // document framing the studio mock established and the user
        // (rightly) called it "the stupid and ugly bay". The detail
        // pane now goes straight to the document: TalkieView when a
        // recording is selected, a quiet editorial empty state when
        // nothing's selected.
        Group {
            if selectedRecordingIDs.count > 1 {
                MultiSelectInspector(
                    count: selectedRecordingIDs.count,
                    itemName: "recordings",
                    onClearSelection: { clearSelection() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let recording = selectedRecording {
                // Branch detail chrome on item kind so notes/captures
                // don't inherit the memo's audio readout + player rail
                // (the "bootleg composed view" the studio brief flagged).
                Group {
                    switch recording.type {
                    case .note:
                        ScopeNoteDetailView(
                            note: recording,
                            onDelete: {
                                selectedRecordingIDs.remove(recording.id)
                                closeCompactInspector()
                            }
                        )
                    case .capture, .selection:
                        // Selections are text-content captures (Quick
                        // Selection grabs a passage). Same chrome as a
                        // screenshot capture; the hero branches on
                        // content.
                        ScopeCaptureDetailView(
                            capture: recording,
                            onDelete: {
                                selectedRecordingIDs.remove(recording.id)
                                closeCompactInspector()
                            }
                        )
                    default:
                        TalkieView(recording: recording, onDelete: {
                            Task { await viewModel.deleteRecording(recording) }
                            selectedRecordingIDs.remove(recording.id)
                            closeCompactInspector()
                        })
                    }
                }
                .id(recording.id)
            } else {
                ScopeLibraryEmptyState(
                    recordings: viewModel.recordings,
                    filter: typeFilter,
                    onSelectRecording: { id in selectRecording(id) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Compact inspector sheet

private struct CompactInspectorSlideSheet<Content: View>: View {
    let availableSize: CGSize
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    private var usesBottomSheet: Bool {
        availableSize.width < 620
    }

    private var panelWidth: CGFloat {
        let maxAvailable = max(360, availableSize.width - 36)
        return min(760, min(maxAvailable, max(560, availableSize.width * 0.82)))
    }

    private var panelHeight: CGFloat {
        let maxAvailable = max(360, availableSize.height - 28)
        return min(maxAvailable, max(420, availableSize.height * 0.84))
    }

    var body: some View {
        ZStack {
            Button(action: onDismiss) {
                Color.black.opacity(0.12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close details")

            if usesBottomSheet {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    panel
                        .frame(height: panelHeight)
                }
            } else {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    panel
                        .frame(width: panelWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onDismiss)
    }

    private var panel: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ThemedScopeCanvas.canvas)
            .clipShape(RoundedRectangle(cornerRadius: usesBottomSheet ? 8 : 0))
            .overlay(edgeRule, alignment: usesBottomSheet ? .top : .leading)
            .overlay(closeButton, alignment: .topTrailing)
            .shadow(
                color: Color.black.opacity(usesBottomSheet ? 0.18 : 0.16),
                radius: usesBottomSheet ? 20 : 28,
                x: usesBottomSheet ? 0 : -10,
                y: usesBottomSheet ? -8 : 0
            )
    }

    @ViewBuilder
    private var edgeRule: some View {
        if usesBottomSheet {
            Rectangle()
                .fill(ThemedScopeEdge.normal)
                .frame(height: 1)
        } else {
            Rectangle()
                .fill(ThemedScopeEdge.normal)
                .frame(width: 1)
        }
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ThemedScopeInk.subtle)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ThemedScopeCanvas.surface.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Close details")
        .padding(12)
    }
}

// MARK: - Resizable split layout
//
// During an active drag the list keeps its committed width — the list,
// LazyVStack rows, and inspector never relayout per drag tick. A ghost
// indicator line floats at the drag position to preview where the
// boundary will land; on release the committed width snaps to the
// preview and the list redraws exactly once.
//
// Drag state lives in this dedicated subview so the parent
// `ScopeLibraryView.body` (and its captures) doesn't re-evaluate on
// every drag tick either — same isolation as the sidebar resize work.

private struct LibrarySplitLayout<List: View, Inspector: View>: View {
    @Binding var committedListWidth: Double
    let availableWidth: CGFloat
    let minListWidth: CGFloat
    let inspectorMinWidth: CGFloat
    @ViewBuilder let list: () -> List
    @ViewBuilder let inspector: () -> Inspector

    /// Cursor x-position during an active drag (measured from leading
    /// edge of the split). `nil` when not dragging. The ghost indicator
    /// reads this; the list/inspector frames intentionally do not.
    @State private var dragX: CGFloat?
    @State private var isHovering = false

    private var committedWidth: CGFloat {
        let maxList = max(minListWidth, availableWidth - inspectorMinWidth)
        return min(maxList, max(minListWidth, CGFloat(committedListWidth)))
    }

    private var clampedDragX: CGFloat? {
        guard let dragX else { return nil }
        let maxList = max(minListWidth, availableWidth - inspectorMinWidth)
        return min(maxList, max(minListWidth, dragX))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                list()
                    .frame(width: committedWidth)
                divider
                inspector()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let ghostX = clampedDragX {
                Rectangle()
                    .fill(ScopeAmber.solid.opacity(0.55))
                    .frame(width: 2)
                    .offset(x: ghostX - 1)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var divider: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(isHovering || dragX != nil ? ScopeEdge.normal : ScopeEdge.faint)
                .frame(width: 1)
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .frame(width: 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragX = committedWidth + value.translation.width
                }
                .onEnded { _ in
                    if let final = clampedDragX {
                        committedListWidth = Double(final)
                    }
                    dragX = nil
                }
        )
    }
}

// MARK: - Number helpers

private extension Int {
    /// "12345" → "12,345" using the user's locale. Used by Broadcast
    /// presentations where big word counts read better with a separator.
    var formattedWithSeparator: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Loading skeleton
//
// Single row mock that matches the real row layout so the
// transition from skeleton → real list is a fade rather than a
// reshuffle. Pulses subtly to read as "live".

private struct ScopeLibraryRowSkeleton: View {
    @State private var phase: Double = 0.0

    var body: some View {
        HStack(spacing: 14) {
            // Channel column (one letter wide)
            RoundedRectangle(cornerRadius: 2)
                .fill(ScopeEdge.subtle)
                .frame(width: 14, height: 12)

            // Title + meta column
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(ScopeEdge.subtle)
                    .frame(width: titleWidth, height: 11)
                RoundedRectangle(cornerRadius: 2)
                    .fill(ScopeEdge.faint)
                    .frame(width: 110, height: 8)
            }

            Spacer(minLength: 12)

            // Right-side detail block (sparkline-or-meta width)
            RoundedRectangle(cornerRadius: 2)
                .fill(ScopeEdge.faint)
                .frame(width: 48, height: 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(0.6 + 0.25 * abs(sin(phase)))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
    }

    /// Vary the title width subtly across rows so the skeleton block
    /// doesn't read as eight identical bars.
    private var titleWidth: CGFloat {
        let widths: [CGFloat] = [180, 220, 150, 240, 200, 130, 210, 170]
        return widths.randomElement() ?? 200
    }
}

// MARK: - RecordingTypeFilter cmd binding

private extension RecordingTypeFilter {
    /// Letter shown inside the ⌘-hold badge for this filter. `All` is
    /// intentionally nil — ⌘A is the standard Select All binding and
    /// we don't override it.
    var cmdShortcutLetter: String? {
        switch self {
        case .all: return nil
        case .memos: return "M"
        case .dictations: return "D"
        case .captures: return "C"
        // ⌘N is reserved for File > New Window globally.
        case .notes: return nil
        }
    }
}
