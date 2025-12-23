//
//  ServiceHealthCard.swift
//  Talkie
//
//  Health status cards for Live and Engine services
//  Shows simple green/red status for regular users
//  Expands to show technical details when enabled
//

import SwiftUI

// MARK: - Service Health Card

struct ServiceHealthCard: View {
    let icon: String
    let title: String
    let isHealthy: Bool
    let statusText: String
    let detailText: String?
    var action: (() -> Void)? = nil
    var actionLabel: String = "Restart"

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with icon and title
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(statusColor)

                Text(title)
                    .font(Theme.current.fontSM)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(statusColor)
                }
            }

            // Detail text
            if let detailText = detailText {
                Text(detailText)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action button when unhealthy
            if !isHealthy, let action = action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                        Text(actionLabel)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusColor)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .onHover { isHovered = $0 }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(TalkieTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var statusColor: Color {
        isHealthy ? SemanticColor.success : SemanticColor.error
    }
}

// MARK: - Live Recording Health Card

struct LiveRecordingHealthCard: View {
    private let liveClient = TalkieLiveClient.shared

    var body: some View {
        ServiceHealthCard(
            icon: "waveform.circle.fill",
            title: "Live Recording",
            isHealthy: liveClient.isRunning,
            statusText: liveClient.isRunning ? "Ready" : "Offline",
            detailText: liveClient.isRunning
                ? "Live Mode is active and ready to record voice memos."
                : "Live Mode is not active. Enable Live Mode to access recording features and hotkeys.",
            action: liveClient.isRunning ? nil : {
                liveClient.launchTalkieLive()
            },
            actionLabel: "Enable Live Mode"
        )
    }
}

// MARK: - Engine Health Card

struct EngineHealthCard: View {
    private let serviceMonitor = TalkieServiceMonitor.shared
    @Environment(LiveSettings.self) private var liveSettings

    private var modelName: String {
        ModelInfo.formatModelName(liveSettings.selectedModelId)
    }

    var body: some View {
        ServiceHealthCard(
            icon: "cpu",
            title: "AI Transcription",
            isHealthy: serviceMonitor.state == .running,
            statusText: statusText,
            detailText: detailText,
            action: serviceMonitor.state == .running ? nil : {
                Task { await serviceMonitor.launch() }
            },
            actionLabel: "Start Engine"
        )
        .onAppear {
            serviceMonitor.startMonitoring()
        }
    }

    private var statusText: String {
        switch serviceMonitor.state {
        case .running: return "Ready"
        case .stopped: return "Offline"
        case .launching: return "Starting..."
        case .terminating: return "Stopping..."
        case .unknown: return "Unknown"
        }
    }

    private var detailText: String {
        switch serviceMonitor.state {
        case .running:
            return "TalkieEngine is running with \(modelName) model."
        case .stopped:
            return "TalkieEngine is not running. Transcription features are unavailable."
        case .launching:
            return "TalkieEngine is starting up..."
        case .terminating:
            return "TalkieEngine is shutting down..."
        case .unknown:
            return "TalkieEngine state is unknown."
        }
    }
}

// MARK: - Preview

#Preview("Healthy") {
    VStack(spacing: Spacing.md) {
        ServiceHealthCard(
            icon: "waveform.circle.fill",
            title: "Live Recording",
            isHealthy: true,
            statusText: "Ready",
            detailText: "TalkieLive is running and ready to record voice memos."
        )

        ServiceHealthCard(
            icon: "cpu",
            title: "AI Transcription",
            isHealthy: true,
            statusText: "Ready",
            detailText: "TalkieEngine is running with Whisper Large v3 model."
        )
    }
    .padding()
    .frame(width: 500)
    .background(Color.black)
}

#Preview("Offline") {
    VStack(spacing: Spacing.md) {
        ServiceHealthCard(
            icon: "waveform.circle.fill",
            title: "Live Recording",
            isHealthy: false,
            statusText: "Offline",
            detailText: "TalkieLive is not running. Live recording features are unavailable.",
            action: { print("Start Live") },
            actionLabel: "Start Live"
        )

        ServiceHealthCard(
            icon: "cpu",
            title: "AI Transcription",
            isHealthy: false,
            statusText: "Offline",
            detailText: "TalkieEngine is not running. Transcription features are unavailable.",
            action: { print("Start Engine") },
            actionLabel: "Start Engine"
        )
    }
    .padding()
    .frame(width: 500)
    .background(Color.black)
}
