//
//  SyntheticCursor.swift
//  DemoKit
//
//  A synthetic cursor that renders in-app, controlled by scripts.
//  No OS permissions needed - lives entirely in the app's view layer.
//

import SwiftUI

// MARK: - Cursor State

@Observable
public class DemoCursor {
    public var position: CGPoint = .zero
    public var isVisible: Bool = false
    public var isClicking: Bool = false
    public var scale: CGFloat = 1.0

    // Click ripple state
    public var rippleScale: CGFloat = 0.5
    public var rippleOpacity: CGFloat = 0.0

    public init() {}

    /// Move cursor to position with animation
    @MainActor
    public func move(to point: CGPoint, duration: Double = 0.3) async {
        withAnimation(.easeInOut(duration: duration)) {
            position = point
        }
        try? await Task.sleep(for: .seconds(duration))
    }

    /// Animate a click with water drop ripple effect
    @MainActor
    public func click() async {
        // Press down
        withAnimation(.easeOut(duration: 0.08)) {
            isClicking = true
            scale = 0.85
        }

        // Start ripple
        rippleScale = 0.3
        rippleOpacity = 0.6

        withAnimation(.easeOut(duration: 0.4)) {
            rippleScale = 1.8
            rippleOpacity = 0.0
        }

        try? await Task.sleep(for: .seconds(0.08))

        // Release
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            isClicking = false
            scale = 1.0
        }

        try? await Task.sleep(for: .seconds(0.3))
    }

    /// Show cursor with fade in
    @MainActor
    public func show() {
        withAnimation(.easeOut(duration: 0.25)) {
            isVisible = true
        }
    }

    /// Hide cursor with fade out
    @MainActor
    public func hide() {
        withAnimation(.easeIn(duration: 0.2)) {
            isVisible = false
        }
    }
}

// MARK: - Cursor View

public struct SyntheticCursorView: View {
    let cursor: DemoCursor

    public init(cursor: DemoCursor) {
        self.cursor = cursor
    }

    public var body: some View {
        ZStack {
            // Water drop ripple effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(0.4),
                            Color.accentColor.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 20
                    )
                )
                .frame(width: 40, height: 40)
                .scaleEffect(cursor.rippleScale)
                .opacity(cursor.rippleOpacity)

            // Outer ripple ring
            Circle()
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                .frame(width: 40, height: 40)
                .scaleEffect(cursor.rippleScale)
                .opacity(cursor.rippleOpacity)

            // Cursor with shadow for depth
            ZStack {
                // Drop shadow (offset)
                MacOSCursorShape()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 17, height: 22)
                    .offset(x: 1.5, y: 1.5)
                    .blur(radius: 1)

                // Main cursor body
                MacOSCursorShape()
                    .fill(Color.white)
                    .frame(width: 17, height: 22)

                // Black outline
                MacOSCursorShape()
                    .stroke(Color.black, lineWidth: 1.2)
                    .frame(width: 17, height: 22)
            }
            .scaleEffect(cursor.scale)
            .offset(x: 5, y: 8) // Offset so tip is at position
        }
        .position(cursor.position)
        .opacity(cursor.isVisible ? 1 : 0)
        .allowsHitTesting(false)
    }
}

// MARK: - macOS Cursor Shape

/// Pixel-accurate macOS arrow cursor shape
struct MacOSCursorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Refined macOS-style pointer
        // Starts at top-left (the point), goes down and around
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h * 0.85))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.65))
        path.addLine(to: CGPoint(x: w * 0.38, y: h))
        path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.92))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.58))
        path.closeSubpath()

        return path
    }
}

// MARK: - Overlay Modifier

public extension View {
    /// Add synthetic cursor overlay to a view (only renders if demo mode enabled)
    /// Also establishes the coordinate space that anchors register into
    func syntheticCursor(_ cursor: DemoCursor) -> some View {
        self
            .coordinateSpace(name: "demoCursorSpace")
            .overlay {
                if DemoMode.isEnabled {
                    SyntheticCursorView(cursor: cursor)
                }
            }
    }
}
