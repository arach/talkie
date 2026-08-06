//
//  PresetPickerView.swift
//  TalkieWatch
//
//  Capture surface — idle. An activity plate, one wide key, and one subordinate
//  AI route. The primary action reads as a control rather than a miniature watch
//  face.
//

import SwiftUI
import WatchKit

struct PresetPickerView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @Binding var selectedPreset: WatchPreset?
    @Binding var isRecording: Bool
    var onOpenAsks: () -> Void = {}

    var body: some View {
        // Measured off the device rather than off a container.
        //
        // This used to read the height out of a `GeometryReader`, which was the
        // right instrument while the face was the whole page. It is the wrong
        // one now: inside a scroll view the vertical proposal is unbounded, so
        // the reader reports the *content* height and the face solves its
        // budget against a number that includes the thing below the fold.
        //
        // The face ignores both safe areas, which makes its height the screen's
        // height by definition — 248pt on a 46mm, 197 on a 40mm, both exactly
        // `screenBounds`. Asking the device is not an approximation of what the
        // reader was measuring; it is the same number, from the source.
        let screenHeight = WKInterfaceDevice.current().screenBounds.height
        let metrics = CaptureFaceMetrics(availableHeight: screenHeight)

        ZStack {
            TalkieCaptureBackground()

            // The crown scrolls; the face does not move until it does.
            //
            // The stack below is pinned to exactly one screen, so the page
            // still opens finished — the whole argument for solving these
            // heights was that the key must not shift when an ask starts, and a
            // face that could drift under the crown at rest would give that
            // back. What is under the fold is genuinely extra.
            ScrollView {
                VStack(spacing: 0) {
                    face(metrics: metrics)
                        .frame(height: screenHeight)

                    CaptureUnderside { preset in
                        startCapture(preset: preset)
                    }
                }
            }
            // watchOS draws a crown indicator down the right edge, which is the
            // column the system clock already owns. One system overlay in that
            // column is a constraint; two is a pile.
            .scrollIndicators(.hidden)

            // Above the scroll, not behind it.
            ClockScrim()
        }
        // The face starts at the glass and ends at it.
        //
        // The top strip exists to keep content clear of the clock, and with the
        // navigation bar gone it was costing ~35pt to protect a corner this
        // face already leaves empty on purpose. The bottom one is sized for a
        // scrolling list and was holding back another ~50pt to make room for
        // three page dots, which need `indicatorClearance` and not a point more.
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    /// Everything above the fold. Unchanged by the crown — see the note at the
    /// scroll view.
    @ViewBuilder
    private func face(metrics: CaptureFaceMetrics) -> some View {
        VStack(spacing: 0) {
                    // The row watchOS's bar used to be. Outside the metrics
                    // because it is not negotiable — it is the same height on
                    // every watch, and the solver below divides what is left.
                    //
                    // It shares its band with watchOS's clock rather than
                    // sitting under it. Hiding the navigation bar does not hide
                    // the time — it promotes it to the large overlay — so the
                    // only way that trade pays for itself is if the face uses
                    // the band the clock is drawn in instead of starting below
                    // it. Gear left, wordmark centre, and the right third left
                    // deliberately empty because that is where the time lands.
                    CaptureHeaderRow()

                    Spacer()
                        .frame(height: CaptureFaceMetrics.headerGap)

                    // The sheet takes the top of the face and runs its roll off
                    // both edges — the bleed is applied inside it, because the
                    // grid is the only part that should leave the page and a
                    // negative padding here would take the type with it.
                    //
                    // Either way the slot is a fixed height. An ask starting or
                    // finishing must not shove the record key down the face —
                    // the same reason recording states swap into a fixed-size
                    // puck instead of resizing the button.
                    if metrics.showsSheet {
                        CaptureContactSheet(
                            onOpenAsks: onOpenAsks,
                            height: metrics.sheetHeight
                        )
                        .frame(height: metrics.sheetHeight)
                    } else {
                        // No room for a sheet on a 40mm. The status line it
                        // would have carried goes back to being a line, and the
                        // roll goes unsaid — it is the half of the sheet the
                        // face can most afford to lose.
                        AskStrip(height: metrics.stripHeight, onOpen: onOpenAsks)
                    }

                    Spacer()
                        .frame(height: metrics.sheetGap)

                    // While an ask is being answered, the AI conversation *is*
                    // the subject of this face — a record key sitting where the
                    // answer should be reads as "memo" no matter what the sheet
                    // above it says. The key swaps; the quick row picks up
                    // capture, and gives up its own ask route while it does.
                    //
                    // Time-driven for the same reason the sheet is: an ask the
                    // phone abandoned mid-flight has to give the key back, and
                    // nothing publishes when a phone simply goes quiet.
                    TimelineView(.periodic(from: .now, by: WatchMemo.silenceTolerance / 2)) { context in
                        let askFace = WatchAskFace.resolve(sessionManager, asOf: context.date)
                        let askTakesKey = askFace?.takesCaptureKey ?? false

                        VStack(spacing: 0) {
                            if let askFace, askTakesKey {
                                AskCaptureKey(
                                    state: askFace,
                                    keyHeight: metrics.keyHeight,
                                    onOpen: onOpenAsks
                                )
                            } else {
                                RecordButton(kind: .start, keyHeight: metrics.keyHeight) {
                                    startCapture(forceAI: false)
                                }
                            }

                            Spacer()
                                .frame(height: metrics.keyGap)

                            CaptureQuickRow(
                                leadingKind: askTakesKey ? .record : .ask,
                                height: metrics.quickRowHeight
                            ) {
                                startCapture(forceAI: !askTakesKey)
                            }
                        }
                        // Both raised objects on one margin. The key used to be
                        // pinned narrower than the row under it, which read as
                        // two unrelated controls that happened to be stacked.
                        .padding(.horizontal, CaptureFaceMetrics.bodyInset)
                    }

                    Spacer()
                        .frame(height: metrics.bottomClearance)
        }
        // No `maxHeight` any more: the caller pins this to one screen, and an
        // infinite maximum inside a scroll view resolves against an unbounded
        // proposal rather than against the pin.
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func startCapture(forceAI: Bool) {
        startCapture(preset: forceAI ? .ai : .go)
    }

    private func startCapture(preset: WatchPreset) {
        WKInterfaceDevice.current().play(.click)
        selectedPreset = preset
        isRecording = true
    }
}

// MARK: - Vertical budget

/// The capture face's vertical layout, solved against the space watchOS
/// actually hands this page.
///
/// At their comfortable sizes the sheet, key and quick row add up to more than
/// any watch has: the page gets 150pt on a 46mm and 123pt on a 40mm.
/// Pinning them meant the stack overflowed and spilled equally out of both ends
/// — which put the bottom row within a few points of the glass on a large
/// watch and cut it off entirely on a small one. Solving for the key instead
/// keeps the stack inside its bounds, so the inset watchOS already reserves
/// below the page dots becomes the face's bottom margin.
struct CaptureFaceMetrics {
    /// Set when the contact sheet can stay without starving the key. It is the
    /// first thing given up: the key is the reason the page exists, and a face
    /// with a beautiful history and a stunted button has its priorities
    /// backwards. On a 40mm the sheet goes — as the wordmark it replaced
    /// already did — and the thin ask strip becomes the top of the stack.
    let showsSheet: Bool
    /// The sheet's slot. Scales with the watch: the two type rows inside it are
    /// pinned, so every point of this the face can spare goes to the roll —
    /// which is also why the sheet solves its own grid rather than declaring a
    /// column count that would only be square at one height.
    let sheetHeight: CGFloat
    let stripHeight: CGFloat
    /// Sheet to key.
    let sheetGap: CGFloat
    let keyHeight: CGFloat
    /// Key to quick row.
    let keyGap: CGFloat
    let quickRowHeight: CGFloat

    /// Between the header and the sheet. Fixed, and taken off the top before
    /// anything is solved: the wordmark needs to read as a separate register
    /// from the live line, and a gap that shrinks under pressure is the first
    /// thing to collapse the two back into one block.
    static let headerGap: CGFloat = 5

    /// Kept clear of the page indicator watchOS draws under a paged `TabView`.
    ///
    /// The face ignores the bottom safe area as well as the top, because that
    /// inset is sized for a scrolling list and left roughly 50pt of black under
    /// the quick row — a quarter of the page held back to protect three dots.
    /// This is what those dots actually need, and they need less of it on a
    /// small watch, where they sit closer to the glass.
    let bottomClearance: CGFloat
    ///
    /// 19, down from 22. The dots need less than the quick row does: three
    /// points came off here so the row could sit lower and open the channel
    /// between itself and the key, which is the gap the eye actually reads.
    private static let regularClearance: CGFloat = 19
    private static let compactClearance: CGFloat = 13

    /// What the sheet asks for, bounded at both ends.
    ///
    /// The ceiling came *down* from 58, which is the opposite of what a taller
    /// key seemed to need — but the sheet is three rows of day cells and one
    /// line of type, and none of those grow. Handed 58pt it did not draw bigger
    /// days; it drew the same days in a taller box and called the leftover
    /// padding. Sized to what the sheet actually holds, the surplus lands in
    /// the gap below instead, which is where the reference puts it: the roll
    /// needs a field of black under it far more than it needs a bigger box.
    private static let sheetShare: CGFloat = 0.35
    /// Low enough for a 40mm to keep a roll at all. The sheet's floor used to sit
    /// above what the small watch could spare, so the whole region fell back to a
    /// status line — trading the subject of the page for a number the ticker was
    /// already saying. It draws fewer fortnights down here instead.
    private static let minimumSheetHeight: CGFloat = 40
    private static let maximumSheetHeight: CGFloat = 74

    /// Enough for a 9pt monospaced label and its status dot, and no more: the
    /// slot is reserved whether or not there is an ask to put in it.
    private static let stripHeight: CGFloat = 18
    /// The quick row's panel. Two cells of icon-over-label, sized so the row
    /// reads as the key's smaller sibling rather than as a toolbar.
    private static let quickRowHeight: CGFloat = 32
    /// Below this the key stops looking like a key and starts looking like a
    /// bar, so the sheet goes before the key crosses it.
    ///
    /// 44, not 50. On a 40mm the old floor was what forced the roll off the face
    /// — the budget cleared it by two points and the whole sheet went. A 44pt key
    /// on a 162pt-wide watch is proportionally the same object a 74pt key is on a
    /// 208pt one; it is tighter, which is what a smaller watch should look like.
    private static let minimumKeyHeight: CGFloat = 44
    /// 74pt is the mock's 150px. It was 64, and the face never reached even
    /// that — with watchOS's bar in place the solver had 60pt to split between
    /// the key and its gaps and handed the key 47. Taking the bar back is what
    /// makes this number reachable rather than aspirational.
    private static let maximumKeyHeight: CGFloat = 74
    /// How much of the page's width the key and the quick row both span.
    ///
    /// One number for both, because they were two: the key was pinned at 128pt
    /// while the row below it ran to the gutters, which read as a small button
    /// centred over a wide panel rather than as a key and its smaller sibling.
    /// Objects in the same family share a footprint; only their heights say
    /// which one is primary.
    static let bodyInset: CGFloat = 8
    /// The two gaps together. The key needs visible separation from the sheet
    /// above and the quick row below or the three stack into one slab.
    private static let minimumGaps: CGFloat = 11
    /// The narrowest the key-to-quick-row channel is allowed to get, whatever
    /// the share works out to. Always less than `minimumGaps`, so honouring it
    /// can never drive the gap above it negative.
    private static let minimumKeyGap: CGFloat = 6
    /// The key takes this much of what is left; the rest becomes the gaps. Held
    /// constant so the face keeps the same rhythm as it scales rather than
    /// growing a fat key on large watches and thin air on small ones.
    private static let keyShare: CGFloat = 0.78

    init(availableHeight: CGFloat) {
        // A 40mm hands this page 197pt where a 46mm hands it 248.
        let compact = availableHeight < 220
        bottomClearance = compact ? Self.compactClearance : Self.regularClearance

        // The header and its gap are spent before anything is negotiated.
        let page = availableHeight
            - CaptureHeaderRow.height
            - Self.headerGap
            - bottomClearance

        let sheet = min(
            Self.maximumSheetHeight,
            max(Self.minimumSheetHeight, page * Self.sheetShare)
        )
        sheetHeight = sheet

        // What the key and its two gaps would have to share if the sheet stayed.
        // The sheet is worth keeping only while the key still clears its floor
        // afterwards; below that the face falls back to the thin strip, which is
        // barely a third of the height.
        let roomWithSheet = page - Self.quickRowHeight - sheet
        showsSheet = roomWithSheet - Self.minimumGaps >= Self.minimumKeyHeight

        let room = showsSheet
            ? roomWithSheet
            : page - Self.quickRowHeight - Self.stripHeight
        keyHeight = min(
            Self.maximumKeyHeight,
            max(Self.minimumKeyHeight, room * Self.keyShare)
        )

        // Whatever the key did not take, split roughly two thirds above the key
        // and one third below. The big gap is not slack, it is the field the
        // roll sits in — take it away and the sheet becomes a band with a
        // button under it. The small one only has to say the quick row is
        // separate from the key, not equal to it.
        //
        // This was 42/58 (a wide channel between the two raised things and none
        // around the printed one), then 80/20, which overcorrected: 4pt below a
        // 71pt key reads as the row being stuck to it. A third is enough
        // separation to see without promoting the row to the key's equal.
        //
        // The floor is what makes that hold on a small watch. A third of a
        // 40mm's slack is 4pt, and 4pt between two raised panels is not a gap,
        // it is a seam. Below the floor the key gap stops scaling and the sheet
        // gap pays — the field above the key has points to spare and the
        // channel below it does not.
        let slack = max(Self.minimumGaps, room - keyHeight)
        keyGap = max(Self.minimumKeyGap, slack * 0.32)
        sheetGap = slack - keyGap

        stripHeight = Self.stripHeight
        quickRowHeight = Self.quickRowHeight
    }
}

// MARK: - Talkie capture face

/// A restrained, brand-first capture composition. The wordmark establishes
/// identity; one porcelain key carries the primary action; an optional route
/// stays visibly subordinate. No decorative telemetry appears at rest.
struct TalkieCaptureLayout<HeaderAccessory: View, Primary: View, Caption: View, Secondary: View>: View {
    @Environment(\.watchThemeName) private var themeName
    private let headerAccessory: HeaderAccessory
    private let primary: Primary
    private let caption: Caption
    private let secondary: Secondary

    init(
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder caption: () -> Caption,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.headerAccessory = headerAccessory()
        self.primary = primary()
        self.caption = caption()
        self.secondary = secondary()
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                let capture = themeName.captureStyle

                Text("talkie")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(capture.material.ink.opacity(0.90))
                    .position(x: width * 0.50, y: height * 0.12)

                headerAccessory
                    .frame(width: width * 0.72, height: 24)
                    .position(x: width * 0.50, y: height * 0.25)

                primary
                    .position(x: width * 0.50, y: height * 0.51)

                caption
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(capture.material.inkFaint)
                    .lineLimit(1)
                    .position(x: width * 0.50, y: height * 0.75)

                secondary
                    .position(x: width * 0.50, y: height * 0.86)
            }
        }
    }
}

