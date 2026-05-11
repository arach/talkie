//
//  RecordingsScreen.swift
//  Talkie
//
//  Unified recordings list showing both memos and dictations.
//  Built using unified components from CoreComponents.
//

import SwiftUI
import TalkieKit

// MARK: - Recording Type Filter

/// Type filter for the title toggle (All/Memos/Dictations)
enum RecordingTypeFilter: String, CaseIterable, Hashable {
    case all, memos, dictations, captures, notes

    var label: String {
        switch self {
        case .all: return "All"
        case .memos: return "Memos"
        case .dictations: return "Dictations"
        case .captures: return "Captures"
        case .notes: return "Notes"
        }
    }

    var semanticFilter: SemanticFilter {
        switch self {
        case .all: return .all
        case .memos: return .memos
        case .dictations: return .dictations
        case .captures: return .captures
        case .notes: return .notes
        }
    }
}

// MARK: - Recording Type Segmented Control

/// Pill-style segmented control for filtering recordings by type.
/// Feels like a distinct, interactable component.
private struct RecordingTypeSegmentedControl: View {
    @Binding var selection: RecordingTypeFilter
    @State private var hoveredOption: RecordingTypeFilter?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RecordingTypeFilter.allCases, id: \.self) { option in
                segmentButton(option)
            }
        }
        .padding(2)
        .background(Theme.current.foreground.opacity(0.06))
        .clipShape(Capsule())
        .frame(height: RecordingsHeaderLayout.controlHeight)
    }

    private func segmentButton(_ option: RecordingTypeFilter) -> some View {
        let isSelected = selection == option
        let isHovered = hoveredOption == option && !isSelected

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection = option
            }
        } label: {
            Text(option.label)
                .font(isSelected ? Theme.current.fontSMBold : Theme.current.fontSMMedium)
                .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(Theme.current.surface2)
                                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                        } else if isHovered {
                            Capsule()
                                .fill(Theme.current.foreground.opacity(0.04))
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveredOption = $0 ? option : nil }
    }
}

private struct LiveActivityBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    let phase = time * 5.8 + Double(index) * 0.52
                    let normalized = 0.25 + 0.75 * ((sin(phase) + 1) * 0.5)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.current.foregroundMuted.opacity(0.62))
                        .frame(width: 2.1, height: 3 + (normalized * 7))
                }
            }
            .frame(height: 10, alignment: .bottom)
        }
    }
}

// MARK: - Recordings Screen

struct RecordingsScreen: View {
    /// Initial type filter — set by navigation to open with a specific tab
    var initialTypeFilter: RecordingTypeFilter

    init(initialTypeFilter: RecordingTypeFilter = .all) {
        self.initialTypeFilter = initialTypeFilter
    }

    private var viewModel = RecordingsViewModel.shared
    private let liveState = ServiceManager.shared.live
    @State private var selectedRecordingIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    // Keyboard navigation
    @State private var keyboardNav = ListKeyboardNavigator<UUID>()
    @FocusState private var isSearchFocused: Bool

    // Scroll-to on external navigation (home page, search, deep link)
    @State private var pendingScrollID: UUID?

    // Layout — reads from LayoutStore (layout.json)
    @State private var isCompactMode = false
    @State private var showInspectorSheet = false
    private let compactThreshold: CGFloat = 900
    private var layoutStore = LayoutStore.shared

    // Column width configuration
    private static let listColumnMinWidth: CGFloat = 240
    private static let inspectorColumnMinWidth: CGFloat = 400
    @State private var currentSplitRatio: Double = 0.5

    // Bridge to LayoutStore for listCollapsed / isDetailedView
    private var listCollapsed: Bool {
        get { layoutStore.listCollapsed }
        nonmutating set { layoutStore.listCollapsed = newValue }
    }
    private var isDetailedView: Bool {
        get { layoutStore.listDetailed }
        nonmutating set { layoutStore.listDetailed = newValue }
    }

    // Recording view
    @State private var showingRecordingView = false

    // Type filter (title toggle)
    @State private var typeFilter: RecordingTypeFilter = .all

    // Retranscription
    @State private var retranscribingIDs: Set<UUID> = []
    private let repository = TalkieObjectRepository()

    // Navigation coordination
    @State private var suppressFilterReload = false

    private var selectedRecording: TalkieObject? {
        guard selectedRecordingIDs.count == 1, let id = selectedRecordingIDs.first else { return nil }
        return viewModel.recordings.first { $0.id == id }
    }

