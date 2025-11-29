//
//  AppIntents.swift
//  Talkie iOS
//
//  Siri and Shortcuts integration via App Intents
//

import AppIntents
import SwiftUI

// MARK: - Start Recording Intent

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Voice Memo"
    static var description = IntentDescription("Start recording a new voice memo with Talkie")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The app will open and DeepLinkManager will handle the recording trigger
        DeepLinkManager.shared.pendingAction = .record
        return .result(dialog: "Starting recording...")
    }
}

// MARK: - Get Memo Count Intent

struct GetMemoCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Voice Memo Count"
    static var description = IntentDescription("Find out how many voice memos you have in Talkie")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = getMemoCount()

        if count == 0 {
            return .result(dialog: "You don't have any voice memos yet. Would you like to record one?")
        } else if count == 1 {
            return .result(dialog: "You have 1 voice memo in Talkie.")
        } else {
            return .result(dialog: "You have \(count) voice memos in Talkie.")
        }
    }

    private func getMemoCount() -> Int {
        // Read from shared UserDefaults (App Group)
        let defaults = UserDefaults(suiteName: "group.com.jdi.talkie")
        return defaults?.integer(forKey: "memoCount") ?? 0
    }
}

// MARK: - Play Last Memo Intent

struct PlayLastMemoIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Last Voice Memo"
    static var description = IntentDescription("Play your most recent voice memo")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Open app and trigger playback of last memo
        DeepLinkManager.shared.pendingAction = .playLastMemo
        return .result(dialog: "Playing your last memo...")
    }
}

// MARK: - Search Memos Intent

struct SearchMemosIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Voice Memos"
    static var description = IntentDescription("Search your voice memos by keyword")

    @Parameter(title: "Search Term")
    var searchTerm: String

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        DeepLinkManager.shared.pendingAction = .search(query: searchTerm)
        return .result(dialog: "Searching for '\(searchTerm)'...")
    }
}

// MARK: - App Shortcuts Provider

struct TalkieShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Record with \(.applicationName)",
                "Start recording with \(.applicationName)",
                "Record a voice memo with \(.applicationName)",
                "New memo in \(.applicationName)",
                "Hey \(.applicationName), record"
            ],
            shortTitle: "Record",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: GetMemoCountIntent(),
            phrases: [
                "How many memos in \(.applicationName)",
                "How many voice memos do I have in \(.applicationName)",
                "Count my \(.applicationName) memos"
            ],
            shortTitle: "Memo Count",
            systemImageName: "number"
        )

        AppShortcut(
            intent: PlayLastMemoIntent(),
            phrases: [
                "Play my last memo in \(.applicationName)",
                "Play last recording in \(.applicationName)",
                "Play my latest \(.applicationName) memo"
            ],
            shortTitle: "Play Last",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: SearchMemosIntent(),
            phrases: [
                "Search \(.applicationName) for \(\.$searchTerm)",
                "Find \(\.$searchTerm) in \(.applicationName)",
                "Look for \(\.$searchTerm) in my memos"
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
    }
}

// MARK: - App Intent Errors

enum TalkieIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noMemosFound
    case recordingFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noMemosFound:
            return "No voice memos found"
        case .recordingFailed:
            return "Failed to start recording"
        }
    }
}
