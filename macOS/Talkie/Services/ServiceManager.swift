//
//  ServiceManager.swift
//  Talkie
//
//  Unified service state management for TalkieLive and TalkieEngine.
//  Single source of truth for all service state, lifecycle, and process info.
//
//  Usage:
//    ServiceManager.shared.live.isRunning
//    ServiceManager.shared.live.toggleRecording()
//    ServiceManager.shared.engine.isConnected
//    ServiceManager.shared.launchLive()
//

import Foundation
import AppKit
import Combine
import ServiceManagement
import os
import TalkieKit
import Observation

private let logger = Logger(subsystem: "jdi.talkie.core", category: "ServiceManager")

// MARK: - Shared Types

public struct ServiceProcessInfo: Identifiable, Equatable {
    public let id = UUID()
    public let pid: Int32
    public let name: String
    public let environment: TalkieEnvironment?
    public let isDaemon: Bool
    public let bundlePath: String?

    public var modeDescription: String {
        isDaemon ? "Daemon" : "Xcode/Direct"
    }

    public var xpcServiceName: String? {
        guard let env = environment else { return nil }
        switch name {
        case "TalkieEngine": return env.engineXPCService
        case "TalkieLive": return env.liveXPCService
        default: return nil
        }
    }

    /// Alias for backwards compatibility
    public var xpcService: String? { xpcServiceName }
}

public struct ServiceDebugInfo {
    public let serviceName: String
    public let processId: pid_t?
    public let environment: TalkieEnvironment?
    public let isXPCConnected: Bool
    public let xpcServiceName: String?
    public let bundleId: String?
}

// MARK: - Service Manager

@MainActor
@Observable
public final class ServiceManager {
    public static let shared = ServiceManager()

    // ─────────────────────────────────────────────────────────────────────────
    // Service State
    // ─────────────────────────────────────────────────────────────────────────

    public let live = LiveServiceState()
    public let engine = EngineServiceState()

    // ─────────────────────────────────────────────────────────────────────────
    // Dev: Multi-process discovery (for DevControlPanel)
    // ─────────────────────────────────────────────────────────────────────────

    public private(set) var allLiveProcesses: [ServiceProcessInfo] = []
    public private(set) var allEngineProcesses: [ServiceProcessInfo] = []

    /// Aliases for DevControlPanel compatibility
    public var liveProcesses: [ServiceProcessInfo] { allLiveProcesses }
    public var engineProcesses: [ServiceProcessInfo] { allEngineProcesses }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper Status (backwards compatibility with AppLauncher)
    // ─────────────────────────────────────────────────────────────────────────

    /// Helper status for UI display
    public enum HelperStatus: String {
        case unknown = "Unknown"
        case notFound = "Not Found"
        case notRegistered = "Not Registered"
        case enabled = "Enabled"
        case requiresApproval = "Requires Approval"
        case running = "Running"
        case notRunning = "Not Running"

        var isHealthy: Bool {
            self == .enabled || self == .running
        }

