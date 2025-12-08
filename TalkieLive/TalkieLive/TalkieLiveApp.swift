import SwiftUI
import TalkieServices

@main
struct TalkieLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window - History (hidden title for cleaner look)
        Window("Talkie Live", id: "main") {
            mainContent
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        #if DEBUG
        DebugToolbarOverlay {
            LiveNavigationView()
        }
        #else
        LiveNavigationView()
        #endif
    }
}

#Preview {
    LiveNavigationView()
}
