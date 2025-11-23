//
//  talkieApp.swift
//  talkie
//
//  Created by Arach Tchoupani on 2025-11-23.
//

import SwiftUI

@main
struct talkieApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
