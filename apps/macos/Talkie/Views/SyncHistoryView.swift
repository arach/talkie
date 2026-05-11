//
//  SyncHistoryView.swift
//  Talkie
//
//  Simple CloudKit sync history viewer
//  Shows recent sync operations with timestamps and status
//

import SwiftUI
import GRDB
import TalkieKit

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

struct SyncActivityDetail: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let level: Level
    let message: String

    init(id: String = UUID().uuidString, timestamp: Date, level: Level, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }

    enum Level: String, Codable {
        case info
        case success
        case warning
        case error

        var icon: String {
            switch self {
            case .info: return "circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }

        @MainActor
        var color: Color {
            switch self {
            case .info: return Theme.current.foregroundSecondary
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
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
    let activity: [SyncActivityDetail] // Run activity log from SyncClient
    let localCount: Int? // Local GRDB memo count at sync time
    let remoteCount: Int? // CloudKit/CoreData memo count at sync time

    // Real sync breakdown (nil for old events before stats were piped)
    let inserted: Int?
    let updated: Int?
    let deleted: Int?
    let skipped: Int?
    let fetchTimeMs: Int?
    let totalTimeMs: Int?
    let syncMode: String?  // "full" or "incremental" (nil for old events)

    init(id: String = UUID().uuidString, timestamp: Date, status: SyncStatus, itemCount: Int, duration: TimeInterval?, errorMessage: String?, details: [SyncRecordDetail] = [], activity: [SyncActivityDetail] = [], localCount: Int? = nil, remoteCount: Int? = nil, inserted: Int? = nil, updated: Int? = nil, deleted: Int? = nil, skipped: Int? = nil, fetchTimeMs: Int? = nil, totalTimeMs: Int? = nil, syncMode: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.itemCount = itemCount
        self.duration = duration
        self.errorMessage = errorMessage
        self.details = details
        self.activity = activity
        self.localCount = localCount
        self.remoteCount = remoteCount
        self.inserted = inserted
        self.updated = updated
        self.deleted = deleted
        self.skipped = skipped
        self.fetchTimeMs = fetchTimeMs
        self.totalTimeMs = totalTimeMs
        self.syncMode = syncMode
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
        static let activityJSON = Column("activityJSON")
        static let localCount = Column(CodingKeys.localCount)
        static let remoteCount = Column(CodingKeys.remoteCount)
        static let inserted = Column(CodingKeys.inserted)
        static let updated = Column(CodingKeys.updated)
        static let deleted = Column(CodingKeys.deleted)
        static let skipped = Column(CodingKeys.skipped)
        static let fetchTimeMs = Column(CodingKeys.fetchTimeMs)
        static let totalTimeMs = Column(CodingKeys.totalTimeMs)
        static let syncMode = Column(CodingKeys.syncMode)
    }

    // Custom encoding for details array
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.timestamp] = timestamp
        container[Columns.status] = status.rawValue
        container[Columns.itemCount] = itemCount
        container[Columns.duration] = duration
        container[Columns.errorMessage] = errorMessage
        container[Columns.localCount] = localCount
        container[Columns.remoteCount] = remoteCount
        container[Columns.inserted] = inserted
        container[Columns.updated] = updated
        container[Columns.deleted] = deleted
        container[Columns.skipped] = skipped
        container[Columns.fetchTimeMs] = fetchTimeMs
        container[Columns.totalTimeMs] = totalTimeMs
        container[Columns.syncMode] = syncMode

        // Serialize details array to JSON
        if !details.isEmpty {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(details)
            container[Columns.detailsJSON] = String(data: jsonData, encoding: .utf8)
        }

        if !activity.isEmpty {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(activity)
            container[Columns.activityJSON] = String(data: jsonData, encoding: .utf8)
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
        localCount = row[Columns.localCount]
        remoteCount = row[Columns.remoteCount]
        inserted = row[Columns.inserted]
        updated = row[Columns.updated]
        deleted = row[Columns.deleted]
        skipped = row[Columns.skipped]
        fetchTimeMs = row[Columns.fetchTimeMs]
        totalTimeMs = row[Columns.totalTimeMs]
        syncMode = row[Columns.syncMode]

        // Deserialize details array from JSON
        if let jsonString: String = row[Columns.detailsJSON],
           let jsonData = jsonString.data(using: .utf8) {
            let decoder = JSONDecoder()
            details = (try? decoder.decode([SyncRecordDetail].self, from: jsonData)) ?? []
        } else {
            details = []
        }

        if let jsonString: String = row[Columns.activityJSON],
           let jsonData = jsonString.data(using: .utf8) {
            let decoder = JSONDecoder()
            activity = (try? decoder.decode([SyncActivityDetail].self, from: jsonData)) ?? []
        } else {
            activity = []
        }
    }
}

// MARK: - SyncHistoryView (removed — replaced by SyncPanel)

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

// MARK: - Old views (SyncEventRow, SyncRecordDetailRow, SyncEventDetailView, ChangeGroupSection)
// Removed — replaced by CompactSyncEventRow in SyncPanel.swift

// MARK: - Dev Mode Sync Section

struct DevSyncStats {
    let coreDataCount: Int
    let grdbCount: Int
    let liveCount: Int
    let lastBridgeSync: Date?
    let coreDataIDs: Set<UUID>
    let grdbIDs: Set<UUID>

    /// Whether Core Data count is available (-1 means unavailable)
    var isCoreDataAvailable: Bool { coreDataCount >= 0 }

    var countMismatch: Bool {
        guard isCoreDataAvailable else { return false }
        return coreDataCount != grdbCount
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
        let live = (try? await TalkieObjectRepository().countDictations()) ?? 0

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
        // Ensure SyncClient is connected before querying
        await MainActor.run {
            let client = SyncClient.shared
            if !client.isConnected, ServiceManager.shared.sync.isRunning {
                client.connect()
            }
        }
        // Give XPC a moment to establish
        try? await Task.sleep(for: .milliseconds(500))

        // Get count from TalkieSync via XPC (Core Data no longer directly accessible)
        let count = await SyncClient.shared.getRemoteMemoCount()
        // We can no longer get individual IDs - return empty set
        return (count, Set<UUID>())
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
                    BrailleSpinner(size: 12)
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
                        value: stats.isCoreDataAvailable ? "\(stats.coreDataCount) memos" : "unavailable",
                        icon: "icloud",
                        color: stats.isCoreDataAvailable ? .blue : .secondary
                    )

                    DevStatRow(
                        label: "Local GRDB",
                        value: "\(stats.grdbCount) memos",
                        icon: "internaldrive",
                        color: stats.countMismatch ? .orange : .green
                    )

                    DevStatRow(
                        label: "Agent Database",
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

                // Actions - simplified since TalkieSync handles both CloudKit + bridge
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                // Single sync button - launches TalkieSync if needed, syncs, then terminates
                                do {
                                    try await SyncClient.shared.runSyncOnce(keepRunning: SettingsManager.shared.syncOnLaunch)
                                } catch {
                                    // Sync failed - SyncClient logs the error
                                }
                                try? await Task.sleep(for: .seconds(2))
                                self.stats = await DevSyncStats.gather()
                            }
                        } label: {
                            Label("Sync Now", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            copyStatsToClipboard(stats)
                        } label: {
                            Label("Copy Stats", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }

                    if stats.isCoreDataAvailable && stats.coreDataCount > stats.grdbCount {
                        Text("\(stats.coreDataCount - stats.grdbCount) memos pending sync from iCloud")
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
        let cdLabel = stats.isCoreDataAvailable ? "\(stats.coreDataCount) memos" : "unavailable"
        var text = """
        Talkie Sync Stats
        =================
        Core Data: \(cdLabel)
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
    SyncPanel()
        .environment(CloudKitSyncManager.shared)
}
