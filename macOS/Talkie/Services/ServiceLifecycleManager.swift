//
//  ServiceLifecycleManager.swift
//  Talkie
//
//  Unified service lifecycle management for all Talkie services
//  Handles launch, restart, terminate, and process monitoring for:
//  - XPC services (TalkieEngine)
//  - Standalone apps (TalkieLive)
//
//  Consolidates logic from TalkieServiceMonitor, AppEnvironment, and process detection
//

import Foundation
import AppKit
import os
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "ServiceLifecycle")

/// Service state
public enum ServiceState: String, Equatable {
    case running = "Running"
    case stopped = "Stopped"
    case launching = "Launching..."
    case terminating = "Terminating..."
    case unknown = "Unknown"
}

/// Service type determines how it's launched and monitored
public enum ServiceType {
    case xpcService(launchctlName: String)  // Launched via launchctl
    case standaloneApp(bundleId: String, appName: String)  // Launched via NSWorkspace
}

/// Unified service lifecycle manager
@MainActor
@Observable
public class ServiceLifecycleManager {
    // MARK: - Published State

    public private(set) var state: ServiceState = .unknown
    public private(set) var processId: pid_t?
    public private(set) var launchedAt: Date?
    public private(set) var lastError: String?

    // MARK: - Configuration

    public let serviceType: ServiceType
    public let environment: TalkieEnvironment
    private let serviceName: String  // For logging

    // MARK: - Private

    private var monitorTimer: Timer?

    // MARK: - Initialization

    public init(serviceType: ServiceType, environment: TalkieEnvironment, serviceName: String) {
        self.serviceType = serviceType
        self.environment = environment
        self.serviceName = serviceName

        logger.info("[\(self.serviceName)] Lifecycle manager initialized")

        // Check initial state
        refreshState()
    }

    // MARK: - Monitoring

    /// Start monitoring service state
    public func startMonitoring(interval: TimeInterval = 2.0) {
        guard monitorTimer == nil else { return }

        logger.info("[\(self.serviceName)] Starting monitoring (interval: \(interval)s)")

        monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }

