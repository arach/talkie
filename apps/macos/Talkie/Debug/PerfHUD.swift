//
//  PerfHUD.swift
//  Talkie macOS
//
//  Tiny on-screen perf HUD. Two readouts:
//    • FPS — frames processed on the main thread per second. Derived
//      from a CVDisplayLink callback that hops back to MainActor; if
//      the main thread is blocked, the callbacks queue up and the
//      measured rate falls below the display's refresh rate. Doubles
//      as a main-thread responsiveness gauge.
//    • Body invalidations / sec — increment a counter from any SwiftUI
//      body to attribute perf cost. Use `PerfHUD.tick("AppNavigation")`
//      at the top of a hot body to track how often it re-evaluates.
//
//  Mounted as a debug overlay (DesignModeManager.isEnabled gated).
//  Costs:
//    • CVDisplayLink fires every refresh (~60–120 Hz) but its callback
//      is microscopic — bumps a counter and posts to main once per
//      0.5s window.
//    • HUD view re-renders only when @Published values change, which
//      is at most ~2x/sec.
//

#if DEBUG
import Foundation
import SwiftUI
import QuartzCore
import os
import os.signpost

private let perfLogger = Logger(subsystem: "to.talkie.app.performance", category: "FPS")
private let navigationSignpostLog = OSLog(subsystem: "to.talkie.app.performance", category: "Navigation")

@MainActor
final class FrameRateMonitor: ObservableObject {
    static let shared = FrameRateMonitor()

    @Published var fps: Double = 0
    /// Worst frame interval observed in the last window, in milliseconds.
    /// A 60Hz display has ~16.7ms ideal; values >33ms mean a frame was
    /// dropped. Surfaces hitches that the average FPS smooths over.
    @Published var worstFrameMs: Double = 0
    /// Number of AppNavigation-style body invalidations counted in the
    /// last sampling window. Useful for catching runaway re-renders.
    @Published var bodyInvalidationsPerSec: [String: Int] = [:]

    /// Length of each sampling/logging window. 250ms = 4 Hz log cadence,
    /// fine-grained enough to see scroll-induced FPS drops while still
    /// averaging out single-frame noise.
    private static let windowSeconds: Double = 0.25

    private var displayLink: CVDisplayLink?
    private var frameCount: Int = 0
    private var windowStartTime: CFTimeInterval = CACurrentMediaTime()
    /// Body-access counts, accumulated lock-protected so `recordBodyAccess`
    /// can be called nonisolated, synchronously, from any thread —
    /// including from inside `body` re-evals — without a `Task { @MainActor }`
    /// hop per call. The old approach allocated and scheduled an unstructured
    /// task on every body access; AppNavigation alone hits ~60 calls/sec at
    /// baseline, and typing into the editor pushes that into the hundreds.
    /// Each Task allocation isn't free, and the MainActor queue gets so
    /// backed up that the main thread starves on actual UI work (typing).
    /// An os_unfair_lock-backed dictionary makes the increment ~nanoseconds.
    private let bodyAccumulator = OSAllocatedUnfairLock<[String: Int]>(initialState: [:])
    private var lastTickTime: CFTimeInterval?
    private var minFrameInterval: Double = .infinity
    private var maxFrameInterval: Double = 0

    // ── Navigation phase timing ──────────────────────────────────
    private struct NavigationTrace {
        let id: Int
        let from: String
        let to: String
        let source: String
        let startTime: CFTimeInterval
        let shellSignpostID: OSSignpostID
        let dataSignpostID: OSSignpostID
        var shellEnded = false
        var dataEnded = false
    }

    private struct RecordingsObservationTrace {
        let id: Int
        let filter: String
        let sort: String
        let limit: Int
        let startTime: CFTimeInterval
        let signpostID: OSSignpostID
    }

    private var nextNavigationTraceID = 0
    private var activeNavigationTrace: NavigationTrace?
    private var nextRecordingsObservationID = 0
    private var activeRecordingsObservation: RecordingsObservationTrace?

