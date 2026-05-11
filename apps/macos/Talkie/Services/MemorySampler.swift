//
//  MemorySampler.swift
//  Talkie macOS
//
//  Lightweight in-app memory sampling for reports and diagnostics.
//

import Foundation
import TalkieKit

@MainActor
final class MemorySampler {
    static let shared = MemorySampler()

    struct Sample: Sendable {
        let timestamp: Date
        let memoryMB: Int
    }

    private let log = Log(.system)
    private var timer: Timer?

    private(set) var samples: [Sample] = []
    private(set) var peakMemoryMB: Int = 0
    private(set) var samplingInterval: TimeInterval = 10
    private(set) var maxSamples: Int = 360

    private init() {}

    func start(interval: TimeInterval = 10, maxSamples: Int = 360) {
        samplingInterval = max(1, interval)
        self.maxSamples = max(10, maxSamples)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: samplingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleNow()
            }
        }

        sampleNow()
        log.info("Memory sampler started", detail: "interval=\(Int(samplingInterval))s, maxSamples=\(self.maxSamples)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        log.info("Memory sampler stopped")
    }

    func sampleNow() {
        guard let memoryMB = Self.currentMemoryMB() else { return }
        appendSample(Sample(timestamp: Date(), memoryMB: memoryMB))
    }

    func snapshot() -> MemorySnapshot {
        let current = samples.last?.memoryMB
        let average = samples.isEmpty ? nil : Int(samples.map(\.memoryMB).reduce(0, +) / samples.count)
        let windowSeconds: Int
        if let first = samples.first, let last = samples.last {
            windowSeconds = Int(last.timestamp.timeIntervalSince(first.timestamp))
        } else {
            windowSeconds = 0
        }

        return MemorySnapshot(
            currentMB: current,
            peakMB: peakMemoryMB,
            averageMB: average,
            sampleCount: samples.count,
            windowSeconds: windowSeconds
        )
    }

    private func appendSample(_ sample: Sample) {
        samples.append(sample)
        peakMemoryMB = max(peakMemoryMB, sample.memoryMB)

        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    // MARK: - Memory Query

    /// Memory usage in MB (physical footprint, Activity Monitor-aligned).
    static func currentMemoryMB() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint / 1_048_576)
    }
}

struct MemorySnapshot: Sendable {
    let currentMB: Int?
    let peakMB: Int
    let averageMB: Int?
    let sampleCount: Int
    let windowSeconds: Int
}
