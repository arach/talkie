//
//  ProcessDiscovery.swift
//  Talkie
//
//  Discovers all running Talkie service instances (Engine + Live)
//  Used by Dev Control Panel to show all processes and manage them
//

import Foundation
import Darwin
import TalkieKit
import Observation

/// Information about a discovered process
public struct DiscoveredProcess: Identifiable, Equatable {
    public let id = UUID()
    public let pid: Int32
    public let name: String
    public let bundlePath: String?
    public let environment: TalkieEnvironment?
    public let isDaemon: Bool
    public let startTime: Date?

    public var displayName: String {
        switch name {
        case "TalkieEngine": return "TalkieEngine"
        case "TalkieLive": return "TalkieLive"
        default: return name
        }
    }

    public var modeDescription: String {
        isDaemon ? "Daemon" : "Xcode/Direct"
    }

    public var xpcService: String? {
        guard let env = environment else { return nil }
        switch name {
        case "TalkieEngine": return env.engineXPCService
        case "TalkieLive": return env.liveXPCService
        default: return nil
        }
    }
}

/// Service to discover all running Talkie processes
@MainActor
@Observable
public class ProcessDiscovery {
    public static let shared = ProcessDiscovery()

    public private(set) var engineProcesses: [DiscoveredProcess] = []
    public private(set) var liveProcesses: [DiscoveredProcess] = []

    private init() {}

    /// Scan for all TalkieEngine and TalkieLive processes
    public func scan() {
        engineProcesses = findProcesses(named: "TalkieEngine")
        liveProcesses = findProcesses(named: "TalkieLive")
    }

    /// Find all processes with a given name
    private func findProcesses(named processName: String) -> [DiscoveredProcess] {
        var results: [DiscoveredProcess] = []

        // Get number of processes
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        // Allocate buffer and get PIDs
        var pidBuffer = [Int32](repeating: 0, count: Int(count) * 2)
        let actualCount = proc_listallpids(&pidBuffer, Int32(pidBuffer.count * MemoryLayout<Int32>.size))

        guard actualCount > 0 else { return [] }

        // Check each process
        for i in 0..<Int(actualCount) {
            let pid = pidBuffer[i]
            guard pid > 0 else { continue }

            // Get process name
            var name = [CChar](repeating: 0, count: 1024)
            let result = proc_name(pid, &name, UInt32(name.count))

            if result > 0 {
                let procName = String(cString: name)
                if procName == processName {
                    // Get additional info
                    let bundlePath = getBundlePath(for: pid)
                    let environment = detectEnvironment(from: bundlePath)
                    let isDaemon = checkIfDaemon(pid: pid)
                    let startTime = getProcessStartTime(pid: pid)

                    results.append(DiscoveredProcess(
                        pid: pid,
                        name: procName,
                        bundlePath: bundlePath,
                        environment: environment,
                        isDaemon: isDaemon,
                        startTime: startTime
                    ))
                }
            }
        }

        return results.sorted { $0.pid < $1.pid }
    }

    /// Get the bundle path for a process
    private func getBundlePath(for pid: Int32) -> String? {
        let maxSize = 4096  // Maximum path size
        var pathBuffer = [CChar](repeating: 0, count: maxSize)
        let result = proc_pidpath(pid, &pathBuffer, UInt32(maxSize))

        guard result > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    /// Detect environment from bundle path
    private func detectEnvironment(from path: String?) -> TalkieEnvironment? {
        guard let path = path else { return nil }

        // Check bundle ID from path
        if path.contains(".dev.app") || path.contains("/Debug/") {
            return .dev
        } else if path.contains(".staging.app") {
            return .staging
        } else if path.contains("/Release/") || path.contains("/Applications/") {
            return .production
        }

        // Fallback: assume dev if running from DerivedData
        if path.contains("DerivedData") {
            return .dev
        }

        return .production
    }

    /// Check if process is launched by launchd (daemon mode)
    private func checkIfDaemon(pid: Int32) -> Bool {
        // Get parent PID
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, Int32(size))
        }

        guard result == size else { return false }

