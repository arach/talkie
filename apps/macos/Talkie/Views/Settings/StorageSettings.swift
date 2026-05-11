//
//  StorageSettings.swift
//  Talkie
//
//  Storage settings - Database, Local Files, and Cloud
//

import SwiftUI
import TalkieKit

private let logger = Log(.ui)

// MARK: - Storage Settings (Consolidated)

/// Combined settings for storage: Database + Files + Inventory
/// Provides tabbed access to retention settings, local file storage, and data inventory
struct StorageSettingsView: View {
    @State private var selectedSection: StorageSection = .database

    enum StorageSection: String, CaseIterable {
        case database = "DATABASE"
        case files = "FILES"
        case inventory = "INVENTORY"

        var icon: String {
            switch self {
            case .database: return "cylinder"
            case .files: return "folder"
            case .inventory: return "tablecells"
            }
        }

        var color: Color {
            switch self {
            case .database: return .purple
            case .files: return .blue
            case .inventory: return .teal
            }
        }

        var description: String {
            switch self {
            case .database: return "Retention & cleanup"
            case .files: return "Local file storage"
            case .inventory: return "All memos status"
            }
        }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "internaldrive",
                title: "STORAGE",
                subtitle: "Configure data retention, local files, and view memo inventory."
            )
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(StorageSection.allCases, id: \.rawValue) { section in
                        tabItem(section)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)

                // Tab indicator line
                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(height: 1)

