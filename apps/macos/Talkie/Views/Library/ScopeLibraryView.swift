//
//  ScopeLibraryView.swift
//  Talkie macOS
//
//  Cream-phosphor Library — the user's primary list of voice content
//  (memos, dictations, notes, captures). Built around the metaphor of
//  a tape archive: amber "ON FILE" stat strip at the top, channel-
//  tagged signal rows beneath, date-bucketed section headers as
//  eyebrow groupings, and a paper inspector to the right.
//
//  Only mounted when SettingsManager.shared.isScopeTheme is true.
//  AppNavigation branches on theme and renders RecordingsScreen() for
//  every other theme. Accepts the same initial type filter so it can
//  serve as Library for memos / dictations / notes / unified.
//

import SwiftUI
import TalkieKit

// MARK: - Scope display fonts

/// Cormorant Garamond is the homepage's `--font-display-modern`.
/// Tries a few PostScript name variants because the font ships with
/// slight naming differences across builds; falls back to system serif.
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

    /// Show the recording overlay (start a new memo).
    @State private var showingRecordingView = false

    /// User-resizable width of the list column. Drags on the divider
    /// between list + inspector persist this value so the chosen
    /// proportion survives navigation and relaunch.
    @AppStorage("scopeLibrary.listColumnWidth")
    private var listColumnWidth: Double = 520


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
            if initialTypeFilter != .all {
                suppressFilterReload = true
                typeFilter = initialTypeFilter
                viewModel.filterState.select(initialTypeFilter.semanticFilter)
            }
            await viewModel.loadWithSemanticFilters()
        }
        .onChange(of: typeFilter) { _, newValue in
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
    @ViewBuilder
    private var topComponent: some View {
        VStack(spacing: 8) {
            titleRow
            filterRow
            searchRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ScopeEdge.faint)
                .frame(height: 0.5)
        }
    }

    private var titleRow: some View {
        let counts = filterCounts()
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titleForCurrentFilter)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(ScopeInk.primary)
                .tracking(-0.2)

            Spacer(minLength: 8)

            Text(metaForCurrentFilter(counts: counts))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(ScopeInk.faint)
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
                                    Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
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
                PhosphorDot(color: ScopeAmber.solid.opacity(0.6), size: 5)
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
                    PhosphorDot(color: ScopeAmber.solid.opacity(0.45), size: 5)
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
                .foregroundStyle(ScopeAmber.solid)
                .phosphorGlow(radius: 3, opacity: 0.28)
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
            ScopeDivider().padding(.horizontal, 32)
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
        HStack(spacing: 10) {
            PhosphorDot(color: ScopeAmber.solid.opacity(0.5), size: 5)
            Text("· LOADING")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        switch typeFilter {
        case .all:        return "Hyper+M to record."
        case .memos:      return "Hyper+M to record."
        case .dictations: return "Hyper+D to dictate."
        case .notes:      return "Hyper+N to start a note."
        case .captures:   return "Hyper+S to capture."
        }
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
            Rectangle().fill(ScopeEdge.faint).frame(height: 1)
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
                TalkieView(recording: recording, onDelete: {
                    Task { await viewModel.deleteRecording(recording) }
                    selectedRecordingIDs.remove(recording.id)
                })
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
        case .memo: return ScopeAmber.solid
        case .dictation: return ScopeInk.muted
        case .note: return ScopeInk.dim
        case .capture: return ScopeInk.muted
        default: return ScopeInk.subtle
        }
    }

    private var rowTitle: String {
        if let title = recording.title, !title.isEmpty { return title }
        if let preview = recording.transcriptPreview { return preview }
        return "(untitled)"
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
    }

    private var timeAgo: String {
        RelativeTimeFormatter.format(recording.createdAt).uppercased()
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
