//
//  SystemReservedHotkeys.swift
//  TalkieKit
//

import Foundation
#if os(macOS)
import Carbon.HIToolbox
#endif

public enum SystemReservedHotkeys {
    /// macOS owns Command-Shift screenshot shortcuts before app-level Carbon
    /// hotkeys can claim them. Treat the clipboard variants as reserved too.
    public static func isAppleScreenshotShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let relevantModifiers = modifiers & (commandModifier | optionModifier | controlModifier | shiftModifier)
        let screenshotModifiers = commandModifier | shiftModifier
        let clipboardScreenshotModifiers = commandModifier | controlModifier | shiftModifier

        guard relevantModifiers == screenshotModifiers ||
              relevantModifiers == clipboardScreenshotModifiers else {
            return false
        }

        switch keyCode {
        case 20, 21, 22, 23: // 3, 4, 6, 5
            return true
        default:
            return false
        }
    }

    private static var commandModifier: UInt32 {
        #if os(macOS)
        UInt32(cmdKey)
        #else
        256
        #endif
    }

    private static var optionModifier: UInt32 {
        #if os(macOS)
        UInt32(optionKey)
        #else
        2048
        #endif
    }

    private static var controlModifier: UInt32 {
        #if os(macOS)
        UInt32(controlKey)
        #else
        4096
        #endif
    }

    private static var shiftModifier: UInt32 {
        #if os(macOS)
        UInt32(shiftKey)
        #else
        512
        #endif
    }
}
