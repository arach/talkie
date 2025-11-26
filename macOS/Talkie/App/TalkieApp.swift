//
//  TalkieApp.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

@main
struct TalkieApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            TalkieNavigationView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
