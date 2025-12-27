//
//  PermissionsSettings.swift
//  Talkie macOS
//
//  Shows status of system permissions and allows opening System Settings
//

import SwiftUI
import AppKit
import AVFoundation
import os
import TalkieKit

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

    // Talkie's own permissions
    var microphoneStatus: PermissionStatus = .unknown
    var accessibilityStatus: PermissionStatus = .unknown
    var automationStatus: PermissionStatus = .unknown

    // TalkieLive's permissions (queried via XPC)
    var liveMicrophoneStatus: PermissionStatus = .unknown
    var liveAccessibilityStatus: PermissionStatus = .unknown
    var liveScreenRecordingStatus: PermissionStatus = .unknown
    var isLiveConnected: Bool = false

    private init() {
        // Don't check permissions eagerly - let views call refreshAllPermissions() on appear
        // This prevents triggering permission prompts just by accessing .shared
    }

    func refreshAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
        checkAutomationPermission()
        checkLivePermissions()
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

    // MARK: - TalkieLive Permissions (via XPC)

    func checkLivePermissions() {
        // Query TalkieLive's permissions via XPC
        let serviceManager = ServiceManager.shared

        // Only check if Live is running and connected
        guard serviceManager.live.isXPCConnected else {
            isLiveConnected = false
            liveMicrophoneStatus = .unknown
            liveAccessibilityStatus = .unknown
            liveScreenRecordingStatus = .unknown
            return
        }

        isLiveConnected = true

        // Get the XPC proxy and query permissions
        // We use ServiceManager's XPC connection to call getPermissions
        Task {
            await queryLivePermissionsViaXPC()
        }
    }

    private func queryLivePermissionsViaXPC() async {
        // Create a temporary XPC connection to query permissions
        let serviceName = TalkieEnvironment.current.liveXPCService
        let connection = NSXPCConnection(machServiceName: serviceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: TalkieLiveXPCServiceProtocol.self)
        connection.resume()

        defer { connection.invalidate() }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            logger.error("Failed to get Live permissions: \(error.localizedDescription)")
        }) as? TalkieLiveXPCServiceProtocol else {
            return
        }

        await withCheckedContinuation { continuation in
            proxy.getPermissions { [weak self] mic, accessibility, screenRecording in
                Task { @MainActor in
                    self?.liveMicrophoneStatus = mic ? .granted : .denied
                    self?.liveAccessibilityStatus = accessibility ? .granted : .denied
                    self?.liveScreenRecordingStatus = screenRecording ? .granted : .denied
                    continuation.resume()
                }
            }
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
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

    private var grantedCount: Int {
        [
            permissionsManager.microphoneStatus == .granted,
            permissionsManager.accessibilityStatus == .granted,
            permissionsManager.automationStatus == .granted
        ].filter { $0 }.count
    }

    private var liveGrantedCount: Int {
        [
            permissionsManager.liveMicrophoneStatus == .granted,
            permissionsManager.liveAccessibilityStatus == .granted,
            permissionsManager.liveScreenRecordingStatus == .granted
        ].filter { $0 }.count
    }

    private var livePermissionsColor: Color {
        if !permissionsManager.isLiveConnected {
            return Theme.current.foregroundMuted
        }
        return liveGrantedCount == 3 ? SemanticColor.success : SemanticColor.warning
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "lock.shield",
                title: "PERMISSIONS",
                subtitle: "System permissions required for Talkie features."
            )
        } content: {
            // MARK: - Required Permissions Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(grantedCount == 3 ? SemanticColor.success : SemanticColor.warning)
                        .frame(width: 3, height: 14)

                    Text("REQUIRED PERMISSIONS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(grantedCount == 3 ? SemanticColor.success : SemanticColor.warning)
                            .frame(width: 6, height: 6)
                        Text("\(grantedCount)/3 GRANTED")
                            .font(.techLabelSmall)
                            .foregroundColor(grantedCount == 3 ? SemanticColor.success : SemanticColor.warning)
                    }
                }

                VStack(spacing: Spacing.sm) {
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
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - TalkieLive Permissions Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(livePermissionsColor)
                        .frame(width: 3, height: 14)

                    Text("TALKIE LIVE PERMISSIONS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if permissionsManager.isLiveConnected {
                        HStack(spacing: Spacing.xxs) {
                            Circle()
                                .fill(livePermissionsColor)
                                .frame(width: 6, height: 6)
                            Text("\(liveGrantedCount)/3 GRANTED")
                                .font(.techLabelSmall)
                                .foregroundColor(livePermissionsColor)
                        }
                    } else {
                        HStack(spacing: Spacing.xxs) {
                            Circle()
                                .fill(Theme.current.foregroundMuted)
                                .frame(width: 6, height: 6)
                            Text("NOT CONNECTED")
                                .font(.techLabelSmall)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                }

                if permissionsManager.isLiveConnected {
                    VStack(spacing: Spacing.sm) {
                        // Live Microphone
                        PermissionRow(
                            icon: "mic.fill",
                            name: "Microphone (Live)",
                            description: "Required for live dictation",
                            status: permissionsManager.liveMicrophoneStatus,
                            onRequest: {
                                permissionsManager.openMicrophoneSettings()
                            }
                        )

                        // Live Accessibility (for autopaste)
                        PermissionRow(
                            icon: "accessibility",
                            name: "Accessibility (Live)",
                            description: "Required for autopaste - paste transcribed text automatically",
                            status: permissionsManager.liveAccessibilityStatus,
                            onRequest: {
                                permissionsManager.openAccessibilitySettings()
                            }
                        )

                        // Live Screen Recording
                        PermissionRow(
                            icon: "rectangle.dashed.badge.record",
                            name: "Screen Recording (Live)",
                            description: "Required for screen context features",
                            status: permissionsManager.liveScreenRecordingStatus,
                            onRequest: {
                                permissionsManager.openScreenRecordingSettings()
                            }
                        )
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(SemanticColor.warning)
                        Text("TalkieLive is not running. Start it to check permissions.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Spacer()
                        Button("Launch Live") {
                            ServiceManager.shared.launchLive()
                            // Refresh after a delay to pick up the new connection
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                permissionsManager.refreshAllPermissions()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Actions Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(SemanticColor.pin)
                        .frame(width: 3, height: 14)

                    Text("ACTIONS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    Button(action: {
                        permissionsManager.refreshAllPermissions()
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.clockwise")
                                .font(Theme.current.fontXS)
                            Text("Refresh Status")
                                .font(Theme.current.fontXSMedium)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        permissionsManager.openPrivacySettings()
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "gear")
                                .font(Theme.current.fontXS)
                            Text("Open Privacy Settings")
                                .font(Theme.current.fontXSMedium)
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Info Note
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .font(Theme.current.fontSM)
                    .foregroundColor(SemanticColor.pin)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Some permissions can only be changed in System Settings → Privacy & Security. Talkie will request permissions when features are first used.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Show app identifier for System Settings lookup (dev/staging builds only)
                    if let bundleID = Bundle.main.bundleIdentifier,
                       bundleID.hasSuffix(".dev") || bundleID.hasSuffix(".staging") {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "app.badge")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Text("Look for: \(bundleID)")
                                .font(.monoXSmall)
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .textSelection(.enabled)
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.xs)
                    }
                }
            }
            .padding(Spacing.sm)
            .background(SemanticColor.pin.opacity(Opacity.light))
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
