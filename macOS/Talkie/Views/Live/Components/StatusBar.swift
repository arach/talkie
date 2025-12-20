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
    @ObservedObject private var liveSettings = LiveSettings.shared

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
    @State private var pathCopied = false

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
                // LEFT SIDE - ON AIR indicator or app statuses
                Group {
                    if liveState.state == .listening && liveSettings.showOnAir {
                        // ON AIR indicator when actively recording (and enabled in settings)
                        OnAirIndicator()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        // App-wide statuses when not recording
                        SyncStatusIcon()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }

                Spacer()

                // CENTER - Live dictation pill or offline indicator
                HStack(spacing: 8) {
                    if liveState.isRunning {
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
                        .contextMenu {
                            Button("Restart TalkieLive") {
                                restartTalkieLive()
                            }
                        }

                        // PID and build info appear on Control+hover
                        if showPID {
                            HStack(spacing: 6) {
                                // PID
                                if let pid = liveState.processId {
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
                                    .help("Click to copy TalkieLive PID")
                                }

                                // Build info
                                if let buildInfo = getLiveBuildInfo() {
                                    Button(action: { copyPath(buildInfo.path) }) {
                                        HStack(spacing: 4) {
                                            Text(buildInfo.type)
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(buildInfo.type == "DEBUG" ? .red : .blue)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .fill((buildInfo.type == "DEBUG" ? Color.red : Color.blue).opacity(0.2))
                                                )

                                            Text(buildInfo.shortPath)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(pathCopied ? SemanticColor.success : TalkieTheme.textTertiary)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(TalkieTheme.hover)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Click to copy full path: \(buildInfo.path)")
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    } else {
                        // Live is offline - show clickable icon to start
                        LiveOfflineIcon(action: launchTalkieLive)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

                Spacer()

                // RIGHT SIDE - Live status icons + Logs + DEV badge
                HStack(spacing: 6) {
                    // Live status icons - conditional on service state
                    if liveState.isRunning {
                        MicStatusIcon()
                    }

                    if serviceMonitor.state == .running {
                        EngineStatusIcon()
                        ModelStatusIcon()
                    } else {
                        // Show engine state for non-running states
                        HStack(spacing: 4) {
                            Image(systemName: serviceMonitor.state == .stopped ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                                .font(.system(size: 9))
                                .foregroundColor(serviceMonitor.state == .stopped ? SemanticColor.warning : TalkieTheme.textMuted)
                            Text(serviceMonitor.state == .stopped ? "Engine Offline" : "Engine \(serviceMonitor.state.rawValue)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(TalkieTheme.textMuted)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background((serviceMonitor.state == .stopped ? SemanticColor.warning : Color.gray).opacity(0.1))
                        .cornerRadius(4)
                        .help("TalkieEngine: \(serviceMonitor.state.rawValue). Click to launch.")
                        .onTapGesture {
                            Task {
                                if serviceMonitor.state != .running {
                                    await serviceMonitor.launch()
                                }
                            }
                        }
                    }

                    // Only show divider if we have status icons
                    if liveState.isRunning || serviceMonitor.state != .unknown {
                        Divider()
                            .frame(height: 12)
                    }

                    // Logs button
                    ConsoleButton(
                        errorCount: errorCount,
                        warningCount: warningCount,
                        infoCount: infoCount,
                        showPopover: $showConsolePopover
                    )

                    // DEV badge (debug builds only)
                    #if DEBUG
                    DevBadgeButton(showConsole: $showConsolePopover)
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
        .animation(.easeInOut(duration: 0.2), value: liveState.isRunning)
        .animation(.easeInOut(duration: 0.2), value: serviceMonitor.state)
        .drawingGroup()
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                withAnimation { showPID = false }
                pidCopied = false
                pathCopied = false
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
                pathCopied = false
            }
        }
        .onChange(of: liveState.state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onAppear {
            // Start monitoring service states
            liveState.startMonitoring()
            serviceMonitor.startMonitoring()
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

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        withAnimation { pathCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { pathCopied = false }
        }
    }

    private func getLiveBuildInfo() -> (type: String, path: String, shortPath: String)? {
        // Get running TalkieLive app
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "jdi.TalkieLive")
        guard let app = apps.first, let bundleURL = app.bundleURL else { return nil }

        let path = bundleURL.path
        let isDerivedData = path.contains("DerivedData")
        let type = isDerivedData ? "DEBUG" : "PROD"

        // Create short path for display
        var shortPath: String
        if isDerivedData {
            // Show just "DerivedData/.../Debug/TalkieLive.app"
            let components = path.components(separatedBy: "/")
            if let ddIndex = components.firstIndex(of: "DerivedData"),
               ddIndex + 1 < components.count {
                let projectName = components[ddIndex + 1]
                shortPath = "DD/\(projectName)/.../Debug"
            } else {
                shortPath = "DerivedData/.../Debug"
            }
        } else {
            // Just show "/Applications"
            shortPath = "/Applications"
        }

        return (type: type, path: path, shortPath: shortPath)
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

    private func launchTalkieLive() {
        _ = AppEnvironment.shared.launch(.talkieLive)
    }

    private func restartTalkieLive() {
        AppEnvironment.shared.restart(.talkieLive)
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

// MARK: - Live Status Icon

struct LiveStatusIcon: View {
    @ObservedObject private var liveState = TalkieLiveStateMonitor.shared
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared

    private var statusColor: Color {
        if !liveState.isRunning { return TalkieTheme.textMuted }
        if audioMonitor.isSilent { return SemanticColor.warning }
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

// MARK: - Mic Status Icon (Legacy - kept for reference)

struct MicStatusIcon: View {
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared
    @ObservedObject private var audioDevices = AudioDeviceManager.shared
    @ObservedObject private var layoutManager = SessionLayoutManager.shared
    @State private var isHovered = false

    private var deviceName: String {
        if let device = audioDevices.inputDevices.first(where: { $0.id == audioDevices.selectedDeviceID }) {
            return device.name
        } else if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
            return defaultDevice.name
        }
        return "No microphone"
    }

    private var statusColor: Color {
        if audioMonitor.isSilent { return SemanticColor.warning }
        return SemanticColor.success
    }

    private var showLabels: Bool {
        isHovered
    }

    var body: some View {
        Button(action: navigateToAudioSettings) {
            HStack(spacing: 4) {
                Image(systemName: "mic")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(statusColor.opacity(isHovered ? 1.0 : 0.7))

                if showLabels {
                    Text(deviceName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .lineLimit(1)
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
        .delayedHelp("\(deviceName) - Click to open Audio settings", delay: 0.6)
        .animation(.easeInOut(duration: 0.15), value: showLabels)
        .onHover { isHovered = $0 }
    }

    private func navigateToAudioSettings() {
        // Navigate to Live Settings → Audio
        NotificationCenter.default.post(name: .switchToLiveSettingsAudio, object: nil)
    }
}

// MARK: - Engine Status Icon

struct EngineStatusIcon: View {
    @ObservedObject private var serviceMonitor = TalkieServiceMonitor.shared
    @ObservedObject private var layoutManager = SessionLayoutManager.shared
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
            case .staging: return "STAGING"
            case .dev: return "DEV"
            case .production: return nil  // No badge for production
            }
        }
        return nil
    }

    private var badgeColor: Color {
        if let mode = EngineClient.shared.connectedMode {
            switch mode {
            case .staging: return .orange
            case .dev: return .red
            case .production: return .blue
            }
        }
        return .blue
    }

    private var showLabels: Bool {
        isHovered
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: handleClick) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(statusColor.opacity(isHovered ? 1.0 : 0.7))

                    if showLabels {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(badgeColor)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(badgeColor.opacity(0.2))
                                .cornerRadius(2)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
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
            .delayedHelp("TalkieEngine - Click for settings, Shift+Click to launch/restart", delay: 0.6)
            .animation(.easeInOut(duration: 0.15), value: showLabels)

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
        // Navigate to Settings → Supporting Apps → TalkieEngine
        NotificationCenter.default.post(name: .switchToSupportingApps, object: nil)
    }
}

// MARK: - Model Status Icon

struct ModelStatusIcon: View {
    @ObservedObject private var settings = LiveSettings.shared
    @ObservedObject private var engineClient = EngineClient.shared
    @ObservedObject private var layoutManager = SessionLayoutManager.shared
    @State private var isHovered = false

    private var modelName: String {
        // Use selected model from LiveSettings
        let modelId = settings.selectedModelId

        // Parse family and model ID
        let (family, id) = ModelInfo.parseModelId(modelId)

        // Format the model name from the ID
        return id
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")
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
        .delayedHelp("\(settings.selectedModelId) - Click to open Transcription settings", delay: 0.6)
        .animation(.easeInOut(duration: 0.15), value: showLabels)
        .onHover { isHovered = $0 }
    }

    private func navigateToModelSettings() {
        // Navigate to Live Settings → Transcription
        NotificationCenter.default.post(name: .switchToLiveSettingsTranscription, object: nil)
    }
}

// MARK: - Sync Status Icon (NEW - Talkie-specific)

struct SyncStatusIcon: View {
    @ObservedObject private var syncManager = CloudKitSyncManager.shared
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

// MARK: - Logs Button

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
        .help("Logs - \(errorCount) errors, \(warningCount) warnings")
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
    // Note: switchToLogs is defined in HistoryViewStubs.swift
    static let switchToSettingsModel = Notification.Name("switchToSettingsModel")
    static let switchToSettingsiCloud = Notification.Name("switchToSettingsiCloud")
    static let switchToSupportingApps = Notification.Name("switchToSupportingApps")

    // Live Settings navigation
    static let switchToLiveSettingsAudio = Notification.Name("switchToLiveSettingsAudio")
    static let switchToLiveSettingsTranscription = Notification.Name("switchToLiveSettingsTranscription")
    static let switchToLiveSettingsOverview = Notification.Name("switchToLiveSettingsOverview")
}

// MARK: - Live Offline Icon with Hover

struct LiveOfflineIcon: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image("LiveMenuBarIcon")
                .renderingMode(.template)
                .foregroundColor(TalkieTheme.textMuted.opacity(isHovered ? 0.8 : 0.4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Live Mode is inactive. Click to enable.")
    }
}

// MARK: - Dev Badge Button

#if DEBUG
struct DevBadgeButton: View {
    @Binding var showConsole: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: { showConsole.toggle() }) {
            Text("DEV")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange.opacity(isHovered ? 1.0 : 0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(isHovered ? 0.25 : 0.15))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open logs (Command+Shift+D)")
    }
}
#endif

// MARK: - Delayed Tooltip Modifier

struct DelayedTooltip: ViewModifier {
    let text: String
    let delay: TimeInterval

    @State private var isHovered = false
    @State private var showTooltip = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if isHovered {
                            showTooltip = true
                        }
                    }
                } else {
                    showTooltip = false
                }
            }
            .help(showTooltip ? text : "")
    }
}

extension View {
    func delayedHelp(_ text: String, delay: TimeInterval = 0.5) -> some View {
        modifier(DelayedTooltip(text: text, delay: delay))
    }
}

// MARK: - Preview

#Preview {
    StatusBar()
        .frame(width: 1000)
        .background(Color.black)
}
