import SwiftUI

@main
struct TalkieAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app with settings accessible via ⌘,
        Settings {
            QuickSettingsView()
                .frame(minWidth: 650, minHeight: 550)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let selectUtterance = Notification.Name("selectUtterance")
    static let showSettingsFromXPC = Notification.Name("showSettingsFromXPC")
}
