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
import TalkieKit

// MARK: - Main Status Bar (Unified App-Wide)

struct StatusBar: View {
    // Unified ViewModel for aggregated state
    @State private var viewModel = StatusBarViewModel()

    // Keep direct service access for actions
    @State private var liveState = TalkieLiveStateMonitor.shared
    @State private var serviceMonitor = TalkieServiceMonitor.shared

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
    @State private var controlPressed = false

    private var barBackgroundColor: Color {
        TalkieTheme.surfaceElevated
    }

    private var isActive: Bool {
        viewModel.recordingState != .idle || showSuccess
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
                    if viewModel.recordingState == .listening && viewModel.showOnAir {
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
                            state: viewModel.recordingState,
                            isWarmingUp: false,
                            showSuccess: showSuccess,
                            recordingDuration: liveState.elapsedTime,
                            processingDuration: processingDuration,
                            isEngineConnected: serviceMonitor.state == .running && viewModel.engineConnected,
                            pendingQueueCount: 0,
                            micDeviceName: viewModel.microphoneName,
                            onTap: {
                                // Toggle recording in TalkieLive via XPC
                                TalkieLiveStateMonitor.shared.toggleRecording()
                            }
                        )
                        .contextMenu {
                            Button("Restart TalkieLive") {
                                restartTalkieLive()
                            }
                        }
                        .onTapGesture(count: 1) { }  // Consume single tap to prevent conflict
                        .simultaneousGesture(
                            TapGesture().modifiers(.control)
                                .onEnded { _ in
                                    // Ctrl+click: Open Talkie settings
                                    openTalkieSettings()
                                }
                        )

                        // Live environment badge (on Ctrl+hover, shows which TalkieLive we're connected to)
                        if showPID, let liveEnv = liveState.connectedMode, liveEnv != .production {
                            liveEnvironmentBadge(liveEnv)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }

                        // PID appears on Control+hover
                        if showPID, let pid = viewModel.processId {
                            Button(action: { copyPID(pid) }) {
                                Text(verbatim: "PID \(String(format: "%d", pid))")
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
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    } else {
                        // Live is offline - show clickable icon to start
                        LiveOfflineIcon(action: launchTalkieLive)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

                Spacer()

                // RIGHT SIDE - Engine status (with model + PID on hover) + Logs + DEV badge
                HStack(spacing: 6) {
                    // Combined engine + model status icon with env badge on hover
                    if serviceMonitor.state == .running {
                        EngineStatusIcon()
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

                    // Console button
                    ConsoleButton(
                        errorCount: viewModel.errorCount,
                        warningCount: viewModel.warningCount,
                        infoCount: viewModel.infoCount,
                        showPopover: $showConsolePopover
                    )

                    // DEV badge (debug builds only, shows on CTRL press)
                    #if DEBUG
                    if controlPressed {
                        Divider()
                            .frame(height: 12)
                        DevBadgeButton(showConsole: $showConsolePopover)
                    }
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
        .onChange(of: viewModel.recordingState) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onAppear {
            // Start monitoring service states
            liveState.startMonitoring()
            serviceMonitor.startMonitoring()

            // Monitor Control key for DEV badge
            NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [self] event in
                let isControlPressed = event.modifierFlags.contains(.control)
                if controlPressed != isControlPressed {
                    controlPressed = isControlPressed
                }
                return event
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

    @ViewBuilder
    private func liveEnvironmentBadge(_ env: TalkieEnvironment) -> some View {
        let badgeColor: Color = {
            switch env {
            case .production: return .green
            case .staging: return .orange
            case .dev: return .purple
            }
        }()

        let badgeText: String = {
            switch env {
            case .staging: return "S"
            case .dev: return "D"
            case .production: return "P"
            }
        }()

        HStack(spacing: 2) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(badgeColor.opacity(0.7))

            Text(badgeText)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(badgeColor.opacity(0.2))
        .cornerRadius(2)
        .help("Connected to TalkieLive (\(env.displayName))")
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

    private func openTalkieSettings() {
        // Open Live Settings in the environment-appropriate Talkie app
        let environment = TalkieEnvironment.current
        let urlString = "\(environment.talkieURLScheme)://settings/live"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
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
    @State private var liveState = TalkieLiveStateMonitor.shared
    @State private var audioMonitor = AudioLevelMonitor.shared

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
    @State private var audioMonitor = AudioLevelMonitor.shared
    @State private var audioDevices = AudioDeviceManager.shared
    @State private var layoutManager = SessionLayoutManager.shared
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

// MARK: - Simple Engine Icon (no badge - badge is in pill now)

struct SimpleEngineIcon: View {
    @State private var serviceMonitor = TalkieServiceMonitor.shared
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

// MARK: - Engine Status Icon (Full with badge)

struct EngineStatusIcon: View {
    @State private var serviceMonitor = TalkieServiceMonitor.shared
    @State private var layoutManager = SessionLayoutManager.shared
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
    @State private var layoutManager = SessionLayoutManager.shared
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

// MARK: - Sync Status Icon (NEW - Talkie-specific)

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

// MARK: - Logs Button

struct ConsoleButton: View {
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int
    @Binding var showPopover: Bool

    @State private var isHovered = false

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? TalkieTheme.textSecondary : TalkieTheme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? TalkieTheme.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            SystemLogsView()
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

// MARK: - Live Environment Badge

struct LiveEnvironmentBadge: View {
    let environment: TalkieEnvironment
    @State private var isHovered = false

    private var badgeColor: Color {
        // Use same color scheme as engine badge for consistency
        switch environment {
        case .production: return .green
        case .staging: return .orange
        case .dev: return .purple
        }
    }

    private var badgeText: String {
        if isHovered {
            return environment.badge  // "STAGE" or "DEV"
        } else {
            // Compact mode: just first letter
            switch environment {
            case .staging: return "S"
            case .dev: return "D"
            case .production: return "P"
            }
        }
    }

    var body: some View {
        Text(badgeText)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(badgeColor)
            .padding(.horizontal, isHovered ? 4 : 3)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.2))
            .cornerRadius(3)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
            .help("TalkieLive: \(environment.displayName)")
    }
}

// MARK: - Dev Badge Button

#if DEBUG
struct DevBadgeButton: View {
    @Binding var showConsole: Bool
    @State private var isHovered = false

    private var badgeText: String {
        isHovered ? "DEV" : "D"
    }

    var body: some View {
        Button(action: { showConsole.toggle() }) {
            Text(badgeText)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange.opacity(isHovered ? 1.0 : 0.7))
                .padding(.horizontal, isHovered ? 6 : 4)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(isHovered ? 0.25 : 0.15))
                .cornerRadius(3)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Debug build - Click to open logs")
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