        var icon: String {
            switch self {
            case .running: return "checkmark.circle.fill"
            case .enabled: return "checkmark.circle"
            case .requiresApproval: return "exclamationmark.circle.fill"
            case .notRegistered, .notFound: return "xmark.circle"
            case .notRunning: return "pause.circle"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    /// Static bundle ID accessors
    public static var engineBundleId: String { TalkieEnvironment.current.engineBundleId }
    public static var liveBundleId: String { TalkieEnvironment.current.liveBundleId }

    /// Engine status
    public var engineStatus: HelperStatus {
        if engine.isRunning { return .running }
        return .notRunning  // Simplified
    }

    /// Live status
    public var liveStatus: HelperStatus {
        if live.isRunning { return .running }
        return .notRunning  // Simplified
    }

    /// Register Engine as login item (alias)
    public func registerEngine() {
        registerEngineLoginItem()
    }

    /// Register Live as login item (alias)
    public func registerLive() {
        registerLiveLoginItem()
    }

    /// Unregister Engine (alias)
    public func unregisterEngine() {
        unregisterEngineLoginItem()
    }

    /// Unregister Live (alias)
    public func unregisterLive() {
        unregisterLiveLoginItem()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private
    // ─────────────────────────────────────────────────────────────────────────

    private var statusTimer: Timer?

    private init() {
        logger.info("[ServiceManager] Initialized")
    }

    // MARK: - Lifecycle Actions

    /// Ensure helper apps are running (called at app launch)
    public func ensureHelpersRunning() {
        refreshStatus()

        // Launch helpers if registered but not running
        if !live.isRunning {
            launchLive()
        }
        if !engine.isRunning {
            launchEngine()
        }
    }

    /// Launch TalkieLive
    public func launchLive() {
        guard !live.isRunning else {
            logger.info("[ServiceManager] Live already running")
            return
        }

        logger.info("[ServiceManager] Launching Live...")
        launchHelper(bundleId: TalkieEnvironment.current.liveBundleId, appName: "TalkieLive.app")
    }

    /// Launch TalkieEngine
    public func launchEngine() {
        guard !engine.isRunning else {
            logger.info("[ServiceManager] Engine already running")
            return
        }

        logger.info("[ServiceManager] Launching Engine...")

        // Engine is launched via launchctl in dev, or as login item in prod
        if TalkieEnvironment.current == .dev {
            launchVialaunchctl(label: "jdi.talkie.engine")
        } else {
            launchHelper(bundleId: TalkieEnvironment.current.engineBundleId, appName: "TalkieEngine.app")
        }
    }

    /// Terminate TalkieLive
    public func terminateLive() {
        guard let pid = live.processId else { return }
        logger.info("[ServiceManager] Terminating Live (PID: \(pid))")
        terminateProcess(pid: pid)
        refreshStatus()
    }

    /// Terminate TalkieEngine
    public func terminateEngine() {
        guard let pid = engine.processId else { return }
        logger.info("[ServiceManager] Terminating Engine (PID: \(pid))")
        terminateProcess(pid: pid)
        refreshStatus()
    }

    // MARK: - Login Item Management

    /// Register TalkieLive as login item
    public func registerLiveLoginItem() {
        registerLoginItem(bundleId: TalkieEnvironment.current.liveBundleId)
        launchLive()
    }

    /// Register TalkieEngine as login item
    public func registerEngineLoginItem() {
        registerLoginItem(bundleId: TalkieEnvironment.current.engineBundleId)
        launchEngine()
    }

    /// Unregister TalkieLive from login items
    public func unregisterLiveLoginItem() {
        unregisterLoginItem(bundleId: TalkieEnvironment.current.liveBundleId)
    }

    /// Unregister TalkieEngine from login items
    public func unregisterEngineLoginItem() {
        unregisterLoginItem(bundleId: TalkieEnvironment.current.engineBundleId)
    }

    /// Open System Settings to Login Items
    public func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Status Refresh

    /// Refresh all service status
    public func refreshStatus() {
        live.refreshProcessState()
        engine.refreshProcessState()
    }

    /// Start periodic status polling
    public func startMonitoring(interval: TimeInterval = 5.0) {
        guard statusTimer == nil else { return }

        refreshStatus()
        live.startXPCMonitoring()

        statusTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }

        logger.info("[ServiceManager] Started monitoring (interval: \(interval)s)")
    }

    /// Stop periodic status polling
    public func stopMonitoring() {
        statusTimer?.invalidate()
        statusTimer = nil
        logger.info("[ServiceManager] Stopped monitoring")
    }

    // MARK: - Process Discovery (Dev)

    /// Scan for all running Talkie processes (for DevControlPanel)
    public func scanAllProcesses() {
        allLiveProcesses = findProcesses(named: "TalkieLive")
        allEngineProcesses = findProcesses(named: "TalkieEngine")
    }

    /// Kill a specific process by PID
    public func killProcess(pid: Int32) -> Bool {
        let result = Darwin.kill(pid, SIGTERM)
        Thread.sleep(forTimeInterval: 0.3)

        // Force kill if still running
        if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
        }

        refreshStatus()
        scanAllProcesses()
        return result == 0
    }

    /// Alias for scanAllProcesses
    public func scan() {
        scanAllProcesses()
    }

    /// Alias for killProcess
    public func kill(pid: Int32) -> Bool {
        killProcess(pid: pid)
    }

    /// Stop a daemon via launchctl
    public func stopDaemon(for process: ServiceProcessInfo) -> Bool {
        guard process.isDaemon, let env = process.environment else { return false }

        let label: String
        switch process.name {
        case "TalkieEngine": label = env.engineBundleId
        case "TalkieLive": label = env.liveBundleId
        default: return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["stop", "gui/\(getuid())/\(label)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.scanAllProcesses()
            }
            return task.terminationStatus == 0
        } catch {
            logger.error("[ServiceManager] Failed to stop daemon: \(error.localizedDescription)")
            return false
        }
    }

    /// Restart a daemon via launchctl kickstart -k
    public func restartDaemon(for process: ServiceProcessInfo) -> Bool {
        guard process.isDaemon, let env = process.environment else { return false }

        let label: String
        switch process.name {
        case "TalkieEngine": label = env.engineBundleId
        case "TalkieLive": label = env.liveBundleId
        default: return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.scanAllProcesses()
            }
            return task.terminationStatus == 0
        } catch {
            logger.error("[ServiceManager] Failed to restart daemon: \(error.localizedDescription)")
            return false
        }
    }

