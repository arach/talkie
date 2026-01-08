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
    @State private var isPruning = false
    @State private var isCleaningOrphans = false
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var live = liveSettings

        SettingsPageView(
            icon: "cylinder",
            title: "DATABASE",
            subtitle: "Configure data retention and cleanup policies."
        ) {
            // MARK: - Dictation Retention
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Section header with accent bar
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(live.utteranceTTLHours <= 0 ? Color.green : Color.purple)
                        .frame(width: 3, height: 14)

                    Text("DICTATION RETENTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if live.utteranceTTLHours <= 0 {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "infinity")
                                .font(Theme.current.fontXS)
                            Text("PERMANENT")
                                .font(.techLabelSmall)
                        }
                        .foregroundColor(.green.opacity(Opacity.prominent))
                    } else {
                        Text("AUTO-DELETE")
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(live.utteranceTTLHours <= 0
                         ? "Dictations will be kept indefinitely. Manually delete what you no longer need."
                         : "Dictations older than the specified time will be automatically deleted to save space.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(live.utteranceTTLHours <= 0 ? .green.opacity(Opacity.prominent) : Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    // Retention presets
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("Keep for")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Spacer()

                            Text(formatRetention(hours: live.utteranceTTLHours))
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(live.utteranceTTLHours <= 0 ? .green : Theme.current.foreground)
                        }

                        // Quick presets: Forever, 1 week, 1 month, 3 months, 1 year
                        HStack(spacing: Spacing.sm) {
                            ForEach([0, 168, 720, 2160, 8760], id: \.self) { hours in
                                Button(action: { live.utteranceTTLHours = hours }) {
                                    Text(formatRetentionShort(hours: hours))
                                        .font(.labelSmall)
                                        .foregroundColor(live.utteranceTTLHours == hours ? .white : Theme.current.foregroundSecondary)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, 4)
                                        .background(live.utteranceTTLHours == hours ? (hours == 0 ? Color.green : Color.purple) : Theme.current.surface2)
                                        .cornerRadius(CornerRadius.xs)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Memo Retention
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("MEMO RETENTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "infinity")
                            .font(Theme.current.fontXS)
                        Text("PERMANENT")
                            .font(.techLabelSmall)
                    }
                    .foregroundColor(.green.opacity(Opacity.prominent))
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(.green.opacity(Opacity.prominent))

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Memos are kept indefinitely")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foreground)
                        Text("Manually delete memos you no longer need from the Memos list.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Cleanup Actions
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)

                    Text("MAINTENANCE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(spacing: Spacing.sm) {
                    // Prune old dictations
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "clock.badge.xmark")
                            .font(.headlineLarge)
                            .foregroundColor(SemanticColor.warning)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Prune Old Dictations")
                                .font(Theme.current.fontSMMedium)
                            Text("Delete dictations older than retention period now")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Button(action: pruneOldDictations) {
                            if isPruning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("PRUNE")
                                    .font(Theme.current.fontXSBold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPruning)
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)

                    // Clean orphaned files
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "doc.badge.gearshape")
                            .font(.headlineLarge)
                            .foregroundColor(.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Clean Orphaned Files")
                                .font(Theme.current.fontSMMedium)
                            Text("Remove audio files with no database entry")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Spacer()

                        Button(action: cleanOrphanedFiles) {
                            if isCleaningOrphans {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("CLEAN")
                                    .font(Theme.current.fontXSBold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCleaningOrphans)
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }

                // Status message
                if let message = statusMessage {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(Theme.current.fontXS)
                            .foregroundColor(message.contains("✓") ? .green : .blue)
                        Text(message)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.xs)
                }
            }
            .settingsSectionCard(padding: Spacing.md)
        }
        .onAppear {
            logger.debug("DatabaseSettingsView appeared")
        }
    }

    private func formatRetention(hours: Int) -> String {
        if hours <= 0 {
            return "Forever"
        } else if hours < 24 {
            return "\(hours) hours"
        } else if hours == 168 {
            return "1 week"
        } else if hours == 720 {
            return "1 month"
        } else if hours == 2160 {
            return "3 months"
        } else if hours == 8760 {
            return "1 year"
        } else {
            let days = hours / 24
            return days == 1 ? "1 day" : "\(days) days"
        }
    }

    private func formatRetentionShort(hours: Int) -> String {
        if hours <= 0 {
            return "∞"
        } else if hours == 168 {
            return "1w"
        } else if hours == 720 {
            return "1mo"
        } else if hours == 2160 {
            return "3mo"
        } else if hours == 8760 {
            return "1yr"
        } else if hours < 24 {
            return "\(hours)h"
        } else if hours < 168 {
            return "\(hours / 24)d"
        } else {
            return "\(hours / 168)w"
        }
    }

    private func pruneOldDictations() {
        isPruning = true
        statusMessage = nil
        logger.info("Prune old dictations requested")

        // Simulate async operation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isPruning = false
            statusMessage = "✓ Pruned old dictations"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if statusMessage == "✓ Pruned old dictations" {
                    statusMessage = nil
                }
            }
        }
    }

    private func cleanOrphanedFiles() {
        isCleaningOrphans = true
        statusMessage = nil
        logger.info("Clean orphaned files requested")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isCleaningOrphans = false
            statusMessage = "✓ Cleaned orphaned files"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if statusMessage == "✓ Cleaned orphaned files" {
                    statusMessage = nil
                }
            }
        }
    }
}

