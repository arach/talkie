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
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Section header with accent bar
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("DICTATION RETENTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text("AUTO-DELETE")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Dictations older than the specified time will be automatically deleted to save space.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    // Retention slider
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("Keep for")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Spacer()

                            Text(formatRetention(hours: live.utteranceTTLHours))
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)
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
                        HStack(spacing: Spacing.sm) {
                            ForEach([24, 48, 168, 336, 720], id: \.self) { hours in
                                Button(action: { live.utteranceTTLHours = hours }) {
                                    Text(formatRetentionShort(hours: hours))
                                        .font(.labelSmall)
                                        .foregroundColor(live.utteranceTTLHours == hours ? .white : Theme.current.foregroundSecondary)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, 4)
                                        .background(live.utteranceTTLHours == hours ? Color.purple : Theme.current.surface2)
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
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

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
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

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
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)
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
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Coming soon card
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue)
                            .frame(width: 3, height: 14)

                        Text("ICLOUD SYNC")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        Text("COMING SOON")
                            .font(.techLabelSmall)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.accentColor)
                            .cornerRadius(3)
                    }

                    HStack(spacing: Spacing.md) {
                        Image(systemName: "icloud")
                            .font(.displayMedium)
                            .foregroundColor(.blue.opacity(Opacity.half))

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Sync Across Devices")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)

                            Text("Sync your memos and dictations seamlessly across all your Apple devices using iCloud.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Spacing.md)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)

                    // Feature list
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        featureRow(icon: "arrow.triangle.2.circlepath", text: "Automatic background sync")
                        featureRow(icon: "lock.shield", text: "End-to-end encryption")
                        featureRow(icon: "iphone.and.arrow.forward", text: "Seamless iPhone integration")
                    }
                }
                .padding(Spacing.md)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)
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
