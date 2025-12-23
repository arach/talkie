//
//  DesignModeManager.swift
//  Talkie macOS
//
//  Design God Mode - State management for design debugging tools
//  Activated via ⌘⇧D keyboard shortcut
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Central state manager for Design God Mode
/// Controls visibility of design tools, visual decorators, and debug navigation sections
@Observable
final class DesignModeManager {
    static let shared = DesignModeManager()

    // MARK: - Core State

    /// Whether Design God Mode is enabled (toggled via ⌘⇧D)
    /// When enabled: shows design sections in sidebar + enables overlays
    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                print("🎨 Design God Mode: ENABLED")
            } else {
                print("🎨 Design God Mode: DISABLED")
                // Optionally reset decorator states when disabled
                // showGrid = false
                // showSpacing = false
                // etc.
            }
        }
    }

    // MARK: - Visual Decorator Toggles

    /// Show 8pt grid overlay (from DebugKit)
    var showGrid: Bool = false

    /// Show spacing decorators (green boxes with token labels)
    var showSpacing: Bool = false

    /// Show typography decorators (font size/weight labels)
    var showTypography: Bool = false

    /// Show color decorators (color chips with token names)
    var showColors: Bool = false

    /// Show border decorators (outlines of major layout areas)
    var showBorders: Bool = false

    // MARK: - Convenience

    /// Whether any decorator is currently active
    var hasActiveDecorators: Bool {
        showGrid || showSpacing || showTypography || showColors || showBorders
    }

    /// Toggle all decorators on/off at once
    func toggleAllDecorators() {
        let newState = !hasActiveDecorators
        showGrid = newState
        showSpacing = newState
        showTypography = newState
        showColors = newState
        showBorders = newState
    }

    /// Reset all decorator states to off
    func resetDecorators() {
        showGrid = false
        showSpacing = false
        showTypography = false
        showColors = false
        showBorders = false
    }

    private init() {}
}

#endif
