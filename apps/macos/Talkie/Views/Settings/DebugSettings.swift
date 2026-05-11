//
//  DebugSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import TalkieKit

// Note: DebugSettingsView was removed as dead code. Settings now routes to:
// - Debug → DebugInfoView()
// - Performance → PerformanceSettingsView()
// - Server → ServerSettingsView()
// - Dev Control → DevControlPanelView()
// See SettingsColumns.swift for routing.

// MARK: - Debug Info Content

/// Extracted debug info content for use in tabbed view
struct DebugInfoContent: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    private var memosVM: MemosViewModel { MemosViewModel.shared }
    @State private var syncServiceStatus: String = "Checking..."

    private let syncIntervalOptions = [1, 5, 10, 15, 30, 60]

    private var environment: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        @Bindable var settings = settingsManager

        VStack(alignment: .leading, spacing: Spacing.lg) {
            // MARK: - App Info
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("APP INFORMATION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    // Environment badge
                    Text(environment.uppercased())
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(environment == "Development" ? Color.orange : Color.green)
                        .cornerRadius(CornerRadius.xs)
                }

                VStack(spacing: Spacing.sm) {
                    debugRow(label: "Bundle ID", value: bundleID, icon: "app.badge")
                    debugRow(label: "Version", value: "\(version) (\(build))", icon: "number")
                    debugRow(label: "Voice Memos", value: "\(memosVM.totalCount)", icon: "doc.text")
                    debugRow(label: "Last Sync", value: SyncStatusManager.shared.lastSyncAgo, icon: "arrow.triangle.2.circlepath")
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Rendering
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("RENDERING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if settingsManager.glassEffectsNeedsRestart {
                        Text("RESTART REQUIRED")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(CornerRadius.xs)
                    }
                }

                Toggle(isOn: $settings.enableGlassEffects) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Glass Effects")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foreground)
                        Text("Liquid glass backgrounds with blur and depth. Disable for better performance on older Macs.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(settingsManager.resolvedAccentColor)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                    Text("Current: \(GlassConfig.enableGlassEffects ? "Enabled" : "Disabled"). Changes require app restart.")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(Theme.current.foregroundMuted)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Sync Service Status
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("SYNC SERVICE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(spacing: Spacing.sm) {
                    debugRow(label: "Service Status", value: syncServiceStatus, icon: "arrow.triangle.2.circlepath", valueColor: syncServiceStatusColor)
                    debugRow(label: "Transport", value: "TalkieSync via XPC", icon: "cable.connector")
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Sync Status
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(syncStatusColor)
                        .frame(width: 3, height: 14)

                    Text("SYNC STATUS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 6, height: 6)
                        Text(syncStatusText.uppercased())
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(syncStatusColor)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Text("Sync every")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Picker("", selection: $settings.syncIntervalMinutes) {
                        ForEach(syncIntervalOptions, id: \.self) { minutes in
                            Text(minutes == 1 ? "1 minute" : "\(minutes) minutes")
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)

                    Spacer()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                Text("Manual sync is always available via the toolbar button. Lower intervals use more battery and network.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Onboarding
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("ONBOARDING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(.purple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Setup Wizard")
                            .font(Theme.current.fontSMMedium)
                        Text("Re-run the setup wizard to configure permissions, services, and models.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Button(action: {
                        OnboardingManager.shared.resetOnboarding()
                    }) {
                        Text("RESTART")
                            .font(Theme.current.fontXSBold)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Configuration (JSON)
            SettingsJSONExportView()

            #if DEBUG
            // MARK: - Live Settings Dump
            LiveSettingsDumpView()
            #endif
        }
        .task {
            await memosVM.loadCount()
        }
        .onAppear {
            Task {
                await checkSyncServiceStatus()
            }
        }
    }

    @ViewBuilder
    private func debugRow(label: String, value: String, icon: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 16)

            Text(label)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(Theme.current.fontSMMedium)
                .foregroundColor(valueColor ?? Theme.current.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.xs)
    }

    private var syncServiceStatusColor: Color {
        switch syncServiceStatus {
        case let status where status.hasPrefix("Available"): return .green
        case "Checking...": return .secondary
        default: return .orange
        }
    }

    private var syncStatusColor: Color {
        switch SyncStatusManager.shared.state {
        case .idle: return .gray
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        }
    }

    private var syncStatusText: String {
        switch SyncStatusManager.shared.state {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .error(let message): return "Error: \(message)"
        }
    }

    private func checkSyncServiceStatus() async {
        let availability = await SyncClient.shared.checkiCloudAvailability()
        if availability.available {
            syncServiceStatus = "Available"
        } else {
            syncServiceStatus = "Unavailable\(availability.error.map { ": \($0)" } ?? "")"
        }
    }
}

// MARK: - Server Settings Content

/// Server settings content wrapper - embeds ServerSettingsEmbeddable
struct ServerSettingsContent: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var bridgeManager = BridgeManager.shared
    @State private var showEnableAlert = false
    @State private var showClaudeEnableAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // ACCESS section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)
                    Text("SERVER ACCESS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Spacer()
                }

                Toggle(isOn: serverEnabledBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable TalkieServer")
                            .font(Theme.current.fontSMMedium)
                        Text("Explicitly unlock Bridge and Gateway server controls.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .settingsSectionCard(padding: Spacing.md)

            // STATUS section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(bridgeManager.bridgeStatus == .running ? Color.green : Color.orange)
                        .frame(width: 3, height: 14)
                    Text("SERVER STATUS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Spacer()
                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(bridgeManager.bridgeStatus == .running ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(bridgeManager.bridgeStatus.rawValue.uppercased())
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(bridgeManager.bridgeStatus == .running ? .green : .orange)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: bridgeManager.bridgeStatus.icon)
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(bridgeManager.bridgeStatus == .running ? .green : .orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(bridgeManager.bridgeStatus == .running ? "Server Running" : "Server \(bridgeManager.bridgeStatus.rawValue)")
                            .font(Theme.current.fontSMMedium)
                        Text(bridgeManager.bridgeStatus == .running ? "Port 8765 • Modules loaded" : "Server is not running")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    if bridgeManager.bridgeStatus == .running {
                        Button(action: { Task { await bridgeManager.stopBridge() } }) {
                            Text("STOP")
                                .font(Theme.current.fontXSBold)
                        }
                        .buttonStyle(.bordered)
                    } else if settingsManager.talkieServerEnabled {
                        Button(action: { Task { await bridgeManager.startBridge() } }) {
                            Text("START")
                                .font(Theme.current.fontXSBold)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // INFO
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("TalkieServer runs Bridge (iOS connectivity) and Gateway (external APIs) as modules. Both require Tailscale for secure networking. Full settings available at Settings → Helpers.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        }
        .onAppear {
            bridgeManager.checkStatus()
        }
        .alert("Enable TalkieServer?", isPresented: $showEnableAlert) {
            Button("Enable") {
                settingsManager.talkieServerEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This starts a local server for Bridge and optional Gateway modules.")
        }
    }

    private var serverEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.talkieServerEnabled },
            set: { newValue in
                if newValue {
                    showEnableAlert = true
                } else {
                    settingsManager.talkieServerEnabled = false
                    Task { await bridgeManager.stopBridge() }
                }
            }
        )
    }
}

// MARK: - Dev Control Content

#if DEBUG
/// Dev control content - embeds key dev panel features
struct DevControlContent: View {
    private let serviceManager = ServiceManager.shared
    @Environment(EngineClient.self) private var engineClient

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Service Status
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)
                    Text("ACTIVE CONNECTIONS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Spacer()
                    Button(action: { serviceManager.scan() }) {
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
                    // Engine status
                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(engineClient.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text("Engine")
                            .font(Theme.current.fontSM)
                        if let pid = engineClient.status?.pid {
                            Text("PID \(pid)")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)

                    // Agent status
                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(serviceManager.live.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text("Agent")
                            .font(Theme.current.fontSM)
                        if let pid = serviceManager.live.processId {
                            Text("PID \(pid)")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // Process Management
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red)
                        .frame(width: 3, height: 14)
                    Text("PROCESS MANAGEMENT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    Button(action: {
                        _ = serviceManager.killAllDaemons(service: "TalkieEngine")
                        _ = serviceManager.killAllXcode(service: "TalkieEngine")
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "xmark.circle")
                            Text("Kill All Engines")
                        }
                        .font(Theme.current.fontXSMedium)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button(action: {
                        _ = serviceManager.killAllDaemons(service: "TalkieAgent")
                        _ = serviceManager.killAllXcode(service: "TalkieAgent")
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "xmark.circle")
                            Text("Kill All Agent")
                        }
                        .font(Theme.current.fontXSMedium)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Spacer()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // Link to full panel
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("This is a summary view. For full dev controls including TTS testing, external data audit, and detailed logs, open the full Dev Control Panel from the Debug menu.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        }
        .onAppear {
            serviceManager.scan()
            serviceManager.live.startMonitoring()
        }
    }
}
#endif

// MARK: - Debug Info View (Legacy - kept for compatibility)

struct DebugInfoView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    private var memosVM: MemosViewModel { MemosViewModel.shared }
    @State private var syncServiceStatus: String = "Checking..."

    private let syncIntervalOptions = [1, 5, 10, 15, 30, 60]

    private var environment: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        @Bindable var settings = settingsManager

        return SettingsPageContainer {
            SettingsPageHeader(
                icon: "info.circle",
                title: "DEBUG INFO",
                subtitle: "Diagnostic information about the app environment."
            )
        } content: {
            // MARK: - App Info
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("APP INFORMATION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    // Environment badge
                    Text(environment.uppercased())
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(environment == "Development" ? Color.orange : Color.green)
                        .cornerRadius(CornerRadius.xs)
                }

                VStack(spacing: Spacing.sm) {
                    debugRow(label: "Bundle ID", value: bundleID, icon: "app.badge")
                    debugRow(label: "Version", value: "\(version) (\(build))", icon: "number")
                    debugRow(label: "Voice Memos", value: "\(memosVM.totalCount)", icon: "doc.text")
                    debugRow(label: "Last Sync", value: SyncStatusManager.shared.lastSyncAgo, icon: "arrow.triangle.2.circlepath")
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Rendering
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("RENDERING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if settingsManager.glassEffectsNeedsRestart {
                        Text("RESTART REQUIRED")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(CornerRadius.xs)
                    }
                }

                Toggle(isOn: $settings.enableGlassEffects) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Glass Effects")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foreground)
                        Text("Liquid glass backgrounds with blur and depth. Disable for better performance on older Macs.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(settingsManager.resolvedAccentColor)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                    Text("Current: \(GlassConfig.enableGlassEffects ? "Enabled" : "Disabled"). Changes require app restart.")
                        .font(Theme.current.fontXS)
                }
                .foregroundColor(Theme.current.foregroundMuted)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Sync Service Status
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("SYNC SERVICE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(spacing: Spacing.sm) {
                    debugRow(label: "Service Status", value: syncServiceStatus, icon: "arrow.triangle.2.circlepath", valueColor: syncServiceStatusColor)
                    debugRow(label: "Transport", value: "TalkieSync via XPC", icon: "cable.connector")
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Sync Status
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(syncStatusColor)
                        .frame(width: 3, height: 14)

                    Text("SYNC STATUS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 6, height: 6)
                        Text(syncStatusText.uppercased())
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(syncStatusColor)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Text("Sync every")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Picker("", selection: $settings.syncIntervalMinutes) {
                        ForEach(syncIntervalOptions, id: \.self) { minutes in
                            Text(minutes == 1 ? "1 minute" : "\(minutes) minutes")
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)

                    Spacer()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                Text("Manual sync is always available via the toolbar button. Lower intervals use more battery and network.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Onboarding
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("ONBOARDING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .font(Theme.current.fontHeadline)
                        .foregroundColor(.purple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Setup Wizard")
                            .font(Theme.current.fontSMMedium)
                        Text("Re-run the setup wizard to configure permissions, services, and models.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Button(action: {
                        OnboardingManager.shared.resetOnboarding()
                    }) {
                        Text("RESTART")
                            .font(Theme.current.fontXSBold)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Configuration (JSON)
            SettingsJSONExportView()

            #if DEBUG
            // MARK: - Live Settings Dump
            LiveSettingsDumpView()
            #endif
        }
        .task {
            await memosVM.loadCount()
        }
        .onAppear {
            Task {
                await checkSyncServiceStatus()
            }
        }
    }

    @ViewBuilder
    private func debugRow(label: String, value: String, icon: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 16)

            Text(label)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(Theme.current.fontSMMedium)
                .foregroundColor(valueColor ?? Theme.current.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.xs)
    }

    private var syncServiceStatusColor: Color {
        switch syncServiceStatus {
        case let status where status.hasPrefix("Available"): return .green
        case "Checking...": return .secondary
        default: return .orange
        }
    }

    private var syncStatusColor: Color {
        switch SyncStatusManager.shared.state {
        case .idle: return .gray
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        }
    }

    private var syncStatusText: String {
        switch SyncStatusManager.shared.state {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .error(let message): return "Error: \(message)"
        }
    }

    private func checkSyncServiceStatus() async {
        let availability = await SyncClient.shared.checkiCloudAvailability()
        if availability.available {
            syncServiceStatus = "Available"
        } else {
            syncServiceStatus = "Unavailable\(availability.error.map { ": \($0)" } ?? "")"
        }
    }
}

// MARK: - Settings JSON Export View

struct SettingsJSONExportView: View {
    @Environment(SettingsManager.self) private var settingsManager

    @State private var jsonText: String = ""
    @State private var showCopiedConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cyan)
                    .frame(width: 3, height: 14)

                Text("CONFIGURATION")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button(action: copyJSON) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(showCopiedConfirmation ? "COPIED" : "COPY")
                            .font(Theme.current.fontXSBold)
                    }
                }
                .buttonStyle(.bordered)
            }

            Text("Current settings as JSON (API keys are masked). Use this to understand your configuration or export for backup.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            ScrollView {
                Text(jsonText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
            }
            .frame(height: 300)
            .background(Theme.current.background)
            .cornerRadius(CornerRadius.xs)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .strokeBorder(Theme.current.divider, lineWidth: 1)
            )
        }
        .settingsSectionCard(padding: Spacing.md)
        .onAppear {
            refreshJSON()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreCoordinatorStoresDidChange)) { _ in
            // Retry when stores become available
            if jsonText.hasPrefix("//") {
                refreshJSON()
            }
        }
    }

    private func refreshJSON() {
        guard PersistenceController.isReady else {
            jsonText = "// Waiting for database..."
            return
        }
        jsonText = settingsManager.exportSettingsAsJSON()
    }

    private func copyJSON() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonText, forType: .string)

        showCopiedConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedConfirmation = false
        }
    }
}

