//
//  DemoScript.swift
//  DemoKit
//
//  Script runner for demo automation.
//  Interprets declarative scripts and drives the synthetic cursor.
//

import SwiftUI

// MARK: - Script Actions

public enum DemoAction: Sendable {
    case moveTo(anchor: String, duration: Double = 0.3)
    case moveToPoint(x: CGFloat, y: CGFloat, duration: Double = 0.3)
    case click
    case doubleClick
    case wait(seconds: Double)
    case show
    case hide

    // For hybrid mode - emit coordinates for real OS interaction
    case emitPosition(callback: @Sendable (CGPoint) -> Void)
}

// MARK: - Script Runner

@MainActor
public class DemoScriptRunner {
    private let cursor: DemoCursor
    private let anchors: DemoAnchorRegistry

    /// Callback for hybrid mode - receives cursor position for OS-level interaction
    public var onPositionEmit: ((CGPoint) -> Void)?

    public init(cursor: DemoCursor, anchors: DemoAnchorRegistry = .shared) {
        self.cursor = cursor
        self.anchors = anchors
    }

    /// Run a sequence of demo actions
    public func run(_ actions: [DemoAction]) async {
        cursor.show()

        for action in actions {
            await execute(action)
        }
    }

    /// Execute a single action
    private func execute(_ action: DemoAction) async {
        switch action {
        case .moveTo(let anchor, let duration):
            if let point = anchors.centerOf(anchor) {
                await cursor.move(to: point, duration: duration)
            } else {
                DemoKitConsole.info("⚠️ DemoKit: Anchor '\(anchor)' not found")
            }

        case .moveToPoint(let x, let y, let duration):
            await cursor.move(to: CGPoint(x: x, y: y), duration: duration)

        case .click:
            await cursor.click()
            // In hybrid mode, emit position for real click
            if let callback = onPositionEmit {
                callback(cursor.position)
            }

        case .doubleClick:
            await cursor.click()
            try? await Task.sleep(for: .seconds(0.1))
            await cursor.click()

        case .wait(let seconds):
            try? await Task.sleep(for: .seconds(seconds))

        case .show:
            cursor.show()

        case .hide:
            cursor.hide()

        case .emitPosition(let callback):
            callback(cursor.position)
        }
    }
}

// MARK: - Convenience Script Builder

public struct DemoScript {
    public var actions: [DemoAction] = []

    public init() {}

    public init(@DemoScriptBuilder _ builder: () -> [DemoAction]) {
        self.actions = builder()
    }

    public mutating func moveTo(_ anchor: String, duration: Double = 0.3) {
        actions.append(.moveTo(anchor: anchor, duration: duration))
    }

    public mutating func move(x: CGFloat, y: CGFloat, duration: Double = 0.3) {
        actions.append(.moveToPoint(x: x, y: y, duration: duration))
    }

    public mutating func click() {
        actions.append(.click)
    }

    public mutating func wait(_ seconds: Double) {
        actions.append(.wait(seconds: seconds))
    }

    public mutating func show() {
        actions.append(.show)
    }

    public mutating func hide() {
        actions.append(.hide)
    }
}

// MARK: - Result Builder

@resultBuilder
public struct DemoScriptBuilder {
    public static func buildBlock(_ components: DemoAction...) -> [DemoAction] {
        components
    }

    public static func buildArray(_ components: [[DemoAction]]) -> [DemoAction] {
        components.flatMap { $0 }
    }
}