    // ── Scene tags ────────────────────────────────────────────────
    /// Currently active section in the host. Updated by AppNavigation
    /// on selection change. Tagged onto every FPS log line so we can
    /// correlate freezes with where the user was.
    private(set) var currentSection: String = "?"
    /// Sidebar mode: "compact" or "expanded". Tagged onto FPS lines so
    /// we can see if a hitch coincided with a sidebar transition.
    private(set) var sidebarMode: String = "?"
    /// "drag" while the edge handle is being dragged, otherwise empty.
    /// Lets us attribute hitches to the resize gesture vs. other causes.
    private(set) var interaction: String = ""

    func setSection(_ name: String) {
        let from = currentSection
        currentSection = name
        if from != name {
            perfLogger.info("event=section_changed from=\(from, privacy: .public) to=\(name, privacy: .public)")
        }
    }

    func setSidebarMode(_ mode: String) {
        let from = sidebarMode
        sidebarMode = mode
        if from != mode && from != "?" {
            perfLogger.info("event=sidebar_toggle from=\(from, privacy: .public) to=\(mode, privacy: .public)")
        }
    }

    func setInteraction(_ kind: String) {
        let from = interaction
        interaction = kind
        if from != kind {
            if kind.isEmpty {
                perfLogger.info("event=interaction_end from=\(from, privacy: .public)")
            } else {
                perfLogger.info("event=interaction_begin kind=\(kind, privacy: .public)")
            }
        }
    }

    /// Log a one-off named event (clicks, key shortcuts, hover targets).
    /// Goes into the same stream so the FPS timeline stays correlated.
    func logEvent(_ name: String, _ detail: String = "") {
        if detail.isEmpty {
            perfLogger.info("event=\(name, privacy: .public)")
        } else {
            perfLogger.info("event=\(name, privacy: .public) \(detail, privacy: .public)")
        }
    }

    /// Start a navigation phase trace. The trace owns two Instruments
    /// intervals:
    ///   • Navigation Shell: intent/click → destination shell visible
    ///   • Navigation Data: intent/click → destination data visible
    ///
    /// The FPS stream also receives matching key=value events so
    /// `talkie-dev logs` can be scrubbed alongside frame samples.
    func beginNavigation(to target: String, source: String) {
        let now = CACurrentMediaTime()
        let normalizedTarget = normalizedTraceValue(target)

        if let activeNavigationTrace,
           normalizedTraceValue(activeNavigationTrace.to) == normalizedTarget,
           now - activeNavigationTrace.startTime < 2 {
            perfLogger.info("event=nav_intent_coalesced id=\(activeNavigationTrace.id, privacy: .public) source=\(source, privacy: .public) to=\(target, privacy: .public)")
            return
        }

        finishActiveNavigation(reason: "superseded")

        nextNavigationTraceID += 1
        let id = nextNavigationTraceID
        let from = currentSection
        let shellID = OSSignpostID(log: navigationSignpostLog)
        let dataID = OSSignpostID(log: navigationSignpostLog)

        activeNavigationTrace = NavigationTrace(
            id: id,
            from: from,
            to: target,
            source: source,
            startTime: now,
            shellSignpostID: shellID,
            dataSignpostID: dataID
        )

        os_signpost(.begin, log: navigationSignpostLog, name: "Navigation Shell", signpostID: shellID,
                    "id=%d source=%{public}s from=%{public}s to=%{public}s", id, source, from, target)
        os_signpost(.begin, log: navigationSignpostLog, name: "Navigation Data", signpostID: dataID,
                    "id=%d source=%{public}s from=%{public}s to=%{public}s", id, source, from, target)

        perfLogger.info("event=nav_click id=\(id, privacy: .public) source=\(source, privacy: .public) from=\(from, privacy: .public) to=\(target, privacy: .public)")
    }

    func markNavigationShellVisible(section: String, source: String) {
        guard var trace = activeNavigationTrace,
              !trace.shellEnded,
              traceMatches(trace.to, section)
        else { return }

        let deltaMs = milliseconds(since: trace.startTime)
        trace.shellEnded = true
        activeNavigationTrace = trace

        os_signpost(.end, log: navigationSignpostLog, name: "Navigation Shell", signpostID: trace.shellSignpostID,
                    "id=%d source=%{public}s section=%{public}s deltaMs=%d", trace.id, source, section, deltaMs)
        perfLogger.info("event=nav_shell_visible id=\(trace.id, privacy: .public) source=\(source, privacy: .public) section=\(section, privacy: .public) deltaMs=\(deltaMs, privacy: .public)")
    }

