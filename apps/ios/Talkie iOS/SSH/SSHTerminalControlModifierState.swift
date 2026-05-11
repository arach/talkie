//
//  SSHTerminalControlModifierState.swift
//  Talkie iOS
//

import Foundation

enum SSHTerminalControlModifierState {
    case inactive
    case armed
    case locked

    var isActive: Bool {
        self != .inactive
    }

    var consumesAfterUse: Bool {
        self == .armed
    }

    var isLocked: Bool {
        self == .locked
    }
}
