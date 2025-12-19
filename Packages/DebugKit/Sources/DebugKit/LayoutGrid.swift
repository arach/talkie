//
//  LayoutGrid.swift
//  DebugKit
//
//  Visual grid overlay for debugging layouts and spacing
//

import SwiftUI

// MARK: - Layout Grid Overlay

/// Overlay that shows layout zones (header, content, footer) and spacing grid
public struct LayoutGridOverlay: View {
    public let zones: [LayoutZone]
    public let showGrid: Bool
    public let gridSpacing: CGFloat
    public let opacity: Double

    public init(
        zones: [LayoutZone] = [],
        showGrid: Bool = true,
        gridSpacing: CGFloat = 8,
        opacity: Double = 0.3
    ) {
        self.zones = zones
        self.showGrid = showGrid
        self.gridSpacing = gridSpacing
        self.opacity = opacity
    }

    public var body: some View {
        ZStack {
            // Background grid
            if showGrid {
                GridPattern(spacing: gridSpacing)
                    .stroke(Color.cyan.opacity(opacity * 0.5), lineWidth: 0.5)
            }

            // Layout zones
            GeometryReader { geometry in
                ForEach(zones) { zone in
                    ZoneOverlay(
                        zone: zone,
                        parentSize: geometry.size,
                        opacity: opacity
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Layout Zone

public struct LayoutZone: Identifiable {
    public let id = UUID()
    public let label: String
    public let frame: LayoutFrame
    public let color: Color

    public init(label: String, frame: LayoutFrame, color: Color = .blue) {
        self.label = label
        self.frame = frame
        self.color = color
    }

    // Common zones
    public static func header(height: CGFloat) -> LayoutZone {
        LayoutZone(
            label: "HEADER",
            frame: .top(height: height),
            color: .blue
        )
    }

    public static func content(topOffset: CGFloat, bottomOffset: CGFloat) -> LayoutZone {
        LayoutZone(
            label: "CONTENT",
            frame: .middle(topOffset: topOffset, bottomOffset: bottomOffset),
            color: .green
        )
    }

    public static func footer(height: CGFloat) -> LayoutZone {
        LayoutZone(
            label: "FOOTER",
            frame: .bottom(height: height),
            color: .orange
        )
    }
}

// MARK: - Layout Frame

public enum LayoutFrame {
    case top(height: CGFloat)
    case bottom(height: CGFloat)
    case middle(topOffset: CGFloat, bottomOffset: CGFloat)
    case custom(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)

    func rect(in parentSize: CGSize) -> CGRect {
        switch self {
        case .top(let height):
            return CGRect(x: 0, y: 0, width: parentSize.width, height: height)
        case .bottom(let height):
            return CGRect(x: 0, y: parentSize.height - height, width: parentSize.width, height: height)
        case .middle(let topOffset, let bottomOffset):
            return CGRect(
                x: 0,
                y: topOffset,
                width: parentSize.width,
                height: parentSize.height - topOffset - bottomOffset
            )
        case .custom(let x, let y, let width, let height):
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }
}

// MARK: - Zone Overlay

private struct ZoneOverlay: View {
    let zone: LayoutZone
    let parentSize: CGSize
    let opacity: Double

    private var rect: CGRect {
        zone.frame.rect(in: parentSize)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Zone outline
            Rectangle()
                .strokeBorder(zone.color.opacity(opacity), lineWidth: 2)
                .frame(width: rect.width, height: rect.height)

            // Zone label
            Text(zone.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(zone.color.opacity(opacity * 2))
                )
                .padding(4)
        }
        .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Grid Pattern

private struct GridPattern: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Vertical lines
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += spacing
        }

        // Horizontal lines
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += spacing
        }

        return path
    }
}

// MARK: - View Extension

public extension View {
    /// Add layout grid overlay for debugging
    func layoutGrid(
        zones: [LayoutZone] = [],
        showGrid: Bool = true,
        gridSpacing: CGFloat = 8,
        opacity: Double = 0.3
    ) -> some View {
        overlay {
            LayoutGridOverlay(
                zones: zones,
                showGrid: showGrid,
                gridSpacing: gridSpacing,
                opacity: opacity
            )
        }
    }
}