/// A sober light-mineral or black-ceramic field with one directional light
/// source. It remains quiet enough for the key and system time to lead.
struct TalkieCaptureBackground: View {
    @Environment(\.watchThemeName) private var themeName

    var body: some View {
        let capture = themeName.captureStyle
        let material = capture.material
        ZStack {
            material.field

            LinearGradient(
                colors: [
                    material.fieldLift.opacity(0.72),
                    material.field.opacity(0.90),
                    material.fieldShade
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: UnitPoint(x: 0.30, y: 0.12),
                startRadius: 0,
                endRadius: 128
            )

            RadialGradient(
                colors: [capture.atmosphere, .clear],
                center: UnitPoint(x: 0.76, y: 0.70),
                startRadius: 0,
                endRadius: 150
            )

        }
        .ignoresSafeArea()
    }
}

/// The corner the system clock lands in, shaded so its numerals have something
/// to read against.
///
/// watchOS draws that clock itself, in white, at a size and position no API
/// reaches — which on a light finish is white on white. The colour is not
/// negotiable but the field under it is, so the face gives it a ground instead.
/// Light only: on black ceramic the numerals already have all the contrast they
/// need, and a second dark patch up there would just look like a smudge.
///
/// An overlay rather than part of the background, because the capture face
/// scrolls now. Pinned behind the content it was a ground for an empty corner;
/// the moment the crown moved, a white key slid under the clock and took the
/// contrast with it. The scrim belongs to the viewport, not to the page.
struct ClockScrim: View {
    @Environment(\.watchThemeName) private var themeName

