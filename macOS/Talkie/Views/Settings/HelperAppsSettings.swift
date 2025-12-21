//
//  HelperAppsSettings.swift
//  Talkie macOS
//
//  Settings view for managing helper apps (TalkieLive, TalkieEngine)
//

import SwiftUI
import TalkieKit

struct HelperAppsSettingsView: View {
    @ObservedObject private var appLauncher = AppLauncher.shared
    @ObservedObject private var engineMonitor = TalkieServiceMonitor.shared
    @ObservedObject private var liveMonitor = TalkieLiveStateMonitor.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "app.connected.to.app.below.fill",
                title: "HELPER APPS",
                subtitle: "Manage background services that power Talkie features."
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                // TalkieEngine
                HelperAppRow(
                    name: "Transcription Engine",
                    description: "Transcription and AI processing service",
                    bundleId: AppLauncher.engineBundleId,
                    status: appLauncher.engineStatus,
                    processId: engineMonitor.processId,
                    environment: EngineClient.shared.connectedMode?.environment,
                    onLaunch: { appLauncher.launchEngine() },
                    onTerminate: { appLauncher.terminateEngine() },
                    onRegister: { appLauncher.registerEngine() },
                    onUnregister: { appLauncher.unregisterEngine() }
                )

                Divider()

                // TalkieLive
                HelperAppRow(
                    name: "Live",
                    description: "Voice capture and quick paste feature",
                    bundleId: AppLauncher.liveBundleId,
                    status: appLauncher.liveStatus,
                    processId: liveMonitor.processId,
                    environment: liveMonitor.connectedMode,
                    onLaunch: { appLauncher.launchLive() },
                    onTerminate: { appLauncher.terminateLive() },
                    onRegister: { appLauncher.registerLive() },
                    onUnregister: { appLauncher.unregisterLive() }
                )
            }

            Divider()
                .padding(.vertical, 8)

            // Actions
            HStack {
                Button(action: {
                    appLauncher.refreshStatus()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("REFRESH STATUS")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    appLauncher.openLoginItemsSettings()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                            .font(.system(size: 10))
                        Text("OPEN LOGIN ITEMS")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            // Info
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("Helper apps run in the background to provide voice capture and AI processing. They automatically start when you log in.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

// MARK: - Helper App Row

private struct HelperAppRow: View {
    let name: String
    let description: String
    let bundleId: String
    let status: AppLauncher.HelperStatus
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
                .cornerRadius(8)

            // Name and description
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                // Technical info (PID, Environment)
                if status == .running {
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
            }

            Spacer()

            // Status badge
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.system(size: 10))
                Text(status.rawValue)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .cornerRadius(4)

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
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
        .cornerRadius(8)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview {
    HelperAppsSettingsView()
        .frame(width: 500, height: 400)
        .padding()
}
