//
//  LayoutInspectorOverlay.swift
//  Talkie macOS
//
//  Real layout inspector using NSView hit testing
//  Shows actual element bounds, positions, and dimensions on hover
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import AppKit

#if DEBUG

/// Layout inspector that shows real view bounds using NSView hit testing
struct LayoutInspectorOverlay: View {
    @State private var inspectedFrame: NSRect?
    @State private var mousePosition: CGPoint = .zero
    @State private var viewClassName: String = ""
    @State private var windowSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Track mouse and detect views
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            mousePosition = location
                            windowSize = geometry.size
                            detectViewUnderCursor(at: location, windowSize: geometry.size)
                        case .ended:
                            inspectedFrame = nil
                            viewClassName = ""
                        }
                    }

                // Crosshair at cursor
                crosshairOverlay

                // View bounds display
                if let frame = inspectedFrame {
                    viewBoundsOverlay(frame: frame, in: geometry.size)
                }

                // Position readout (always visible)
                positionReadout(in: geometry.size)

                // Ruler guides on edges
                edgeRulers(in: geometry.size)
            }
        }
        .allowsHitTesting(true)
    }

    // MARK: - View Detection

    private func detectViewUnderCursor(at location: CGPoint, windowSize: CGSize) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView else {
            inspectedFrame = nil
            return
        }

        // Convert SwiftUI coordinates to window coordinates
        // SwiftUI origin is top-left, NSView origin is bottom-left
        let windowPoint = NSPoint(
            x: location.x,
            y: windowSize.height - location.y
        )

        // Hit test to find the view
        if let hitView = contentView.hitTest(windowPoint) {
            // Get frame in window coordinates
            let frameInWindow = hitView.convert(hitView.bounds, to: contentView)

            // Convert back to SwiftUI coordinates (flip Y)
            inspectedFrame = NSRect(
                x: frameInWindow.origin.x,
                y: windowSize.height - frameInWindow.origin.y - frameInWindow.height,
                width: frameInWindow.width,
                height: frameInWindow.height
            )

            // Get class name for display
            viewClassName = String(describing: type(of: hitView))
                .replacingOccurrences(of: "_", with: "")
                .prefix(30)
                .description
        } else {
            inspectedFrame = nil
            viewClassName = ""
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var crosshairOverlay: some View {
        // Vertical line
        Rectangle()
            .fill(Color.cyan.opacity(0.3))
            .frame(width: 1)
            .position(x: mousePosition.x, y: windowSize.height / 2)

        // Horizontal line
        Rectangle()
            .fill(Color.cyan.opacity(0.3))
            .frame(height: 1)
            .position(x: windowSize.width / 2, y: mousePosition.y)

        // Cursor dot
        Circle()
            .fill(Color.cyan)
            .frame(width: 6, height: 6)
            .position(mousePosition)
    }

    @ViewBuilder
    private func viewBoundsOverlay(frame: NSRect, in size: CGSize) -> some View {
        let cgFrame = frame

        // Bounding box
        Rectangle()
            .strokeBorder(Color.orange, lineWidth: 2)
            .background(Color.orange.opacity(0.1))
            .frame(width: cgFrame.width, height: cgFrame.height)
            .position(x: cgFrame.midX, y: cgFrame.midY)

        // Dimension label (width × height)
        Text("\(Int(cgFrame.width)) × \(Int(cgFrame.height))")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange)
                    .shadow(color: .black.opacity(0.3), radius: 3)
            )
            .position(x: cgFrame.midX, y: cgFrame.minY - 16)

        // Position label (x, y)
        Text("x:\(Int(cgFrame.minX)) y:\(Int(cgFrame.minY))")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.8))
            )
            .position(x: cgFrame.minX + 40, y: cgFrame.maxY + 12)

        // Distance to edges
        distanceIndicators(frame: cgFrame, in: size)

        // Class name
        if !viewClassName.isEmpty {
            Text(viewClassName)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .position(x: cgFrame.midX, y: cgFrame.maxY + 26)
        }
    }

    @ViewBuilder
    private func distanceIndicators(frame: CGRect, in size: CGSize) -> some View {
        // Distance to left edge
        if frame.minX > 30 {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.cyan.opacity(0.5))
                    .frame(width: frame.minX - 4, height: 1)
                Text("\(Int(frame.minX))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            .position(x: frame.minX / 2, y: frame.midY)
        }

        // Distance to top edge
        if frame.minY > 30 {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.cyan.opacity(0.5))
                    .frame(width: 1, height: frame.minY - 4)
                Text("\(Int(frame.minY))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            .position(x: frame.midX, y: frame.minY / 2)
        }

        // Distance to right edge
        let rightDist = size.width - frame.maxX
        if rightDist > 30 {
            HStack(spacing: 0) {
                Text("\(Int(rightDist))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.cyan)
                Rectangle()
                    .fill(Color.cyan.opacity(0.5))
                    .frame(width: rightDist - 4, height: 1)
            }
            .position(x: frame.maxX + rightDist / 2, y: frame.midY)
        }

        // Distance to bottom edge
        let bottomDist = size.height - frame.maxY
        if bottomDist > 30 {
            VStack(spacing: 0) {
                Text("\(Int(bottomDist))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.cyan)
                Rectangle()
                    .fill(Color.cyan.opacity(0.5))
                    .frame(width: 1, height: bottomDist - 4)
            }
            .position(x: frame.midX, y: frame.maxY + bottomDist / 2)
        }
    }

    @ViewBuilder
    private func positionReadout(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Current mouse position
            HStack(spacing: 8) {
                Text("X: \(Int(mousePosition.x))")
                Text("Y: \(Int(mousePosition.y))")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white)

            // Window size
            Text("Window: \(Int(size.width)) × \(Int(size.height))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.85))
        )
        .position(x: 80, y: size.height - 40)
    }

    @ViewBuilder
    private func edgeRulers(in size: CGSize) -> some View {
        // Top ruler
        HStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: Int(size.width), by: 50)), id: \.self) { x in
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.white.opacity(x % 100 == 0 ? 0.4 : 0.2))
                        .frame(width: 1, height: x % 100 == 0 ? 8 : 4)
                    if x % 100 == 0 && x > 0 {
                        Text("\(x)")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(width: 50)
            }
        }
        .position(x: size.width / 2, y: 10)

        // Left ruler
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: Int(size.height), by: 50)), id: \.self) { y in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.white.opacity(y % 100 == 0 ? 0.4 : 0.2))
                        .frame(width: y % 100 == 0 ? 8 : 4, height: 1)
                    if y % 100 == 0 && y > 0 {
                        Text("\(y)")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(height: 50)
            }
        }
        .position(x: 10, y: size.height / 2)
    }
}

#Preview("Layout Inspector") {
    ZStack {
        // Sample UI
        VStack(spacing: 20) {
            Text("Header")
                .font(.title)
                .padding()
                .background(Color.blue.opacity(0.2))

            HStack(spacing: 16) {
                Button("Button 1") {}
                Button("Button 2") {}
            }

            Rectangle()
                .fill(Color.purple.opacity(0.2))
                .frame(height: 100)
        }
        .padding(40)

        LayoutInspectorOverlay()
    }
    .frame(width: 800, height: 600)
    .background(Color.gray.opacity(0.1))
}

#endif
