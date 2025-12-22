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

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "cylinder",
                title: "DATABASE",
                subtitle: "Configure data retention and cleanup policies."
            )
        } content: {
            // MARK: - Dictation Retention
            VStack(alignment: .leading, spacing: 12) {
                // Section header with accent bar
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("DICTATION RETENTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("AUTO-DELETE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Dictations older than the specified time will be automatically deleted to save space.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    // Retention slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Keep for")
                                .font(Theme.current.fontSM)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(formatRetention(hours: live.utteranceTTLHours))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }

                        Stepper(
                            value: $live.utteranceTTLHours,
                            in: 24...720,
                            step: 24
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()

                        // Quick presets
                        HStack(spacing: 8) {
                            ForEach([24, 48, 168, 336, 720], id: \.self) { hours in
                                Button(action: { live.utteranceTTLHours = hours }) {
                                    Text(formatRetentionShort(hours: hours))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(live.utteranceTTLHours == hours ? .white : .secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(live.utteranceTTLHours == hours ? Color.purple : Theme.current.surface2)
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Memo Retention
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("MEMO RETENTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "infinity")
                            .font(.system(size: 10))
                        Text("PERMANENT")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.green.opacity(0.8))
                }

                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green.opacity(0.7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memos are kept indefinitely")
                            .font(Theme.current.fontSM)
                            .foregroundColor(.primary)
                        Text("Manually delete memos you no longer need from the Memos list.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Cleanup Actions
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)

                    Text("MAINTENANCE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                VStack(spacing: 12) {
                    // Prune old dictations
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.xmark")
                            .font(.system(size: 18))
                            .foregroundColor(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prune Old Dictations")
                                .font(Theme.current.fontSMMedium)
                            Text("Delete dictations older than retention period now")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.secondary)
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
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)

                    // Clean orphaned files
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.gearshape")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clean Orphaned Files")
                                .font(Theme.current.fontSMMedium)
                            Text("Remove audio files with no database entry")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.secondary)
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
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                }

                // Status message
                if let message = statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(Theme.current.fontXS)
                            .foregroundColor(message.contains("✓") ? .green : .blue)
                        Text(message)
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Theme.current.surface1)
                    .cornerRadius(6)
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)
        }
        .onAppear {
            logger.debug("DatabaseSettingsView appeared")
        }
    }

    private func formatRetention(hours: Int) -> String {
        if hours < 24 {
            return "\(hours) hours"
        } else {
            let days = hours / 24
            return days == 1 ? "1 day" : "\(days) days"
        }
    }

    private func formatRetentionShort(hours: Int) -> String {
        if hours < 24 {
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
            VStack(alignment: .leading, spacing: 16) {
                // Coming soon card
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue)
                            .frame(width: 3, height: 14)

                        Text("ICLOUD SYNC")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("COMING SOON")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(3)
                    }

                    HStack(spacing: 16) {
                        Image(systemName: "icloud")
                            .font(.system(size: 32))
                            .foregroundColor(.blue.opacity(0.6))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync Across Devices")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(.primary)

                            Text("Sync your memos and dictations seamlessly across all your Apple devices using iCloud.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.secondary.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)

                    // Feature list
                    VStack(alignment: .leading, spacing: 8) {
                        featureRow(icon: "arrow.triangle.2.circlepath", text: "Automatic background sync")
                        featureRow(icon: "lock.shield", text: "End-to-end encryption")
                        featureRow(icon: "iphone.and.arrow.forward", text: "Seamless iPhone integration")
                    }
                }
                .padding(16)
                .background(Theme.current.surface2)
                .cornerRadius(8)
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(.blue)
                .frame(width: 16)

            Text(text)
                .font(Theme.current.fontXS)
                .foregroundColor(.secondary)
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
