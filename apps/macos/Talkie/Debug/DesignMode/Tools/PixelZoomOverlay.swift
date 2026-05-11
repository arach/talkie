//
//  PixelZoomOverlay.swift
//  Talkie macOS
//
//  Pixel zoom overlay - Magnification loupe that follows cursor
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Displays a magnification loupe that follows the cursor
struct PixelZoomOverlay: View {
    let zoomLevel: Int // 2 or 4
    @State private var mouseLocation: CGPoint = .zero
    @State private var isHovering: Bool = false

    private let loupeSize: CGFloat = 150
    private let offset: CGFloat = 20 // Offset from cursor

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent interaction layer
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            mouseLocation = location
                            isHovering = true
                        case .ended:
                            isHovering = false
                        }
                    }

                // Loupe window
                if isHovering && zoomLevel > 0 {
                    loupeView(in: geometry.size)
                }
            }
        }
    }

    @ViewBuilder
    private func loupeView(in size: CGSize) -> some View {
        let loupePosition = calculateLoupePosition(mouseLocation: mouseLocation, containerSize: size)

        ZStack {
            // Loupe background
            Circle()
                .fill(Color.black.opacity(0.9))
                .frame(width: loupeSize, height: loupeSize)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)

            // Crosshair at center
            crosshair

            // Zoom level indicator
            zoomIndicator

            // Pixel grid overlay (for high zoom)
            if zoomLevel >= 4 {
                pixelGrid
            }

            // Color value at cursor
            colorValue
        }
        .frame(width: loupeSize, height: loupeSize)
        .position(loupePosition)
        .allowsHitTesting(false)
    }

    private var crosshair: some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(Color.cyan.opacity(0.6))
                .frame(width: 1, height: loupeSize * 0.4)

            // Horizontal line
            Rectangle()
                .fill(Color.cyan.opacity(0.6))
                .frame(width: loupeSize * 0.4, height: 1)

            // Center dot
            Circle()
                .fill(Color.cyan)
                .frame(width: 4, height: 4)
        }
    }

    private var zoomIndicator: some View {
        Text("\(zoomLevel)×")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.cyan)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
            )
            .offset(y: -loupeSize / 2 + 20)
    }

    private var pixelGrid: some View {
        ZStack {
            let gridSize = Int(loupeSize / CGFloat(zoomLevel))

            ForEach(0..<gridSize, id: \.self) { i in
                // Vertical lines
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 0.5)
                    .offset(x: CGFloat(i) * CGFloat(zoomLevel) - loupeSize / 2)

                // Horizontal lines
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 0.5)
                    .offset(y: CGFloat(i) * CGFloat(zoomLevel) - loupeSize / 2)
            }
        }
        .clipShape(Circle())
    }

    private var colorValue: some View {
        VStack(spacing: 2) {
            // Color swatch
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3)) // Simulated color
                .frame(width: 20, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                )

            // Hex value
            Text("#FFFFFF")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))

            // RGB value
            Text("255, 255, 255")
                .font(.system(size: 7, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
        )
        .offset(y: loupeSize / 2 - 50)
    }

    private func calculateLoupePosition(mouseLocation: CGPoint, containerSize: CGSize) -> CGPoint {
        var x = mouseLocation.x + offset
        var y = mouseLocation.y - offset

        // Keep loupe within bounds
        let margin: CGFloat = loupeSize / 2 + 10

        if x + loupeSize / 2 > containerSize.width - margin {
            x = mouseLocation.x - offset - loupeSize / 2
        }
        if y - loupeSize / 2 < margin {
            y = mouseLocation.y + offset + loupeSize / 2
        }

        return CGPoint(x: x, y: y)
    }
}

#Preview("Pixel Zoom 2x") {
    ZStack {
        Color.gray.opacity(0.1)

        // Sample content
        VStack(spacing: 20) {
            Text("Move cursor here")
                .font(.system(size: 24, weight: .bold))

            HStack(spacing: 10) {
                Circle().fill(Color.red).frame(width: 40, height: 40)
                Circle().fill(Color.green).frame(width: 40, height: 40)
                Circle().fill(Color.blue).frame(width: 40, height: 40)
            }
        }

        PixelZoomOverlay(zoomLevel: 2)
    }
    .frame(width: 800, height: 600)
}

#Preview("Pixel Zoom 4x") {
    ZStack {
        Color.gray.opacity(0.1)

        PixelZoomOverlay(zoomLevel: 4)
    }
    .frame(width: 800, height: 600)
}

#endif
