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

    #if DEBUG
    // Git branch for debug display (cached at view init)
    private var gitBranch: String? {
        Self.cachedGitBranch
    }

    // Static cache - computed once at app launch
    private static let cachedGitBranch: String? = {
        // Try known development paths first
        let devPaths = [
            "/Users/arach/dev/talkie-dev",  // Main repo
            FileManager.default.currentDirectoryPath
        ]

        for basePath in devPaths {
            if let branch = readGitBranch(from: URL(fileURLWithPath: basePath)) {
                return branch
            }
        }
        return nil
    }()

    private static func readGitBranch(from directory: URL) -> String? {
        let fm = FileManager.default
        let gitPath = directory.appendingPathComponent(".git")

        guard fm.fileExists(atPath: gitPath.path) else { return nil }

        // Check if it's a file (worktree) or directory (regular repo)
        var isDir: ObjCBool = false
        fm.fileExists(atPath: gitPath.path, isDirectory: &isDir)

        if isDir.boolValue {
            // Regular repo: .git/HEAD contains "ref: refs/heads/branch"
            let headPath = gitPath.appendingPathComponent("HEAD")
            if let content = try? String(contentsOf: headPath, encoding: .utf8),
               content.hasPrefix("ref: refs/heads/") {
                return content
                    .replacingOccurrences(of: "ref: refs/heads/", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            // Worktree: .git file contains path to actual git dir
            if let worktreeRef = try? String(contentsOf: gitPath, encoding: .utf8),
               worktreeRef.hasPrefix("gitdir:") {
                let gitDir = worktreeRef
                    .replacingOccurrences(of: "gitdir:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let worktreeHead = URL(fileURLWithPath: gitDir).appendingPathComponent("HEAD")
                if let content = try? String(contentsOf: worktreeHead, encoding: .utf8),
                   content.hasPrefix("ref: refs/heads/") {
                    return content
                        .replacingOccurrences(of: "ref: refs/heads/", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }
    #endif

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

            ZStack {
                // CENTER - Absolutely centered LivePill (rendered first, behind edges)
                HStack(spacing: 8) {
                    if liveState.isRunning {
                        LivePill(
                            state: liveState.state,
                            isWarmingUp: false,
                            showSuccess: showSuccess,
                            recordingDuration: liveState.elapsedTime,
                            processingDuration: 0,
                            isEngineConnected: serviceMonitor.isConnected,
                            pendingQueueCount: 0,
                            micDeviceName: microphoneName,
                            audioLevel: 0,
                            onTap: {
                                ServiceManager.shared.live.toggleRecording()
                            }
                        )
                        .contextMenu {
                            Button("Restart TalkieLive") {
                                restartTalkieLive()
                            }
                        }
                        .onTapGesture(count: 1) { }
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

                // LEFT/RIGHT edges overlay
                HStack(spacing: Spacing.sm) {
                    // LEFT SIDE - Sync status + ON AIR indicator
                    HStack(spacing: 6) {
                        SyncStatusIcon(showSuccess: showSuccess)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))

                        if liveState.state == .listening && liveSettings.showOnAir {
                            OnAirIndicator()
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }

                    Spacer()

                    // RIGHT SIDE - Engine + Logs + version
                    HStack(spacing: 6) {
                        if serviceMonitor.state == .running {
                            EngineStatusIcon(showSuccess: showSuccess)
                        } else {
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

                        ConsoleButton(
                            errorCount: errorCount,
                            warningCount: warningCount,
                            infoCount: infoCount,
                            showPopover: $showConsolePopover
                        )

                        Text("v\(appVersion)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(TalkieTheme.textMuted)

                        #if DEBUG
                        // Git branch indicator
                        if let branch = gitBranch {
                            Text(branch)
                                .font(Theme.current.fontXS)
                                .foregroundColor(TalkieTheme.textMuted)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(TalkieTheme.surfaceCard)
                                )
                        }

                        // Theme indicator for audit mode
                        Text(SettingsManager.shared.currentTheme?.displayName ?? "Default")
                            .font(Theme.current.fontXS)
                            .foregroundColor(LinearStyle.isActive ? LinearStyle.glowColor : TalkieTheme.textMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(LinearStyle.isActive ? LinearStyle.glowColor.opacity(0.15) : Color.clear)
                            )

                        if controlPressed {
                            Divider()
                                .frame(height: 12)
                            DevBadgeButton(showConsole: $showConsolePopover)
                        }
                        #endif
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
        .frame(height: 32)
        .background(Theme.current.surface)
        .background(barBackgroundColor.opacity(0.3))
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
