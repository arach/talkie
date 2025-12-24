//
//  TalkieAgentApp.swift
//  TalkieAgent
//
//  Created by Arach Tchoupani on 2025-12-23.
//

import SwiftUI

@main
struct TalkieAgentApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
