//
//  TalkieWidgetControl.swift
//  TalkieWidget
//
//  Control Center widget for quick recording (iOS 18+)
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Control Widget

struct TalkieWidgetControl: ControlWidget {
    static let kind: String = "com.jdi.talkie.record-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RecordVoiceMemoIntent()) {
                Label("Record", systemImage: "mic.fill")
            }
        }
        .displayName("Record Memo")
        .description("Quickly start recording a voice memo")
    }
}

// MARK: - Record Intent

struct RecordVoiceMemoIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Voice Memo"
    static var description = IntentDescription("Start recording a new voice memo")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Set a flag in shared UserDefaults that the app will check on launch
        if let defaults = UserDefaults(suiteName: "group.com.jdi.talkie") {
            defaults.set(true, forKey: "shouldStartRecording")
            defaults.synchronize() // Ensure immediate write for cross-process access
        }
        return .result()
    }
}
