//
//  LiveTranscriptionTrace.swift
//  TalkieLive
//
//  Step-level performance tracing for the full dictation flow.
//  Modeled after TalkieEngine's TranscriptionTrace.
//
//  Emits os_signpost intervals for Instruments profiling.
//  Uses mach_absolute_time for minimal overhead, monotonic timing.
//

import Foundation
import os.signpost

// MARK: - Signpost Configuration

/// Shared signpost log for TalkieLive performance profiling in Instruments
/// Uses consistent subsystem for cross-app correlation
let livePerformanceLog = OSLog(subsystem: "jdi.talkie.performance", category: "Live")

// MARK: - Trace Step

/// A single step in the dictation pipeline
struct LiveTraceStep: Identifiable {
    let id = UUID()
    let name: String        // e.g., "recording", "file_write", "xpc_call"
    let startMs: Int        // Milliseconds from trace start
    let durationMs: Int     // How long this step took
    let metadata: String?   // Optional detail (e.g., "2.3s audio", "48KB")

    var endMs: Int { startMs + durationMs }
}

// MARK: - Live Transcription Trace

/// Collects timing for all steps in a dictation flow (hotkey → paste)
/// Automatically emits os_signpost intervals for Instruments profiling
/// Uses mach_absolute_time for minimal overhead
final class LiveTranscriptionTrace {
    let traceId: String

    /// The mach_absolute_time when the trace started
    /// Can be initialized from a HotKeyTimestamp for accurate hotkey → recording measurement
    private let startTicks: UInt64

    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private var steps: [LiveTraceStep] = []
    private var stepStartTicks: UInt64 = 0
    private var currentStepName: String?

    // Signpost tracking for Instruments
    private let signpostLog = livePerformanceLog
    private var currentSignpostID: OSSignpostID?

    // External reference ID for correlation with Engine
    var externalRefId: String?

    /// Initialize a trace, optionally with a precise hotkey timestamp
    /// - Parameters:
    ///   - traceId: Optional trace ID (auto-generated if nil)
    ///   - hotkeyTimestamp: If provided, uses the precise mach_absolute_time from the Carbon callback
    init(traceId: String? = nil, hotkeyTimestamp: HotKeyTimestamp? = nil) {
        self.traceId = traceId ?? Self.generateTraceId()
        self.startTicks = hotkeyTimestamp?.machTicks ?? mach_absolute_time()
    }

    deinit {
        // IMPORTANT: Close any open signpost interval to prevent crashes
        // The os_signpost API requires balanced begin/end calls
        if let signpostID = currentSignpostID, let name = currentStepName {
            os_signpost(.end, log: signpostLog, name: "Live Step", signpostID: signpostID,
                        "%{public}s (abandoned)", name)
        }
    }

    /// Generate a short trace ID (8-char hex)
    private static func generateTraceId() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    /// Convert mach ticks to milliseconds
    private func ticksToMs(_ ticks: UInt64) -> Int {
        let nanos = ticks * UInt64(Self.timebaseInfo.numer) / UInt64(Self.timebaseInfo.denom)
        return Int(nanos / 1_000_000)
    }

    // MARK: - Step Tracking

    /// Begin timing a step - also emits os_signpost for Instruments
    func begin(_ name: String) {
        // End any previous step first (auto-close if caller forgot to call end())
        if let prevName = currentStepName, stepStartTicks > 0 {
            let now = mach_absolute_time()
            let durationMs = ticksToMs(now - stepStartTicks)

            // End previous signpost
            if let signpostID = currentSignpostID {
                os_signpost(.end, log: signpostLog, name: "Live Step", signpostID: signpostID, "%{public}s", prevName)
            }

            endStep(prevName, startTicks: stepStartTicks, durationMs: durationMs)
        }

        currentStepName = name
        stepStartTicks = mach_absolute_time()

        // Emit signpost begin for Instruments
        let signpostID = OSSignpostID(log: signpostLog)
        currentSignpostID = signpostID
        os_signpost(.begin, log: signpostLog, name: "Live Step", signpostID: signpostID,
                    "trace=%{public}s step=%{public}s", traceId, name)
    }

    /// End the current step with optional metadata
    /// Returns the step duration in milliseconds
    @discardableResult
    func end(_ metadata: String? = nil) -> Int {
        guard let name = currentStepName, stepStartTicks > 0 else { return 0 }

        let now = mach_absolute_time()
        let durationMs = ticksToMs(now - stepStartTicks)

        // End signpost for Instruments
        if let signpostID = currentSignpostID {
            if let meta = metadata {
                os_signpost(.end, log: signpostLog, name: "Live Step", signpostID: signpostID,
                            "%{public}s: %{public}s (%dms)", name, meta, durationMs)
            } else {
                os_signpost(.end, log: signpostLog, name: "Live Step", signpostID: signpostID,
                            "%{public}s (%dms)", name, durationMs)
            }
            currentSignpostID = nil
        }

        endStep(name, startTicks: stepStartTicks, durationMs: durationMs, metadata: metadata)
        currentStepName = nil
        stepStartTicks = 0

        return durationMs
    }

