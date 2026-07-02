//
//  TalkieWidgetLiveActivity.swift
//  TalkieWidget
//
//  Recording Live Activity — Dynamic Island + lock-screen banner
//  shown while the recording sheet is capturing tape.
//
//  NOTE ON THE DUPLICATED TYPE: `TalkieWidgetAttributes` is also
//  declared in "Talkie iOS"/Models/RecordingLiveActivityController.swift
//  for the app target (this folder syncs to the extension only).
//  ActivityKit matches by type name + Codable payload, so the two
//  declarations must stay field-for-field identical.
//
//  Elapsed time renders with Text(timerInterval:) off the fixed
//  `startedAt` attribute — no content-state pushes while recording.
//  The single update the app ever sends is `endedAt`, which freezes
//  the readout when the tape stops.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TalkieWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Set when the tape stops — freezes the elapsed readout.
        var endedAt: Date?
    }

    /// Recording start. The widget derives the ticking elapsed
    /// readout from this, no pushes required.
    var startedAt: Date
}

struct TalkieWidgetLiveActivity: Widget {
    // Tape amber — matches the app's recording accent voice.
    private let amber = Color(red: 1.0, green: 0.64, blue: 0.26)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TalkieWidgetAttributes.self) { context in
            // Lock screen / banner
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: context.state.endedAt == nil ? "mic.fill" : "checkmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(context.state.endedAt == nil ? Color.red : amber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.endedAt == nil ? "RECORDING" : "ON TAPE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.7))
                    elapsedText(context)
                        .font(.system(size: 24, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("TALKIE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.86))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.endedAt == nil ? Color.red : amber)
                            .frame(width: 8, height: 8)
                        Text(context.state.endedAt == nil ? "REC" : "TAPE")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsedText(context)
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("TALKIE · VOICE MEMO")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.45))
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(context.state.endedAt == nil ? Color.red : amber)
            } compactTrailing: {
                elapsedText(context)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(context.state.endedAt == nil ? Color.red : amber)
            }
            .widgetURL(URL(string: "talkie://recording"))
            .keylineTint(amber)
        }
    }

    /// Ticking elapsed readout driven entirely by the fixed start
    /// date — pauses (freezes) once `endedAt` lands. The far upper
    /// bound just keeps the interval valid for very long takes.
    private func elapsedText(_ context: ActivityViewContext<TalkieWidgetAttributes>) -> Text {
        Text(
            timerInterval: context.attributes.startedAt...context.attributes.startedAt.addingTimeInterval(8 * 60 * 60),
            pauseTime: context.state.endedAt,
            countsDown: false
        )
    }
}

extension TalkieWidgetAttributes {
    fileprivate static var preview: TalkieWidgetAttributes {
        TalkieWidgetAttributes(startedAt: Date().addingTimeInterval(-42))
    }
}

extension TalkieWidgetAttributes.ContentState {
    fileprivate static var recording: TalkieWidgetAttributes.ContentState {
        TalkieWidgetAttributes.ContentState(endedAt: nil)
    }

    fileprivate static var stopped: TalkieWidgetAttributes.ContentState {
        TalkieWidgetAttributes.ContentState(endedAt: Date())
    }
}

#Preview("Notification", as: .content, using: TalkieWidgetAttributes.preview) {
   TalkieWidgetLiveActivity()
} contentStates: {
    TalkieWidgetAttributes.ContentState.recording
    TalkieWidgetAttributes.ContentState.stopped
}
