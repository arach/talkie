//
//  SyncHistoryView.swift
//  Talkie
//
//  Simple CloudKit sync history viewer
//  Shows recent sync operations with timestamps and status
//

import SwiftUI

// MARK: - Sync Event Model

struct SyncEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let status: SyncStatus
    let itemCount: Int
    let duration: TimeInterval?
    let errorMessage: String?

    enum SyncStatus {
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

// MARK: - Sync History View

struct SyncHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var syncManager = CloudKitSyncManager.shared

    // TODO: Replace with actual sync history from CloudKitSyncManager
    // For now, showing mock data
    private let mockEvents: [SyncEvent] = [
        SyncEvent(timestamp: Date().addingTimeInterval(-300), status: .success, itemCount: 3, duration: 1.2, errorMessage: nil),
        SyncEvent(timestamp: Date().addingTimeInterval(-3600), status: .success, itemCount: 7, duration: 2.1, errorMessage: nil),
        SyncEvent(timestamp: Date().addingTimeInterval(-7200), status: .partial, itemCount: 2, duration: 0.8, errorMessage: "1 item failed to sync"),
        SyncEvent(timestamp: Date().addingTimeInterval(-14400), status: .success, itemCount: 12, duration: 3.5, errorMessage: nil),
    ]

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
                    ForEach(mockEvents) { event in
                        SyncEventRow(event: event)
                        Divider()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
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

    var body: some View {
        HStack(spacing: 12) {
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

            // Details
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
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
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

// MARK: - Preview

#Preview {
    SyncHistoryView()
}
