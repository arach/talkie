//
//  AllMemos.swift
//  Talkie
//
//  All Memos view - clean, performant, ViewModel-driven
//  Uses GRDB repository with proper pagination
//

import SwiftUI
import OSLog
import CoreData

// MARK: - All Memos View

struct AllMemos: View {
    @State private var viewModel = MemosViewModel()
    @State private var selectedMemoIDs: Set<UUID> = []
    @State private var searchText = ""

    // Debounce search
    @State private var searchTask: Task<Void, Never>?

    // CoreData context for fetching full VoiceMemo objects
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedVoiceMemo: VoiceMemo?

    // For keyboard/click selection
    @State private var lastClickedID: UUID?

    private var selectedMemoID: UUID? {
        selectedMemoIDs.count == 1 ? selectedMemoIDs.first : nil
    }

    var body: some View {
        TalkieSection("AllMemos") {
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
                .frame(minWidth: 400, idealWidth: 500)

                // Right: Memo detail (resizable)
                detailPane
                    .frame(minWidth: 350)
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
            .onChange(of: selectedMemoIDs) { _, newIDs in
                // Load full VoiceMemo from CoreData when single selection changes
                if newIDs.count == 1, let memoID = newIDs.first {
                    loadVoiceMemo(id: memoID)
                } else {
                    selectedVoiceMemo = nil
                }
            }
        } onLoad: {
            await viewModel.loadMemos()
        }
    }

    // MARK: - Selection Handling

