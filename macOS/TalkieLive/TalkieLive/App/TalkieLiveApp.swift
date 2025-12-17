import SwiftUI

@main
struct TalkieLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Pure menu bar app - no windows
        // LSUIElement=true in Info.plist makes this menu bar only (no dock icon)
        // All UI accessed via menu bar icon and AppDelegate
        Settings {
            EmptyView()
        }
    }
}

#Preview {
    LiveNavigationView()
}

// MARK: - Notification Names

extension Notification.Name {
    static let selectUtterance = Notification.Name("selectUtterance")
}