        // Immediate refresh
        refreshState()
    }

    /// Stop monitoring service state
    public func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        logger.info("[\(self.serviceName)] Stopped monitoring")
    }

    /// Refresh current state
    public func refreshState() {
        let wasRunning = state == .running
        let (isRunning, pid) = checkRunningState()

        processId = pid

        // Don't overwrite transitional states (launching, terminating)
        if state != .launching && state != .terminating {
            state = isRunning ? .running : .stopped
        }

        // Update launch time when service starts
        if !wasRunning && isRunning {
            launchedAt = Date()
            logger.info("[\(self.serviceName)] Service started (PID: \(pid ?? 0))")
        } else if wasRunning && !isRunning {
            launchedAt = nil
            logger.info("[\(self.serviceName)] Service stopped")
        }
    }

    /// Check if service is running and get PID
    private func checkRunningState() -> (isRunning: Bool, pid: pid_t?) {
        switch serviceType {
        case .xpcService:
            return checkXPCServiceState()
        case .standaloneApp(let bundleId, _):
            return checkStandaloneAppState(bundleId: bundleId)
        }
    }

    /// Check XPC service state using pgrep
    private func checkXPCServiceState() -> (isRunning: Bool, pid: pid_t?) {
        // Get process name from launchctl name
        guard case .xpcService(let launchctlName) = serviceType else {
            return (false, nil)
        }

        // Extract process name (e.g., "jdi.talkie.engine" -> "TalkieEngine")
        let processName = launchctlName.components(separatedBy: ".").last?.capitalized ?? launchctlName

        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", processName]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let pid = pid_t(output) {
                    return (true, pid)
                }
                return (true, nil)
            }

            return (false, nil)
        } catch {
            return (false, nil)
        }
    }

    /// Check standalone app state using NSWorkspace
    private func checkStandaloneAppState(bundleId: String) -> (isRunning: Bool, pid: pid_t?) {
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
            return (true, app.processIdentifier)
        }
        return (false, nil)
    }

    // MARK: - Lifecycle Control

    /// Launch the service
    public func launch() async -> Bool {
        guard state != .running && state != .launching else {
            logger.warning("[\(self.serviceName)] Already running or launching")
            return false
        }

        state = .launching
        lastError = nil

        logger.info("[\(self.serviceName)] Launching...")

        let success: Bool

        switch serviceType {
        case .xpcService(let launchctlName):
            success = await launchXPCService(launchctlName: launchctlName)
        case .standaloneApp(let bundleId, let appName):
            success = await launchStandaloneApp(bundleId: bundleId, appName: appName)
        }

        // Wait a bit and refresh state
        try? await Task.sleep(for: .milliseconds(500))
        refreshState()

        if success {
            logger.info("[\(self.serviceName)] ✓ Launched successfully")
        } else {
            state = .stopped
            logger.error("[\(self.serviceName)] ❌ Launch failed")
        }

        return success
    }

    /// Launch XPC service via launchctl
    private func launchXPCService(launchctlName: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["start", launchctlName]

            let errorPipe = Pipe()
            task.standardError = errorPipe
            task.standardOutput = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()

                if task.terminationStatus == 0 {
                    continuation.resume(returning: true)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    self.lastError = errorMessage
                    logger.error("[\(self.serviceName)] launchctl error: \(errorMessage)")
                    continuation.resume(returning: false)
                }
            } catch {
                self.lastError = error.localizedDescription
                logger.error("[\(self.serviceName)] Launch failed: \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
        }
    }

    /// Launch standalone app via NSWorkspace
    private func launchStandaloneApp(bundleId: String, appName: String) async -> Bool {
        // Find the app (prefers debug build in debug mode, /Applications otherwise)
        guard let appURL = findStandaloneApp(appName: appName) else {
            lastError = "\(appName) not found"
            logger.error("[\(self.serviceName)] App not found: \(appName)")
            return false
        }

        do {
            let configuration = NSWorkspace.OpenConfiguration()
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            logger.info("[\(self.serviceName)] Launched from \(appURL.path)")
            return true
        } catch {
            lastError = error.localizedDescription
            logger.error("[\(self.serviceName)] Failed to launch: \(error.localizedDescription)")
            return false
        }
    }

    /// Find standalone app (prefers debug build in debug mode)
    private func findStandaloneApp(appName: String) -> URL? {
        #if DEBUG
        // In debug mode, prefer DerivedData build
        if let debugBuild = findDebugBuild(appName: appName) {
            logger.info("[\(self.serviceName)] Using debug build: \(debugBuild.path)")
            return debugBuild
        }
        #endif

        // Fall back to /Applications
        let installedPath = URL(fileURLWithPath: "/Applications/\(appName)")
        if FileManager.default.fileExists(atPath: installedPath.path) {
            logger.info("[\(self.serviceName)] Using installed app: \(installedPath.path)")
            return installedPath
        }

        logger.warning("[\(self.serviceName)] App not found: \(appName)")
        return nil
    }

    /// Find debug build in DerivedData
    private func findDebugBuild(appName: String) -> URL? {
        let derivedDataPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let enumerator = FileManager.default.enumerator(
            at: derivedDataPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == appName &&
               fileURL.path.contains("Build/Products/Debug") {
                return fileURL
            }
        }

        return nil
    }

    /// Terminate the service
    public func terminate() async {
        guard state == .running || state == .launching, let pid = processId else {
            logger.warning("[\(self.serviceName)] Not running")
            return
        }

        state = .terminating
        logger.info("[\(self.serviceName)] Terminating PID \(pid)")

        // Send SIGTERM
        kill(pid, SIGTERM)

        // Wait for graceful shutdown
        try? await Task.sleep(for: .seconds(2))
        refreshState()

        // Force kill if still running
        if state == .running, let stillPid = processId {
            logger.warning("[\(self.serviceName)] Force killing PID \(stillPid)")
            kill(stillPid, SIGKILL)
            try? await Task.sleep(for: .milliseconds(500))
            refreshState()
        }
    }

    /// Restart the service
    public func restart() async {
        logger.info("[\(self.serviceName)] Restarting...")

        await terminate()

        // Wait a bit before relaunching
        try? await Task.sleep(for: .seconds(1))

        _ = await launch()
    }
}

// MARK: - Convenience Factory Methods

extension ServiceLifecycleManager {
    /// Create lifecycle manager for TalkieEngine
    public static func forEngine(environment: TalkieEnvironment = .current) -> ServiceLifecycleManager {
        ServiceLifecycleManager(
            serviceType: .xpcService(launchctlName: "jdi.talkie.engine"),
            environment: environment,
            serviceName: "Engine"
        )
    }

    /// Create lifecycle manager for TalkieLive
    public static func forLive(environment: TalkieEnvironment = .current) -> ServiceLifecycleManager {
        ServiceLifecycleManager(
            serviceType: .standaloneApp(
                bundleId: environment.liveBundleId,
                appName: "TalkieLive.app"
            ),
            environment: environment,
            serviceName: "Live"
        )
    }
}