    func markNavigationDataVisible(section: String, source: String, detail: String = "") {
        guard var trace = activeNavigationTrace,
              !trace.dataEnded,
              traceMatches(trace.to, section)
        else { return }

        let deltaMs = milliseconds(since: trace.startTime)
        trace.dataEnded = true
        activeNavigationTrace = trace

        os_signpost(.end, log: navigationSignpostLog, name: "Navigation Data", signpostID: trace.dataSignpostID,
                    "id=%d source=%{public}s section=%{public}s deltaMs=%d detail=%{public}s", trace.id, source, section, deltaMs, detail)

        if detail.isEmpty {
            perfLogger.info("event=nav_data_visible id=\(trace.id, privacy: .public) source=\(source, privacy: .public) section=\(section, privacy: .public) deltaMs=\(deltaMs, privacy: .public)")
        } else {
            perfLogger.info("event=nav_data_visible id=\(trace.id, privacy: .public) source=\(source, privacy: .public) section=\(section, privacy: .public) deltaMs=\(deltaMs, privacy: .public) \(detail, privacy: .public)")
        }

        activeNavigationTrace = nil
    }

    func beginRecordingsObservation(filter: String, sort: String, limit: Int) {
        finishActiveRecordingsObservation(reason: "superseded")

        nextRecordingsObservationID += 1
        let id = nextRecordingsObservationID
        let signpostID = OSSignpostID(log: navigationSignpostLog)
        activeRecordingsObservation = RecordingsObservationTrace(
            id: id,
            filter: filter,
            sort: sort,
            limit: limit,
            startTime: CACurrentMediaTime(),
            signpostID: signpostID
        )

        os_signpost(.begin, log: navigationSignpostLog, name: "Recordings Observation", signpostID: signpostID,
                    "id=%d filter=%{public}s sort=%{public}s limit=%d", id, filter, sort, limit)
        perfLogger.info("event=recordings_observation_start id=\(id, privacy: .public) filter=\(filter, privacy: .public) sort=\(sort, privacy: .public) limit=\(limit, privacy: .public)")
    }

    func markRecordingsObservation(stage: String) {
        guard let trace = activeRecordingsObservation else { return }
        let deltaMs = milliseconds(since: trace.startTime)

        os_signpost(.event, log: navigationSignpostLog, name: "Recordings Observation Mark", signpostID: trace.signpostID,
                    "id=%d stage=%{public}s deltaMs=%d", trace.id, stage, deltaMs)
        perfLogger.info("event=recordings_observation_stage id=\(trace.id, privacy: .public) stage=\(stage, privacy: .public) deltaMs=\(deltaMs, privacy: .public)")
    }

    func finishRecordingsObservation(displayed: Int, total: Int) {
        guard let trace = activeRecordingsObservation else { return }
        let deltaMs = milliseconds(since: trace.startTime)

        os_signpost(.end, log: navigationSignpostLog, name: "Recordings Observation", signpostID: trace.signpostID,
                    "id=%d status=ready displayed=%d total=%d deltaMs=%d", trace.id, displayed, total, deltaMs)
        perfLogger.info("event=recordings_observation_ready id=\(trace.id, privacy: .public) displayed=\(displayed, privacy: .public) total=\(total, privacy: .public) deltaMs=\(deltaMs, privacy: .public)")

        activeRecordingsObservation = nil
    }

    func failRecordingsObservation(_ message: String) {
        guard let trace = activeRecordingsObservation else { return }
        let deltaMs = milliseconds(since: trace.startTime)

        os_signpost(.end, log: navigationSignpostLog, name: "Recordings Observation", signpostID: trace.signpostID,
                    "id=%d status=error deltaMs=%d error=%{public}s", trace.id, deltaMs, message)
        perfLogger.info("event=recordings_observation_error id=\(trace.id, privacy: .public) deltaMs=\(deltaMs, privacy: .public) error=\(message, privacy: .public)")

        activeRecordingsObservation = nil
    }

