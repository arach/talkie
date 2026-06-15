//
//  AppMode.swift
//  Talkie
//
//  Runtime guard for lite mode. Set once at process start, never changes.
//
//  Usage in unsafe singletons:
//    guard AppMode.current != .lite else {
//        fatalError("⛔️ \(Self.self) cannot be accessed in lite mode")
//    }
//

import Foundation

/// App execution mode - set once at startup, immutable thereafter
enum AppMode {
    case full       // Normal app launch - everything available
    case lite       // Interstitial-only launch - restricted access

    /// Current mode - set by main.swift before anything else runs
    /// Defaults to .full for safety (normal app behavior)
    private(set) static var current: AppMode = .full

    /// Set the mode (can only be called once, at startup)
    static func set(_ mode: AppMode) {
        // Only allow setting once
        guard current == .full else {
            TalkieConsole.critical("⚠️ [AppMode] Attempted to change mode after initialization")
            return
        }
        current = mode
        TalkieConsole.critical("🚀 [AppMode] Set to: \(mode)")
    }

    /// Check if we're in lite mode
    static var isLite: Bool { current == .lite }

    /// Check if we're in full mode
    static var isFull: Bool { current == .full }
}

// MARK: - Guard Helpers

extension AppMode {
    /// Guard against accessing a component in the wrong mode
    /// Usage: `AppMode.guard(.lite, "ServiceManager")` - logs warning but doesn't crash
    /// Use `AppMode.isLite` checks to gracefully skip code paths instead
    static func `guard`(_ mode: AppMode, _ component: String, file: String = #file, line: Int = #line) {
        guard current == mode else { return }

        let message = "⚠️ [\(component)] skipped in \(mode) mode"
        TalkieConsole.critical("%@", message)
        TalkieConsole.critical("   at %@:%d", file, line)
        // Don't crash - let caller handle gracefully
    }
}
