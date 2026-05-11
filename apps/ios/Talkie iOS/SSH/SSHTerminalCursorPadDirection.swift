//
//  SSHTerminalCursorPadDirection.swift
//  Talkie iOS
//

import CoreGraphics

enum SSHTerminalCursorPadDirection: CaseIterable {
    case up
    case left
    case right
    case down

    var systemImage: String {
        switch self {
        case .up:
            return "chevron.up"
        case .left:
            return "chevron.left"
        case .right:
            return "chevron.right"
        case .down:
            return "chevron.down"
        }
    }

    var escapeSequence: String {
        switch self {
        case .up:
            return "\u{1B}[A"
        case .left:
            return "\u{1B}[D"
        case .right:
            return "\u{1B}[C"
        case .down:
            return "\u{1B}[B"
        }
    }

    func buttonOffset(distance: CGFloat) -> CGSize {
        switch self {
        case .up:
            return CGSize(width: 0, height: -distance)
        case .left:
            return CGSize(width: -distance, height: 0)
        case .right:
            return CGSize(width: distance, height: 0)
        case .down:
            return CGSize(width: 0, height: distance)
        }
    }
}
