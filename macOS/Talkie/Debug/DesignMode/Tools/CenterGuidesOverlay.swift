//
//  CenterGuidesOverlay.swift
//  Talkie macOS
//
//  Center guides overlay - Shows vertical and horizontal center lines
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Displays dashed center guides (vertical and horizontal) for the window
struct CenterGuidesOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2

            ZStack {
                // Vertical center line
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: 0))
                    path.addLine(to: CGPoint(x: centerX, y: geometry.size.height))
                }
                .stroke(
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: [6, 4]
                    )
                )
                .foregroundColor(.cyan.opacity(0.6))

                // Horizontal center line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: centerY))
                }
                .stroke(
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: [6, 4]
                    )
                )
                .foregroundColor(.cyan.opacity(0.6))

                // Center intersection indicator
                Circle()
                    .fill(Color.cyan.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .position(x: centerX, y: centerY)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                // Dimension labels
                Text("\(Int(geometry.size.width))×\(Int(geometry.size.height))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                    )
                    .position(x: centerX, y: centerY - 20)
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("Center Guides") {
    ZStack {
        Color.gray.opacity(0.1)

        CenterGuidesOverlay()
    }
    .frame(width: 800, height: 600)
}

#endif