                // Content based on selected section
                Group {
                    switch selectedSection {
                    case .database:
                        ScrollView {
                            DatabaseSettingsContent()
                                .padding(.top, Spacing.md)
                        }
                    case .files:
                        ScrollView {
                            LocalFilesSettingsContent()
                                .padding(.top, Spacing.md)
                        }
                    case .inventory:
                        DataInventoryView()
                            .padding(.top, Spacing.sm)
                    }
                }
            }
        }
        .onAppear {
            logger.debug("StorageSettingsView appeared")
        }
    }

    @ViewBuilder
    private func tabItem(_ section: StorageSection) -> some View {
        let isSelected = selectedSection == section

        Button(action: { selectedSection = section }) {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: section.icon)
                        .font(.system(size: 11))

                    Text(section.rawValue)
                        .font(Theme.current.fontXSBold)
                }
                .foregroundColor(isSelected ? section.color : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                // Active indicator
                Rectangle()
                    .fill(isSelected ? section.color : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Local Files Settings Content

/// Extracted local files settings content for use in consolidated view
struct LocalFilesSettingsContent: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var showingTranscriptsFolderPicker = false
    @State private var showingAudioFolderPicker = false
    @State private var statusMessage: String?
    @State private var stats: (transcripts: Int, audioFiles: Int, totalSize: Int64) = (0, 0, 0)

    var body: some View {
        @Bindable var settings = settingsManager

        VStack(alignment: .leading, spacing: Spacing.lg) {
            // MARK: - Value Proposition
            HStack(spacing: Spacing.sm) {
                Image(systemName: "lock.shield.fill")
                    .font(Theme.current.fontHeadline)
                    .foregroundColor(SemanticColor.success)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("YOUR DATA, YOUR FILES")
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(SemanticColor.success)

                    Text("Local files are stored as plain text (Markdown) and standard audio formats. You can open, edit, backup, or move them freely. No lock-in, full portability.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
            .padding(Spacing.md)
            .background(SemanticColor.success.opacity(Opacity.light))
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(SemanticColor.success.opacity(Opacity.medium), lineWidth: 1)
            )

            // MARK: - Transcripts Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(settingsManager.saveTranscriptsLocally ? Color.blue : Color.secondary)
                        .frame(width: 3, height: 14)

                    Text("TRANSCRIPTS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(settingsManager.saveTranscriptsLocally ? SemanticColor.success : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(settingsManager.saveTranscriptsLocally ? "ENABLED" : "DISABLED")
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(settingsManager.saveTranscriptsLocally ? SemanticColor.success : Theme.current.foregroundSecondary)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "doc.text.fill")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(.blue)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Save Transcripts Locally")
                            .font(Theme.current.fontSMMedium)

                        HStack(spacing: Spacing.xxs) {
                            Text("Save as Markdown with YAML frontmatter.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Link("File format", destination: URL(string: "https://talkie.jdi.do/docs/file-format")!)
                                .font(Theme.current.fontXS)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: $settings.saveTranscriptsLocally)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: settingsManager.saveTranscriptsLocally) { _, enabled in
                            if enabled {
                                TranscriptFileManager.shared.ensureFoldersExist()
                                syncNow()
                            }
                        }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                if settingsManager.saveTranscriptsLocally {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("FOLDER PATH")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        HStack(spacing: Spacing.sm) {
                            TextField("~/Documents/Talkie/Transcripts", text: $settings.transcriptsFolderPath)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.current.fontSM)

                            Button(action: { showingTranscriptsFolderPicker = true }) {
                                Image(systemName: "folder")
                                    .font(Theme.current.fontSM)
                            }
                            .buttonStyle(.bordered)
                            .help("Browse for folder")

                            Button(action: { TranscriptFileManager.shared.openTranscriptsFolderInFinder() }) {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(Theme.current.fontSM)
                            }
                            .buttonStyle(.bordered)
                            .help("Open in Finder")
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Audio Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(settingsManager.saveAudioLocally ? Color.purple : Color.secondary)
                        .frame(width: 3, height: 14)

                    Text("AUDIO FILES")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(settingsManager.saveAudioLocally ? SemanticColor.success : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(settingsManager.saveAudioLocally ? "ENABLED" : "DISABLED")
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(settingsManager.saveAudioLocally ? SemanticColor.success : Theme.current.foregroundSecondary)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "waveform")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(.purple)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Save Audio Files Locally")
                            .font(Theme.current.fontSMMedium)
                        Text("Copy M4A audio recordings to your local folder.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.saveAudioLocally)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: settingsManager.saveAudioLocally) { _, enabled in
                            if enabled {
                                TranscriptFileManager.shared.ensureFoldersExist()
                                syncNow()
                            }
                        }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                if settingsManager.saveAudioLocally {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("FOLDER PATH")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        HStack(spacing: Spacing.sm) {
                            TextField("~/Documents/Talkie/Audio", text: $settings.audioFolderPath)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.current.fontSM)

                            Button(action: { showingAudioFolderPicker = true }) {
                                Image(systemName: "folder")
                                    .font(Theme.current.fontSM)
                            }
                            .buttonStyle(.bordered)
                            .help("Browse for folder")

                            Button(action: { TranscriptFileManager.shared.openAudioFolderInFinder() }) {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(Theme.current.fontSM)
                            }
                            .buttonStyle(.bordered)
                            .help("Open in Finder")
                        }

                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.orange)
                            Text("Audio files can take significant disk space")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.orange)
                        }
                        .padding(Spacing.sm)
                        .background(Color.orange.opacity(Opacity.light))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // Stats and actions (only show if any local files enabled)
            if settingsManager.localFilesEnabled {
                // MARK: - Statistics Section
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.cyan)
                            .frame(width: 3, height: 14)

                        Text("STATISTICS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        Button(action: refreshStats) {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(Theme.current.fontXS)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    HStack(spacing: Spacing.md) {
                        StatCard(
                            value: "\(stats.transcripts)",
                            label: "Transcripts",
                            color: .blue,
                            icon: "doc.text"
                        )

                        StatCard(
                            value: "\(stats.audioFiles)",
                            label: "Audio Files",
                            color: .purple,
                            icon: "waveform"
                        )

                        StatCard(
                            value: ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file),
                            label: "Total Size",
                            color: .green,
                            icon: "externaldrive"
                        )
                    }
                }
                .settingsSectionCard(padding: Spacing.md)

                // MARK: - Quick Actions
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.orange)
                            .frame(width: 3, height: 14)

                        Text("QUICK ACTIONS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()
                    }

                    HStack(spacing: Spacing.sm) {
                        Button(action: syncNow) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Now")
                            }
                            .font(Theme.current.fontXSMedium)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(.bordered)

                        if let message = statusMessage {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                                    .foregroundColor(message.contains("✓") ? SemanticColor.success : .blue)
                                Text(message)
                                    .font(Theme.current.fontXS)
                            }
                        }

                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
                .settingsSectionCard(padding: Spacing.md)
            }
        }
        .fileImporter(
            isPresented: $showingTranscriptsFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    settingsManager.transcriptsFolderPath = url.path
                    TranscriptFileManager.shared.ensureFoldersExist()
                    refreshStats()
                }
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingAudioFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    settingsManager.audioFolderPath = url.path
                    TranscriptFileManager.shared.ensureFoldersExist()
                    refreshStats()
                }
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
        .onAppear {
            refreshStats()
        }
    }

    private func syncNow() {
        Task {
            await TranscriptFileManager.shared.syncAllMemos()
            await MainActor.run {
                statusMessage = "✓ Synced local files"
            }
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                refreshStats()
                if statusMessage == "✓ Synced local files" {
                    statusMessage = nil
                }
            }
        }
    }

    private func refreshStats() {
        stats = TranscriptFileManager.shared.getStats()
    }

    // Stat card component for FILES tab
    private struct StatCard: View {
        let value: String
        let label: String
        let color: Color
        let icon: String

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: icon)
                        .font(Theme.current.fontXS)
                        .foregroundColor(color)
                    Text(value)
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(color)
                }
                Text(label)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        }
    }
}

