//
//  PowerStateManager.swift
//  Talkie macOS
//
//  Monitors macOS power lifecycle to help iOS users understand
//  when their Mac is available for async memo processing.
//
//  States tracked:
//  - active: User present, fully awake
//  - idle: User away, system awake
//  - screenOff: Display off, system may be running
//  - sleeping: Deep sleep
//  - shuttingDown: Shutting down
//

import Foundation
import AppKit
import CoreGraphics
import IOKit.ps
import TalkieKit

private let log = Log(.system)

@MainActor
@Observable
final class PowerStateManager {
    static let shared = PowerStateManager()

    // MARK: - Power State

    enum PowerState: String, Codable, CaseIterable, Sendable {
        case active        // User present, fully awake
        case idle          // User away, system awake
        case screenOff     // Display off, system may be running
        case sleeping      // Deep sleep
        case shuttingDown  // Shutting down
    }

    private(set) var state: PowerState = .active
    private(set) var lastStateChange: Date = .now
    private(set) var idleTime: TimeInterval = 0

    // MARK: - Capability Assessment

    struct Capabilities: Codable, Sendable {
        let canProcessMemos: Bool
        let canRunWorkflows: Bool
        let estimatedAvailability: String  // "now", "periodic", "when user returns"
    }

    var currentCapabilities: Capabilities {
        switch state {
        case .active, .idle:
            return Capabilities(
                canProcessMemos: true,
                canRunWorkflows: true,
                estimatedAvailability: "now"
            )
        case .screenOff:
            // Depends on "Prevent sleep when display off" setting
            let preventsSleep = checkPreventSleepSetting()
            return Capabilities(
                canProcessMemos: preventsSleep,
                canRunWorkflows: preventsSleep,
                estimatedAvailability: preventsSleep ? "now" : "when display wakes"
            )
        case .sleeping, .shuttingDown:
            return Capabilities(
                canProcessMemos: false,
                canRunWorkflows: false,
                estimatedAvailability: "when user returns"
            )
        }
    }

    // MARK: - Timers

    @ObservationIgnored private var idleTimer: Timer?
    @ObservationIgnored private var heartbeatTimer: Timer?

    // Idle threshold: 5 minutes
    private let idleThreshold: TimeInterval = 300

    // Heartbeat interval: 5 minutes
    private let heartbeatInterval: TimeInterval = 300

    // MARK: - Notification Observers

    @ObservationIgnored private var notificationObservers: [Any] = []

    // MARK: - Init

    private init() {
        // Don't setup here - wait for explicit setup() call from StartupCoordinator
    }

    // MARK: - Setup

    func setup() {
        subscribeToWorkspaceNotifications()
        startIdleTimeMonitoring()
        startHeartbeat()
        updateState(.active)
        log.info("PowerStateManager initialized")
    }

    // MARK: - Workspace Notifications

    private func subscribeToWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        // Screen events
        notificationObservers.append(
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleScreenDidSleep()
                }
            }
        )

        notificationObservers.append(
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleScreenDidWake()
                }
            }
        )

        // System sleep/wake
        notificationObservers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWillSleep()
                }
            }
        )

        notificationObservers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDidWake()
                }
            }
        )

        // Shutdown
        notificationObservers.append(
            center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWillPowerOff()
                }
            }
        )

        log.debug("Subscribed to workspace power notifications")
    }

    private func handleScreenDidSleep() {
        log.info("Screen did sleep")
        updateState(.screenOff)
    }

    private func handleScreenDidWake() {
        log.info("Screen did wake")
        updateState(.active)
    }

    private func handleWillSleep() {
        log.info("System will sleep")
        updateState(.sleeping)
        // Sync immediately - last chance before sleep
        syncToCloudKit()
    }

    private func handleDidWake() {
        log.info("System did wake")
        updateState(.active)
        syncToCloudKit()
    }

    private func handleWillPowerOff() {
        log.info("System will power off")
        updateState(.shuttingDown)
        syncToCloudKit()
    }

    // MARK: - Idle Time Monitoring

    private func startIdleTimeMonitoring() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleTime()
            }
        }
    }

    private func checkIdleTime() {
        // Get seconds since last user input (keyboard or mouse)
        let keyIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .keyDown
        )
        let mouseIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .mouseMoved
        )

        // Use the minimum - user is active if either input happened
        idleTime = min(keyIdle, mouseIdle)

        // Only transition between active/idle - other states come from notifications
        if state == .active && idleTime > idleThreshold {
            log.info("User idle for \(Int(idleTime))s, transitioning to idle")
            updateState(.idle)
        } else if state == .idle && idleTime < 60 {
            log.info("User activity detected, transitioning to active")
            updateState(.active)
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncToCloudKit()
            }
        }
    }

    // MARK: - State Updates

    private func updateState(_ newState: PowerState) {
        guard state != newState else { return }

        let oldState = state
        state = newState
        lastStateChange = .now

        log.info("Power state: \(oldState.rawValue) → \(newState.rawValue)")

        // Post notification for other parts of the app
        NotificationCenter.default.post(
            name: .powerStateDidChange,
            object: nil,
            userInfo: ["state": newState.rawValue, "oldState": oldState.rawValue]
        )

        // Sync to CloudKit for iOS awareness
        syncToCloudKit()
    }

    // MARK: - CloudKit Sync

    private func syncToCloudKit() {
        Task {
            await CoreDataSyncGateway.shared.updateMacStatus(
                powerState: state,
                capabilities: currentCapabilities,
                idleTime: idleTime
            )
        }
    }

    // MARK: - Helpers

    private func checkPreventSleepSetting() -> Bool {
        // Check if system is configured to prevent sleep when display is off
        // This is a simplification - for full accuracy would need IOKit/pmset
        //
        // For now, assume it's enabled on desktop Macs (no battery)
        // and disabled on laptops (has battery)
        return !hasBattery()
    }

    private func hasBattery() -> Bool {
        // Check if this Mac has a battery (laptop vs desktop)
        // Desktop Macs typically stay awake when display is off
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            // No power sources = desktop Mac
            return false
        }
        return true
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let powerStateDidChange = Notification.Name("powerStateDidChange")
}
