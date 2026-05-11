//
//  NotchInfo.swift
//  Talkie
//
//  Notch detection — determines if the display has a notch and its dimensions.
//  Ported from TalkieAgent's NotchOverlay.swift.
//

import AppKit

struct NotchInfo {
    static let defaultMenuBarHeight: CGFloat = 24
    static let defaultVirtualNotchWidth: CGFloat = 180
    static let defaultVirtualNotchHeight: CGFloat = 34

    let hasNotch: Bool
    let isVirtual: Bool       // True when synthesized for non-notch displays
    let notchWidth: CGFloat
    let notchHeight: CGFloat  // Height of menu bar / notch area
    let screenFrame: CGRect
    let screenCenter: CGFloat  // X center used to anchor notch overlay
    let displayID: CGDirectDisplayID

    static func detect(for screen: NSScreen? = NSScreen.main) -> NotchInfo {
        guard let screen = screen else {
            return NotchInfo(
                hasNotch: false,
                isVirtual: false,
                notchWidth: 0,
                notchHeight: defaultMenuBarHeight,
                screenFrame: .zero,
                screenCenter: 0,
                displayID: 0
            )
        }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let resolvedDisplayID = Self.displayID(for: screen) ?? 0

        // Menu bar height (includes notch on notched displays)
        // Notched MacBooks: ~37pt, Non-notched: ~24pt
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        var hasNotch = false

        // Fallback values when exact notch geometry isn't available.
        var notchWidth: CGFloat = 0
        var notchCenter: CGFloat = screenFrame.midX

        // Prefer the real hardware notch exclusion zones when available.
        if #available(macOS 12.0, *) {
            if let left = screen.auxiliaryTopLeftArea,
               let right = screen.auxiliaryTopRightArea,
               left.width > 0,
               right.width > 0 {
                var leftMaxX = left.maxX
                var rightMinX = right.minX
                let rawCenter = (leftMaxX + rightMinX) / 2

                // Some multi-display setups can report local screen coordinates.
                // If so, shift into global screen-space using screenFrame's origin.
                if abs(rawCenter - screenFrame.midX) > (screenFrame.width / 2) {
                    leftMaxX += screenFrame.minX
                    rightMinX += screenFrame.minX
                }

                let measuredWidth = rightMinX - leftMaxX
                // Guard against false positives on external displays where menu-bar
                // metrics can be tall but no physical notch exists.
                if measuredWidth > 80, measuredWidth < (screenFrame.width * 0.55) {
                    hasNotch = true
                    notchWidth = measuredWidth
                    notchCenter = (leftMaxX + rightMinX) / 2
                }
            }
        }

        // Fallback: if auxiliary areas are unavailable, allow a built-in-display
        // heuristic so real MacBook notches still resolve.
        if !hasNotch, CGDisplayIsBuiltin(resolvedDisplayID) != 0, menuBarHeight > 30 {
            hasNotch = true
            notchWidth = defaultVirtualNotchWidth
            notchCenter = screenFrame.midX
        }

        // Use the actual menu bar height from the system. The hardcoded defaults
        // are only floors for edge cases (e.g., headless displays with no menu bar).
        let resolvedHeight = max(menuBarHeight, defaultMenuBarHeight)

        return NotchInfo(
            hasNotch: hasNotch,
            isVirtual: false,
            notchWidth: notchWidth,
            notchHeight: resolvedHeight,
            screenFrame: screenFrame,
            screenCenter: notchCenter,
            displayID: resolvedDisplayID
        )
    }

    static func effective(for screen: NSScreen? = NSScreen.main) -> NotchInfo {
        let detected = detect(for: screen)
        guard let screen else { return detected }
        guard !detected.hasNotch else { return detected }

        return NotchInfo(
            hasNotch: true,
            isVirtual: true,
            notchWidth: defaultVirtualNotchWidth,
            notchHeight: max(detected.notchHeight, defaultVirtualNotchHeight),
            screenFrame: screen.frame,
            screenCenter: screen.frame.midX,
            displayID: detected.displayID
        )
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
