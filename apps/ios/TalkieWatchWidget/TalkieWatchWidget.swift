//
//  TalkieWatchWidget.swift
//  TalkieWatchWidget
//
//  One complication, configured per watch face, showing live watch state.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Role

/// What a given placement of the complication is for.
///
/// One configurable kind rather than one kind per preset: a wearer who wants
/// Ask on their modular face and a memo button on their infograph face is
/// choosing between the same five things twice, and the watch face editor is
/// already the right place to make that choice.
enum ComplicationRole: String, AppEnum {
    case ask
    case memo
    case thought
    case meeting
    case task

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Action")
    }

    // Has to stay a dictionary literal: the AppIntents metadata processor reads
    // it out of the source at build time, so anything computed fails export.
    static var caseDisplayRepresentations: [ComplicationRole: DisplayRepresentation] {
        [
            .ask: DisplayRepresentation(
                title: "Ask",
                subtitle: "Ask a question, and see the answer arrive"
            ),
            .memo: DisplayRepresentation(title: "Memo", subtitle: "Start recording"),
            .thought: DisplayRepresentation(title: "Thought", subtitle: "Record a thought"),
            .meeting: DisplayRepresentation(title: "Meeting", subtitle: "Record meeting notes"),
            .task: DisplayRepresentation(title: "Task", subtitle: "Record a task")
        ]
    }

    /// What this role is called wherever the wearer is choosing between roles.
    ///
    /// Taken from the display representations above rather than from the preset:
    /// the preset names the *button* ("Go"), and offering the same case as "Go"
    /// in the face gallery and "Memo" on the configuration screen reads as two
    /// different complications.
    var displayName: String {
        guard let title = Self.caseDisplayRepresentations[self]?.title else {
            return rawValue.capitalized
        }
        return String(localized: title)
    }
}

// MARK: - Preset Definition (duplicated for widget isolation)

struct ComplicationPreset {
    let id: String
    let name: String
    let icon: String
    let color: Color
}

extension ComplicationPreset {
    // Kept in step with `TalkieWatch Watch App/WatchPreset.swift` by hand — the
    // face should look like the button it stands in for.
    static let go = ComplicationPreset(id: "go", name: "Go", icon: "bolt.fill", color: .red)
    static let ai = ComplicationPreset(id: "ai", name: "Ask", icon: "sparkles", color: .cyan)
    static let thought = ComplicationPreset(id: "thought", name: "Thought", icon: "note.text", color: .purple)
    static let meeting = ComplicationPreset(id: "meeting", name: "Meeting", icon: "person.2.fill", color: .blue)
    static let task = ComplicationPreset(id: "task", name: "Task", icon: "checkmark.circle.fill", color: .green)
}

extension ComplicationRole {
    var preset: ComplicationPreset {
        switch self {
        case .ask: .ai
        case .memo: .go
        case .thought: .thought
        case .meeting: .meeting
        case .task: .task
        }
    }
}

// MARK: - Configuration Intent

struct TalkieComplicationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Talkie"
    static var description = IntentDescription("Choose what this complication does.")

    @Parameter(title: "Action", default: .ask)
    var role: ComplicationRole

    init() {}

    init(role: ComplicationRole) {
        self.role = role
    }
}

// MARK: - Timeline Entry

struct TalkieComplicationEntry: TimelineEntry {
    let date: Date
    let role: ComplicationRole
    let state: WatchSharedState

    /// Everything the views draw, resolved once here so the four families
    /// cannot disagree about what the watch is currently doing.
    var face: ComplicationFace {
        ComplicationFace(role: role, state: state, now: date)
    }
}

/// The resolved appearance of one complication at one moment.
struct ComplicationFace {
    let symbol: String
    let tint: Color
    /// The short word on a corner or inline complication.
    let label: String
    /// The second line the rectangular family has room for. Nil when there is
    /// nothing true to say — a filler subtitle is worse than none.
    let detail: String?
    /// Draw the unread dot. Reserved for an answer nobody has looked at yet:
    /// it is the only state where the wearer is being told something rather
    /// than reminded of something.
    let showsBadge: Bool
    let url: URL?

    init(role: ComplicationRole, state: WatchSharedState, now: Date) {
        let preset = role.preset

        // Every role but Ask is a launcher, and a launcher has one appearance.
        guard role == .ask else {
            symbol = preset.icon
            tint = preset.color
            label = preset.name
            detail = "Tap to record"
            showsBadge = false
            url = URL(string: "talkie://record/\(preset.id)")
            return
        }

        symbol = preset.icon

        if state.hasWaitingAnswer {
            tint = .green
            label = "Answer"
            // The question, not the answer: an answer worth reading does not
            // fit here, and a truncated one reads as the whole thing.
            detail = state.askQuestion ?? "Tap to hear it"
            showsBadge = true
            // Straight to that answer. Landing on the list and hunting for the
            // one the face just announced is the wearer redoing work the watch
            // had already done.
            url = state.askID
                .flatMap { URL(string: "talkie://ask/\($0)") }
                ?? URL(string: "talkie://record/\(preset.id)")
            return
        }

        if state.isStalled(asOf: now) {
            // Not an error — the phone may simply be out of range. Said as an
            // observation, so the wearer knows to stop waiting without being
            // told something went wrong that may not have.
            tint = .orange
            label = "Quiet"
            detail = state.isReachable ? "No word back yet" : "Phone out of reach"
            showsBadge = false
            url = URL(string: "talkie://record/\(preset.id)")
            return
        }

        if state.isWorking(asOf: now) {
            tint = preset.color
            label = "Working"
            detail = state.askQuestion ?? "Waiting on the phone"
            showsBadge = false
            url = URL(string: "talkie://record/\(preset.id)")
            return
        }

        tint = preset.color
        label = preset.name
        detail = "Tap to ask"
        showsBadge = false
        url = URL(string: "talkie://record/\(preset.id)")
    }
}

