//
//  StorageSettings.swift
//  Talkie
//
//  Storage settings - Database and Cloud
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "StorageSettings")

// MARK: - Database Settings

/// Database storage settings: retention, cleanup for memos and dictations
struct DatabaseSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings

    // Stats
    @State private var totalDictations: Int = 0
    @State private var totalAudioFiles: Int = 0
    @State private var storageSize: String = "..."

    // Prune preview
    @State private var pruneCount: Int = 0
    @State private var pruneOldestDate: Date?
    @State private var pruneNewestDate: Date?

    // Orphan preview
    @State private var orphanCount: Int = 0
    @State private var orphanSize: Int64 = 0

    // Confirmation
    @State private var showPruneConfirm = false
    @State private var showOrphanConfirm = false

    var body: some View {
        @Bindable var live = liveSettings

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "cylinder",
                title: "DATABASE",
                subtitle: "Configure data retention and cleanup."
            )
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                // Overview Stats
                storageOverview

                Divider()

                // Dictation Retention
                VStack(alignment: .leading, spacing: 12) {
                    Text("DICTATION RETENTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Dictations older than this can be pruned from maintenance below.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    // Preset buttons
                    HStack(spacing: 8) {
                        RetentionPresetButton(label: "1 Month", hours: 720, current: $live.utteranceTTLHours)
                        RetentionPresetButton(label: "3 Months", hours: 2160, current: $live.utteranceTTLHours)
                        RetentionPresetButton(label: "6 Months", hours: 4320, current: $live.utteranceTTLHours)
                        RetentionPresetButton(label: "1 Year", hours: 8760, current: $live.utteranceTTLHours)
                        RetentionPresetButton(label: "Forever", hours: 0, current: $live.utteranceTTLHours)
                    }

                    // Custom input
                    if live.utteranceTTLHours > 0 && ![720, 2160, 4320, 8760].contains(live.utteranceTTLHours) {
                        HStack(spacing: 8) {
                            Text("Custom:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("\(live.utteranceTTLHours / 24) days")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                }

                Divider()

                // Memo Retention (placeholder)
                VStack(alignment: .leading, spacing: 12) {
                    Text("MEMO RETENTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    HStack {
                        Image(systemName: "infinity")
                            .foregroundColor(.secondary)
                        Text("Memos are kept indefinitely until manually deleted.")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }

                Divider()

                // Maintenance Actions (with transparency)
                maintenanceSection
            }
        }
        .onAppear {
            refreshStats()
        }
        .onChange(of: live.utteranceTTLHours) { _, _ in
            refreshPrunePreview()
        }
        .alert("Prune Old Dictations?", isPresented: $showPruneConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Prune \(pruneCount) Dictations", role: .destructive) {
                performPrune()
            }
        } message: {
            Text("This will permanently delete \(pruneCount) dictations older than \(liveSettings.utteranceTTLHours / 24) days and their audio files. This cannot be undone.")
        }
        .alert("Clean Orphaned Files?", isPresented: $showOrphanConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(orphanCount) Files", role: .destructive) {
                performOrphanCleanup()
            }
        } message: {
            Text("This will permanently delete \(orphanCount) audio files (\(formattedSize(orphanSize))) that are not linked to any dictation. This cannot be undone.")
        }
    }

    // MARK: - Storage Overview

    private var storageOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OVERVIEW")
                .font(Theme.current.fontXSBold)
                .foregroundColor(.secondary)

            HStack(spacing: 24) {
                StatPill(icon: "text.bubble", value: "\(totalDictations)", label: "Dictations")
                StatPill(icon: "waveform", value: "\(totalAudioFiles)", label: "Audio Files")
                StatPill(icon: "internaldrive", value: storageSize, label: "Storage")
            }
        }
    }

    // MARK: - Maintenance Section

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MAINTENANCE")
                .font(Theme.current.fontXSBold)
                .foregroundColor(.secondary)

            // Prune Old Dictations
            MaintenanceCard(
                icon: "clock.badge.xmark",
                title: "Old Dictations",
                count: canPrune ? pruneCount : 0,
                detail: pruneDetailText,
                actionLabel: "Prune",
                actionColor: canPrune ? .orange : .secondary,
                isEnabled: canPrune
            ) {
                showPruneConfirm = true
            }

            // Orphaned Files
            MaintenanceCard(
                icon: "doc.badge.gearshape",
                title: "Orphaned Files",
                count: orphanCount,
                detail: orphanDetailText,
                actionLabel: "Clean",
                actionColor: orphanCount > 0 ? .orange : .secondary,
                isEnabled: orphanCount > 0
            ) {
                showOrphanConfirm = true
            }
        }
    }

    // MARK: - Computed Properties

    private var pruneDetailText: String {
        // Forever = no pruning
        if liveSettings.utteranceTTLHours == 0 {
            return "Retention set to Forever - no pruning"
        }
        guard pruneCount > 0 else {
            return "No dictations older than \(liveSettings.utteranceTTLHours / 24) days"
        }
        if let oldest = pruneOldestDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Oldest: \(formatter.localizedString(for: oldest, relativeTo: Date()))"
        }
        return "\(pruneCount) dictations to remove"
    }

    private var canPrune: Bool {
        liveSettings.utteranceTTLHours > 0 && pruneCount > 0
    }

    private var orphanDetailText: String {
        guard orphanCount > 0 else {
            return "All audio files are linked to dictations"
        }
        return "\(formattedSize(orphanSize)) of unlinked audio"
    }

    // MARK: - Actions

    private func refreshStats() {
        totalDictations = LiveDatabase.count()
        totalAudioFiles = AudioStorage.fileCount()

        Task {
            storageSize = await AudioStorage.formattedStorageSizeAsync()
        }

        refreshPrunePreview()
        refreshOrphanPreview()
    }

    private func refreshPrunePreview() {
        let preview = LiveDatabase.prunePreview(olderThanHours: liveSettings.utteranceTTLHours)
        pruneCount = preview.count
        pruneOldestDate = preview.oldestDate
        pruneNewestDate = preview.newestDate
    }

    private func refreshOrphanPreview() {
        let referenced = LiveDatabase.allAudioFilenames()
        let preview = AudioStorage.orphanedFilesPreview(referencedFilenames: referenced)
        orphanCount = preview.count
        orphanSize = preview.totalBytes
    }

    private func performPrune() {
        logger.info("Pruning \(pruneCount) old dictations")
        LiveDatabase.prune(olderThanHours: liveSettings.utteranceTTLHours)
        refreshStats()
    }

    private func performOrphanCleanup() {
        logger.info("Cleaning \(orphanCount) orphaned files")
        let referenced = LiveDatabase.allAudioFilenames()
        AudioStorage.pruneOrphanedFiles(referencedFilenames: referenced)
        refreshStats()
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Helper Views

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct RetentionPresetButton: View {
    let label: String
    let hours: Int
    @Binding var current: Int

    var isSelected: Bool { current == hours }

    var body: some View {
        Button(action: { current = hours }) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MaintenanceCard: View {
    let icon: String
    let title: String
    let count: Int
    let detail: String
    let actionLabel: String
    let actionColor: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(count > 0 ? .orange : .secondary)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange))
                    }
                }

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action Button
            Button(action: action) {
                Text(actionLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isEnabled ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isEnabled ? actionColor : Color.secondary.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.current.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(count > 0 ? Color.orange.opacity(0.3) : Theme.current.divider, lineWidth: 1)
                )
        )
    }
}

// MARK: - Cloud Settings

/// Cloud storage settings: sync configuration (future)
struct CloudSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "cloud",
                title: "CLOUD",
                subtitle: "Configure cloud sync and backup."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                // Placeholder content
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cloud Sync Coming Soon")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.primary)

                        Text("Sync your memos and dictations across devices with iCloud.")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Previews

#Preview("Database") {
    DatabaseSettingsView()
        .frame(width: 600, height: 500)
}

#Preview("Cloud") {
    CloudSettingsView()
        .frame(width: 600, height: 400)
}