    /// Kill all daemon instances of a given service
    public func killAllDaemons(service: String) -> Int {
        let processes: [ServiceProcessInfo]
        switch service {
        case "TalkieEngine": processes = allEngineProcesses
        case "TalkieLive": processes = allLiveProcesses
        default: return 0
        }

        var killed = 0
        for process in processes where process.isDaemon {
            if stopDaemon(for: process) {
                killed += 1
            }
        }
        return killed
    }

    /// Kill all Xcode/direct launch instances of a given service
    public func killAllXcode(service: String) -> Int {
        let processes: [ServiceProcessInfo]
        switch service {
        case "TalkieEngine": processes = allEngineProcesses
        case "TalkieLive": processes = allLiveProcesses
        default: return 0
        }

        var killed = 0
        for process in processes where !process.isDaemon {
            if killProcess(pid: process.pid) {
                killed += 1
            }
        }
        return killed
    }

    // MARK: - Private Helpers

    private func launchHelper(bundleId: String, appName: String) {
        // Try to find the app
        var appURL: URL?

        // 1. Check embedded location (Contents/Library/LoginItems/)
        if let mainBundle = Bundle.main.bundleURL as URL? {
            let embeddedURL = mainBundle
                .appendingPathComponent("Contents/Library/LoginItems")
                .appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: embeddedURL.path) {
                appURL = embeddedURL
            }
        }

        // 2. Check /Applications
        if appURL == nil {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        }

        // 3. Check DerivedData (debug builds)
        #if DEBUG
        if appURL == nil {
            appURL = findDebugBuild(appName: appName)
        }
        #endif

        guard let url = appURL else {
            logger.error("[ServiceManager] App not found: \(appName)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false

        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            Task { @MainActor in
                if let error = error {
                    logger.error("[ServiceManager] Failed to launch \(appName): \(error.localizedDescription)")
                } else {
                    logger.info("[ServiceManager] Launched \(appName)")
                }
                self?.refreshStatus()
            }
        }
    }

    private func launchVialaunchctl(label: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["start", label]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            logger.info("[ServiceManager] Started via launchctl: \(label)")
        } catch {
            logger.error("[ServiceManager] launchctl failed: \(error.localizedDescription)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshStatus()
        }
    }

    private func terminateProcess(pid: Int32) {
        Darwin.kill(pid, SIGTERM)

        // Force kill after 2 seconds if still running
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if Darwin.kill(pid, 0) == 0 {
                logger.warning("[ServiceManager] Force killing PID \(pid)")
                Darwin.kill(pid, SIGKILL)
            }
            self?.refreshStatus()
        }
    }