    var body: some View {
        let material = themeName.captureStyle.material

        if material == .lightMineral {
            // Ink, not `fieldShade`. The shade token is one step down the same
            // near-white ramp — a legible difference between two panels and
            // nothing at all behind white numerals.
            RadialGradient(
                colors: [material.ink.opacity(0.52), .clear],
                // Centred on the numerals, not on the corner. The clock sits a
                // little below and inboard of the bezel, and a pool centred at
                // 0,0 had already fallen off by the time it got there.
                center: UnitPoint(x: 0.93, y: 0.11),
                startRadius: 12,
                endRadius: 76
            )
            .ignoresSafeArea()
            // It shades; it does not intercept. The gear sits under its edge.
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Shared scope chrome

/// Instrument header — a compact, truthful two-column readout. The timer and
/// phone link state sit below the system clock without repeating the product
/// wordmark or competing with watchOS toolbar chrome.
struct InstrumentHeader: View {
    let elapsed: TimeInterval
    let isLive: Bool

    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        let chrome = WatchTheme.current
        HStack(spacing: 6) {
            Text(formatElapsed(elapsed))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isLive ? chrome.panelInk : chrome.panelInkFaint)
                .frame(minWidth: 36, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(sessionManager.isReachable ? Color.green : chrome.panelInkFaint)
                    .frame(width: 5, height: 5)
                    .shadow(
                        color: sessionManager.isReachable ? Color.green.opacity(0.65) : .clear,
                        radius: 2
                    )

                Text(sessionManager.isReachable ? "LINK" : "WAIT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(chrome.panelInkFaint)
            }
            .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private func formatElapsed(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let secondsText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsText)"
    }
}

/// Recessed Watch instrument surface shared by capture and Codex. Its depth
/// comes from a restrained surface ladder and one border, not ornamental
/// brackets or simulated hardware texture.
struct WatchInstrumentPanel<Content: View>: View {
    var annotation: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let chrome = WatchTheme.current
        ZStack {
            RoundedRectangle(cornerRadius: chrome.chromeCorner + 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [chrome.panelAlt, chrome.panel],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.chromeCorner + 3, style: .continuous)
                        .stroke(chrome.panelEdge, lineWidth: chrome.hairlineWidth)
                )

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if let annotation {
                PanelAnnotation(text: annotation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Quiet panel label for contexts that need one; omitted on capture where the
/// ready state already names the action.
private struct PanelAnnotation: View {
    let text: String

    var body: some View {
        let chrome = WatchTheme.current
        Text(text.uppercased())
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(chrome.panelInkFaint.opacity(0.72))
            .padding(.leading, 10)
            .padding(.top, 7)
    }
}

enum ScopeTreatment {
    /// Smooth oscilloscope sine trace — calm at rest, blooms with energy.
    case line
    /// Scrolling vertical bars — mirrors the macOS LiveWaveformBars.
    case bars
}

/// Two-mode waveform. Default `.line` reads like a calm scope trace and
/// pairs well with the bigger slot; `.bars` is the macOS-style scrolling
/// bar visualizer kept available so we can A/B without losing it.
struct ScopeWaveform: View {
    let audioLevel: Float
    let isLive: Bool
    var treatment: ScopeTreatment = .line

    var body: some View {
        switch treatment {
        case .line:
            ScopeLineTrace(audioLevel: audioLevel, isLive: isLive)
        case .bars:
            ScopeBars(audioLevel: audioLevel, isLive: isLive)
        }
    }
}

/// Sine-modulated continuous trace. At rest holds a low-amplitude calm
/// line; while live the amplitude grows with audio level and the line
/// gets a soft glow underneath for the lit-chrome instrument feel.
struct ScopeLineTrace: View {
    let audioLevel: Float
    let isLive: Bool

    var body: some View {
        let chrome = WatchTheme.current
        TimelineView(.animation(minimumInterval: 0.040, paused: !isLive)) { timeline in
            Canvas { ctx, size in
                let centerY = size.height / 2
                let t = timeline.date.timeIntervalSinceReferenceDate
                let raw = max(0.05, CGFloat(audioLevel))
                let amplitude = centerY * (isLive ? (0.18 + raw * 0.78) : 0.18)

                // Faint scope ticks: short vertical marks at quarters.
                for col in 1..<4 {
                    var tick = Path()
                    let x = size.width * CGFloat(col) / 4
                    tick.move(to: CGPoint(x: x, y: centerY - 5))
                    tick.addLine(to: CGPoint(x: x, y: centerY + 5))
                    ctx.stroke(tick, with: .color(chrome.edgeSubtle), lineWidth: 0.4)
                }

                // The trace.
                var trace = Path()
                let samples = 96
                for i in 0..<samples {
                    let progress = CGFloat(i) / CGFloat(samples - 1)
                    let x = progress * size.width

                    let phase = (isLive ? t * 5 : t * 1.5) + Double(progress) * 7.5
                    let primary = sin(phase) * Double(amplitude)
                    let harmonic = sin(phase * 2.7) * Double(amplitude) * 0.30
                    let y = centerY + CGFloat(primary + harmonic)

                    if i == 0 {
                        trace.move(to: CGPoint(x: x, y: y))
                    } else {
                        trace.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                ctx.stroke(trace, with: .color(chrome.accent), lineWidth: 1.4)

                // Glow under the trace.
                ctx.addFilter(.blur(radius: 2.5))
                ctx.stroke(trace, with: .color(chrome.accent.opacity(0.32)), lineWidth: 2.2)
            }
        }
    }
}

/// Scrolling vertical bars — mirrors the macOS LiveWaveformBars. At rest
/// (`isLive == false`) we hold a quiet 0.15-level baseline; while live
/// the bars shift right-to-left and the rightmost takes the current
/// audio level, evoking a moving scope trace.
struct ScopeBars: View {
    let audioLevel: Float
    let isLive: Bool

    @State private var bars: [CGFloat] = Array(repeating: 0.15, count: 56)

    private let barWidth: CGFloat = 2
    private let gap: CGFloat = 2

    var body: some View {
        let chrome = WatchTheme.current
        GeometryReader { proxy in
            let count = max(20, Int(proxy.size.width / (barWidth + gap)))

            TimelineView(.animation(minimumInterval: 0.05, paused: !isLive)) { timeline in
                Canvas { ctx, size in
                    let totalWidth = CGFloat(count) * (barWidth + gap) - gap
                    let startX = (size.width - totalWidth) / 2
                    let maxHeight = size.height * 0.85
                    let centerY = size.height / 2

                    for i in 0..<count {
                        let x = startX + CGFloat(i) * (barWidth + gap)

                        let seed = Double(i) * 1.618
                        let variation: CGFloat = 0.65 + CGFloat(sin(seed * 3)) * 0.35
                        let level = bars[i % bars.count] * variation
                        let h = max(2, level * maxHeight)
                        let opacity = isLive ? (0.45 + Double(level) * 0.55) : 0.32

                        let rect = CGRect(
                            x: x,
                            y: centerY - h / 2,
                            width: barWidth,
                            height: h
                        )
                        ctx.fill(
                            RoundedRectangle(cornerRadius: 1).path(in: rect),
                            with: .color(chrome.accent.opacity(opacity))
                        )
                    }
                }
                .onChange(of: timeline.date) { _, _ in
                    advance(count: count)
                }
            }
        }
        .onAppear {
            bars = Array(repeating: isLive ? 0.20 : 0.15, count: bars.count)
        }
    }

    private func advance(count: Int) {
        let raw = CGFloat(audioLevel)
        let target: CGFloat = isLive ? max(0.18, pow(raw, 0.5)) : 0.15

        var next = bars
        let effective = min(count, bars.count)
        for i in 0..<(effective - 1) {
            next[i] = next[i + 1]
        }
        if effective > 0 {
            next[effective - 1] = target
        }
        bars = next
    }
}

/// Calm, deterministic instrument background. The low-contrast cobalt lift
/// provides hierarchy without procedural grain or frame-to-frame noise.
struct WatchInstrumentBackground: View {
    var body: some View {
        let chrome = WatchTheme.current
        ZStack {
            chrome.panel

            LinearGradient(
                colors: [chrome.panelAlt.opacity(0.70), chrome.panel.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [chrome.accent.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 150
            )
        }
        .ignoresSafeArea()
    }
}

/// Primary capture action. The idle key carries Talkie's trace and an explicit
/// recording legend; semantic red appears only where recording is meant.
struct RecordButton: View {
    enum Kind { case start, stop }
    let kind: Kind
    var audioLevel: Float = 0
    /// The capture face solves this against the watch it is on; the recording
    /// screen, which has the display to itself, keeps the full size.
    var keyHeight: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch kind {
            case .start:
                TalkieCaptureKey(keyHeight: keyHeight)
            case .stop:
                TalkieStopKey(audioLevel: audioLevel)
            }
        }
        .buttonStyle(TalkieRecordButtonStyle())
        .accessibilityLabel(kind == .start ? "Start recording" : "Stop and send")
    }
}

struct TalkieRecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A wide light-mineral or black-ceramic key. Its horizontal geometry,
/// elevated edge, and press response keep it from reading as a miniature
/// device nested inside the Watch.
///
/// The chassis is shared rather than copied because more than one thing can
/// hold the primary slot — recording at rest, an ask in flight, an answer
/// waiting to be played. Swapping only the face means the key's footprint,
/// bevel, and hairline never shift underneath the wearer's thumb.
struct TalkieKeyChassis<Content: View>: View {
    @Environment(\.watchThemeName) private var themeName
    /// Overrides the theme's hairline when the key's job is not the usual one.
    /// `nil` keeps the resting accent.
    var accent: Color?
    /// Nil takes the full width offered, which on the capture face means the
    /// same span as the quick row beneath it — where it was 128pt, a fixed
    /// number that made the primary action look like a small button centred over
    /// a wide panel. A key is the biggest thing on the face; it should not be
    /// the narrowest.
    var width: CGFloat?
    /// Set by the capture face, which has to fit the key between the sheet and
    /// the quick row inside whatever height the watch gives it.
    var height: CGFloat = 64
    @ViewBuilder var content: () -> Content

    init(
        accent: Color? = nil,
        width: CGFloat? = nil,
        height: CGFloat = 64,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accent = accent
        self.width = width
        self.height = height
        self.content = content
    }

    private let cornerRadius: CGFloat = 18
    /// Gap between the bevel and the accent hairline. Also subtracted from the
    /// inner radius so the two rings stay concentric instead of the inner one
    /// bowing away from the corners.
    private let keyAccentInset: CGFloat = 1.5

    var body: some View {
        let capture = themeName.captureStyle
        let material = capture.material
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            material.keyTop,
                            material.keyMiddle,
                            material.keyBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: material.shadow, radius: 7, y: 5)
                // The key's edge. Drawn inside the fill so the silhouette stays
                // exactly `cornerRadius` — a straddling stroke would round off
                // half a point wider than the shadow it sits in.
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(material.keyEdgeRing, lineWidth: WatchEdgeWeight.bevel)
                }
                // A theme hairline just inside the bevel, concentric with it.
                // This is the one place the key carries the signal color at
                // rest, and it is what makes the key and the AI pill read as
                // two members of the same set rather than two shapes.
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius - keyAccentInset, style: .continuous)
                        .strokeBorder(accent ?? capture.keyAccentEdge, lineWidth: WatchEdgeWeight.hairline)
                        .padding(keyAccentInset)
                }

            content()
        }
        .frame(maxWidth: width ?? .infinity)
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The resting face: the Talkie signal over a record legend.
private struct TalkieCaptureKey: View {
    @Environment(\.watchThemeName) private var themeName
    var keyHeight: CGFloat = 64

    var body: some View {
        let capture = themeName.captureStyle
        TalkieKeyChassis(height: keyHeight) {
            VStack(spacing: 3) {
                TalkieTraceReveal(color: capture.trace)
                    .frame(width: 86, height: 22)

                // `TALK`, not `REC`. The old legend was a mic glyph in semantic
                // red beside a three-letter state — the only hue on this face
                // belonging to neither the material nor the trace, and a word
                // naming what the hardware is about to do rather than what the
                // wearer is about to do. Red is for the key that stops a running
                // recording, where it means something.
                Text("TALK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(capture.material.keyInk.opacity(0.88))

                // Where it goes. The face's one destination, said once, in the
                // faintest ink on the key — a key that says only what it is
                // leaves the wearer to guess where the words end up.
                Text("→ INBOX")
                    .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(capture.material.keyInk.opacity(0.42))
            }
        }
    }
}

/// One deliberate Talkie signal: quiet lead-in, peak, trough, recovery, rest.
/// The asymmetry keeps it from reading as a generic waveform or equalizer.
private struct TalkieSignalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let middle = rect.midY
        let height = rect.height

        path.move(to: CGPoint(x: rect.minX, y: middle))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.24, y: middle))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.42, y: middle - height * 0.34),
            control1: CGPoint(x: rect.minX + rect.width * 0.33, y: middle),
            control2: CGPoint(x: rect.minX + rect.width * 0.35, y: middle - height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.57, y: middle + height * 0.28),
            control1: CGPoint(x: rect.minX + rect.width * 0.47, y: middle - height * 0.34),
            control2: CGPoint(x: rect.minX + rect.width * 0.51, y: middle + height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.70, y: middle - height * 0.13),
            control1: CGPoint(x: rect.minX + rect.width * 0.62, y: middle + height * 0.28),
            control2: CGPoint(x: rect.minX + rect.width * 0.65, y: middle - height * 0.13)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.80, y: middle),
            control1: CGPoint(x: rect.minX + rect.width * 0.74, y: middle - height * 0.13),
            control2: CGPoint(x: rect.minX + rect.width * 0.76, y: middle)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: middle))
        return path
    }
}

