import Foundation
import Observation
import os

private let transcriptionSignpostLog = OSLog(subsystem: "to.talkie.app.engine", category: .pointsOfInterest)

struct EngineLogEntry: Identifiable {
    enum LogLevel {
        case debug
        case info
        case warning
        case error
    }

    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
}

struct TranscriptionStep {
    let name: String
    let startMs: Int
    let durationMs: Int
    let metadata: String?
}

final class TranscriptionTrace {
    let jobId = UUID()
    private let startTicks: UInt64 = mach_absolute_time()
    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    var externalRefId: String?
    private var steps: [TranscriptionStep] = []
    private var stepStartTicks: UInt64 = 0
    private var currentStepName: String?
    private let signpostLog = transcriptionSignpostLog
    private var currentSignpostID: OSSignpostID?

    private func ticksToMs(_ ticks: UInt64) -> Int {
        let nanos = ticks * UInt64(Self.timebaseInfo.numer) / UInt64(Self.timebaseInfo.denom)
        return Int(nanos / 1_000_000)
    }

    func begin(_ name: String) {
        if let previousName = currentStepName, stepStartTicks > 0 {
            let now = mach_absolute_time()
            let durationMs = ticksToMs(now - stepStartTicks)
            if let signpostID = currentSignpostID {
                os_signpost(.end, log: signpostLog, name: "Transcription Step", signpostID: signpostID, "%{public}s", previousName)
            }
            endStep(previousName, startTicks: stepStartTicks, durationMs: durationMs)
        }

        currentStepName = name
        stepStartTicks = mach_absolute_time()
        let signpostID = OSSignpostID(log: signpostLog)
        currentSignpostID = signpostID
        os_signpost(.begin, log: signpostLog, name: "Transcription Step", signpostID: signpostID, "%{public}s", name)
    }

    @discardableResult
    func end(_ metadata: String? = nil) -> Int {
        guard let name = currentStepName, stepStartTicks > 0 else { return 0 }

        let now = mach_absolute_time()
        let durationMs = ticksToMs(now - stepStartTicks)

        if let signpostID = currentSignpostID {
            if let metadata {
                os_signpost(.end, log: signpostLog, name: "Transcription Step", signpostID: signpostID, "%{public}s: %{public}s", name, metadata)
            } else {
                os_signpost(.end, log: signpostLog, name: "Transcription Step", signpostID: signpostID, "%{public}s", name)
            }
            currentSignpostID = nil
        }

        endStep(name, startTicks: stepStartTicks, durationMs: durationMs, metadata: metadata)
        currentStepName = nil
        stepStartTicks = 0
        return durationMs
    }

    func mark(_ name: String, metadata: String? = nil) {
        let startMs = ticksToMs(mach_absolute_time() - startTicks)
        steps.append(
            TranscriptionStep(
                name: name,
                startMs: startMs,
                durationMs: 0,
                metadata: metadata
            )
        )

        if let metadata {
            os_signpost(.event, log: signpostLog, name: "Transcription Mark", "%{public}s: %{public}s", name, metadata)
        } else {
            os_signpost(.event, log: signpostLog, name: "Transcription Mark", "%{public}s", name)
        }
    }

    func getSteps() -> [TranscriptionStep] {
        steps.sorted { $0.startMs < $1.startMs }
    }

    var elapsedMs: Int {
        ticksToMs(mach_absolute_time() - startTicks)
    }

    var elapsedSeconds: Double {
        Double(elapsedMs) / 1000.0
    }

    var summary: String {
        let traceID = externalRefId ?? jobId.uuidString.prefix(8).lowercased()
        let stepSummary = steps.map { "\($0.name)=\($0.durationMs)ms" }.joined(separator: ", ")
        return "[\(traceID)] \(elapsedMs)ms total: \(stepSummary)"
    }

    private func endStep(_ name: String, startTicks: UInt64, durationMs: Int, metadata: String? = nil) {
        let startMs = ticksToMs(startTicks - self.startTicks)
        steps.append(
            TranscriptionStep(
                name: name,
                startMs: startMs,
                durationMs: durationMs,
                metadata: metadata
            )
        )
    }
}

struct TranscriptionMetric: Identifiable {
    let id = UUID()
    let timestamp: Date
    let elapsedSeconds: Double
    let audioDurationSeconds: Double?
    let wordCount: Int
    let transcriptPreview: String?
    let steps: [TranscriptionStep]
    let modelId: String?
    let audioFilename: String?
    let audioSamples: Int?
    let externalRefId: String?
}

@MainActor
@Observable
final class EngineStatusManager {
    static let shared = EngineStatusManager()

    var logs: [EngineLogEntry] = []
    var isTranscribing = false
    var currentModel: String?
    var totalTranscriptions = 0
    var recentMetrics: [TranscriptionMetric] = []

    private let maxLogs = 500
    private let maxMetrics = 100

    private init() {}

    func log(_ level: EngineLogEntry.LogLevel, _ category: String, _ message: String) {
        logs.insert(
            EngineLogEntry(timestamp: Date(), level: level, category: category, message: message),
            at: 0
        )
        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }
    }

    func recordMetric(
        elapsed: Double,
        audioDuration: Double? = nil,
        wordCount: Int,
        transcript: String? = nil,
        trace: TranscriptionTrace?,
        modelId: String?,
        audioFilename: String?,
        audioSamples: Int?
    ) {
        recentMetrics.insert(
            TranscriptionMetric(
                timestamp: Date(),
                elapsedSeconds: elapsed,
                audioDurationSeconds: audioDuration,
                wordCount: wordCount,
                transcriptPreview: transcript.map { String($0.prefix(40)) },
                steps: trace?.getSteps() ?? [],
                modelId: modelId,
                audioFilename: audioFilename,
                audioSamples: audioSamples,
                externalRefId: trace?.externalRefId
            ),
            at: 0
        )
        if recentMetrics.count > maxMetrics {
            recentMetrics = Array(recentMetrics.prefix(maxMetrics))
        }
    }
}
