//
//  StatusBar.swift
//  Talkie
//
//  Unified status bar for Live features
//  Adapted from TalkieLive's DebugKit StatusBar
//
//  Layout:
//  - Left: Keyboard shortcut hints
//  - Center: Interactive dictation pill (StatePill) with PID display on Ctrl+hover
//  - Right: Status icons (Mic, Engine, Model, Sync, Logs)
//

import SwiftUI
import AppKit

// MARK: - Main Status Bar (Unified App-Wide)

struct StatusBar: View {
    // Live state monitoring (watches TalkieLive's recording state from database)
    @ObservedObject private var liveState = TalkieLiveStateMonitor.shared

    // Service monitoring
    @ObservedObject private var whisperService = WhisperService.shared
    @ObservedObject private var engineClient = EngineClient.shared
    @ObservedObject private var serviceMonitor = TalkieServiceMonitor.shared

    // App-wide observables
    @ObservedObject private var events = SystemEventManager.shared
    @ObservedObject private var syncManager = CloudKitSyncManager.shared

    // App-wide data (passed from NavigationView)
    let memoCount: Int

    @State private var recordingDuration: TimeInterval = 0
    @State private var processingDuration: TimeInterval = 0
    @State private var durationTimer: Timer?
    @State private var showSuccess: Bool = false
    @State private var successTimer: Timer?
    @State private var showConsolePopover = false

    // PID display state
    @State private var isHovered = false
    @State private var showPID = false
    @State private var pidCopied = false
    private let pid = ProcessInfo.processInfo.processIdentifier

    private var errorCount: Int {
        events.events.filter { $0.type == .error }.count
    }

    private var warningCount: Int {
        // Warnings: workflow-related events
        events.events.filter { $0.type == .workflow }.count
    }

    private var infoCount: Int {
        // Info: system, record, transcribe, sync
        events.events.filter { $0.type == .system || $0.type == .transcribe || $0.type == .sync || $0.type == .record }.count
    }

    private var barBackgroundColor: Color {
        TalkieTheme.surfaceElevated
    }

    private var isActive: Bool {
        liveState.state != .idle || showSuccess
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1)

            HStack(spacing: Spacing.sm) {
                // LEFT SIDE - App-wide statuses
                HStack(spacing: 8) {
                    // Sync status
                    SyncStatusIcon()

                    Divider()
                        .frame(height: 12)

                    // Memo count
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TalkieTheme.textMuted)
                        Text("\(memoCount) memos")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TalkieTheme.textMuted)
                    }
                }

                Spacer()

                // CENTER - Live dictation pill (always visible)
                HStack(spacing: 8) {
                    StatePill(
                        state: liveState.state,
                        isWarmingUp: false,
                        showSuccess: showSuccess,
                        recordingDuration: liveState.elapsedTime,
                        processingDuration: processingDuration,
                        isEngineConnected: serviceMonitor.state == .running,
                        pendingQueueCount: 0,
                        onTap: {
                            // Toggle recording in TalkieLive via XPC
                            TalkieLiveStateMonitor.shared.toggleRecording()
                        },
                        onQueueTap: nil
                    )

                    // PID appears next to pill on Control+hover
                    if showPID {
                        Button(action: copyPID) {
                            Text("\(pid)")
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

                Spacer()

                // RIGHT SIDE - Live status icons + Console + DEV badge
                HStack(spacing: 6) {
                    // Live status icons (always visible - show engine/model state)
                    MicStatusIcon()
                    EngineStatusIcon()
                    ModelStatusIcon()

                    Divider()
                        .frame(height: 12)

                    // Console button
                    ConsoleButton(
                        errorCount: errorCount,
                        warningCount: warningCount,
                        infoCount: infoCount,
                        showPopover: $showConsolePopover
                    )

                    // DEV badge (debug builds only)
                    #if DEBUG
                    Text("DEV")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(3)
                    #endif
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
        .frame(height: 32)
        .background(barBackgroundColor)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: showPID)
        .drawingGroup()
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                withAnimation { showPID = false }
                pidCopied = false
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                // Check for Control modifier while hovering
                let controlHeld = NSEvent.modifierFlags.contains(.control)
                if controlHeld != showPID {
                    withAnimation { showPID = controlHeld }
                }
            case .ended:
                withAnimation { showPID = false }
                pidCopied = false
            }
        }
        .onChange(of: liveState.state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
    }

    private func copyPID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(pid)", forType: .string)
        withAnimation { pidCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { pidCopied = false }
        }
    }

    private func handleStateChange(from oldState: LiveState, to newState: LiveState) {
        // Recording timer
        if newState == .listening {
            startRecordingTimer()
        } else if oldState == .listening {
            stopRecordingTimer()
        }

        // Processing timer
        if newState == .transcribing {
            startProcessingTimer()
        } else if oldState == .transcribing {
            stopProcessingTimer()
        }

        // Show success state when we return to idle after routing
        if newState == .idle && oldState == .routing {
            showSuccessState()
        }
    }

    private func showSuccessState() {
        showSuccess = true
        successTimer?.invalidate()
        successTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.3)) {
                    showSuccess = false
                }
            }
        }
    }

    private func startRecordingTimer() {
        recordingDuration = 0
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                recordingDuration += 0.1
            }
        }
    }

    private func stopRecordingTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingDuration = 0
    }

    private func startProcessingTimer() {
        processingDuration = 0
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                processingDuration += 0.1
            }
        }
    }

    private func stopProcessingTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        processingDuration = 0
    }
}

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

