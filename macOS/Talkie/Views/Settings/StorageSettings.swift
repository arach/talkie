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
                // Dictation Retention
                VStack(alignment: .leading, spacing: 12) {
                    Text("DICTATION RETENTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Dictations older than this will be automatically deleted.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    HStack {
                        Stepper(
                            value: $live.utteranceTTLHours,
                            in: 1...720,
                            step: 24
                        ) {
                            Text("\(live.utteranceTTLHours) hours (\(live.utteranceTTLHours / 24) days)")
                                .font(SettingsManager.shared.fontSM)
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

                // Cleanup Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("CLEANUP")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button(action: {
                            logger.info("Prune old dictations requested")
                            // TODO: Implement prune
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("PRUNE OLD")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            logger.info("Clean orphaned files requested")
                            // TODO: Implement orphan cleanup
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.badge.gearshape")
                                    .font(.system(size: 10))
                                Text("CLEAN ORPHANS")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            logger.debug("DatabaseSettingsView appeared")
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
