//
//  ElementBoundsOverlay.swift
//  Talkie macOS
//
//  Element bounds overlay - Shows bounding boxes with dimensions on hover
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Displays bounding boxes and dimensions for UI elements on hover
struct ElementBoundsOverlay: View {
    @State private var mouseLocation: CGPoint = .zero
    @State private var hoveredBounds: CGRect?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent interaction layer for mouse tracking
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            mouseLocation = location
                            // Simulate detecting element bounds
                            // In a real implementation, this would raycast to find actual views
                            hoveredBounds = simulateElementDetection(at: location, in: geometry.size)
                        case .ended:
                            hoveredBounds = nil
                        }
                    }

                // Display bounds if hovering
                if let bounds = hoveredBounds {
                    elementBoundsDisplay(bounds: bounds, in: geometry.size)
                }
            }
        }
    }

    @ViewBuilder
    private func elementBoundsDisplay(bounds: CGRect, in size: CGSize) -> some View {
        ZStack {
            // Bounding box
            Rectangle()
                .strokeBorder(Color.purple.opacity(0.8), lineWidth: 1.5)
                .background(Color.purple.opacity(0.1))
                .frame(width: bounds.width, height: bounds.height)
                .position(x: bounds.midX, y: bounds.midY)

            // Corner indicators
            ForEach(cornerPoints(for: bounds), id: \.x) { point in
                cornerIndicator
                    .position(point)
            }

            // Dimension label
            dimensionLabel(
                width: bounds.width,
                height: bounds.height,
                position: CGPoint(
                    x: bounds.midX,
                    y: bounds.minY - 16
                )
            )

            // Position label
            positionLabel(
                x: bounds.minX,
                y: bounds.minY,
                position: CGPoint(
                    x: bounds.minX,
                    y: bounds.maxY + 16
                )
            )
        }
        .allowsHitTesting(false)
    }

    private var cornerIndicator: some View {
        ZStack {
            Circle()
                .fill(Color.purple)
                .frame(width: 6, height: 6)

            Circle()
                .fill(Color.white)
                .frame(width: 2, height: 2)
        }
    }

    @ViewBuilder
    private func dimensionLabel(width: CGFloat, height: CGFloat, position: CGPoint) -> some View {
        Text("\(Int(width)) × \(Int(height))")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.purple.opacity(0.5), lineWidth: 1)
                    )
            )
            .position(position)
    }

    @ViewBuilder
    private func positionLabel(x: CGFloat, y: CGFloat, position: CGPoint) -> some View {
        Text("x: \(Int(x)), y: \(Int(y))")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.purple.opacity(0.8))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
            .position(position)
    }

    private func cornerPoints(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), // Top-left
            CGPoint(x: rect.maxX, y: rect.minY), // Top-right
            CGPoint(x: rect.minX, y: rect.maxY), // Bottom-left
            CGPoint(x: rect.maxX, y: rect.maxY)  // Bottom-right
        ]
    }

    private func simulateElementDetection(at location: CGPoint, in size: CGSize) -> CGRect? {
        // This is a simplified simulation - in production, you'd use hit testing
        // to find actual view boundaries

        // Create a simulated element around the mouse
        let elementWidth: CGFloat = 120
        let elementHeight: CGFloat = 40

        return CGRect(
            x: location.x - elementWidth / 2,
            y: location.y - elementHeight / 2,
            width: elementWidth,
            height: elementHeight
        )
    }
}

#Preview("Element Bounds") {
    ZStack {
        Color.gray.opacity(0.1)

        // Sample elements to hover over
        VStack(spacing: 20) {
            Text("Hover over me")
                .padding()
                .background(Color.blue.opacity(0.2))

            Button("Button Element") {}
                .buttonStyle(.borderedProminent)
        }

        ElementBoundsOverlay()
    }
    .frame(width: 800, height: 600)
}

#endif
