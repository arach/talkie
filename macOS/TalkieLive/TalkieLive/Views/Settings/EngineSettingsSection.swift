//
//  EngineSettingsSection.swift
//  TalkieLive
//
//  Engine/Transcription settings: model management, service status
//

import SwiftUI
import TalkieKit

// MARK: - Transcription Settings Section

struct EngineSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @ObservedObject private var engineClient = EngineClient.shared
    @ObservedObject private var audioDevices = AudioDeviceManager.shared
    @StateObject private var whisperService = WhisperService.shared
    @State private var downloadingModelId: String?
    @State private var downloadTask: Task<Void, Never>?

    /// Group available models by family
    private var modelsByFamily: [String: [ModelInfo]] {
        Dictionary(grouping: engineClient.availableModels) { $0.family }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "waveform",
                title: "TRANSCRIPTION",
                subtitle: "Speech recognition models and settings."
            )
        } content: {
            // Service Status - simplified, user-friendly
            SettingsCard(title: "STATUS") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(engineStatusColor)
                                    .frame(width: 8, height: 8)
                                Text(engineClient.isConnected ? "Ready" : "Connecting...")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(TalkieTheme.textPrimary)
                            }

                            if engineClient.isConnected, let status = engineClient.status {
                                Text("\(status.totalTranscriptions) transcriptions processed")
                                    .font(.system(size: 10))
                                    .foregroundColor(TalkieTheme.textTertiary)
                            } else if let error = engineClient.lastError {
                                Text(error)
                                    .font(.system(size: 10))
                                    .foregroundColor(SemanticColor.error.opacity(0.8))
                            } else {
                                Text("Starting transcription service...")
                                    .font(.system(size: 10))
                                    .foregroundColor(TalkieTheme.textTertiary)
                            }
                        }

                        Spacer()

                        if !engineClient.isConnected {
                            Button(action: {
                                engineClient.reconnect()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10))
                                    Text("Retry")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(CornerRadius.xs)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Speech Recognition Models - Dynamic from Engine
            ForEach(ModelFamily.allCases, id: \.rawValue) { family in
                if let models = modelsByFamily[family.rawValue], !models.isEmpty {
                    SettingsCard(title: "\(family.displayName.uppercased()) MODELS") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(models) { model in
                                ModelManagementRow(
                                    model: model,
                                    isSelected: settings.selectedModelId == model.id,
                                    isDownloading: downloadingModelId == model.id,
                                    downloadProgress: engineClient.downloadProgress?.modelId == model.id
                                        ? Float(engineClient.downloadProgress?.progress ?? 0)
                                        : 0,
                                    onSelect: { settings.selectedModelId = model.id },
                                    onDownload: { downloadModel(model.id) },
                                    onDelete: { deleteModel(model.id) }
                                )

                                if model.id != models.last?.id {
                                    Divider()
                                        .background(TalkieTheme.hover)
                                }
                            }
                        }
                    }
                }
            }

            // Show message if no models available yet
            if engineClient.availableModels.isEmpty {
                SettingsCard(title: "MODELS") {
                    VStack(spacing: Spacing.sm) {
                        if engineClient.connectionState == .connected {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading available models...")
                                .font(.system(size: 11))
                                .foregroundColor(TalkieTheme.textTertiary)
                        } else {
                            Text("Connect to engine to see available models")
                                .font(.system(size: 11))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                }
            }

            // Info
            SettingsCard(title: "ABOUT ENGINE") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("TalkieEngine runs as a separate process to keep ML models warm in memory across app restarts. It supports multiple speech recognition models including Whisper and Parakeet, all running locally via Apple's Neural Engine.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Technical details
                    if let status = engineClient.status {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Divider()
                                .padding(.vertical, Spacing.xs)

                            // Process info
                            HStack(spacing: Spacing.xs) {
                                Text("Process ID:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                Text("\(status.pid)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(TalkieTheme.textPrimary)
                            }

                            // XPC service name
                            if let mode = engineClient.connectedMode {
                                HStack(spacing: Spacing.xs) {
                                    Text("XPC Service:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                    Text(mode.rawValue)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(TalkieTheme.textPrimary)
                                }
                            }

                            // Connection state
                            HStack(spacing: Spacing.xs) {
                                Text("Connection:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                Text(engineClient.connectionState.rawValue)
                                    .font(.system(size: 9))
                                    .foregroundColor(engineStatusColor)
                            }

                            // Uptime
                            HStack(spacing: Spacing.xs) {
                                Text("Uptime:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                Text(formatUptime(status.uptime))
                                    .font(.system(size: 9))
                                    .foregroundColor(TalkieTheme.textPrimary)
                            }

                            // Transcriptions processed
                            HStack(spacing: Spacing.xs) {
                                Text("Transcriptions:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                Text("\(status.totalTranscriptions)")
                                    .font(.system(size: 9))
                                    .foregroundColor(TalkieTheme.textPrimary)
                            }

                            // Memory usage
                            if let memoryMB = status.memoryUsageMB {
                                HStack(spacing: Spacing.xs) {
                                    Text("Memory:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                    Text("\(memoryMB) MB")
                                        .font(.system(size: 9))
                                        .foregroundColor(TalkieTheme.textPrimary)
                                }
                            }

                            // Build type
                            if let isDebug = status.isDebugBuild {
                                HStack(spacing: Spacing.xs) {
                                    Text("Build:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                    Text(isDebug ? "Debug" : "Release")
                                        .font(.system(size: 9))
                                        .foregroundColor(TalkieTheme.textPrimary)
                                }
                            }

                            // Loaded model
                            if let modelId = status.loadedModelId {
                                HStack(spacing: Spacing.xs) {
                                    Text("Loaded Model:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                    Text(modelId)
                                        .font(.system(size: 9))
                                        .foregroundColor(TalkieTheme.textPrimary)
                                }
                            }
                        }
                        .padding(.top, Spacing.xs)
                    }

                    HStack(spacing: Spacing.md) {
                        ModelInfoBadge(icon: "lock.shield", label: "Private")
                        ModelInfoBadge(icon: "bolt", label: "On-device")
                        ModelInfoBadge(icon: "memorychip", label: "Persistent")
                    }
                    .padding(.top, Spacing.xs)
                }
            }
        }
        .onAppear {
            Task {
                // Ensure connection first, then refresh
                let connected = await engineClient.ensureConnected()
                if connected {
                    engineClient.refreshStatus()
                    await engineClient.refreshAvailableModels()
                }
            }
        }
    }

    private var engineStatusColor: Color {
        switch engineClient.connectionState {
        case .connected: return SemanticColor.success
        case .connectedWrongBuild: return SemanticColor.warning
        case .connecting: return SemanticColor.warning
        case .disconnected: return .gray
        case .error: return SemanticColor.error
        }
    }

    private var selectedDeviceName: String {
        let selectedID = audioDevices.selectedDeviceID
        if let device = audioDevices.inputDevices.first(where: { $0.id == selectedID }) {
            return device.name
        }
        // Fallback to default device name
        if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
            return "\(defaultDevice.name) (Default)"
        }
        return "System Default"
    }

    private func formatUptime(_ date: Date?) -> String {
        guard let date = date else { return "--" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m"
    }

    private func formatUptime(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "1h+ ago"
    }

    private func downloadModel(_ modelId: String) {
        // Check if already downloaded
        if let model = engineClient.availableModels.first(where: { $0.id == modelId }),
           model.isDownloaded {
            return
        }

        downloadingModelId = modelId
        downloadTask = Task {
            do {
                try await engineClient.downloadModel(modelId)
                await MainActor.run {
                    downloadingModelId = nil
                    downloadTask = nil
                }
            } catch {
                await MainActor.run {
                    downloadingModelId = nil
                    downloadTask = nil
                }
            }
        }
    }

    private func deleteModel(_ modelId: String) {
        // TODO: Implement delete via engine XPC
        // For now, this is a no-op as deletion isn't implemented in the engine
    }
}

// MARK: - Engine Stat Badge

struct EngineStatBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.accentColor.opacity(0.8))

            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(TalkieTheme.textMuted)

                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TalkieTheme.textPrimary)
            }
        }
    }
}

