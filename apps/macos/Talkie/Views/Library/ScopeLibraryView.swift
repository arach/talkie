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

    /// Active treatment for the readout body. The filter ribbon is
    /// locked to Patch Bay; the inspector empty state is locked to
    /// Library Readout. What flexes is the *content* inside the readout
    /// bay — different bodies render different "instruments" on the
    /// same chrome.
    @AppStorage("scopeLibrary.readoutBodyVariant")
    private var readoutBodyVariantRaw: String = LibraryReadoutBodyVariant.stats.rawValue
    private var readoutBodyVariant: LibraryReadoutBodyVariant {
        LibraryReadoutBodyVariant(rawValue: readoutBodyVariantRaw) ?? .stats
    }

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
            heroHeader
            topComponent
            if viewModel.isLoading && viewModel.recordings.isEmpty {
                loadingState
            } else if viewModel.recordings.isEmpty {
                emptyState
            } else {
                recordingsList
            }
            #if DEBUG
            variantSwitcherStrip
            #endif
            footerBar
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header strip
    //
    // Universal 44pt top band — title names the active filter, trailing
    // chrome states totals, record button anchors the right edge.
    // Baseline-aligned with the sidebar wordmark via `ScopeTopBand`.

    private var heroHeader: some View {
        ScopeTopBand(
            title: "Library",
            breadcrumb: filterBreadcrumb,
            chrome: "\(viewModel.totalCount) ON FILE"
        ) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingRecordingView = true
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ScopeAmber.solid)
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ScopeEdge.normal, lineWidth: 1)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ScopeAmber.tintSubtle)
                    )
            }
            .buttonStyle(.plain)
            .help("New recording")
        }
    }

    /// Secondary title shown after the "›" chevron embellishment when a
    /// specific filter is active. On `.all` we return nil so just the
    /// section name "Library" reads — no breadcrumb noise.
    private var filterBreadcrumb: String? {
        switch typeFilter {
        case .all:        return nil
        case .memos:      return "Memos"
        case .dictations: return "Dictations"
        case .notes:      return "Notes"
        case .captures:   return "Captures"
        }
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

    /// Filter ribbon — locked to Patch Bay. The other ribbon variants
    /// have been removed; their treatments are preserved only in git
    /// history. Patch Bay is the brass LED dot family above each label
    /// with an inline count and an amber underline on the active option.
    @ViewBuilder
    private var topComponent: some View {
        let counts = filterCounts()
        patchBayRibbon(counts: counts)
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .animation(.smooth(duration: 0.4), value: viewModel.recordings.count)
    }

    /// The text-field + magnifier + clear-button — shared by every
    /// variant so search styling stays consistent regardless of which
    /// filter treatment is in use.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ScopeInk.faint)
            TextField("Search the library…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.dim)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.subtle)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Filter ribbon — Patch Bay (brass LED dots, no container)

    private func patchBayRibbon(counts: FilterCounts) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(RecordingTypeFilter.allCases, id: \.self) { option in
                    patchBaySegment(option, count: counts.count(for: option))
                        .frame(maxWidth: .infinity)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ScopeEdge.faint)
                    .frame(height: 0.5)
            }

            searchField
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ScopeCanvas.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.faint, lineWidth: 0.5)
                )
        }
    }

    private func patchBaySegment(_ option: RecordingTypeFilter, count: Int) -> some View {
        let isSelected = typeFilter == option
        return Button {
            typeFilter = option
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? ScopeAmber.solid : Color.clear)
                    .frame(width: 4, height: 4)
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected ? Color.clear : ScopeAmber.solid.opacity(0.35),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: isSelected ? ScopeAmber.glow : .clear, radius: 3)
                HStack(spacing: 6) {
                    Text(option.label.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("\(count)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 14, alignment: .trailing)
                        .foregroundStyle(isSelected ? ScopeAmber.solid.opacity(0.75) : ScopeInk.subtle)
                }
                .foregroundStyle(isSelected ? ScopeAmber.solid : ScopeInk.faint)
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? ScopeAmber.solid : Color.clear)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

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
            Text("LOADING")
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
            Text("NO RECORDINGS YET")
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
        case .all: return "Start a recording."
        case .memos: return "Memos land here once you've recorded."
        case .dictations: return "Trigger dictation in any app — transcripts arrive here."
        case .notes: return "Typed thoughts and screenshots collect here."
        case .captures: return "Hyper+S to clip the screen alongside what you say."
        }
    }

    // MARK: - Debug variant switcher (Design God Mode only)

    #if DEBUG
    @ViewBuilder
    private var variantSwitcherStrip: some View {
        if DesignModeManager.shared.isEnabled {
            HStack(spacing: 6) {
                Text("· READOUT")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopePanel.inkFaint)
                    .frame(width: 64, alignment: .leading)
                ForEach(LibraryReadoutBodyVariant.allCases, id: \.self) { option in
                    let raw = option.rawValue
                    let isActive = readoutBodyVariantRaw == raw
                    Button {
                        readoutBodyVariantRaw = raw
                    } label: {
                        Text(option.displayName.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(isActive ? ScopePanel.bg : ScopePanel.inkMuted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isActive ? ScopeAmber.solid : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(
                                        isActive ? ScopeAmber.solid : ScopePanel.Edge.normal,
                                        lineWidth: 0.5
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 8)
            .background(ScopePanel.bg.opacity(0.92))
            .overlay(alignment: .top) {
                Rectangle().fill(ScopePanel.Edge.normal).frame(height: 1)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(ScopeAmber.solid.opacity(0.6))
                    .frame(width: 2)
            }
        }
    }
    #endif

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
    //
    // The readout panel sits as a permanent header above whatever the
    // rest of the column shows — selection detail, multi-select hint,
    // or an empty hint. The panel doesn't reflow or move when selection
    // changes; it's a stable shelf with the row detail rendered below.
    // The body *content* of the readout (stats grid vs. phase plot vs.
    // reference monitor vs. transit console) is dispatched on
    // `readoutBodyVariant` — same chrome, different instruments.

    private var inspectorColumn: some View {
        VStack(spacing: 0) {
            libraryReadoutPanel
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 18)
            Rectangle().fill(ScopeEdge.faint).frame(height: 0.5)

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
                    inspectorEmpty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Dispatches the readout body by the active variant and wraps it
    /// in the universal bay chrome (frame, top strip, bottom strip,
    /// drop shadow). The bay shape stays constant across variants; only
    /// the body content and the variant's `ReadoutSurface` palette change.
    private var libraryReadoutPanel: some View {
        let surface: ReadoutSurface = {
            switch readoutBodyVariant {
            case .stats:     return .stats
            case .phasePlot: return .phasePlot
            case .broadcast: return .broadcast
            }
        }()
        return readoutBay(surface: surface) {
            readoutBody(surface: surface)
        }
    }

    /// Universal bay wrapper: eyebrow above, framed bay below with top
    /// strip + body + bottom strip + drop shadow. Variant-agnostic.
    @ViewBuilder
    private func readoutBay<Body: View>(
        surface: ReadoutSurface,
        @ViewBuilder body: () -> Body
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(surface.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(surface.edgeFaint, lineWidth: 1)
                )

            VStack(spacing: 0) {
                readoutChromeStrip(
                    surface: surface,
                    leading: surface.topStripLeading,
                    trailing: surface.topStripTrailing,
                    fill: AnyView(surface.topStripFill),
                    isTop: true
                )
                body()
                    .frame(maxHeight: .infinity)
                readoutChromeStrip(
                    surface: surface,
                    leading: surface.bottomStripLeading,
                    trailing: Date().formatted(date: .omitted, time: .shortened).uppercased(),
                    fill: AnyView(surface.bottomStripFill),
                    isTop: false
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 200)
        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
    }

    /// Universal top/bottom chrome strip. Pulled out so variants share
    /// the same dot + leading + trailing rhythm.
    private func readoutChromeStrip(
        surface: ReadoutSurface,
        leading: String,
        trailing: String,
        fill: AnyView,
        isTop: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if isTop {
                PhosphorDot(color: surface.signal, size: 5)
            }
            Text(leading)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(surface.inkMuted)
            Spacer()
            Text(trailing)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(surface.inkSubtle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(fill)
        .overlay(alignment: isTop ? .bottom : .top) {
            Rectangle()
                .fill(surface.edgeFaint)
                .frame(height: 1)
                .padding(.horizontal, 14)
        }
    }

    /// Dispatch to the active body. Each body takes the surface palette
    /// and the currently selected recording (nil → idle state).
    @ViewBuilder
    private func readoutBody(surface: ReadoutSurface) -> some View {
        switch readoutBodyVariant {
        case .stats:
            readoutBodyStats(surface: surface)
        case .phasePlot:
            readoutBodyPhasePlot(surface: surface, recording: selectedRecording)
        case .broadcast:
            readoutBodyBroadcast(surface: surface, recording: selectedRecording)
        }
    }

    /// Daily activity counts for the last `days` days, oldest → newest.
    /// Used by readout body variants (Reference Monitor's sparkline,
    /// Phase Plot's idle telemetry) so the panel always has a
    /// continuous "library pulse" signal to derive renderings from.
    private func pulseSeries(days: Int) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var counts = Array(repeating: 0, count: days)
        for r in viewModel.recordings {
            let day = cal.startOfDay(for: r.createdAt)
            guard let diff = cal.dateComponents([.day], from: day, to: today).day else { continue }
            let idx = days - 1 - diff
            if idx >= 0 && idx < days { counts[idx] += 1 }
        }
        return counts
    }

    /// Single fallback rendered below the readout panel when there's
    /// no selection. The readout panel above always shows the variant
    /// body, so this is intentionally minimal.
    private var inspectorEmpty: some View {
        inspectorEmptySimple
    }

    private var inspectorEmptySimple: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(ScopeEdge.normal, lineWidth: 0.5)
                    .frame(width: 40, height: 40)
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 14))
                    .foregroundStyle(ScopeInk.subtle)
            }
            Text("NOTHING SELECTED")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            Text("Pick a row to see details.")
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.subtle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Body — Stats (the original 4-tile grid, retinted for surface)

    private func readoutBodyStats(surface: ReadoutSurface) -> some View {
        let stats = readoutStats()
        return ZStack {
            GraticuleBackground(pitch: 20, color: surface.signal.opacity(0.06), opacity: 0.5)
            HStack(spacing: 0) {
                statsTile(value: "\(stats.total)",      label: "RECORDINGS", surface: surface)
                statsDivider(surface: surface)
                statsTile(value: "\(stats.thisWeek)",    label: "THIS WEEK",  surface: surface)
                statsDivider(surface: surface)
                statsTile(value: stats.topChannel,       label: "TOP SOURCE", surface: surface)
                statsDivider(surface: surface)
                statsTile(value: stats.avgDuration,      label: "AVG LENGTH", surface: surface)
            }
            .padding(.horizontal, 14)
        }
    }

    private func statsDivider(surface: ReadoutSurface) -> some View {
        Rectangle()
            .fill(surface.edgeFaint)
            .frame(width: 1)
            .padding(.vertical, 18)
    }

    private func statsTile(value: String, label: String, surface: ReadoutSurface) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(ScopeFont.display(size: 28))
                .foregroundStyle(surface.signal)
                .tracking(-0.4)
                .shadow(color: surface.signalGlow, radius: 4)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(surface.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    // MARK: Body — Phase Plot (Lissajous at idle, amplitude band on select)

    /// Animated Lissajous curl. Idle: figure-eight breathing on a 14s
    /// cycle in aqua-mint phosphor. Selected: trace unwraps into a
    /// horizontal amplitude band and the recording title floats above.
    private func readoutBodyPhasePlot(surface: ReadoutSurface, recording: TalkieObject?) -> some View {
        let selected = recording != nil
        return ZStack {
            // Soft grid behind the trace — keeps the phosphor anchored.
            GraticuleBackground(pitch: 24, color: surface.signal.opacity(0.05), opacity: 0.5)

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { ctx in
                Canvas { context, size in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let w = size.width
                    let h = size.height
                    let cx = w / 2
                    let cy = h / 2

                    // Two phase-locked sines: figure-eight at idle. On
                    // selection, the Y-axis amplitude collapses so the
                    // curl "unwraps" into a horizontal band.
                    let unwrap: CGFloat = selected ? 0.85 : 0.0
                    let ampX: CGFloat = (w * 0.36)
                    let ampY: CGFloat = (h * 0.34) * (1.0 - unwrap)
                    let phase = t * 0.45  // slow drift
                    let steps = 240

                    var path = Path()
                    for i in 0...steps {
                        let u = Double(i) / Double(steps)
                        let angle = u * .pi * 2
                        // X-axis: linear sweep when "unwrapped"; pure sin at idle.
                        let xIdle = sin(angle * 3 + phase)
                        let xSel = (u * 2 - 1)
                        let x = cx + ampX * CGFloat(xIdle * (1 - Double(unwrap)) + xSel * Double(unwrap))
                        // Y-axis: cos(2θ) gives the figure-eight; collapses on select.
                        let y = cy + ampY * CGFloat(cos(angle * 2 + phase * 1.2))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    // Trailing afterglow — dimmer, slightly thicker.
                    context.stroke(
                        path,
                        with: .color(surface.signal.opacity(selected ? 0.18 : 0.35)),
                        lineWidth: selected ? 1.2 : 2.4
                    )
                    // Main trace.
                    context.stroke(
                        path,
                        with: .color(surface.signal.opacity(selected ? 0.55 : 0.9)),
                        lineWidth: 1.0
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            // Overlay: title + meta on selection; ambient whisper at idle.
            VStack(alignment: .leading, spacing: 6) {
                if let r = recording {
                    Text(phaseTitle(for: r))
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .foregroundStyle(surface.inkPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .shadow(color: surface.signalGlow.opacity(0.4), radius: 6)
                    Text(phaseMeta(for: r))
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(surface.inkMuted)
                } else {
                    Text(phaseIdleHint)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(surface.inkSubtle)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.easeInOut(duration: 0.6), value: selected)
    }

    private var phaseIdleHint: String {
        let count = viewModel.totalCount
        if count == 0 { return "IDLE" }
        return "\(count) ON FILE"
    }

    private func phaseTitle(for r: TalkieObject) -> String {
        if let t = r.title, !t.isEmpty { return t }
        if let p = r.transcriptPreview, !p.isEmpty { return p }
        return "Untitled"
    }

    private func phaseMeta(for r: TalkieObject) -> String {
        var parts: [String] = []
        if let app = r.appContext?.name, !app.isEmpty {
            parts.append(app.uppercased())
        } else {
            parts.append(r.source.displayName.uppercased())
        }
        if r.duration > 0 {
            parts.append(formatDuration(r.duration))
        }
        parts.append(r.type.rawValue.uppercased())
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Body — Broadcast (polymorphic canvas, per-type presentation)
    //
    // The merged design: Transit Console's source-coded accent bar +
    // Reference Monitor's clean SF Pro typography. Amber is reserved
    // for the chrome eyebrow dot — body text is neutral cream. The
    // distinguishing move: each record `type` declares its own
    // "core presentation" in the bottom slot of the canvas (memo →
    // waveform, dictation → word count + target, note → content
    // type, capture → context).

    private func readoutBodyBroadcast(surface: ReadoutSurface, recording: TalkieObject?) -> some View {
        let tint = recording.map { broadcastSourceTint(for: $0) }
        return VStack(spacing: 0) {
            // Source accent bar — top edge. Dim hairline at idle, lit
            // in the source color when something's selected.
            Rectangle()
                .fill(tint ?? surface.edgeFaint)
                .frame(height: 2)
                .animation(.easeInOut(duration: 0.32), value: tint?.description ?? "")

            if let r = recording {
                broadcastForRecording(r, surface: surface)
            } else {
                broadcastIdle(surface: surface)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: recording?.id)
    }

    // MARK: - Broadcast: idle state

    private func broadcastIdle(surface: ReadoutSurface) -> some View {
        let week = pulseSeries(days: 7).reduce(0, +)
        let total = viewModel.totalCount
        let lastAgo = lastRecordingTimeAgo()

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PhosphorDot(color: surface.signal, size: 5)
                Text("LIBRARY")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(surface.inkMuted)
                Spacer()
            }
            .padding(.bottom, 10)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(total)")
                    .font(.system(size: 40, weight: .light, design: .default))
                    .foregroundStyle(surface.inkPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .tracking(-0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("on file")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(surface.inkMuted)
                    if total > 0 {
                        Text(broadcastIdleSubtitle(week: week, lastAgo: lastAgo))
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundStyle(surface.inkSubtle)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func broadcastIdleSubtitle(week: Int, lastAgo: String?) -> String {
        var parts: [String] = []
        if week > 0 { parts.append("\(week) this week") }
        if let ago = lastAgo { parts.append("last \(ago)") }
        if parts.isEmpty { return "no recordings yet" }
        return parts.joined(separator: " · ")
    }

    private func lastRecordingTimeAgo() -> String? {
        guard let latest = viewModel.recordings.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
        return RelativeTimeFormatter.format(latest.createdAt).lowercased()
    }

    // MARK: - Broadcast: per-record presentation

    /// The selected-state canvas. Top: chrome row with type + context.
    /// Middle: title. Bottom: type-specific accent — the "core
    /// presentation" each record type declares for this surface.
    private func broadcastForRecording(_ r: TalkieObject, surface: ReadoutSurface) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            broadcastChromeRow(r, surface: surface)
                .padding(.bottom, 8)

            Text(broadcastTitle(for: r))
                .font(.system(size: 22, weight: .regular, design: .default))
                .foregroundStyle(surface.inkPrimary)
                .tracking(-0.2)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            broadcastTypeAccent(r, surface: surface)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Common chrome row at the top of any selected presentation —
    /// channel type · context · time-ago.
    private func broadcastChromeRow(_ r: TalkieObject, surface: ReadoutSurface) -> some View {
        HStack(spacing: 8) {
            PhosphorDot(color: surface.signal, size: 5)
            Text(broadcastChromeLine(for: r))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(surface.inkMuted)
                .lineLimit(1)
            Spacer()
        }
    }

    private func broadcastChromeLine(for r: TalkieObject) -> String {
        var parts: [String] = [r.type.rawValue.uppercased()]
        if let app = r.appContext?.name, !app.isEmpty {
            parts.append("IN \(app.uppercased())")
        } else if r.source.displayName.uppercased() != r.type.rawValue.uppercased() {
            parts.append(r.source.displayName.uppercased())
        }
        parts.append(RelativeTimeFormatter.format(r.createdAt).uppercased())
        return parts.joined(separator: " · ")
    }

    private func broadcastTitle(for r: TalkieObject) -> String {
        if let t = r.title, !t.isEmpty { return t }
        if let p = r.transcriptPreview, !p.isEmpty { return p }
        return r.displayTitle
    }

    /// Each record type declares its own presentation in this slot —
    /// the "core presentation thing" that's the design constraint of
    /// this canvas. Adding a new `TalkieObjectType` means filling in
    /// the corresponding case here.
    @ViewBuilder
    private func broadcastTypeAccent(_ r: TalkieObject, surface: ReadoutSurface) -> some View {
        switch r.type {
        case .memo:      memoBroadcastAccent(r, surface: surface)
        case .dictation: dictationBroadcastAccent(r, surface: surface)
        case .note:      noteBroadcastAccent(r, surface: surface)
        case .capture:   captureBroadcastAccent(r, surface: surface)
        default:         genericBroadcastAccent(r, surface: surface)
        }
    }

    // Memo → bottom waveform + duration ruler. Audio is the point.
    private func memoBroadcastAccent(_ r: TalkieObject, surface: ReadoutSurface) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TraceSparkline(seed: r.id.uuidString.hashValue)
                .frame(height: 22)
                .opacity(0.85)
            HStack {
                Text("0:00")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(surface.inkSubtle)
                Spacer()
                if r.wordCount > 0 {
                    Text("\(r.wordCount.formattedWithSeparator) WORDS")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(surface.inkSubtle)
                    Text("·")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(surface.inkSubtle.opacity(0.6))
                }
                Text(r.duration > 0 ? formatDuration(r.duration) : "—")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(surface.inkSubtle)
            }
        }
    }

    // Dictation → word count + target arrow. Text-first, audio transient.
    private func dictationBroadcastAccent(_ r: TalkieObject, surface: ReadoutSurface) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(r.wordCount.formattedWithSeparator)")
                .font(.system(size: 22, weight: .light, design: .default))
                .foregroundStyle(surface.inkPrimary)
                .monospacedDigit()
                .tracking(-0.3)
            Text("words")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(surface.inkMuted)
            Spacer()
            if let target = r.appContext?.name, !target.isEmpty {
                Text("→  \(target.uppercased())")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(surface.inkMuted)
            } else if r.duration > 0 {
                Text(formatDuration(r.duration))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(surface.inkSubtle)
            }
        }
    }

    // Note → content composition (text + screenshots + clips).
    private func noteBroadcastAccent(_ r: TalkieObject, surface: ReadoutSurface) -> some View {
        let shots = r.screenshots.count
        let clips = r.clips.count
        let attachments = r.attachments.count
        var bits: [String] = []
        if r.wordCount > 0 { bits.append("\(r.wordCount.formattedWithSeparator) WORDS") }
        if shots > 0       { bits.append("\(shots) \(shots == 1 ? "SHOT" : "SHOTS")") }
        if clips > 0       { bits.append("\(clips) \(clips == 1 ? "CLIP" : "CLIPS")") }
        if attachments > 0 { bits.append("\(attachments) \(attachments == 1 ? "FILE" : "FILES")") }
        if bits.isEmpty    { bits.append("TYPED NOTE") }

        return HStack(spacing: 10) {
            Image(systemName: noteSymbol(shots: shots, clips: clips, attachments: attachments))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(surface.inkMuted)
            Text(bits.joined(separator: "  ·  "))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(surface.inkMuted)
            Spacer()
        }
    }

    private func noteSymbol(shots: Int, clips: Int, attachments: Int) -> String {
        if clips > 0           { return "play.rectangle" }
        if shots > 0           { return "photo.on.rectangle" }
        if attachments > 0     { return "paperclip" }
        return "text.alignleft"
    }

    // Capture → context source + dimensions if we have a screenshot.
    private func captureBroadcastAccent(_ r: TalkieObject, surface: ReadoutSurface) -> some View {
        let firstShot = r.screenshots.first
        return HStack(spacing: 10) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(surface.inkMuted)
            if let shot = firstShot {
                Text(captureMetaLine(for: r, shot: shot))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(surface.inkMuted)
            } else {
                Text("CAPTURE  ·  \(r.source.displayName.uppercased())")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(surface.inkMuted)
            }
            Spacer()
        }
    }

    private func captureMetaLine(for r: TalkieObject, shot: RecordingScreenshot) -> String {
        var parts: [String] = []
        if let w = shot.width, let h = shot.height, w > 0, h > 0 {
            parts.append("\(w) × \(h)")
        }
        if !shot.captureMode.isEmpty {
            parts.append(shot.captureMode.uppercased())
        }
        if let app = shot.appName, !app.isEmpty {
            parts.append("FROM \(app.uppercased())")
        }
        if parts.isEmpty { parts.append("CAPTURE") }
        return parts.joined(separator: "  ·  ")
    }

    // Anything else (selection, segment) → minimal generic accent.
    private func genericBroadcastAccent(_ r: TalkieObject, surface: ReadoutSurface) -> some View {
        HStack {
            Text(r.source.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(surface.inkMuted)
            if r.duration > 0 {
                Text("·")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(surface.inkSubtle.opacity(0.6))
                Text(formatDuration(r.duration))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(surface.inkSubtle)
            }
            Spacer()
        }
    }

    /// Source-color "line" for the top accent bar — Slack purple,
    /// Notes yellow, etc. Falls back to a quiet neutral when the
    /// source isn't recognized.
    private func broadcastSourceTint(for r: TalkieObject) -> Color {
        let name = (r.appContext?.name ?? r.source.displayName).lowercased()
        switch name {
        case let s where s.contains("slack"):    return Color.hex("6B4FBB")
        case let s where s.contains("notes"):    return Color.hex("FFD400")
        case let s where s.contains("mic"):      return Color.hex("34D1B7")
        case let s where s.contains("meeting"),
             let s where s.contains("zoom"):     return Color.hex("FF5E5B")
        case let s where s.contains("cursor"),
             let s where s.contains("vscode"),
             let s where s.contains("code"):     return Color.hex("4FC3FF")
        case let s where s.contains("mail"):     return Color.hex("48A8E0")
        case let s where s.contains("safari"),
             let s where s.contains("chrome"),
             let s where s.contains("arc"):      return Color.hex("8E7CC9")
        default:                                  return Color.hex("9AA8A4")
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "0:\(String(format: "%02d", secs))"
    }

    private struct ReadoutStats {
        let total: Int
        let thisWeek: Int
        let topChannel: String
        let avgDuration: String
    }

    private func readoutStats() -> ReadoutStats {
        let week = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var thisWeek = 0
        var totalDuration: Double = 0
        var withDuration = 0
        var channelCounts: [String: Int] = [:]
        for r in viewModel.recordings {
            if r.createdAt >= week { thisWeek += 1 }
            if r.duration > 0 {
                totalDuration += r.duration
                withDuration += 1
            }
            let channel = r.appContext?.name ?? r.source.displayName
            channelCounts[channel, default: 0] += 1
        }
        let top = channelCounts.max { $0.value < $1.value }?.key ?? "—"
        let avg: String
        if withDuration > 0 {
            let avgSecs = totalDuration / Double(withDuration)
            let mins = Int(avgSecs) / 60
            let secs = Int(avgSecs) % 60
            avg = mins > 0 ? "\(mins):\(String(format: "%02d", secs))" : "0:\(String(format: "%02d", secs))"
        } else {
            avg = "—"
        }
        return ReadoutStats(
            total: viewModel.recordings.count,
            thisWeek: thisWeek,
            topChannel: top.uppercased(),
            avgDuration: avg
        )
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

// MARK: - Readout body variants
//
// The Library inspector header is a permanent "instrument bay" that
// renders one of several body variants. Each body owns its own
// palette (see `ReadoutSurface` below), so the bay chrome can host
// a Phase Plot in abyssal teal *or* a Reference Monitor in slate *or*
// a Transit Console in pixel black without forking the wrapper. Same
// envelope, different instruments.
//
// Adding a new variant: add a case + displayName here, declare a
// `ReadoutSurface` static for its palette, write the body view, dispatch
// it from `libraryReadoutPanel`. No other code changes required.

enum LibraryReadoutBodyVariant: String, CaseIterable, Hashable {
    /// The original 4-tile grid: TRACKS · THIS WEEK · TOP CHANNEL · AVG LENGTH.
    /// Baseline / control surface.
    case stats
    /// Living Lissajous curl — pure aesthetic. Idle: hypnotic figure-eight
    /// in aqua-mint phosphor. Selected: trace unwraps to a horizontal
    /// amplitude band, recording title overlays in cream.
    case phasePlot
    /// Polymorphic broadcast canvas. Slate surface, SF Pro typography,
    /// source-colored accent bar at the top edge. Each record type owns
    /// its own "core presentation" in the canvas — memo gets a waveform,
    /// dictation gets word count + target, note gets content type, etc.
    /// The constraint: every new record type has to declare how it
    /// presents itself here.
    case broadcast

    var displayName: String {
        switch self {
        case .stats:     return "Stats"
        case .phasePlot: return "Phase Plot"
        case .broadcast: return "Broadcast"
        }
    }
}

/// Palette + chrome configuration for one readout body variant. The
/// bay wrapper (top strip, body, bottom strip, drop shadow) is universal
/// — variants only declare their colors and the labels that flank their
/// body. New variants get instant chrome by defining a `ReadoutSurface`.
struct ReadoutSurface {
    /// Primary bay fill.
    let bg: Color
    /// Sub-recess — used for the top + bottom strips when they're solid.
    let bgSecondary: Color
    /// Optional metallic gradient for the top strip; falls back to `bgSecondary`.
    let stripTop: AnyShapeStyle?
    /// Optional metallic gradient for the bottom strip; falls back to `bgSecondary`.
    let stripBottom: AnyShapeStyle?
    /// Body / focal text.
    let inkPrimary: Color
    /// Section / mid-weight labels.
    let inkMuted: Color
    /// Tertiary metadata.
    let inkSubtle: Color
    /// The "lit pixel" / phosphor color — the variant's signature.
    let signal: Color
    /// Glow halo for the signal.
    let signalGlow: Color
    /// Frame hairline.
    let edgeFaint: Color
    /// Top strip leading label (left side).
    let topStripLeading: String
    /// Top strip trailing label (right side).
    let topStripTrailing: String
    /// Bottom strip leading label.
    let bottomStripLeading: String
}

extension ReadoutSurface {
    /// Current default — matches the global panel tokens, so existing
    /// stats grid continues to render on cool gunmetal without forking.
    static let stats = ReadoutSurface(
        bg: ScopePanel.bg,
        bgSecondary: ScopePanel.bg,
        stripTop: AnyShapeStyle(ScopePanel.stripTop),
        stripBottom: AnyShapeStyle(ScopePanel.stripBottom),
        inkPrimary: ScopePanel.ink,
        inkMuted: ScopePanel.inkMuted,
        inkSubtle: ScopePanel.inkSubtle,
        signal: ScopePanel.trace,
        signalGlow: ScopePanel.traceGlow,
        edgeFaint: ScopePanel.Edge.faint,
        topStripLeading: "LIBRARY",
        topStripTrailing: "",
        bottomStripLeading: "· 30D"
    )

    /// Abyssal teal-black with aqua-mint phosphor — the figure-eight bay.
    static let phasePlot = ReadoutSurface(
        bg: Color.hex("0B1418"),
        bgSecondary: Color.hex("0F1C22"),
        stripTop: nil,
        stripBottom: nil,
        inkPrimary: Color.hex("F2F6F4"),
        inkMuted: Color.hex("9FB3AE"),
        inkSubtle: Color.hex("6A7E7A"),
        signal: Color.hex("5FE3C9"),
        signalGlow: Color.hex("5FE3C9").opacity(0.45),
        edgeFaint: Color.hex("5FE3C9").opacity(0.12),
        topStripLeading: "LIBRARY",
        topStripTrailing: "",
        bottomStripLeading: ""
    )

    /// Slate canvas with neutral cream ink — the merged Broadcast.
    /// Borrows Transit Console's source-coded accent bar idea (the bar
    /// at the top lights up in the source color when something is
    /// selected) and Reference Monitor's calm SF Pro typography (no
    /// amber title text, amber reserved for the eyebrow dot). The body
    /// is a polymorphic canvas — each `TalkieObjectType` declares its
    /// own presentation inside it.
    static let broadcast = ReadoutSurface(
        bg: Color.hex("15191E"),
        bgSecondary: Color.hex("1A1F25"),
        stripTop: nil,
        stripBottom: nil,
        inkPrimary: Color.hex("E8ECEA"),
        inkMuted: Color.hex("9AA8A4"),
        inkSubtle: Color.hex("6B7A75"),
        signal: Color.hex("C47D1C"),
        signalGlow: Color.hex("C47D1C").opacity(0.32),
        edgeFaint: Color.hex("2A3138"),
        topStripLeading: "LIBRARY",
        topStripTrailing: "",
        bottomStripLeading: ""
    )

    /// Resolved top-strip fill — either the variant's custom gradient
    /// or its `bgSecondary` solid fill.
    @ViewBuilder
    var topStripFill: some View {
        if let style = stripTop {
            Rectangle().fill(style)
        } else {
            Rectangle().fill(bgSecondary)
        }
    }

    /// Resolved bottom-strip fill.
    @ViewBuilder
    var bottomStripFill: some View {
        if let style = stripBottom {
            Rectangle().fill(style)
        } else {
            Rectangle().fill(bgSecondary)
        }
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
