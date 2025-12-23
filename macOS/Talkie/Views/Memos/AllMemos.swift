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

    // Column widths (resizable)
    @State private var durationColumnWidth: CGFloat = 70
    @State private var dateColumnWidth: CGFloat = 90
    @State private var dragStartWidth: CGFloat = 0


    // View mode: auto switches based on count, or user can force
    enum ViewMode: String, CaseIterable {
        case auto = "Auto"
        case condensed = "Condensed"
        case expanded = "Expanded"
    }
    @State private var viewMode: ViewMode = .auto

    // Threshold for auto-switching from preview to table
    private let previewThreshold = 10

    private var usePreviewMode: Bool {
        switch viewMode {
        case .auto: return viewModel.totalCount < previewThreshold
        case .condensed: return false
        case .expanded: return true
        }
    }

    private var selectedMemoID: UUID? {
        selectedMemoIDs.count == 1 ? selectedMemoIDs.first : nil
    }

    private var allSelected: Bool {
        !viewModel.memos.isEmpty && selectedMemoIDs.count == viewModel.memos.count
    }

    private var someSelected: Bool {
        !selectedMemoIDs.isEmpty && selectedMemoIDs.count < viewModel.memos.count
    }

    var body: some View {
        TalkieSection("AllMemos") {
            HSplitView {
                listPane
                    .frame(minWidth: 350, idealWidth: 500)

                inspectorContent
                    .frame(minWidth: 300)
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

    // MARK: - List Pane

    @ViewBuilder
    private var listPane: some View {
        VStack(spacing: 0) {
            headerView

            if viewModel.isLoading && viewModel.memos.isEmpty {
                loadingView
            } else if viewModel.memos.isEmpty {
                emptyView
            } else {
                memosTable
            }

            footerView
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
        ScrollViewReader { proxy in
            ScrollView {
                if usePreviewMode {
                    // Preview mode: card-style layout with spacing
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.memos) { memo in
                            MemoRowPreview(
                                memo: memo,
                                isSelected: selectedMemoIDs.contains(memo.id),
                                onSelect: { event in
                                    handleSelection(memo: memo, event: event)
                                }
                            )
                            .id(memo.id)
                            .onAppear {
                                if memo.id == viewModel.memos.last?.id {
                                    Task { await viewModel.loadNextPage() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                } else {
                    // Table mode: compact rows with header
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(viewModel.memos.enumerated()), id: \.element.id) { index, memo in
                                MemoRowEnhanced(
                                    memo: memo,
                                    isSelected: selectedMemoIDs.contains(memo.id),
                                    isMultiSelected: selectedMemoIDs.count > 1,
                                    onSelect: { event in
                                        handleSelection(memo: memo, event: event)
                                    },
                                    durationWidth: durationColumnWidth,
                                    dateWidth: dateColumnWidth,
                                    isEvenRow: index.isMultiple(of: 2)
                                )
                                .id(memo.id)
                                .onAppear {
                                    if memo.id == viewModel.memos.last?.id {
                                        Task { await viewModel.loadNextPage() }
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
                        } header: {
                            tableHeader
                        }
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            // Spacer for accent bar alignment
            Color.clear.frame(width: 3)

            // Select all checkbox
            Button {
                toggleSelectAll()
            } label: {
                Image(systemName: selectAllIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(selectedMemoIDs.isEmpty ? Color.white.opacity(0.2) : .accentColor)
                    .frame(width: 28)
            }
            .buttonStyle(.plain)

            // Title (sortable)
            sortableColumnHeader(title: "TITLE", field: .title, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Duration (sortable, resizable)
            sortableColumnHeader(title: "DURATION", field: .duration, alignment: .trailing)
                .frame(width: durationColumnWidth, alignment: .trailing)
                .overlay(
                    columnResizeHandle(width: $durationColumnWidth),
                    alignment: .trailing
                )

            // Date (sortable, resizable)
            sortableColumnHeader(title: "DATE", field: .timestamp, alignment: .trailing)
                .frame(width: dateColumnWidth, alignment: .trailing)
                .padding(.trailing, 4)
                .overlay(
                    columnResizeHandle(width: $dateColumnWidth, minWidth: 60),
                    alignment: .trailing
                )
        }
        .padding(.vertical, 8)
        .background(TalkieTheme.surface)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var selectAllIcon: String {
        if allSelected {
            return "checkmark.circle.fill"
        } else if someSelected {
            return "minus.circle.fill"
        } else {
            return "circle"
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedMemoIDs.removeAll()
        } else {
            selectedMemoIDs = Set(viewModel.memos.map { $0.id })
        }
    }

    private func sortableColumnHeader(title: String, field: MemoModel.SortField, alignment: Alignment) -> some View {
        Button {
            Task { await viewModel.changeSortField(field) }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                if viewModel.sortField == field {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .foregroundColor(viewModel.sortField == field ? Color.white.opacity(0.9) : Color.white.opacity(0.4))
        }
        .buttonStyle(.plain)
    }

    private func columnResizeHandle(width: Binding<CGFloat>, minWidth: CGFloat = 50) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartWidth == 0 {
                            dragStartWidth = width.wrappedValue
                        }
                        width.wrappedValue = max(minWidth, dragStartWidth + value.translation.width)
                    }
                    .onEnded { _ in
                        dragStartWidth = 0
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
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
        HStack(spacing: Spacing.md) {
            // Left: Count info (always visible)
            HStack(spacing: 4) {
                if selectedMemoIDs.count > 1 {
                    // Selection mode: show both selection and total
                    Text("\(selectedMemoIDs.count) selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)

                    Text("·")
                        .foregroundColor(TalkieTheme.textMuted)
                }

                Text("\(viewModel.displayedCount) of \(viewModel.totalCount)")
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textMuted)
            }

            // Center: Load more (if applicable)
            if viewModel.hasMorePages && selectedMemoIDs.count <= 1 {
                Spacer()

                TalkieButton("LoadMore") {
                    await viewModel.loadNextPage()
                } label: {
                    HStack(spacing: 4) {
                        Text("Load more")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()
            } else {
                Spacer()
            }

            // View mode toggle (only after graduating to 10+ memos)
            if viewModel.totalCount >= previewThreshold && selectedMemoIDs.count <= 1 {
                viewModeToggle
            }

            // Bulk actions when multi-selected
            if selectedMemoIDs.count > 1 {
                HStack(spacing: 8) {
                    Button {
                        // Export selected
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 10))
                            Text("Export")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(TalkieTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TalkieTheme.surfaceCard)
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedMemoIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TalkieTheme.textMuted)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Clear selection")
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(TalkieTheme.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Image(systemName: iconForMode(mode))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(viewMode == mode ? TalkieTheme.textPrimary : TalkieTheme.textMuted)
                        .frame(width: 24, height: 20)
                        .background(viewMode == mode ? Color.white.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(mode.rawValue)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }

    private func iconForMode(_ mode: ViewMode) -> String {
        switch mode {
        case .auto: return "sparkles"
        case .condensed: return "list.bullet"
        case .expanded: return "rectangle.grid.1x2"
        }
    }

    // MARK: - Inspector Content

    @ViewBuilder
    private var inspectorContent: some View {
        // Content
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
                // Empty state - tasteful, minimal
                VStack(spacing: 16) {
                    // Subtle icon
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    VStack(spacing: 4) {
                        Text("No Selection")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(TalkieTheme.textSecondary)

                        Text("Select a memo to view details")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textMuted)
                    }

                    // Keyboard hint
                    HStack(spacing: 4) {
                        Text("⌘I")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(3)

                        Text("to toggle inspector")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(TalkieTheme.textMuted.opacity(0.6))
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Preview Memo Row (Rich view for early users)

struct MemoRowPreview: View {
    let memo: MemoModel
    let isSelected: Bool
    let onSelect: (NSEvent?) -> Void

    @State private var isHovering = false

    private static let selectedBg = Color.accentColor.opacity(0.12)
    private static let hoverBg = Color.white.opacity(0.03)
    private static let cardBg = Color.white.opacity(0.02)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Title + Duration
            HStack(alignment: .center) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : Color.white.opacity(0.2))

                Text(memo.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .primary : TalkieTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Duration pill
                Text(formatDuration(memo.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TalkieTheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
            }

            // Transcript preview
            if let preview = memo.transcriptPreview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .lineLimit(2)
                    .padding(.leading, 22) // Align with title (past checkbox)
            }

            // Bottom row: Date + Source
            HStack(spacing: 12) {
                Text(RelativeTimeFormatter.format(memo.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textMuted)

                if memo.source != .unknown {
                    HStack(spacing: 4) {
                        Image(systemName: memo.source.icon)
                            .font(.system(size: 9))
                        Text(memo.source.displayName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(memo.source.color.opacity(0.8))
                }

                Spacer()
            }
            .padding(.leading, 22)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Self.selectedBg : (isHovering ? Self.hoverBg : Self.cardBg))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .buttonStyle(.plain)
        .onTapGesture { onSelect(NSApp.currentEvent) }
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let secondsStr = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsStr)"
    }
}

// MARK: - Enhanced Memo Row (Better Visual Hierarchy)

struct MemoRowEnhanced: View {
    let memo: MemoModel
    let isSelected: Bool
    let isMultiSelected: Bool
    let onSelect: (NSEvent?) -> Void
    var durationWidth: CGFloat = 70
    var dateWidth: CGFloat = 90
    var isEvenRow: Bool = false

    @State private var isHovering = false

    // Pre-computed colors - no runtime opacity math
    private static let selectedBg = Color.accentColor.opacity(0.15)
    private static let hoverBg = Color.white.opacity(0.03)
    private static let evenRowBg = Color.white.opacity(0.015)
    private static let accentBar = Color.accentColor

    var body: some View {
        Button {
            onSelect(NSApp.currentEvent)
        } label: {
            HStack(spacing: 0) {
                // Left accent bar for selected state
                Rectangle()
                    .fill(isSelected ? Self.accentBar : Color.clear)
                    .frame(width: 3)

                // Checkbox (always visible - no layout shifts)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : Color.white.opacity(0.2))
                    .frame(width: 28)

                // Title - stronger typography
                Text(memo.displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : TalkieTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Duration - monospace for alignment
                Text(formatDuration(memo.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TalkieTheme.textMuted)
                    .frame(width: durationWidth, alignment: .trailing)

                // Date
                Text(RelativeTimeFormatter.format(memo.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textMuted)
                    .frame(width: dateWidth, alignment: .trailing)
                    .padding(.trailing, 4)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Self.selectedBg }
        if isHovering { return Self.hoverBg }
        if isEvenRow { return Self.evenRowBg }
        return .clear
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let secondsStr = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsStr)"
    }
}

// MARK: - Relative Time Formatter

enum RelativeTimeFormatter {
    static func format(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let interval = now.timeIntervalSince(date)

        // Today: show relative time
        if calendar.isDateInToday(date) {
            if interval < 3600 {
                let minutes = max(1, Int(interval / 60))
                return "\(minutes)m ago"
            } else {
                let hours = Int(interval / 3600)
                return "\(hours)h ago"
            }
        }

        // This week: show short day name
        if interval < 604800 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"  // Mon, Tue, Wed
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
