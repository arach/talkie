import SwiftUI

@main
struct NotchCanonicalTestApp: App {
    var body: some Scene {
        WindowGroup("Notch Canonical Test") {
            NotchLabView()
        }
        .defaultSize(width: 1120, height: 760)
    }
}
