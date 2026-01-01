//
//  StorageSettingsSection.swift
//  TalkieLive
//
//  Storage settings: data management, retention, statistics
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Storage Settings Section

struct StorageSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @State private var storageStats = StorageStats()
    @State private var isRefreshing = false
    @State private var showDeleteConfirmation = false

    private let ttlOptions = [1, 6, 12, 24, 48, 72, 168] // hours, 168 = 1 week

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "folder",
                title: "STORAGE",
                subtitle: "Manage transcription history and storage."
            )
        } content: {
            // Live Stats Overview
            SettingsCard(title: "LIVE STORAGE") {
                VStack(spacing: Spacing.md) {
                    // Main stats row
                    HStack(spacing: Spacing.lg) {
                        StorageStatBox(
                            icon: "text.bubble.fill",
                            value: "\(storageStats.totalUtterances)",
                            label: "Transcriptions",
                            color: .accentColor
                        )

                        StorageStatBox(
                            icon: "waveform",
                            value: storageStats.audioStorageFormatted,
                            label: "Audio Files",
                            color: .purple
                        )

                        StorageStatBox(
                            icon: "cylinder.fill",
                            value: storageStats.databaseSizeFormatted,
                            label: "Database",
                            color: SemanticColor.warning
                        )

                        StorageStatBox(
                            icon: "sum",
                            value: storageStats.totalStorageFormatted,
                            label: "Total",
                            color: SemanticColor.success
                        )
                    }

                    Divider()
                        .background(TalkieTheme.surfaceElevated)

                    // Secondary stats
                    HStack(spacing: Spacing.lg) {
                        // Time range
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TIME RANGE")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(TalkieTheme.textMuted)

                            if let oldest = storageStats.oldestDate, let newest = storageStats.newestDate {
                                Text("\(formatDate(oldest)) → \(formatDate(newest))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(TalkieTheme.textSecondary)
                            } else {
                                Text("No data")
                                    .font(.system(size: 10))
                                    .foregroundColor(TalkieTheme.textMuted)
                            }
                        }

                        Spacer()

                        // Total words
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TOTAL WORDS")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(TalkieTheme.textMuted)

                            Text(formatNumber(storageStats.totalWords))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(TalkieTheme.textSecondary)
                        }

                        // Total duration
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TOTAL DURATION")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(TalkieTheme.textMuted)

                            Text(formatDuration(storageStats.totalDurationSeconds))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(TalkieTheme.textSecondary)
                        }
                    }

                    // Refresh button
                    HStack {
                        Button(action: refreshStats) {
                            HStack(spacing: 4) {
                                if isRefreshing {
                                    BrailleSpinner(speed: 0.08)
                                        .font(.system(size: 9))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 9))
                                }
                                Text("Refresh")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(TalkieTheme.textTertiary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("Last updated: \(formatTime(storageStats.lastUpdated))")
                            .font(.system(size: 9))
                            .foregroundColor(TalkieTheme.textMuted)
                    }
                }
            }

            // Top Apps
            if !storageStats.topApps.isEmpty {
                SettingsCard(title: "TOP APPS") {
                    VStack(spacing: Spacing.xs) {
                        ForEach(storageStats.topApps.prefix(5), id: \.bundleID) { app in
                            HStack {
                                Text(app.name)
                                    .font(.system(size: 10))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(app.count)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.accentColor)

                                // Progress bar
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.accentColor.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(app.count) / CGFloat(max(storageStats.topApps.first?.count ?? 1, 1)))
                                }
                                .frame(width: 60, height: 4)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // Retention
            SettingsCard(title: "RETENTION") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Keep dictations for:")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textPrimary)

                        Spacer()

                        Picker("", selection: $settings.dictationTTLHours) {
                            ForEach(ttlOptions, id: \.self) { hours in
                                Text(formatTTL(hours)).tag(hours)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }

                    Text("Older dictations will be automatically deleted.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            // Storage Location & Actions
            SettingsCard(title: "DATA MANAGEMENT") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Location row
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)

                        Text("~/Library/Application Support/TalkieLive")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Open") {
                            if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("TalkieLive") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    Divider()
                        .background(TalkieTheme.surfaceElevated)

                    // Action buttons
                    HStack(spacing: Spacing.sm) {
                        StorageActionButton(
                            icon: "trash",
                            label: "Prune Old",
                            color: SemanticColor.warning
                        ) {
                            LiveDatabase.prune(olderThanHours: settings.dictationTTLHours)
                            refreshStats()
                        }

                        StorageActionButton(
                            icon: "doc.badge.gearshape",
                            label: "Clean Orphans",
                            color: .purple
                        ) {
                            cleanOrphanedAudio()
                            refreshStats()
                        }

                        Spacer()

                        StorageActionButton(
                            icon: "trash.fill",
                            label: "Delete All",
                            color: SemanticColor.error
                        ) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
        }
        .onAppear {
            refreshStats()
        }
        .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                LiveDatabase.deleteAll()
                refreshStats()
            }
        } message: {
            Text("This will permanently delete all \(storageStats.totalUtterances) transcriptions and \(storageStats.audioStorageFormatted) of audio files. This cannot be undone.")
        }
    }

    private func refreshStats() {
        isRefreshing = true
        Task {
            let stats = await StorageStats.calculate()
            await MainActor.run {
                storageStats = stats
                isRefreshing = false
            }
        }
    }

    private func cleanOrphanedAudio() {
        let utterances = LiveDatabase.all()
        let referencedFilenames = Set(utterances.compactMap { $0.audioFilename })
        AudioStorage.pruneOrphanedFiles(referencedFilenames: referencedFilenames)
    }

    private func formatTTL(_ hours: Int) -> String {
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if hours == 168 {
            return "1 week"
        } else {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Storage Stats

struct StorageStats {
    var totalUtterances: Int = 0
    var totalWords: Int = 0
    var totalDurationSeconds: Double = 0
    var audioStorageBytes: Int64 = 0
    var databaseSizeBytes: Int64 = 0
    var oldestDate: Date?
    var newestDate: Date?
    var topApps: [AppUsage] = []
    var lastUpdated: Date = Date()

    var audioStorageFormatted: String {
        ByteCountFormatter.string(fromByteCount: audioStorageBytes, countStyle: .file)
    }

    var databaseSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: databaseSizeBytes, countStyle: .file)
    }

    var totalStorageFormatted: String {
        ByteCountFormatter.string(fromByteCount: audioStorageBytes + databaseSizeBytes, countStyle: .file)
    }

    struct AppUsage: Identifiable {
        let bundleID: String
        let name: String
        let count: Int
        var id: String { bundleID }
    }

    static func calculate() async -> StorageStats {
        let utterances = LiveDatabase.all()
        var stats = StorageStats()

        stats.totalUtterances = utterances.count
        stats.totalWords = utterances.compactMap { $0.wordCount }.reduce(0, +)
        stats.totalDurationSeconds = utterances.compactMap { $0.durationSeconds }.reduce(0, +)
        stats.audioStorageBytes = await AudioStorage.totalStorageBytesAsync()

        // Database size
        if let dbPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TalkieLive/PastLives.sqlite").path {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
               let size = attrs[.size] as? Int64 {
                stats.databaseSizeBytes = size
            }
        }

        // Date range
        if let oldest = utterances.last {
            stats.oldestDate = oldest.createdAt
        }
        if let newest = utterances.first {
            stats.newestDate = newest.createdAt
        }

        // Top apps
        var appCounts: [String: (name: String, count: Int)] = [:]
        for u in utterances {
            if let bundleID = u.appBundleID {
                let name = u.appName ?? bundleID
                let existing = appCounts[bundleID]
                appCounts[bundleID] = (name: name, count: (existing?.count ?? 0) + 1)
            }
        }
        stats.topApps = appCounts.map { AppUsage(bundleID: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted { $0.count > $1.count }

        stats.lastUpdated = Date()
        return stats
    }
}

// MARK: - Storage Stat Box

struct StorageStatBox: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(TalkieTheme.textPrimary)

            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Storage Action Button

struct StorageActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isHovered ? color : TalkieTheme.textTertiary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isHovered ? color.opacity(0.15) : TalkieTheme.hover)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
