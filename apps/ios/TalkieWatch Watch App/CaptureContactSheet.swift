//
//  CaptureContactSheet.swift
//  TalkieWatch
//
//  The capture face's top region, drawn as a contact sheet.
//
//  It was a plate before this: a rounded, bordered, scanlined screen let into
//  the chassis. The border was the problem. A panel with four visible sides is
//  an object sitting *on* the face, and at the width of a watch there is no
//  distance at which a full-bleed rounded rectangle stops reading as a card —
//  which put a card where the top of the page should have been.
//
//  A contact sheet has no frame. The roll runs off both edges and fades out
//  rather than stopping, so the region reads as the face's own material with
//  the history printed into it. Nothing is set into anything. The only framed,
//  raised, touchable things left on the page are the capture key and the quick
//  row beneath it — which means the boundary between "what this is" and "what
//  you can press" now falls exactly where the relief starts, instead of being
//  spelled out four times in rounded corners.
//
//  One cell per day, oldest at the top left, today at the bottom right and
//  drawn as an outline: the frame currently being exposed. The grid solves its
//  own column count so the cells come out square on whatever height the face
//  can spare, so a taller watch gets a squarer sheet rather than a stretched
//  one.
//
//  On a 40mm there is no room for it and the face falls back to the thin
//  `AskStrip`, which is why that view still exists.
//

import SwiftUI
import WatchKit

// MARK: - Sheet

