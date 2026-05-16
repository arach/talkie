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

    /// Active treatment for the filter ribbon. Pickable in DesignMode
    /// (Debug → Components) so we can A/B different visual languages
    /// without code edits. Default matches what shipped to master.
    @AppStorage("scopeLibrary.filterRibbonVariant")
    private var filterRibbonVariantRaw: String = LibraryFilterRibbonVariant.classic.rawValue
    private var filterRibbonVariant: LibraryFilterRibbonVariant {
        LibraryFilterRibbonVariant(rawValue: filterRibbonVariantRaw) ?? .classic
    }

    /// Active treatment for the empty inspector pane.
    @AppStorage("scopeLibrary.inspectorEmptyVariant")
    private var inspectorEmptyVariantRaw: String = LibraryInspectorEmptyVariant.simple.rawValue
    private var inspectorEmptyVariant: LibraryInspectorEmptyVariant {
        LibraryInspectorEmptyVariant(rawValue: inspectorEmptyVariantRaw) ?? .simple
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

    /// Dispatches the filter-ribbon presentation by the active variant
    /// stored in `@AppStorage`. Each variant is responsible for its own
    /// layout including the search field (some treatments fuse them
    /// into one container, others keep them separate surfaces).
    @ViewBuilder
    private var topComponent: some View {
        let counts = filterCounts()
        Group {
            switch filterRibbonVariant {
            case .classic:        classicRibbon(counts: counts, palette: .warm)
            case .classicTepid:   classicRibbon(counts: counts, palette: .tepid)
            case .classicSilver:  classicRibbon(counts: counts, palette: .silver)
            case .classicSlate:   classicRibbon(counts: counts, palette: .slate)
            case .patchBay:       patchBayRibbon(counts: counts)
            case .instrumentBay:  instrumentBayRibbon(counts: counts)
            case .indexTabs:      indexTabsRibbon(counts: counts)
            case .etchedSelector: etchedSelectorRibbon(counts: counts)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .animation(.smooth(duration: 0.4), value: viewModel.recordings.count)
    }

    /// Palette for the Classic ribbon family. `warm` matches the
    /// original cream + brown active state; `silver` and `slate` use
    /// cool/metallic surfaces to step away from the warm direction.
    private struct ClassicPalette {
        let containerFill: Color
        let containerStroke: Color
        let activeFillTop: Color
        let activeFillBottom: Color
        let activeText: Color
        let inactiveText: Color
        let countOpacityActive: Double
        let countOpacityInactive: Double

        static let warm = ClassicPalette(
            containerFill: ScopeCanvas.surface,
            containerStroke: ScopeEdge.faint,
            activeFillTop: Color.hex("4A4744"),
            activeFillBottom: Color.hex("36343A"),
            activeText: ScopeAmber.solid,
            inactiveText: ScopeInk.muted,
            countOpacityActive: 0.85,
            countOpacityInactive: 0.55
        )

        /// Cool neutral graphite. Container stays cream so the page
        /// doesn't feel half-converted to silver, but the active pill
        /// drops its warm/brown bias — reads as a stamped slate plate.
        static let tepid = ClassicPalette(
            containerFill: ScopeCanvas.surface,
            containerStroke: ScopeEdge.faint,
            activeFillTop: Color.hex("525458"),
            activeFillBottom: Color.hex("38393D"),
            activeText: Color.hex("F2F1EE"),
            inactiveText: ScopeInk.muted,
            countOpacityActive: 0.7,
            countOpacityInactive: 0.55
        )

        static let silver = ClassicPalette(
            // Cool pale surface — barely-warm neutral, drops the cream.
            containerFill: Color.hex("EFEFF1"),
            containerStroke: Color.hex("D6D6DA"),
            // Brushed steel active fill: light silver fading down.
            activeFillTop: Color.hex("8E9098"),
            activeFillBottom: Color.hex("5D6068"),
            activeText: Color.hex("F2F2F4"),
            inactiveText: Color.hex("6E6E73"),
            countOpacityActive: 0.7,
            countOpacityInactive: 0.55
        )

        static let slate = ClassicPalette(
            // Slightly deeper cool gray — reads as architectural slate.
            containerFill: Color.hex("DEDEE2"),
            containerStroke: Color.hex("C3C3C8"),
            // Deep steel active fill: charcoal with a hint of cool light.
            activeFillTop: Color.hex("55585F"),
            activeFillBottom: Color.hex("3A3C42"),
            activeText: Color.hex("E8E8EC"),
            inactiveText: Color.hex("5A5C62"),
            countOpacityActive: 0.7,
            countOpacityInactive: 0.6
        )
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

    // MARK: Variant — Classic family (cream / silver / slate palettes)

    private func classicRibbon(counts: FilterCounts, palette: ClassicPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(RecordingTypeFilter.allCases, id: \.self) { option in
                    classicSegment(option, count: counts.count(for: option), palette: palette)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(4)

            Rectangle()
                .fill(palette.containerStroke.opacity(0.6))
                .frame(height: 0.5)

            searchField
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(palette.containerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(palette.containerStroke, lineWidth: 0.5)
        )
    }

    private func classicSegment(
        _ option: RecordingTypeFilter,
        count: Int,
        palette: ClassicPalette
    ) -> some View {
        let isSelected = typeFilter == option
        return Button {
            typeFilter = option
        } label: {
            HStack(spacing: 6) {
                Text(option.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("\(count)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 16, alignment: .trailing)
                    .opacity(isSelected ? palette.countOpacityActive : palette.countOpacityInactive)
            }
            .foregroundStyle(isSelected ? palette.activeText : palette.inactiveText)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [palette.activeFillTop, palette.activeFillBottom],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: Variant — Patch Bay (brass LED dots, no container)

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

    // MARK: Variant — Instrument Bay (dark panel, phosphor active state)

    private func instrumentBayRibbon(counts: FilterCounts) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopePanel.bg)
                GraticuleBackground(pitch: 18, color: ScopePanel.traceFaint, opacity: 0.4)
                    .mask(RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 0) {
                    ForEach(RecordingTypeFilter.allCases, id: \.self) { option in
                        instrumentBaySegment(option, count: counts.count(for: option))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(ScopePanel.stripTop)
                        .frame(height: 3)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 6,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 6
                            )
                        )
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ScopePanel.stripBottom)
                        .frame(height: 3)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 6,
                                bottomTrailingRadius: 6,
                                topTrailingRadius: 0
                            )
                        )
                }
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

    private func instrumentBaySegment(_ option: RecordingTypeFilter, count: Int) -> some View {
        let isSelected = typeFilter == option
        return Button {
            typeFilter = option
        } label: {
            HStack(spacing: 6) {
                Text(option.label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("\(count)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ScopePanel.bgDeep)
                    )
                    .foregroundStyle(
                        isSelected
                            ? ScopePanel.trace.opacity(0.85)
                            : ScopePanel.inkSubtle
                    )
            }
            .foregroundStyle(isSelected ? ScopePanel.trace : ScopePanel.inkFaint)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isSelected ? ScopePanel.bgDeep : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(
                                isSelected ? ScopePanel.Edge.normal : Color.clear,
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: isSelected ? ScopeAmber.glow : .clear, radius: 4)
            )
            .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    // MARK: Variant — Index Tabs (card-catalog tabs fused to search)
    //
    // Tabs sit directly on top of the search row with zero gap between
    // them. The active tab "owns" the search row visually: its bottom
    // border drops out so the two surfaces read as one drawer. Inactive
    // tabs sit on a recessed lower plane (a 1pt baseline runs across
    // the row of inactive tabs). Inter-tab gap is hairline only, not
    // padding — keeps the row tight and unified.

    private func indexTabsRibbon(counts: FilterCounts) -> some View {
        let surface = Color.hex("EFEFF1")
        let recessed = Color.hex("E0E0E4")
        let edge = Color.hex("CDCDD2")

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(RecordingTypeFilter.allCases.enumerated()), id: \.offset) { idx, option in
                    indexTabsSegment(
                        option,
                        count: counts.count(for: option),
                        surface: surface,
                        recessed: recessed,
                        edge: edge
                    )
                    .frame(maxWidth: .infinity)
                    if idx < RecordingTypeFilter.allCases.count - 1 {
                        Rectangle()
                            .fill(edge.opacity(0.6))
                            .frame(width: 0.5, height: 18)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 6)
                    }
                }
            }
            .frame(height: 30, alignment: .bottom)
            .overlay(alignment: .bottom) {
                // Baseline that runs UNDER inactive tabs but breaks for
                // the active one — implemented as a full-width hairline
                // that the active tab's surface visually overrides.
                Rectangle().fill(edge).frame(height: 0.5)
            }

            // Search row — surface continues from the active tab
            searchField
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(surface)
        }
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(edge, lineWidth: 0.5)
        )
    }

    private func indexTabsSegment(
        _ option: RecordingTypeFilter,
        count: Int,
        surface: Color,
        recessed: Color,
        edge: Color
    ) -> some View {
        let isSelected = typeFilter == option
        return Button {
            typeFilter = option
        } label: {
            HStack(spacing: 5) {
                Text(option.label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("\(count)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(
                        isSelected
                            ? ScopeAmber.solid.opacity(0.8)
                            : Color.hex("8A8A90")
                    )
            }
            .foregroundStyle(isSelected ? Color.hex("1A1612") : Color.hex("6E6E73"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? surface : recessed)
            .overlay(alignment: .top) {
                // Top amber edge only on active tab.
                Rectangle()
                    .fill(isSelected ? ScopeAmber.solid : Color.clear)
                    .frame(height: 1.5)
            }
            .padding(.top, isSelected ? 0 : 4) // inactive tabs sit lower
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Variant — Etched Selector (drafting-paper, left-aligned)
    //
    // Labels group from the left with full-height vertical separators
    // between each, so the gap between MEMOS · DICTATIONS · CAPTURES
    // reads as deliberate joinery (not gutters). Active label gets an
    // amber underline; the row hugs its content, with a trailing
    // Spacer pushing the whole bank against the left edge.

    private func etchedSelectorRibbon(counts: FilterCounts) -> some View {
        let separator = Color.hex("BFBCB1")  // warm hairline (not too amber)
        return VStack(spacing: 14) {
            HStack(spacing: 0) {
                // Leading bracket
                Rectangle()
                    .fill(separator)
                    .frame(width: 0.5, height: 22)

                ForEach(Array(RecordingTypeFilter.allCases.enumerated()), id: \.offset) { idx, option in
                    etchedSelectorSegment(option, count: counts.count(for: option))
                    if idx < RecordingTypeFilter.allCases.count - 1 {
                        Rectangle()
                            .fill(separator)
                            .frame(width: 0.5, height: 22)
                    }
                }

                // Trailing bracket — closes the bank
                Rectangle()
                    .fill(separator)
                    .frame(width: 0.5, height: 22)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)

            searchField
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(alignment: .top) {
                    Rectangle().fill(ScopeEdge.faint).frame(height: 0.5)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ScopeEdge.faint).frame(height: 0.5)
                }
        }
    }

    private func etchedSelectorSegment(_ option: RecordingTypeFilter, count: Int) -> some View {
        let isSelected = typeFilter == option
        return Button {
            typeFilter = option
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(option.label.uppercased())
                        .font(.system(
                            size: 11,
                            weight: isSelected ? .bold : .medium,
                            design: .monospaced
                        ))
                        .tracking(1.2)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(isSelected ? ScopeInk.primary : ScopeInk.muted)
                    Text("\(count)")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(ScopeInk.subtle)
                }
                Rectangle()
                    .fill(isSelected ? ScopeAmber.solid : Color.clear)
                    .frame(height: 1.5)
                    .shadow(color: isSelected ? ScopeAmber.glow : .clear, radius: 3)
            }
            .padding(.horizontal, 14)
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
            Text("SCANNING TAPE · STAND BY")
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
            Text("NO SIGNAL · WAITING FOR INPUT")
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
        case .all: return "Start a recording — the channel will light up."
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
            VStack(alignment: .leading, spacing: 6) {
                variantRow(
                    label: "RIBBON",
                    options: LibraryFilterRibbonVariant.allCases,
                    raw: $filterRibbonVariantRaw,
                    rawOf: { $0.rawValue },
                    nameOf: { $0.displayName }
                )
                variantRow(
                    label: "EMPTY",
                    options: LibraryInspectorEmptyVariant.allCases,
                    raw: $inspectorEmptyVariantRaw,
                    rawOf: { $0.rawValue },
                    nameOf: { $0.displayName }
                )
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

    private func variantRow<Option: Hashable>(
        label: String,
        options: [Option],
        raw: Binding<String>,
        rawOf: @escaping (Option) -> String,
        nameOf: @escaping (Option) -> String
    ) -> some View {
        HStack(spacing: 6) {
            Text("· \(label)")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
                .frame(width: 60, alignment: .leading)
            ForEach(options, id: \.self) { option in
                let rawValue = rawOf(option)
                let isActive = raw.wrappedValue == rawValue
                Button {
                    raw.wrappedValue = rawValue
                } label: {
                    Text(nameOf(option).uppercased())
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
    // For the `.libraryReadout` variant the readout panel sits as a
    // permanent header above whatever the rest of the column shows —
    // selection detail, multi-select hint, or empty hint. The panel
    // doesn't reflow or move when selection changes; it's a stable
    // shelf with the row detail rendered below it.

    private var inspectorColumn: some View {
        VStack(spacing: 0) {
            if inspectorEmptyVariant == .readout {
                libraryReadoutPanel
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                Rectangle().fill(ScopeEdge.faint).frame(height: 0.5)
            }

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

    /// The readout panel extracted so it can render both as the empty
    /// state of the `.libraryReadout` variant AND as the permanent
    /// header above selection-driven detail. Same dark graphite bay
    /// with stripTop header, 4-tile grid, stripBottom footer.
    private var libraryReadoutPanel: some View {
        let stats = readoutStats()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("· LIBRARY")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                Spacer()
                Text("\(viewModel.totalCount) ON FILE")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ScopePanel.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ScopePanel.Edge.normal, lineWidth: 1)
                    )
                GraticuleBackground(pitch: 20, color: ScopePanel.traceFaint, opacity: 0.5)
                    .mask(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 0) {
                    readoutHeader(stats: stats)
                    readoutGrid(stats: stats)
                    readoutFooter(stats: stats)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 200)
            .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
        }
    }

    @ViewBuilder
    private var inspectorEmpty: some View {
        switch inspectorEmptyVariant {
        case .simple, .readout:
            // For `.readout` the panel renders permanently above this
            // body in `inspectorColumn`. The empty body itself is the
            // same minimal "NO TRACK SELECTED" hint as `.simple`.
            inspectorEmptySimple
        case .cassette:
            inspectorEmptyCassette
        case .idleTrace:
            inspectorEmptyIdleTrace
        }
    }

    // MARK: Variant — Simple (the original centered eyebrow)

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
            Text("NO TRACK SELECTED")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            Text("Pick a row to inspect its trace.")
                .font(.system(size: 12))
                .foregroundStyle(ScopeInk.subtle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Variant — Library Readout (mini instrument bay, permanent header)
    //
    // The readout view is `libraryReadoutPanel` defined alongside
    // `inspectorColumn` above — when the variant is `.readout` the
    // panel renders permanently at the top of the inspector and the
    // empty-state body below it is the same simple hint as `.simple`.

    private func readoutHeader(stats: ReadoutStats) -> some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopePanel.trace, size: 5)
            Text("LIBRARY · IDLE")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text("LOCAL ONLY")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ScopePanel.stripTop)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ScopePanel.Edge.faint)
                .frame(height: 1)
                .padding(.horizontal, 14)
        }
    }

    private func readoutGrid(stats: ReadoutStats) -> some View {
        HStack(spacing: 0) {
            readoutTile(value: "\(stats.total)", label: "TRACKS")
            readoutDivider
            readoutTile(value: "\(stats.thisWeek)", label: "THIS WEEK")
            readoutDivider
            readoutTile(value: stats.topChannel, label: "TOP CHANNEL")
            readoutDivider
            readoutTile(value: stats.avgDuration, label: "AVG LENGTH")
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 14)
    }

    private var readoutDivider: some View {
        Rectangle()
            .fill(ScopePanel.Edge.faint)
            .frame(width: 1)
            .padding(.vertical, 18)
    }

    private func readoutTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(ScopeFont.display(size: 28))
                .foregroundStyle(ScopePanel.trace)
                .tracking(-0.4)
                .shadow(color: ScopePanel.traceGlow, radius: 4)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func readoutFooter(stats: ReadoutStats) -> some View {
        HStack(spacing: 12) {
            Text("· 30D · SIGNAL PATH · LOCAL")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text(Date().formatted(date: .omitted, time: .shortened).uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ScopePanel.stripBottom)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ScopePanel.Edge.faint)
                .frame(height: 1)
                .padding(.horizontal, 14)
        }
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

    // MARK: Variant — Cassette Carriage (hairline scaffold of the filled state)

    private var inspectorEmptyCassette: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                PhosphorDot(color: ScopeAmber.solid.opacity(0.7), size: 5)
                Text("AWAITING SELECT · CH —")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
                Spacer()
                Text("—:—")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ScopeEdge.faint).frame(height: 0.5)
            }

            // Sparkline well — outlined slot where the trace would render
            RoundedRectangle(cornerRadius: 4)
                .stroke(ScopeEdge.subtle, lineWidth: 0.5)
                .frame(height: 56)

            // Transcript ghost lines — varied widths suggest text flow
            VStack(alignment: .leading, spacing: 10) {
                ForEach([0.92, 0.78, 0.85, 0.40], id: \.self) { width in
                    Capsule()
                        .fill(ScopeAmber.tintSubtle)
                        .frame(height: 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }

            // Metadata grid — 4 ghost label/value pairs
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(ScopeEdge.subtle)
                            .frame(width: 28, height: 4)
                        Capsule()
                            .fill(ScopeEdge.faint)
                            .frame(width: 52, height: 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Variant — Idle Trace (oscilloscope baseline waiting for a trigger)

    private var inspectorEmptyIdleTrace: some View {
        ZStack {
            GraticuleBackground(pitch: 24, color: ScopeTrace.faint, opacity: 0.55)
                .allowsHitTesting(false)

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { ctx in
                Canvas { context, size in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let y = size.height / 2
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    let blipPhase = (t.truncatingRemainder(dividingBy: 4.0)) / 4.0
                    let blipActive = blipPhase > 0.92
                    let stride: CGFloat = 2
                    var x: CGFloat = 0
                    while x <= size.width {
                        let phase = Double(x / size.width)
                        var dy: CGFloat = 0
                        if blipActive {
                            let envelope = pow(sin(blipPhase * .pi * 12), 2)
                            dy = CGFloat(sin(phase * 70 + t * 4) * 4 * envelope)
                        }
                        path.addLine(to: CGPoint(x: x, y: y + dy))
                        x += stride
                    }
                    context.stroke(
                        path,
                        with: .color(ScopeAmber.solid.opacity(0.5)),
                        lineWidth: 1
                    )
                }
                .blur(radius: 0.4)
            }

            VStack {
                HStack {
                    Text("CH — · IDLE · 1.00 V/DIV")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Text("NO TRIGGER")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                }
            }
            .padding(20)
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

// MARK: - Library variants
//
// All variant treatments live in dedicated structs (below) so the
// switch at each call site stays compact and individual variants can
// be iterated on without disturbing the rest of the view. Variants
// are selected at runtime via `@AppStorage`-backed enum values, with
// the picker UI living in `DesignComponentsView` (DEBUG-only).

enum LibraryFilterRibbonVariant: String, CaseIterable, Hashable {
    /// Cream-surface bordered container with warm brown active fill
    /// — the treatment that shipped to master.
    case classic
    /// Classic structure, **cool-neutral** active state — sits halfway
    /// between the warm Classic and the full Silver. Cream container
    /// stays put; just the selected pill's fill loses its brown bias.
    case classicTepid
    /// Pale silver container with brushed-steel active fill — full
    /// step toward metallic.
    case classicSilver
    /// Cool light-gray container with charcoal active fill.
    case classicSlate
    /// Pinned brass LED dot above each label; no container.
    case patchBay
    /// Dark graphite strip with graticule grid; phosphor active state.
    case instrumentBay
    /// Card-catalog paper tabs that dock into the search row.
    case indexTabs
    /// Bare labels on cream with graduation ticks; amber underline.
    case etchedSelector

    var displayName: String {
        switch self {
        case .classic:        return "Classic"
        case .classicTepid:   return "Classic · Tepid"
        case .classicSilver:  return "Classic · Silver"
        case .classicSlate:   return "Classic · Slate"
        case .patchBay:       return "Patch Bay"
        case .instrumentBay:  return "Instrument Bay"
        case .indexTabs:      return "Index Tabs"
        case .etchedSelector: return "Etched Selector"
        }
    }
}

enum LibraryInspectorEmptyVariant: String, CaseIterable, Hashable {
    /// Centered eyebrow text (`NO TRACK SELECTED`) — what shipped.
    case simple
    /// Mini Home-style stat panel with sparkline + top sources list.
    case readout
    /// Hairline wireframe of the inspector's filled state — a ghost
    /// of where transcript / sparkline / metadata will land.
    case cassette
    /// Full-pane graticule with an idling amber oscilloscope trace.
    case idleTrace

    var displayName: String {
        switch self {
        case .simple:    return "Simple"
        case .readout:   return "Library Readout"
        case .cassette:  return "Cassette Carriage"
        case .idleTrace: return "Idle Trace"
        }
    }
}
