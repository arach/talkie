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
    private let liveState = ServiceManager.shared.live

    var body: some View {
        ServiceHealthCard(
            icon: "waveform.circle.fill",
            title: "Live Recording",
            isHealthy: liveState.isRunning,
            statusText: liveState.isRunning ? "Active" : "Inactive",
            detailText: liveState.isRunning
                ? "Live Mode is active and ready to record voice memos."
                : "Live Mode is not active. Enable Live Mode to access recording features and hotkeys.",
            action: liveState.isRunning ? nil : {
                // Launch TalkieLive
                launchTalkieLive()
            },
            actionLabel: "Enable Live Mode"
        )
        .onAppear {
            liveState.startMonitoring()
        }
    }

    private func launchTalkieLive() {
        // TODO: Implement TalkieLive launch
        let appPath = "/Applications/TalkieLive.app"
        if FileManager.default.fileExists(atPath: appPath) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath),
                                              configuration: NSWorkspace.OpenConfiguration())
        } else {
            // Try to find it in build products
            NSLog("[Talkie] TalkieLive.app not found at \(appPath)")
        }
    }
}

// MARK: - Engine Health Card

struct EngineHealthCard: View {
    private let serviceMonitor = ServiceManager.shared.engine
    @Environment(LiveSettings.self) private var liveSettings

    /// Last error from TalkieLive logs (read from log file)
    @State private var recentError: String? = nil
    @State private var showErrorPopover = false

    private var modelName: String {
        ModelInfo.formatModelName(liveSettings.selectedModelId)
    }

    var body: some View {
        VStack(spacing: 0) {
            ServiceHealthCard(
                icon: "cpu",
                title: "AI Transcription",
                isHealthy: serviceMonitor.state == .running && recentError == nil,
                statusText: statusText,
                detailText: detailText,
                action: serviceMonitor.state == .running ? nil : {
                    Task { await serviceMonitor.launch() }
                },
                actionLabel: "Start Engine"
            )

            // Show recent error if any
            if let error = recentError {
                Button(action: { showErrorPopover.toggle() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(SemanticColor.warning)
                        Text("Recent Error")
                            .font(Theme.current.fontXS)
                            .foregroundColor(SemanticColor.warning)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(SemanticColor.warning.opacity(0.1))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showErrorPopover, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("Recent XPC Error")
                                .font(Theme.current.fontSMBold)
                            Spacer()
                            Button(action: copyError) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("Copy error to clipboard")
                        }
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.current.foreground)
                            .textSelection(.enabled)

                        Divider()

                        Text("Try: Restart TalkieEngine (⌘Q then relaunch)")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Button("Dismiss Error") {
                            recentError = nil
                            showErrorPopover = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                    .frame(width: 350)
                }
            }
        }
        .onAppear {
            serviceMonitor.startMonitoring()
            checkForRecentErrors()
        }
    }

    private var statusText: String {
        switch serviceMonitor.state {
        case .running: return recentError != nil ? "Warning" : "Ready"
        case .stopped: return "Offline"
        case .launching: return "Starting..."
        case .terminating: return "Stopping..."
        case .unknown: return "Unknown"
        }
    }

    private var detailText: String {
        switch serviceMonitor.state {
        case .running:
            if recentError != nil {
                return "TalkieEngine is running but encountered an error."
            }
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

    private func copyError() {
        guard let error = recentError else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(error, forType: .string)
    }

    /// Check TalkieLive logs for recent XPC errors
    private func checkForRecentErrors() {
        // Load recent errors from TalkieLive logs
        let events = LogFileManager.shared.loadTodayEventsFrom(sources: [.talkieLive], limit: 50)
        let cutoff = Date().addingTimeInterval(-300) // Last 5 minutes

        // Find XPC-related errors
        let xpcErrors = events.filter { event in
            event.type == .error &&
            event.timestamp > cutoff &&
            (event.message.contains("XPC") || event.detail?.contains("XPC") == true)
        }

        if let latestError = xpcErrors.first {
            var errorText = latestError.message
            if let detail = latestError.detail {
                errorText += "\n\n\(detail)"
            }
            recentError = errorText
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
