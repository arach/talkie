//
//  DataInventoryView.swift
//  Talkie
//
//  Table view showing all memos and their storage status across layers.
//  Gives users visibility into where their data lives.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Data Inventory View

struct DataInventoryView: View {
    @State private var inventoryService = StorageInventoryService.shared
    @State private var selectedFilter: StatusFilter = .all
    @State private var sortOrder: SortOrder = .dateDesc
    @State private var selectedMemo: MemoStorageStatus?
    @State private var showingDetail = false
    @State private var selectedMemos: Set<UUID> = []
    @State private var isMultiSelectMode = false
    @State private var isBatchSyncing = false

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case synced = "Synced"
        case localOnly = "Local Only"
        case pending = "Pending"
        case issues = "Issues"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .synced: return "checkmark.circle"
            case .localOnly: return "iphone"
            case .pending: return "arrow.triangle.2.circlepath"
            case .issues: return "exclamationmark.triangle"
            }
        }
    }

    enum SortOrder: String, CaseIterable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case title = "By Title"
        case status = "By Status"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary header
            summaryHeader

            Divider()
                .padding(.vertical, Spacing.sm)

            // Filter and sort controls
            controlBar

            // Memo list
            if inventoryService.isLoading && inventoryService.memos.isEmpty {
                loadingView
            } else if filteredMemos.isEmpty {
                emptyView
            } else {
                memoList
            }
        }
        .task {
            if inventoryService.memos.isEmpty {
                await inventoryService.refresh()
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let memo = selectedMemo {
                MemoStorageDetailSheet(memo: memo)
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("DATA INVENTORY")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if inventoryService.isLoading {
                    BrailleSpinner(size: 12)
                } else if let lastRefresh = inventoryService.lastRefresh {
                    Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Button(action: {
                    Task { await inventoryService.refresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.current.fontXS)
                }
                .buttonStyle(.plain)
                .disabled(inventoryService.isLoading)
            }

            if let summary = inventoryService.summary {
                HStack(spacing: Spacing.md) {
                    statBadge(
                        value: "\(summary.totalMemos)",
                        label: "Total",
                        color: .blue
                    )
                    statBadge(
                        value: "\(summary.syncedCount)",
                        label: "Synced",
                        color: .green
                    )
                    statBadge(
                        value: "\(summary.localOnlyCount)",
                        label: "Local",
                        color: .orange
                    )
                    if summary.issueCount > 0 {
                        statBadge(
                            value: "\(summary.issueCount)",
                            label: "Issues",
                            color: .red
                        )
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: summary.totalLocalSize, countStyle: .file))
                        .font(.techLabel)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            if let error = inventoryService.lastError {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(Theme.current.fontXS)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.techLabelSmall)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(minWidth: 50)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                // Filter picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(StatusFilter.allCases, id: \.self) { filter in
                        Label(filter.rawValue, systemImage: filter.icon)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Spacer()

                // Multi-select toggle
                Toggle(isOn: $isMultiSelectMode) {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .toggleStyle(.button)
                .onChange(of: isMultiSelectMode) { _, newValue in
                    if !newValue {
                        selectedMemos.removeAll()
                    }
                }

                // Sort picker
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            // Batch action bar (when in multi-select mode)
            if isMultiSelectMode {
                batchActionBar
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Batch Action Bar

    private var batchActionBar: some View {
        HStack(spacing: Spacing.md) {
            // Selection count
            Text("\(selectedMemos.count) selected")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)

            Spacer()

            // Quick select buttons
            Button("Select All") {
                selectedMemos = Set(filteredMemos.map(\.id))
            }
            .buttonStyle(.plain)
            .font(Theme.current.fontXS)

            Button("Clear") {
                selectedMemos.removeAll()
            }
            .buttonStyle(.plain)
            .font(Theme.current.fontXS)
            .disabled(selectedMemos.isEmpty)

            Divider()
                .frame(height: 16)

            // Batch sync actions
            if !selectedMemos.isEmpty {
                let selectedStatuses = filteredMemos.filter { selectedMemos.contains($0.id) }
                let hasDownloadable = selectedStatuses.contains { $0.status == .pendingDownload || $0.status == .audioMissing }
                let hasUploadable = selectedStatuses.contains { $0.status == .localOnly || $0.status == .pendingUpload }

                if hasDownloadable {
                    Button(action: {
                        Task { await batchDownload() }
                    }) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBatchSyncing)
                }

                if hasUploadable {
                    Button(action: {
                        Task { await batchUpload() }
                    }) {
                        Label("Upload", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBatchSyncing)
                }

                if isBatchSyncing {
                    BrailleSpinner(size: 12)
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.xs)
    }

    // MARK: - Batch Actions

    private func batchDownload() async {
        let ids = selectedMemos.filter { id in
            filteredMemos.first { $0.id == id }?.status == .pendingDownload ||
            filteredMemos.first { $0.id == id }?.status == .audioMissing
        }

        guard !ids.isEmpty else { return }

        isBatchSyncing = true
        await inventoryService.syncDownload(ids: ids)
        isBatchSyncing = false
        selectedMemos.removeAll()
    }

    private func batchUpload() async {
        let ids = selectedMemos.filter { id in
            let status = filteredMemos.first { $0.id == id }?.status
            return status == .localOnly || status == .pendingUpload
        }

        guard !ids.isEmpty else { return }

        isBatchSyncing = true
        await inventoryService.syncUpload(ids: ids)
        isBatchSyncing = false
        selectedMemos.removeAll()
    }

    // MARK: - Memo List

    private var memoList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                // Column headers
                columnHeaders

                ForEach(filteredMemos) { memo in
                    memoRow(memo)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("MEMO")
                .frame(width: 200, alignment: .leading)
            Text("CREATED")
                .frame(width: 100, alignment: .leading)
            Text("LOCAL")
                .frame(width: 70, alignment: .center)
            Text("GRDB")
                .frame(width: 50, alignment: .center)
            Text("SYNC")
                .frame(width: 50, alignment: .center)
            Text("CLOUD")
                .frame(width: 50, alignment: .center)
            Text("STATUS")
                .frame(minWidth: 100, alignment: .leading)
            Spacer()
        }
        .font(.techLabelSmall)
        .foregroundColor(Theme.current.foregroundMuted)
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
    }

    private func memoRow(_ memo: MemoStorageStatus) -> some View {
        let isSelected = selectedMemos.contains(memo.id)

        return Button(action: {
            if isMultiSelectMode {
                // Toggle selection
                if isSelected {
                    selectedMemos.remove(memo.id)
                } else {
                    selectedMemos.insert(memo.id)
                }
            } else {
                // Show detail
                selectedMemo = memo
                showingDetail = true
            }
        }) {
            HStack(spacing: 0) {
                // Selection checkbox (in multi-select mode)
                if isMultiSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : Theme.current.foregroundMuted)
                        .font(Theme.current.fontSM)
                        .frame(width: 30)
                }

                // Title
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(memo.title)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(1)
                    if memo.hasTranscription {
                        Text("Has transcript")
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
                .frame(width: isMultiSelectMode ? 170 : 200, alignment: .leading)

                // Created date
                Text(memo.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 100, alignment: .leading)

                // Local audio file
                storageIndicator(
                    present: memo.hasLocalAudioFile,
                    size: memo.localAudioSize
                )
                .frame(width: 70, alignment: .center)

                // GRDB
                checkIndicator(memo.hasLocalDBRecord)
                    .frame(width: 50, alignment: .center)

                // Sync DB (CoreData)
                checkIndicator(memo.hasSyncDBRecord)
                    .frame(width: 50, alignment: .center)

                // CloudKit
                cloudIndicator(memo.hasRemoteRecord, syncedAt: memo.cloudSyncedAt)
                    .frame(width: 50, alignment: .center)

                // Status badge
                statusBadge(memo.status)
                    .frame(minWidth: 100, alignment: .leading)

                Spacer()

                // Inline action button based on status (only in non-select mode)
                if !isMultiSelectMode {
                    inlineActionButton(for: memo)
                        .frame(width: 80)
                }

                // Chevron (only in non-select mode)
                if !isMultiSelectMode {
                    Image(systemName: "chevron.right")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.sm)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.1)
                    : (memo.status.isHealthy ? Theme.current.surface1 : Color.red.opacity(0.05))
            )
            .cornerRadius(CornerRadius.xs)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func storageIndicator(present: Bool, size: Int64?) -> some View {
        if present, let size = size {
            VStack(spacing: 0) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(Theme.current.fontXS)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.system(size: 8))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        } else if present {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(Theme.current.fontSM)
        } else {
            Image(systemName: "xmark.circle")
                .foregroundColor(.red.opacity(0.5))
                .font(Theme.current.fontSM)
        }
    }

    @ViewBuilder
    private func checkIndicator(_ present: Bool) -> some View {
        Image(systemName: present ? "checkmark.circle.fill" : "circle")
            .foregroundColor(present ? .green : Theme.current.foregroundMuted.opacity(0.3))
            .font(Theme.current.fontSM)
    }

    @ViewBuilder
    private func cloudIndicator(_ present: Bool?, syncedAt: Date?) -> some View {
        if let present = present {
            if present {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundColor(.blue)
                    .font(Theme.current.fontSM)
            } else {
                Image(systemName: "icloud.slash")
                    .foregroundColor(.orange)
                    .font(Theme.current.fontSM)
            }
        } else if syncedAt != nil {
            // If we have a sync date, assume it's in cloud
            Image(systemName: "checkmark.icloud.fill")
                .foregroundColor(.blue)
                .font(Theme.current.fontSM)
        } else {
            Image(systemName: "questionmark.circle")
                .foregroundColor(Theme.current.foregroundMuted.opacity(0.5))
                .font(Theme.current.fontSM)
        }
    }

    private func statusBadge(_ status: MemoSyncStatus) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: status.icon)
                .font(.system(size: 10))
            Text(status.displayName)
                .font(.techLabelSmall)
        }
        .foregroundColor(statusColor(status))
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(statusColor(status).opacity(0.1))
        .cornerRadius(CornerRadius.xs)
    }

    private func statusColor(_ status: MemoSyncStatus) -> Color {
        switch status.color {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }

    // MARK: - Inline Action Buttons

    @State private var syncingMemoId: UUID?

    @ViewBuilder
    private func inlineActionButton(for memo: MemoStorageStatus) -> some View {
        let isSyncing = syncingMemoId == memo.id

        switch memo.status {
        case .localOnly, .pendingUpload:
            // Local-only memos can be pushed to cloud
            Button {
                Task { await syncSingleMemo(memo, action: .upload) }
            } label: {
                HStack(spacing: 2) {
                    if isSyncing {
                        BrailleSpinner(size: 10)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 10))
                    }
                    Text("Sync")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)

        case .pendingDownload:
            // Pending download can be fetched
            Button {
                Task { await syncSingleMemo(memo, action: .download) }
            } label: {
                HStack(spacing: 2) {
                    if isSyncing {
                        BrailleSpinner(size: 10)
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 10))
                    }
                    Text("Download")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)

        case .audioMissing:
            // Missing audio can potentially be recovered
            Button {
                Task { await syncSingleMemo(memo, action: .recover) }
            } label: {
                HStack(spacing: 2) {
                    if isSyncing {
                        BrailleSpinner(size: 10)
                    } else {
                        Image(systemName: "arrow.clockwise.icloud")
                            .font(.system(size: 10))
                    }
                    Text("Recover")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)

        case .synced, .orphaned, .unknown:
            // Already synced or no action available
            EmptyView()
        }
    }

    private enum SyncAction {
        case upload, download, recover
    }

    private func syncSingleMemo(_ memo: MemoStorageStatus, action: SyncAction) async {
        syncingMemoId = memo.id

        switch action {
        case .upload:
            await inventoryService.forceUpload(memoId: memo.id)
        case .download:
            await inventoryService.forceDownload(memoId: memo.id)
        case .recover:
            _ = await inventoryService.attemptAudioRecovery(for: memo.id)
        }

        syncingMemoId = nil
    }

    // MARK: - Empty / Loading States

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            BrailleSpinner()
            Text("Scanning storage layers...")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(Theme.current.foregroundMuted)
            Text("No memos found")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
            if selectedFilter != .all {
                Text("Try selecting a different filter")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: - Filtering & Sorting

    private var filteredMemos: [MemoStorageStatus] {
        let filtered: [MemoStorageStatus]

        switch selectedFilter {
        case .all:
            filtered = inventoryService.memos
        case .synced:
            filtered = inventoryService.syncedMemos
        case .localOnly:
            filtered = inventoryService.localOnlyMemos
        case .pending:
            filtered = inventoryService.pendingUploadMemos + inventoryService.pendingDownloadMemos
        case .issues:
            filtered = inventoryService.memosWithIssues
        }

        return sortMemos(filtered)
    }

    private func sortMemos(_ memos: [MemoStorageStatus]) -> [MemoStorageStatus] {
        switch sortOrder {
        case .dateDesc:
            return memos.sorted { $0.createdAt > $1.createdAt }
        case .dateAsc:
            return memos.sorted { $0.createdAt < $1.createdAt }
        case .title:
            return memos.sorted { $0.title.lowercased() < $1.title.lowercased() }
        case .status:
            return memos.sorted(by: MemoStorageStatus.sortByStatusThenDate)
        }
    }
}

// MARK: - Memo Storage Detail Sheet

struct MemoStorageDetailSheet: View {
    let memo: MemoStorageStatus
    @Environment(\.dismiss) private var dismiss
    @State private var isFetchingAudio = false
    @State private var fetchError: String?
    @State private var fetchSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(memo.title)
                            .font(Theme.current.fontHeadline)
                        Text(memo.createdAt.formatted())
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }

                Divider()

                // Memo metadata
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("MEMO INFO")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack {
                        Text("Duration")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Spacer()
                        Text(formatDuration(memo.duration))
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                    }

                    if memo.hasTranscription {
                        HStack(alignment: .top) {
                            Text("Transcript")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Spacer()
                            Text("Available")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(.green)
                        }
                    }

                    if memo.hasLocalAudioFile, let path = memo.localAudioPath {
                        HStack {
                            Text("Audio File")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Spacer()
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    HStack {
                        Text("ID")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Spacer()
                        Text(memo.id.uuidString)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(1)
                    }
                }

                Divider()

                // Storage breakdown
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("STORAGE LAYERS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    storageRow(
                        icon: "folder.fill",
                        label: "Local Audio File",
                        value: memo.hasLocalAudioFile ? "Present" : "Missing",
                        detail: memo.localAudioSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
                        isPresent: memo.hasLocalAudioFile
                    )

                    storageRow(
                        icon: "cylinder.fill",
                        label: "Local Database (GRDB)",
                        value: memo.hasLocalDBRecord ? "Present" : "Missing",
                        detail: memo.hasTranscription ? "Has transcript" : nil,
                        isPresent: memo.hasLocalDBRecord
                    )

                    storageRow(
                        icon: "arrow.triangle.2.circlepath",
                        label: "Sync Database (CoreData)",
                        value: memo.hasSyncDBRecord ? "Present" : "Missing",
                        detail: nil,
                        isPresent: memo.hasSyncDBRecord
                    )

                    storageRow(
                        icon: "icloud.fill",
                        label: "CloudKit",
                        value: cloudStatus,
                        detail: memo.cloudSyncedAt.map { "Last synced: \($0.formatted())" },
                        isPresent: memo.hasRemoteRecord ?? (memo.cloudSyncedAt != nil)
                    )
                }

                Divider()

                // Status
                HStack {
                    Text("Status:")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: memo.status.icon)
                        Text(memo.status.displayName)
                    }
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(memo.status.isHealthy ? .green : .orange)
                }

                Divider()

                // Actions (always visible)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("ACTIONS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Reveal in Finder (when local audio exists)
                    if memo.hasLocalAudioFile, let path = memo.localAudioPath {
                        Button {
                            let audioURL = AudioStorage.audioDirectory.appendingPathComponent(path)
                            if FileManager.default.fileExists(atPath: audioURL.path) {
                                NSWorkspace.shared.selectFile(audioURL.path, inFileViewerRootedAtPath: audioURL.deletingLastPathComponent().path)
                            }
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Fetch from iCloud (when audio missing but memo has duration)
                    if !memo.hasLocalAudioFile && memo.duration > 0 {
                        Button {
                            Task { await fetchAudio() }
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                if isFetchingAudio {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Label("Fetch Audio from iCloud", systemImage: "icloud.and.arrow.down")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isFetchingAudio)
                    }

                    if let error = fetchError {
                        Text(error)
                            .font(Theme.current.fontXS)
                            .foregroundColor(.red)
                    }

                    if fetchSuccess {
                        Label("Audio downloaded", systemImage: "checkmark.circle.fill")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.green)
                    }

                    // Status-specific actions
                    if memo.status == .localOnly || memo.status == .pendingUpload {
                        Button {
                            Task { await StorageInventoryService.shared.forceUpload(memoId: memo.id) }
                        } label: {
                            Label("Force Upload to iCloud", systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    if memo.status == .pendingDownload {
                        Button {
                            Task { await StorageInventoryService.shared.forceDownload(memoId: memo.id) }
                        } label: {
                            Label("Force Download", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Copy ID (always available)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(memo.id.uuidString, forType: .string)
                    } label: {
                        Label("Copy Memo ID", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 560, minHeight: 400, idealHeight: 580, maxHeight: 700)
    }

    private func fetchAudio() async {
        isFetchingAudio = true
        fetchError = nil
        fetchSuccess = false
        do {
            _ = try await SyncClient.shared.fetchAudioForMemo(memoID: memo.id)
            fetchSuccess = true
            NotificationCenter.default.post(name: .syncDataAvailable, object: nil)
        } catch {
            fetchError = error.localizedDescription
        }
        isFetchingAudio = false
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private var cloudStatus: String {
        if let present = memo.hasRemoteRecord {
            return present ? "Present" : "Not synced"
        } else if memo.cloudSyncedAt != nil {
            return "Synced"
        } else {
            return "Unknown"
        }
    }

    private func storageRow(
        icon: String,
        label: String,
        value: String,
        detail: String?,
        isPresent: Bool
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(isPresent ? .green : .red.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(label)
                    .font(Theme.current.fontSM)
                if let detail = detail {
                    Text(detail)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }

            Spacer()

            Text(value)
                .font(Theme.current.fontSMMedium)
                .foregroundColor(isPresent ? .green : .orange)
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.xs)
    }
}

// MARK: - Preview

#Preview("Data Inventory") {
    DataInventoryView()
        .frame(width: 800, height: 600)
}
