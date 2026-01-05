//
//  LivePerformanceStore.swift
//  TalkieLive
//
//  Collects and stores completed LiveTraceMetrics for performance analysis.
//  Observable for SwiftUI binding.
//

import Foundation
import SwiftUI

/// Stores completed performance traces for viewing in debug UI
@MainActor
final class LivePerformanceStore: ObservableObject {
    static let shared = LivePerformanceStore()

    /// Maximum number of traces to keep in memory
    private let maxTraces = 50

    /// Completed traces, most recent first
    @Published private(set) var traces: [LiveTraceMetric] = []

    /// Current trace in progress (if any)
    @Published var activeTrace: LiveTranscriptionTrace?

    private init() {}

    /// Add a completed trace to the store
    func add(_ metric: LiveTraceMetric) {
        traces.insert(metric, at: 0)

        // Trim to max size
        if traces.count > maxTraces {
            traces.removeLast(traces.count - maxTraces)
        }
    }

    /// Clear all stored traces
    func clear() {
        traces.removeAll()
    }

    // MARK: - Statistics (Actionable Time - excludes recording)

    /// Average actionable time across all traces (excludes recording)
    var averageActionableMs: Int {
        guard !traces.isEmpty else { return 0 }
        let sum = traces.reduce(0) { $0 + $1.actionableMs }
        return sum / traces.count
    }

    /// 95th percentile actionable time (excludes recording)
    var p95ActionableMs: Int {
        guard traces.count >= 5 else { return traces.first?.actionableMs ?? 0 }
        let sorted = traces.map { $0.actionableMs }.sorted()
        let index = Int(Double(sorted.count) * 0.95)
        return sorted[min(index, sorted.count - 1)]
    }

    /// Average pre-recording latency (hotkey → recording starts)
    var averagePreRecordingMs: Int {
        guard !traces.isEmpty else { return 0 }
        let sum = traces.reduce(0) { $0 + $1.preRecordingMs }
        return sum / traces.count
    }

    /// Average post-recording latency (recording stops → complete)
    var averagePostRecordingMs: Int {
        guard !traces.isEmpty else { return 0 }
        let sum = traces.reduce(0) { $0 + $1.postRecordingMs }
        return sum / traces.count
    }

    /// Average time for a specific step across all traces
    func averageFor(step: String) -> Int {
        let stepsWithName = traces.flatMap { $0.steps.filter { $0.name == step } }
        guard !stepsWithName.isEmpty else { return 0 }
        let sum = stepsWithName.reduce(0) { $0 + $1.durationMs }
        return sum / stepsWithName.count
    }

    /// Most common bottleneck step name (excludes recording)
    var mostCommonBottleneck: String? {
        let bottlenecks = traces.compactMap { $0.bottleneck?.name }
        guard !bottlenecks.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for name in bottlenecks {
            counts[name, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Step Statistics

extension LivePerformanceStore {
    /// Get statistics for all step names across traces (excludes recording)
    var stepStatistics: [StepStats] {
        var statsByName: [String: [Int]] = [:]

        for trace in traces {
            // Exclude recording from statistics - it's user-controlled
            for step in trace.steps where step.durationMs > 0 && step.name != "recording" {
                statsByName[step.name, default: []].append(step.durationMs)
            }
        }

        return statsByName.map { name, durations in
            let sorted = durations.sorted()
            let avg = sorted.reduce(0, +) / sorted.count
            let min = sorted.first ?? 0
            let max = sorted.last ?? 0
            let p95Index = Int(Double(sorted.count) * 0.95)
            let p95 = sorted[Swift.min(p95Index, sorted.count - 1)]

            return StepStats(
                name: name,
                count: durations.count,
                avgMs: avg,
                minMs: min,
                maxMs: max,
                p95Ms: p95
            )
        }.sorted { $0.avgMs > $1.avgMs }  // Sort by average duration descending
    }
}

/// Statistics for a single step type
struct StepStats: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let avgMs: Int
    let minMs: Int
    let maxMs: Int
    let p95Ms: Int
}
