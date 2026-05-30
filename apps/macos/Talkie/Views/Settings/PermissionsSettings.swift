//
//  PermissionsSettings.swift
//  Talkie macOS
//
//  Shows status of system permissions and allows opening System Settings
//

import SwiftUI
import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreServices
import TalkieKit

private let logger = Log(.ui)

// MARK: - Permission Status

@MainActor
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

    var storedValue: String {
        switch self {
        case .granted: return "granted"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .unknown: return "unknown"
        }
    }

    init?(storedValue: String) {
        switch storedValue {
        case "granted": self = .granted
        case "denied": self = .denied
        case "notDetermined": self = .notDetermined
        case "restricted": self = .restricted
        case "unknown": self = .unknown
        default: return nil
        }
    }
}

enum AutomationTarget: String, CaseIterable, Identifiable {
    case reminders

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .reminders: return "com.apple.reminders"
        }
    }

    var icon: String {
        switch self {
        case .reminders: return "checklist"
        }
    }

    var permissionName: String {
        switch self {
        case .reminders: return "Reminders Automation"
        }
    }

    var permissionDescription: String {
        switch self {
        case .reminders: return "Needed when a workflow creates Apple Reminders"
        }
    }
}

// MARK: - Permissions Manager

@MainActor
@Observable
class PermissionsManager {
    static let shared = PermissionsManager()

    var microphoneStatus: PermissionStatus = .unknown
    var agentMicrophoneStatus: PermissionStatus = .unknown
    var accessibilityStatus: PermissionStatus = .unknown
    var automationStatus: PermissionStatus = .unknown
    var screenRecordingStatus: PermissionStatus = .unknown
    var isRequestingAgentMicrophonePermission = false
    var isRequestingAgentAccessibilityPermission = false
    private var accessibilityCheckTimer: Timer?
    private var accessibilityPollingDeadline: Date?
    private var agentAccessibilityCheckTimer: Timer?
    private var agentAccessibilityPollingDeadline: Date?
    private var screenRecordingCheckTimer: Timer?
    private var screenRecordingPollingDeadline: Date?
    private var automationTargetStatuses: [AutomationTarget: PermissionStatus] =
        Dictionary(uniqueKeysWithValues: AutomationTarget.allCases.map { ($0, .unknown) })

    private let automationStatusDefaultsKey = "PermissionsManager.automationTargetStatuses"

    private init() {
        // Don't check permissions eagerly - let views call refreshAllPermissions() on appear
        // This prevents triggering permission prompts just by accessing .shared
        loadStoredAutomationStatuses()
        updateAutomationSummaryStatus()
    }

    func automationStatus(for target: AutomationTarget) -> PermissionStatus {
        automationTargetStatuses[target] ?? .unknown
    }

    /// Refreshes permission state without triggering new system prompts.
    /// Startup surfaces and first-run flows should use this path so users only
    /// see prompts after explicitly opting into a gated feature.
    func refreshPassivePermissions() {
        checkMicrophonePermission()
        checkAgentMicrophonePermission()
        checkAccessibilityPermission()
        checkAutomationPermission(promptIfNeeded: false)
        checkScreenRecordingPermission(promptIfNeeded: false)
    }

    /// Alias retained for existing call sites. This intentionally defaults to
    /// passive checks so "refresh" actions and startup observers do not cause
    /// first-run prompts for Automation or Screen Recording.
    func refreshAllPermissions(promptIfNeeded: Bool = false) {
        checkMicrophonePermission()
        refreshAgentMicrophonePermission()
        checkAccessibilityPermission()
        checkAutomationPermission(promptIfNeeded: promptIfNeeded)
        checkScreenRecordingPermission(promptIfNeeded: promptIfNeeded)
    }

    // MARK: - Microphone

    func checkMicrophonePermission() {
        microphoneStatus = switch MicrophonePermission.status {
        case .granted: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        }
    }

    func requestMicrophonePermission() {
        Task { [weak self] in
            _ = await MicrophonePermission.request()
            await MainActor.run {
                self?.checkMicrophonePermission()
            }
        }
    }

    func checkAgentMicrophonePermission() {
        guard let hasPermission = ServiceManager.shared.live.hasMicrophonePermission else {
            agentMicrophoneStatus = .unknown
            return
        }

        agentMicrophoneStatus = hasPermission ? .granted : .denied
    }

    func refreshAgentMicrophonePermission() {
        checkAgentMicrophonePermission()

        guard ServiceManager.shared.live.isXPCConnected else { return }

        Task { [weak self] in
            guard let permissions = await ServiceManager.shared.live.refreshPermissionsNow() else { return }

            await MainActor.run {
                self?.agentMicrophoneStatus = permissions.microphone ? .granted : .denied
            }
        }
    }

