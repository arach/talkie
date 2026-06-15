//
//  RulerTool.swift
//  Talkie macOS
//
//  Ruler tool for measuring pixel distances between points
//  Click and drag to measure - shows distance overlay while dragging
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

struct MeasureTool: View {
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isDragging = false
    @State private var isShiftHeld = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Subtle tint to show measure mode is active
                Color.cyan.opacity(0.03)

                // Transparent overlay to capture gestures
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if startPoint == nil {
                                    startPoint = value.startLocation
                                }

                                // Apply Shift constraint for straight lines
                                var endPoint = value.location
                                if isShiftHeld, let start = startPoint {
                                    let dx = abs(endPoint.x - start.x)
                                    let dy = abs(endPoint.y - start.y)
                                    // Snap to horizontal or vertical based on dominant direction
                                    if dx > dy {
                                        endPoint.y = start.y  // Horizontal line
                                    } else {
                                        endPoint.x = start.x  // Vertical line
                                    }
                                }

                                currentPoint = endPoint
                                isDragging = true
                            }
                            .onEnded { _ in
                                isDragging = false
                                // Keep the measurement visible briefly, then auto-deactivate
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        startPoint = nil
                                        currentPoint = nil
                                    }
                                    // Deactivate tool so clicks pass through again
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        DesignModeManager.shared.activeTool = nil
                                    }
                                }
                            }
                    )

                // Ruler visualization
                if let start = startPoint, let end = currentPoint {
                    rulerOverlay(from: start, to: end, in: geometry.size)
                }

                // Instruction hint (when not dragging)
                if startPoint == nil {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("📏 Click and drag to measure")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Hold ⇧ for straight lines • ESC to exit")
                                    .font(.system(size: 9))
                                    .opacity(0.8)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.cyan.opacity(0.9))
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                            )
                            .padding(.top, 60)
                            .padding(.trailing, 20)
                        }
                        Spacer()
                    }
                }
            }
        }
        .allowsHitTesting(true)
        .onAppear {
            TalkieConsole.info("🎨 MeasureTool: Active - drag to measure, Shift for straight, ESC to exit")
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    // MARK: - Keyboard Monitoring

    @State private var keyMonitor: Any?

    private func setupKeyboardMonitor() {
        // Defensive: remove existing monitor before creating new one
        // Prevents leaking monitors if view is recreated rapidly
        removeKeyboardMonitor()

        // Monitor for Shift key and Escape
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .flagsChanged {
                // Track Shift key state
                isShiftHeld = event.modifierFlags.contains(.shift)
            } else if event.type == .keyDown {
                // ESC to exit tool
                if event.keyCode == 53 {  // Escape key
                    DesignModeManager.shared.activeTool = nil
                    return nil  // Consume event
                }
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    @ViewBuilder
    private func rulerOverlay(from start: CGPoint, to end: CGPoint, in size: CGSize) -> some View {
        let distance = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))
        let horizontalDist = abs(end.x - start.x)
        let verticalDist = abs(end.y - start.y)
        let midPoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

        ZStack {
            // Main line
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 3]))

            // Start point
            Circle()
                .fill(Color.cyan)
                .frame(width: 8, height: 8)
                .position(start)

            // End point
            Circle()
                .fill(Color.cyan)
                .frame(width: 8, height: 8)
                .position(end)

            // Distance label
            Text("\(Int(distance))px")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cyan)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                )
                .position(x: midPoint.x, y: midPoint.y - 20)

            // Horizontal/Vertical measurements (if significant)
            if horizontalDist > 20 || verticalDist > 20 {
                VStack(alignment: .leading, spacing: 2) {
                    if horizontalDist > 20 {
                        Text("→ \(Int(horizontalDist))px")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    if verticalDist > 20 {
                        Text("↓ \(Int(verticalDist))px")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.75))
                )
                .position(x: midPoint.x, y: midPoint.y + 20)
            }
        }
    }
}

// Backwards compatibility
typealias RulerTool = MeasureTool

#Preview("Measure Tool") {
    MeasureTool()
        .frame(width: 600, height: 400)
        .background(Color.gray.opacity(0.1))
        .onAppear {
            DesignModeManager.shared.isEnabled = true
        }
}

#endif
