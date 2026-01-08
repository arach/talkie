//
//  SyncHistoryView.swift
//  Talkie
//
//  Simple CloudKit sync history viewer
//  Shows recent sync operations with timestamps and status
//

import SwiftUI
import GRDB

// MARK: - Sync Event Models

struct SyncRecordDetail: Identifiable, Codable {
    let id: String // Record ID
    let recordType: String // e.g., "VoiceMemo" (CD_ prefix stripped)
    let title: String // From CD_title field
    let modificationDate: Date?
    let changeType: ChangeType

    enum ChangeType: String, Codable {
        case added
        case modified
        case deleted

        var icon: String {
            switch self {
            case .added: return "plus.circle"
            case .modified: return "pencil.circle"
            case .deleted: return "minus.circle"
            }
        }

        var color: Color {
            switch self {
            case .added: return .green
            case .modified: return .blue
            case .deleted: return .red
            }
        }
    }
}

struct SyncEvent: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let status: SyncStatus
    let itemCount: Int
    let duration: TimeInterval?
    let errorMessage: String?
    let details: [SyncRecordDetail] // Drill-down details

    init(id: String = UUID().uuidString, timestamp: Date, status: SyncStatus, itemCount: Int, duration: TimeInterval?, errorMessage: String?, details: [SyncRecordDetail] = []) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.itemCount = itemCount
        self.duration = duration
        self.errorMessage = errorMessage
        self.details = details
    }

    enum SyncStatus: String, Codable {
        case success
        case failed
        case partial

        var color: Color {
            switch self {
            case .success: return .green
            case .failed: return .red
            case .partial: return .orange
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .partial: return "exclamationmark.circle.fill"
            }
        }
    }
}

// MARK: - GRDB Persistence

extension SyncEvent: FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_history"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let status = Column(CodingKeys.status)
        static let itemCount = Column(CodingKeys.itemCount)
        static let duration = Column(CodingKeys.duration)
        static let errorMessage = Column(CodingKeys.errorMessage)
        static let detailsJSON = Column("detailsJSON")
    }

    // Custom encoding for details array
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.timestamp] = timestamp
        container[Columns.status] = status.rawValue
        container[Columns.itemCount] = itemCount
        container[Columns.duration] = duration
        container[Columns.errorMessage] = errorMessage

        // Serialize details array to JSON
        if !details.isEmpty {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(details)
            container[Columns.detailsJSON] = String(data: jsonData, encoding: .utf8)
        }
    }

    // Custom decoding for details array
    init(row: Row) throws {
        id = row[Columns.id]
        timestamp = row[Columns.timestamp]
        status = SyncStatus(rawValue: row[Columns.status]) ?? .partial
        itemCount = row[Columns.itemCount]
        duration = row[Columns.duration]
        errorMessage = row[Columns.errorMessage]

        // Deserialize details array from JSON
        if let jsonString: String = row[Columns.detailsJSON],
           let jsonData = jsonString.data(using: .utf8) {
            let decoder = JSONDecoder()
            details = (try? decoder.decode([SyncRecordDetail].self, from: jsonData)) ?? []
        } else {
            details = []
        }
    }
}

// MARK: - Sync History View