    func requestAgentMicrophonePermission() {
        guard !isRequestingAgentMicrophonePermission else { return }

        isRequestingAgentMicrophonePermission = true
        agentMicrophoneStatus = .unknown

        let env = ServiceManager.shared.effectiveHelperEnvironment
        logger.info(
            "Requesting Agent microphone permission",
            detail: "env=\(env.displayName), bundle=\(TalkieHelper.agent.bundleId(for: env))"
        )

        Task { [weak self] in
            let granted = await ServiceManager.shared.requestAgentMicrophonePermission()

            await MainActor.run {
                self?.isRequestingAgentMicrophonePermission = false

                if let granted {
                    self?.agentMicrophoneStatus = granted ? .granted : .denied
                    if !granted {
                        self?.openMicrophoneSettings()
                    }
                } else {
                    self?.checkAgentMicrophonePermission()
                    self?.openMicrophoneSettings()
                }
            }
        }
    }

    // MARK: - Accessibility

    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }

    func requestAccessibilityPermission() {
        openAccessibilityInstallAssistant(for: .talkie)
        startAccessibilityPermissionPolling()
    }

    func requestAgentAccessibilityPermission() {
        guard !isRequestingAgentAccessibilityPermission else { return }

        isRequestingAgentAccessibilityPermission = true

        let env = ServiceManager.shared.effectiveHelperEnvironment
        logger.info(
            "Requesting Agent accessibility permission",
            detail: "env=\(env.displayName), bundle=\(TalkieHelper.agent.bundleId(for: env))"
        )

        Task { [weak self] in
            let result = await ServiceManager.shared.requestAgentAccessibilityPermission()

            await MainActor.run {
                self?.isRequestingAgentAccessibilityPermission = false

                switch result {
                case .granted:
                    self?.stopAgentAccessibilityPermissionPolling()
                case .waitingForUserAction:
                    self?.openAccessibilityInstallAssistant(for: .agent)
                    self?.startAgentAccessibilityPermissionPolling()
                case .agentUnavailable:
                    self?.openAccessibilityInstallAssistant(for: .agent)
                    self?.stopAgentAccessibilityPermissionPolling()
                }
            }
        }
    }

    // MARK: - Automation (AppleScript)

    func checkAutomationPermission(promptIfNeeded: Bool = false) {
        guard promptIfNeeded else {
            updateAutomationSummaryStatus()
            refreshRunningAutomationPermissions()
            return
        }

        if let pendingTarget = AutomationTarget.allCases.first(where: {
            automationStatus(for: $0) != .granted
        }) {
            requestAutomationPermission(for: pendingTarget)
        } else {
            openAutomationSettings()
        }
    }

    func requestAutomationPermission(for target: AutomationTarget) {
        Task { [weak self] in
            guard let self else { return }
            let isRunning = await self.ensureAutomationTargetRunning(target)
            guard isRunning else { return }

            let status = await Self.determineAutomationPermissionStatus(
                for: target,
                askUserIfNeeded: true
            )

            await MainActor.run {
                self.applyAutomationStatus(status, for: target)
            }
        }
    }

    // MARK: - Screen Recording

    func checkScreenRecordingPermission(promptIfNeeded: Bool = false) {
        guard promptIfNeeded else {
            screenRecordingStatus = CGPreflightScreenCaptureAccess() ? .granted : .unknown
            return
        }

        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                screenRecordingStatus = .granted
            } catch {
                screenRecordingStatus = .denied
            }
        }
    }

    func requestScreenRecordingPermission() {
        logger.info(
            "Requesting Screen Recording permission",
            detail: "bundle=\(TalkieEnvironment.current.talkieBundleId)"
        )

        AccessibilityInstallAssistant.shared.present(target: .talkie, permission: .screenRecording)
        startScreenRecordingPermissionPolling()
    }

    // MARK: - Open System Settings

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettingsPane() {
        openAccessibilityInstallAssistant(for: .talkie)
    }

    func openAccessibilitySettings() {
        openAccessibilityInstallAssistant(for: .talkie)
        startAccessibilityPermissionPolling()
    }

    func openAccessibilityInstallAssistant(for target: AccessibilityInstallTarget) {
        AccessibilityInstallAssistant.shared.present(target: target)
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

    private func refreshRunningAutomationPermissions() {
        for target in AutomationTarget.allCases where isAutomationTargetRunning(target) {
            Task { [weak self] in
                let status = await Self.determineAutomationPermissionStatus(
                    for: target,
                    askUserIfNeeded: false
                )

                guard status != .unknown else { return }

                await MainActor.run {
                    self?.applyAutomationStatus(status, for: target)
                }
            }
        }
    }

    private func isAutomationTargetRunning(_ target: AutomationTarget) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty
    }

    private func ensureAutomationTargetRunning(_ target: AutomationTarget) async -> Bool {
        if isAutomationTargetRunning(target) {
            return true
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
            logger.error("Could not locate automation target app: \(target.bundleIdentifier)")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        do {
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            try? await Task.sleep(for: .milliseconds(350))
            return true
        } catch {
            logger.error("Failed to launch automation target \(target.bundleIdentifier): \(error.localizedDescription)")
            return false
        }
    }

    @concurrent
    private static func determineAutomationPermissionStatus(
        for target: AutomationTarget,
        askUserIfNeeded: Bool
    ) async -> PermissionStatus {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty else {
            return .unknown
        }

        let osStatus = target.bundleIdentifier.utf8CString.withUnsafeBufferPointer { buffer -> OSStatus in
            var address = AEAddressDesc()
            defer { AEDisposeDesc(&address) }

            let createStatus = AECreateDesc(
                DescType(typeApplicationBundleID),
                buffer.baseAddress,
                buffer.count - 1,
                &address
            )
            guard createStatus == noErr else {
                return OSStatus(createStatus)
            }

            return AEDeterminePermissionToAutomateTarget(
                &address,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                askUserIfNeeded
            )
        }

        switch osStatus {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(procNotFound):
            return .unknown
        default:
            return .unknown
        }
    }

    private func applyAutomationStatus(_ status: PermissionStatus, for target: AutomationTarget) {
        automationTargetStatuses[target] = status
        persistAutomationStatuses()
        updateAutomationSummaryStatus()
    }

    private func updateAutomationSummaryStatus() {
        let statuses = AutomationTarget.allCases.map { automationStatus(for: $0) }

        if statuses.allSatisfy({ $0 == .granted }) {
            automationStatus = .granted
        } else if statuses.contains(.denied) {
            automationStatus = .denied
        } else if statuses.contains(.notDetermined) {
            automationStatus = .notDetermined
        } else if statuses.allSatisfy({ $0 == .unknown }) {
            automationStatus = .unknown
        } else {
            automationStatus = .unknown
        }
    }

    private func loadStoredAutomationStatuses() {
        guard let storedStatuses = UserDefaults.standard.dictionary(forKey: automationStatusDefaultsKey) as? [String: String] else {
            return
        }

        for target in AutomationTarget.allCases {
            guard let storedValue = storedStatuses[target.rawValue],
                  let status = PermissionStatus(storedValue: storedValue) else {
                continue
            }
            automationTargetStatuses[target] = status
        }
    }

    private func persistAutomationStatuses() {
        let values = automationTargetStatuses.reduce(into: [String: String]()) { result, entry in
            result[entry.key.rawValue] = entry.value.storedValue
        }
        UserDefaults.standard.set(values, forKey: automationStatusDefaultsKey)
    }

    private func startAccessibilityPermissionPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityPollingDeadline = Date().addingTimeInterval(90)
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollAccessibilityPermission()
            }
        }

        if let accessibilityCheckTimer {
            RunLoop.main.add(accessibilityCheckTimer, forMode: .common)
        }
    }

    private func pollAccessibilityPermission() {
        checkAccessibilityPermission()

        if accessibilityStatus == .granted || Date() >= (accessibilityPollingDeadline ?? .distantPast) {
            stopAccessibilityPermissionPolling()
        }
    }

    private func stopAccessibilityPermissionPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
        accessibilityPollingDeadline = nil
    }

    private func startAgentAccessibilityPermissionPolling() {
        agentAccessibilityCheckTimer?.invalidate()
        agentAccessibilityPollingDeadline = Date().addingTimeInterval(90)
        agentAccessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollAgentAccessibilityPermission()
            }
        }

        if let agentAccessibilityCheckTimer {
            RunLoop.main.add(agentAccessibilityCheckTimer, forMode: .common)
        }
    }

    private func pollAgentAccessibilityPermission() async {
        let permissions = await ServiceManager.shared.live.refreshPermissionsNow()

        if permissions?.accessibility == true || Date() >= (agentAccessibilityPollingDeadline ?? .distantPast) {
            stopAgentAccessibilityPermissionPolling()
        }
    }

    private func stopAgentAccessibilityPermissionPolling() {
        agentAccessibilityCheckTimer?.invalidate()
        agentAccessibilityCheckTimer = nil
        agentAccessibilityPollingDeadline = nil
    }

    private func startScreenRecordingPermissionPolling() {
        screenRecordingCheckTimer?.invalidate()
        screenRecordingPollingDeadline = Date().addingTimeInterval(90)
        screenRecordingCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollScreenRecordingPermission()
            }
        }

        if let screenRecordingCheckTimer {
            RunLoop.main.add(screenRecordingCheckTimer, forMode: .common)
        }
    }

    private func pollScreenRecordingPermission() {
        checkScreenRecordingPermission()

        if screenRecordingStatus == .granted || Date() >= (screenRecordingPollingDeadline ?? .distantPast) {
            stopScreenRecordingPermissionPolling()
        }
    }

    private func stopScreenRecordingPermissionPolling() {
        screenRecordingCheckTimer?.invalidate()
        screenRecordingCheckTimer = nil
        screenRecordingPollingDeadline = nil
    }
}

