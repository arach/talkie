//
//  EdgeGuidesOverlay.swift
//  Talkie macOS
//
//  Edge guides overlay - Shows window margins and safe areas
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Displays edge guides showing window margins and safe areas
struct EdgeGuidesOverlay: View {
    private let marginSize: CGFloat = 20
    private let safeAreaSize: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Safe area boundaries (outer)
                Rectangle()
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: [4, 3]
                        )
                    )
                    .foregroundColor(.orange.opacity(0.5))
                    .padding(safeAreaSize)

                // Margin boundaries (inner)
                Rectangle()
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: [6, 4]
                        )
                    )
                    .foregroundColor(.green.opacity(0.5))
                    .padding(marginSize)

                // Corner labels
                edgeLabel(
                    text: "Safe Area",
                    color: .orange,
                    position: CGPoint(x: safeAreaSize + 8, y: safeAreaSize - 16)
                )

                edgeLabel(
                    text: "Margin",
                    color: .green,
                    position: CGPoint(x: marginSize + 8, y: marginSize - 16)
                )

                // Measurement indicators
                VStack {
                    measurementLine(
                        start: CGPoint(x: 0, y: safeAreaSize / 2),
                        end: CGPoint(x: safeAreaSize, y: safeAreaSize / 2),
                        label: "\(Int(safeAreaSize))pt",
                        color: .orange
                    )

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func edgeLabel(text: String, color: Color, position: CGPoint) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
            .position(position)
    }

    @ViewBuilder
    private func measurementLine(start: CGPoint, end: CGPoint, label: String, color: Color) -> some View {
        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(color.opacity(0.6), lineWidth: 1)

            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.8))
                )
                .position(
                    x: (start.x + end.x) / 2,
                    y: start.y
                )
        }
    }
}

#Preview("Edge Guides") {
    ZStack {
        Color.gray.opacity(0.1)

        EdgeGuidesOverlay()
    }
    .frame(width: 800, height: 600)
}

#endif
