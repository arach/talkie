import SwiftUI

@main
struct TalkieLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var onboarding = OnboardingManager.shared
    @StateObject private var troubleshooter = AudioTroubleshooterController.shared

    var body: some Scene {
        // Main window - History (hidden title for cleaner look)
        Window("Talkie Live", id: "main") {
            mainContent
                .sheet(isPresented: $onboarding.shouldShowOnboarding) {
                    OnboardingView()
                }
                .sheet(isPresented: $troubleshooter.isShowing) {
                    AudioTroubleshooterView()
                }
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