struct CaptureContactSheet: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @Environment(\.watchThemeName) private var themeName
    /// Always-on drops the gloss, the caret and the halos. The sheet is
    /// evidence, not a notification — it has nothing urgent enough to justify
    /// burning pixels on a wrist that is down.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// Opens the Asks page. Live only while the ticker is showing an ask — a
    /// tap target that lands somewhere unrelated is worse than a label that
    /// stays put.
    let onOpenAsks: () -> Void

    /// The slot the face gave this sheet. Passed in rather than measured because
    /// the legend has to name the span the roll is *drawing*, and on a 40mm that
    /// is fewer fortnights than the phone sent — a number only knowable once the
    /// box is known.
    let height: CGFloat

    /// How wide the roll reads when the phone has never been heard from.
    /// Matches the phone's own (`WatchSessionManager.watchActivityDays`), which
    /// the two targets cannot share a definition of — the Watch folder belongs
    /// to a different target — so the relationship is held by this comment.
    private static let fallbackWindow = 70

    /// The live line. Pinned: the roll takes what is left, so a taller watch
    /// gets a taller sheet rather than a lonelier headline. Both rows came down
    /// with their type — the sheet's job is to hold days, and every point spent
    /// on a label is a point the cells do not get.
    fileprivate static let tickerHeight: CGFloat = 10
    /// Ticker to roll. Wide enough that the sheet reads as a line *and* a field
    /// rather than as one block of small marks with a caption stuck to its top.
    ///
    /// These three came down together to pay for the header's corner inset. The
    /// choice was four points of label padding or a whole fortnight of history,
    /// and the roll is what the region is for — the alternative was taking it
    /// out of the key, which is what the region is *next to*.
    fileprivate static let rowGap: CGFloat = 5
    fileprivate static let legendHeight: CGFloat = 8
    fileprivate static let legendGap: CGFloat = 3
    /// The sheet's type sits on the same margin as the header above it. Only the
    /// roll leaves it, and it does that from the inside.
    fileprivate static let gutter: CGFloat = 9
    /// How far past the page's gutters the roll runs. Generous, unlike the
    /// plate's two points — a plate is only an instrument while you can see all
    /// four of its sides, and a sheet is only a field while you cannot.
    fileprivate static let sideBleed: CGFloat = 10

    var body: some View {
        let capture = themeName.captureStyle
        let dim = isLuminanceReduced

        // Same cadence as the strip this descends from: a phone that has gone
        // quiet announces itself only by the clock advancing, so the sheet has
        // to re-read rather than wait to be told. It is also fast enough that
        // the day boundary underneath the roll is never stale for long.
        TimelineView(.periodic(from: .now, by: WatchMemo.silenceTolerance / 2)) { context in
            let now = context.date
            let ask = WatchAskFace.resolve(sessionManager, asOf: now)
            let headline = headline(ask: ask, asOf: now)
            let cells = roll(asOf: now)
            let today = todayTakes(asOf: now)

            sheet(headline: headline, cells: cells, today: today, capture: capture, dim: dim)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    spokenLabel(ask: ask, headline: headline, cells: cells, today: today)
                )
                .accessibilityAddTraits(headline.opensAsks ? .isButton : [])
        }
    }

    @ViewBuilder
    private func sheet(
        headline: Headline,
        cells: [WatchActivity.Cell],
        today: Int,
        capture: WatchCaptureStyle,
        dim: Bool
    ) -> some View {
        let face = VStack(alignment: .leading, spacing: Self.rowGap) {
            // Today's count used to ride the right end of this line. It is gone,
            // not moved: every position it can occupy on this face is either on
            // the roll it labels or in the top-right corner, and that corner is
            // the system clock's. Three homes tried, three collisions — the
            // honest read is that a 46mm face does not have room for a second
            // numeric readout, and the roll already shows today as its last cell.
            TickerRow(headline: headline, capture: capture, dim: dim)
                .frame(height: Self.tickerHeight)

            // The roll is the flexible member, exactly as the console is on the
            // Codex deck: the ticker is fixed, and every point the face can
            // spare goes into cell size.
            //
            // The legend sits *on* the grid rather than in a row beneath it.
            // Below, it was a third register competing with the ticker for the
            // same job, and it cost a full slot plus a gap — 13pt taken from the
            // one element on this face that is supposed to be the subject. On
            // the grid it is what it always was: chrome, labelling a field it
            // does not need to be separated from.
            // The legend belongs to the grid, so it is nested with it rather
            // than made a third peer of the ticker: it sits close enough to read
            // as the field's own caption, and the wider row gap stays where it
            // does work — between the live line and the sheet.
            VStack(alignment: .leading, spacing: Self.legendGap) {
                RollField(cells: cells, capture: capture, dim: dim)
                    .frame(maxHeight: .infinity)

                RollLegend(days: drawnDays(of: cells.count), today: today, capture: capture, dim: dim)
                    .frame(height: Self.legendHeight)
            }
        }
        .padding(.horizontal, Self.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        if headline.opensAsks {
            Button {
                WKInterfaceDevice.current().play(.click)
                onOpenAsks()
            } label: {
                face.contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            face.allowsHitTesting(false)
        }
    }

    /// How many days the roll will actually get on screen, given this sheet's
    /// slot. The roll solves the same geometry from its own `GeometryReader`;
    /// this asks the same function the same question one level up, so the legend
    /// and the grid can never disagree about how much history is showing.
    private func drawnDays(of available: Int) -> Int {
        let box = CGSize(
            width: WKInterfaceDevice.current().screenBounds.width
                - Self.gutter * 2
                + Self.sideBleed,
            height: height - Self.tickerHeight - Self.rowGap - Self.legendGap - Self.legendHeight
        )
        return min(available, RollField.rows(in: box) * RollField.columns)
    }

    // MARK: Content

    /// What the live row says, in strict priority: an ask first because it is
    /// the only thing here the wearer can act on, then captures the phone has
    /// stopped acknowledging, then a streak worth protecting, then the last
    /// thing said into the watch.
    ///
    /// The bottom of that list is not filler. A line that goes blank at rest is
    /// a line you learn to stop reading, and echoing the last capture is what a
    /// terminal would do anyway — it is also the only place on this face that
    /// answers "did that go through".
    private func headline(ask: WatchAskFace?, asOf now: Date) -> Headline {
        if let ask {
            return Headline(text: ask.text, kind: .ask(ask), opensAsks: true)
        }
        if let waiting = waitingText(asOf: now) {
            return Headline(text: waiting, kind: .waiting, opensAsks: false)
        }
        if let streak = sessionManager.activity?.streak, streak > 0 {
            return Headline(text: "\(streak) DAY STREAK", kind: .streak, opensAsks: false)
        }
        if let echo = lastCaptureEcho() {
            return Headline(text: echo, kind: .echo, opensAsks: false)
        }
        return Headline(text: "STANDING BY", kind: .idle, opensAsks: false)
    }

    /// Memos the phone has gone quiet on, or nil when everything has landed.
    ///
    /// Non-asks only: an ask in this state is already the branch above, and
    /// counting it twice would put the same capture on the row under two
    /// different names. Gated on the same silence tolerance the ask face uses —
    /// a capture in flight for two seconds is the system working; one still in
    /// flight minutes later is the phone having stopped answering.
    private func waitingText(asOf now: Date) -> String? {
        let stranded = sessionManager.recentMemos.filter { memo in
            guard !memo.isAsk, memo.isInFlight else { return false }
            let heardFrom = memo.lastUpdatedAt ?? memo.timestamp
            return now.timeIntervalSince(heardFrom) > WatchMemo.silenceTolerance
        }

        guard !stranded.isEmpty else { return nil }
        return stranded.count == 1 ? "1 MEMO WAITING" : "\(stranded.count) MEMOS WAITING"
    }

    /// The last thing transcribed, echoed back. Nil while the newest capture is
    /// still being worked on — a half-typed line is worse than a quiet one, and
    /// the branches above already cover anything actually in flight.
    private func lastCaptureEcho() -> String? {
        guard let preview = sessionManager.recentMemos.first?.transcriptionPreview else {
            return nil
        }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The roll, phone history and wrist-local captures merged, with provenance
    /// kept so the sheet can mark what the phone has not confirmed yet.
    ///
    /// With no payload at all the Watch still draws the window rather than
    /// nothing: an empty sheet with the wrist's own days printed is a true — if
    /// partial — statement, and the same shape the roll will hold once the phone
    /// answers, so the sheet does not restructure itself when it syncs.
    private func roll(asOf now: Date) -> [WatchActivity.Cell] {
        if let seeded = Self.seededRoll(asOf: now) { return seeded }
        let history = sessionManager.activity
            ?? .blank(width: Self.fallbackWindow, asOf: now)
        return history.roll(now: now, recent: sessionManager.recentMemos)
    }

    /// A plausible six weeks, for looking at the sheet in a simulator.
    ///
    /// Not a convenience — a necessity. A simulated watch has no paired phone,
    /// so the roll is structurally empty there and the one thing this region
    /// exists to show is the one thing that cannot be seen while designing it.
    /// Off unless explicitly asked for:
    ///
    ///     xcrun simctl launch <udid> to.talkie.app.watchkitapp -watch.seedRoll YES
    ///
    /// Deterministic rather than random, so two screenshots of the same change
    /// differ only by the change.
    private static func seededRoll(asOf now: Date) -> [WatchActivity.Cell]? {
        guard UserDefaults.standard.bool(forKey: "watch.seedRoll") else { return nil }
        return (0..<fallbackWindow).map { index in
            let density = Double((index * index * 17 + index * 11) % 23) / 23
            let weight = Double((index * 7 + 3) % 11) / 11
            let takes: Int = density > 0.14 ? (weight > 0.46 ? 3 : 1) : 0
            return WatchActivity.Cell(
                takes: takes,
                isUnsent: takes > 0 && index >= fallbackWindow - 4 && weight > 0.24
            )
        }
    }

    /// Today's captures — the one number on this sheet the Watch can always
    /// compute for itself, which is the whole reason the caption carries it
    /// rather than the streak.
    ///
    /// Not read off the roll: those counts are clamped to `maximumIntensity`
    /// because they were shaped for drawing, and a caption that says `3` on a
    /// seven-capture morning is wrong rather than abbreviated. The phone's count
    /// wins when it is fresher, but only if it was taken today — yesterday's
    /// `todayTakes` is a different day's number wearing the same name.
    private func todayTakes(asOf now: Date, calendar: Calendar = .current) -> Int {
        let local = sessionManager.recentMemos
            .filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
            .count

        guard let activity = sessionManager.activity,
              calendar.isDate(activity.updatedAt, inSameDayAs: now) else {
            return local
        }
        return max(activity.todayTakes, local)
    }

    /// Read aloud as facts, not as a sheet. VoiceOver gets what the region is
    /// saying rather than a description of the grid — and it says asks in their
    /// long form, since VoiceOver spells out ALLCAPS mono tokens letter by
    /// letter.
    private func spokenLabel(
        ask: WatchAskFace?,
        headline: Headline,
        cells: [WatchActivity.Cell],
        today: Int
    ) -> String {
        let active = cells.filter { $0.takes > 0 }.count
        var parts: [String] = []

        if let ask {
            parts.append(ask.spokenText)
        } else if case .idle = headline.kind {
            // Nothing worth announcing; the roll below carries the meaning.
        } else {
            parts.append(headline.text)
        }

        parts.append("Captured on \(active) of the last \(cells.count) days")
        parts.append(today == 1 ? "1 capture today" : "\(today) captures today")

        var spoken = parts.joined(separator: ". ") + "."
        if ask != nil { spoken += " Open asks." }
        return spoken
    }
}

// MARK: - Headline

/// The ticker's content and what colour it earns. Kept as a value rather than a
/// view so the priority ladder above reads as one list of rules instead of a
/// nested `if` tree with a `Text` at the bottom of every branch.
private struct Headline {
    enum Kind {
        case ask(WatchAskFace)
        case waiting
        case streak
        case echo
        case idle
    }

    let text: String
    let kind: Kind
    /// Whether tapping the sheet should open Asks. True only for asks: what the
    /// waiting line names is a memo, and memos live two pushes away under Recent
    /// rather than on the page this would open.
    let opensAsks: Bool
}

/// The live line, with a block caret behind it.
///
/// The caret is the whole reason this reads as a readout rather than as a label
/// someone typed. It is also the only animation on the region, which is the
/// budget a watch face has for one.
private struct TickerRow: View {
    let headline: Headline
    let capture: WatchCaptureStyle
    let dim: Bool

    /// Slow enough to read as a terminal rather than as a warning light.
    private static let caretPeriod: TimeInterval = 0.58

    var body: some View {
        HStack(spacing: 5) {
            marker

            // 7pt, not 12. At 12 this line was the largest type on the face
            // and read as a headline with a texture under it; the mock sets the
            // same string at 13px — 6.5pt — precisely so the roll stays the
            // subject and the line stays a readout.
            Text(headline.text)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(ink)
                .shadow(color: halo, radius: halo == .clear ? 0 : 2.5)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)

            caret

            Spacer(minLength: 0)
        }
    }

    /// The status LED, or nothing when there is no state to report. At rest the
    /// caret alone carries the line, which is one mark instead of two saying the
    /// same thing.
    @ViewBuilder
    private var marker: some View {
        switch headline.kind {
        case .ask(let state) where state.spins:
            BrailleSpinner(size: 8, color: state.color(capture: capture))
        case .ask(let state):
            Circle()
                .fill(state.color(capture: capture))
                .frame(width: 4, height: 4)
        case .waiting:
            // The face's one accent, not a system orange. Red and orange were
            // the only hues here that belonged to neither the material nor the
            // trace, which is what broke the palette on both finishes.
            Circle()
                .fill(capture.trace)
                .frame(width: 4, height: 4)
        case .streak, .echo, .idle:
            EmptyView()
        }
    }

    /// Blinks only while the wrist is up. Always-on gets a steady block: the
    /// line still terminates in something, and nothing on this face is worth
    /// waking the display twice a second for.
    @ViewBuilder
    private var caret: some View {
        // Sized off the type it terminates: a caret taller than its line is a
        // marker, and this one is punctuation.
        let block = RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(capture.trace)
            .frame(width: 2.5, height: 8)

        if dim {
            block.opacity(0.3)
        } else {
            TimelineView(.periodic(from: .now, by: Self.caretPeriod)) { context in
                // Stepped, not eased. A caret that fades is a pulse; a caret
                // that snaps is a cursor.
                let lit = Int(context.date.timeIntervalSince1970 / Self.caretPeriod) % 2 == 0
                block.opacity(lit ? 1 : 0)
            }
        }
    }

    /// Page ink, not panel ink. The plate this replaced spelled every one of
    /// these as a white opacity because it sat on black glass; there is no glass
    /// now, and white on light mineral is white on white. This is the same trade
    /// `railInk` makes on the Codex deck when its rail goes flush.
    private var ink: Color {
        let material = capture.material
        switch headline.kind {
        case .ask(let state):
            switch state {
            case .waiting, .inFlight: return material.ink.opacity(dim ? 0.45 : 0.92)
            case .stalled, .ready, .failed: return state.color(capture: capture)
            }
        case .waiting: return material.ink.opacity(dim ? 0.45 : 0.92)
        case .streak: return capture.trace
        // The echo is a quotation, not a reading. It sets back so it cannot be
        // mistaken for the sheet asserting something.
        case .echo: return material.inkFaint
        case .idle: return material.inkFaint
        }
    }

    private var halo: Color {
        guard !dim else { return .clear }
        switch headline.kind {
        case .streak:
            return capture.trace.opacity(0.35)
        case .ask(let state):
            switch state {
            case .stalled, .ready, .failed: return state.color(capture: capture).opacity(0.35)
            case .waiting, .inFlight: return .clear
            }
        case .waiting, .echo, .idle:
            return .clear
        }
    }
}

// MARK: - The roll

/// The contact sheet itself: one cell per day, wrapped into rows, running off
/// both edges of the face.
///
/// It was a single row of bars before this — a fortnight histogram, which is a
/// chart. A chart answers "how much"; a sheet answers "which ones", and on a
/// device you look at for a second and a half the second question is the one you
/// can actually answer at a glance. The grid also buys back the vertical: bars
/// need height to mean anything, cells need none, so the same band holds six
/// weeks instead of two.
private struct RollField: View {
    let cells: [WatchActivity.Cell]
    let capture: WatchCaptureStyle
    let dim: Bool

    private static let gap: CGFloat = 2
    private static let corner: CGFloat = 1.5
    /// Where the roll stops being visible at the top, as a fraction of the
    /// field's height. The sheet is printed into the face rather than framed on
    /// it, so its top edge has to dissolve — a hard edge is a border drawn in
    /// one direction only, which reads as a mistake rather than as restraint.
    ///
    /// Shallow, and shallower again now that the grid sits at the top of the
    /// field rather than centred in it: at 0.15 the fade started inside the
    /// first row of days and dimmed a week of history to make an edge softer.
    /// This is softening an edge, not clearing space.
    private static let crestFade: CGFloat = 0.05
    /// How many weeks-worth of rows the sheet draws.
    ///
    /// Declared, not solved. This used to pick a row count by whichever divisor
    /// of the window put cells nearest a target aspect in whatever box the face
    /// could spare — which is defensible right up until the box changes, at
    /// which point the sheet silently restructures itself. It did: one point of
    /// extra height flipped it from fourteen columns in three rows to twenty-one
    /// in two, and a contact sheet that reorganises when the layout breathes is
    /// not a contact sheet, it is a chart looking for a shape.
    ///
    /// One row is a fortnight — fixed, because it is a unit rather than a number.
    ///
    /// This is what stops the grid restructuring under its own layout. With the
    /// column count solved, one extra point of height once flipped the sheet from
    /// fourteen columns in three rows to twenty-one in two; with it fixed, a
    /// taller box can only ever add another fortnight to the bottom. Every row
    /// spans the same fourteen days on every watch, so the sheet reads the same
    /// way on a 40mm as on a 46mm — there is just less of it.
    static let columns = 14

    /// How many fortnights the face will draw. The ceiling is what a 46mm holds;
    /// the floor is the fewest that still reads as a sheet rather than a bar.
    ///
    /// A range rather than a constant because five rows do not fit a 40mm, and
    /// the alternative — what the face did until now — was to drop the roll
    /// altogether on the small watch and fall back to a status line. That traded
    /// the entire subject of the page for a number the ticker already carries.
    /// Three fortnights of history is worth more than none.
    private static let rowRange = 2...5

    var body: some View {
        GeometryReader { proxy in
            // Bled to the left only, and applied here rather than at the call
            // site: the roll is the only thing on the region that should leave
            // the page, and a negative padding on the whole region would take
            // the type with it.
            //
            // The asymmetry is the point. The source sheet fades both edges
            // because its "now" marker sits six cells in from the end; ours is
            // the last cell, and running the most important frame on the face
            // out under a gradient to look like film is a trade in the wrong
            // direction. The past continues past the glass because there is more
            // of it than fits. The future does not, because there is none.
            let width = proxy.size.width + CaptureContactSheet.sideBleed
            let solved = Layout(box: CGSize(width: width, height: proxy.size.height))

            grid(solved: solved, width: width)
                // Top of the field, not centred in it. The grid no longer fills
                // its slot — cell height comes from cell width now — and what it
                // leaves at the bottom is where the legend goes. Centring put
                // the type back on the cells it is supposed to label.
                .frame(width: width, height: proxy.size.height, alignment: .top)
                .mask {
                    // Horizontal: the older end dissolves rather than stopping,
                    // and today stays fully drawn. Vertical: the roll thins out
                    // under the ticker so the line above it never sits on
                    // texture.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.16)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: Self.crestFade)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .offset(x: -CaptureContactSheet.sideBleed)
        }
    }

    @ViewBuilder
    private func grid(solved: Layout, width: CGFloat) -> some View {
        // Which end gets dropped when the window does not fit, and which end gets
        // padded when it does not fill. Both answers are "the old one": today has
        // to be the last cell for the outline to mean what it says, so a short
        // watch loses its oldest fortnights off the top and a short window leaves
        // its empty slots there.
        let slots = solved.rows * Self.columns
        let shown = min(cells.count, slots)
        let lead = slots - shown
        let start = cells.count - shown

        VStack(spacing: Self.gap) {
            ForEach(0..<solved.rows, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        let slot = row * Self.columns + column
                        if slot >= lead {
                            let index = start + (slot - lead)
                            cell(cells[index], isToday: index == cells.count - 1)
                                .frame(width: solved.cell.width, height: solved.cell.height)
                        } else {
                            // A gap is honest; a stretched first row would say
                            // the sheet holds more days than it does.
                            Color.clear
                                .frame(width: solved.cell.width, height: solved.cell.height)
                        }
                    }
                }
            }
        }
        .frame(width: width, height: solved.usedHeight, alignment: .bottom)
        .frame(width: width, alignment: .center)
    }

    @ViewBuilder
    private func cell(_ cell: WatchActivity.Cell, isToday: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)

        shape
            .fill(fill(cell, isToday: isToday))
            .overlay {
                // The gloss is what makes a cell read as a frame on film rather
                // than as a square of colour. It goes on always-on, where it is
                // the first thing that is costing pixels for nothing.
                if !dim {
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.16), location: 0),
                                .init(color: .clear, location: 0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(border(cell, isToday: isToday), lineWidth: WatchEdgeWeight.hairline)
            }
            .compositingGroup()
            .shadow(color: glow(cell, isToday: isToday), radius: 2)
            .opacity(dim ? 0.55 : 1)
    }

    /// Today is an outline, not a fill: the frame currently being exposed. Days
    /// the wrist knows about but the phone has not confirmed are drawn in the
    /// signal colour — the sheet's one use of the trace as ink rather than as
    /// light, which is the distinction the source sheet draws too.
    private func fill(_ cell: WatchActivity.Cell, isToday: Bool) -> Color {
        let material = capture.material
        if isToday { return .clear }
        if cell.isUnsent { return capture.trace }
        guard cell.takes > 0 else { return material.ink.opacity(0.06) }

        let capped = min(cell.takes, WatchActivity.maximumIntensity)
        let share = Double(capped) / Double(WatchActivity.maximumIntensity)
        return material.ink.opacity(0.16 + 0.30 * share)
    }

    private func border(_ cell: WatchActivity.Cell, isToday: Bool) -> Color {
        let material = capture.material
        if isToday { return material.ink.opacity(dim ? 0.4 : 0.85) }
        if cell.isUnsent { return capture.trace }
        return material.ink.opacity(0.07)
    }

    private func glow(_ cell: WatchActivity.Cell, isToday: Bool) -> Color {
        guard !dim, cell.isUnsent else { return .clear }
        return capture.trace.opacity(0.5)
    }

    /// How many fortnights fit the box handed to the roll.
    ///
    /// Shared with the sheet so the legend can name the span it is actually
    /// drawing rather than the span the phone sent — on a 40mm those differ.
    static func rows(in box: CGSize) -> Int {
        Layout(box: box).rows
    }

    /// The sheet's geometry. Columns are fixed; only the row count is solved, and
    /// it is solved against a cell whose shape is declared rather than derived.
    ///
    /// That ordering is what fixed a grid that grew fat when its slot did. Cell
    /// height used to be `box.height / rows`, so a taller sheet did not draw more
    /// days — it drew the same days as tall squares. Now height comes from width
    /// (a day is a frame on a strip, and frames have a shape), and extra height
    /// buys another fortnight or else goes back to the face as air.
    private struct Layout {
        let rows: Int
        let cell: CGSize
        /// What the grid actually occupies, so it can sit on the field's floor
        /// instead of floating in a band it did not fill.
        let usedHeight: CGFloat

        /// A day, as a landscape frame. Not square: a grid of squares at this
        /// pitch is a barcode — the eye reads the texture and stops. Wider than
        /// tall reads as exposures on a strip, which is the claim being made.
        private static let cellAspect: CGFloat = 2.0

        init(box: CGSize) {
            guard box.width > 0, box.height > 0 else {
                rows = RollField.rowRange.lowerBound
                cell = .zero
                usedHeight = 0
                return
            }

            let width = (box.width - RollField.gap * CGFloat(RollField.columns - 1))
                / CGFloat(RollField.columns)
            let height = width / Self.cellAspect
            let pitch = height + RollField.gap

            let fits = Int(((box.height + RollField.gap) / pitch).rounded(.down))
            rows = min(RollField.rowRange.upperBound, max(RollField.rowRange.lowerBound, fits))

            cell = CGSize(width: max(width, 1), height: max(height, 1))
            usedHeight = cell.height * CGFloat(rows) + RollField.gap * CGFloat(rows - 1)
        }
    }
}

