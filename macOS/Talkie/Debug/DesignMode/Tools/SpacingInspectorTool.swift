//
//  SpacingInspectorTool.swift
//  Talkie macOS
//
//  Spacing inspector tool for measuring gaps between UI elements
//  Hover between elements to see spacing values with dimension lines
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

struct SpacingInspectorTool: View {
    @State private var hoverPosition: CGPoint?
    @State private var detectedSpacing: SpacingMeasurement?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent overlay to track hover
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                hoverPosition = value.location
                                detectSpacing(at: value.location, in: geometry.size)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverPosition = location
                            detectSpacing(at: location, in: geometry.size)
                        case .ended:
                            hoverPosition = nil
                            detectedSpacing = nil
                        }
                    }

                // Spacing visualization
                if let spacing = detectedSpacing {
                    spacingOverlay(spacing: spacing)
                }
            }
        }
        .allowsHitTesting(true)
    }

    private func detectSpacing(at location: CGPoint, in size: CGSize) {
        // This is a simplified implementation that detects spacing in a grid pattern
        // In a real implementation, this would analyze the actual view hierarchy

        // For demo purposes, we'll create artificial spacing measurements
        // based on a virtual 8pt grid system

        let gridSize: CGFloat = 8
        let nearestGridX = round(location.x / gridSize) * gridSize
        let nearestGridY = round(location.y / gridSize) * gridSize

        let distanceToGridX = abs(location.x - nearestGridX)
        let distanceToGridY = abs(location.y - nearestGridY)

        // If we're close to a grid line, show spacing measurement
        if distanceToGridX < 20 || distanceToGridY < 20 {
            if distanceToGridY < distanceToGridX {
                // Show vertical spacing
                let spacing = Int(gridSize * 2) // Simulate 16px spacing
                detectedSpacing = SpacingMeasurement(
                    value: spacing,
                    start: CGPoint(x: location.x, y: nearestGridY - CGFloat(spacing)),
                    end: CGPoint(x: location.x, y: nearestGridY),
                    isVertical: true
                )
            } else {
                // Show horizontal spacing
                let spacing = Int(gridSize * 3) // Simulate 24px spacing
                detectedSpacing = SpacingMeasurement(
                    value: spacing,
                    start: CGPoint(x: nearestGridX - CGFloat(spacing), y: location.y),
                    end: CGPoint(x: nearestGridX, y: location.y),
                    isVertical: false
                )
            }
        } else {
            detectedSpacing = nil
        }
    }

    @ViewBuilder
    private func spacingOverlay(spacing: SpacingMeasurement) -> some View {
        ZStack {
            if spacing.isVertical {
                // Vertical spacing indicator
                VStack(spacing: 0) {
                    // Top cap
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: 20, height: 1)
                        .position(x: spacing.start.x, y: spacing.start.y)

                    // Dimension line
                    Path { path in
                        path.move(to: spacing.start)
                        path.addLine(to: spacing.end)
                    }
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

                    // Bottom cap
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: 20, height: 1)
                        .position(x: spacing.end.x, y: spacing.end.y)
                }

                // Label
                Text("\(spacing.value)px")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.cyan)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    )
                    .position(
                        x: spacing.start.x + 30,
                        y: (spacing.start.y + spacing.end.y) / 2
                    )
            } else {
                // Horizontal spacing indicator
                HStack(spacing: 0) {
                    // Left cap
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: 1, height: 20)
                        .position(x: spacing.start.x, y: spacing.start.y)

                    // Dimension line
                    Path { path in
                        path.move(to: spacing.start)
                        path.addLine(to: spacing.end)
                    }
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

                    // Right cap
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: 1, height: 20)
                        .position(x: spacing.end.x, y: spacing.end.y)
                }

                // Label
                Text("\(spacing.value)px")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.cyan)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    )
                    .position(
                        x: (spacing.start.x + spacing.end.x) / 2,
                        y: spacing.start.y - 20
                    )
            }
        }
    }
}

// MARK: - Spacing Measurement Model

private struct SpacingMeasurement {
    let value: Int
    let start: CGPoint
    let end: CGPoint
    let isVertical: Bool
}

#Preview("Spacing Inspector Tool") {
    ZStack {
        // Sample UI elements
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.3))
                .frame(height: 60)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.3))
                .frame(height: 60)
        }
        .padding(32)

        SpacingInspectorTool()
    }
    .frame(width: 600, height: 400)
    .background(Color.gray.opacity(0.1))
}

#endif