/// Generic model management row that works with ModelInfo from the engine
struct ModelManagementRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isDownloading: Bool
    let downloadProgress: Float
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Selection indicator
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : TalkieTheme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(!model.isDownloaded)

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(model.isDownloaded ? .white : TalkieTheme.textTertiary)

                    if model.isLoaded {
                        Text("LOADED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(SemanticColor.success)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(SemanticColor.success.opacity(0.2))
                            .cornerRadius(3)
                    }

                    Text(model.sizeDescription)
                        .font(.system(size: 8))
                        .foregroundColor(TalkieTheme.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(TalkieTheme.hover)
                        .cornerRadius(3)
                }

                Text(model.description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textMuted)
            }

            Spacer()

            // Action buttons
            if isDownloading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
                .frame(width: 60)
            } else if model.isDownloaded {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(isHovered ? SemanticColor.error : TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.5)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                        Text("Download")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
        .background(isHovered ? TalkieTheme.divider : Color.clear)
        .onHover { isHovered = $0 }
    }
}

/// Legacy alias for backwards compatibility
typealias WhisperModelManagementRow = ModelManagementRow

struct ModelInfoBadge: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 9))
        }
        .foregroundColor(TalkieTheme.textTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TalkieTheme.hover)
        .cornerRadius(4)
    }
}
