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

// MARK: - Scope display fonts

// (Removed local `ScopeFont` enum — unused, and Cormorant lookup is
// now centralized in `ScopeType.display(size:weight:)` (TalkieKit).
// Other Scope surfaces that still defined their own copies have been
// migrated to the same single source so resolution doesn't drift.)

// MARK: - Date bucket

/// Section-header buckets for the library list. Items are grouped
/// into these buckets in date-descending order; oldest items fall
/// into a month bucket so the list stays tractable for big archives.
private enum DateBucket: Hashable {
    case today
    case yesterday
    case thisWeek
    case month(year: Int, month: Int)

    var label: String {
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

    static func bucket(for date: Date, now: Date = Date()) -> DateBucket {
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
}

// MARK: - ScopeLibraryView

struct ScopeLibraryView: View {
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


    private var selectedRecording: TalkieObject? {
        guard selectedRecordingIDs.count == 1, let id = selectedRecordingIDs.first else { return nil }
        return viewModel.recordings.first { $0.id == id }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let compact = geo.size.width < 880

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
                        selectedRecordingIDs = [memoId]
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
        .onChange(of: NavigationState.shared.params) { _, _ in
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
        let params = NavigationState.shared.params

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
            selectedRecordingIDs = [id]
        }

        for key in consumedKeys {
            NavigationState.shared.params.removeValue(forKey: key)
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

    /// Library list header — title row + filter pills + search row.
    /// Sits below the chrome-bar zone: a small offset keeps the title
    /// clear of the centered Talkie pill without burning a full band
    /// of whitespace below the toolbar.
    @ViewBuilder
    private var topComponent: some View {
        VStack(spacing: 8) {
            titleRow
            filterRow
            searchRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            ScopeRule(.section)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titleForCurrentFilter)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(ScopeInk.primary)
                .tracking(-0.2)

            Spacer(minLength: 8)
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

    /// "{n} · 7D" — total count for the active filter, with the studio's
    /// "7d" recency hint. Mono caps, faint.
    private func metaForCurrentFilter(counts: FilterCounts) -> String {
        "\(counts.count(for: typeFilter)) · 7D"
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
                    .foregroundColor(
                        isSelected
                            ? ScopeInk.primary
                            : ScopeInk.faint
                    )
                Text("\(count)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(
                        isSelected
                            ? ScopeAmber.solid.opacity(0.75)
                            : ScopeInk.subtle
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? ScopeAmber.solid : Color.clear)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            searchField
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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
        let groups = bucketed(viewModel.recordings)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(groups, id: \.bucket) { group in
                        bucketHeader(group.bucket, count: group.items.count)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, recording in
                            ScopeLibraryRow(
                                recording: recording,
                                isSelected: selectedRecordingIDs.contains(recording.id),
                                onSelect: { selectedRecordingIDs = [recording.id] }
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

    private func bucketHeader(_ bucket: DateBucket, count: Int) -> some View {
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

    private struct BucketGroup {
        let bucket: DateBucket
        let items: [TalkieObject]
    }

    private func bucketed(_ items: [TalkieObject]) -> [BucketGroup] {
        let now = Date()
        // Preserve original ordering — RecordingsViewModel already sorts desc.
        var order: [DateBucket] = []
        var map: [DateBucket: [TalkieObject]] = [:]
        for r in items {
            let b = DateBucket.bucket(for: r.createdAt, now: now)
            if map[b] == nil {
                order.append(b)
                map[b] = []
            }
            map[b]?.append(r)
        }
        return order.map { BucketGroup(bucket: $0, items: map[$0] ?? []) }
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
                    onClearSelection: { selectedRecordingIDs.removeAll() }
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
                            onDelete: { selectedRecordingIDs.remove(recording.id) }
                        )
                    case .capture, .selection:
                        // Selections are text-content captures (Quick
                        // Selection grabs a passage). Same chrome as a
                        // screenshot capture; the hero branches on
                        // content.
                        ScopeCaptureDetailView(
                            capture: recording,
                            onDelete: { selectedRecordingIDs.remove(recording.id) }
                        )
                    default:
                        TalkieView(recording: recording, onDelete: {
                            Task { await viewModel.deleteRecording(recording) }
                            selectedRecordingIDs.remove(recording.id)
                        })
                    }
                }
                .id(recording.id)
            } else {
                ScopeLibraryEmptyState(
                    recordings: viewModel.recordings,
                    onSelectRecording: { id in selectedRecordingIDs = [id] }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Row

/// Compact channel-tagged signal row. The heart of the library: leading
/// channel label (M / D / N / C), title in sans, chrome metadata line,
/// and a right-side detail block (sparkline for memos w/ duration, else
/// word count / time).
private struct ScopeLibraryRow: View {
    let recording: TalkieObject
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

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

    /// Chrome metadata — date · source · duration · word count.
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

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                // Channel tag
                ChannelLabel(
                    channelLetter,
                    color: isSelected ? ScopeAmber.solid : channelColor,
                    strokeColor: isSelected ? ScopeAmber.solid.opacity(0.5) : ScopeEdge.normal
                )
                .frame(width: 26, alignment: .leading)

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
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .modifier(CaptureRowDragModifier(fileURL: primaryScreenshotURL))
    }

    private var timeAgo: String {
        RelativeTimeFormatter.format(recording.createdAt).uppercased()
    }

    /// First screenshot file on disk, if any. Captures (and notes / memos
    /// with an image attached) drag as the file URL so the receiver sees
    /// a real image, not bitmap data. nil for audio-only rows.
    private var primaryScreenshotURL: URL? {
        guard let filename = recording.screenshots.first?.filename else { return nil }
        return ScreenshotStorage.screenshotsDirectory.appendingPathComponent(filename)
    }
}

/// Conditionally adds `.onDrag` to a row when a file URL is available.
/// Avoids starting a drag gesture on rows that have no payload (audio-
/// only memos, dictations) — those drag visually but drop nothing,
/// which feels broken.
struct CaptureRowDragModifier: ViewModifier {
    let fileURL: URL?

    func body(content: Content) -> some View {
        if let url = fileURL {
            content.onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        } else {
            content
        }
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
