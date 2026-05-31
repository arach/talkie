//
//  KeyboardAction.swift
//  TalkieMobileKit
//
//  Shared keyboard action model and host abstraction.
//

import Foundation

public enum KeyboardCursorMovement: Sendable, Equatable {
    case left
    case right
    case up
    case down
    case wordLeft
    case wordRight
}

public enum KeyboardAction: Sendable, Equatable {
    case insert(String)
    case deleteBackward
    case copy
    case paste
    case selectAll
    case toggleShift
    case toggleControl
    case tab
    case escape
    case enter
    case interrupt
    case dismissKeyboard
    case moveCursor(KeyboardCursorMovement)
}

@MainActor
public protocol KeyboardInputHost: AnyObject {
    func performKeyboardAction(_ action: KeyboardAction)
}

public enum KeyboardActionResolver {
    public static func action(for config: SlotConfig) -> KeyboardAction? {
        switch config.type {
        case .text, .snippet:
            return .insert(config.content)
        case .space:
            return .insert(" ")
        case .empty:
            return nil
        case .action:
            switch config.label {
            case "COPY":
                return .copy
            case "PASTE":
                return .paste
            case "SELECT":
                return .selectAll
            case "SHIFT":
                return .toggleShift
            case "CONTROL":
                return .toggleControl
            case "DEL":
                return .deleteBackward
            case "TAB":
                return .tab
            case "ESC":
                return .escape
            case "ENTER":
                return .enter
            default:
                return config.content.isEmpty ? nil : .insert(config.content)
            }
        }
    }

    @MainActor
    public static func perform(_ config: SlotConfig, on host: KeyboardInputHost) {
        guard let action = action(for: config) else { return }
        host.performKeyboardAction(action)
    }
}
