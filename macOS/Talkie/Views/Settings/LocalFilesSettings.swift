//
//  LocalFilesSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Local Files Settings View

struct LocalFilesSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var showingTranscriptsFolderPicker = false
    @State private var showingAudioFolderPicker = false
    @State private var statusMessage: String?
    @State private var stats: (transcripts: Int, audioFiles: Int, totalSize: Int64) = (0, 0, 0)

    var body: some View {
        @Bindable var settings = settingsManager

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "folder.badge.person.crop",
                title: "LOCAL FILES",
                subtitle: "Store your transcripts and audio files locally on your Mac."
            )
        } content: {
            // MARK: - Value Proposition
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR DATA, YOUR FILES")
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(.green)

                    Text("Local files are stored as plain text (Markdown) and standard audio formats. You can open, edit, backup, or move them freely. No lock-in, full portability.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
            )

            // MARK: - Transcripts Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(settingsManager.saveTranscriptsLocally ? Color.blue : Color.secondary)
                        .frame(width: 3, height: 14)

                    Text("TRANSCRIPTS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(settingsManager.saveTranscriptsLocally ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(settingsManager.saveTranscriptsLocally ? "ENABLED" : "DISABLED")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(settingsManager.saveTranscriptsLocally ? .green : .secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save Transcripts Locally")
                            .font(Theme.current.fontSMMedium)

                        HStack(spacing: 4) {
                            Text("Save as Markdown with YAML frontmatter.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.secondary)
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
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)

                if settingsManager.saveTranscriptsLocally {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOLDER PATH")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("~/Documents/Talkie/Transcripts", text: $settings.transcriptsFolderPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

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
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Audio Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(settingsManager.saveAudioLocally ? Color.purple : Color.secondary)
                        .frame(width: 3, height: 14)

                    Text("AUDIO FILES")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(settingsManager.saveAudioLocally ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(settingsManager.saveAudioLocally ? "ENABLED" : "DISABLED")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(settingsManager.saveAudioLocally ? .green : .secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 20))
                        .foregroundColor(.purple)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save Audio Files Locally")
                            .font(Theme.current.fontSMMedium)
                        Text("Copy M4A audio recordings to your local folder.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary)
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
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)

                if settingsManager.saveAudioLocally {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOLDER PATH")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("~/Documents/Talkie/Audio", text: $settings.audioFolderPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

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

                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.orange)
                            Text("Audio files can take significant disk space")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // Stats and actions (only show if any local files enabled)
            if settingsManager.localFilesEnabled {
                // MARK: - Statistics Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.cyan)
                            .frame(width: 3, height: 14)

                        Text("STATISTICS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: refreshStats) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(Theme.current.fontXS)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }

                    HStack(spacing: 16) {
                        LocalFilesStatCard(
                            value: "\(stats.transcripts)",
                            label: "Transcripts",
                            color: .blue,
                            icon: "doc.text"
                        )

                        LocalFilesStatCard(
                            value: "\(stats.audioFiles)",
                            label: "Audio Files",
                            color: .purple,
                            icon: "waveform"
                        )

                        LocalFilesStatCard(
                            value: ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file),
                            label: "Total Size",
                            color: .green,
                            icon: "externaldrive"
                        )
                    }
                }
                .padding(16)
                .background(Theme.current.surface2)
                .cornerRadius(8)

                // MARK: - Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.orange)
                            .frame(width: 3, height: 14)

                        Text("QUICK ACTIONS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button(action: syncNow) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Now")
                            }
                            .font(Theme.current.fontXSMedium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)

                        if let message = statusMessage {
                            HStack(spacing: 6) {
                                Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                                    .foregroundColor(message.contains("✓") ? .green : .blue)
                                Text(message)
                                    .font(Theme.current.fontXS)
                            }
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                }
                .padding(16)
                .background(Theme.current.surface2)
                .cornerRadius(8)
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
        let context = PersistenceController.shared.container.viewContext
        TranscriptFileManager.shared.syncAllMemos(context: context)
        statusMessage = "✓ Synced local files"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            refreshStats()
            if statusMessage == "✓ Synced local files" {
                statusMessage = nil
            }
        }
    }

    private func refreshStats() {
        stats = TranscriptFileManager.shared.getStats()
    }
}

// MARK: - Local Files Stat Card Component
private struct LocalFilesStatCard: View {
    let value: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Theme.current.fontXS)
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
            Text(label)
                .font(Theme.current.fontXS)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.current.surface1)
        .cornerRadius(8)
    }
}

