//
//  RealClick.swift
//  DemoKit
//
//  Performs real OS-level clicks for hybrid demo mode.
//  Converts local view coordinates to screen coordinates and triggers actual clicks.
//

import Foundation
import AppKit

/// Hybrid click system - synthetic cursor visuals + real OS clicks
public enum RealClick {

    /// Perform a real click at the given local view coordinates
    /// Converts to screen coordinates using the key window's frame
    @MainActor
    public static func click(at localPoint: CGPoint, in window: NSWindow? = nil) {
        guard DemoMode.isEnabled else { return }

        // Try multiple ways to get the window
        let targetWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first

        guard let windowFrame = targetWindow?.frame else {
            NSLog("RealClick: No window available for coordinate conversion (windows: \(NSApp.windows.count))")
            return
        }

        // Ensure our app is frontmost
        NSApp.activate(ignoringOtherApps: true)

        // Get screen height for coordinate flip (macOS uses bottom-left origin)
        guard let screen = targetWindow?.screen ?? NSScreen.main else {
            NSLog("RealClick: No screen available")
            return
        }
        let screenHeight = screen.frame.height

        // Convert local (view) coordinates to screen coordinates
        // Local SwiftUI coordinates: origin at top-left of window content
        // Screen coordinates: origin at bottom-left of screen
        let screenX = windowFrame.origin.x + localPoint.x

        // Window frame Y is from screen bottom, local Y is from window top
        // screenY = windowTop - localY, where windowTop = windowFrame.origin.y + windowFrame.height
        let windowTopY = windowFrame.origin.y + windowFrame.height
        let screenY = windowTopY - localPoint.y

        // Convert to "top-left origin" coordinates that CGEvent expects
        // CGEvent uses a coordinate system where (0,0) is top-left of main display
        let cgEventY = screenHeight - screenY

        NSLog("RealClick: local=(\(Int(localPoint.x)), \(Int(localPoint.y))) → screen=(\(Int(screenX)), \(Int(cgEventY))) [window at \(Int(windowFrame.origin.x)),\(Int(windowFrame.origin.y)) size \(Int(windowFrame.width))x\(Int(windowFrame.height))]")

        performClick(x: screenX, y: cgEventY)
    }

    /// Perform a click at absolute screen coordinates
    public static func performClick(x: CGFloat, y: CGFloat) {
        // Use CGEvent for reliable clicking
        let point = CGPoint(x: x, y: y)

        // Mouse down
        if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            mouseDown.post(tap: .cghidEventTap)
        }

        // Small delay between down and up
        usleep(50000) // 50ms

        // Mouse up
        if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }

        NSLog("RealClick: Posted CGEvent at (\(Int(x)), \(Int(y)))")
    }

    /// Perform a click using AppleScript (fallback if CGEvent doesn't work)
    public static func performClickViaAppleScript(x: CGFloat, y: CGFloat) {
        let script = """
        do shell script "osascript -e 'tell application \\"System Events\\" to click at {\(Int(x)), \(Int(y))}'"
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                NSLog("RealClick AppleScript error: \(error)")
            }
        }
    }
}