// MARK: - Legend

/// What the grid is, and what today's reading on it is.
///
/// Two tokens, and it took three attempts to earn them. A caption row saying
/// `· ROLL · 1 CELL PER DAY` explained a picture that does not need explaining;
/// an overlay printed the same words on the cells they described; parking the
/// count at the end of the ticker put it in the system clock's corner. What
/// survives is the part that is a reading rather than a definition: the name of
/// the field, its width in weeks, and how many captures today has.
///
/// `ROLL` is set as a filled tag rather than as more small caps, which is the one
/// borrowed move from the reference sheet's `ROLL / GAUGES` switch. The switch
/// itself is not borrowed: there is no gauges view to switch to, and a control
/// with one live segment is a promise the app does not keep.
private struct RollLegend: View {
    let days: Int
    let today: Int
    let capture: WatchCaptureStyle
    let dim: Bool

    /// Weeks, not days. `70 DAYS` is a number you have to divide before it means
    /// anything; the grid is five rows of a fortnight-and-a-bit, and weeks is the
    /// unit the rows are actually in.
    private var span: Int { max(days / 7, 1) }

    var body: some View {
        let material = capture.material

        HStack(spacing: 5) {
            Text("ROLL")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .tracking(0.9)
                // The tag's ink is the field, not the material's ink: it is
                // knocked out of a solid patch, so it has to match what the
                // patch is sitting on.
                .foregroundStyle(material.field)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(material.inkFaint.opacity(dim ? 0.5 : 0.85))
                )

            Text("\(span) WK")
                .font(.system(size: 6.5, weight: .medium, design: .monospaced).monospacedDigit())
                .tracking(0.9)
                .foregroundStyle(material.inkFaint.opacity(dim ? 0.5 : 0.8))

            Spacer(minLength: 4)

            Text("TDY \(today)")
                .font(.system(size: 6.5, weight: .semibold, design: .monospaced).monospacedDigit())
                .tracking(0.9)
                // A zero is unlit. It is a true reading, not a lit one, and
                // lighting it would put the same emphasis on a day you have not
                // started as on one you have.
                .foregroundStyle(
                    today > 0 ? capture.trace : material.inkFaint.opacity(dim ? 0.5 : 0.8)
                )
                .fixedSize()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Header

/// The band watchOS draws its clock in, shared rather than ceded.
///
/// Hiding the navigation bar does not hide the time; it promotes it from a small
/// glyph inside the bar to the large overlay clock. So the bar's 55pt bought a
/// taller key and a louder clock, and the second half of that trade is only
/// worth taking if the face stops treating the top of the screen as off limits
/// and moves into it: settings in the corner it belongs in, the wordmark thin
/// and letterspaced at centre, and the right third left empty on purpose,
/// because that is where watchOS puts the time and nothing here can move it.
///
/// The count that briefly sat on the right is gone rather than relocated. It was
/// the same number the live line below already spells out in words, and it was
/// crowding the one element on this face the app does not control.
///
/// The wordmark earns its place here in a way it did not when it sat alone above
/// the key. There it was decoration on an empty face; here it is the middle
/// register — the thing that stops the face reading as one shout and one whisper
/// with nothing in between.
struct CaptureHeaderRow: View {
    @Environment(\.watchThemeName) private var themeName
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// Measured from the top of the display, not from the bottom of a reserved
    /// strip — the face begins at the glass (`ignoresSafeArea(.top)`).
    ///
    /// Tight, because everything below inherits it. At 30 this row centred its
    /// contents a good 6pt lower than the reference and pushed the live line and
    /// the roll down with it, which read as a face floating inside its own
    /// bezel. The wordmark wants to sit at the top edge, not in a band near it.
    /// The row's own height, and how far down the glass it starts.
    ///
    /// The inset is not taste, it is the corner. A 46mm display rounds at about
    /// 42pt, and the arc is measured from (42, 42): a 19pt ring sitting at
    /// gutter 9, top 0 has its outermost point 48pt from that centre, so the
    /// watch cuts six points off it. Nothing in a flat framebuffer capture shows
    /// this — `simctl io screenshot` returns the raw rectangle with no corner
    /// mask — which is exactly how it survived several rounds of review.
    ///
    /// At gutter 15 and top 10 the same ring measures 37pt from the arc centre
    /// and clears. It also drops the wordmark onto the system clock's optical
    /// middle instead of floating above it.
    static let rowHeight: CGFloat = 22
    static let topInset: CGFloat = 10
    static let height: CGFloat = rowHeight + topInset
    private static let gutter: CGFloat = 15
    /// The settings ring. Sized to the row rather than to a finger — the tap
    /// target around it is what has to be thumb-sized, and it is.
    private static let plate: CGFloat = 19

    var body: some View {
        let material = themeName.captureStyle.material
        let dim = isLuminanceReduced

        ZStack {
            Text("TALKIE")
                .font(.system(size: 8, weight: .light))
                .tracking(3.4)
                .foregroundStyle(material.inkFaint.opacity(dim ? 0.5 : 0.85))
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                NavigationLink {
                    WatchMoreView()
                } label: {
                    // Given a plate, because it is the one thing in this row you
                    // can press.
                    //
                    // The face's whole boundary rule is that relief means
                    // touchable: nothing on the sheet is raised and nothing on it
                    // is tappable, everything below the sheet is both. A bare
                    // glyph up here broke that rule in the one place it is
                    // hardest to notice — and it broke twice on porcelain, where
                    // a gearshape is mostly holes and dissolves into a near-white
                    // field at any value quiet enough to belong there. The plate
                    // fixes the contrast and the affordance with the same move.
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(material.ink.opacity(dim ? 0.4 : 0.58))
                        .frame(width: Self.plate, height: Self.plate)
                        // A ring, not a filled plate. Filled, it became a second
                        // heavy mark in a row that already has one it cannot
                        // move: the system clock sits in the opposite corner at
                        // a size nothing here can answer, and two loaded corners
                        // with a hairline wordmark strung between them reads as
                        // a bar, not a header. The ring keeps the affordance —
                        // this is still the only thing in the row you can press
                        // — and gives back the weight.
                        .background {
                            Circle().strokeBorder(
                                material.secondaryEdge,
                                lineWidth: WatchEdgeWeight.hairline
                            )
                        }
                        // The tap target stays wider than the plate. The corner
                        // is where this belongs, and a button padded out to look
                        // reachable is a button in the way.
                        .frame(width: 28, height: Self.rowHeight, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Talkie settings")

                Spacer(minLength: 0)
            }
        }
        .frame(height: Self.rowHeight)
        .padding(.top, Self.topInset)
        .padding(.horizontal, Self.gutter)
    }
}

// MARK: - Quick row

/// The face's two secondary routes, in one panel split by a hairline.
///
/// This replaced a floating capsule. The capsule was the only control on the
/// page with no relief, which made the face's one raised object — the key — look
/// like an exception rather than like the rule; and it could hold exactly one
/// route, so Recent lived two pushes deep under the toolbar for no reason other
/// than that there was nowhere to put it.
///
/// The panel is the counterweight to the sheet above it. Nothing up there is
/// raised and nothing up there is touchable; everything down here is both. That
/// correspondence is the only thing on the face teaching which is which, so the
/// panel is drawn with the key's own vocabulary — lit top edge, bevel ring, a
/// shadow underneath — rather than with a lighter version of it.
struct CaptureQuickRow: View {
    @Environment(\.watchThemeName) private var themeName

    /// What the left cell does. When an ask has taken the capture key, capture
    /// has nowhere else to live, so it comes down here and the ask route steps
    /// aside — the same swap the pill made, for the same reason.
    var leadingKind: Kind = .ask
    var height: CGFloat = 36
    let onLeading: () -> Void

    enum Kind {
        case ask
        case record

        var symbol: String {
            switch self {
            case .ask: "sparkles"
            case .record: "mic.fill"
            }
        }

        var title: String {
            switch self {
            case .ask: "ASK"
            case .record: "REC"
            }
        }

        var spoken: String {
            switch self {
            case .ask: "Start AI conversation"
            case .record: "Start recording"
            }
        }
    }

    private static let corner: CGFloat = 8

    var body: some View {
        let capture = themeName.captureStyle
        let material = capture.material

        HStack(spacing: 0) {
            Button(action: onLeading) {
                cell(
                    symbol: leadingKind.symbol,
                    title: leadingKind.title,
                    tint: capture.trace,
                    capture: capture
                )
            }
            .buttonStyle(QuickCellStyle())
            .accessibilityLabel(leadingKind.spoken)

            Rectangle()
                .fill(material.ink.opacity(0.10))
                .frame(width: WatchEdgeWeight.hairline)
                .padding(.vertical, 6)

            NavigationLink {
                RecentMemosView()
            } label: {
                cell(
                    symbol: "line.3.horizontal",
                    title: "REVIEW",
                    tint: material.ink.opacity(0.78),
                    capture: capture
                )
            }
            .buttonStyle(QuickCellStyle())
            .accessibilityLabel("Recent memos")
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
            shape
                .fill(material.fieldLift)
                .overlay {
                    // Lit from the same diagonal as the key and the chassis
                    // beneath it, so the two raised objects agree about where
                    // the light is.
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.10), location: 0),
                                .init(color: .clear, location: 0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape.strokeBorder(material.keyEdgeRing, lineWidth: WatchEdgeWeight.bevel)
                }
                .compositingGroup()
                // Shallower than the key's. The key is the thing you press
                // without looking; this row is the thing you press when you
                // meant something else, and a matching shadow would make them
                // peers.
                .shadow(color: material.shadow, radius: 4, y: 3)
        }
    }

    @ViewBuilder
    private func cell(
        symbol: String,
        title: String,
        tint: Color,
        capture: WatchCaptureStyle
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(capture.material.ink.opacity(0.68))
                .minimumScaleFactor(0.85)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
    }
}

/// The press. Half the key's travel: this panel sits closer to the face than the
/// key does, so it has less room to go down before it reads as a glitch.
private struct QuickCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .offset(y: configuration.isPressed ? 0.75 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