    private func registerLoginItem(bundleId: String) {
        do {
            let service = SMAppService.loginItem(identifier: bundleId)
            try service.register()
            logger.info("[ServiceManager] Registered login item: \(bundleId)")
        } catch {
            logger.error("[ServiceManager] Failed to register login item: \(error.localizedDescription)")
        }
    }

    private func unregisterLoginItem(bundleId: String) {
        do {
            let service = SMAppService.loginItem(identifier: bundleId)
            try service.unregister()
            logger.info("[ServiceManager] Unregistered login item: \(bundleId)")
        } catch {
            logger.error("[ServiceManager] Failed to unregister login item: \(error.localizedDescription)")
        }
    }

    private func findDebugBuild(appName: String) -> URL? {
        let derivedDataPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let enumerator = FileManager.default.enumerator(
            at: derivedDataPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == appName && fileURL.path.contains("Build/Products/Debug") {
                return fileURL
            }
        }
        return nil
    }

    private func findProcesses(named processName: String) -> [ServiceProcessInfo] {
        var results: [ServiceProcessInfo] = []

        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        var pidBuffer = [Int32](repeating: 0, count: Int(count) * 2)
        let actualCount = proc_listallpids(&pidBuffer, Int32(pidBuffer.count * MemoryLayout<Int32>.size))
        guard actualCount > 0 else { return [] }

        for i in 0..<Int(actualCount) {
            let pid = pidBuffer[i]
            guard pid > 0 else { continue }

            var name = [CChar](repeating: 0, count: 1024)
            let result = proc_name(pid, &name, UInt32(name.count))

            if result > 0 {
                let procName = String(cString: name)
                if procName == processName {
                    let bundlePath = getBundlePath(for: pid)
                    let environment = detectEnvironment(from: bundlePath)
                    let isDaemon = checkIfDaemon(pid: pid)

                    results.append(ServiceProcessInfo(
                        pid: pid,
                        name: procName,
                        environment: environment,
                        isDaemon: isDaemon,
                        bundlePath: bundlePath
                    ))
                }
            }
        }

        return results.sorted { $0.pid < $1.pid }
    }

    private func getBundlePath(for pid: Int32) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &pathBuffer, UInt32(4096))
        guard result > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    private func detectEnvironment(from path: String?) -> TalkieEnvironment? {
        guard let path = path else { return nil }

        if path.contains(".dev.app") || path.contains("/Debug/") || path.contains("DerivedData") {
            return .dev
        } else if path.contains(".staging.app") {
            return .staging
        }
        return .production
    }

    private func checkIfDaemon(pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, Int32(size))
        }
        guard result == size else { return false }
        return info.pbi_ppid == 1
    }
}

// MARK: - Live Service State

@MainActor
@Observable
public final class LiveServiceState: NSObject, TalkieLiveStateObserverProtocol {

    // ─── Core State ───
    public private(set) var isRunning: Bool = false
    public private(set) var state: LiveState = .idle
    public private(set) var elapsedTime: TimeInterval = 0
    public var isRecording: Bool { state == .listening || state == .transcribing }

    // ─── Process Info ───
    public private(set) var processId: pid_t?
    public private(set) var environment: TalkieEnvironment?

    /// Backwards compatibility alias
    public var connectedMode: TalkieEnvironment? { environment }

    // ─── XPC Connection ───
    public private(set) var isXPCConnected: Bool = false
    public private(set) var audioLevel: Float = 0

    // ─── Private ───
    private var xpcManager: XPCServiceManager<TalkieLiveXPCServiceProtocol>?
    private var cancellables = Set<AnyCancellable>()

    public override init() {
        super.init()
    }

    // MARK: - Actions

    /// Toggle recording in TalkieLive
    public func toggleRecording() {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { error in
            logger.error("[Live] Toggle error: \(error.localizedDescription)")
        }) else {
            logger.warning("[Live] Cannot toggle - not connected")
            return
        }