// MARK: - Live Settings Dump View

#if DEBUG
struct LiveSettingsDumpView: View {
    @State private var settingsJSON: String = "Loading..."
    @State private var dumpPath: String = ""
    @State private var showCopiedConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange)
                    .frame(width: 3, height: 14)

                Text("LIVE SETTINGS DUMP")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button(action: loadSettings) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("REFRESH")
                            .font(Theme.current.fontXSBold)
                    }
                }
                .buttonStyle(.bordered)

                Button(action: copyJSON) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(showCopiedConfirmation ? "COPIED" : "COPY")
                            .font(Theme.current.fontXSBold)
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: Spacing.xs) {
                Text("Path:")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                Text(dumpPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ScrollView {
                Text(settingsJSON)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.current.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
            }
            .frame(height: 250)
            .background(Theme.current.background)
            .cornerRadius(CornerRadius.xs)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .strokeBorder(Theme.current.divider, lineWidth: 1)
            )

            Button(action: revealInFinder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text("Reveal in Finder")
                        .font(Theme.current.fontXS)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.current.accent)
        }
        .settingsSectionCard(padding: Spacing.md)
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("Talkie")
        let file = tmpDir.appendingPathComponent("settings-dump.json")
        dumpPath = file.path

        if let data = try? Data(contentsOf: file),
           let json = String(data: data, encoding: .utf8) {
            settingsJSON = json
        } else {
            settingsJSON = "No settings dump found.\nSettings will be dumped on next app launch or settings change."
        }
    }

    private func copyJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(settingsJSON, forType: .string)
        showCopiedConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedConfirmation = false
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(dumpPath, inFileViewerRootedAtPath: "")
    }
}
#endif

