//
//  PermissionsSettings.swift
//  Talkie macOS
//
//  Shows status of system permissions and allows opening System Settings
//

import SwiftUI
import AVFoundation
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Permissions")

// MARK: - Permission Status

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
    case restricted
    case unknown

    var displayName: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not Requested"
        case .restricted: return "Restricted"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .granted: return SemanticColor.success
        case .denied: return SemanticColor.error
        case .notDetermined: return SemanticColor.warning
        case .restricted: return SemanticColor.error
        case .unknown: return Theme.current.foregroundMuted
        }
    }

    var icon: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .restricted: return "lock.circle.fill"
        case .unknown: return "circle.dashed"
        }
    }
}

// MARK: - Permissions Manager

@MainActor
@Observable
class PermissionsManager {
    static let shared = PermissionsManager()

    var microphoneStatus: PermissionStatus = .unknown
    var accessibilityStatus: PermissionStatus = .unknown
    var automationStatus: PermissionStatus = .unknown

    private init() {
        // Don't check permissions eagerly - let views call refreshAllPermissions() on appear
        // This prevents triggering permission prompts just by accessing .shared
    }

    func refreshAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
        checkAutomationPermission()
    }

    // MARK: - Microphone

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .restricted:
            microphoneStatus = .restricted
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                self?.checkMicrophonePermission()
            }
        }
    }

    // MARK: - Accessibility

    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }

    func requestAccessibilityPermission() {
        // This opens System Settings to the Accessibility pane
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Recheck after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkAccessibilityPermission()
        }
    }

    // MARK: - Automation (AppleScript)

    func checkAutomationPermission() {
        // Try indirect detection: attempt to get app name via AppleScript
        // If it works, we likely have automation permission
        let script = """
        tell application "System Events"
            get name of first process whose frontmost is true
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)

            if error == nil && result.stringValue != nil {
                automationStatus = .granted
            } else {
                automationStatus = .denied
            }
        } else {
            automationStatus = .unknown
        }
    }

    // MARK: - Open System Settings

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Permissions Settings View

struct PermissionsSettingsView: View {
    private let permissionsManager = PermissionsManager.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "lock.shield",
                title: "PERMISSIONS",
                subtitle: "System permissions required for Talkie features."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Microphone
                PermissionRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    description: "Required for recording voice memos",
                    status: permissionsManager.microphoneStatus,
                    onRequest: {
                        if permissionsManager.microphoneStatus == .notDetermined {
                            permissionsManager.requestMicrophonePermission()
                        } else {
                            permissionsManager.openMicrophoneSettings()
                        }
                    }
                )

                Divider()

                // Accessibility
                PermissionRow(
                    icon: "accessibility",
                    name: "Accessibility",
                    description: "Required for Quick Open auto-paste feature",
                    status: permissionsManager.accessibilityStatus,
                    onRequest: {
                        permissionsManager.requestAccessibilityPermission()
                    }
                )

                Divider()

                // Automation
                PermissionRow(
                    icon: "gearshape.2.fill",
                    name: "Automation",
                    description: "Required for AppleScript workflows",
                    status: permissionsManager.automationStatus,
                    statusOverride: "Check in System Settings",
                    onRequest: {
                        permissionsManager.openAutomationSettings()
                    }
                )
            }

            Divider()
                .padding(.vertical, Spacing.sm)

            // Refresh button
            HStack {
                Button(action: {
                    permissionsManager.refreshAllPermissions()
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(Theme.current.fontXS)
                        Text("REFRESH STATUS")
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.foregroundMuted.opacity(Opacity.light))
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    permissionsManager.openPrivacySettings()
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "gear")
                            .font(Theme.current.fontXS)
                        Text("OPEN PRIVACY SETTINGS")
                            .font(Theme.current.fontXSMedium)
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.foregroundMuted.opacity(Opacity.light))
                    .cornerRadius(CornerRadius.xs)
                }
                .buttonStyle(.plain)
            }

            // Info note
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Text("Some permissions can only be changed in System Settings → Privacy & Security. Talkie will request permissions when features are first used.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Show app identifier for System Settings lookup (dev/staging builds only)
                if let bundleID = Bundle.main.bundleIdentifier,
                   bundleID.hasSuffix(".dev") || bundleID.hasSuffix(".staging") {
                    Divider()

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "app.badge")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Look for this app in System Settings:")
                                .font(Theme.current.fontXSMedium)
                                .foregroundColor(Theme.current.foregroundMuted)

                            Text(bundleID)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted.opacity(Opacity.prominent))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(Spacing.sm)
            .background(Theme.current.foregroundMuted.opacity(Opacity.subtle))
            .cornerRadius(CornerRadius.sm)
        }
        .onAppear {
            // Check permissions when view appears (not on init)
            permissionsManager.refreshAllPermissions()
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let name: String
    let description: String
    let status: PermissionStatus
    var statusOverride: String? = nil
    let onRequest: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            Image(systemName: icon)
                .font(Theme.current.fontTitle)
                .foregroundColor(status.color)
                .frame(width: 32, height: 32)
                .background(status.color.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.sm)

            // Name and description
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(name)
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(Theme.current.foreground)

                Text(description)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            // Status badge
            HStack(spacing: Spacing.xxs) {
                Image(systemName: status.icon)
                    .font(Theme.current.fontXS)
                Text(statusOverride ?? status.displayName)
                    .font(Theme.current.fontXSMedium)
            }
            .foregroundColor(statusOverride != nil ? Theme.current.foregroundMuted : status.color)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(status.color.opacity(Opacity.light))
            .cornerRadius(CornerRadius.xs)

            // Action button
            Button(action: onRequest) {
                Text(status == .granted ? "SETTINGS" : "ENABLE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(status == .granted ? Theme.current.foregroundMuted : .white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(status == .granted ? Theme.current.foregroundMuted.opacity(Opacity.medium) : Color.accentColor)
                    .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(isHovered ? Theme.current.surfaceHover : Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview {
    PermissionsSettingsView()
        .frame(width: 500, height: 400)
        .padding()
}
