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

struct RulerTool: View {
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent overlay to capture gestures
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if startPoint == nil {
                                    startPoint = value.startLocation
                                }
                                currentPoint = value.location
                                isDragging = true
                            }
                            .onEnded { _ in
                                isDragging = false
                                // Keep the measurement visible briefly, then reset
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        startPoint = nil
                                        currentPoint = nil
                                    }
                                }
                            }
                    )

                // Ruler visualization
                if let start = startPoint, let end = currentPoint {
                    rulerOverlay(from: start, to: end, in: geometry.size)
                }
            }
        }
        .allowsHitTesting(true)
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

#Preview("Ruler Tool") {
    RulerTool()
        .frame(width: 600, height: 400)
        .background(Color.gray.opacity(0.1))
}

#endif