struct SyncHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudKitSyncManager.self) private var syncManager

    @State private var pendingDeletions: [MemoModel] = []
    @State private var selectedDeletions: Set<UUID> = []
    @State private var isLoadingDeletions = false

    private let viewModel = MemosViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Manager")
                        .font(.system(size: 16, weight: .semibold))

                    if let lastSync = syncManager.lastSyncDate {
                        Text("Last synced \(formatRelativeTime(lastSync))")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }

                Spacer()

                // Sync Now button
                if syncManager.isSyncing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Syncing...")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                } else {
                    Button {
                        syncManager.syncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }

                // Copy history button
                Button {
                    copyHistoryToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy sync history")

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Pending Deletions Section
                    if !pendingDeletions.isEmpty {
                        PendingDeletionsSection(
                            deletions: pendingDeletions,
                            selectedDeletions: $selectedDeletions,
                            onApprove: approveDeletions,
                            onRestore: restoreDeletions
                        )

                        Divider()
                            .padding(.vertical, 8)
                    }

                    // Sync History Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sync History")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        if syncManager.syncHistory.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 48))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                Text("No sync history yet")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            ForEach(syncManager.syncHistory) { event in
                                SyncEventRow(event: event)
                                Divider()
                            }
                        }
                    }

                    // Dev Mode Troubleshooting Section (DEBUG builds only)
                    #if DEBUG
                    Divider()
                        .padding(.vertical, 8)

                    DevModeSyncSection(
                        syncManager: syncManager,
                        onForceBridge: {
                            syncManager.forceSyncToGRDB()
                        }
                    )
                    #endif
                }
            }
        }
        .frame(width: 600, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadPendingDeletions()
        }
    }

    private func loadPendingDeletions() async {
        isLoadingDeletions = true
        pendingDeletions = await viewModel.fetchPendingDeletions()
        isLoadingDeletions = false
        print("📋 [SyncHistory] Loaded \(pendingDeletions.count) pending deletions")
    }

    private func approveDeletions() {
        let idsToDelete = selectedDeletions.isEmpty
            ? Set(pendingDeletions.map(\.id))
            : selectedDeletions

        Task {
            await viewModel.permanentlyDeleteMemos(idsToDelete)
            await loadPendingDeletions()
            selectedDeletions.removeAll()
        }
    }

    private func restoreDeletions() {
        let idsToRestore = selectedDeletions.isEmpty
            ? Set(pendingDeletions.map(\.id))
            : selectedDeletions

        Task {
            await viewModel.restoreMemos(idsToRestore)
            await loadPendingDeletions()
            selectedDeletions.removeAll()
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func copyHistoryToClipboard() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        var text = "Sync History\n"
        text += "============\n\n"

        for event in syncManager.syncHistory {
            let status = event.status.rawValue.capitalized
            let time = dateFormatter.string(from: event.timestamp)
            let duration = event.duration.map { String(format: "%.1fs", $0) } ?? "-"

            text += "[\(status)] \(time)\n"
            text += "  Items: \(event.itemCount), Duration: \(duration)\n"

            if let error = event.errorMessage {
                text += "  Error: \(error)\n"
            }

            if !event.details.isEmpty {
                for detail in event.details {
                    text += "    • [\(detail.changeType.rawValue)] \(detail.recordType): \(detail.title)\n"
                }
            }
            text += "\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Pending Deletions Section

struct PendingDeletionsSection: View {
    let deletions: [MemoModel]
    @Binding var selectedDeletions: Set<UUID>

    let onApprove: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "trash.circle.fill")
                    .foregroundColor(.orange)
                Text("Pending Deletions")
                    .font(.system(size: 13, weight: .semibold))

                Text("(\(deletions.count))")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onRestore) {
                        Label(
                            selectedDeletions.isEmpty ? "Restore All" : "Restore",
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button(action: onApprove) {
                        Label(
                            selectedDeletions.isEmpty ? "Delete All" : "Delete",
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Deletion list
            VStack(spacing: 0) {
                ForEach(deletions) { memo in
                    PendingDeletionRow(
                        memo: memo,
                        isSelected: selectedDeletions.contains(memo.id),
                        onToggle: {
                            if selectedDeletions.contains(memo.id) {
                                selectedDeletions.remove(memo.id)
                            } else {
                                selectedDeletions.insert(memo.id)
                            }
                        }
                    )
                    Divider()
                        .padding(.leading, 48)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(CornerRadius.sm)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Pending Deletion Row

struct PendingDeletionRow: View {
    let memo: MemoModel
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : Theme.current.foregroundSecondary)

                // Source icon
                Image(systemName: memo.source.icon)
                    .font(.system(size: 14))
                    .foregroundColor(memo.source.color)
                    .frame(width: 20)

                // Memo info
                VStack(alignment: .leading, spacing: 2) {
                    Text(memo.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let deletedAt = memo.deletedAt {
                            Text("Deleted \(formatRelativeTime(deletedAt))")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        if memo.duration > 0 {
                            Text("•")
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Text(formatDuration(memo.duration))
                                .font(.system(size: 10))
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Sync Event Row

struct SyncEventRow: View {
    let event: SyncEvent
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row - always visible
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 12)

                    // Status icon
                    Image(systemName: event.status.icon)
                        .font(.system(size: 14))
                        .foregroundColor(event.status.color)
                        .frame(width: 20)

                    // Timestamp
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatTime(event.timestamp))
                            .font(.system(size: 12, weight: .medium))
                        Text(formatDate(event.timestamp))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .frame(width: 100, alignment: .leading)

                    // Summary
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(event.itemCount) item\(event.itemCount == 1 ? "" : "s")")
                                .font(.system(size: 12))

                            if let duration = event.duration {
                                Text("•")
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                Text(String(format: "%.1fs", duration))
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                        }

                        if let error = event.errorMessage {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(isExpanded ? 0.7 : 0.5))

            // Details - shown when expanded
            if isExpanded && !event.details.isEmpty {
                VStack(spacing: 0) {
                    ForEach(event.details) { detail in
                        SyncRecordDetailRow(detail: detail)
                    }
                }
                .padding(.leading, 48)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Sync Record Detail Row

struct SyncRecordDetailRow: View {
    let detail: SyncRecordDetail

    var body: some View {
        HStack(spacing: 10) {
            // Change type icon
            Image(systemName: detail.changeType.icon)
                .font(.system(size: 11))
                .foregroundColor(detail.changeType.color)
                .frame(width: 16)

            // Record type badge
            Text(detail.recordType)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(recordTypeColor(detail.recordType))
                .cornerRadius(CornerRadius.xs)

            // Title
            Text(detail.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Modification date
            if let modDate = detail.modificationDate {
                Text(formatShortDate(modDate))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func recordTypeColor(_ type: String) -> Color {
        switch type {
        case "VoiceMemo": return .blue
        case "Workflow": return .purple
        case "WorkflowStep": return .indigo
        case "TranscriptionSegment": return .teal
        default: return .gray
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Dev Mode Sync Section

struct DevSyncStats {
    let coreDataCount: Int
    let grdbCount: Int
    let liveCount: Int
    let lastBridgeSync: Date?
    let coreDataIDs: Set<UUID>
    let grdbIDs: Set<UUID>

    var countMismatch: Bool {
        coreDataCount != grdbCount
    }

    var inCoreDataOnly: Set<UUID> {
        coreDataIDs.subtracting(grdbIDs)
    }

    var inGRDBOnly: Set<UUID> {
        grdbIDs.subtracting(coreDataIDs)
    }

    static func gather() async -> DevSyncStats {
        let (coreDataCount, coreDataIDs) = await fetchCoreDataInfo()
        let (grdbCount, grdbIDs) = await fetchGRDBInfo()
        let live = LiveDatabase.count()

        return DevSyncStats(
            coreDataCount: coreDataCount,
            grdbCount: grdbCount,
            liveCount: live,
            lastBridgeSync: nil,
            coreDataIDs: coreDataIDs,
            grdbIDs: grdbIDs
        )
    }

    private static func fetchCoreDataInfo() async -> (Int, Set<UUID>) {
        // Use gateway for safe Core Data access with isReady check
        guard let context = await CoreDataSyncGateway.shared.context else {
            return (0, Set<UUID>())
        }
        return await context.perform {
            let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
            request.propertiesToFetch = ["id"]
            guard let memos = try? context.fetch(request) else {
                return (0, Set<UUID>())
            }
            let ids = Set(memos.compactMap { $0.id })
            return (memos.count, ids)
        }
    }

    private static func fetchGRDBInfo() async -> (Int, Set<UUID>) {
        do {
            let repo = LocalRepository()
            let count = try await repo.countMemos()
            let ids = try await repo.fetchAllIDs()
            return (count, ids)
        } catch {
            return (0, Set<UUID>())
        }
    }
}

struct DevModeSyncSection: View {
    let syncManager: CloudKitSyncManager
    let onForceBridge: () -> Void

    @State private var stats: DevSyncStats?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundColor(.orange)
                Text("Dev Mode")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()

                Button {
                    Task {
                        isLoading = true
                        stats = await DevSyncStats.gather()
                        isLoading = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading stats...")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(.horizontal, 16)
            } else if let stats = stats {
                // Database counts
                VStack(spacing: 8) {
                    DevStatRow(
                        label: "Core Data",
                        value: "\(stats.coreDataCount) memos",
                        icon: "icloud",
                        color: .blue
                    )

                    DevStatRow(
                        label: "Local GRDB",
                        value: "\(stats.grdbCount) memos",
                        icon: "internaldrive",
                        color: stats.countMismatch ? .orange : .green
                    )

                    DevStatRow(
                        label: "Live Database",
                        value: "\(stats.liveCount) dictations",
                        icon: "waveform",
                        color: .purple
                    )

                    // Diff info
                    if !stats.inCoreDataOnly.isEmpty || !stats.inGRDBOnly.isEmpty {
                        Divider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            if !stats.inCoreDataOnly.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "icloud.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 10))
                                    Text("\(stats.inCoreDataOnly.count) in CloudKit only")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.blue)
                                    Text("(needs bridge)")
                                        .font(.system(size: 9))
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }
                                .padding(.horizontal, 16)
                            }

                            if !stats.inGRDBOnly.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "internaldrive.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 10))
                                    Text("\(stats.inGRDBOnly.count) in Local only")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.orange)
                                    Text("(orphaned)")
                                        .font(.system(size: 9))
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    } else if stats.countMismatch {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Count mismatch (same IDs)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                // Actions
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            onForceBridge()
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1))
                                self.stats = await DevSyncStats.gather()
                            }
                        } label: {
                            Label("Bridge Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            CloudKitSyncManager.shared.fullSyncToGRDB()
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(3))
                                self.stats = await DevSyncStats.gather()
                            }
                        } label: {
                            Label("Full Sync (All)", systemImage: "arrow.clockwise.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button {
                            copyStatsToClipboard(stats)
                        } label: {
                            Label("Copy Stats", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }

                    if !stats.inCoreDataOnly.isEmpty {
                        Text("Full Sync will copy \(stats.inCoreDataOnly.count) CloudKit memos to local")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(CornerRadius.sm)
        .padding(.horizontal, 16)
        .task {
            stats = await DevSyncStats.gather()
            isLoading = false
        }
    }

    private func copyStatsToClipboard(_ stats: DevSyncStats) {
        var text = """
        Talkie Sync Stats
        =================
        Core Data: \(stats.coreDataCount) memos
        Local GRDB: \(stats.grdbCount) memos
        Live DB: \(stats.liveCount) dictations
        Mismatch: \(stats.countMismatch ? "YES" : "No")
        """

        if !stats.inCoreDataOnly.isEmpty {
            text += "\n\nIn CloudKit only (\(stats.inCoreDataOnly.count)):\n"
            for id in stats.inCoreDataOnly.prefix(20) {
                text += "  • \(id.uuidString)\n"
            }
            if stats.inCoreDataOnly.count > 20 {
                text += "  ... and \(stats.inCoreDataOnly.count - 20) more\n"
            }
        }

        if !stats.inGRDBOnly.isEmpty {
            text += "\n\nIn Local only (\(stats.inGRDBOnly.count)):\n"
            for id in stats.inGRDBOnly.prefix(20) {
                text += "  • \(id.uuidString)\n"
            }
            if stats.inGRDBOnly.count > 20 {
                text += "  ... and \(stats.inGRDBOnly.count - 20) more\n"
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct DevStatRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#Preview {
    SyncHistoryView()
}
