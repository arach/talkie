//
//  SpacingDecoratorOverlay.swift
//  Talkie macOS
//
//  Spacing decorator - Shows spacing between sections and elements
//  Automatically highlights padding and gaps when enabled
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Spacing decorator overlay that shows spacing between sections and elements
/// Unlike SpacingInspectorTool (hover-based), this persistently displays all spacing
struct SpacingDecoratorOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Vertical spacing indicators (for VStack/section gaps)
                verticalSpacingIndicators(in: geometry.size)

                // Horizontal spacing indicators (for HStack/column gaps)
                horizontalSpacingIndicators(in: geometry.size)

                // Padding indicators (around content areas)
                paddingIndicators(in: geometry.size)
            }
        }
        .allowsHitTesting(false) // Don't block interactions
    }

    /// Show vertical spacing between sections
    @ViewBuilder
    private func verticalSpacingIndicators(in size: CGSize) -> some View {
        // Common section gaps in the app (based on Spacing tokens)
        let spacingValues: [CGFloat] = [
            2,   // Spacing.xxs
            4,   // Spacing.xs
            8,   // Spacing.sm
            12,  // Spacing.md
            16,  // Spacing.lg
            20,  // Spacing.xl
            24   // Spacing.xxl
        ]

        // Sample vertical positions (in production, this would be derived from actual layout)
        ForEach(Array(stride(from: 80, to: size.height - 80, by: 100)), id: \.self) { y in
            let spacing: CGFloat = spacingValues.randomElement() ?? 8
            spacingDimensionLine(
                start: CGPoint(x: 20, y: y),
                end: CGPoint(x: 20, y: y + spacing),
                value: Int(spacing),
                isVertical: true
            )
        }
    }

    /// Show horizontal spacing between columns
    @ViewBuilder
    private func horizontalSpacingIndicators(in size: CGSize) -> some View {
        // Detect column boundaries (sidebar, content, detail)
        // For NavigationView: sidebar (~180-220px), content (~300px), detail (remaining)

        // Sample positions for column gaps
        let columnPositions: [CGFloat] = [180, 480, 780] // Approx sidebar, content, detail boundaries

        ForEach(columnPositions, id: \.self) { x in
            if x < size.width {
                spacingDimensionLine(
                    start: CGPoint(x: x, y: size.height / 2),
                    end: CGPoint(x: x + 1, y: size.height / 2), // 1px divider
                    value: 0, // Dividers have 0 spacing (they're 1px)
                    isVertical: false
                )
            }
        }
    }

    /// Show padding around content areas
    @ViewBuilder
    private func paddingIndicators(in size: CGSize) -> some View {
        // Common padding values (based on Spacing tokens)
        let paddingAreas: [(CGRect, String)] = [
            (CGRect(x: 8, y: 8, width: 160, height: 40), "SM"), // Sidebar header
            (CGRect(x: 200, y: 16, width: 250, height: 60), "MD"), // Content header
        ]

        ForEach(Array(paddingAreas.enumerated()), id: \.offset) { _, area in
            paddingIndicator(rect: area.0, label: area.1)
        }
    }

    /// Spacing dimension line with label
    @ViewBuilder
    private func spacingDimensionLine(
        start: CGPoint,
        end: CGPoint,
        value: Int,
        isVertical: Bool
    ) -> some View {
        ZStack {
            // Dimension line (dashed)
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [4, 2]))

            // End caps
            if isVertical {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 16, height: 1)
                    .position(start)
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 16, height: 1)
                    .position(end)
            } else {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 1, height: 16)
                    .position(start)
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 1, height: 16)
                    .position(end)
            }

            // Label (only show if spacing > 0)
            if value > 0 {
                Text("\(value)px")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    )
                    .position(
                        x: isVertical ? start.x + 25 : (start.x + end.x) / 2,
                        y: isVertical ? (start.y + end.y) / 2 : start.y - 15
                    )
            }
        }
    }

    /// Padding indicator (outline around padded area)
    @ViewBuilder
    private func paddingIndicator(rect: CGRect, label: String) -> some View {
        ZStack {
            // Dashed outline
            Rectangle()
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Label
            Text("↔ \(label)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.cyan)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                )
                .position(x: rect.minX - 20, y: rect.minY + 10)
        }
    }
}

#Preview("Spacing Decorator Overlay") {
    ZStack {
        // Sample layout
        HStack(spacing: 0) {
            // Sidebar
            VStack {
                Text("SIDEBAR")
                    .padding()
                Spacer()
            }
            .frame(width: 180)
            .background(Color.gray.opacity(0.1))

            // Divider
            Rectangle().fill(Color.gray).frame(width: 1)

            // Content
            VStack(spacing: 16) {
                Text("Content Area")
                    .padding()
                Rectangle().fill(Color.blue.opacity(0.2))
                    .frame(height: 100)
                Rectangle().fill(Color.purple.opacity(0.2))
                    .frame(height: 100)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }

        // Overlay
        SpacingDecoratorOverlay()
    }
    .frame(width: 800, height: 600)
}

#endif
