//
//  TalkieWatchApp.swift
//  TalkieWatch
//
//  Fire-and-forget voice recording from your wrist
//

import SwiftUI

@main
struct TalkieWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            RecordingView()
                .environmentObject(sessionManager)
        }
    }
}
