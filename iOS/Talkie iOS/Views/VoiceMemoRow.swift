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

    @State private var showingDetail = false

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    /// File size from audioData or estimated from duration
    private var fileSize: String {
        if let data = memo.audioData {
            return formatFileSize(data.count)
        }
        let estimatedBytes = Int(memo.duration * 16000)
        return formatFileSize(estimatedBytes)
    }

    /// Audio format from filename extension
    private var audioFormat: String {
        guard let filename = memo.fileURL else { return "M4A" }
        let ext = (filename as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "M4A" : ext
    }

    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack(alignment: .top, spacing: 12) {
                // Left side: Name and metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text(memoTitle)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    // Metadata: Time | Size | Format
                    HStack(spacing: 0) {
                        Text(formatTime(memoCreatedAt))
                        Text("  |  ").foregroundColor(.textTertiary.opacity(0.5))
                        Text(fileSize)
                        Text("  |  ").foregroundColor(.textTertiary.opacity(0.5))
                        Text(audioFormat)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                }

                Spacer(minLength: 8)

                // Right side: Duration and status badges
                VStack(alignment: .trailing, spacing: 6) {
                    Text(formatDuration(memo.duration))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.textSecondary)

                    // Status badges - TXT → CLOUD → SPARKLES
                    HStack(spacing: 6) {
                        if memo.isTranscribing {
                            ZStack {
                                PulsingDot(color: .textTertiary, size: 4)
                            }
                            .frame(width: 22, height: 12) // Match TXT label size
                        } else if memo.transcription != nil && !memo.transcription!.isEmpty {
                            Text("TXT")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green)
                        }

                        if memo.cloudSyncedAt == nil && memo.audioData != nil {
                            // Uploading to cloud
                            CloudSyncIndicator(isSynced: false)
                        } else if memo.cloudSyncedAt != nil {
                            // Synced
                            CloudSyncIndicator(isSynced: true)
                        }

                        if memo.summary != nil && !memo.summary!.isEmpty {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.purple)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            VoiceMemoDetailView(memo: memo, audioPlayer: audioPlayer)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
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
        Image(systemName: isSynced ? "checkmark.icloud.fill" : "arrow.up.icloud.fill")
            .font(.system(size: 11))
            .foregroundColor(isSynced ? .green : .textTertiary)
    }
}

/// Animated braille-style dots over cloud for upload state
struct CloudSyncBraille: View {
    @State private var dotIndex = 0

    // Braille patterns that look like dots moving upward
    private let patterns = ["⠁", "⠂", "⠄", "⠠", "⠐", "⠈"]

    var body: some View {
        ZStack {
            // Base cloud
            Image(systemName: "icloud.fill")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary.opacity(0.5))

            // Animated braille dot
            Text(patterns[dotIndex])
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.textTertiary)
                .offset(y: -1)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                dotIndex = (dotIndex + 1) % patterns.count
            }
        }
    }
}

// MARK: - Debug Combined Status Row

/// Shows TXT and SYNC side by side with different timing
/// TXT: 2.5s processing -> done, SYNC: 1.5s uploading -> done
struct CombinedStatusRow: View {
    @State private var txtDone = false
    @State private var syncDone = false
    @State private var cycleTimer: Timer?

    var body: some View {
        HStack(spacing: 6) {
            // TXT indicator
            ZStack {
                if txtDone {
                    Text("TXT")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                } else {
                    PulsingDot(color: .textTertiary, size: 4)
                }
            }
            .frame(width: 24, height: 12)
            .animation(.easeInOut(duration: 0.2), value: txtDone)

            // SYNC indicator
            ZStack {
                if syncDone {
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(width: 16, height: 12)
            .animation(.easeInOut(duration: 0.2), value: syncDone)

            Spacer()
        }
        .onAppear {
            startCycle()
        }
        .onDisappear {
            cycleTimer?.invalidate()
        }
    }

    private func startCycle() {
        // Reset to processing state
        txtDone = false
        syncDone = false

        // SYNC completes first at 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            syncDone = true
        }

        // TXT completes at 2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            txtDone = true
        }

        // Restart cycle after showing done state for 1.5s
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            // Reset
            txtDone = false
            syncDone = false

            // SYNC completes first
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                syncDone = true
            }

            // TXT completes after
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                txtDone = true
            }
        }
    }
}
