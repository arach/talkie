//
//  StatusBar.swift
//  Talkie
//
//  Unified status bar for Live features
//  Simplified version - direct service access, no ViewModel middleman
//
//  Layout:
//  - Left: ON AIR indicator or Sync status
//  - Center: Interactive dictation pill with PID display on Ctrl+hover
//  - Right: Engine status + Logs + DEV badge
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Main Status Bar

struct StatusBar: View {
    // Direct service access - use let for @Observable singletons
    private let liveState = ServiceManager.shared.live
    private let serviceMonitor = ServiceManager.shared.engine
    private let events = SystemEventManager.shared
    private let liveSettings = LiveSettings.shared
    private let audioDevices = AudioDeviceManager.shared

    // UI state
    @State private var showConsolePopover = false
    @State private var showSuccess = false
    @State private var successTimer: Timer?

    // Hover/PID state
    @State private var isHovered = false
    @State private var showPID = false
    @State private var pidCopied = false
    @State private var controlPressed = false

    // App version for display
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    // Computed properties (replaces ViewModel aggregation)
    private var microphoneName: String {
        if let device = audioDevices.inputDevices.first(where: { $0.id == liveSettings.selectedMicrophoneID }) {
            return device.name
        } else if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
            return defaultDevice.name
        }
        return "No microphone"
    }

    private var errorCount: Int {
        events.events.filter { $0.type == .error }.count
    }

    private var warningCount: Int {
        events.events.filter { $0.type == .workflow }.count
    }

    private var infoCount: Int {
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
            // Top border (light touch)
            Rectangle()
                .fill(TalkieTheme.borderSubtle)
                .frame(height: 1)

            HStack(spacing: Spacing.sm) {
                // LEFT SIDE - ON AIR indicator or Sync status
                Group {
                    if liveState.state == .listening && liveSettings.showOnAir {
                        OnAirIndicator()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        SyncStatusIcon()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }

                Spacer()

                // CENTER - Live dictation pill or offline indicator
                HStack(spacing: 8) {
                    if liveState.isRunning {
                        LivePill(
                            state: liveState.state,
                            isWarmingUp: false,
                            showSuccess: showSuccess,
                            recordingDuration: liveState.elapsedTime,  // Use Live's elapsed time directly
                            processingDuration: 0,  // Simplified - not tracking separately
                            isEngineConnected: serviceMonitor.state == .running,
                            pendingQueueCount: 0,
                            micDeviceName: microphoneName,
                            audioLevel: 0,  // StatusBar doesn't have audio capture - just shows pill
                            onTap: {
                                ServiceManager.shared.live.toggleRecording()
                            }
                        )
                        .contextMenu {
                            Button("Restart TalkieLive") {
                                restartTalkieLive()
                            }
                        }
                        .onTapGesture(count: 1) { }  // Consume single tap
                        .simultaneousGesture(
                            TapGesture().modifiers(.control)
                                .onEnded { _ in
                                    openTalkieSettings()
                                }
                        )

                        // Live environment badge (on Ctrl+hover)
                        if showPID, let liveEnv = liveState.connectedMode, liveEnv != .production {
                            LiveEnvironmentBadge(environment: liveEnv)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }

                        // PID appears on Control+hover
                        if showPID, let pid = liveState.processId {
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
                        LiveOfflineIcon(action: launchTalkieLive)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

                Spacer()

                // RIGHT SIDE - Engine status + Logs + DEV badge
                HStack(spacing: 6) {
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
                        errorCount: errorCount,
                        warningCount: warningCount,
                        infoCount: infoCount,
                        showPopover: $showConsolePopover
                    )

                    // Version badge - always visible
                    Text("v\(appVersion)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(TalkieTheme.textMuted)

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
            // Show success state when returning to idle after routing
            if newState == .idle && oldState == .routing {
                showSuccessState()
            }
        }
        .onAppear {
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

    // MARK: - Helper Methods

    private func copyPID(_ pid: Int32) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(pid)", forType: .string)
        withAnimation { pidCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { pidCopied = false }
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

    private func launchTalkieLive() {
        _ = AppEnvironment.shared.launch(.talkieLive)
    }

    private func restartTalkieLive() {
        AppEnvironment.shared.restart(.talkieLive)
    }

    private func openTalkieSettings() {
        let environment = TalkieEnvironment.current
        let urlString = "\(environment.talkieURLScheme)://settings/live"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    StatusBar()
        .frame(width: 1000)
        .background(Color.black)
}