/// One-shot trace reveal with a brief moving highlight. Reduce Motion keeps
/// the same final state and substitutes a short opacity transition.
private struct TalkieTraceReveal: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAnimated = false
    @State private var revealProgress: CGFloat = 0
    @State private var highlightProgress: CGFloat = 0
    @State private var highlightOpacity = 0.0
    @State private var traceOpacity = 0.0

    var body: some View {
        ZStack {
            TalkieSignalLine()
                .trim(from: 0, to: revealProgress)
                .stroke(
                    color.opacity(0.82),
                    style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
                )
                .opacity(traceOpacity)

            TalkieSignalLine()
                .trim(
                    from: max(0, highlightProgress - 0.18),
                    to: min(1, highlightProgress)
                )
                .stroke(
                    Color.white.opacity(0.84),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: color.opacity(0.46), radius: 2)
                .opacity(highlightOpacity)
        }
        .onAppear(perform: animateOnce)
    }

    private func animateOnce() {
        guard !hasAnimated else { return }
        hasAnimated = true

        if reduceMotion {
            revealProgress = 1
            withAnimation(.easeOut(duration: 0.18)) {
                traceOpacity = 1
            }
            return
        }

        traceOpacity = 1
        withAnimation(.easeOut(duration: 0.72).delay(0.08)) {
            revealProgress = 1
        }
        withAnimation(.easeIn(duration: 0.12).delay(0.18)) {
            highlightOpacity = 0.72
        }
        withAnimation(.easeInOut(duration: 0.68).delay(0.18)) {
            highlightProgress = 1
        }
        withAnimation(.easeOut(duration: 0.20).delay(0.78)) {
            highlightOpacity = 0
        }
    }
}

/// The live stop action remains unmistakably semantic and intentionally does
/// not inherit the idle key's decorative material or load animation.
private struct TalkieStopKey: View {
    let audioLevel: Float

    var body: some View {
        let level = min(max(audioLevel, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.24 + Double(level) * 0.48), lineWidth: 1.5)
                .frame(width: 67, height: 67)
                .scaleEffect(1 + CGFloat(level) * 0.06)

            Circle()
                .fill(Color.red)
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.40), radius: 7, y: 5)

            Image(systemName: "stop.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(watchHex: "F7FAFF"))
        }
        .frame(width: 70, height: 70)
        .contentShape(Circle())
    }
}

#Preview {
    PresetPickerView(
        selectedPreset: .constant(nil),
        isRecording: .constant(false)
    )
    .environmentObject(WatchSessionManager.shared)
}
