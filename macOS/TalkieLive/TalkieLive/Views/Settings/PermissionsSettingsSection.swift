//
//  PermissionsSettingsSection.swift
//  TalkieLive
//
//  Permission Center - shows all required permissions and their status
//

import SwiftUI
import AVFoundation
import AppKit
import ApplicationServices

// MARK: - Permission Types

enum PermissionType: String, CaseIterable, Identifiable {
    case microphone
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .accessibility: return "hand.point.up.left.fill"
        }
    }

    var description: String {
        switch self {
        case .microphone:
            return "Required to record audio for transcription"
        case .accessibility:
            return "Required to automatically paste transcribed text (simulates Cmd+V)"
        }
    }

    var isRequired: Bool {
        // Both permissions are required for TalkieLive to function
        return true
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}

// MARK: - Permission Status

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
    case restricted

    var color: Color {
        switch self {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        case .restricted: return .gray
        }
    }

    var label: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not Set"
        case .restricted: return "Restricted"
        }
    }

    var icon: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .restricted: return "lock.circle.fill"
        }
    }
}

// MARK: - Permission Manager

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var accessibilityStatus: PermissionStatus = .notDetermined

    private var pollTimer: Timer?

    init() {
        refreshAll()
    }

    func refreshAll() {
        checkMicrophone()
        checkAccessibility()
    }

    func checkMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneStatus = .granted
        case .denied:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .restricted:
            microphoneStatus = .restricted
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }

    func checkAccessibility() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
    }

    func openSettings(for permission: PermissionType) {
        if permission == .accessibility {
            // Use system prompt - shows dialog and opens Settings with app pre-highlighted
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } else if let url = permission.settingsURL {
            NSWorkspace.shared.open(url)
        }

        // Start polling to detect when permission is granted
        startPolling()
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAll()
            }
        }

        // Stop polling after 60 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.stopPolling()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func status(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .microphone: return microphoneStatus
        case .accessibility: return accessibilityStatus
        }
    }

    var allRequiredGranted: Bool {
        microphoneStatus == .granted && accessibilityStatus == .granted
    }

    var grantedCount: Int {
        var count = 0
        if microphoneStatus == .granted { count += 1 }
        if accessibilityStatus == .granted { count += 1 }
        return count
    }

    var totalCount: Int { 2 }
}

// MARK: - Permissions Settings Section

struct PermissionsSettingsSection: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                headerSection

                // Status summary
                statusSummary

                // Permission rows
                VStack(spacing: Spacing.sm) {
                    ForEach(PermissionType.allCases) { permission in
                        PermissionSettingsRow(
                            permission: permission,
                            status: permissionManager.status(for: permission),
                            onRequest: {
                                handlePermissionRequest(permission)
                            }
                        )
                    }
                }

                // Troubleshooting tips
                troubleshootingSection
            }
            .padding(Spacing.lg)
        }
        .onAppear {
            permissionManager.refreshAll()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Spacing.md) {
                // Icon in a subtle glass container
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Color.accentColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .frame(width: 36, height: 36)

                // Title and subtitle stacked
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.sm) {
                        Text("PERMISSIONS")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(Tracking.normal)
                            .foregroundColor(TalkieTheme.textPrimary)

                        Spacer()

                        Button(action: {
                            isRefreshing = true
                            permissionManager.refreshAll()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                isRefreshing = false
                            }
                        }) {
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

                    Text("Grant required permissions for TalkieLive to function.")
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
    }

    // MARK: - Status Summary

    private var statusSummary: some View {
        HStack(spacing: Spacing.md) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(permissionManager.allRequiredGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: permissionManager.allRequiredGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 22))
                    .foregroundColor(permissionManager.allRequiredGranted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(permissionManager.allRequiredGranted ? "All Set" : "Action Required")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("\(permissionManager.grantedCount)/\(permissionManager.totalCount) permissions granted")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color.white.opacity(0.04))
                RoundedRectangle(cornerRadius: CornerRadius.md)
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
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
        )
    }

    // MARK: - Troubleshooting

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TROUBLESHOOTING")
                .font(.system(size: 10, weight: .bold))
                .tracking(Tracking.normal)
                .foregroundColor(TalkieTheme.textTertiary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                tipRow(icon: "arrow.clockwise", text: "Toggle permissions off and on if they seem stuck")
                tipRow(icon: "trash", text: "Remove and re-add the app in System Settings if issues persist")
                tipRow(icon: "hammer", text: "Permissions can reset after app updates or rebuilds")

                // Show bundle ID for dev/staging builds
                if let bundleID = Bundle.main.bundleIdentifier,
                   bundleID.hasSuffix(".dev") || bundleID.hasSuffix(".staging") {
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, Spacing.xs)

                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "app.badge")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Look for this app in System Settings:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(TalkieTheme.textSecondary)

                            Text(bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(TalkieTheme.textTertiary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: CornerRadius.md)
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
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            )
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(TalkieTheme.textTertiary)
                .frame(width: 14)

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(TalkieTheme.textSecondary)
        }
    }

    // MARK: - Actions

    private func handlePermissionRequest(_ permission: PermissionType) {
        switch permission {
        case .microphone:
            if permissionManager.microphoneStatus == .notDetermined {
                Task {
                    await permissionManager.requestMicrophone()
                }
            } else {
                permissionManager.openSettings(for: permission)
            }
        case .accessibility:
            permissionManager.openSettings(for: permission)
        }
    }
}

// MARK: - Permission Row

struct PermissionSettingsRow: View {
    let permission: PermissionType
    let status: PermissionStatus
    let onRequest: () -> Void

    @State private var isHovered = false
    @State private var isButtonHovered = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(status.color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: permission.icon)
                    .font(.system(size: 16))
                    .foregroundColor(status.color)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(permission.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TalkieTheme.textPrimary)
                        .lineLimit(1)

                    if permission.isRequired {
                        Text("Required")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)
                    }

                    Spacer()

                    // Status badge (moved inline with title)
                    HStack(spacing: 4) {
                        Image(systemName: status.icon)
                            .font(.system(size: 10))
                        Text(status.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(status.color)
                }

                Text(permission.description)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action button - glass style with hover
            Button(action: onRequest) {
                Text("Open Settings")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isButtonHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .glassHover(
                        isHovered: isButtonHovered,
                        cornerRadius: CornerRadius.xs,
                        baseOpacity: 0.04,
                        hoverOpacity: 0.15
                    )
            }
            .buttonStyle(.plain)
            .onHover { isButtonHovered = $0 }
        }
        .padding(Spacing.md)
        .glassHover(isHovered: isHovered, cornerRadius: CornerRadius.md)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    PermissionsSettingsSection()
        .frame(width: 500, height: 600)
        .background(TalkieTheme.background)
}
