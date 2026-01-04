//
//  HelperAppsSettings.swift
//  Talkie macOS
//
//  Settings view for managing helper apps (TalkieLive, TalkieEngine)
//

import SwiftUI
import TalkieKit

struct HelperAppsSettingsView: View {
    private let serviceManager = ServiceManager.shared
    @State private var isRefreshing = false

    var body: some View {
        SettingsPageContainer {
            HStack {
                SettingsPageHeader(
                    icon: "app.connected.to.app.below.fill",
                    title: "HELPER APPS",
                    subtitle: "Manage background services that power Talkie features."
                )
                Spacer()
                Button(action: {
                    isRefreshing = true
                    serviceManager.refreshStatus()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        isRefreshing = false
                    }
                }) {
                    Group {
                        if isRefreshing {
                            BrailleSpinner(speed: 0.08)
                                .font(.system(size: 12))
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        } content: {
            // Helper Apps Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green)
                        .frame(width: 3, height: 14)

                    Text("BACKGROUND SERVICES")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    let runningCount = [serviceManager.engineStatus, serviceManager.liveStatus].filter { $0 == .running }.count
                    Text("\(runningCount)/2 RUNNING")
                        .font(.techLabelSmall)
                        .foregroundColor(runningCount == 2 ? .green : .orange)
                }

                VStack(spacing: Spacing.sm) {
                    // TalkieEngine
                    HelperAppRow(
                        name: "Transcription Engine",
                        description: "Transcription and AI processing service",
                        bundleId: ServiceManager.engineBundleId,
                        status: serviceManager.engineStatus,
                        processId: serviceManager.engine.processId,
                        environment: EngineClient.shared.connectedMode,
                        onLaunch: { serviceManager.launchEngine() },
                        onTerminate: { serviceManager.terminateEngine() },
                        onRegister: { serviceManager.registerEngine() },
                        onUnregister: { serviceManager.unregisterEngine() }
                    )

                    // TalkieLive
                    HelperAppRow(
                        name: "Live",
                        description: "Voice capture and quick paste feature",
                        bundleId: ServiceManager.liveBundleId,
                        status: serviceManager.liveStatus,
                        processId: serviceManager.live.processId,
                        environment: serviceManager.live.connectedMode,
                        onLaunch: { serviceManager.launchLive() },
                        onTerminate: { serviceManager.terminateLive() },
                        onRegister: { serviceManager.registerLive() },
                        onUnregister: { serviceManager.unregisterLive() }
                    )
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // Actions Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("SYSTEM SETTINGS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Button(action: {
                    serviceManager.openLoginItemsSettings()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                            .font(Theme.current.fontXS)
                        Text("OPEN LOGIN ITEMS")
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }
            .settingsSectionCard(padding: Spacing.md)

            // Info Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("ABOUT HELPERS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Helper apps run in the background to provide voice capture and AI processing. They automatically start when you log in.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // Developer options (only show if running dev build)
            #if DEBUG
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("DEVELOPER OPTIONS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.purple)
                }

                HelperEnvironmentPicker(serviceManager: serviceManager)
            }
            .settingsSectionCard(padding: Spacing.md)
            #endif
        }
        .onAppear {
            // Start monitoring to get PID and connection status
            serviceManager.live.startMonitoring()
        }
    }
}

// MARK: - Helper App Row

private struct HelperAppRow: View {
    let name: String
    let description: String
    let bundleId: String
    let status: ServiceManager.HelperStatus
    let processId: pid_t?
    let environment: TalkieEnvironment?
    let onLaunch: () -> Void
    let onTerminate: () -> Void
    let onRegister: () -> Void
    let onUnregister: () -> Void

    @State private var isHovered = false

    private var statusColor: Color {
        switch status {
        case .running, .enabled:
            return .green
        case .requiresApproval, .notRegistered:
            return .orange
        case .notFound, .notRunning, .unknown:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: status == .running ? "app.badge.checkmark.fill" : "app.fill")
                .font(.system(size: 24))
                .foregroundColor(statusColor)
                .frame(width: 40, height: 40)
                .background(statusColor.opacity(0.15))
                .cornerRadius(CornerRadius.sm)

            // Name and description
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(description)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                // Technical info (PID, Environment)
                HStack(spacing: 8) {
                    if let pid = processId {
                        HStack(spacing: 3) {
                            Image(systemName: "number")
                                .font(.system(size: 8))
                            Text(verbatim: "PID \(String(format: "%d", pid))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }

                    if let env = environment, env != .production {
                        HStack(spacing: 3) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 8))
                            Text(env.displayName)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(env == .dev ? .purple.opacity(0.8) : .orange.opacity(0.8))
                    }
                }
            }

            Spacer()

            // Status badge
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(Theme.current.fontXS)
                Text(status.rawValue)
                    .font(Theme.current.fontXSMedium)
            }
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .cornerRadius(CornerRadius.xs)

            // Actions menu
            Menu {
                if status == .running {
                    Button(action: onTerminate) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                } else {
                    Button(action: onLaunch) {
                        Label("Start", systemImage: "play.fill")
                    }
                }

                Divider()

                if status == .notRegistered || status == .notFound {
                    Button(action: onRegister) {
                        Label("Enable at Login", systemImage: "checkmark.circle")
                    }
                } else {
                    Button(action: onUnregister) {
                        Label("Disable at Login", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
                    .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Helper Environment Picker (Debug only)

#if DEBUG
private struct HelperEnvironmentPicker: View {
    let serviceManager: ServiceManager

    private var currentEnvBinding: Binding<TalkieEnvironment> {
        Binding(
            get: { serviceManager.effectiveHelperEnvironment },
            set: { serviceManager.helperEnvironmentOverride = ($0 == TalkieEnvironment.current) ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Text("Launch helpers from:")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Picker("", selection: currentEnvBinding) {
                    Text("Current (\(TalkieEnvironment.current.displayName))")
                        .tag(TalkieEnvironment.current)
                    ForEach(TalkieEnvironment.allCases.filter { $0 != TalkieEnvironment.current }, id: \.self) { env in
                        Text(env.displayName).tag(env)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()
            }

            if serviceManager.helperEnvironmentOverride != nil {
                Text("Override active: launching \(serviceManager.effectiveHelperEnvironment.displayName) helpers regardless of app environment")
                    .font(.system(size: 9))
                    .foregroundColor(.orange.opacity(0.8))
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }
}
#endif

// MARK: - Preview

#Preview {
    HelperAppsSettingsView()
        .frame(width: 500, height: 400)
        .padding()
}
