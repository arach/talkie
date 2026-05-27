//
//  PermissionsSettingsSection.swift
//  TalkieAgent
//
//  Permission Center - shows all required permissions and their status
//

import SwiftUI
import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import TalkieKit

// MARK: - Permission Types

enum PermissionType: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .accessibility: return "hand.point.up.left.fill"
        case .screenRecording: return "rectangle.dashed.badge.record"
        }
    }

    var description: String {
        switch self {
        case .microphone:
            return "Required to record audio for transcription"
        case .accessibility:
            return "Required to automatically paste transcribed text (simulates Cmd+V)"
        case .screenRecording:
            return "Used to capture screenshots and on-screen context for memos"
        }
    }

    var shortDescription: String {
        switch self {
        case .microphone:
            return "For recording audio"
        case .accessibility:
            return "For auto-paste"
        case .screenRecording:
            return "For screenshots and context"
        }
    }

    var isRequired: Bool {
        switch self {
        case .microphone, .accessibility:
            return true
        case .screenRecording:
            return false
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return nil
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
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

// MARK: - Thread-Safe Accessibility Cache

/// Thread-safe cache for accessibility permission.
/// This is separate from PermissionManager to allow nonisolated access from any context.
final class AccessibilityCache: @unchecked Sendable {
    static let shared = AccessibilityCache()

    private let lock = NSLock()
    private var cachedResult: Bool?
    private var cacheTime: Date?

    // Cache durations based on current permission state
    private let grantedCacheDuration: TimeInterval = 24 * 3600  // 24 hours when granted
    private let missingCacheDuration: TimeInterval = 10         // 10 seconds when missing (user may grant any moment)

    private init() {}

    /// Whether accessibility is available (uses cached value if fresh, thread-safe).
    var hasPermission: Bool {
        // Check cache while holding lock
        lock.lock()
        if let cached = cachedResult, let time = cacheTime {
            let cacheDuration = cached ? grantedCacheDuration : missingCacheDuration
            if Date().timeIntervalSince(time) < cacheDuration {
                lock.unlock()
                return cached
            }
        }
        lock.unlock()

        // Cache miss or expired - check outside lock to avoid blocking other threads
        let result = AXIsProcessTrusted()

        // Update cache
        lock.lock()
        cachedResult = result
        cacheTime = Date()
        lock.unlock()

        return result
    }

    /// Pre-flight check: call this on boot to warm the cache.
    @discardableResult
    func preflight() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let result = AXIsProcessTrusted()
        cachedResult = result
        cacheTime = Date()
        return result
    }

    /// Invalidate the cache (e.g., when paste fails).
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedResult = nil
        cacheTime = nil
    }

    /// Report a failure and immediately re-check.
    func reportFailure() {
        lock.lock()
        defer { lock.unlock() }
        let result = AXIsProcessTrusted()
        cachedResult = result
        cacheTime = Date()
    }
}

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var accessibilityStatus: PermissionStatus = .notDetermined
    @Published var screenRecordingStatus: PermissionStatus = .notDetermined

    private var pollTimer: Timer?

    /// Thread-safe accessor for accessibility permission (delegates to AccessibilityCache).
    /// Can be safely called from any context.
    nonisolated var hasAccessibilityPermission: Bool {
        AccessibilityCache.shared.hasPermission
    }

    /// Pre-flight check: call this on boot to warm the accessibility cache.
    @discardableResult
    func preflightAccessibilityCheck() -> Bool {
        let result = AccessibilityCache.shared.preflight()
        accessibilityStatus = result ? .granted : .denied
        return result
    }

    /// Report an accessibility-related failure (e.g., paste didn't work).
    nonisolated func reportAccessibilityFailure() {
        AccessibilityCache.shared.reportFailure()
    }

    init() {
        refreshAll()
    }

    func refreshAll() {
        checkMicrophone()
        checkAccessibility()
        checkScreenRecording()
    }

    func checkMicrophone() {
        microphoneStatus = switch MicrophonePermission.status {
        case .granted: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        }
    }

    func checkAccessibility() {
        // Use the shared cache and update our published status
        let result = AccessibilityCache.shared.preflight()
        accessibilityStatus = result ? .granted : .denied
    }

    func checkScreenRecording() {
        screenRecordingStatus = CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Triggers the system Screen Recording prompt on first call; subsequent calls
    /// no-op (CGRequestScreenCaptureAccess only prompts once per app lifetime).
    /// After denial, the user must grant via System Settings.
    @discardableResult
    func requestScreenRecording() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        screenRecordingStatus = granted ? .granted : .denied
        return granted
    }

    @discardableResult
    func requestMicrophone() async -> Bool {
        let currentStatus = MicrophonePermission.status

        switch currentStatus {
        case .granted:
            microphoneStatus = .granted
            return true
        case .notDetermined:
            let granted = await MicrophonePermission.request()
            microphoneStatus = granted ? .granted : .denied
            return granted
        case .denied:
            microphoneStatus = .denied
            return false
        }
    }

    func requestAccessibility() {
        AccessibilityInstallAssistant.shared.present()
        startPolling()
    }

    func openSettings(for permission: PermissionType) {
        if permission == .accessibility {
            AccessibilityInstallAssistant.shared.present()
        } else if let url = permission.settingsURL {
            openSystemSettings(url)
        }

        // Start polling to detect when permission is granted
        startPolling()
    }

    /// Reliably open a System Settings URL.
    /// NSWorkspace.shared.open can silently fail from background MachService context,
    /// so we fall back to /usr/bin/open which always works.
    private func openSystemSettings(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [url.absoluteString]
            try? process.run()
        }
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
        case .screenRecording: return screenRecordingStatus
        }
    }

    var allRequiredGranted: Bool {
        PermissionType.allCases
            .filter(\.isRequired)
            .allSatisfy { status(for: $0) == .granted }
    }

    /// Dispatches the appropriate request flow for a permission and falls back
    /// to opening System Settings when the in-app prompt isn't available or was
    /// already denied. Shared by Settings → Permissions and About → Permissions.
    func handleRequest(for permission: PermissionType) {
        switch permission {
        case .microphone:
            switch microphoneStatus {
            case .notDetermined:
                Task { @MainActor in
                    let granted = await requestMicrophone()
                    if !granted {
                        openSettings(for: permission)
                    }
                }
            case .granted, .denied, .restricted:
                openSettings(for: permission)
            }
        case .accessibility:
            if accessibilityStatus == .granted {
                openSettings(for: permission)
            } else {
                requestAccessibility()
            }
        case .screenRecording:
            let granted = requestScreenRecording()
            if !granted {
                openSettings(for: permission)
            }
        }
    }

    var grantedCount: Int {
        PermissionType.allCases.count { status(for: $0) == .granted }
    }

    var totalCount: Int { PermissionType.allCases.count }
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

                    Text("Grant required permissions for TalkieAgent to function.")
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

                // Show bundle ID for dev builds
                if let bundleID = Bundle.main.bundleIdentifier,
                   bundleID.hasSuffix(".dev") {
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
        permissionManager.handleRequest(for: permission)
    }
}

// MARK: - Permission Row

struct PermissionSettingsRow: View {
    let permission: PermissionType
    let status: PermissionStatus
    let onRequest: () -> Void

    @State private var isHovered = false

    private var actionLabel: String {
        switch status {
        case .granted: return "Review"
        case .notDetermined:
            return permission == .microphone ? "Request" : "Enable"
        case .denied: return "Open Settings"
        case .restricted: return "Review"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(status == .granted ? .green : TalkieTheme.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                HStack(spacing: 6) {
                    Text(permission.shortDescription)
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textTertiary)

                    Text("•")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary.opacity(0.7))

                    Text(status.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(status.color.opacity(0.9))
                }
            }

            Spacer()

            Button(action: onRequest) {
                HStack(spacing: 6) {
                    Text(actionLabel)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(isHovered ? .white : .accentColor)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isHovered ? Color.accentColor : Color.accentColor.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(status != .granted ? Color.orange.opacity(0.04) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

#Preview {
    PermissionsSettingsSection()
        .frame(width: 500, height: 600)
        .background(TalkieTheme.background)
}