    private func handleSelection(memo: MemoModel, event: NSEvent?) {
        let id = memo.id

        if let event = event {
            if event.modifierFlags.contains(.command) {
                // Cmd+click: Toggle selection
                if selectedMemoIDs.contains(id) {
                    selectedMemoIDs.remove(id)
                } else {
                    selectedMemoIDs.insert(id)
                }
            } else if event.modifierFlags.contains(.shift), let lastID = lastClickedID {
                // Shift+click: Range selection
                if let lastIndex = viewModel.memos.firstIndex(where: { $0.id == lastID }),
                   let currentIndex = viewModel.memos.firstIndex(where: { $0.id == id }) {
                    let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
                    for i in range {
                        selectedMemoIDs.insert(viewModel.memos[i].id)
                    }
                }
            } else {
                // Regular click: Single selection
                selectedMemoIDs = [id]
            }
        } else {
            // No event (keyboard nav): Single selection
            selectedMemoIDs = [id]
        }

        lastClickedID = id
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
        VStack(spacing: 0) {
            tableHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.memos) { memo in
                            MemoRowEnhanced(
                                memo: memo,
                                isSelected: selectedMemoIDs.contains(memo.id),
                                isMultiSelected: selectedMemoIDs.count > 1,
                                onSelect: { event in
                                    handleSelection(memo: memo, event: event)
                                }
                            )
                            .id(memo.id)
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
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            // Checkbox column spacer
            Color.clear.frame(width: 28)

            // Title
            Button {
                Task { await viewModel.changeSortField(.title) }
            } label: {
                HStack(spacing: 4) {
                    Text("Title")
                        .font(.system(size: 11, weight: .semibold))
                    if viewModel.sortField == .title {
                        Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundColor(viewModel.sortField == .title ? TalkieTheme.textPrimary : TalkieTheme.textMuted)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Duration
            Button {
                Task { await viewModel.changeSortField(.duration) }
            } label: {
                HStack(spacing: 4) {
                    Text("Duration")
                        .font(.system(size: 11, weight: .semibold))
                    if viewModel.sortField == .duration {
                        Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundColor(viewModel.sortField == .duration ? TalkieTheme.textPrimary : TalkieTheme.textMuted)
            }
            .buttonStyle(.plain)
            .frame(width: 56, alignment: .trailing)

            // Date
            Button {
                Task { await viewModel.changeSortField(.timestamp) }
            } label: {
                HStack(spacing: 4) {
                    Text("Date")
                        .font(.system(size: 11, weight: .semibold))
                    if viewModel.sortField == .timestamp {
                        Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundColor(viewModel.sortField == .timestamp ? TalkieTheme.textPrimary : TalkieTheme.textMuted)
            }
            .buttonStyle(.plain)
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(TalkieTheme.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
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
            // Selection count or total count
            if selectedMemoIDs.count > 1 {
                Text("\(selectedMemoIDs.count) selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
            } else {
                Text("\(viewModel.displayedCount) of \(viewModel.totalCount) memos")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textMuted)
            }

            Spacer()

            // Bulk actions when multi-selected
            if selectedMemoIDs.count > 1 {
                HStack(spacing: 12) {
                    Button {
                        // Export selected
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(TalkieTheme.textMuted)

                    Button {
                        selectedMemoIDs.removeAll()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(TalkieTheme.textMuted)
                }
            } else if viewModel.hasMorePages {
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
        if selectedMemoIDs.count > 1 {
            // Multi-select state
            VStack(spacing: Spacing.md) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor.opacity(0.6))

                Text("\(selectedMemoIDs.count) MEMOS SELECTED")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TalkieTheme.textSecondary)

                Text("Cmd+click to toggle, Shift+click for range")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textMuted)

                // Bulk action buttons
                HStack(spacing: 12) {
                    Button {
                        // Export all selected
                    } label: {
                        Label("Export All", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        selectedMemoIDs.removeAll()
                    } label: {
                        Label("Clear Selection", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, Spacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TalkieTheme.surface)
        } else if let voiceMemo = selectedVoiceMemo {
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

    /// Fetch VoiceMemo from CoreData
    private func loadVoiceMemo(id: UUID) {
        let fetchRequest: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            let results = try viewContext.fetch(fetchRequest)
            selectedVoiceMemo = results.first
        } catch {
            let logger = Logger(subsystem: "jdi.talkie.core", category: "AllMemos")
            logger.error("Failed to fetch VoiceMemo: \(error.localizedDescription)")
            selectedVoiceMemo = nil
        }
    }
}

// MARK: - Enhanced Memo Row (Better Visual Hierarchy)

struct MemoRowEnhanced: View {
    let memo: MemoModel
    let isSelected: Bool
    let isMultiSelected: Bool
    let onSelect: (NSEvent?) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Selection checkbox (standard placement)
            if isMultiSelected || isHovering {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : TalkieTheme.textMuted.opacity(0.4))
                    .frame(width: 28)
            } else {
                // Reserve space for alignment consistency
                Color.clear
                    .frame(width: 28)
            }

            // Title (main content, flexible width)
            Text(memo.displayTitle)
                .font(.system(size: 13))
                .foregroundColor(TalkieTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            // Duration (plain text, right-aligned)
            Text(formatDuration(memo.duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(TalkieTheme.textMuted)
                .frame(width: 56, alignment: .trailing)

            // Date (plain text, right-aligned)
            Text(RelativeTimeFormatter.format(memo.createdAt))
                .font(.system(size: 12))
                .foregroundColor(TalkieTheme.textMuted)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(
            Rectangle()
                .fill(TalkieTheme.border.opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect(NSApp.currentEvent)
        }
    }

    // MARK: - Helpers

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.12)
            } else if isHovering {
                TalkieTheme.surfaceCard.opacity(0.5)
            } else {
                Color.clear
            }
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Relative Time Formatter

enum RelativeTimeFormatter {
    static func format(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        // Less than 1 minute
        if interval < 60 {
            return "Just now"
        }

        // Less than 1 hour
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        }

        // Less than 24 hours
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }

        // Yesterday
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday, \(formatter.string(from: date))"
        }

        // This week (within 7 days)
        if interval < 604800 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"  // Day name
            return formatter.string(from: date)
        }

        // This year
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }

        // Different year
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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
    AllMemos()
        .frame(width: 900, height: 600)
}

// MARK: - Backwards Compatibility Alias
typealias AllMemosView2 = AllMemos
