//
//  TalkieWatchApp.swift
//  TalkieWatch Watch App
//
//  Created by Arach Tchoupani on 2025-12-12.
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