// MARK: - Timeline Provider

struct TalkieComplicationProvider: AppIntentTimelineProvider {
    private let reader = WatchSharedStateReader()

    func placeholder(in context: Context) -> TalkieComplicationEntry {
        TalkieComplicationEntry(date: Date(), role: .ask, state: WatchSharedState())
    }

    /// What the watch face gallery offers before the wearer has configured
    /// anything. One entry per role, so picking a complication and picking what
    /// it does stay a single step — the editor's own configuration screen is
    /// then only for changing your mind.
    func recommendations() -> [AppIntentRecommendation<TalkieComplicationIntent>] {
        ComplicationRole.allCases.map { role in
            AppIntentRecommendation(
                intent: TalkieComplicationIntent(role: role),
                description: Text(role.displayName)
            )
        }
    }

    func snapshot(
        for configuration: TalkieComplicationIntent,
        in context: Context
    ) async -> TalkieComplicationEntry {
        TalkieComplicationEntry(
            date: Date(),
            role: configuration.role,
            state: reader.read()
        )
    }

    func timeline(
        for configuration: TalkieComplicationIntent,
        in context: Context
    ) async -> Timeline<TalkieComplicationEntry> {
        let now = Date()
        let state = reader.read()

        var entries = [
            TalkieComplicationEntry(date: now, role: configuration.role, state: state)
        ]

        // The one change that happens on its own: an ask that has been quiet
        // long enough to stop claiming it is working. Scheduling it as a second
        // entry means the face corrects itself at the right moment even if the
        // app never runs again to publish it.
        if let staleAt = state.askStaleAt, staleAt > now {
            entries.append(
                TalkieComplicationEntry(date: staleAt, role: configuration.role, state: state)
            )
        }

        // Everything else is pushed: the app reloads timelines whenever the
        // state it publishes actually moves, so polling would only spend budget
        // to redraw what is already on screen. `.atEnd` applies solely to the
        // scheduled flip above, to pick the real state back up afterwards.
        return Timeline(entries: entries, policy: entries.count > 1 ? .atEnd : .never)
    }
}

// MARK: - Views

struct TalkieComplicationEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: TalkieComplicationEntry

    var body: some View {
        content
            .widgetURL(entry.face.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        #if os(watchOS)
        case .accessoryCorner:
            cornerView
        #endif
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    private var face: ComplicationFace { entry.face }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: face.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(face.tint)

            if face.showsBadge {
                // Corner-anchored rather than beside the glyph: the circular
                // family is small enough that anything inline with the icon
                // reads as part of it.
                Circle()
                    .fill(face.tint)
                    .frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(4)
            }
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(face.tint.opacity(0.3))
                    .frame(width: 36, height: 36)

                Image(systemName: face.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(face.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(face.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    if face.showsBadge {
                        Circle()
                            .fill(face.tint)
                            .frame(width: 5, height: 5)
                    }
                }

                if let detail = face.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    #if os(watchOS)
    private var cornerView: some View {
        Image(systemName: face.symbol)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(face.tint)
            .widgetLabel {
                Text(face.label)
            }
    }
    #endif

    private var inlineView: some View {
        Label(face.label, systemImage: face.symbol)
    }
}

// MARK: - Supported families
//
// `accessoryCorner` is watchOS-only — the iOS slice of this extension
// (built for the iPhone host) doesn't have it on `WidgetFamily`. Swift
// rejects `#if` inside array literals, so the families are computed
// here once and passed as a value.
private enum ComplicationFamilies {
    static let all: [WidgetFamily] = {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline]
        #else
        return [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }()
}

// MARK: - Widget

struct TalkieComplication: Widget {
    // Unchanged from when this was a static configuration, so a complication
    // already sitting on a face survives the switch rather than vanishing off
    // it. Existing placements come back configured as the default role.
    let kind: String = "TalkieComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TalkieComplicationIntent.self,
            provider: TalkieComplicationProvider()
        ) { entry in
            TalkieComplicationEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Talkie")
        .description("Ask, or start a recording, from the watch face.")
        .supportedFamilies(ComplicationFamilies.all)
    }
}

// MARK: - Widget Bundle

@main
struct TalkieWatchWidgets: WidgetBundle {
    var body: some Widget {
        TalkieComplication()
    }
}
