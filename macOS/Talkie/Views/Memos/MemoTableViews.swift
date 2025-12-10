//
//  MemoTableViews.swift
//  Talkie macOS
//
//  Extracted from NavigationView.swift
//

import SwiftUI
import CoreData
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Memo Table Sort Field

enum MemoSortField: String, CaseIterable {
    case timestamp = "TIMESTAMP"
    case title = "TITLE"
    case duration = "DURATION"
    case workflows = "WORKFLOWS"
}

// MARK: - Memo Table Full View (with Inspector Panel)

struct MemoTableFullView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var settings = SettingsManager.shared

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var allMemos: FetchedResults<VoiceMemo>

    // Selection & Inspector state
    @State private var selectedMemo: VoiceMemo?
    @State private var showInspector: Bool = false

    // Sorting state
    @State private var sortField: MemoSortField = .timestamp
    @State private var sortAscending: Bool = false

    // Column widths (resizable)
    @State private var timestampWidth: CGFloat = 150
    @State private var titleWidth: CGFloat = 280
    @State private var durationWidth: CGFloat = 80
    @State private var workflowsWidth: CGFloat = 100

    // Inspector panel width (resizable)
    @State private var inspectorWidth: CGFloat = 420

    // Sorted memos based on current sort state
    private var sortedMemos: [VoiceMemo] {
        let memos = Array(allMemos)
        return memos.sorted { a, b in
            let result: Bool
            switch sortField {
            case .timestamp:
                result = (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            case .title:
                result = (a.title ?? "") < (b.title ?? "")
            case .duration:
                result = a.duration > b.duration
            case .workflows:
                result = (a.workflowRuns?.count ?? 0) > (b.workflowRuns?.count ?? 0)
            }
            return sortAscending ? !result : result
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Main table content (full width, always visible)
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 4) {
                    Text("All Memos")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(SettingsManager.shared.tacticalForeground)
                        .textCase(SettingsManager.shared.uiTextCase)

                    Text("\(allMemos.count)")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)

                    Spacer()

                    // Inspector toggle button
                    if selectedMemo != nil {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showInspector.toggle() } }) {
                            Image(systemName: showInspector ? "sidebar.right" : "sidebar.right")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(showInspector ? .blue : SettingsManager.shared.tacticalForegroundSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(showInspector ? "Hide Details" : "Show Details")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SettingsManager.shared.tacticalBackgroundSecondary)

                Divider()

                if allMemos.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "waveform.slash")
                            .font(SettingsManager.shared.fontDisplay)
                            .foregroundColor(.secondary.opacity(0.3))

                        Text("NO MEMOS YET")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text("Record your first voice memo on iOS")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Table header with sortable columns
                    MemoTableHeader(
                        sortField: $sortField,
                        sortAscending: $sortAscending,
                        timestampWidth: $timestampWidth,
                        titleWidth: $titleWidth,
                        durationWidth: $durationWidth,
                        workflowsWidth: $workflowsWidth
                    )

                    Divider()

                    // Table rows
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedMemos, id: \.id) { memo in
                                MemoTableRow(
                                    memo: memo,
                                    isSelected: selectedMemo?.id == memo.id,
                                    onSelect: {
                                        selectedMemo = memo
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showInspector = true
                                        }
                                    },
                                    timestampWidth: timestampWidth,
                                    titleWidth: titleWidth,
                                    durationWidth: durationWidth,
                                    workflowsWidth: workflowsWidth
                                )

                                Rectangle()
                                    .fill(SettingsManager.shared.tacticalDivider.opacity(0.25))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .background(SettingsManager.shared.tacticalBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsManager.shared.tacticalBackground)

            // Inspector Panel (overlays from right, anchored to right edge)
            if showInspector, let memo = selectedMemo {
                HStack(spacing: 0) {
                    // Resizable divider (on left side of inspector)
                    InspectorResizeHandle(width: $inspectorWidth)

                    MemoInspectorPanel(
                        memo: memo,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showInspector = false
                            }
                        }
                    )
                    .frame(width: inspectorWidth)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: -1, y: 0)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onKeyPress(.escape) {
            if showInspector {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInspector = false
                }
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - Memo Table Header

struct MemoTableHeader: View {
    @Binding var sortField: MemoSortField
    @Binding var sortAscending: Bool
    @Binding var timestampWidth: CGFloat
    @Binding var titleWidth: CGFloat
    @Binding var durationWidth: CGFloat
    @Binding var workflowsWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            MemoSortableColumnHeader(
                title: "TIMESTAMP",
                field: .timestamp,
                currentSort: $sortField,
                ascending: $sortAscending,
                width: timestampWidth
            )
            ColumnResizer(width: $timestampWidth, minWidth: 100, maxWidth: 200)

            MemoSortableColumnHeader(
                title: "TITLE",
                field: .title,
                currentSort: $sortField,
                ascending: $sortAscending,
                width: titleWidth
            )
            ColumnResizer(width: $titleWidth, minWidth: 120, maxWidth: 400)

            MemoSortableColumnHeader(
                title: "DURATION",
                field: .duration,
                currentSort: $sortField,
                ascending: $sortAscending,
                width: durationWidth,
                alignment: .trailing
            )
            ColumnResizer(width: $durationWidth, minWidth: 60, maxWidth: 120)

            MemoSortableColumnHeader(
                title: "WORKFLOWS",
                field: .workflows,
                currentSort: $sortField,
                ascending: $sortAscending,
                width: workflowsWidth,
                alignment: .trailing
            )

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 26)
        .background(SettingsManager.shared.tacticalBackgroundSecondary)
    }
}

