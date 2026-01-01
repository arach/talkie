//
//  StartupProfiler.swift
//  Talkie
//
//  Precise timing instrumentation for startup performance analysis
//  Captures every milestone from process start to user-ready state
//

import Foundation
import os

// MARK: - Process Start Time (set at load time, before any Swift code)

/// Absolute earliest timestamp - set when this file is loaded
private let _processStartTime = CFAbsoluteTimeGetCurrent()

/// Centralized startup profiler - captures precise timestamps for every load step
/// Usage: StartupProfiler.shared.mark("milestone-name")
final class StartupProfiler {
    static let shared = StartupProfiler()

    /// Process start time (set at file load, before any Swift code runs)
    let processStart: CFAbsoluteTime = _processStartTime

    /// All recorded milestones with timestamps (thread-safe via lock)
    private var _milestones: [(name: String, time: CFAbsoluteTime, elapsed: Double)] = []
    private let lock = NSLock()

    var milestones: [(name: String, time: CFAbsoluteTime, elapsed: Double)] {
        lock.lock()
        defer { lock.unlock() }
        return _milestones
    }

    /// Track if we've printed the summary (protected by lock)
    private var _hasPrintedSummary = false

    private init() {}

    /// Mark a milestone with current timestamp (thread-safe, logs inline)
    func mark(_ name: String) {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = (now - processStart) * 1000

        lock.lock()
        _milestones.append((name: name, time: now, elapsed: elapsed))
        lock.unlock()

        // Use NSLog for immediate unbuffered output (print() is buffered in GUI apps)
        NSLog("⏱️ [%6.1fms] %@", elapsed, name)
    }

    /// Mark with inline print (same as mark, kept for compatibility)
    func markEarly(_ name: String) {
        mark(name)
    }

    /// Print full timeline summary (thread-safe)
    func printSummary() {
        lock.lock()
        guard !_hasPrintedSummary else {
            lock.unlock()
            return
        }
        _hasPrintedSummary = true
        let snapshotMilestones = _milestones
        lock.unlock()

        NSLog("\n" + String(repeating: "=", count: 60))
        NSLog("STARTUP TIMELINE")
        NSLog(String(repeating: "=", count: 60))

        var lastTime = processStart
        for (name, time, elapsed) in snapshotMilestones {
            let delta = (time - lastTime) * 1000
            let deltaStr = delta > 0.5 ? String(format: "+%.1fms", delta) : ""
            let paddedName = name.padding(toLength: 40, withPad: " ", startingAt: 0)
            NSLog(String(format: "%7.1fms  %@  %@", elapsed, paddedName, deltaStr))
            lastTime = time
        }

        if let last = snapshotMilestones.last {
            NSLog(String(repeating: "-", count: 60))
            NSLog(String(format: "%7.1fms  TOTAL TIME TO READY", last.elapsed))
        }
        NSLog(String(repeating: "=", count: 60) + "\n")
    }

    /// Reset for fresh measurement (thread-safe)
    func reset() {
        lock.lock()
        _milestones.removeAll()
        _hasPrintedSummary = false
        lock.unlock()
    }

    /// Log a compact one-liner snapshot of launch performance
    /// Suitable for production builds - outputs to system log and user-facing StartupLogger
    func logSnapshot() {
        lock.lock()
        let snapshot = _milestones
        lock.unlock()

        // Find key phase milestones
        let dataReady = snapshot.first { $0.name == "db.grdb.ready" }?.elapsed ?? 0
        let uiPresented = snapshot.first { $0.name == "home.dictations.rendered" }?.elapsed ?? 0
        let ready = snapshot.last?.elapsed ?? 0

        // System log: "🚀 Launch: data 45ms → ui 299ms → ready 347ms"
        let summary = String(format: "🚀 Launch: data %.0fms → ui %.0fms → ready %.0fms", dataReady, uiPresented, ready)
        NSLog("%@", summary)

        // User-facing log (StartupLogger feeds the Logs viewer)
        Task { @MainActor in
            StartupLogger.shared.log(String(format: "Ready in %.0fms (data %.0fms, ui %.0fms)", ready, dataReady, uiPresented))
        }
    }
}