// MARK: - Mic Status Icon

struct MicStatusIcon: View {
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared

    // TODO: Add AudioDeviceManager if needed
    private var deviceName: String {
        "Built-in"  // Placeholder - wire to actual device manager
    }

    private var statusColor: Color {
        if audioMonitor.isSilent { return SemanticColor.warning }
        return SemanticColor.success
    }

    var body: some View {
        StatusIcon(
            icon: "mic",
            color: statusColor,
            label: deviceName,
            detail: "Audio input - Click to open Audio settings",
            action: navigateToAudioSettings
        )
    }

    private func navigateToAudioSettings() {
        // TODO: Navigate to Settings → Audio
        NotificationCenter.default.post(name: .switchToSettingsAudio, object: nil)
    }
}

// MARK: - Engine Status Icon

struct EngineStatusIcon: View {
    @ObservedObject private var serviceMonitor = TalkieServiceMonitor.shared
    @State private var isHovered = false
    @State private var showPID = false
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

    private var label: String {
        switch serviceMonitor.state {
        case .running: return "Engine"
        case .stopped: return "Offline"
        case .launching: return "Starting"
        case .terminating: return "Stopping"
        case .unknown: return "Unknown"
        }
    }

    private var badge: String? {
        // Show connection mode badge if running
        guard serviceMonitor.state == .running else { return nil }

        // Check EngineClient connection mode
        if let mode = EngineClient.shared.connectedMode {
            switch mode {
            case .debug: return "DEBUG"
            case .dev: return "DEV"
            case .production: return nil  // No badge for production
            }
        }
        return nil
    }

    private var badgeColor: Color {
        if let mode = EngineClient.shared.connectedMode {
            switch mode {
            case .debug: return .red
            case .dev: return .orange
            case .production: return .blue
            }
        }
        return .blue
    }

