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
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        case .restricted: return .red
        case .unknown: return .secondary
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
class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var microphoneStatus: PermissionStatus = .unknown
    @Published var accessibilityStatus: PermissionStatus = .unknown
    @Published var automationStatus: PermissionStatus = .unknown

    private init() {
        refreshAllPermissions()
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
        // There's no direct API to check automation permission
        // We'll mark it as unknown/not determinable programmatically
        // The user needs to check System Settings manually
        automationStatus = .unknown
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
    @StateObject private var permissionsManager = PermissionsManager.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "lock.shield",
                title: "PERMISSIONS",
                subtitle: "System permissions required for Talkie features."
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
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
                .padding(.vertical, 8)

            // Refresh button
            HStack {
                Button(action: {
                    permissionsManager.refreshAllPermissions()
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
                    permissionsManager.openPrivacySettings()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                            .font(.system(size: 10))
                        Text("OPEN PRIVACY SETTINGS")
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

            // Info note
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("Some permissions can only be changed in System Settings → Privacy & Security. Talkie will request permissions when features are first used.")
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
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(status.color)
                .frame(width: 32, height: 32)
                .background(status.color.opacity(0.15))
                .cornerRadius(8)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status badge
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.system(size: 10))
                Text(statusOverride ?? status.displayName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundColor(statusOverride != nil ? .secondary : status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.1))
            .cornerRadius(4)

            // Action button
            Button(action: onRequest) {
                Text(status == .granted ? "SETTINGS" : "ENABLE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(status == .granted ? .secondary : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(status == .granted ? Color.secondary.opacity(0.15) : Color.accentColor)
                    .cornerRadius(4)
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
    PermissionsSettingsView()
        .frame(width: 500, height: 400)
        .padding()
}
