//
//  AllMemosView2.swift
//  Talkie
//
//  Rebuilt All Memos view - clean, performant, ViewModel-driven
//  Uses GRDB repository with proper pagination
//

import SwiftUI
import OSLog
import CoreData

// MARK: - All Memos View 2.0

struct AllMemosView2: View {
    @StateObject private var viewModel = MemosViewModel()
    @State private var selectedMemoID: UUID?
    @State private var searchText = ""

    // Debounce search
    @State private var searchTask: Task<Void, Never>?

    // CoreData context for fetching full VoiceMemo objects
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedVoiceMemo: VoiceMemo?

    var body: some View {
        TalkieSection("AllMemosV2") {
            HSplitView {
                // Left: Memos list
                VStack(spacing: 0) {
                    // Header with search and sort controls
                    headerView

                    // Memos table
                    if viewModel.isLoading && viewModel.memos.isEmpty {
                        loadingView
                    } else if viewModel.memos.isEmpty {
                        emptyView
                    } else {
                        memosTable
                    }

                    // Footer with stats
                    footerView
                }
                .frame(minWidth: 280, idealWidth: 350)

                // Right: Memo detail (resizable)
                detailPane
                    .frame(minWidth: 400)
            }
            .onChange(of: searchText) { _, newValue in
                // Debounce search (500ms)
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if !Task.isCancelled {
                        await viewModel.search(query: newValue)
                    }
                }
            }
            .onChange(of: selectedMemoID) { _, newID in
                // Load full VoiceMemo from CoreData when selection changes
                if let memoID = newID {
                    loadVoiceMemo(id: memoID)
                } else {
                    selectedVoiceMemo = nil
                }
            }
        } onLoad: {
            await viewModel.loadMemos()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            // Top row: Search and sort controls
            HStack(spacing: Spacing.md) {
                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(TalkieTheme.textMuted)
                        .font(.system(size: 12))

                    TextField("Search memos...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                    if !searchText.isEmpty {
                        TalkieButtonSync("ClearSearch") {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(TalkieTheme.textMuted)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(TalkieTheme.surfaceCard)
                .cornerRadius(CornerRadius.sm)

                Spacer()

                // Sort controls
                sortControls
            }
            .padding(Spacing.md)

            // Smart filters row
            if viewModel.hasActiveFilters || showFiltersButton {
                smartFiltersView
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
            }
        }
        .background(TalkieTheme.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var showFiltersButton: Bool {
        // Always show filters section for discoverability
        true
    }

    // MARK: - Smart Filters

    private var smartFiltersView: some View {
        HStack(spacing: Spacing.sm) {
            // Filter label
            Text("Filters:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TalkieTheme.textMuted)

            // Short recordings filter
            filterChip(
                filter: .shortRecordings,
                label: "Short",
                icon: "clock"
            )

            // Source filters
            filterChip(
                filter: .source(.iPhone(deviceName: nil)),
                label: "iPhone",
                icon: "iphone"
            )

            filterChip(
                filter: .source(.mac(deviceName: nil)),
                label: "Mac",
                icon: "desktopcomputer"
            )

            filterChip(
                filter: .source(.live),
                label: "Live",
                icon: "waveform.circle.fill"
            )

            // Clear all button (only when filters are active)
            if viewModel.hasActiveFilters {
                TalkieButton("ClearAllFilters") {
                    await viewModel.clearFilters()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(TalkieTheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(TalkieTheme.surfaceCard)
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Active filter count
            if viewModel.hasActiveFilters {
                Text("\(viewModel.displayedCount) filtered")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textMuted)
            }
        }
    }

    private func filterChip(filter: MemoFilter, label: String, icon: String) -> some View {
        TalkieButton("Filter.\(filter.id)") {
            await viewModel.toggleFilter(filter)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(viewModel.isFilterActive(filter) ? .white : filter.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(viewModel.isFilterActive(filter) ? filter.color : filter.color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(filter.color.opacity(viewModel.isFilterActive(filter) ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var sortControls: some View {
        HStack(spacing: 8) {
            Text("Sort:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TalkieTheme.textMuted)

            ForEach([MemoModel.SortField.timestamp, .title, .duration, .workflows], id: \.self) { field in
                sortButton(for: field)
            }
        }
    }

    private func sortButton(for field: MemoModel.SortField) -> some View {
        TalkieButton("Sort.\(field.displayName)") {
            await viewModel.changeSortField(field)
        } label: {
            HStack(spacing: 4) {
                Text(field.displayName)
                    .font(.system(size: 11, weight: .medium))

                if viewModel.sortField == field {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundColor(viewModel.sortField == field ? TalkieTheme.textPrimary : TalkieTheme.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(viewModel.sortField == field ? TalkieTheme.surfaceCard : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Memos Table

    private var memosTable: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.memos) { memo in
                        TalkieButton("LoadMemoDetail.\(memo.displayTitle)") {
                            // Track memo detail load
                            await loadMemoDetail(memo)
                        } label: {
                            MemoRow2(
                                memo: memo,
                                isSelected: selectedMemoID == memo.id
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // Load more when approaching end
                            if memo.id == viewModel.memos.last?.id {
                                Task {
                                    await viewModel.loadNextPage()
                                }
                            }
                        }
                    }

                    // Loading indicator for pagination
                    if viewModel.isLoading && !viewModel.memos.isEmpty {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading more...")
                                .font(.system(size: 11))
                                .foregroundColor(TalkieTheme.textMuted)
                        }
                        .padding(.vertical, Spacing.md)
                    }
                }
            }
        }
    }

    // MARK: - Empty/Loading States

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Loading memos...")
                .font(.system(size: 13))
                .foregroundColor(TalkieTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundColor(TalkieTheme.textMuted)

            if searchText.isEmpty {
                Text("No memos yet")
                    .font(.system(size: 15, weight: .medium))
                Text("Record your first voice memo to get started")
                    .font(.system(size: 13))
                    .foregroundColor(TalkieTheme.textMuted)
            } else {
                Text("No results for \"\(searchText)\"")
                    .font(.system(size: 15, weight: .medium))
                Text("Try a different search term")
                    .font(.system(size: 13))
                    .foregroundColor(TalkieTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("\(viewModel.displayedCount) of \(viewModel.totalCount) memos")
                .font(.system(size: 11))
                .foregroundColor(TalkieTheme.textMuted)

            Spacer()

            if viewModel.hasMorePages {
                TalkieButton("LoadMore") {
                    await viewModel.loadNextPage()
                } label: {
                    Text("Load More")
                }
                .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(Spacing.sm)
        .background(TalkieTheme.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let voiceMemo = selectedVoiceMemo {
            MemoDetailView(memo: voiceMemo)
                .id(voiceMemo.id)  // Stable identity for SwiftUI diffing
        } else {
            // Empty state
            VStack(spacing: Spacing.md) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundColor(TalkieTheme.textMuted.opacity(0.4))

                Text("SELECT A MEMO")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TalkieTheme.textMuted)

                Text("Click a memo to view details")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textMuted.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TalkieTheme.surface)
        }
    }

    // MARK: - Helpers

    /// Load memo detail with full performance tracking
    private func loadMemoDetail(_ memo: MemoModel) async {
        // Set selection (this triggers loadVoiceMemo via onChange)
        selectedMemoID = memo.id
    }

    /// Fetch VoiceMemo from CoreData
    private func loadVoiceMemo(id: UUID) {
        let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            let results = try viewContext.fetch(fetchRequest)
            selectedVoiceMemo = results.first
        } catch {
            let logger = Logger(subsystem: "jdi.talkie.core", category: "AllMemosV2")
            logger.error("Failed to fetch VoiceMemo: \(error.localizedDescription)")
            selectedVoiceMemo = nil
        }
    }
}

// MARK: - Memo Row 2.0 (Lightweight, Only Observes Displayed Properties)

struct MemoRow2: View {
    let memo: MemoModel
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Selection indicator
            Circle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .strokeBorder(TalkieTheme.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(memo.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)
                    .lineLimit(1)

                // Metadata
                HStack(spacing: 8) {
                    // Timestamp
                    Text(MemosViewModel.timestampFormatter.string(from: memo.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textMuted)

                    Text("•")
                        .foregroundColor(TalkieTheme.textMuted)

                    // Duration
                    HStack(spacing: 3) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                        Text(MemosViewModel.formatDuration(memo.duration))
                            .font(.system(size: 11))
                    }
                    .foregroundColor(TalkieTheme.textMuted)

                    // Source badge
                    if memo.source != .unknown {
                        MemoSourceBadgeV2(source: memo.source, showLabel: false, size: .small)
                    }
                }
            }

            Spacer()

            // Word count
            if memo.wordCount > 0 {
                Text("\(memo.wordCount) words")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textMuted)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())  // Make entire row clickable
        .background(
            ZStack {
                // Selected state
                if isSelected {
                    TalkieTheme.surfaceCard.opacity(0.5)
                }
                // Hover state
                if isHovering && !isSelected {
                    TalkieTheme.surfaceCard.opacity(0.3)
                }
            }
        )
        .overlay(
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Sort Field Display Name

extension MemoModel.SortField {
    var displayName: String {
        switch self {
        case .timestamp: return "Date"
        case .title: return "Title"
        case .duration: return "Duration"
        case .workflows: return "Workflows"
        }
    }
}

// MARK: - MemoSourceBadge (for new MemoModel.Source)

struct MemoSourceBadgeV2: View {
    let source: MemoModel.Source
    var showLabel: Bool = true
    var size: BadgeSize = .small

    enum BadgeSize {
        case small, medium

        var iconSize: CGFloat {
            switch self {
            case .small: return 9
            case .medium: return 11
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 9
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            }
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: source.icon)
                .font(.system(size: size.iconSize))

            if showLabel {
                Text(source.displayName)
                    .font(.system(size: size.fontSize, weight: .medium, design: .monospaced))
            }
        }
        .foregroundColor(source.color)
        .padding(.horizontal, size.padding)
        .padding(.vertical, 2)
        .background(source.color.opacity(0.12))
        .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview {
    AllMemosView2()
        .frame(width: 800, height: 600)
}