        service.toggleRecording { success in
            if success {
                logger.info("[Live] Toggle request sent")
            }
        }
    }

    // MARK: - XPC Monitoring

    /// Start monitoring TalkieLive XPC connection (backwards compatibility)
    public func startMonitoring() {
        startXPCMonitoring()
    }

    func startXPCMonitoring() {
        guard xpcManager == nil else { return }

        xpcManager = XPCServiceManager<TalkieLiveXPCServiceProtocol>(
            serviceNameProvider: { env in env.liveXPCService },
            interfaceProvider: { NSXPCInterface(with: TalkieLiveXPCServiceProtocol.self) },
            exportedInterface: NSXPCInterface(with: TalkieLiveStateObserverProtocol.self),
            exportedObject: self
        )

        xpcManager?.$connectionInfo
            .map(\.isConnected)
            .sink { [weak self] connected in
                self?.isXPCConnected = connected
                if connected {
                    self?.environment = self?.xpcManager?.connectedMode
                    self?.registerAsObserver()
                    logger.info("[Live] XPC connected")
                }
            }
            .store(in: &cancellables)

        Task {
            await xpcManager?.connect()
        }
    }

    private func registerAsObserver() {
        guard let service = xpcManager?.remoteObjectProxy(errorHandler: { _ in }) else { return }

        service.registerStateObserver { [weak self] success, pid in
            Task { @MainActor in
                if success {
                    self?.processId = pid
                    logger.info("[Live] Registered (PID: \(pid))")
                }
            }
        }

        service.getCurrentState { [weak self] stateStr, elapsed, pid in
            Task { @MainActor in
                self?.processId = pid
                self?.updateState(stateStr, elapsed)
            }
        }
    }

    // MARK: - Process Detection

    /// Refresh process ID by detecting running TalkieLive (backwards compatibility)
    public func refreshProcessId() {
        refreshProcessState()
    }

    func refreshProcessState() {
        let bundleId = TalkieEnvironment.current.liveBundleId
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)

        if let app = apps.first {
            isRunning = true
            processId = app.processIdentifier
        } else {
            // Only mark as not running if XPC is also not connected
            if !isXPCConnected {
                isRunning = false
            }
        }
    }

    // MARK: - URL Notification Handler

    /// Update state from URL notification (preferred over XPC)
    public func updateFromNotification(state newState: LiveState, elapsedTime elapsed: TimeInterval = 0) {
        isRunning = true  // We're receiving notifications, so it's running
        self.elapsedTime = elapsed

        if newState != state {
            state = newState
            logger.info("[Live] State (notification): \(newState.rawValue)")
        }
    }

    // MARK: - TalkieLiveStateObserverProtocol

    nonisolated public func stateDidChange(state stateString: String, elapsedTime: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.updateState(stateString, elapsedTime)
        }
    }

    nonisolated public func dictationWasAdded() {
        DispatchQueue.main.async {
            DictationStore.shared.refresh()
            logger.info("[Live] Dictation added, refreshed store")
        }
    }

    nonisolated public func audioLevelDidChange(level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
        }
    }

    private func updateState(_ stateString: String, _ elapsed: TimeInterval) {
        let newState = LiveState(rawValue: stateString) ?? .idle
        self.elapsedTime = elapsed

        if newState != state {
            state = newState
            logger.info("[Live] State (XPC): \(stateString)")
        }
    }

    // MARK: - Debug Info

    public var debugInfo: ServiceDebugInfo {
        ServiceDebugInfo(
            serviceName: "TalkieLive",
            processId: processId,
            environment: environment,
            isXPCConnected: isXPCConnected,
            xpcServiceName: environment?.liveXPCService,
            bundleId: environment?.liveBundleId
        )
    }
}

/// Engine process state (backwards compatibility with TalkieServiceState)
public enum TalkieServiceState: String {
    case running = "Running"
    case stopped = "Stopped"
    case launching = "Launching..."
    case terminating = "Terminating..."
    case unknown = "Unknown"
}

// MARK: - Engine Service State

@MainActor
@Observable
public final class EngineServiceState {

    // ─── Core State ───
    public private(set) var isRunning: Bool = false
    public private(set) var isConnected: Bool = false
    public private(set) var isLaunching: Bool = false

    /// Computed state for backwards compatibility
    public var state: TalkieServiceState {
        if isLaunching { return .launching }
        if isRunning { return .running }
        return .stopped
    }

