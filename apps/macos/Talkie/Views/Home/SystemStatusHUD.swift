//
//  SystemStatusHUD.swift
//  Talkie
//
//  System status overview with Account Settings aesthetic.
//  Shows the core state of services, permissions, and user activity.
//
//  NOTE: This is the expandable HUD component (collapsed dot + "All systems ready", expands on click).
//  For the terminal-style grid card, see SystemStatusCardView in HomeGridCards.swift.
//

import SwiftUI
import TalkieKit

// MARK: - System Status HUD

/// A polished system status indicator inspired by Account Settings aesthetic.
/// Shows core information about services, permissions, and activity.
struct SystemStatusHUD: View {
    // Service states
    private let liveState = ServiceManager.shared.live
    private let engineState = ServiceManager.shared.engine
    private let permissions = PermissionsManager.shared

    @State private var isExpanded = false
    @State private var expandedSection: StatusSection? = nil
    @State private var externalSyncAvailable = false
    @State private var externalSyncStatusText = "Checking..."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed: Minimal status bar
            collapsedHeader

            // Expanded: Detailed status sections
            if isExpanded {
                Divider()
                    .padding(.horizontal, Spacing.md)

                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.current.backgroundSecondary.opacity(0.3))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.border.opacity(0.5), lineWidth: 1)
        }
        .cornerRadius(CornerRadius.sm)
        .onAppear {
            permissions.refreshPassivePermissions()
            Task { await checkExternalSyncStatus() }
        }
    }

    // MARK: - Collapsed Header

    private var collapsedHeader: some View {
        Button {
            withAnimation(TalkieAnimation.microSpring) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(overallStatusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: overallStatusColor.opacity(0.5), radius: 3)

                    Text(overallStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                // Quick stats
                if !isExpanded {
                    quickStats
                }

                // Expand indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var quickStats: some View {
        HStack(spacing: Spacing.md) {
            // Agent readiness
            HStack(spacing: 4) {
                Circle()
                    .fill(liveState.isRunning ? SemanticColor.success : SemanticColor.warning)
                    .frame(width: 5, height: 5)
                Text(liveState.isRunning ? "Agent Ready" : "Agent Off")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Model loaded indicator
            if let modelId = engineState.loadedModelId {
                Text(modelShortName(modelId))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Services section
            statusSection(
                section: .services,
                number: "001",
                category: "SERVICES",
                headline: servicesHeadline,
                rows: servicesRows
            )

            Divider()
                .padding(.leading, 136)

            // Permissions section
            statusSection(
                section: .permissions,
                number: "002",
                category: "PERMISSIONS",
                headline: permissionsHeadline,
                rows: permissionsRows
            )

            Divider()
                .padding(.leading, 136)

            // Data section
            statusSection(
                section: .data,
                number: "003",
                category: "DATA",
                headline: dataHeadline,
                rows: dataRows
            )
        }
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Section Builder

    private func statusSection(
        section: StatusSection,
        number: String,
        category: String,
        headline: String,
        rows: [StatusRow]
    ) -> some View {
        let isActive = rows.allSatisfy { $0.status == .ok }
        let isSectionExpanded = expandedSection == section

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSection = isSectionExpanded ? nil : section
                }
            } label: {
                HStack(alignment: .center, spacing: Spacing.lg) {
                    // Number and category
                    HStack(spacing: 0) {
                        Text(number)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(isActive ? SemanticColor.success : Theme.current.foregroundMuted.opacity(0.5))

                        Text(" / ")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted.opacity(0.3))

                        Text(category)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(isActive ? SemanticColor.success : Theme.current.foregroundMuted.opacity(0.5))
                    }
                    .frame(width: 110, alignment: .leading)

                    // Headline
                    Text(headline)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)

                    Spacer()

                    // Status summary
                    statusSummary(rows: rows)

                    // Expand indicator
                    Image(systemName: isSectionExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Theme.current.foregroundMuted.opacity(0.5))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded rows
            if isSectionExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rows, id: \.label) { row in
                        statusRow(row)
                    }
                }
                .padding(.leading, 126)
                .padding(.trailing, Spacing.md)
                .padding(.bottom, Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isActive ? Theme.current.backgroundTertiary.opacity(0.2) : Color.clear)
    }

    private func statusSummary(rows: [StatusRow]) -> some View {
        let okCount = rows.filter { $0.status == .ok }.count
        let total = rows.count

        return HStack(spacing: 4) {
            if okCount == total {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(SemanticColor.success)
            } else {
                Text("\(okCount)/\(total)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(okCount == total ? SemanticColor.success : SemanticColor.warning)
            }
        }
    }

    private func statusRow(_ row: StatusRow) -> some View {
        HStack(spacing: Spacing.sm) {
            // Status icon
            Image(systemName: row.status.icon)
                .font(.system(size: 10))
                .foregroundColor(row.status.color)
                .frame(width: 14)

            // Label
            Text(row.label)
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foreground)

            Spacer()

            // Value
            Text(row.value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)

            // Action button if available
            if let action = row.action {
                Button(action: action.handler) {
                    Text(action.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.current.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Status Calculations

    private var overallStatusColor: Color {
        let issues = countIssues()
        if issues == 0 { return SemanticColor.success }
        if issues <= 2 { return SemanticColor.warning }
        return SemanticColor.error
    }

    private var overallStatusText: String {
        let issues = countIssues()
        if issues == 0 { return "All systems ready" }
        if issues == 1 { return "1 item needs attention" }
        return "\(issues) items need attention"
    }

    private func countIssues() -> Int {
        // Only count critical permission issues — services not running is a soft nudge, not an error
        var issues = 0
        if permissions.microphoneStatus != .granted { issues += 1 }
        if permissions.accessibilityStatus != .granted { issues += 1 }
        return issues
    }

    private func modelShortName(_ modelId: String) -> String {
        if modelId.contains("parakeet") {
            return "PKT"
        } else if modelId.contains("whisper") {
            return "WSP"
        }
        return "AI"
    }

    // MARK: - Section Data

    private var servicesHeadline: String {
        if liveState.isRunning && engineState.isRunning {
            return "Agent and transcription ready"
        } else if !liveState.isRunning {
            return "Agent available on demand"
        } else {
            return "Agent running, transcription warming up"
        }
    }

    private var servicesRows: [StatusRow] {
        [
            StatusRow(
                label: "TalkieAgent",
                status: liveState.isRunning ? .ok : .warning,
                value: liveState.isRunning ? "Running" : "Stopped",
                action: !liveState.isRunning ? StatusAction(label: "Start", handler: {
                    ServiceManager.shared.launchLive(resolvingConflicts: true)
                }) : nil
            ),
            StatusRow(
                label: "Transcription",
                status: engineState.isRunning ? .ok : (liveState.isRunning ? .pending : .warning),
                value: engineState.isRunning ? (engineState.loadedModelId ?? "Ready") : (liveState.isRunning ? "Starting" : "Agent stopped"),
                action: !liveState.isRunning ? StatusAction(label: "Start Agent", handler: {
                    ServiceManager.shared.launchLive(resolvingConflicts: true)
                }) : nil
            )
        ]
    }

    private var permissionsHeadline: String {
        let mic = permissions.microphoneStatus == .granted
        let ax = permissions.accessibilityStatus == .granted
        let sr = permissions.screenRecordingStatus == .granted
        if mic && ax && sr {
            return "All permissions granted"
        } else if mic && ax {
            return "Core permissions granted"
        } else if !mic && !ax {
            return "Permissions required"
        } else {
            return "Some permissions missing"
        }
    }

    private var permissionsRows: [StatusRow] {
        [
            StatusRow(
                label: "Microphone",
                status: statusFor(permissions.microphoneStatus),
                value: permissions.microphoneStatus.displayName,
                action: permissions.microphoneStatus != .granted ? StatusAction(label: "Grant", handler: {
                    permissions.openMicrophoneSettings()
                }) : nil
            ),
            StatusRow(
                label: "Accessibility",
                status: statusFor(permissions.accessibilityStatus),
                value: permissions.accessibilityStatus.displayName,
                action: permissions.accessibilityStatus != .granted ? StatusAction(label: "Grant", handler: {
                    permissions.openAccessibilitySettings()
                }) : nil
            ),
            StatusRow(
                label: "Screen Recording",
                status: permissions.screenRecordingStatus == .granted ? .ok : .pending,
                value: permissions.screenRecordingStatus.displayName,
                action: permissions.screenRecordingStatus != .granted ? StatusAction(label: "Grant", handler: {
                    permissions.openScreenRecordingSettings()
                }) : nil
            )
        ]
    }

    private var dataHeadline: String {
        externalSyncAvailable ? "Syncing via external service" : "Local storage"
    }

    private var dataRows: [StatusRow] {
        [
            StatusRow(
                label: "External Sync",
                status: externalSyncAvailable ? .ok : .pending,
                value: externalSyncStatusText
            ),
            StatusRow(
                label: "Storage",
                status: .ok,
                value: "Local + TalkieSync"
            )
        ]
    }

    private func statusFor(_ permission: PermissionStatus) -> StatusRow.RowStatus {
        switch permission {
        case .granted: return .ok
        case .denied, .restricted: return .error
        case .notDetermined, .unknown: return .pending
        }
    }

    private func checkExternalSyncStatus() async {
        let status = await SyncClient.shared.checkiCloudAvailability()
        externalSyncAvailable = status.available
        externalSyncStatusText = status.available ? "Connected" : "Unavailable"
    }
}

// MARK: - Supporting Types

private enum StatusSection: String {
    case services
    case permissions
    case data
}

private struct StatusRow {
    let label: String
    let status: RowStatus
    let value: String
    var action: StatusAction? = nil

    enum RowStatus {
        case ok
        case warning
        case error
        case pending

        @MainActor
        var color: Color {
            switch self {
            case .ok: return SemanticColor.success
            case .warning: return SemanticColor.warning
            case .error: return SemanticColor.error
            case .pending: return Theme.current.foregroundMuted
            }
        }

        var icon: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .pending: return "circle.dashed"
            }
        }
    }
}

private struct StatusAction {
    let label: String
    let handler: () -> Void
}

// MARK: - Legacy Types for Compatibility

struct StatusLine: Identifiable {
    let id = UUID()
    let label: String
    let status: LineStatus
    let value: String

    enum LineStatus {
        case ok
        case warning
        case error
        case pending

        @MainActor
        var color: Color {
            switch self {
            case .ok: return SemanticColor.success
            case .warning: return SemanticColor.warning
            case .error: return SemanticColor.error
            case .pending: return Theme.current.foregroundMuted
            }
        }

        var icon: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .pending: return "circle.dashed"
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        SystemStatusHUD()
            .frame(width: 450)

        Spacer()
    }
    .padding()
    .background(Theme.current.surfaceBase)
}
#endif
