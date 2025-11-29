//
//  TalkieControlWidget.swift
//  TalkieWidget
//
//  Control Center widget for iOS 18+
//

import WidgetKit
import SwiftUI
import AppIntents

@available(iOSApplicationExtension 18.0, *)
struct TalkieControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jdi.talkie.control") {
            ControlWidgetButton(action: RecordVoiceMemoIntent()) {
                Label("Record", systemImage: "mic.fill")
            }
        }
        .displayName("Quick Record")
        .description("Start recording a voice memo")
    }
}

// MARK: - Record Intent

@available(iOS 18.0, *)
struct RecordVoiceMemoIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Voice Memo"
    static var description = IntentDescription("Start recording a new voice memo")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // The app will be opened, and we'll handle the recording via URL scheme
        // which is set up in the main app
        return .result()
    }
}
