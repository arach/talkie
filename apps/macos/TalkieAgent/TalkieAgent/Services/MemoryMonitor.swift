//
//  MemoryMonitor.swift
//  TalkieAgent
//
//  Tracks memory usage and logs when crossing thresholds.
//  Helps diagnose memory leaks by showing when usage climbs.
//

import Foundation
import Darwin.Mach
import TalkieKit

private let log = Log(.system)

/// Monitors memory usage and logs when crossing defined thresholds
final class MemoryMonitor {
    static let shared = MemoryMonitor()

    /// Thresholds in MB - logs once when each is crossed
    private let thresholdsMB: [Int] = [100, 250, 500, 750, 1000, 1500, 2000, 3000]

    /// Track which thresholds have been logged (reset on app launch)
    private var loggedThresholds: Set<Int> = []

    /// Timer for periodic checks
    private var timer: Timer?

    /// Last recorded memory for delta tracking
    private var lastMemoryMB: Int = 0

    private init() {}

    /// Start monitoring (call once at app launch)
    func start(interval: TimeInterval = 600) {
        // Log initial memory
        let initialMB = currentMemoryMB()
        lastMemoryMB = initialMB
        log.info("Memory monitor started", detail: "\(initialMB) MB")

        // Check periodically
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkMemory()
        }
    }

    /// Stop monitoring
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Manual check (can be called from debug UI)
    func checkMemory() {
        let currentMB = currentMemoryMB()

        // Check if we crossed any new thresholds
        for threshold in thresholdsMB {
            if currentMB >= threshold && !loggedThresholds.contains(threshold) {
                loggedThresholds.insert(threshold)
                let delta = currentMB - lastMemoryMB
                let deltaStr = delta >= 0 ? "+\(delta)" : "\(delta)"
                log.info("Memory crossed \(threshold) MB", detail: "now \(currentMB) MB (\(deltaStr) since last)")

                // Log context to help identify the culprit
                logMemoryContext()

                // Log full snapshot at higher thresholds
                if threshold >= 500 {
                    logMemorySnapshot()
                }
            }
        }

        lastMemoryMB = currentMB
    }

    /// Log context about what might be using memory
    private func logMemoryContext() {
        Task { @MainActor in
            var context: [String] = []

            // Audio memory tracker (most likely culprit)
            let audio = AudioMemoryTracker.shared.summary
            context.append("audio_chunks=\(audio["audio_chunks"] ?? 0)(\(audio["audio_chunk_mb"] ?? 0)MB)")
            context.append("pcm_buf=\(audio["pcm_buffer_kb"] ?? 0)KB")
            context.append("temp_files=\(audio["temp_files"] ?? 0)")

            // Ambient audio state
            let ambient = AmbientAudioCapture.shared
            context.append("ambient_dur=\(String(format: "%.0f", ambient.totalBufferedDuration))s")

            // Database counts
            let dictationCount = UnifiedDatabase.countDictations()
            context.append("dictations=\(dictationCount)")

            // System events (debug logging)
            let eventCount = SystemEventManager.shared.events.count
            context.append("events=\(eventCount)")

            // Log viewer entries
            let logEntries = AppLogger.shared.entries.count
            context.append("log_entries=\(logEntries)")

            log.info("Memory context", detail: context.joined(separator: ", "))
        }
    }

    /// Get current memory usage in MB
    func currentMemoryMB() -> Int {
        Int(getMemoryFootprint() / 1_000_000)
    }

    /// Get memory footprint in bytes using Mach API
    private func getMemoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Get current memory as formatted string
    var currentMemoryFormatted: String {
        let mb = currentMemoryMB()
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }

    /// Reset threshold tracking (useful after investigating a spike)
    func resetThresholds() {
        loggedThresholds.removeAll()
        log.info("Memory thresholds reset", detail: "will log again on next crossing")
    }

    // MARK: - Memory Stack Inspection

    /// Capture detailed memory breakdown
    func captureMemorySnapshot() -> MemorySnapshot {
        var snapshot = MemorySnapshot()
        snapshot.timestamp = Date()

        // Task VM info
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            snapshot.physicalFootprint = info.phys_footprint
            snapshot.virtualSize = info.virtual_size
            snapshot.residentSize = info.resident_size
            snapshot.residentSizePeak = info.resident_size_peak
            snapshot.compressed = info.compressed
            snapshot.internalMemory = info.internal
            snapshot.externalMemory = info.external
        }

        // Malloc zone stats
        snapshot.mallocZones = getMallocZoneStats()

        return snapshot
    }

    /// Log a full memory snapshot
    func logMemorySnapshot() {
        let snapshot = captureMemorySnapshot()

        log.info("Memory snapshot", detail: """
            physical=\(snapshot.physicalMB)MB, \
            virtual=\(snapshot.virtualMB)MB, \
            resident=\(snapshot.residentMB)MB (peak=\(snapshot.residentPeakMB)MB), \
            internal=\(snapshot.internalMB)MB, \
            external=\(snapshot.externalMB)MB, \
            compressed=\(snapshot.compressedMB)MB
            """.replacingOccurrences(of: "\n", with: ""))

        // Log malloc zones
        for zone in snapshot.mallocZones {
            log.info("Malloc zone: \(zone.name)", detail: "size=\(zone.sizeMB)MB, blocks=\(zone.blockCount)")
        }
    }

    /// Get malloc zone statistics
    private func getMallocZoneStats() -> [MallocZoneInfo] {
        var zones: [MallocZoneInfo] = []

        // Get default zone
        if let defaultZone = malloc_default_zone() {
            var stats = malloc_statistics_t()
            malloc_zone_statistics(defaultZone, &stats)

            zones.append(MallocZoneInfo(
                name: "default",
                sizeInUse: stats.size_in_use,
                maxSizeInUse: stats.max_size_in_use,
                blockCount: Int(stats.blocks_in_use)
            ))
        }

        return zones
    }
}

// MARK: - Memory Snapshot

struct MemorySnapshot {
    var timestamp: Date = Date()
    var physicalFootprint: UInt64 = 0
    var virtualSize: UInt64 = 0
    var residentSize: UInt64 = 0
    var residentSizePeak: UInt64 = 0
    var compressed: UInt64 = 0
    var internalMemory: UInt64 = 0
    var externalMemory: UInt64 = 0
    var mallocZones: [MallocZoneInfo] = []

    var physicalMB: Int { Int(physicalFootprint / 1_000_000) }
    var virtualMB: Int { Int(virtualSize / 1_000_000) }
    var residentMB: Int { Int(residentSize / 1_000_000) }
    var residentPeakMB: Int { Int(residentSizePeak / 1_000_000) }
    var compressedMB: Int { Int(compressed / 1_000_000) }
    var internalMB: Int { Int(internalMemory / 1_000_000) }
    var externalMB: Int { Int(externalMemory / 1_000_000) }
}

struct MallocZoneInfo {
    let name: String
    let sizeInUse: Int
    let maxSizeInUse: Int
    let blockCount: Int

    var sizeMB: Int { sizeInUse / 1_000_000 }
    var maxSizeMB: Int { maxSizeInUse / 1_000_000 }
}
