//
//  HelperProcessState.swift
//  Talkie
//
//  Generic observable process state for helper apps.
//  Replaces per-helper state classes (SyncServiceState etc.) with a
//  single reusable class parameterized by TalkieHelper.
//

import Foundation
import AppKit
import Observation
import TalkieKit

private let log = Log(.system)

/// Observable state for a Talkie helper process.
///
/// Tracks process lifecycle (running, PID, uptime) and XPC connection status.
/// Used directly for Sync; Agent/Engine keep their own subclasses for now
/// since they carry domain-specific state (recording, transcription).
@MainActor
@Observable
public final class HelperProcessState {

    /// Which helper this state tracks
    public let kind: TalkieHelper

    // ─── Process Detection ───
    public private(set) var isRunning: Bool = false
    public private(set) var processId: pid_t?
    public private(set) var bundlePath: String?
    public private(set) var launchedAt: Date?
    public private(set) var uptime: TimeInterval = 0

    // ─── Connection (set by XPC clients) ───
    public private(set) var isConnected: Bool = false
    public private(set) var environment: TalkieEnvironment?

    // ─── Resource Usage ───
    public private(set) var cpuUsage: Double = 0
    public private(set) var memoryUsage: UInt64 = 0

    public init(kind: TalkieHelper) {
        self.kind = kind
    }

    // MARK: - Process Detection

    func refreshProcessState() {
        if let runtimeState = TalkieHelperRuntimeStateStore.validatedState(
            for: kind,
            environment: TalkieEnvironment.current
        ) {
            isRunning = true
            processId = runtimeState.processId
            bundlePath = runtimeState.executablePath
            launchedAt = runtimeState.startedAt
            uptime = Date().timeIntervalSince(runtimeState.startedAt)

            Task.detached { [weak self] in
                await self?.updateResourceUsage(pid: runtimeState.processId)
            }
            return
        }

        let bundleId = kind.bundleId(for: TalkieEnvironment.current)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)

        if let app = apps.first {
            isRunning = true
            processId = app.processIdentifier
            bundlePath = app.bundleURL?.path

            if launchedAt == nil {
                launchedAt = talkieProcessStartTime(pid: app.processIdentifier) ?? Date()
            }
            if let launched = launchedAt {
                uptime = Date().timeIntervalSince(launched)
            }

            // Update resource usage off main thread
            Task.detached { [weak self] in
                await self?.updateResourceUsage(pid: app.processIdentifier)
            }
        } else {
            // Only mark as not running if XPC is also not connected
            if !isConnected {
                isRunning = false
                processId = nil
                cpuUsage = 0
                memoryUsage = 0
                uptime = 0
                launchedAt = nil
                bundlePath = nil
            }
        }
    }

    /// Update from XPC client connection state
    public func updateConnectionState(connected: Bool, environment: TalkieEnvironment?) {
        isConnected = connected
        self.environment = environment
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

    // MARK: - Computed Properties

    /// Connected environment (alias for environment)
    public var connectedMode: TalkieEnvironment? { environment }

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

    // MARK: - Actions

    /// Terminate this helper
    public func terminate() {
        guard let pid = processId else { return }
        HelperLaunchManager.shared.terminate(kind, pid: pid)
    }

    /// Launch this helper
    public func launch() async {
        try? await HelperLaunchManager.shared.launch(kind)
    }

    /// Restart this helper
    public func restart() async {
        if let pid = processId {
            HelperLaunchManager.shared.terminate(kind, pid: pid)
            try? await Task.sleep(for: .milliseconds(500))
        }
        try? await HelperLaunchManager.shared.launch(kind)
    }

    // MARK: - Debug Info

    public var debugInfo: ServiceDebugInfo {
        let env = environment ?? TalkieEnvironment.current
        return ServiceDebugInfo(
            serviceName: kind.displayName,
            processId: processId,
            environment: environment,
            isXPCConnected: isConnected,
            xpcServiceName: env.xpcServiceName(for: kind),
            bundleId: env.bundleId(for: kind)
        )
    }
}
