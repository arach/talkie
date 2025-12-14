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
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Handle talkielive://utterance/{id}
        guard url.scheme == "talkielive" else { return }

        if url.host == "utterance",
           let idString = url.pathComponents.last,
           let id = Int64(idString) {
            // Post notification to select this utterance
            NotificationCenter.default.post(
                name: .selectUtterance,
                object: nil,
                userInfo: ["id": id]
            )
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

// MARK: - Notification Names

extension Notification.Name {
    static let selectUtterance = Notification.Name("selectUtterance")
}