    private func endStep(_ name: String, startTicks: UInt64, durationMs: Int, metadata: String? = nil) {
        let startMs = ticksToMs(startTicks - self.startTicks)
        steps.append(LiveTraceStep(
            name: name,
            startMs: startMs,
            durationMs: durationMs,
            metadata: metadata
        ))
    }

    /// Mark a point in time (zero-duration event)
    func mark(_ name: String, metadata: String? = nil) {
        let startMs = ticksToMs(mach_absolute_time() - startTicks)
        steps.append(LiveTraceStep(
            name: name,
            startMs: startMs,
            durationMs: 0,
            metadata: metadata
        ))

        // Emit signpost event for Instruments
        if let meta = metadata {
            os_signpost(.event, log: signpostLog, name: "Live Mark",
                        "trace=%{public}s %{public}s: %{public}s", traceId, name, meta)
        } else {
            os_signpost(.event, log: signpostLog, name: "Live Mark",
                        "trace=%{public}s %{public}s", traceId, name)
        }
    }

    // MARK: - Lifecycle

    /// Invalidate the trace - closes any open signpost and prevents further use
    /// Call this before setting the trace to nil for clean lifecycle management
    func invalidate() {
        // Close any open step
        if currentStepName != nil {
            _ = end("invalidated")
        }
    }

    // MARK: - Results

    /// Get all recorded steps (sorted by start time)
    func getSteps() -> [LiveTraceStep] {
        return steps.sorted { $0.startMs < $1.startMs }
    }

    /// Total elapsed time since trace start in milliseconds
    var elapsedMs: Int {
        ticksToMs(mach_absolute_time() - startTicks)
    }

    /// Total elapsed seconds
    var elapsedSeconds: Double {
        Double(elapsedMs) / 1000.0
    }

    /// Longest step (bottleneck)
    var bottleneck: LiveTraceStep? {
        steps.max { $0.durationMs < $1.durationMs }
    }

    /// Summary string for logging
    var summary: String {
        let stepSummary = steps.map { "\($0.name)=\($0.durationMs)ms" }.joined(separator: ", ")
        return "[\(traceId)] \(elapsedMs)ms total: \(stepSummary)"
    }
}

// MARK: - Trace Metric (for storage/display)

/// A completed trace with all metrics
/// Recording duration is tracked separately since it's user-controlled, not a performance metric
struct LiveTraceMetric: Identifiable {
    let id = UUID()
    let traceId: String
    let timestamp: Date

    /// Total time INCLUDING recording (for reference only)
    let totalMs: Int

    let steps: [LiveTraceStep]

    // Context
    let wordCount: Int?
    let audioFilename: String?
    let audioDurationSeconds: Double?
    let transcriptPreview: String?
    let externalRefId: String?  // For Engine correlation

    /// Has step breakdown
    var hasSteps: Bool { !steps.isEmpty }

    // MARK: - Actionable Performance Metrics

    /// Actionable time EXCLUDING recording - this is what we can optimize
    /// Pre-recording (hotkey → record start) + Post-recording (record stop → paste)
    var actionableMs: Int {
        steps.filter { $0.name != "recording" }.reduce(0) { $0 + $1.durationMs }
    }

    /// Pre-recording latency: hotkey → recording starts
    /// This measures how quickly we respond to the hotkey
    var preRecordingMs: Int {
        var sum = 0
        for step in steps {
            if step.name == "recording" { break }
            sum += step.durationMs
        }
        return sum
    }

    /// Post-recording latency: recording stops → complete
    /// This measures transcription + routing + paste time
    var postRecordingMs: Int {
        var foundRecording = false
        var sum = 0
        for step in steps {
            if step.name == "recording" {
                foundRecording = true
                continue
            }
            if foundRecording {
                sum += step.durationMs
            }
        }
        return sum
    }

    /// Recording duration (user-controlled, not a performance metric)
    var recordingMs: Int {
        steps.first(where: { $0.name == "recording" })?.durationMs ?? 0
    }

    /// Bottleneck step (slowest, excluding recording since that's user-controlled)
    var bottleneck: LiveTraceStep? {
        steps.filter { $0.name != "recording" }.max { $0.durationMs < $1.durationMs }
    }

    /// Create from active trace
    init(from trace: LiveTranscriptionTrace,
         wordCount: Int? = nil,
         audioFilename: String? = nil,
         audioDurationSeconds: Double? = nil,
         transcriptPreview: String? = nil) {
        self.traceId = trace.traceId
        self.timestamp = Date()
        self.totalMs = trace.elapsedMs
        self.steps = trace.getSteps()
        self.wordCount = wordCount
        self.audioFilename = audioFilename
        self.audioDurationSeconds = audioDurationSeconds
        self.transcriptPreview = transcriptPreview
        self.externalRefId = trace.externalRefId
    }
}
