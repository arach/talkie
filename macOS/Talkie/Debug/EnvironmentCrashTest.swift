//
//  EnvironmentCrashTest.swift
//  Talkie
//
//  Test to reproduce the @Environment crash from the crash report.
//  This demonstrates what happens when @Environment(Type.self) is used
//  without the value being provided.
//

import SwiftUI

// MARK: - Test Views

/// A view that REQUIRES LiveSettings from the environment
/// This will crash if LiveSettings is not provided via .environment()
private struct ViewThatNeedsEnvironment: View {
    @Environment(LiveSettings.self) private var liveSettings

    var body: some View {
        VStack {
            Text("Hotkey: \(liveSettings.hotkey.displayString)")
            Text("If you see this, environment was provided correctly")
        }
        .padding()
    }
}

/// Test harness to demonstrate the crash
struct EnvironmentCrashTestView: View {
    @State private var showSafeSheet = false
    @State private var showUnsafeSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Environment Crash Test")
                .font(.headline)

            Text("""
                This demonstrates the crash from the crash report.

                @Environment(LiveSettings.self) requires the value to be
                provided via .environment(). If it's missing, SwiftUI crashes
                with: "No Observable object of type LiveSettings found"
                """)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            Divider()

            // SAFE: Environment is provided
            Button("Show SAFE Sheet (with environment)") {
                showSafeSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // UNSAFE: Environment is NOT provided - WILL CRASH
            Button("Show UNSAFE Sheet (NO environment) - WILL CRASH!") {
                showUnsafeSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Text("The unsafe button will crash the app!")
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding(40)
        .frame(width: 500, height: 400)

        // SAFE: Environment IS provided
        .sheet(isPresented: $showSafeSheet) {
            ViewThatNeedsEnvironment()
                .environment(LiveSettings.shared)  // ✅ Environment provided
                .frame(width: 300, height: 200)
        }

        // UNSAFE: Environment is NOT provided - this WILL crash
        .sheet(isPresented: $showUnsafeSheet) {
            ViewThatNeedsEnvironment()
                // ❌ NO .environment(LiveSettings.shared) - CRASH!
                .frame(width: 300, height: 200)
        }
    }
}

// MARK: - How to trigger from Debug menu

extension EnvironmentCrashTestView {
    /// Call this from the debug menu to show the test window
    @MainActor
    static func showTestWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Environment Crash Test"
        window.contentView = NSHostingView(rootView: EnvironmentCrashTestView())
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Keep window alive
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Auto-crash for testing

/// A view that crashes IMMEDIATELY when rendered (no user interaction needed)
/// Use: --debug=environment-crash
struct EnvironmentCrashImmediateView: View {
    // This will crash because LiveSettings is not in the environment
    @Environment(LiveSettings.self) private var liveSettings

    var body: some View {
        // This line will never execute - crash happens during view setup
        Text("Hotkey: \(liveSettings.hotkey.displayString)")
    }
}

extension EnvironmentCrashTestView {
    /// Trigger immediate crash for testing
    /// Run with: Talkie.app/Contents/MacOS/Talkie --debug=environment-crash
    @MainActor
    static func triggerImmediateCrash() {
        print("🔴 Triggering environment crash test...")
        print("   This simulates the crash from the crash report.")
        print("   A view will try to access @Environment(LiveSettings.self)")
        print("   without LiveSettings being provided.")
        print("")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Crash Test"

        // This will crash! The view expects LiveSettings in environment but we don't provide it
        window.contentView = NSHostingView(rootView: EnvironmentCrashImmediateView())
        // ❌ NO .environment(LiveSettings.shared) - should crash here

        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

#Preview {
    EnvironmentCrashTestView()
}