    // ─── Process Info ───
    public private(set) var processId: pid_t?
    public private(set) var environment: TalkieEnvironment?

    // ─── Resource Usage (Dev) ───
    public private(set) var cpuUsage: Double = 0
    public private(set) var memoryUsage: UInt64 = 0
    public private(set) var uptime: TimeInterval = 0
    public private(set) var launchedAt: Date?

    // ─── Engine Status ───
    public private(set) var loadedModelId: String?
    public private(set) var isTranscribing: Bool = false

    public init() {}

    // MARK: - Process Detection

    func refreshProcessState() {
        let bundleId = TalkieEnvironment.current.engineBundleId
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)

        if let app = apps.first {
            let wasRunning = isRunning
            isRunning = true
            processId = app.processIdentifier

            if !wasRunning {
                launchedAt = Date()
            }

            if let launched = launchedAt {
                uptime = Date().timeIntervalSince(launched)
            }

            // Update resource usage
            Task.detached { [weak self] in
                await self?.updateResourceUsage(pid: app.processIdentifier)
            }
        } else {
            isRunning = false
            processId = nil
            cpuUsage = 0
            memoryUsage = 0
            uptime = 0
            launchedAt = nil
        }
    }

    /// Update from EngineClient connection state
    public func updateConnectionState(connected: Bool, environment: TalkieEnvironment?) {
        isConnected = connected
        self.environment = environment
    }

    /// Update from EngineClient status
    public func updateStatus(loadedModel: String?, transcribing: Bool) {
        loadedModelId = loadedModel
        isTranscribing = transcribing
    }

    private nonisolated func updateResourceUsage(pid: pid_t) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "%cpu=,rss="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let parts = output.split(separator: " ").map { String($0) }
                if parts.count >= 2 {
                    let cpu = Double(parts[0]) ?? 0
                    let memory = (UInt64(parts[1]) ?? 0) * 1024

                    await MainActor.run {
                        self.cpuUsage = cpu
                        self.memoryUsage = memory
                    }
                }
            }
        } catch {
            // Silently fail
        }
    }

    // MARK: - Formatted Properties

    public var formattedMemory: String {
        let mb = Double(memoryUsage) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    public var formattedUptime: String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }

    // MARK: - Monitoring (backwards compatibility)

    /// Logs from engine (placeholder)
    public private(set) var logs: [TalkieServiceLogEntry] = []

    /// Last error (placeholder)
    public private(set) var lastError: String?

    /// Start monitoring (no-op for now)
    public func startMonitoring() {}

    /// Stop monitoring (no-op for now)
    public func stopMonitoring() {}

    /// Clear logs
    public func clearLogs() {
        logs = []
    }

    /// Terminate engine
    public func terminate() {
        ServiceManager.shared.terminateEngine()
    }

    /// Refresh state
    public func refreshState() {
        refreshProcessState()
    }

    /// Restart engine
    public func restart() async {
        ServiceManager.shared.terminateEngine()
        try? await Task.sleep(for: .milliseconds(500))
        ServiceManager.shared.launchEngine()
    }

    // MARK: - Actions

    /// Launch TalkieEngine (delegates to ServiceManager)
    public func launch() async {
        await MainActor.run {
            ServiceManager.shared.launchEngine()
        }
    }

    // MARK: - Debug Info

    public var debugInfo: ServiceDebugInfo {
        ServiceDebugInfo(
            serviceName: "TalkieEngine",
            processId: processId,
            environment: environment,
            isXPCConnected: isConnected,
            xpcServiceName: environment?.engineXPCService,
            bundleId: environment?.engineBundleId
        )
    }
}

// MARK: - Backwards Compatibility

/// Alias for DiscoveredProcess - use ServiceProcessInfo instead
public typealias DiscoveredProcess = ServiceProcessInfo

/// Log entry from TalkieEngine (backwards compatibility)
public struct TalkieServiceLogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String

    public enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case fault = "FAULT"

        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            case .fault: return "purple"
            }
        }
    }
}
