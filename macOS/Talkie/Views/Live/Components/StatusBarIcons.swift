//
//  StatusBarIcons.swift
//  Talkie
//
//  Status bar icon components
//  Extracted from StatusBar.swift for better organization
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Status Icon Base Component

struct StatusIcon: View {
    let icon: String
    let color: Color
    let label: String
    let detail: String?
    var badge: String? = nil
    var badgeColor: Color = .orange
    var action: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color)

                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(TalkieTheme.textTertiary)
                    .lineLimit(1)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(badgeColor.opacity(0.2))
                        .cornerRadius(2)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? TalkieTheme.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(detail ?? label)
    }
}

// MARK: - Live Status Icon

struct LiveStatusIcon: View {
    private let liveState = TalkieLiveStateMonitor.shared

    private var statusColor: Color {
        if !liveState.isRunning { return TalkieTheme.textMuted }
        // Note: Silence detection happens in TalkieLive, not here
        // We just show green when running, muted when not
        return SemanticColor.success
    }

    private var icon: String {
        liveState.isRunning ? "mic" : "waveform.circle"
    }

    private var label: String {
        if !liveState.isRunning { return "Live" }
        return "Built-in"  // TODO: wire to actual device name
    }

    private var detail: String {
        if !liveState.isRunning {
            return "Live Mode is inactive - Click to open Live settings"
        }
        return "Audio input - Click to open Audio settings"
    }

    var body: some View {
        StatusIcon(
            icon: icon,
            color: statusColor,
            label: label,
            detail: detail,
            action: navigateToSettings
        )
    }

    private func navigateToSettings() {
        if liveState.isRunning {
            // Navigate to Live Settings → Audio
            NotificationCenter.default.post(name: .switchToLiveSettingsAudio, object: nil)
        } else {
            // Navigate to Live Settings → Overview to see health card
            NotificationCenter.default.post(name: .switchToLiveSettingsOverview, object: nil)
        }
    }
}

// MARK: - Simple Engine Icon

struct SimpleEngineIcon: View {
    private let serviceMonitor = TalkieServiceMonitor.shared
    @State private var isHovered = false

    private var statusColor: Color {
        switch serviceMonitor.state {
        case .running: return SemanticColor.success
        case .stopped: return SemanticColor.error
        case .launching: return SemanticColor.info
        case .terminating: return SemanticColor.warning
        case .unknown: return TalkieTheme.textMuted
        }
    }

