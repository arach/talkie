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
            // Value proposition - always visible
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(Theme.current.fontSM)
                            .foregroundColor(.green)
                        Text("YOUR DATA, YOUR FILES")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.green)
                    }

                    Text("Local files are stored as plain text (Markdown) and standard audio formats. You can open, edit, backup, or move them freely. No lock-in, full portability.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color.green.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )

                Divider()

                // MARK: - Transcripts Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settings.saveTranscriptsLocally) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(.blue)
                                Text("Save Transcripts Locally")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            HStack(spacing: 4) {
                                Text("Save as Markdown with YAML frontmatter.")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(.secondary)
                                Link("File format", destination: URL(string: "https://talkie.jdi.do/docs/file-format")!)
                                    .font(Theme.current.fontXS)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(settingsManager.resolvedAccentColor)
                    .onChange(of: settingsManager.saveTranscriptsLocally) { _, enabled in
                        if enabled {
                            TranscriptFileManager.shared.ensureFoldersExist()
                            syncNow()
                        }
                    }

                    if settingsManager.saveTranscriptsLocally {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TRANSCRIPTS FOLDER")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
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
                        .padding(.leading, 24)
                    }
                }
                .padding(16)
                .background(Theme.current.surface2)
                .cornerRadius(8)

                // MARK: - Audio Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settings.saveAudioLocally) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(.purple)
                                Text("Save Audio Files Locally")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            Text("Copy M4A audio recordings to your local folder.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(settingsManager.resolvedAccentColor)
                    .onChange(of: settingsManager.saveAudioLocally) { _, enabled in
                        if enabled {
                            TranscriptFileManager.shared.ensureFoldersExist()
                            syncNow()
                        }
                    }

                    if settingsManager.saveAudioLocally {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AUDIO FOLDER")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
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
                        .padding(.leading, 24)
                    }
                }
                .padding(16)
                .background(Theme.current.surface2)
                .cornerRadius(8)

                // Stats and actions (only show if any local files enabled)
                if settingsManager.localFilesEnabled {
                    Divider()

                    // Stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FILE STATISTICS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(stats.transcripts)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                Text("Transcripts")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(stats.audioFiles)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.purple)
                                Text("Audio Files")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                Text("Total Size")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.current.surface2)
                        .cornerRadius(8)
                    }

                    // Quick actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QUICK ACTIONS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button(action: syncNow) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Sync Now")
                                }
                                .font(Theme.current.fontXS)
                            }
                            .buttonStyle(.bordered)

                            Button(action: refreshStats) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh Stats")
                                }
                                .font(Theme.current.fontXS)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Status message
                    if let message = statusMessage {
                        HStack(spacing: 6) {
                            Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                                .foregroundColor(message.contains("✓") ? .green : .blue)
                            Text(message)
                                .font(Theme.current.fontXS)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
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

