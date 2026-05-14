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

private let perfLogger = Logger(subsystem: "to.talkie.app.performance", category: "FPS")

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
    private var bodyAccumulator: [String: Int] = [:]
    private var lastTickTime: CFTimeInterval?
    private var minFrameInterval: Double = .infinity
    private var maxFrameInterval: Double = 0

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
    nonisolated func recordBodyAccess(_ name: String) {
        Task { @MainActor in
            self.bodyAccumulator[name, default: 0] += 1
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
        var snapshot: [String: Int] = [:]
        for (name, count) in bodyAccumulator {
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
        bodyAccumulator.removeAll(keepingCapacity: true)
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
#endif