    private func finishActiveNavigation(reason: String) {
        guard let trace = activeNavigationTrace else { return }
        let deltaMs = milliseconds(since: trace.startTime)

        if !trace.shellEnded {
            os_signpost(.end, log: navigationSignpostLog, name: "Navigation Shell", signpostID: trace.shellSignpostID,
                        "id=%d status=%{public}s deltaMs=%d", trace.id, reason, deltaMs)
        }
        if !trace.dataEnded {
            os_signpost(.end, log: navigationSignpostLog, name: "Navigation Data", signpostID: trace.dataSignpostID,
                        "id=%d status=%{public}s deltaMs=%d", trace.id, reason, deltaMs)
        }

        perfLogger.info("event=nav_end id=\(trace.id, privacy: .public) status=\(reason, privacy: .public) deltaMs=\(deltaMs, privacy: .public)")
        activeNavigationTrace = nil
    }

    private func finishActiveRecordingsObservation(reason: String) {
        guard let trace = activeRecordingsObservation else { return }
        let deltaMs = milliseconds(since: trace.startTime)

        os_signpost(.end, log: navigationSignpostLog, name: "Recordings Observation", signpostID: trace.signpostID,
                    "id=%d status=%{public}s deltaMs=%d", trace.id, reason, deltaMs)
        perfLogger.info("event=recordings_observation_end id=\(trace.id, privacy: .public) status=\(reason, privacy: .public) deltaMs=\(deltaMs, privacy: .public)")

        activeRecordingsObservation = nil
    }

    private func traceMatches(_ lhs: String, _ rhs: String) -> Bool {
        normalizedTraceValue(lhs) == normalizedTraceValue(rhs)
    }

    private func normalizedTraceValue(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func milliseconds(since startTime: CFTimeInterval) -> Int {
        Int(((CACurrentMediaTime() - startTime) * 1000).rounded())
    }

    private init() {}

    func start() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        let createStatus = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard createStatus == kCVReturnSuccess, let link = link else { return }
        displayLink = link

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, ptr in
            guard let ptr = ptr else { return kCVReturnError }
            let monitor = Unmanaged<FrameRateMonitor>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.processTick()
            }
            return kCVReturnSuccess
        }, opaqueSelf)

        CVDisplayLinkStart(link)
    }

    func stop() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
    }

    /// Called by a view's body to attribute a body invalidation. The
    /// counter rolls up into `bodyInvalidationsPerSec` at the end of
    /// each sampling window.
    ///
    /// Synchronous + lock-protected — must be cheap because hot views
    /// (AppNavigation, ScopeDraftsScreen) can call this hundreds of
    /// times per second. No Task allocation, no actor hop.
    nonisolated func recordBodyAccess(_ name: String) {
        bodyAccumulator.withLock { dict in
            dict[name, default: 0] += 1
        }
    }

    private func processTick() {
        frameCount += 1
        let now = CACurrentMediaTime()

        // Per-frame interval tracking — captures stutters that average
        // FPS smooths away. A single 80ms frame in a 250ms window still
        // averages ~50 FPS, but maxFrame=80ms screams "hitch".
        if let last = lastTickTime {
            let interval = (now - last) * 1000.0
            if interval < minFrameInterval { minFrameInterval = interval }
            if interval > maxFrameInterval { maxFrameInterval = interval }
        }
        lastTickTime = now

        let elapsed = now - windowStartTime
        guard elapsed >= Self.windowSeconds else { return }

        let measuredFPS = Double(frameCount) / elapsed
        fps = measuredFPS
        worstFrameMs = maxFrameInterval

        // Snapshot + rescale body invalidations to per-second rate.
        // Drains the lock-protected accumulator in one short critical
        // section — keeping the lock contention with `recordBodyAccess`
        // (called from any thread) negligible.
        let raw = bodyAccumulator.withLock { dict -> [String: Int] in
            let copy = dict
            dict.removeAll(keepingCapacity: true)
            return copy
        }
        var snapshot: [String: Int] = [:]
        for (name, count) in raw {
            snapshot[name] = Int(Double(count) / elapsed)
        }
        bodyInvalidationsPerSec = snapshot

        // Emit a structured log line every window so we can scrub the
        // FPS time series via `talkie-dev logs talkie` after a session.
        // Format chosen for easy grep + awk: key=value pairs.
        let hottest = snapshot.max(by: { $0.value < $1.value })
        let hottestField: String
        if let h = hottest, h.value > 0 {
            hottestField = " hottest=\(h.key):\(h.value)/s"
        } else {
            hottestField = ""
        }
        let fpsStr = String(format: "%.1f", measuredFPS)
        let minMsStr = String(format: "%.1f", minFrameInterval)
        let maxMsStr = String(format: "%.1f", maxFrameInterval)
        let interactionField = interaction.isEmpty ? "" : " interaction=\(interaction)"
        // `privacy: .public` so the values aren't redacted by the
        // unified log (default for string interpolations is .private,
        // which renders as `<private>` in `log show` output).
        perfLogger.info("fps=\(fpsStr, privacy: .public) minMs=\(minMsStr, privacy: .public) maxMs=\(maxMsStr, privacy: .public) frames=\(self.frameCount, privacy: .public) section=\(self.currentSection, privacy: .public) sidebar=\(self.sidebarMode, privacy: .public)\(interactionField, privacy: .public)\(hottestField, privacy: .public)")

        frameCount = 0
        windowStartTime = now
        minFrameInterval = .infinity
        maxFrameInterval = 0
    }
}