        // If parent is launchd (PID 1), it's likely a daemon
        return info.pbi_ppid == 1
    }

    /// Get process start time
    private func getProcessStartTime(pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, Int32(size))
        }

        guard result == size else { return nil }

        // Convert timeval to Date
        let startTime = info.pbi_start_tvsec
        return Date(timeIntervalSince1970: TimeInterval(startTime))
    }

    /// Kill a specific process
    public func kill(pid: Int32) -> Bool {
        let result = Darwin.kill(pid, SIGTERM)

        // Wait a moment for graceful shutdown
        Thread.sleep(forTimeInterval: 0.5)

        // Check if still running
        if Darwin.kill(pid, 0) == 0 {
            // Still running, force kill
            Darwin.kill(pid, SIGKILL)
        }

        // Rescan
        scan()

        return result == 0
    }

    /// Kill all daemon instances of a service
    public func killAllDaemons(service: String) -> Int {
        let processes = service == "TalkieEngine" ? engineProcesses : liveProcesses
        let daemons = processes.filter { $0.isDaemon }

        var killed = 0
        for daemon in daemons {
            if kill(pid: daemon.pid) {
                killed += 1
            }
        }

        return killed
    }

    /// Kill all non-daemon instances of a service
    public func killAllXcode(service: String) -> Int {
        let processes = service == "TalkieEngine" ? engineProcesses : liveProcesses
        let xcode = processes.filter { !$0.isDaemon }

        var killed = 0
        for proc in xcode {
            if kill(pid: proc.pid) {
                killed += 1
            }
        }

        return killed
    }

    /// Start/restart a daemon process using launchctl
    public func startDaemon(for process: DiscoveredProcess) -> Bool {
        guard process.isDaemon, let env = process.environment else { return false }

        // Get the launchd label for this service
        let label: String
        switch process.name {
        case "TalkieEngine":
            label = env.engineLaunchdLabel
        case "TalkieLive":
            label = env.liveLaunchdLabel
        default:
            return false
        }

        // Use launchctl to start the service
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["start", label]

        do {
            try task.run()
            task.waitUntilExit()

            // Wait a moment for the service to start
            Thread.sleep(forTimeInterval: 0.5)

            // Rescan to update state
            Task { @MainActor in
                scan()
            }

            return task.terminationStatus == 0
        } catch {
            NSLog("[ProcessDiscovery] Failed to start daemon \(label): \(error)")
            return false
        }
    }

    /// Stop a daemon process using launchctl bootout (properly unloads and prevents restart)
    public func stopDaemon(for process: DiscoveredProcess) -> Bool {
        guard process.isDaemon, let env = process.environment else { return false }

        // Get the launchd label for this service
        let label: String
        switch process.name {
        case "TalkieEngine":
            label = env.engineLaunchdLabel
        case "TalkieLive":
            label = env.liveLaunchdLabel
        default:
            return false
        }

        // Use launchctl bootout to properly unload the service
        // This prevents launchd from restarting it (unlike 'stop' which is temporary)
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(uid)/\(label)"]

        do {
            try task.run()
            task.waitUntilExit()

            // If bootout fails, fall back to kill
            if task.terminationStatus != 0 {
                NSLog("[ProcessDiscovery] bootout failed for \(label), falling back to kill")
                _ = kill(pid: process.pid)
            }

            // Wait a moment for the service to stop
            Thread.sleep(forTimeInterval: 0.5)

            // Rescan to update state
            Task { @MainActor in
                scan()
            }

            return true
        } catch {
            NSLog("[ProcessDiscovery] Failed to stop daemon \(label): \(error)")
            // Fall back to kill
            return kill(pid: process.pid)
        }
    }

    /// Restart a daemon process using launchctl kickstart
    public func restartDaemon(for process: DiscoveredProcess) -> Bool {
        guard process.isDaemon, let env = process.environment else { return false }

        let label: String
        switch process.name {
        case "TalkieEngine":
            label = env.engineLaunchdLabel
        case "TalkieLive":
            label = env.liveLaunchdLabel
        default:
            return false
        }

        // Use launchctl kickstart -k to restart (kills existing and starts new)
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "-k", "gui/\(uid)/\(label)"]

        do {
            try task.run()
            task.waitUntilExit()

            Thread.sleep(forTimeInterval: 0.5)

            Task { @MainActor in
                scan()
            }

            return task.terminationStatus == 0
        } catch {
            NSLog("[ProcessDiscovery] Failed to restart daemon \(label): \(error)")
            return false
        }
    }
}
