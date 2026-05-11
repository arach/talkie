//
//  VoiceMemoRow.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

struct VoiceMemoRow: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject var audioPlayer: AudioPlayerManager
    var onSelect: ((VoiceMemo) -> Void)? = nil

    // Access theme colors via cached static - no @ObservedObject needed for read-only access
    private var themeColors: ThemeColors { ThemeManager.shared.colors }

    @State private var selectedMemoForDetail: VoiceMemo?

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    /// File size estimated from duration (avoids loading audioData into memory)
    private var fileSize: String {
        // Estimate: ~16KB/sec for AAC audio at typical quality
        // Accessing audioData.count would load entire blob into memory!
        let estimatedBytes = Int(memo.duration * 16000)
        return formatFileSize(estimatedBytes)
    }

    /// Audio format from filename extension
    private var audioFormat: String {
        guard let filename = memo.fileURL else { return "M4A" }
        let ext = (filename as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "M4A" : ext
    }

    /// Count of workflow actions that have been run
    private var actionCount: Int {
        guard let runs = memo.workflowRuns as? Set<WorkflowRun> else { return 0 }
        return runs.filter { $0.status == "completed" }.count
    }

    var body: some View {
        Button(action: {
            if let onSelect {
                onSelect(memo)
            } else {
                selectedMemoForDetail = memo
            }
        }) {
            HStack(alignment: .center, spacing: 12) {
                rowTypeBadge

                VStack(spacing: 4) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(memoTitle)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if actionCount > 0 {
                            HStack(spacing: 4) {
                                Text("\(actionCount)")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(themeColors.accent)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(themeColors.accent)
                            }
                        }
                    }

                    HStack(spacing: 0) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                        Text(" ")
                        Text(formatDateTime(memoCreatedAt))
                        Text("  ·  ").foregroundColor(.textTertiary.opacity(0.6))
                        Image(systemName: "doc")
                            .font(.system(size: 8))
                        Text(" ")
                        Text(fileSize)
                        Spacer()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("memo.row")
        .sheet(item: $selectedMemoForDetail) { (memoToShow: VoiceMemo) in
            VoiceMemoDetailView(memo: memoToShow, audioPlayer: audioPlayer)
        }
    }

    private var rowTypeBadge: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textSecondary)
            .frame(width: 28, height: 28)
            .background(Color.surfaceSecondary)
            .clipShape(Circle())
    }

    // Static formatters - DateFormatter is expensive to create
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d h:mm a"
        return f
    }()

    private func formatDateTime(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else {
            return Self.dateTimeFormatter.string(from: date)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            let kb = Double(bytes) / 1024
            return String(format: "%.0f KB", kb)
        }
    }
}

// MARK: - Pulsing Dot Indicator

/// A single dot that pulses smoothly for processing states
struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 8

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .opacity(isPulsing ? 1.0 : 0.5)
        }
        .frame(width: size, height: size)
        .animation(
            Animation.easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true),
            value: isPulsing
        )
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Cloud Sync Indicator

/// Cloud icon - same shape for both states, just different fill
struct CloudSyncIndicator: View {
    let isSynced: Bool

    var body: some View {
        Image(systemName: isSynced ? "checkmark.icloud.fill" : "icloud.fill")
            .font(.system(size: 11))
            .foregroundColor(isSynced ? .green : .textTertiary)
    }
}