// MARK: - Permissions Settings View

struct PermissionsSettingsView: View {
    private let permissionsManager = PermissionsManager.shared

    private var grantedCount: Int {
        return [
            permissionsManager.microphoneStatus == .granted,
            permissionsManager.accessibilityStatus == .granted
        ].filter { $0 }.count
    }

    private var totalPermissionCount: Int {
        2
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
                        .fill(grantedCount == totalPermissionCount ? SemanticColor.success : SemanticColor.warning)
                        .frame(width: 3, height: 14)

                    Text("APP PERMISSIONS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(grantedCount == totalPermissionCount ? SemanticColor.success : SemanticColor.warning)
                            .frame(width: 6, height: 6)
                        Text("\(grantedCount)/\(totalPermissionCount) REQUIRED")
                            .font(.techLabelSmall)
                            .foregroundColor(grantedCount == totalPermissionCount ? SemanticColor.success : SemanticColor.warning)
                    }
                    .help("Required permissions granted. Screen Recording is optional.")
                }

                VStack(spacing: Spacing.sm) {
                    // Microphone
                    SettingsPermissionRow(
                        icon: "mic.fill",
                        name: "Microphone",
                        description: "Required for voice memos recorded in Talkie",
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
                    SettingsPermissionRow(
                        icon: "accessibility",
                        name: "Accessibility",
                        description: "Required for auto-paste after dictation",
                        status: permissionsManager.accessibilityStatus,
                        onRequest: {
                            permissionsManager.requestAccessibilityPermission()
                        }
                    )

                    // Screen Recording
                    SettingsPermissionRow(
                        icon: "rectangle.dashed.badge.record",
                        name: "Screen Recording",
                        description: "Optional — enables screen context capture",
                        status: permissionsManager.screenRecordingStatus,
                        onRequest: {
                            if permissionsManager.screenRecordingStatus == .granted {
                                permissionsManager.openScreenRecordingSettings()
                            } else {
                                permissionsManager.requestScreenRecordingPermission()
                            }
                        }
                    )

                    // Footer with actions
                    HStack {
                        Spacer()

                        Button(action: {
                            permissionsManager.refreshAllPermissions()
                        }) {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9))
                                Text("Refresh")
                                    .font(Theme.current.fontXS)
                            }
                            .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .buttonStyle(.plain)

                        Text("·")
                            .foregroundColor(Theme.current.foregroundMuted)

                        Button(action: {
                            permissionsManager.openPrivacySettings()
                        }) {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 9))
                                Text("Open System Settings")
                                    .font(Theme.current.fontXS)
                            }
                            .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, Spacing.xs)
                }
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Info Note
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(Theme.current.fontSM)
                        .foregroundColor(SemanticColor.pin)

                    Text("Permissions are managed in System Settings → Privacy & Security. Agent dictation uses Talkie Agent, which has its own permissions.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("LOOK FOR IN SYSTEM SETTINGS:")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Theme.current.foregroundMuted)

                    HStack(spacing: Spacing.md) {
                        HStack(spacing: Spacing.xxs) {
                            Text("Talkie:")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(TalkieEnvironment.current.talkieBundleId)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: Spacing.xxs) {
                            Text("Agent:")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(ServiceManager.shared.effectiveHelperEnvironment.bundleId(for: .agent))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .textSelection(.enabled)
                        }
                    }

                    if let path = ServiceManager.shared.live.bundlePath {
                        Text(path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.xs)
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

struct SettingsPermissionRow: View {
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