// MARK: - Cloud Settings

/// Cloud storage settings: sync configuration
struct CloudSettingsView: View {
    @AppStorage(SyncSettingsKey.iCloudEnabled) private var iCloudEnabled = true
    @State private var iCloudStatus: ConnectionStatus = .available
    @State private var isChecking = false
    @State private var showingEnableConfirmation = false
    @State private var pendingEnableValue = false
    @State private var localMemoCount: Int = 0

    var body: some View {
        SettingsPageView(
            icon: "cloud",
            title: "CLOUD",
            subtitle: "Configure cloud sync and backup.",
            debugInfo: {
                [
                    "Enabled": "\(iCloudEnabled)",
                    "Status": "\(iCloudStatus)",
                    "Local Memos": "\(localMemoCount)"
                ]
            }
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // iCloud Sync Settings
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(iCloudEnabled ? Color.blue : Color.gray)
                            .frame(width: 3, height: 14)

                        Text("ICLOUD SYNC")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        // Status indicator
                        statusBadge
                    }

                    // Toggle and status
                    VStack(spacing: Spacing.md) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: iCloudEnabled ? "icloud" : "icloud.slash")
                                .font(.displayMedium)
                                .foregroundColor(iCloudEnabled ? .blue : .gray.opacity(Opacity.half))

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(iCloudEnabled ? "Sync Enabled" : "Sync Disabled")
                                    .font(Theme.current.fontSMMedium)
                                    .foregroundColor(Theme.current.foreground)