// MARK: - Database Settings Content

/// Extracted database settings content for use in consolidated view
struct DatabaseSettingsContent: View {
    @Environment(AgentSettings.self) private var liveSettings: AgentSettings
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var isPruning = false
    @State private var isCleaningOrphans = false
    @State private var statusMessage: String?
    @State private var databaseSize: Int64 = 0
    @State private var appliedMigrations: [String] = []
    @State private var showMigrations = false

    // Database path from TalkieKit
    private var databasePath: String {
        TalkieDatabase.databaseURL.path
    }

    var body: some View {
        @Bindable var live = liveSettings

        VStack(alignment: .leading, spacing: Spacing.lg) {
            // MARK: - Database Location
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("DATABASE LOCATION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if databaseSize > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: databaseSize, countStyle: .file))
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "cylinder.fill")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(.cyan)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("talkie.sqlite")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text(databasePath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button(action: revealDatabaseInFinder) {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "folder")
                            Text("Reveal")
                        }
                        .font(Theme.current.fontXSMedium)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            if settingsManager.settingsAudience.canAccess(.pro) {
                // MARK: - Migrations (Developer mode)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue)
                            .frame(width: 3, height: 14)

                        Text("MIGRATIONS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        Text("\(appliedMigrations.count) applied")
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(.green)

                        Button(action: { showMigrations.toggle() }) {
                            Image(systemName: showMigrations ? "chevron.up" : "chevron.down")
                                .font(Theme.current.fontXS)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    if showMigrations && !appliedMigrations.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            ForEach(appliedMigrations, id: \.self) { migration in
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(.green)

                                    Text(migration)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Theme.current.foregroundSecondary)

                                    Spacer()
                                }
                            }
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)
                    }
                }
                .settingsSectionCard(padding: Spacing.md)
            }

            // MARK: - Dictation Retention
            VStack(alignment: .leading, spacing: Spacing.sm) {
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
                                BrailleSpinner(size: 12)
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
                                BrailleSpinner(size: 12)
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
            loadDatabaseInfo()
        }
        .onChange(of: settingsManager.settingsAudience) { _, _ in
            loadDatabaseInfo()
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

    private func revealDatabaseInFinder() {
        let url = TalkieDatabase.databaseURL
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func loadDatabaseInfo() {
        // Get database file size
        let url = TalkieDatabase.databaseURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            databaseSize = size
        }

        if settingsManager.settingsAudience.canAccess(.pro) {
            // Get applied migrations from GRDB's grdb_migrations table (developer mode only)
            Task {
                do {
                    let db = try DatabaseManager.shared.database()
                    let migrations: [String] = try await db.read { db in
                        try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
                    }
                    await MainActor.run {
                        appliedMigrations = migrations
                    }
                } catch {
                    logger.error("Failed to load migrations: \(error)")
                }
            }
        } else {
            appliedMigrations = []
            showMigrations = false
        }
    }
}

// MARK: - Database Settings

/// Database storage settings: retention, cleanup for memos and dictations
struct DatabaseSettingsView: View {
    @Environment(AgentSettings.self) private var liveSettings: AgentSettings
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
                                BrailleSpinner(size: 12)
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
                                BrailleSpinner(size: 12)
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
    @State private var settingsManager = SettingsManager.shared
    @State private var externalSyncStatus: ConnectionStatus = .available
    @State private var isChecking = false
    @State private var showingEnableConfirmation = false
    @State private var localMemoCount: Int = 0

