//
//  SpacingDecoratorOverlay.swift
//  Talkie macOS
//
//  Spacing decorator - Shows main layout section widths
//  Useful for screenshots and documentation
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

/// Shows main layout section widths with visual annotations
/// Designed for screenshot documentation
struct SpacingDecoratorOverlay: View {
    // Known layout constants (from NavigationViewNative)
    private let sidebarWidth: CGFloat = 180
    private let sidebarMinWidth: CGFloat = 160
    private let contentMinWidth: CGFloat = 300

    var body: some View {
        GeometryReader { geometry in
            let windowWidth = geometry.size.width
            let windowHeight = geometry.size.height
            let contentWidth = windowWidth - sidebarWidth - 1 // -1 for divider

            ZStack {
                // === HORIZONTAL MEASUREMENTS ===

                // Sidebar width indicator (top)
                widthIndicator(
                    x: 0,
                    width: sidebarWidth,
                    y: 8,
                    label: "Sidebar",
                    sublabel: "\(Int(sidebarWidth))px",
                    color: .cyan
                )

                // Content width indicator (top)
                widthIndicator(
                    x: sidebarWidth + 1,
                    width: contentWidth,
                    y: 8,
                    label: "Content",
                    sublabel: "\(Int(contentWidth))px",
                    color: .orange
                )

                // Total window width (bottom)
                widthIndicator(
                    x: 0,
                    width: windowWidth,
                    y: windowHeight - 24,
                    label: "Window",
                    sublabel: "\(Int(windowWidth)) × \(Int(windowHeight))",
                    color: .purple
                )

                // === VERTICAL DIVIDER ===

                // Sidebar/Content divider line
                Rectangle()
                    .fill(Color.cyan.opacity(0.5))
                    .frame(width: 2)
                    .position(x: sidebarWidth, y: windowHeight / 2)

                // === MARGIN ANNOTATIONS ===

                // Content area padding indicator
                let contentPadding: CGFloat = 16  // Spacing.lg typically
                marginIndicator(
                    at: CGPoint(x: sidebarWidth + contentPadding, y: 60),
                    size: contentPadding,
                    direction: .left,
                    label: "padding"
                )

                // === PROPORTIONS ===

                // Ratio indicator
                let sidebarRatio = Int((sidebarWidth / windowWidth) * 100)
                let contentRatio = 100 - sidebarRatio

                VStack(alignment: .leading, spacing: 4) {
                    Text("LAYOUT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.cyan)
                            .frame(width: CGFloat(sidebarRatio), height: 4)
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: CGFloat(contentRatio), height: 4)
                    }
                    .frame(width: 100)

                    Text("\(sidebarRatio)% / \(contentRatio)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.85))
                )
                .position(x: windowWidth - 70, y: windowHeight - 60)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Width Indicator

    @ViewBuilder
    private func widthIndicator(
        x: CGFloat,
        width: CGFloat,
        y: CGFloat,
        label: String,
        sublabel: String,
        color: Color
    ) -> some View {
        let centerX = x + width / 2

        ZStack {
            // Horizontal line with end caps
            Path { path in
                path.move(to: CGPoint(x: x + 4, y: y))
                path.addLine(to: CGPoint(x: x + width - 4, y: y))
            }
            .stroke(color.opacity(0.6), lineWidth: 1)

            // Left cap
            Path { path in
                path.move(to: CGPoint(x: x + 4, y: y - 6))
                path.addLine(to: CGPoint(x: x + 4, y: y + 6))
            }
            .stroke(color, lineWidth: 2)

            // Right cap
            Path { path in
                path.move(to: CGPoint(x: x + width - 4, y: y - 6))
                path.addLine(to: CGPoint(x: x + width - 4, y: y + 6))
            }
            .stroke(color, lineWidth: 2)

            // Label
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                Text(sublabel)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(color.opacity(0.4), lineWidth: 1)
                    )
            )
            .position(x: centerX, y: y + 20)
        }
    }

    // MARK: - Margin Indicator

    enum MarginDirection {
        case left, right, top, bottom
    }

    @ViewBuilder
    private func marginIndicator(
        at point: CGPoint,
        size: CGFloat,
        direction: MarginDirection,
        label: String
    ) -> some View {
        let color = Color.green

        ZStack {
            // Arrow line
            switch direction {
            case .left:
                Path { path in
                    path.move(to: CGPoint(x: point.x - size, y: point.y))
                    path.addLine(to: point)
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

                // Arrow head
                Path { path in
                    path.move(to: CGPoint(x: point.x - 6, y: point.y - 4))
                    path.addLine(to: point)
                    path.addLine(to: CGPoint(x: point.x - 6, y: point.y + 4))
                }
                .stroke(color, lineWidth: 1.5)

            default:
                EmptyView()
            }

            // Label
            Text("\(Int(size))px")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                )
                .position(x: point.x - size / 2, y: point.y - 12)
        }
    }
}

#Preview("Spacing Decorator") {
    ZStack {
        // Simulated app layout
        HStack(spacing: 0) {
            // Sidebar
            VStack {
                Text("Sidebar")
                    .padding()
                Spacer()
            }
            .frame(width: 180)
            .background(Color.gray.opacity(0.15))

            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1)

            // Content
            VStack {
                Text("Content Area")
                    .padding()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.05))
        }

        SpacingDecoratorOverlay()
    }
    .frame(width: 900, height: 600)
    .background(Color(white: 0.1))
}

#endif
