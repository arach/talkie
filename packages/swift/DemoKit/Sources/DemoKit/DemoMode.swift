//
//  DemoMode.swift
//  DemoKit
//
//  Central configuration for demo mode.
//  Zero cost when disabled - all operations become no-ops.
//

import Foundation

/// Demo mode configuration
public enum DemoMode {
    /// Whether demo mode is currently active
    public static var isEnabled: Bool = {
        // Check launch arguments
        if CommandLine.arguments.contains("--demo") {
            return true
        }
        // Check environment variable
        if ProcessInfo.processInfo.environment["DEMO_MODE"] == "1" {
            return true
        }
        return false
    }()

    /// Manually enable demo mode (call early in app startup)
    public static func enable() {
        isEnabled = true
        print("🎬 DemoKit: Demo mode enabled")
    }

    /// Manually disable demo mode
    public static func disable() {
        isEnabled = false
    }

    /// Run a closure only if demo mode is enabled
    @inlinable
    public static func whenEnabled(_ action: () -> Void) {
        guard isEnabled else { return }
        action()
    }

    /// Run an async closure only if demo mode is enabled
    @inlinable
    public static func whenEnabled(_ action: () async -> Void) async {
        guard isEnabled else { return }
        await action()
    }
}