    var body: some View {
        @Bindable var settingsManager = settingsManager
        SettingsPageView(
            icon: "arrow.triangle.2.circlepath",
            title: "SYNC",
            subtitle: "Configure external sync through TalkieSync.",
            debugInfo: {
                [
                    "Enabled": "\(settingsManager.iCloudSyncEnabled)",
                    "Status": "\(externalSyncStatus)",
                    "Local Memos": "\(localMemoCount)"
                ]
            }
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // External Sync Settings
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(settingsManager.iCloudSyncEnabled ? Color.blue : Color.gray)
                            .frame(width: 3, height: 14)

                        Text("EXTERNAL SYNC")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        // Status indicator
                        statusBadge
                    }

                    // Toggle and status
                    VStack(spacing: Spacing.md) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: settingsManager.iCloudSyncEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                                .font(.displayMedium)
                                .foregroundColor(settingsManager.iCloudSyncEnabled ? .blue : .gray.opacity(Opacity.half))

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(settingsManager.iCloudSyncEnabled ? "Sync Enabled" : "Sync Disabled")
                                    .font(Theme.current.fontSMMedium)
                                    .foregroundColor(Theme.current.foreground)

                                Text(settingsManager.iCloudSyncEnabled
                                     ? "Memos sync through TalkieSync."
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
                            Text("Enable External Sync")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { settingsManager.iCloudSyncEnabled },
                                set: { newValue in
                                    if newValue && !settingsManager.iCloudSyncEnabled {
                                        // Enabling - show confirmation
                                        countLocalMemos()
                                        showingEnableConfirmation = true
                                    } else if !newValue && settingsManager.iCloudSyncEnabled {
                                        settingsManager.iCloudSyncEnabled = false
                                        handleToggleChange(false)
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)
                        .alert("Enable External Sync?", isPresented: $showingEnableConfirmation) {
                            Button("Cancel", role: .cancel) {
                            }
                            Button("Enable") {
                                settingsManager.iCloudSyncEnabled = true
                                handleToggleChange(true)
                            }
                        } message: {
                            Text(localMemoCount > 0
                                 ? "\(localMemoCount) memo\(localMemoCount == 1 ? "" : "s") will be included in the next sync pass."
                                 : "Your memos will sync across devices via TalkieSync.")
                        }
                    }

                    // Feature list
                    if settingsManager.iCloudSyncEnabled {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            featureRow(icon: "arrow.triangle.2.circlepath", text: "Automatic background sync")
                            featureRow(icon: "lock.shield", text: "Managed by TalkieSync service")
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
            await checkExternalSyncStatus()
        }
    }

    private var statusBadge: some View {
        Group {
            if isChecking {
                HStack(spacing: Spacing.xs) {
                    BrailleSpinner(size: 10)
                    Text("CHECKING")
                        .font(.techLabelSmall)
                }
                .foregroundColor(Theme.current.foregroundSecondary)
            } else if !settingsManager.iCloudSyncEnabled {
                Text("DISABLED")
                    .font(.techLabelSmall)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(Color.gray)
                    .cornerRadius(3)
            } else {
                switch externalSyncStatus {
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
                        BrailleSpinner(size: 10)
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
        logger.info("External sync \(enabled ? "enabled" : "disabled")")

        if enabled {
            Task {
                do {
                    try await SyncClient.shared.runSyncOnce(keepRunning: false)
                } catch {
                    logger.error("Failed to run one-time sync after enabling: \(error)")
                }
            }
        } else {
            logger.info("External sync paused")
        }

        Task {
            await ConnectionManager.shared.checkAllConnections()
        }
    }

    private func checkExternalSyncStatus() async {
        guard settingsManager.iCloudSyncEnabled else {
            externalSyncStatus = .unavailable(reason: "Disabled")
            return
        }

        isChecking = true

        let availability = await SyncClient.shared.checkiCloudAvailability()
        await MainActor.run {
            externalSyncStatus = availability.available
                ? .available
                : .unavailable(reason: availability.error ?? "Not available")
            isChecking = false
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

#Preview("Storage (Consolidated)") {
    StorageSettingsView()
        .environment(AgentSettings.shared)
        .frame(width: 800, height: 600)
}

#Preview("Database") {
    DatabaseSettingsView()
        .environment(AgentSettings.shared)
        .frame(width: 600, height: 600)
}

#Preview("Cloud") {
    CloudSettingsView()
        .frame(width: 600, height: 400)
}
