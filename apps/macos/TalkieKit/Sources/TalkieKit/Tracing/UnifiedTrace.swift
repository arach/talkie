//
//  UnifiedTrace.swift
//  TalkieKit
//
//  Unified tracing infrastructure for cross-app performance correlation.
//  All apps (Talkie, TalkieAgent, TalkieEngine) can emit spans in a common format,
//  allowing end-to-end visualization of dictation flows.
//
//  Usage:
//    let trace = UnifiedTrace(source: .live)
//    trace.begin("context_capture")
//    // ... do work ...
//    trace.end()
//    trace.begin("recording")
//    // ... etc ...
//
//  The traceId is shared across apps via XPC calls, enabling correlation.
//

import Foundation
import os.signpost

// MARK: - Trace Source

/// Which app emitted the trace span
public enum TraceSource: String, Codable, Sendable {
    case talkie = "Talkie"
    case live = "Live"
    case engine = "Engine"

    public var icon: String {
        switch self {
        case .talkie: return "app.fill"
        case .live: return "menubar.rectangle"
        case .engine: return "gearshape.fill"
        }
    }

    public var shortName: String {
        rawValue
    }
}

// MARK: - Trace Span

/// A single timed operation within a trace
/// Spans can be nested via parentSpanId
public struct TraceSpan: Identifiable, Codable, Sendable {
    public let id: String           // Unique span ID
    public let traceId: String      // Shared across all spans in a flow
    public let parentSpanId: String? // For nested operations
    public let source: TraceSource
    public let name: String
    public let startTime: Date
    public let duration: TimeInterval
    public let metadata: [String: String]

    /// Duration in milliseconds (convenience)
    public var durationMs: Int {
        Int(duration * 1000)
    }

    /// Start time as milliseconds offset from a reference point
    public func startMs(relativeTo reference: Date) -> Int {
        Int(startTime.timeIntervalSince(reference) * 1000)
    }

    /// End time
    public var endTime: Date {
        startTime.addingTimeInterval(duration)
    }

    /// Whether this is a user-controlled step (like recording time)
    public var isUserControlled: Bool {
        ["recording", "record", "user_input", "speaking"].contains(name.lowercased())
    }

    public init(
        id: String = UUID().uuidString,
        traceId: String,
        parentSpanId: String? = nil,
        source: TraceSource,
        name: String,
        startTime: Date,
        duration: TimeInterval,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.traceId = traceId
        self.parentSpanId = parentSpanId
        self.source = source
        self.name = name
        self.startTime = startTime
        self.duration = duration
        self.metadata = metadata
    }
}

// MARK: - Unified Trace

/// Collects spans for a single end-to-end flow
/// The traceId can be passed to other apps for correlation
public final class UnifiedTrace: @unchecked Sendable {
    public let traceId: String
    public let source: TraceSource
    public let startTime: Date

    private let lock = NSLock()
    private var _spans: [TraceSpan] = []
    private var currentSpanStart: Date?
    private var currentSpanName: String?
    private var currentSpanMetadata: [String: String] = [:]

    // Signpost for Instruments
    private static let signpostLog = OSLog(subsystem: "jdi.talkie.trace", category: "Unified")
    private var currentSignpostID: OSSignpostID?

    /// All completed spans (thread-safe read)
    public var spans: [TraceSpan] {
        lock.lock()
        defer { lock.unlock() }
        return _spans
    }

    /// Total elapsed time since trace start
    public var elapsedMs: Int {
        Int(Date().timeIntervalSince(startTime) * 1000)
    }

    /// System latency (excludes user-controlled spans like recording)
    public var systemLatencyMs: Int {
        spans.filter { !$0.isUserControlled }.reduce(0) { $0 + $1.durationMs }
    }

    /// Initialize a new trace
    /// - Parameters:
    ///   - source: Which app is creating this trace
    ///   - traceId: Optional ID for correlation (auto-generated if nil)
    ///   - startTime: Optional custom start time (defaults to now)
    public init(source: TraceSource, traceId: String? = nil, startTime: Date? = nil) {
        self.source = source
        self.traceId = traceId ?? Self.generateTraceId()
        self.startTime = startTime ?? Date()
    }

    /// Generate a short trace ID (8-char hex)
    public static func generateTraceId() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    // MARK: - Span Recording

    /// Begin timing a span
    public func begin(_ name: String, metadata: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }

        // Auto-close any open span
        if let prevName = currentSpanName, let prevStart = currentSpanStart {
            let duration = Date().timeIntervalSince(prevStart)
            _spans.append(TraceSpan(
                traceId: traceId,
                source: source,
                name: prevName,
                startTime: prevStart,
                duration: duration,
                metadata: currentSpanMetadata
            ))

            // End previous signpost
            if let signpostID = currentSignpostID {
                os_signpost(.end, log: Self.signpostLog, name: "Span", signpostID: signpostID)
            }
        }