// MARK: - Memo Sortable Column Header

struct MemoSortableColumnHeader: View {
    let title: String
    let field: MemoSortField
    @Binding var currentSort: MemoSortField
    @Binding var ascending: Bool
    let width: CGFloat
    var alignment: Alignment = .leading

    @ObservedObject private var settings = SettingsManager.shared
    @State private var isHovering = false

    private var isSorted: Bool { currentSort == field }

    var body: some View {
        Button(action: {
            if currentSort == field {
                ascending.toggle()
            } else {
                currentSort = field
                ascending = false
            }
        }) {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer() }

                Text(title)
                    .font(SettingsManager.shared.fontSMMedium)
                    .foregroundColor(isSorted ? .primary : .secondary)

                if isSorted {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(SettingsManager.shared.fontXSBold)
                        .foregroundColor(.blue)
                }

                if alignment == .leading { Spacer() }
            }
            .frame(width: width, alignment: alignment)
            .padding(.vertical, 2)
            .background(isHovering ? settings.surfaceHover : Color.clear)
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Memo Table Row

struct MemoTableRow: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject private var settings = SettingsManager.shared
    let isSelected: Bool
    let onSelect: () -> Void
    let timestampWidth: CGFloat
    let titleWidth: CGFloat
    let durationWidth: CGFloat
    let workflowsWidth: CGFloat

    @State private var isHovering = false

    private var workflowCount: Int {
        memo.workflowRuns?.count ?? 0
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // Timestamp
                Text(formatTimestamp(memo.createdAt ?? Date()))
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)
                    .frame(width: timestampWidth, alignment: .leading)

                // Title
                Text(memo.title ?? "Untitled")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(SettingsManager.shared.tacticalForeground)
                    .lineLimit(1)
                    .frame(width: titleWidth, alignment: .leading)

                // Duration
                Text(formatDuration(memo.duration))
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)
                    .frame(width: durationWidth, alignment: .trailing)

                // Workflow count
                HStack(spacing: 3) {
                    if workflowCount > 0 {
                        Image(systemName: "wand.and.stars")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.blue.opacity(0.8))
                        Text("\(workflowCount)")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.blue)
                    } else {
                        Text("—")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(SettingsManager.shared.tacticalForegroundMuted.opacity(0.5))
                    }
                }
                .frame(width: workflowsWidth, alignment: .trailing)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color.blue.opacity(0.15) :
                    (isHovering ? SettingsManager.shared.tacticalBackgroundTertiary : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"  // 24hr for tactical look
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Memo Inspector Panel

struct MemoInspectorPanel: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject private var settings = SettingsManager.shared
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Minimal inspector toolbar
            HStack {
                Text("DETAILS")
                    .font(SettingsManager.shared.fontXSBold)
                    .tracking(1)
                    .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)

                Spacer()

                CloseButton(action: onClose)
                    .help("Close inspector (Esc)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SettingsManager.shared.tacticalBackgroundSecondary)

            Rectangle()
                .fill(SettingsManager.shared.tacticalDivider)
                .frame(height: 0.5)

            // Embed MemoDetailView without redundant header
            MemoDetailView(memo: memo, showHeader: false)
        }
        .background(SettingsManager.shared.tacticalBackground)
    }
}

// MARK: - Close Button

/// Reusable close button with extended hit target and hover highlight
struct CloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Extended hit area to the left (invisible)
                Color.clear
                    .frame(width: 16)

                // Visual button area with highlight
                Image(systemName: "xmark")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(isHovering
                        ? SettingsManager.shared.tacticalForeground
                        : SettingsManager.shared.tacticalForegroundSecondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHovering
                                ? SettingsManager.shared.tacticalForegroundMuted.opacity(0.15)
                                : Color.clear)
                    )
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}
