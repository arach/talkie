//
//  SyncPerformanceView.swift
//  TalkieSync
//
//  Performance dashboard for TalkieSync.
//  Shows sync history, throughput, and queue status.
//

import SwiftUI
import TalkieKit

struct SyncPerformanceView: View {
    @State private var syncHistory: [SyncHistoryEntry] = SyncHistoryEntry.sampleData

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metricsSection
                    historySection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("TalkieSync Performance")
                    .font(.headline)
                Text("Sync history and throughput metrics")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: triggerSync) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("SYNC NOW")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Metrics Section

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("METRICS", color: .orange)

            HStack(spacing: 12) {
                metricCard(
                    title: "Total Synced",
                    value: "1,234",
                    subtitle: "records",
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue
                )

                metricCard(
                    title: "Avg Duration",
                    value: "0.8s",
                    subtitle: "per sync",
                    icon: "clock",
                    color: .green
                )

                metricCard(
                    title: "Success Rate",
                    value: "99.2%",
                    subtitle: "last 24h",
                    icon: "checkmark.circle",
                    color: .green
                )

                metricCard(
                    title: "Queue Depth",
                    value: "0",
                    subtitle: "pending",
                    icon: "tray",
                    color: .gray
                )
            }
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("SYNC HISTORY", color: .blue)
                Spacer()
                Text("\(syncHistory.count) events")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 1) {
                // Header row
                HStack(spacing: 0) {
                    Text("TIME")
                        .frame(width: 100, alignment: .leading)
                    Text("TYPE")
                        .frame(width: 80, alignment: .leading)
                    Text("RECORDS")
                        .frame(width: 70, alignment: .trailing)
                    Text("DURATION")
                        .frame(width: 70, alignment: .trailing)
                    Text("STATUS")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                // History rows
                ForEach(syncHistory) { entry in
                    historyRow(entry)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func historyRow(_ entry: SyncHistoryEntry) -> some View {
        HStack(spacing: 0) {
            Text(entry.timeAgo)
                .frame(width: 100, alignment: .leading)
            Text(entry.type)
                .frame(width: 80, alignment: .leading)
            Text("\(entry.recordCount)")
                .frame(width: 70, alignment: .trailing)
            Text(entry.duration)
                .frame(width: 70, alignment: .trailing)
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.success ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(entry.success ? "OK" : "Failed")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: 14)

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
        }
    }

    private func triggerSync() {
        SyncScheduler.shared.syncNow()
    }
}

// MARK: - Sample Data

struct SyncHistoryEntry: Identifiable {
    let id = UUID()
    let timeAgo: String
    let type: String
    let recordCount: Int
    let duration: String
    let success: Bool

    static let sampleData: [SyncHistoryEntry] = [
        SyncHistoryEntry(timeAgo: "2 min ago", type: "Scheduled", recordCount: 3, duration: "0.8s", success: true),
        SyncHistoryEntry(timeAgo: "12 min ago", type: "Scheduled", recordCount: 0, duration: "0.2s", success: true),
        SyncHistoryEntry(timeAgo: "22 min ago", type: "Manual", recordCount: 15, duration: "1.2s", success: true),
        SyncHistoryEntry(timeAgo: "32 min ago", type: "Scheduled", recordCount: 2, duration: "0.6s", success: true),
        SyncHistoryEntry(timeAgo: "42 min ago", type: "Scheduled", recordCount: 0, duration: "0.1s", success: true),
        SyncHistoryEntry(timeAgo: "52 min ago", type: "Background", recordCount: 8, duration: "1.5s", success: true),
        SyncHistoryEntry(timeAgo: "1 hr ago", type: "Scheduled", recordCount: 1, duration: "0.4s", success: true),
    ]
}

#Preview {
    SyncPerformanceView()
}