    // MARK: - Body

    var body: some View {
        TalkieSection(
            "Library",
            showRecordButton: true,
            onRecordTap: { withAnimation(.easeInOut(duration: 0.2)) { showingRecordingView = true } },
            titleAccessory: AnyView(RecordingTypeSegmentedControl(selection: $typeFilter).fixedSize())
        ) {
            ZStack {
                    GeometryReader { geometry in
                        let compact = geometry.size.width < compactThreshold

                        Group {
                            if compact {
                                listPane
                                    .frame(minWidth: 500)
                            } else if listCollapsed {
                            // Minimized list rail + full inspector
                            HStack(spacing: 0) {
                                collapsedListRail
                                inspectorPane
                            }
                        } else {
                            DeterministicSplitView(
                                ratio: currentSplitRatio,
                                minLeftWidth: Self.listColumnMinWidth,
                                minRightWidth: Self.inspectorColumnMinWidth,
                                onRatioChange: { newRatio in
                                    currentSplitRatio = newRatio
                                    layoutStore.setSplitRatio(newRatio, for: typeFilter.rawValue)
                                },
                                left: { listPane },
                                right: { inspectorPane }
                            )
                            .onAppear {
                                currentSplitRatio = layoutStore.splitRatio(for: typeFilter.rawValue)
                            }
                            .onChange(of: typeFilter) { _, newFilter in
                                currentSplitRatio = layoutStore.splitRatio(for: newFilter.rawValue)
                            }
                        }
                    }
                    .frame(minWidth: 500)
                    .background {
                        Button("") { withAnimation(.easeInOut(duration: 0.15)) { listCollapsed.toggle() } }
                            .keyboardShortcut("0", modifiers: .command)
                            .hidden()
                    }
                    .onChange(of: compact) { _, newValue in
                        isCompactMode = newValue
                        if !newValue { showInspectorSheet = false }
                    }
                    .onAppear { isCompactMode = compact }
                }

                // Recording overlay - list stays visible underneath (dimmed)
                if showingRecordingView {
                    RecordingOverlay(
                        controller: MemoRecordingController.shared,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingRecordingView = false
                            }
                            // Refresh after recording
                            Task { await viewModel.loadRecordings() }
                        },
                        onMemoCreated: { memoId in
                            // Refresh list and select the new memo (shows in inspector)
                            await viewModel.refresh()
                            selectedRecordingIDs = [memoId]
                        },
                        onNewRecording: {
                            // Stay in overlay, just reset for new recording
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showingRecordingView)
            .sheet(isPresented: $showInspectorSheet) {
                inspectorSheet
            }
        } onLoad: {
            // Apply initial type filter if set by navigation
            if initialTypeFilter != .all {
                suppressFilterReload = true
                typeFilter = initialTypeFilter
                viewModel.filterState.toggle(initialTypeFilter.semanticFilter)
            }

            // Apply pending navigation params BEFORE initial load
            let pendingParams = NavigationState.shared.params
            if let filterValue = pendingParams["typeFilter"] as? String,
               let filter = RecordingTypeFilter(rawValue: filterValue) {
                suppressFilterReload = true
                typeFilter = filter
                viewModel.filterState.toggle(filter.semanticFilter)
            }
            if let date = pendingParams["dateFilter"] as? Date {
                viewModel.filterState.setDateFilter(date)
            }
            if let query = pendingParams["searchQuery"] as? String {
                searchText = query
                viewModel.filterState.searchQuery = query
            }

            await viewModel.loadWithSemanticFilters()
            setupKeyboardNavigation()

            // Apply selection AFTER data is loaded and scroll to it
            if let id = pendingParams["selectedID"] as? UUID {
                selectedRecordingIDs = [id]
                pendingScrollID = id
            } else if let id = NavigationState.shared.selectedMemoID {
                selectedRecordingIDs = [id]
                pendingScrollID = id
            } else if let id = NavigationState.shared.selectedDictationID {
                selectedRecordingIDs = [id]
                pendingScrollID = id
            }
            if !pendingParams.isEmpty {
                // Only clear params that RecordingsScreen consumed — other params
                // (e.g. initialText for Compose) may be in-flight to another screen.
                for key in pendingParams.keys {
                    NavigationState.shared.params.removeValue(forKey: key)
                }
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
        .onChange(of: typeFilter) { _, newValue in
            if suppressFilterReload {
                suppressFilterReload = false
                return
            }
            Task {
                await viewModel.toggleSemanticFilter(newValue.semanticFilter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ShowRecordingView"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showingRecordingView = true
            }
        }
        .onChange(of: MemoRecordingController.shared.state) { _, newState in
            if newState.isRecording && !showingRecordingView {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingRecordingView = true
                }
            }
        }
        .task(id: NavigationState.shared.selectedMemoID) {
            guard let id = NavigationState.shared.selectedMemoID else { return }
            await waitForRecordingsIfNeeded()
            selectedRecordingIDs = [id]
            pendingScrollID = id
        }
        .task(id: NavigationState.shared.selectedDictationID) {
            guard let id = NavigationState.shared.selectedDictationID else { return }
            await waitForRecordingsIfNeeded()
            selectedRecordingIDs = [id]
            pendingScrollID = id
        }
        .onChange(of: NavigationState.shared.params) { _, newParams in
            consumeNavigationParams(newParams)
        }
        .onDisappear {
            keyboardNav.deactivate()
        }
        #if DEBUG
        .trackDepth("RecordingsScreen")
        #endif
    }

    // MARK: - Collapsed List Rail

    private var collapsedListRail: some View {
        VStack(spacing: 0) {
            // Top area aligned with header band
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { listCollapsed = false } }) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.current.foreground.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help("Show list (⌘0)")
            .padding(.top, 12)
            .padding(.bottom, Spacing.sm)

            // Mini item list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.recordings) { recording in
                        CollapsedRailItem(
                            recording: recording,
                            isSelected: selectedRecordingIDs.contains(recording.id)
                        ) {
                            selectedRecordingIDs = [recording.id]
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 44)
        .background(Theme.current.surfaceBase)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.current.foreground.opacity(0.06))
                .frame(width: 0.5)
        }
    }

