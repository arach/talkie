//
//  MemoryInstrumentation.swift
//  Talkie
//
//  Memory debugging utilities for tracking allocations and identifying leaks.
//  Only active in DEBUG builds.
//

import Foundation

#if DEBUG

private let logger = Log(.system)

// MARK: - Memory Monitor

/// Monitors memory usage and reports significant allocations
@MainActor
@Observable
final class MemoryMonitor {
    static let shared = MemoryMonitor()

    // Current stats
    var footprintMB: Double = 0
    var peakFootprintMB: Double = 0
    var residentMB: Double = 0

    // History for graphing
    var history: [MemorySample] = []
    private let maxHistoryCount = 120  // 2 minutes at 1 sample/sec

    // Tracking
    private var timer: Timer?
    private var isRunning = false

    struct MemorySample: Identifiable {
        let id = UUID()
        let timestamp: Date
        let footprintMB: Double
        let residentMB: Double
    }

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Sample immediately
        sample()

        // Then sample every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }

        logger.info("Memory monitor started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        logger.info("Memory monitor stopped")
    }

    private func sample() {
        let stats = Self.getMemoryStats()

        footprintMB = stats.footprintMB
        residentMB = stats.residentMB

        if footprintMB > peakFootprintMB {
            peakFootprintMB = footprintMB
        }

        let sample = MemorySample(
            timestamp: Date(),
            footprintMB: footprintMB,
            residentMB: residentMB
        )

        history.append(sample)
        if history.count > maxHistoryCount {
            history.removeFirst()
        }
    }

    /// Get current memory statistics (nonisolated - safe to call from any context)
    nonisolated static func getMemoryStats() -> (footprintMB: Double, residentMB: Double, virtualMB: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0, 0)
        }

        let footprintMB = Double(info.phys_footprint) / 1_048_576
        let residentMB = Double(info.resident_size) / 1_048_576
        let virtualMB = Double(info.virtual_size) / 1_048_576

        return (footprintMB, residentMB, virtualMB)
    }

    /// Log current memory state
    func logState(context: String = "") {
        let stats = Self.getMemoryStats()
        let contextStr = context.isEmpty ? "" : " [\(context)]"
        logger.info("Memory\(contextStr): footprint=\(String(format: "%.1f", stats.footprintMB))MB, resident=\(String(format: "%.1f", stats.residentMB))MB, peak=\(String(format: "%.1f", self.peakFootprintMB))MB")
    }
}

// MARK: - Allocation Tracker

/// Tracks specific allocations by category
final class AllocationTracker: @unchecked Sendable {
    static let shared = AllocationTracker()

    private let lock = NSLock()
    private var allocations: [String: AllocationCategory] = [:]

    struct AllocationCategory {
        var count: Int = 0
        var totalBytes: Int = 0
        var peakBytes: Int = 0
    }

    private init() {}

    /// Track an allocation
    func track(_ category: String, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }

        var cat = allocations[category] ?? AllocationCategory()
        cat.count += 1
        cat.totalBytes += bytes
        if cat.totalBytes > cat.peakBytes {
            cat.peakBytes = cat.totalBytes
        }
        allocations[category] = cat
    }

    /// Untrack an allocation (when freed)
    func untrack(_ category: String, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard var cat = allocations[category] else { return }
        cat.count = max(0, cat.count - 1)
        cat.totalBytes = max(0, cat.totalBytes - bytes)
        allocations[category] = cat
    }

    /// Get summary of all tracked categories
    func summary() -> [(category: String, count: Int, bytes: Int, peakBytes: Int)] {
        lock.lock()
        defer { lock.unlock() }

        return allocations.map { (category: $0.key, count: $0.value.count, bytes: $0.value.totalBytes, peakBytes: $0.value.peakBytes) }
            .sorted { $0.bytes > $1.bytes }
    }

    /// Log summary
    func logSummary() {
        let items = summary()
        logger.info("Allocation Tracker Summary:")
        for item in items.prefix(10) {
            let mb = Double(item.bytes) / 1_048_576
            let peakMB = Double(item.peakBytes) / 1_048_576
            logger.info("  \(item.category): \(item.count) items, \(String(format: "%.2f", mb))MB (peak: \(String(format: "%.2f", peakMB))MB)")
        }
    }

    /// Reset all tracking
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        allocations.removeAll()
    }
}

// MARK: - View Hierarchy Depth Tracker

/// Tracks SwiftUI view hierarchy depth to detect deeply nested views
/// (which cause "call stack limit reached" in Instruments)
final class ViewDepthTracker: @unchecked Sendable {
    static let shared = ViewDepthTracker()

    private let lock = NSLock()
    private var maxDepth: Int = 0
    private var currentDepth: Int = 0
    private var deepestPath: [String] = []

    private init() {}

    /// Call when entering a view body
    func enter(_ viewName: String) {
        lock.lock()
        defer { lock.unlock() }

        currentDepth += 1

        if currentDepth > maxDepth {
            maxDepth = currentDepth
            // Only track path for unusually deep hierarchies
            let depth = maxDepth
            if depth > 30 {
                logger.warning("Deep view hierarchy detected: depth=\(depth), view=\(viewName)")
            }
        }
    }

    /// Call when exiting a view body
    func exit() {
        lock.lock()
        defer { lock.unlock() }
        currentDepth = max(0, currentDepth - 1)
    }

    var maximumDepth: Int {
        lock.lock()
        defer { lock.unlock() }
        return maxDepth
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        maxDepth = 0
        currentDepth = 0
        deepestPath.removeAll()
    }
}

// MARK: - Memory Pressure Handler

/// Responds to system memory pressure notifications
@MainActor
final class MemoryPressureHandler {
    static let shared = MemoryPressureHandler()

    private var source: DispatchSourceMemoryPressure?
    private var handlers: [() -> Void] = []

    private init() {}

    /// Start listening for memory pressure
    func start() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)

        source?.setEventHandler { [weak self] in
            guard let self = self, let source = self.source else { return }

            let event = source.data
            if event.contains(.critical) {
                logger.error("CRITICAL memory pressure - purging caches")
                self.handlePressure(critical: true)
            } else if event.contains(.warning) {
                logger.warning("Memory pressure warning - reducing footprint")
                self.handlePressure(critical: false)
            }
        }

        source?.resume()
        logger.info("Memory pressure handler started")
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// Register a handler to be called on memory pressure
    func onPressure(_ handler: @escaping () -> Void) {
        handlers.append(handler)
    }

    private func handlePressure(critical: Bool) {
        // Log current state
        let stats = MemoryMonitor.getMemoryStats()
        logger.info("Memory at pressure event: \(String(format: "%.1f", stats.footprintMB))MB")

        // Notify handlers
        for handler in handlers {
            handler()
        }

        // Force a GC cycle
        // Note: This is a hint, not guaranteed
        autoreleasepool { }
    }
}

// MARK: - Debug Helpers

extension MemoryMonitor {
    /// Format bytes as human-readable string
    nonisolated static func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return "\(bytes) B"
        }
    }
}

// MARK: - View Modifier for Depth Tracking

import SwiftUI
import TalkieKit

/// Modifier to track view hierarchy depth
struct TrackViewDepth: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                ViewDepthTracker.shared.enter(name)
            }
            .onDisappear {
                ViewDepthTracker.shared.exit()
            }
    }
}

extension View {
    /// Track this view's depth in the hierarchy (DEBUG only)
    /// Usage: MyView().trackDepth("MyView")
    func trackDepth(_ name: String = #function) -> some View {
        modifier(TrackViewDepth(name: name))
    }
}

#endif