/// On-screen pill that shows FPS + (optionally) the top body
/// invalidation source. Mount via `.overlay(alignment: .bottomLeading)`
/// in DEBUG when Design Mode is on.
struct PerfHUD: View {
    @ObservedObject private var monitor = FrameRateMonitor.shared

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(fpsColor)
                .frame(width: 6, height: 6)
            Text(String(format: "%.0f FPS", monitor.fps))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)

            // Surface worst-frame whenever a frame exceeded ~33ms
            // (= a dropped frame on 60Hz). Stays hidden during smooth
            // periods so the HUD doesn't clutter.
            if monitor.worstFrameMs > 33 {
                Text(String(format: "·%.0fms", monitor.worstFrameMs))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(monitor.worstFrameMs > 66 ? Color.red.opacity(0.95) : Color.orange.opacity(0.95))
            }

            if let hottest = hottestBody {
                Text("·")
                    .foregroundColor(.white.opacity(0.45))
                Text("\(hottest.0) \(hottest.1)/s")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.72))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .allowsHitTesting(false)
    }

    private var hottestBody: (String, Int)? {
        guard let top = monitor.bodyInvalidationsPerSec.max(by: { $0.value < $1.value }) else {
            return nil
        }
        return (top.key, top.value)
    }

    private var fpsColor: Color {
        if monitor.fps >= 55 { return .green }
        if monitor.fps >= 30 { return .yellow }
        return .red
    }
}

/// Compact FPS readout sized to live INLINE in the status bar (alongside
/// PID / git branch), rather than as a floating capsule that overlaps
/// content. Same CVDisplayLink source; just stripped to status-bar
/// typography. Mounts/starts the monitor on appear.
struct PerfStatusReadout: View {
    @ObservedObject private var monitor = FrameRateMonitor.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(fpsColor)
                .frame(width: 5, height: 5)
            Text(String(format: "%.0f FPS", monitor.fps))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            if monitor.worstFrameMs > 33 {
                Text(String(format: "·%.0fms", monitor.worstFrameMs))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(monitor.worstFrameMs > 66 ? Color.red.opacity(0.9) : Color.orange.opacity(0.9))
            }
        }
        .help("Frame rate (dev) · CVDisplayLink-driven main-thread responsiveness gauge")
        .onAppear { FrameRateMonitor.shared.start() }
    }

    private var fpsColor: Color {
        if monitor.fps >= 55 { return .green }
        if monitor.fps >= 30 { return .yellow }
        return .red
    }
}
#endif