// MARK: - Performance Settings View

struct PerformanceSettingsView: View {
    @State private var selectedTab: PerformanceTab = .appPerformance

    enum PerformanceTab: String, CaseIterable {
        case appPerformance = "APP PERFORMANCE"
        case startup = "BOOT METRICS"

        var icon: String {
            switch self {
            case .appPerformance: return "chart.bar"
            case .startup: return "bolt"
            }
        }

        var color: Color {
            switch self {
            case .appPerformance: return .blue
            case .startup: return .orange
            }
        }
    }

    var body: some View {
        SettingsPageContainer {
            // No header - tabs are self-explanatory
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(PerformanceTab.allCases, id: \.rawValue) { tab in
                        performanceTabItem(tab)
                    }
                    Spacer()

                    // Quick links to external app settings
                    helperLinksMenu
                }
                .padding(.horizontal, Spacing.sm)

                // Tab indicator line
                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(height: 1)

                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case .appPerformance:
                        PerformanceDebugView()
                    case .startup:
                        StartupProfileView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func performanceTabItem(_ tab: PerformanceTab) -> some View {
        let isSelected = selectedTab == tab

        Button(action: { selectedTab = tab }) {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11))

                    Text(tab.rawValue)
                        .font(Theme.current.fontXSBold)
                }
                .foregroundColor(isSelected ? tab.color : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                // Active indicator
                Rectangle()
                    .fill(isSelected ? tab.color : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var helperLinksMenu: some View {
        Button(action: openLivePerformance) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10))
                Text("Agent Performance")
                    .font(Theme.current.fontXSMedium)
            }
            .foregroundColor(Theme.current.foregroundSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    private func openLivePerformance() {
        ServiceManager.shared.openHelperRoute(.agent, route: "performance")
    }
}

// MARK: - Startup Profile View

struct StartupProfileView: View {
    @State private var milestones: [(name: String, time: CFAbsoluteTime, elapsed: Double)] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STARTUP TIMELINE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("FROM PROCESS START")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let lastMilestone = milestones.last {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total Time")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("\(Int(lastMilestone.elapsed))ms")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(startupTimeColor(lastMilestone.elapsed))
                    }
                }

