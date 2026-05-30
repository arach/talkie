//
//  ContentView.swift
//  TalkieAgent
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        AgentHomeView(
            onDismiss: {},
            onOpenSettings: {
                NotificationCenter.default.post(name: .showSettingsFromXPC, object: nil)
            }
        )
    }
}

#Preview {
    ContentView()
}
