//
//  ConnectionsSettingsSection.swift
//  TalkieLive
//
//  Connections settings: XPC service status, environment info
//

import SwiftUI
import TalkieKit

// MARK: - Connections Settings Section

struct ConnectionsSettingsSection: View {
    @State private var engineStatus: EngineConnectionStatus = .unknown
    @State private var talkieConnected = false
    @State private var isRefreshing = false

    private let myPID = ProcessInfo.processInfo.processIdentifier

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header - consistent glass style
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    // Icon in a subtle glass container
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Color.accentColor.opacity(0.12))
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                        Image(systemName: "network")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 36, height: 36)

                    // Title and subtitle stacked
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.sm) {
                            Text("CONNECTIONS")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(Tracking.normal)
                                .foregroundColor(TalkieTheme.textPrimary)

                            Spacer()

                            Button(action: refresh) {
                                if isRefreshing {
                                    BrailleSpinner()
                                        .font(.system(size: 12, weight: .medium))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(TalkieTheme.textSecondary)
                        }

                        Text("XPC service connections to Talkie ecosystem.")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }

                    Spacer()
                }

                // Subtle separator line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.top, Spacing.md)
            }

            // This Process
            ConnectionCard(
                title: "TalkieLive",
                subtitle: "This process",
                icon: "app.fill",
                status: .connected,
                pid: myPID,
                serviceName: nil
            )

            // TalkieEngine Connection
            ConnectionCard(
                title: "TalkieEngine",
                subtitle: "Transcription service",
                icon: "waveform",
                status: engineStatus,
                pid: engineStatus.pid,
                serviceName: TalkieEnvironment.current.engineXPCService
            )

            // Talkie Connection (observers)
            ConnectionCard(
                title: "Talkie",
                subtitle: "Main app (observing us)",
                icon: "app.badge.checkmark",
                status: talkieConnected ? .connected : .disconnected,
                pid: nil,
                serviceName: TalkieEnvironment.current.liveXPCService
            )

            // Environment Info
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("ENVIRONMENT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(Tracking.normal)
                    .foregroundColor(TalkieTheme.textTertiary)

                HStack {
                    Text("Mode:")
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textSecondary)
                    Text(TalkieEnvironment.current.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(TalkieTheme.accent)

                    Spacer()

                    if let bundleID = Bundle.main.bundleIdentifier {
                        Text(bundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .textSelection(.enabled)
                    }
                }
                .padding(Spacing.sm)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Color.white.opacity(0.04))
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.06),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                )
            }
        }
        .padding(Spacing.lg)
        .onAppear { refresh() }
        .onReceive(TalkieLiveXPCService.shared.$isTalkieConnected) { connected in
            talkieConnected = connected
        }
    }

    private func refresh() {
        isRefreshing = true

        // Check Engine connection
        Task {
            let client = EngineClient.shared
            let connected = await client.ensureConnected()

            await MainActor.run {
                if connected {
                    // Try to get PID from engine status
                    engineStatus = .connected
                } else {
                    engineStatus = .disconnected
                }

                // Check if Talkie is observing us
                talkieConnected = TalkieLiveXPCService.shared.isTalkieConnected

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isRefreshing = false
                }
            }
        }
    }
}

// MARK: - Engine Connection Status

enum EngineConnectionStatus {
    case unknown
    case connected
    case disconnected

    var pid: Int32? { nil }  // TODO: Get from engine status
}

// MARK: - Connection Card

struct ConnectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let status: EngineConnectionStatus
    var pid: Int32?
    var serviceName: String?

    @State private var isHovered = false

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .red
        case .unknown: return .orange
        }
    }

    private var statusText: String {
        switch status {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .unknown: return "Unknown"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(statusColor.opacity(isHovered ? 0.25 : 0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(statusColor)
            }
            .animation(TalkieAnimation.fast, value: isHovered)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)

                if let serviceName = serviceName {
                    Text(serviceName)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            Spacer()

            // Status + PID
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusColor)
                }

                if let pid = pid {
                    Text("PID \(pid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }
        }
        .padding(Spacing.md)
        .glassHover(isHovered: isHovered, cornerRadius: CornerRadius.md, accentColor: statusColor)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(statusColor.opacity(isHovered ? 0.4 : 0.2), lineWidth: isHovered ? 1 : 0.5)
                .animation(TalkieAnimation.fast, value: isHovered)
        )
        .onHover { isHovered = $0 }
    }
}
