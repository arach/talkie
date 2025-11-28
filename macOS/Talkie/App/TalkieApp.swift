//
//  TalkieApp.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AppKit

@main
struct TalkieApp: App {
    // Wire up AppDelegate for push notification handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    @ObservedObject private var settingsManager = SettingsManager.shared

    var body: some Scene {
        WindowGroup {
            TalkieNavigationView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .frame(minWidth: 900, minHeight: 600)
                .tint(settingsManager.accentColor.color)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .frame(minWidth: 800, minHeight: 600)
                .tint(settingsManager.accentColor.color)
        }
    }
}