    var body: some View {
        Button(action: navigateToEngineSettings) {
            Image(systemName: "engine.combustion")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(statusColor.opacity(isHovered ? 1.0 : 0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? TalkieTheme.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("TalkieEngine - Click for settings")
    }

    private func navigateToEngineSettings() {
        NotificationCenter.default.post(name: .switchToSupportingApps, object: nil)
    }
}

// MARK: - Engine Status Icon

struct EngineStatusIcon: View {
    private let serviceMonitor = TalkieServiceMonitor.shared
    private let layoutManager = SessionLayoutManager.shared
    @State private var isHovered = false
    @State private var showPID = false
    @State private var showEnvBadge = false
    @State private var pidCopied = false

    private var statusColor: Color {
        switch serviceMonitor.state {
        case .running: return SemanticColor.success
        case .stopped: return SemanticColor.error
        case .launching: return SemanticColor.info
        case .terminating: return SemanticColor.warning
        case .unknown: return TalkieTheme.textMuted
        }
    }

    @Environment(LiveSettings.self) private var settings
    @Environment(EngineClient.self) private var engineClient

    private var label: String {
        // Show loaded model name when running, otherwise show engine state
        if serviceMonitor.state == .running {
            // Show the ACTUALLY LOADED model, not just the selected one
            let modelId: String
            if let status = engineClient.status, let loadedId = status.loadedModelId {
                modelId = loadedId
            } else {
                // No model loaded, show selected model
                modelId = settings.selectedModelId
            }
            return ModelInfo.formatModelName(modelId)
        }

        switch serviceMonitor.state {
        case .running: return "Engine"  // Fallback (shouldn't reach here)
        case .stopped: return "Offline"
        case .launching: return "Starting"
        case .terminating: return "Stopping"
        case .unknown: return "Unknown"
        }
    }

    private var badgeMode: EngineServiceMode? {
        // Show connection mode badge if running
        guard serviceMonitor.state == .running else { return nil }
        return EngineClient.shared.connectedMode
    }

    private var badgeText: String? {
        // Only show on Ctrl+hover
        guard showEnvBadge, let mode = badgeMode else { return nil }

        // Always show full text when visible (since it only shows on Ctrl+hover)
        switch mode {
        case .staging: return "STAGING"
        case .dev: return "DEV"
        case .production: return nil
        }
    }

    private var badgeColor: Color {
        guard let mode = badgeMode else { return .green }
        switch mode {
        case .production: return .green
        case .staging: return .orange
        case .dev: return .purple
        }
    }

    private var showLabels: Bool {
        isHovered
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: handleClick) {
                HStack(spacing: 4) {
                    Image(systemName: "engine.combustion")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(statusColor.opacity(isHovered ? 1.0 : 0.7))

                    if showLabels {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                    }

                    // Badge visible on Ctrl+hover
                    if let badge = badgeText {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(badgeColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.2))
                            .cornerRadius(3)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.horizontal, showLabels ? 6 : 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? TalkieTheme.hover : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .delayedHelp("TalkieEngine - Click for status dashboard, Shift+Click to launch/restart", delay: 0.6)
            .animation(.easeInOut(duration: 0.15), value: showLabels)

            // PID appears on Ctrl+hover
            if showPID, let pid = serviceMonitor.processId {
                Button(action: { copyPID(pid) }) {
                    Text(verbatim: String(format: "%d", pid))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(pidCopied ? SemanticColor.success : TalkieTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(TalkieTheme.hover)
                        )
                }
                .buttonStyle(.plain)
                .help("Click to copy PID")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                withAnimation {
                    showPID = false
                    showEnvBadge = false
                }
                pidCopied = false
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                // Check for Control modifier while hovering
                let controlHeld = NSEvent.modifierFlags.contains(.control)
                if controlHeld != showPID {
                    withAnimation {
                        showPID = controlHeld
                        showEnvBadge = controlHeld
                    }
                }
            case .ended:
                withAnimation {
                    showPID = false
                    showEnvBadge = false
                }
                pidCopied = false
            }
        }
    }

    private func copyPID(_ pid: Int32) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(pid)", forType: .string)
        withAnimation { pidCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { pidCopied = false }
        }
    }

    private func handleClick() {
        // Check for Shift modifier
        if NSEvent.modifierFlags.contains(.shift) {
            // Shift+Click: Launch or restart engine
            Task {
                if serviceMonitor.state == .running {
                    await serviceMonitor.terminate()
                    try? await Task.sleep(for: .milliseconds(500))
                }
                await serviceMonitor.launch()
            }
        } else {
            // Normal click: Navigate to settings
            navigateToEngineSettings()
        }
    }

    private func navigateToEngineSettings() {
        // Open TalkieEngine's native dashboard via URL scheme
        if let url = URL(string: "talkieengine://dashboard") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Model Status Icon

struct ModelStatusIcon: View {
    @Environment(LiveSettings.self) private var settings
    @Environment(EngineClient.self) private var engineClient
    private let layoutManager = SessionLayoutManager.shared
    @State private var isHovered = false

    private var modelName: String {
        // Show the ACTUALLY LOADED model, not just the selected one
        // This prevents confusion when selected model != loaded model
        let modelId: String
        if let status = engineClient.status, let loadedId = status.loadedModelId {
            modelId = loadedId
        } else {
            // No model loaded, show selected model with warning color
            modelId = settings.selectedModelId
        }

        // Format with family display name for clarity (e.g., "Parakeet v3" not just "v3")
        return ModelInfo.formatModelName(modelId)
    }

    private var statusColor: Color {
        // Check if model is actually loaded in engine
        if let status = engineClient.status, status.loadedModelId == settings.selectedModelId {
            return SemanticColor.success
        }
        // Model selected but not loaded yet
        return SemanticColor.info
    }

    private var isModelLoaded: Bool {
        engineClient.status?.loadedModelId == settings.selectedModelId
    }

    private var tooltipText: String {
        if let status = engineClient.status, let loadedId = status.loadedModelId {
            if loadedId == settings.selectedModelId {
                return "\(loadedId) (loaded) - Click to open Transcription settings"
            } else {
                return "Loaded: \(loadedId)\nSelected: \(settings.selectedModelId) - Click to open Transcription settings"
            }
        } else {
            return "No model loaded\nSelected: \(settings.selectedModelId) - Click to open Transcription settings"
        }
    }

    private var showLabels: Bool {
        isHovered
    }

    var body: some View {
        Button(action: navigateToModelSettings) {
            HStack(spacing: 4) {
                Image(systemName: isModelLoaded ? "waveform" : "waveform.badge.exclamationmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(statusColor.opacity(isHovered ? 1.0 : 0.7))

                if showLabels {
                    Text(modelName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                }
            }
            .padding(.horizontal, showLabels ? 6 : 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? TalkieTheme.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .delayedHelp(tooltipText, delay: 0.6)
        .animation(.easeInOut(duration: 0.15), value: showLabels)
        .onHover { isHovered = $0 }
    }

    private func navigateToModelSettings() {
        // Navigate to Live Settings → Transcription
        NotificationCenter.default.post(name: .switchToLiveSettingsTranscription, object: nil)
    }
}

// MARK: - Sync Status Icon

struct SyncStatusIcon: View {
    @Environment(CloudKitSyncManager.self) private var syncManager
    @State private var isHovered = false
    @State private var showingSyncHistory = false

    private var statusColor: Color {
        if syncManager.isSyncing { return SemanticColor.info }
        return SemanticColor.success
    }

    private var icon: String {
        if syncManager.isSyncing { return "arrow.triangle.2.circlepath" }
        return "checkmark.icloud"
    }

    private var hoverText: String {
        if syncManager.isSyncing {
            return "Syncing with iCloud..."
        }

        // Show last sync time on hover
        if let lastSync = syncManager.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let timeAgo = formatter.localizedString(for: lastSync, relativeTo: Date())
            return "Last synced \(timeAgo)"
        }

        return "CloudKit sync ready"
    }

    var body: some View {
        Button(action: showSyncHistory) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(statusColor.opacity(isHovered ? 1.0 : 0.7))
                .symbolEffect(.pulse, options: .repeating, isActive: syncManager.isSyncing)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(hoverText)
        .sheet(isPresented: $showingSyncHistory) {
            SyncHistoryView()
        }
    }

    private func showSyncHistory() {
        showingSyncHistory = true
    }
}