                Button(action: refresh) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                        Text("Refresh")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            if milestones.isEmpty {
                emptyStateView
            } else {
                milestonesListView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { refresh() }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bolt.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No startup data")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Startup profiling happens on app launch")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var milestonesListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 8) {
                    Text("ELAPSED")
                        .frame(width: 80, alignment: .leading)
                    Text("DELTA")
                        .frame(width: 70, alignment: .leading)
                    Text("MILESTONE")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                // Milestones
                ForEach(Array(milestones.enumerated()), id: \.offset) { index, milestone in
                    milestoneRow(milestone, previousTime: index > 0 ? milestones[index - 1].elapsed : 0)
                    if index < milestones.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func milestoneRow(_ milestone: (name: String, time: CFAbsoluteTime, elapsed: Double), previousTime: Double) -> some View {
        let delta = milestone.elapsed - previousTime

        return HStack(spacing: 8) {
            // Elapsed time
            Text("\(Int(milestone.elapsed))ms")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(startupTimeColor(milestone.elapsed))
                .frame(width: 80, alignment: .leading)

            // Delta
            if delta > 0.5 {
                Text("+\(Int(delta))ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(deltaColor(delta))
                    .frame(width: 70, alignment: .leading)
            } else {
                Text("—")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .leading)
            }

            // Milestone name
            Text(milestone.name)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func startupTimeColor(_ ms: Double) -> Color {
        if ms >= 3000 { return .red }
        if ms >= 1500 { return .orange }
        return .green
    }

    private func deltaColor(_ ms: Double) -> Color {
        if ms >= 500 { return .red }
        if ms >= 200 { return .orange }
        if ms >= 50 { return .yellow }
        return .secondary
    }

    private func refresh() {
        milestones = StartupProfiler.shared.milestones
    }
}
