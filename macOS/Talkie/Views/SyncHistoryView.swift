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
    @ObservedObject private var syncManager = CloudKitSyncManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync History")
                        .font(.system(size: 16, weight: .semibold))

                    if let lastSync = syncManager.lastSyncDate {
                        Text("Last synced \(formatRelativeTime(lastSync))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if syncManager.isSyncing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Syncing...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Sync Events List
            ScrollView {
                LazyVStack(spacing: 0) {
                    if syncManager.syncHistory.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No sync history yet")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 80)
                    } else {
                        ForEach(syncManager.syncHistory) { event in
                            SyncEventRow(event: event)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
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
                        .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 100, alignment: .leading)

                    // Summary
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(event.itemCount) item\(event.itemCount == 1 ? "" : "s")")
                                .font(.system(size: 12))

                            if let duration = event.duration {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1fs", duration))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
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
                .cornerRadius(4)

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
                    .foregroundColor(.secondary)
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

// MARK: - Preview

#Preview {
    SyncHistoryView()
}