    // MARK: - List Pane

    private var listPane: some View {
        VStack(spacing: 0) {

            // Filter chips
            HStack(spacing: Spacing.sm) {
                FilterChipBar(
                    viewModel: viewModel,
                    horizontalInset: 0
                )
            }
            .frame(height: RecordingsHeaderLayout.secondaryBandHeight)
            .padding(.horizontal, PageLayout.horizontalPadding)

            if viewModel.isLoading && viewModel.recordings.isEmpty && liveState.state == .idle {
                loadingState
            } else if viewModel.recordings.isEmpty && liveState.state == .idle {
                emptyState
            } else {
                recordingsList
            }

            footerBar
        }
        .background(TalkieTheme.surface)
    }

    // MARK: - Legacy Header (replaced by FilterChipBar)
    // Kept for reference during transition

    private var sourceFilterMenu: some View {
        let activeSourceFilters = viewModel.activeFilters.compactMap { filter -> RecordingSource? in
            if case .source(let source) = filter { return source }
            return nil
        }

        let label = activeSourceFilters.isEmpty ? "All Sources" :
            activeSourceFilters.count == 1 ? activeSourceFilters[0].displayName :
            "\(activeSourceFilters.count) Sources"

        return Menu {
            Button {
                Task { await viewModel.clearFilters() }
            } label: {
                Label("All Sources", systemImage: "square.grid.2x2")
            }
            .disabled(activeSourceFilters.isEmpty)

            Divider()

            Button {
                Task { await viewModel.toggleFilter(.source(.iphone)) }
            } label: {
                HStack {
                    Label("iPhone", systemImage: "iphone")
                    if viewModel.isFilterActive(.source(.iphone)) {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                Task { await viewModel.toggleFilter(.source(.mac)) }
            } label: {
                HStack {
                    Label("Mac", systemImage: "desktopcomputer")
                    if viewModel.isFilterActive(.source(.mac)) {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                Task { await viewModel.toggleFilter(.source(.live)) }
            } label: {
                HStack {
                    Label("Agent", systemImage: "waveform.circle.fill")
                    if viewModel.isFilterActive(.source(.live)) {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                Task { await viewModel.toggleFilter(.source(.watch)) }
            } label: {
                HStack {
                    Label("Watch", systemImage: "applewatch")
                    if viewModel.isFilterActive(.source(.watch)) {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(activeSourceFilters.isEmpty ? Theme.current.foregroundSecondary : .accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(activeSourceFilters.isEmpty ? Theme.current.foreground.opacity(0.06) : Color.accentColor.opacity(0.15))
            )
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            // Condensed (zen)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isDetailedView = false }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(!isDetailedView ? Theme.current.foreground : Theme.current.foregroundSecondary)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(!isDetailedView ? Theme.current.foreground.opacity(0.1) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Condensed view")

            // Detailed
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isDetailedView = true }
            } label: {
                Image(systemName: "text.justify.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDetailedView ? Theme.current.foreground : Theme.current.foregroundSecondary)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDetailedView ? Theme.current.foreground.opacity(0.1) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Detailed view")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.current.foreground.opacity(0.05))
        )
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if liveState.state != .idle {
                        pendingRecordingRow
                    }

                    ForEach(Array(viewModel.recordings.enumerated()), id: \.element.id) { index, recording in
                        recordingRow(recording: recording, index: index)
                    }

                    // Pagination loading
                    if viewModel.isLoading && !viewModel.recordings.isEmpty {
                        HStack {
                            BrailleSpinner(size: 12)
                            Text("Loading more...")
                                .font(.system(size: 11))
                                .foregroundColor(TalkieTheme.textMuted)
                        }
                        .padding(.vertical, Spacing.md)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .onAppear {
                keyboardNav.onScrollTo = { index in
                    guard index < viewModel.recordings.count else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(viewModel.recordings[index].id, anchor: .center)
                    }
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

    // MARK: - Recording Row

    private func recordingRow(recording: TalkieObject, index: Int) -> some View {
        let isSelected = selectedRecordingIDs.contains(recording.id)
        let isFocused = keyboardNav.focusedIndex == index
        let isMultiSelect = selectedRecordingIDs.count > 1

        return DetailRow(
            isSelected: isSelected,
            isMultiSelectMode: isMultiSelect,
            isFocused: isFocused,
            isAlternate: false,
            style: isDetailedView ? .standard : .compact,
            onSelect: { event in
                keyboardNav.syncFocusToIndex(index)
                handleSelection(recording: recording, event: event)
            }
        ) {
            // Leading: App icon for dictations, type icon for memos
            leadingIcon(for: recording)
        } content: {
            if isDetailedView {
                // DETAILED MODE: Two lines with more context
                detailedRowContent(recording: recording, isSelected: isSelected)
            } else {
                // CONDENSED MODE: Single line, zen, minimal
                condensedRowContent(recording: recording, isSelected: isSelected)
            }
        } trailing: {
            if isDetailedView {
                // Show duration in detailed mode
                DurationBadge(seconds: Int(recording.duration))
            } else {
                // Just time ago in condensed mode
                Text(RelativeTimeFormatter.format(recording.createdAt))
                    .font(Theme.current.fontSM)
                    .foregroundColor(TalkieTheme.textMuted)
            }
        }
        .id(recording.id)
        .contextMenu {
            recordingContextMenu(for: recording)
        }
        .onAppear {
            if recording.id == viewModel.recordings.last?.id {
                Task { await viewModel.loadNextPage() }
            }
        }
    }

    @ViewBuilder
    private func leadingIcon(for recording: TalkieObject) -> some View {
        // Icon dimensions — tunable via Design Toolbar in DEBUG
        #if DEBUG
        let dm = DesignModeManager.shared
        let frameSize: CGFloat = dm.listTuningEnabled ? dm.listIconSize : (isDetailedView ? 44 : 40)
        let radius: CGFloat = dm.listTuningEnabled ? dm.listIconCornerRadius : 8
        let borderWidth: CGFloat = dm.listTuningEnabled ? dm.listIconBorderWidth : 0.5
        let borderOpacity: Double = dm.listTuningEnabled ? dm.listIconBorderOpacity : 0.1
        #else
        let frameSize: CGFloat = isDetailedView ? 44 : 40
        let radius: CGFloat = 8
        let borderWidth: CGFloat = 0.5
        let borderOpacity: Double = 0.1
        #endif
        let iconSize: CGFloat = frameSize * 0.64  // Icon scales with frame

        // All icons get a nice frame background
        ZStack {
            // Frame background
            RoundedRectangle(cornerRadius: radius)
                .fill(iconFrameColor(for: recording))
                .frame(width: frameSize, height: frameSize)

            // Border for definition
            if borderWidth > 0 {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.current.border.opacity(borderOpacity), lineWidth: borderWidth)
                    .frame(width: frameSize, height: frameSize)
            }

            // Icon content
            iconContent(for: recording, size: iconSize)
        }
    }

    private func iconFrameColor(for recording: TalkieObject) -> Color {
        if recording.isDictation {
            return Theme.current.foreground.opacity(0.06)
        } else {
            // Memos get a subtle blue tint
            return Color.blue.opacity(0.08)
        }
    }

    @ViewBuilder
    private func iconContent(for recording: TalkieObject, size: CGFloat) -> some View {
        if recording.isDictation {
            // Dictations: show the active app icon
            if let appContext = recording.appContext, let bundleId = appContext.bundleId {
                AppIconView(bundleIdentifier: bundleId, size: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                // Fallback: waveform icon
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.6, weight: .medium))
                    .foregroundColor(.cyan)
            }
        } else {
            // Memos: show Talkie app icon for the source
            switch recording.source {
            case .iphone:
                Image("TalkieIOS")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            case .watch:
                Image("TalkieWatch")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(Circle()) // Watch icons are circular
            case .mac:
                // Use the Mac app icon or a system icon
                Image(systemName: "desktopcomputer")
                    .font(.system(size: size * 0.7, weight: .medium))
                    .foregroundColor(.blue)
            case .live:
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: size * 0.8))
                    .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Condensed Row Content (Zen mode)

    private func condensedRowContent(recording: TalkieObject, isSelected: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            // Short preview - first ~40 chars
            let preview = recording.text?.prefix(40) ?? recording.displayTitle.prefix(40)
            Text(String(preview) + (preview.count >= 40 ? "…" : ""))
                .font(isSelected ? Theme.current.fontBodyMedium : Theme.current.fontBody)
                .foregroundColor(TalkieTheme.textPrimary)
                .lineLimit(1)

            if recording.wasRefined {
                Image(systemName: "sparkles")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.purple.opacity(0.6))
            }

            Spacer()

            // Duration with clock icon
            if recording.duration > 0 {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "clock")
                        .font(Theme.current.fontXS)
                    Text(formatDuration(recording.duration))
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(TalkieTheme.textMuted)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        } else {
            return "0:\(String(format: "%02d", secs))"
        }
    }

    // MARK: - Detailed Row Content

    private func detailedRowContent(recording: TalkieObject, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(recording.displayTitle)
                    .font(isSelected ? Theme.current.fontBodyMedium : Theme.current.fontBody)
                    .foregroundColor(TalkieTheme.textPrimary)
                    .lineLimit(1)

                if recording.wasPromoted {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.blue.opacity(0.7))
                }

                if recording.wasRefined {
                    Image(systemName: "sparkles")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.purple.opacity(0.7))
                }

                Spacer()

                Text(RelativeTimeFormatter.format(recording.createdAt))
                    .font(Theme.current.fontSM)
                    .foregroundColor(TalkieTheme.textMuted)
            }

            if let preview = recording.text?.prefix(100), !preview.isEmpty {
                Text(String(preview))
                    .font(Theme.current.fontSM)
                    .foregroundColor(TalkieTheme.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var pendingRecordingRow: some View {
        HStack(spacing: 10) {
            let iconSize: CGFloat = isDetailedView ? 28 : 24

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.current.surface2.opacity(0.9))
                    .frame(width: isDetailedView ? 44 : 40, height: isDetailedView ? 44 : 40)
                AppIconView(bundleIdentifier: TalkieEnvironment.current.talkieBundleId, size: iconSize)
                    .saturation(0.9)
                    .opacity(0.72)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Dictation in progress...")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                LiveActivityBars()
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(Theme.current.surface2.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .stroke(Theme.current.borderSubtle.opacity(0.8), lineWidth: 1)
        )
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    @ViewBuilder
    private func recordingContextMenu(for recording: TalkieObject) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(recording.text ?? "", forType: .string)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if let text = recording.text, !text.isEmpty {
            Button {
                NavigationState.shared.navigateToCompose(withText: text, sourceRecordingId: recording.id)
            } label: {
                Label("Open in Compose", systemImage: "square.and.pencil")
            }
        }

        if recording.isMemo && recording.hasAudio {
            Button {
                MemoRecordingController.shared.startContinuingMemo(memoId: recording.id)
            } label: {
                Label("Continue Memo", systemImage: "mic.badge.plus")
            }
        }

        Divider()

        if recording.type == .dictation {
            Button {
                Task { await viewModel.promoteToMemo(recording) }
            } label: {
                Label("Promote to Memo", systemImage: "arrow.up.doc")
            }
        }

        Button {
            let text = recording.text ?? ""
            let picker = NSSharingServicePicker(items: [text])
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
            }
        } label: {
            Label("Share...", systemImage: "square.and.arrow.up")
        }

        if recording.hasAudio {
            Divider()

            Menu {
                Section("Parakeet") {
                    Button("V3 (25 languages, fast)") {
                        retranscribeRecording(recording, modelId: "parakeet:v3")
                    }
                    Button("V2 (English, most accurate)") {
                        retranscribeRecording(recording, modelId: "parakeet:v2")
                    }
                }
                Section("Whisper") {
                    Button("Small (balanced)") {
                        retranscribeRecording(recording, modelId: "whisper:openai_whisper-small")
                    }
                    Button("Large V3 (best quality)") {
                        retranscribeRecording(recording, modelId: "whisper:distil-whisper_distil-large-v3")
                    }
                }
            } label: {
                if retranscribingIDs.contains(recording.id) {
                    Label("Retranscribing...", systemImage: "waveform")
                } else {
                    Label("Retranscribe...", systemImage: "arrow.clockwise")
                }
            }
            .disabled(retranscribingIDs.contains(recording.id))
        }

        Divider()

        Button(role: .destructive) {
            Task {
                await viewModel.deleteRecording(recording)
                selectedRecordingIDs.remove(recording.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        ListFooter(
            displayedCount: viewModel.displayedCount,
            totalCount: viewModel.totalCount,
            selectedCount: selectedRecordingIDs.count
        ) {
            if isCompactMode && selectedRecordingIDs.count == 1 && selectedRecording != nil {
                Button {
                    showInspectorSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 10))
                        Text("Details")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        LoadingState("Loading recordings...")
    }

    private var emptyState: some View {
        Group {
            if searchText.isEmpty && viewModel.filterType == .all {
                ListEmptyState(
                    icon: "mic.slash",
                    title: "No recordings yet",
                    subtitle: "Record your first voice memo or dictation to get started"
                )
            } else if searchText.isEmpty {
                ListEmptyState(
                    icon: viewModel.filterType == .memos ? "doc.text" : "waveform",
                    title: "No \(viewModel.filterType.rawValue.lowercased()) found",
                    subtitle: "Try a different filter"
                )
            } else {
                ListEmptyState(
                    icon: "magnifyingglass",
                    title: "No results for \"\(searchText)\"",
                    subtitle: "Try a different search"
                )
            }
        }
    }

    // MARK: - Inspector

    private var inspectorPane: some View {
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
                ListEmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "No Recording Selected",
                    subtitle: "Click a recording to view details"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            TalkieTheme.surface
                .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TalkieTheme.borderSubtle)
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    private var inspectorSheet: some View {
        NavigationStack {
            Group {
                if let recording = selectedRecording {
                    TalkieView(recording: recording, onDelete: {
                        Task { await viewModel.deleteRecording(recording) }
                        selectedRecordingIDs.remove(recording.id)
                        showInspectorSheet = false
                    })
                        .id(recording.id)
                } else {
                    ListEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "No Recording Selected"
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showInspectorSheet = false }
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 500, minHeight: 500, idealHeight: 600)
    }

    /// Wait for recordings to be available (max 1s, yields instead of busy-looping).
    private func waitForRecordingsIfNeeded() async {
        guard viewModel.recordings.isEmpty || viewModel.isLoading else { return }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            if (!viewModel.recordings.isEmpty && !viewModel.isLoading) || Task.isCancelled { return }
        }
    }

    // MARK: - Navigation Params

    private func consumeNavigationParams(_ params: [String: AnyHashable]) {
        guard !params.isEmpty else { return }

        let selectedID = params["selectedID"] as? UUID
        let filterValue = params["typeFilter"] as? String
        let query = params["searchQuery"] as? String
        let dateFilter = params["dateFilter"] as? Date

        // Only clear params that RecordingsScreen consumes — other params
        // (e.g. initialText for Compose) may be in-flight to another screen.
        for key in ["selectedID", "typeFilter", "searchQuery", "dateFilter"] {
            NavigationState.shared.params.removeValue(forKey: key)
        }

        Task {
            // Apply filter and await reload before setting selection
            if let filterValue, let filter = RecordingTypeFilter(rawValue: filterValue) {
                suppressFilterReload = true
                typeFilter = filter
                await viewModel.toggleSemanticFilter(filter.semanticFilter)
            }

            if let dateFilter {
                await viewModel.setDateFilter(dateFilter)
            }

            if let query {
                searchText = query
                viewModel.filterState.searchQuery = query
                await viewModel.loadWithSemanticFilters()
            }

            // Apply selection AFTER data is loaded
            if let id = selectedID {
                selectedRecordingIDs = [id]
                pendingScrollID = id
            }
        }
    }

    // MARK: - Selection

    private func handleSelection(recording: TalkieObject, event: NSEvent?) {
        let id = recording.id

        if let event = event {
            if event.modifierFlags.contains(.command) {
                if selectedRecordingIDs.contains(id) {
                    selectedRecordingIDs.remove(id)
                } else {
                    selectedRecordingIDs.insert(id)
                }
            } else if event.modifierFlags.contains(.shift), let lastID = selectedRecordingIDs.first {
                if let lastIndex = viewModel.recordings.firstIndex(where: { $0.id == lastID }),
                   let currentIndex = viewModel.recordings.firstIndex(where: { $0.id == id }) {
                    let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
                    for i in range {
                        selectedRecordingIDs.insert(viewModel.recordings[i].id)
                    }
                }
            } else {
                selectedRecordingIDs = [id]
                if isCompactMode { showInspectorSheet = true }
            }
        } else {
            selectedRecordingIDs = [id]
        }
    }

    // MARK: - Keyboard Navigation

    private func setupKeyboardNavigation() {
        keyboardNav.itemCount = viewModel.recordings.count

        keyboardNav.itemAtIndex = { index in
            guard index < viewModel.recordings.count else { return viewModel.recordings.first!.id }
            return viewModel.recordings[index].id
        }

        keyboardNav.onSelect = { ids, _ in
            selectedRecordingIDs = ids
        }

        keyboardNav.onActivate = { id in
            selectedRecordingIDs = [id]
            if isCompactMode { showInspectorSheet = true }
        }

        keyboardNav.allItemIDs = {
            Set(viewModel.recordings.map { $0.id })
        }

        keyboardNav.onFocusRegionChange = { region in
            switch region {
            case .search: isSearchFocused = true
            case .list: isSearchFocused = false
            default: break
            }
        }

        keyboardNav.activate()
    }

    // MARK: - Retranscription

    private func retranscribeRecording(_ recording: TalkieObject, modelId: String) {
        retranscribingIDs.insert(recording.id)

        Task {
            do {
                Log(.transcription).info("Retranscribe: Starting for \(recording.id.uuidString.prefix(8)) with model \(modelId)")

                let newTranscript = try await RecordingRetranscriptionService.shared.retranscribe(
                    recording,
                    modelId: modelId
                )

                Log(.transcription).info("Retranscribe: Got transcript (\(newTranscript.count) chars)")

                await viewModel.loadRecordings()
                Log(.database).info("Retranscribe: Reloaded recordings list")

                _ = await MainActor.run {
                    retranscribingIDs.remove(recording.id)
                }
            } catch {
                Log(.database).error("Retranscribe failed: \(error.localizedDescription)")
                await RecordingRetranscriptionService.shared.persistFailureState(
                    for: recording,
                    errorMessage: error.localizedDescription
                )
                _ = await MainActor.run {
                    retranscribingIDs.remove(recording.id)
                }
            }
        }
    }
}

// MARK: - Collapsed Rail Item

/// A single mini item in the collapsed list rail — type icon dot with title on hover.
private struct CollapsedRailItem: View {
    let recording: TalkieObject
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: recording.type.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundMuted)
                .frame(width: 36, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected
                              ? Theme.current.foreground.opacity(0.12)
                              : isHovered ? Theme.current.foreground.opacity(0.06) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .overlay(alignment: .leading) {
            if isHovered {
                railTooltip
            }
        }
    }

    private var railTooltip: some View {
        Text(recording.displayTitle)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.current.foreground.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.current.surface2)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 2, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.current.foreground.opacity(0.1), lineWidth: 0.5)
            )
            .fixedSize()
            .offset(x: 44)
            .transition(.opacity)
            .zIndex(100)
    }
}

// MARK: - Preview

#Preview {
    RecordingsScreen()
        .frame(width: 1000, height: 700)
}
