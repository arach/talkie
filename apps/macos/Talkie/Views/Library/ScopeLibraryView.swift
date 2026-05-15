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
                    HStack(spacing: 0) {
                        listColumn
                            .frame(width: max(420, geo.size.width * 0.46))
                        Rectangle()
                            .fill(ScopeEdge.faint)
                            .frame(width: 1)
                        inspectorColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
            statStrip
            filterRibbon
            searchBar
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

    // MARK: - Header strip
    //
    // Universal 44pt top band — title names the active filter, trailing
    // chrome states totals, record button anchors the right edge.
    // Baseline-aligned with the sidebar wordmark via `ScopeTopBand`.

    private var heroHeader: some View {
        ScopeTopBand(
            title: filterEyebrow,
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

    private var filterEyebrow: String {
        switch typeFilter {
        case .all:        return "Library"
        case .memos:      return "Memos"
        case .dictations: return "Dictations"
        case .notes:      return "Notes"
        case .captures:   return "Captures"
        }
    }

    // MARK: - Stat strip (bichromatic dark bay)

    private var statStrip: some View {
        let stats = computeStats()
        return ZStack {
            Rectangle()
                .fill(ScopePanel.bg)
                .overlay(
                    Rectangle().stroke(ScopePanel.Edge.normal, lineWidth: 0.5)
                )
            GraticuleBackground(pitch: 18, color: ScopePanel.traceFaint, opacity: 0.45)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                statTile(value: "\(stats.memos)", label: "MEMOS")
                tileDivider
                statTile(value: "\(stats.dictations)", label: "DICTATIONS")
                tileDivider
                statTile(value: "\(stats.notes)", label: "NOTES")
                tileDivider
                statTile(value: stats.wordsFormatted, label: "WORDS")
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 56)
        .padding(.horizontal, 32)
        .padding(.top, 16)
    }

    private var tileDivider: some View {
        Rectangle()
            .fill(ScopePanel.Edge.faint)
            .frame(width: 1)
            .padding(.vertical, 12)
    }

    private func statTile(value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Text(value)
                .font(ScopeFont.display(size: 20))
                .foregroundStyle(ScopePanel.trace)
                .tracking(-0.4)
                .shadow(color: ScopePanel.traceGlow, radius: 3)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private struct LibraryStats {
        let memos: Int
        let dictations: Int
        let notes: Int
        let words: Int
        var wordsFormatted: String {
            if words >= 1000 {
                return String(format: "%.1fk", Double(words) / 1000)
            }
            return "\(words)"
        }
    }

    private func computeStats() -> LibraryStats {
        var memos = 0
        var dictations = 0
        var notes = 0
        var words = 0
        for r in viewModel.recordings {
            switch r.type {
            case .memo: memos += 1
            case .dictation: dictations += 1
            case .note: notes += 1
            default: break
            }
            words += r.wordCount
        }
        return LibraryStats(memos: memos, dictations: dictations, notes: notes, words: words)
    }

    // MARK: - Filter ribbon

    private var filterRibbon: some View {
        HStack(spacing: 6) {
            ForEach(RecordingTypeFilter.allCases, id: \.self) { option in
                filterChip(option)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func filterChip(_ option: RecordingTypeFilter) -> some View {
        let isSelected = typeFilter == option
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { typeFilter = option }
        } label: {
            Text(option.label.uppercased())
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(isSelected ? ScopePanel.bg : ScopeInk.faint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isSelected ? ScopeAmber.solid : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(isSelected ? ScopeAmber.solid : ScopeEdge.normal, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search bar

    private var searchBar: some View {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(ScopeCanvas.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ScopeEdge.normal, lineWidth: 0.5)
        )
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
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
        .background(ScopeCanvas.surface)
    }

    private var inspectorEmpty: some View {
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

                // Trailing: time-ago, plus tiny sparkline for memos with duration.
                VStack(alignment: .trailing, spacing: 4) {
                    Text(timeAgo)
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                    if recording.isMemo && recording.duration > 0 {
                        TraceSparkline(seed: recording.id.uuidString.hashValue)
                            .frame(width: 56, height: 10)
                            .opacity(isHovered || isSelected ? 1.0 : 0.65)
                    }
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