        currentSpanName = name
        currentSpanStart = Date()
        currentSpanMetadata = metadata

        // Begin signpost for Instruments
        let signpostID = OSSignpostID(log: Self.signpostLog)
        currentSignpostID = signpostID
        os_signpost(.begin, log: Self.signpostLog, name: "Span", signpostID: signpostID,
                    "[%{public}s] %{public}s.%{public}s", traceId, source.rawValue, name)
    }

    /// End the current span
    @discardableResult
    public func end(metadata: [String: String] = [:]) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        guard let name = currentSpanName, let start = currentSpanStart else { return 0 }

        let duration = Date().timeIntervalSince(start)
        var finalMetadata = currentSpanMetadata
        finalMetadata.merge(metadata) { _, new in new }

        _spans.append(TraceSpan(
            traceId: traceId,
            source: source,
            name: name,
            startTime: start,
            duration: duration,
            metadata: finalMetadata
        ))

        // End signpost
        if let signpostID = currentSignpostID {
            os_signpost(.end, log: Self.signpostLog, name: "Span", signpostID: signpostID,
                        "%{public}s (%dms)", name, Int(duration * 1000))
            currentSignpostID = nil
        }

        currentSpanName = nil
        currentSpanStart = nil
        currentSpanMetadata = [:]

        return duration
    }

    /// Add a completed span directly (for importing from other apps)
    public func addSpan(_ span: TraceSpan) {
        lock.lock()
        defer { lock.unlock() }
        _spans.append(span)
    }

    /// Mark a point-in-time event (zero-duration)
    public func mark(_ name: String, metadata: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }

        _spans.append(TraceSpan(
            traceId: traceId,
            source: source,
            name: name,
            startTime: Date(),
            duration: 0,
            metadata: metadata
        ))

        os_signpost(.event, log: Self.signpostLog, name: "Mark",
                    "[%{public}s] %{public}s.%{public}s", traceId, source.rawValue, name)
    }

    // MARK: - Summary

    /// Summary string for logging
    public var summary: String {
        let spanSummary = spans.map { "\($0.name)=\($0.durationMs)ms" }.joined(separator: ", ")
        return "[\(traceId)] \(source.rawValue) \(elapsedMs)ms: \(spanSummary)"
    }

    /// Bottleneck span (slowest, excluding user-controlled)
    public var bottleneck: TraceSpan? {
        spans.filter { !$0.isUserControlled }.max { $0.duration < $1.duration }
    }
}

// MARK: - Correlated Trace

/// A complete end-to-end trace with spans from multiple apps
public struct CorrelatedTrace: Identifiable, Sendable {
    public let id: String  // Same as traceId
    public let traceId: String
    public let startTime: Date
    public var spans: [TraceSpan]

    /// Spans grouped by source
    public var spansBySource: [TraceSource: [TraceSpan]] {
        Dictionary(grouping: spans, by: { $0.source })
    }

    /// Total system latency (excludes user-controlled spans)
    public var systemLatencyMs: Int {
        spans.filter { !$0.isUserControlled }.reduce(0) { $0 + $1.durationMs }
    }

    /// User-controlled time (like recording duration)
    public var userTimeMs: Int {
        spans.filter { $0.isUserControlled }.reduce(0) { $0 + $1.durationMs }
    }

    /// Total duration from first span start to last span end
    public var totalDurationMs: Int {
        guard let first = spans.min(by: { $0.startTime < $1.startTime }),
              let last = spans.max(by: { $0.endTime < $1.endTime }) else {
            return 0
        }
        return Int(last.endTime.timeIntervalSince(first.startTime) * 1000)
    }

    /// Which sources contributed spans
    public var sources: Set<TraceSource> {
        Set(spans.map { $0.source })
    }

    /// Whether we have spans from all three apps
    public var isComplete: Bool {
        sources.contains(.live) && sources.contains(.engine)
    }

    /// Bottleneck span across all sources
    public var bottleneck: TraceSpan? {
        spans.filter { !$0.isUserControlled }.max { $0.duration < $1.duration }
    }

    public init(traceId: String, spans: [TraceSpan] = []) {
        self.id = traceId
        self.traceId = traceId
        self.startTime = spans.min(by: { $0.startTime < $1.startTime })?.startTime ?? Date()
        self.spans = spans.sorted { $0.startTime < $1.startTime }
    }

    /// Add spans from another trace with the same traceId
    public mutating func merge(spans newSpans: [TraceSpan]) {
        spans.append(contentsOf: newSpans.filter { $0.traceId == traceId })
        spans.sort { $0.startTime < $1.startTime }
    }
}
