//
//  AxisRulers.swift
//  Talkie macOS
//
//  Axis rulers with tick marks along X and Y edges
//  Like design tools (Figma, Sketch) - shows position markers
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Axis rulers overlay - shows tick marks along top and left edges
struct AxisRulersOverlay: View {
    let tickSpacing: Int

    init(tickSpacing: Int = 50) {
        self.tickSpacing = tickSpacing
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .topLeading) {
                // Horizontal ruler (top edge)
                horizontalRuler(width: width)

                // Vertical ruler (left edge)
                verticalRuler(height: height)

                // Origin marker (0,0)
                originMarker()
            }
        }
    }

    // MARK: - Horizontal Ruler (X-axis)

    @ViewBuilder
    private func horizontalRuler(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Background bar
            Rectangle()
                .fill(Color.black.opacity(0.85))
                .frame(height: 20)

            // Tick marks and labels
            ForEach(tickPositions(for: width), id: \.self) { position in
                let isMajor = position % (tickSpacing * 2) == 0

                VStack(spacing: 0) {
                    // Tick mark
                    Rectangle()
                        .fill(isMajor ? Color.cyan : Color.white.opacity(0.4))
                        .frame(width: 1, height: isMajor ? 12 : 6)

                    // Label (only for major ticks)
                    if isMajor && position > 0 {
                        Text("\(position)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyan)
                            .offset(y: -2)
                    }
                }
                .offset(x: CGFloat(position))
            }
        }
    }

    // MARK: - Vertical Ruler (Y-axis)

    @ViewBuilder
    private func verticalRuler(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Background bar
            Rectangle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 20)

            // Tick marks and labels
            ForEach(tickPositions(for: height), id: \.self) { position in
                let isMajor = position % (tickSpacing * 2) == 0

                HStack(spacing: 0) {
                    // Tick mark
                    Rectangle()
                        .fill(isMajor ? Color.cyan : Color.white.opacity(0.4))
                        .frame(width: isMajor ? 12 : 6, height: 1)

                    // Label (only for major ticks)
                    if isMajor && position > 0 {
                        Text("\(position)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyan)
                            .rotationEffect(.degrees(-90))
                            .fixedSize()
                            .offset(x: 8)
                    }
                }
                .offset(y: CGFloat(position))
            }
        }
    }

    // MARK: - Origin Marker

    @ViewBuilder
    private func originMarker() -> some View {
        Rectangle()
            .fill(Color.cyan)
            .frame(width: 20, height: 20)
            .overlay(
                Text("0")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
            )
    }

    // MARK: - Helpers

    private func tickPositions(for dimension: CGFloat) -> [Int] {
        let count = Int(dimension) / tickSpacing + 1
        return (0..<count).map { $0 * tickSpacing }
    }
}

#Preview("Axis Rulers") {
    ZStack {
        Color.gray.opacity(0.2)

        Text("Content Area")
            .foregroundColor(.white)

        AxisRulersOverlay(tickSpacing: 50)
            .allowsHitTesting(false)
    }
    .frame(width: 600, height: 400)
}

#endif