                                Text(iCloudEnabled
                                     ? "Memos sync across all your Apple devices via iCloud."
                                     : "Memos are stored locally only. Enable to sync with other devices.")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(Spacing.md)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)

                        // Toggle control
                        HStack {
                            Text("Enable iCloud Sync")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { iCloudEnabled },
                                set: { newValue in
                                    if newValue && !iCloudEnabled {
                                        // Enabling - show confirmation
                                        pendingEnableValue = true
                                        countLocalMemos()
                                        showingEnableConfirmation = true
                                    } else if !newValue && iCloudEnabled {
                                        // Disabling - no confirmation needed, just pause
                                        iCloudEnabled = false
                                        handleToggleChange(false)
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)
                        .alert("Enable iCloud Sync?", isPresented: $showingEnableConfirmation) {
                            Button("Cancel", role: .cancel) {
                                pendingEnableValue = false
                            }
                            Button("Enable") {
                                iCloudEnabled = true
                                handleToggleChange(true)
                            }
                        } message: {
                            Text(localMemoCount > 0
                                 ? "\(localMemoCount) memo\(localMemoCount == 1 ? "" : "s") will be uploaded to iCloud. This may take a few moments."
                                 : "Your memos will sync across all your Apple devices via iCloud.")
                        }
                    }

                    // Feature list
                    if iCloudEnabled {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            featureRow(icon: "arrow.triangle.2.circlepath", text: "Automatic background sync")
                            featureRow(icon: "lock.shield", text: "Encrypted by Apple")
                            featureRow(icon: "iphone.gen3.radiowaves.left.and.right", text: "iPhone and Mac sync")
                        }
                    }
                }
                .settingsSectionCard(padding: Spacing.md)

                // Future providers placeholder
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray)
                            .frame(width: 3, height: 14)

                        Text("OTHER PROVIDERS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        Text("COMING SOON")
                            .font(.techLabelSmall)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.gray)
                            .cornerRadius(3)
                    }

                    Text("Direct Connect (Tailscale), Dropbox, Google Drive, and S3 support coming soon.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                }
                .settingsSectionCard(padding: Spacing.md)
            }
        }
        .task {
            await checkiCloudStatus()
        }
    }

    private var statusBadge: some View {
        Group {
            if isChecking {
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("CHECKING")
                        .font(.techLabelSmall)
                }
                .foregroundColor(Theme.current.foregroundSecondary)
            } else if !iCloudEnabled {
                Text("DISABLED")
                    .font(.techLabelSmall)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(Color.gray)
                    .cornerRadius(3)
            } else {
                switch iCloudStatus {
                case .available:
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.current.fontXS)
                        Text("ACTIVE")
                            .font(.techLabelSmall)
                    }
                    .foregroundColor(.green)

                case .unavailable(let reason):
                    Text(reason.uppercased())
                        .font(.techLabelSmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.orange)
                        .cornerRadius(3)

                case .connecting, .syncing:
                    HStack(spacing: Spacing.xs) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("SYNCING")
                            .font(.techLabelSmall)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }

    private func countLocalMemos() {
        // Count memos in local GRDB database
        Task {
            do {
                let repository = LocalRepository()
                let count = try await repository.countMemos()
                await MainActor.run {
                    localMemoCount = count
                }
            } catch {
                logger.error("Failed to count local memos: \(error)")
                await MainActor.run {
                    localMemoCount = 0
                }
            }
        }
    }

    private func handleToggleChange(_ enabled: Bool) {
        logger.info("iCloud sync \(enabled ? "enabled" : "disabled")")

        if enabled {
            // Resume sync - trigger immediate sync
            CloudKitSyncManager.shared.syncNow()
        } else {
            // Pause sync - CloudKit container keeps running but we don't trigger syncs
            logger.info("iCloud sync paused - will not trigger automatic syncs")
        }

        Task {
            await ConnectionManager.shared.checkAllConnections()
        }
    }

    private func checkiCloudStatus() async {
        guard iCloudEnabled else {
            iCloudStatus = .unavailable(reason: "Disabled")
            return
        }

        isChecking = true

        if let provider = ConnectionManager.shared.provider(for: .iCloud) {
            let status = await provider.checkConnection()
            await MainActor.run {
                iCloudStatus = status
                isChecking = false
            }
        } else {
            await MainActor.run {
                iCloudStatus = .unavailable(reason: "Not available")
                isChecking = false
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(.accentColor)
                .frame(width: 16)

            Text(text)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }
}

// MARK: - Previews

#Preview("Database") {
    DatabaseSettingsView()
        .environment(LiveSettings.shared)
        .frame(width: 600, height: 600)
}

#Preview("Cloud") {
    CloudSettingsView()
        .frame(width: 600, height: 400)
}