    var body: some View {
        HStack(spacing: 6) {
            StatusIcon(
                icon: "cpu",
                color: statusColor,
                label: label,
                detail: "TalkieEngine - Click for settings, Shift+Click to launch/restart",
                badge: badge,
                badgeColor: badgeColor,
                action: handleClick
            )

            // PID appears on Ctrl+hover
            if showPID, let pid = serviceMonitor.processId {
                Button(action: { copyPID(pid) }) {
                    Text("\(pid)")
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
                withAnimation { showPID = false }
                pidCopied = false
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                // Check for Control modifier while hovering
                let controlHeld = NSEvent.modifierFlags.contains(.control)
                if controlHeld != showPID {
                    withAnimation { showPID = controlHeld }
                }
            case .ended:
                withAnimation { showPID = false }
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
        // TODO: Navigate to Settings → Engine
        NotificationCenter.default.post(name: .switchToSettingsEngine, object: nil)
    }
}

// MARK: - Model Status Icon

struct ModelStatusIcon: View {
    @ObservedObject private var whisperService = WhisperService.shared

    private var modelName: String {
        guard let loadedModel = whisperService.loadedModel else {
            return "No Model"
        }
        // Format model name (use rawValue from enum)
        return loadedModel.rawValue
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")
    }

    private var statusColor: Color {
        if whisperService.loadedModel != nil { return SemanticColor.success }
        return SemanticColor.warning
    }

    private var hasModel: Bool {
        whisperService.loadedModel != nil
    }

    var body: some View {
        StatusIcon(
            icon: hasModel ? "waveform" : "waveform.slash",
            color: statusColor,
            label: modelName,
            detail: (whisperService.loadedModel?.rawValue ?? "No model loaded") + " - Click to open Model settings",
            action: navigateToModelSettings
        )
    }

    private func navigateToModelSettings() {
        // TODO: Navigate to Settings → Models
        NotificationCenter.default.post(name: .switchToSettingsModel, object: nil)
    }
}

// MARK: - Sync Status Icon (NEW - Talkie-specific)

struct SyncStatusIcon: View {
    @ObservedObject private var syncManager = CloudKitSyncManager.shared

    private var statusColor: Color {
        if syncManager.isSyncing { return SemanticColor.info }
        return SemanticColor.success
    }

    private var icon: String {
        if syncManager.isSyncing { return "arrow.triangle.2.circlepath" }
        return "checkmark.icloud"
    }

    private var label: String {
        if syncManager.isSyncing { return "Syncing" }

        // Show last sync time
        if let lastSync = syncManager.lastSyncDate {
            let interval = Date().timeIntervalSince(lastSync)
            if interval < 60 {
                return "Just now"
            } else if interval < 3600 {
                let mins = Int(interval / 60)
                return "\(mins)m ago"
            } else {
                let hours = Int(interval / 3600)
                return "\(hours)h ago"
            }
        }

        return "Ready"
    }

    var body: some View {
        StatusIcon(
            icon: icon,
            color: statusColor,
            label: label,
            detail: "CloudKit sync - Click for iCloud settings",
            action: navigateToSyncSettings
        )
    }

    private func navigateToSyncSettings() {
        // TODO: Navigate to Settings → iCloud
        NotificationCenter.default.post(name: .switchToSettingsiCloud, object: nil)
    }
}

// MARK: - Console Button

struct ConsoleButton: View {
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int
    @Binding var showPopover: Bool

    @State private var isHovered = false

    private var statusColor: Color {
        if errorCount > 0 { return SemanticColor.error }
        if warningCount > 0 { return SemanticColor.warning }
        return SemanticColor.success
    }

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 6) {
                // Error count (red)
                if errorCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                        Text("\(errorCount)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(SemanticColor.error)
                }

                // Workflow count (amber)
                if warningCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("\(warningCount)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.3))
                }

                // Terminal icon
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(TalkieTheme.textMuted)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(TalkieTheme.surfaceCard.opacity(0.5))
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            SystemConsoleView()
                .frame(width: 600, height: 350)
        }
        .help("Console - \(errorCount) errors, \(warningCount) warnings")
    }
}

// MARK: - Shortcut Hint

struct ShortcutHint: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(TalkieTheme.textMuted.opacity(0.7))

            Text(shortcut)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.5)  // Subtle letter spacing
                .foregroundColor(TalkieTheme.textMuted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .offset(y: -1)  // Move up 1 pixel
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .offset(y: -1)  // Background moves with content
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // Note: switchToLogs, switchToSettingsAudio, switchToSettingsEngine are defined in HistoryViewStubs.swift
    static let switchToSettingsModel = Notification.Name("switchToSettingsModel")
    static let switchToSettingsiCloud = Notification.Name("switchToSettingsiCloud")
}

// MARK: - Preview

#Preview {
    StatusBar(memoCount: 211)
        .frame(width: 1000)
        .background(Color.black)
}
