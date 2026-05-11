//
//  TalkieWatchWidget.swift
//  TalkieWatchWidget
//
//  Watch complications for one-tap recording
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct TalkieComplicationEntry: TimelineEntry {
    let date: Date
    let isReady: Bool
}

// MARK: - Timeline Provider

struct TalkieComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> TalkieComplicationEntry {
        TalkieComplicationEntry(date: Date(), isReady: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TalkieComplicationEntry) -> Void) {
        completion(TalkieComplicationEntry(date: Date(), isReady: true))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TalkieComplicationEntry>) -> Void) {
        let entry = TalkieComplicationEntry(date: Date(), isReady: true)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
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
    static let go = ComplicationPreset(id: "go", name: "Go", icon: "bolt.fill", color: .red)
    static let thought = ComplicationPreset(id: "thought", name: "Thought", icon: "brain.head.profile", color: .purple)
    static let meeting = ComplicationPreset(id: "meeting", name: "Meeting", icon: "person.2.fill", color: .blue)
    static let task = ComplicationPreset(id: "task", name: "Task", icon: "checkmark.circle.fill", color: .green)
}

// MARK: - Main Complication View

struct TalkieComplicationEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: TalkieComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.red)
        }
        .widgetURL(URL(string: "talkie://record/go"))
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.3))
                    .frame(width: 36, height: 36)

                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Talkie")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Tap to record")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .widgetURL(URL(string: "talkie://record/go"))
    }

    private var cornerView: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.red)
            .widgetLabel {
                Text("Record")
            }
            .widgetURL(URL(string: "talkie://record/go"))
    }

    private var inlineView: some View {
        Label("Talkie", systemImage: "mic.fill")
            .widgetURL(URL(string: "talkie://record/go"))
    }
}

// MARK: - Main Widget

struct TalkieComplication: Widget {
    let kind: String = "TalkieComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TalkieComplicationProvider()) { entry in
            TalkieComplicationEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Talkie")
        .description("One-tap voice recording")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Preset-Specific Complication View

struct PresetComplicationView: View {
    @Environment(\.widgetFamily) var family
    let preset: ComplicationPreset

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()

                Image(systemName: preset.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(preset.color)
            }
            .widgetURL(URL(string: "talkie://record/\(preset.id)"))

        case .accessoryCorner:
            Image(systemName: preset.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(preset.color)
                .widgetLabel {
                    Text(preset.name)
                }
                .widgetURL(URL(string: "talkie://record/\(preset.id)"))

        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: preset.icon)
                    .foregroundStyle(preset.color)
            }
            .widgetURL(URL(string: "talkie://record/\(preset.id)"))
        }
    }
}

// MARK: - Preset Widgets

struct ThoughtComplication: Widget {
    let kind: String = "ThoughtComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TalkieComplicationProvider()) { entry in
            PresetComplicationView(preset: .thought)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Thought")
        .description("Record a thought")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct MeetingComplication: Widget {
    let kind: String = "MeetingComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TalkieComplicationProvider()) { entry in
            PresetComplicationView(preset: .meeting)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Meeting")
        .description("Record meeting notes")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct TaskComplication: Widget {
    let kind: String = "TaskComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TalkieComplicationProvider()) { entry in
            PresetComplicationView(preset: .task)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Task")
        .description("Record a task")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

// MARK: - Widget Bundle

@main
struct TalkieWatchWidgets: WidgetBundle {
    var body: some Widget {
        TalkieComplication()
        ThoughtComplication()
        MeetingComplication()
        TaskComplication()
    }
}
